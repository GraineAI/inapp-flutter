import CryptoKit
import DeviceCheck
import Flutter
import Foundation
import Security

/**
 * `ai.graine.inapp/app` on iOS: what Dart needs to say which app this is and
 * to prove it (sdk/contract/APP-IDENTITY.md §1.2, §3.4, §3.6). Native code only
 * READS and PROVES here; every rule applied to the answers (the Team ID's
 * shape, when to prove, what to send) is in Dart, held to the contract's
 * vectors by its tests.
 *
 *   declaration      → {platform: "ios", id, accessGroup?}: the bundle id, and the access group
 *                      of a Keychain item this app owns — Dart takes the Team ID from it
 *   readDebugToken   → String?: development mode's token, kept in the Keychain beside the install
 *                      id — the same item the SDK's call engine keeps its own in, so an install has one
 *   writeDebugToken    String
 *   prove            {challenge} → {kind: "attest", keyId, attestation} · {kind: "assert", keyId, assertion}
 *                      · {error: "unsupported" | "backoff" | "failed", message?}
 *   forgetProofKey     Graine no longer knows the App Attest key: the next proof makes a new one
 *
 * Results are delivered on the main thread; the Keychain and App Attest are
 * never waited on there.
 */
final class GraineFlutterAppIdentity {
    private static let queue = DispatchQueue(label: "ai.graine.inapp.flutter.app-identity", qos: .utility)

    static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "declaration":
            queue.async {
                let answer = declaration()
                DispatchQueue.main.async { result(answer) }
            }
        case "readDebugToken":
            queue.async {
                let token = KeychainInstallIdStore(account: "debug-token").read()
                DispatchQueue.main.async { result(token) }
            }
        case "writeDebugToken":
            guard let token = call.arguments as? String else {
                result(FlutterError(code: "invalid_arguments", message: "writeDebugToken takes a string", details: nil))
                return
            }
            queue.async {
                _ = KeychainInstallIdStore(account: "debug-token").write(token)
                DispatchQueue.main.async { result(nil) }
            }
        case "prove":
            guard let challenge = (call.arguments as? [String: Any])?["challenge"] as? String, !challenge.isEmpty else {
                result(["error": "failed", "message": "prove takes {challenge}"])
                return
            }
            GraineFlutterAppAttest.prove(challenge: challenge) { answer in
                DispatchQueue.main.async { result(answer) }
            }
        case "forgetProofKey":
            GraineFlutterAppAttest.forgetKey()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - The declaration (§1.2)

    /// Read once per launch: neither changes while the app runs.
    private static var accessGroupRead = false
    private static var accessGroup: String?

    private static func declaration() -> [String: Any]? {
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return nil }
        if !accessGroupRead {
            accessGroup = probeAccessGroup()
            accessGroupRead = true
        }
        var answer: [String: Any] = ["platform": "ios", "id": id]
        if let group = accessGroup { answer["accessGroup"] = group }
        return answer
    }

    /**
     * The access group iOS gives a Keychain item this app adds — the App ID
     * prefix (the Team ID), a dot, and the bundle id. A generic password with
     * service `ai.graine.inapp.app-id-probe` and account `probe`, readable after
     * the first unlock (a ring can wake the app before anyone unlocks it); one
     * already there is read back as it is. Any Keychain error: nil — the Team
     * ID is then left out, never guessed.
     */
    private static func probeAccessGroup() -> String? {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.graine.inapp.app-id-probe",
            kSecAttrAccount as String: "probe",
        ]
        var add = item
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecValueData as String] = Data("probe".utf8)
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess || added == errSecDuplicateItem else { return nil }
        var query = item
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let attributes = found as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessGroup as String] as? String
    }
}

/**
 * App Attest (§3.4) for the Dart side's own proofs. Its key is its own — not
 * the call engine's, so two proofs never share one key's counter — and its id
 * is kept in `UserDefaults` (the plugin's suite), not the Keychain: the Secure
 * Enclave key does not survive a reinstall or a restore to another phone, and
 * its id must not outlive it.
 */
enum GraineFlutterAppAttest {
    private static let defaults = UserDefaults(suiteName: "ai.graine.inapp.flutter") ?? .standard
    private static let keyIdKey = "appAttestKeyId"

    /// No key id → a new key, attested (`attest`); a key id → an assertion (`assert`). A key iOS no longer
    /// knows (`invalidKey`) is let go and a new one attested.
    static func prove(challenge: String, _ done: @escaping ([String: Any]) -> Void) {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            done(["error": "unsupported", "message": "App Attest is not available on this device"])
            return
        }
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        guard let keyId = defaults.string(forKey: keyIdKey), !keyId.isEmpty else {
            attestNewKey(service, clientDataHash, done)
            return
        }
        service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
            if let assertion = assertion {
                done(["kind": "assert", "keyId": keyId, "assertion": assertion.base64EncodedString()])
            } else if (error as? DCError)?.code == .invalidKey {
                forgetKey()
                attestNewKey(service, clientDataHash, done)
            } else {
                done(failure(error))
            }
        }
    }

    static func forgetKey() {
        defaults.removeObject(forKey: keyIdKey)
    }

    private static func attestNewKey(
        _ service: DCAppAttestService,
        _ clientDataHash: Data,
        _ done: @escaping ([String: Any]) -> Void
    ) {
        service.generateKey { keyId, error in
            guard let keyId = keyId else {
                done(failure(error))
                return
            }
            service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
                guard let attestation = attestation else {
                    done(failure(error))
                    return
                }
                // Kept once Apple attested it; a key whose attestation never reached Graine is answered
                // `unknown_key` at its first assertion, and Dart lets it go.
                defaults.set(keyId, forKey: keyIdKey)
                done(["kind": "attest", "keyId": keyId, "attestation": attestation.base64EncodedString()])
            }
        }
    }

    /// Apple could not be reached → `backoff` (tried again later, with the outage grace); the feature missing →
    /// `unsupported`; anything else → `failed`.
    private static func failure(_ error: Error?) -> [String: Any] {
        switch (error as? DCError)?.code {
        case .serverUnavailable?:
            return ["error": "backoff", "message": "Apple could not be reached"]
        case .featureUnsupported?:
            return ["error": "unsupported", "message": "App Attest is not available on this device"]
        default:
            return ["error": "failed", "message": error.map { "\($0)" } ?? "App Attest failed"]
        }
    }
}

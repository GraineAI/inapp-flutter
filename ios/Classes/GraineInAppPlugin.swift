import Combine
import Flutter
import UIKit

/**
 * The iOS half of graine_inapp's calls: the MethodChannel `ai.graine.inapp/calls`
 * and the EventChannel `ai.graine.inapp/calls/events`, which streams
 * `{"event": name, "data": payload}`, over GraineCallsHost in the Graine iOS SDK
 * this plugin carries.
 *
 * It only marshals values: every rule is in the host, inside the SDK, where its
 * own tests cover it. Server tokens too: Dart's own token manager pushes each
 * new one (`setClientToken`), and hears `needClientToken` when one was refused. One instance per Flutter engine — the app's, and a
 * background messaging isolate's — each with its own sink while its Dart side
 * listens. Method calls arrive, and events are sent, on the main thread.
 *
 * And `ai.graine.inapp/device`: what Dart needs from the device for the
 * identity channel — the install id the SDK keeps in the Keychain (the SAME
 * id its call engine sends), the IANA zone, and the Dart side's own few bytes
 * of preferences (its users' memory choices, by fingerprint).
 *
 * And `ai.graine.inapp/app` (GraineFlutterAppIdentity.swift): which app this
 * is, and its App Attest proofs, for "Your app and your users".
 *
 * And every hosted agent's verification: what Graine made of this app and its
 * user on the engine's own requests (a call's ticket, its credential), as the
 * `verification` event — `{publishableKey, app, appReason, user, userReason,
 * traits}`, `traits` being what this plugin last handed the engine — once with
 * the current state while Dart listens, then on every change. Read through the
 * SDK's public API (GraineInApp.all, each agent's `verification`).
 */
public class GraineInAppPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: Int?
    /// Dart's events while it listens: the host's, and every agent's verification.
    private var events: FlutterEventSink?
    /// What this plugin last handed the engine as setIdentity (nil: none) — each verification event names it.
    private var traits: [String: Any]?
    /// The agents whose verification is forwarded, by publishable key.
    private var watching: [String: AnyCancellable] = [:]

    /// The install id as this process first read it: one per launch, whatever the Keychain does after.
    private static var installId: String?
    private static let prefsKey = "ai.graine.inapp.flutter.prefs"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = GraineInAppPlugin()
        let methods = FlutterMethodChannel(name: "ai.graine.inapp/calls", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: methods)
        let events = FlutterEventChannel(name: "ai.graine.inapp/calls/events", binaryMessenger: registrar.messenger())
        events.setStreamHandler(plugin)
        let device = FlutterMethodChannel(name: "ai.graine.inapp/device", binaryMessenger: registrar.messenger())
        device.setMethodCallHandler { call, result in GraineInAppPlugin.handleDevice(call, result: result) }
        let app = FlutterMethodChannel(name: "ai.graine.inapp/app", binaryMessenger: registrar.messenger())
        app.setMethodCallHandler { call, result in GraineFlutterAppIdentity.handle(call, result: result) }
        // An app delegate registers its plugins inside didFinishLaunching: the calls configure
        // themselves from the kept options now, so a VoIP push that woke the app rings before any
        // Dart runs. GraineInAppLaunch.m does the same for an engine that starts later.
        GraineCallsHost.shared.restore()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let host = GraineCallsHost.shared
        switch call.method {
        case "configure":
            do {
                try host.configure(call.arguments as? [String: Any])
                // The agents it configured (and any it added): their verification reaches Dart too.
                watchVerification()
                result(nil)
            } catch let error as GraineCallsHostError {
                result(FlutterError(code: error.code, message: error.message, details: nil))
            } catch {
                result(FlutterError(code: "invalid_options", message: error.localizedDescription, details: nil))
            }
        case "restore":
            let restored = host.restore()
            watchVerification()
            result(restored)
        case "snapshot", "getState":
            result(host.snapshot())
        case "enableVoIPPushes":
            host.enableVoIPPushes()
            result(nil)
        case "handlePush":
            result(host.handlePush(call.arguments as? [String: Any]))
        case "startCall":
            result(host.startCall(call.arguments as? [String: Any]))
        case "prepareCall":
            // startCall's arguments, for the call the app expects next: made ready before the tap, nothing dialled.
            host.prepareCall(call.arguments as? [String: Any])
            result(nil)
        case "answer":
            host.answer()
            result(nil)
        case "decline":
            host.decline()
            result(nil)
        case "end":
            host.end()
            result(nil)
        case "setMuted", "setSpeaker", "setSpeakerByDefault":
            guard let on = call.arguments as? Bool else {
                result(FlutterError(code: "invalid_arguments", message: "\(call.method) takes a bool", details: nil))
                return
            }
            switch call.method {
            case "setMuted": host.setMuted(on)
            case "setSpeaker": host.setSpeaker(on)
            // Where calls start their sound: kept by the host for the next cold start, held until configure.
            default: host.setSpeakerByDefault(on)
            }
            result(nil)
        case "setIdentity":
            // The traits as the app passed them: the SDK masks them for the agent
            // and keeps the identity raw for Graine, as its own identify does.
            // Noted first: what the engine reports from now on is about them.
            traits = call.arguments as? [String: Any]
            host.setIdentity(call.arguments as? [String: Any])
            result(nil)
        case "setIdentityToken":
            // The identity token for the user setIdentity named (APP-IDENTITY.md §1.3), for the calls this
            // engine places and answers. Sent after setIdentity, which the host applies at once on this thread;
            // before the engine exists Dart says both again at configure.
            GraineInApp.current?.setIdentityToken(call.arguments as? String)
            result(nil)
        case "setMemory":
            // The current user's memory choice, for the calls this engine places and
            // answers. Before the engine exists Dart says it again at configure.
            guard let on = call.arguments as? Bool else {
                result(FlutterError(code: "invalid_arguments", message: "setMemory takes a bool", details: nil))
                return
            }
            host.setMemory(on)
            result(nil)
        case "registerPushToken":
            // Android's FCM token; iOS registers its VoIP token natively.
            result(nil)
        case "callPermissions":
            result(host.callPermissions())
        case "requestCallPermissions":
            // The system's dialog when it can still ask; the permissions as they stand after.
            host.requestCallPermissions { result($0) }
        case "openCallSettings":
            result(host.openCallSettings(call.arguments as? String))
        case "callSetupProblems":
            // Info.plist is the app's to edit: the check names what to add.
            result(host.callSetupProblems())
        case "setClientToken":
            // The server token Dart's token manager holds (nil: none), on every change: every request the engine
            // makes carries it. One refused for it comes back to Dart as the `needClientToken` event.
            host.setClientToken(call.arguments as? String)
            result(nil)
        case "setVariables":
            host.setVariables(call.arguments as? [String: Any])
            result(nil)
        case "setScreen":
            host.setScreen(call.arguments as? [String: Any])
            result(nil)
        case "setActions":
            // The actions this engine's Dart answers: their requests come to this engine's sink.
            let names = (call.arguments as? [Any] ?? []).compactMap { $0 as? String }
            host.setActions(names, sink: sink)
            result(nil)
        case "resolveAction":
            guard let arguments = call.arguments as? [String: Any], let requestId = arguments["requestId"] as? String else {
                result(FlutterError(code: "invalid_arguments", message: "resolveAction takes {requestId, result}", details: nil))
                return
            }
            host.resolveAction(requestId, result: arguments["result"] as? [String: Any])
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - The device

    private static func handleDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "installId":
            if let known = installId { result(known); return }
            // The SDK's own id (the host's, once configured or restored), else the
            // same Keychain item it keeps it in — one id per device either way.
            let id = GraineCallsHost.shared.installId() ?? InstallId.resolve(KeychainInstallIdStore()).id
            installId = id
            result(id)
        case "timezone":
            result(TimeZone.current.identifier)
        case "readPrefs":
            result(UserDefaults.standard.string(forKey: prefsKey))
        case "writePrefs":
            guard let json = call.arguments as? String else {
                result(FlutterError(code: "invalid_arguments", message: "writePrefs takes a string", details: nil))
                return
            }
            UserDefaults.standard.set(json, forKey: prefsKey)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        stopListening()
        self.events = events
        sink = GraineCallsHost.shared.addSink { event, payload in
            events(["event": event, "data": payload])
        }
        watchVerification()
        return nil
    }

    // MARK: - Verification

    /// Every configured agent's verification, each watched once: its current state at once, then every change.
    private func watchVerification() {
        guard events != nil else { return }
        for agent in GraineInApp.all.values {
            let key = agent.config.publishableKey
            if watching[key] != nil { continue }
            // A published value is delivered as it is set, and once at subscription: the current state.
            watching[key] = agent.$verification.sink { [weak self] verification in
                self?.sendVerification(key, verification)
            }
        }
    }

    private func sendVerification(_ key: String, _ v: GraineVerification) {
        let send = { [weak self] in
            guard let self = self, let events = self.events else { return }
            let data: [String: Any] = [
                "publishableKey": key,
                "app": v.app.rawValue,
                "appReason": v.appReason ?? NSNull(),
                "user": v.user.rawValue,
                "userReason": v.userReason ?? NSNull(),
                "traits": self.traits ?? NSNull(),
            ]
            events(["event": "verification", "data": data])
        }
        if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopListening()
        return nil
    }

    /// The engine is going away: its sink goes with it, so nothing is sent into an engine that is gone.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        stopListening()
    }

    private func stopListening() {
        watching.values.forEach { $0.cancel() }
        watching.removeAll()
        events = nil
        guard let token = sink else { return }
        sink = nil
        GraineCallsHost.shared.removeSink(token)
    }
}

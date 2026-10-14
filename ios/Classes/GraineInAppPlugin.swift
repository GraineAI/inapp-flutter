import Flutter
import UIKit

/**
 * The iOS half of graine_inapp's calls: the MethodChannel `ai.graine.inapp/calls`
 * and the EventChannel `ai.graine.inapp/calls/events`, which streams
 * `{"event": name, "data": payload}`, over GraineCallsHost in the Graine iOS SDK
 * this plugin carries.
 *
 * It only marshals values: every rule is in the host, inside the SDK, where its
 * own tests cover it. One instance per Flutter engine — the app's, and a
 * background messaging isolate's — each with its own sink while its Dart side
 * listens. Method calls arrive, and events are sent, on the main thread.
 *
 * And `ai.graine.inapp/device`: what Dart needs from the device for the
 * identity channel — the install id the SDK keeps in the Keychain (the SAME
 * id its call engine sends), the IANA zone, and the Dart side's own few bytes
 * of preferences (its users' memory choices, by fingerprint).
 */
public class GraineInAppPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: Int?

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
                result(nil)
            } catch let error as GraineCallsHostError {
                result(FlutterError(code: error.code, message: error.message, details: nil))
            } catch {
                result(FlutterError(code: "invalid_options", message: error.localizedDescription, details: nil))
            }
        case "restore":
            result(host.restore())
        case "snapshot", "getState":
            result(host.snapshot())
        case "enableVoIPPushes":
            host.enableVoIPPushes()
            result(nil)
        case "handlePush":
            result(host.handlePush(call.arguments as? [String: Any]))
        case "startCall":
            result(host.startCall(call.arguments as? [String: Any]))
        case "answer":
            host.answer()
            result(nil)
        case "decline":
            host.decline()
            result(nil)
        case "end":
            host.end()
            result(nil)
        case "setMuted", "setSpeaker":
            guard let on = call.arguments as? Bool else {
                result(FlutterError(code: "invalid_arguments", message: "\(call.method) takes a bool", details: nil))
                return
            }
            if call.method == "setMuted" { host.setMuted(on) } else { host.setSpeaker(on) }
            result(nil)
        case "setIdentity":
            // The traits as the app passed them: the SDK masks them for the agent
            // and keeps the identity raw for Graine, as its own identify does.
            host.setIdentity(call.arguments as? [String: Any])
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
        sink = GraineCallsHost.shared.addSink { event, payload in
            events(["event": event, "data": payload])
        }
        return nil
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
        guard let token = sink else { return }
        sink = nil
        GraineCallsHost.shared.removeSink(token)
    }
}

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
 */
public class GraineInAppPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: Int?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = GraineInAppPlugin()
        let methods = FlutterMethodChannel(name: "ai.graine.inapp/calls", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(plugin, channel: methods)
        let events = FlutterEventChannel(name: "ai.graine.inapp/calls/events", binaryMessenger: registrar.messenger())
        events.setStreamHandler(plugin)
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
            host.setIdentity(call.arguments as? [String: Any])
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

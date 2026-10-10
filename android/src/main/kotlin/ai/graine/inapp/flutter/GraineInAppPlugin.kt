package ai.graine.inapp.flutter

import ai.graine.inapp.GraineCallsHost
import ai.graine.inapp.GraineCallsHostException
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * THE CALLS CHANNELS, ON ANDROID: Dart's `GraineCalls` speaks to the SDK's
 * [GraineCallsHost] through `ai.graine.inapp/calls` (methods) and
 * `ai.graine.inapp/calls/events` (`{"event": name, "data": payload}`).
 *
 * Nothing about calls is decided here — the host holds every rule (see
 * sdk/CALLS-HOST.md); this class only marshals values and plumbs the
 * activity. One instance per Flutter engine: the app's, and a background
 * isolate's (firebase_messaging runs one for pushes), each with its own sink,
 * so a push can ring before any of the app's Dart has run.
 */
class GraineInAppPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.NewIntentListener {

    private var context: Context? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var activity: ActivityPluginBinding? = null

    /** The host's token for this engine's event sink, while Dart listens. */
    private var sink: Int? = null

    // ── the engine ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHODS).also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, EVENTS).also { it.setStreamHandler(this) }
        // A launch the last configure() can answer for: calls ring from the kept options.
        GraineCallsHost.restore(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        stopListening()
        methods = null
        events = null
        context = null
    }

    // ── events ──────────────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopListening()
        sink = GraineCallsHost.addSink { event, payload ->
            events.success(mapOf("event" to event, "data" to payload))
        }
    }

    override fun onCancel(arguments: Any?) = stopListening()

    private fun stopListening() {
        sink?.let { GraineCallsHost.removeSink(it) }
        sink = null
    }

    // ── methods ─────────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("unavailable", "The plugin is not attached to an engine.", null)
        try {
            when (call.method) {
                "configure" -> {
                    GraineCallsHost.configure(ctx, call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "snapshot", "getState" -> result.success(GraineCallsHost.snapshot())
                "enableVoIPPushes" -> result.success(null)   // iOS only: Android rings from handlePush
                "handlePush" -> result.success(GraineCallsHost.handlePush(ctx, call.arguments as? Map<*, *>))
                "startCall" -> result.success(GraineCallsHost.startCall(activity?.activity, call.arguments as? Map<*, *>))
                "answer" -> done(result) { GraineCallsHost.answer() }
                "decline" -> done(result) { GraineCallsHost.decline() }
                "end" -> done(result) { GraineCallsHost.end() }
                "setMuted" -> flag(call, result) { GraineCallsHost.setMuted(it) }
                "setSpeaker" -> flag(call, result) { GraineCallsHost.setSpeaker(it) }
                "setIdentity" -> done(result) { GraineCallsHost.setIdentity(call.arguments as? Map<*, *>) }
                "setVariables" -> done(result) { GraineCallsHost.setVariables(call.arguments as? Map<*, *>) }
                "setScreen" -> done(result) { GraineCallsHost.setScreen(call.arguments as? Map<*, *>) }
                // The agent's actions come to the engine that lists them — this one's sink.
                "setActions" -> done(result) { GraineCallsHost.setActions(call.arguments as? List<*>, sink) }
                "resolveAction" -> {
                    val args = call.arguments as? Map<*, *>
                    val requestId = args?.get("requestId") as? String
                        ?: return result.error("invalid_arguments", "resolveAction takes {requestId, result}.", null)
                    GraineCallsHost.resolveAction(requestId, args["result"] as? Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: GraineCallsHostException) {
            result.error(e.code, e.message, null)
        }
    }

    private inline fun done(result: MethodChannel.Result, block: () -> Unit) {
        block()
        result.success(null)
    }

    private inline fun flag(call: MethodCall, result: MethodChannel.Result, block: (Boolean) -> Unit) {
        val on = call.arguments as? Boolean
            ?: return result.error("invalid_arguments", "${call.method} takes a bool.", null)
        block(on)
        result.success(null)
    }

    // ── the activity ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)

    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onDetachedFromActivity() = detach()

    private fun attach(binding: ActivityPluginBinding) {
        activity = binding
        // With callScreen "app" the call is drawn in this activity: the SDK asks
        // for the microphone from it, and the ring's Answer arrives as a new intent.
        binding.addRequestPermissionsResultListener(this)
        binding.addOnNewIntentListener(this)
    }

    private fun detach() {
        activity?.removeRequestPermissionsResultListener(this)
        activity?.removeOnNewIntentListener(this)
        activity = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean =
        GraineCallsHost.onRequestPermissionsResult(requestCode, grantResults)

    override fun onNewIntent(intent: Intent): Boolean {
        val current = activity?.activity ?: return false
        return GraineCallsHost.onNewIntent(current, intent)
    }

    private companion object {
        const val METHODS = "ai.graine.inapp/calls"
        const val EVENTS = "ai.graine.inapp/calls/events"
    }
}

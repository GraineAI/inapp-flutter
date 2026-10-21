package ai.graine.inapp.flutter

import ai.graine.inapp.GraineCallsHost
import ai.graine.inapp.GraineCallsHostException
import android.content.Context
import android.content.Intent
import java.io.File
import java.util.TimeZone
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
 *
 * And `ai.graine.inapp/device`: what Dart needs from the device for the
 * identity channel (contract 1.2-1.3) — the install id the native SDK keeps
 * (the SAME id its call engine sends), the IANA zone, and the Dart side's
 * own few bytes of preferences (its users' memory choices, by fingerprint).
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
    private var device: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null

    /** The host's token for this engine's event sink, while Dart listens. */
    private var sink: Int? = null

    // ── the engine ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHODS).also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, EVENTS).also { it.setStreamHandler(this) }
        device = MethodChannel(binding.binaryMessenger, DEVICE).also { it.setMethodCallHandler(::onDeviceCall) }
        // A launch the last configure() can answer for: calls ring from the kept options.
        GraineCallsHost.restore(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        device?.setMethodCallHandler(null)
        stopListening()
        methods = null
        events = null
        device = null
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
                "enableVoIPPushes" -> result.success(null)   // iOS only: Android rings from Firebase's messages
                "handlePush" -> result.success(GraineCallsHost.handlePush(ctx, call.arguments as? Map<*, *>))
                "startCall" -> result.success(GraineCallsHost.startCall(activity?.activity, call.arguments as? Map<*, *>))
                // startCall's arguments; no activity — nothing is dialled and the microphone is not touched.
                "prepareCall" -> done(result) { GraineCallsHost.prepareCall(call.arguments as? Map<*, *>) }
                "answer" -> done(result) { GraineCallsHost.answer() }
                "decline" -> done(result) { GraineCallsHost.decline() }
                "end" -> done(result) { GraineCallsHost.end() }
                "setMuted" -> flag(call, result) { GraineCallsHost.setMuted(it) }
                "setSpeaker" -> flag(call, result) { GraineCallsHost.setSpeaker(it) }
                // Where calls start their sound: kept by the host for the next cold start, held until configure.
                "setSpeakerByDefault" -> flag(call, result) { GraineCallsHost.setSpeakerByDefault(it) }
                // The traits as the app passed them: the SDK masks them for the
                // agent and keeps the identity raw for Graine, as its own identify does.
                "setIdentity" -> done(result) { GraineCallsHost.setIdentity(call.arguments as? Map<*, *>) }
                // The current user's memory choice, for the calls this engine places
                // and answers; the host holds it until the SDK's instance exists.
                "setMemory" -> flag(call, result) { GraineCallsHost.setMemory(it) }
                // Android hosted ringing: FCM's token, kept and registered with Graine.
                "registerPushToken" -> {
                    val token = (call.arguments as? Map<*, *>)?.get("token") as? String
                        ?: return result.error("invalid_arguments", "registerPushToken takes {token}.", null)
                    GraineCallsHost.onNewToken(ctx, token)
                    result.success(null)
                }
                "callPermissions" -> result.success(GraineCallsHost.callPermissions(ctx))
                // Asked from the SDK's own transparent screen over this activity: no result to forward.
                "requestCallPermissions" -> GraineCallsHost.requestCallPermissions(ctx, activity?.activity) { result.success(it) }
                "openCallSettings" -> result.success(GraineCallsHost.openCallSettings(ctx, activity?.activity, call.arguments))
                "callSetupProblems" -> result.success(GraineCallsHost.callSetupProblems())
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

    // ── the device ──────────────────────────────────────────────────────────

    private fun onDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("unavailable", "The plugin is not attached to an engine.", null)
        when (call.method) {
            "installId" -> result.success(runCatching { GraineCallsHost.installId(ctx) }.getOrNull())
            "timezone" -> result.success(runCatching { TimeZone.getDefault().id }.getOrNull())
            "readPrefs" -> result.success(runCatching { prefsFile(ctx)?.takeIf { it.exists() }?.readText() }.getOrNull())
            "writePrefs" -> {
                val json = call.arguments as? String
                    ?: return result.error("invalid_arguments", "writePrefs takes a string.", null)
                runCatching {
                    val f = prefsFile(ctx) ?: return@runCatching
                    f.parentFile?.mkdirs()
                    val tmp = File(f.parentFile, f.name + ".tmp")
                    tmp.writeText(json)
                    if (!tmp.renameTo(f)) { f.writeText(json); tmp.delete() }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Beside the native SDK's own store: never backed up, so never restored onto another phone. */
    private fun prefsFile(ctx: Context): File? =
        runCatching { File(File(ctx.applicationContext.noBackupFilesDir, "graine-inapp"), "flutter.json") }.getOrNull()

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
        const val DEVICE = "ai.graine.inapp/device"
    }
}

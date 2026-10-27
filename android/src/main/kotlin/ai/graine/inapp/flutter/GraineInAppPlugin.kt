package ai.graine.inapp.flutter

import ai.graine.inapp.GraineCallsHost
import ai.graine.inapp.GraineCallsHostException
import ai.graine.inapp.GraineInApp
import ai.graine.inapp.GraineVerification
import ai.graine.inapp.GraineVerificationListener
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
 * activity. Server tokens too: Dart's own token manager pushes each new one
 * (`setClientToken`), and hears `needClientToken` when one was refused. One instance per Flutter engine: the app's, and a background
 * isolate's (firebase_messaging runs one for pushes), each with its own sink,
 * so a push can ring before any of the app's Dart has run.
 *
 * And `ai.graine.inapp/device`: what Dart needs from the device for the
 * identity channel (contract 1.2-1.3) — the install id the native SDK keeps
 * (the SAME id its call engine sends), the IANA zone, and the Dart side's
 * own few bytes of preferences (its users' memory choices, by fingerprint).
 *
 * And `ai.graine.inapp/app` ([GraineFlutterAppIdentity]): which app this is,
 * and its Play Integrity proofs, for "Your app and your users".
 *
 * And every hosted agent's verification: what Graine made of this app and its
 * user on the engine's own requests (a call's ticket, its credential), as the
 * `verification` event — `{publishableKey, app, appReason, user, userReason,
 * traits}`, `traits` being what this plugin last handed the engine — once with
 * the current state while Dart listens, then on every change. Read through the
 * SDK's public API ([GraineInApp.all], each agent's verification listener).
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
    private var app: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null

    /** The host's token for this engine's event sink, while Dart listens. */
    private var sink: Int? = null

    /** Dart's events while it listens: the host's, and every agent's verification. */
    private var eventSink: EventChannel.EventSink? = null

    /** What this plugin last handed the engine as setIdentity (null: none) — each verification event names it. */
    private var traits: Map<*, *>? = null

    /** The agents whose verification is forwarded, by publishable key, and what stops each. */
    private val watching = HashMap<String, () -> Unit>()

    // ── the engine ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHODS).also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, EVENTS).also { it.setStreamHandler(this) }
        device = MethodChannel(binding.binaryMessenger, DEVICE).also { it.setMethodCallHandler(::onDeviceCall) }
        val identity = GraineFlutterAppIdentity(binding.applicationContext)
        app = MethodChannel(binding.binaryMessenger, APP).also { it.setMethodCallHandler(identity::onMethodCall) }
        // A launch the last configure() can answer for: calls ring from the kept options.
        GraineCallsHost.restore(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        device?.setMethodCallHandler(null)
        app?.setMethodCallHandler(null)
        stopListening()
        methods = null
        events = null
        device = null
        app = null
        context = null
    }

    // ── events ──────────────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopListening()
        eventSink = events
        sink = GraineCallsHost.addSink { event, payload ->
            events.success(mapOf("event" to event, "data" to payload))
        }
        watchVerification()
    }

    override fun onCancel(arguments: Any?) = stopListening()

    private fun stopListening() {
        watching.values.forEach { it() }
        watching.clear()
        eventSink = null
        sink?.let { GraineCallsHost.removeSink(it) }
        sink = null
    }

    // ── verification ────────────────────────────────────────────────────────

    /** Every configured agent's verification, each watched once: its current state at once, then every change (main thread). */
    private fun watchVerification() {
        if (eventSink == null) return
        for (g in GraineInApp.all.values) {
            val key = g.config.publishableKey
            if (watching.containsKey(key)) continue
            val listener = GraineVerificationListener { v -> sendVerification(key, v) }
            g.addVerificationListener(listener)
            watching[key] = { g.removeVerificationListener(listener) }
            sendVerification(key, g.verification)
        }
    }

    private fun sendVerification(key: String, v: GraineVerification) {
        eventSink?.success(
            mapOf(
                "event" to "verification",
                "data" to mapOf(
                    "publishableKey" to key,
                    "app" to v.app.word,
                    "appReason" to v.appReason,
                    "user" to v.user.word,
                    "userReason" to v.userReason,
                    "traits" to traits,
                ),
            ),
        )
    }

    // ── methods ─────────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("unavailable", "The plugin is not attached to an engine.", null)
        try {
            when (call.method) {
                "configure" -> {
                    GraineCallsHost.configure(ctx, call.arguments as? Map<*, *>)
                    // The agents it configured (and any it added): their verification reaches Dart too.
                    watchVerification()
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
                // Noted first: what the engine reports from now on is about them.
                "setIdentity" -> done(result) {
                    traits = call.arguments as? Map<*, *>
                    GraineCallsHost.setIdentity(call.arguments as? Map<*, *>)
                }
                // The current user's memory choice, for the calls this engine places
                // and answers; the host holds it until the SDK's instance exists.
                "setMemory" -> flag(call, result) { GraineCallsHost.setMemory(it) }
                // The identity token for the user setIdentity named (APP-IDENTITY.md §1.3), for the calls this
                // engine places and answers — after setIdentity, which the host applies at once on this thread.
                // Before the engine exists Dart says both again at configure.
                "setIdentityToken" -> done(result) {
                    val token = call.arguments as? String
                    GraineInApp.all.values.forEach { it.setIdentityToken(token) }
                }
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
                // The server token Dart's token manager holds (null: none), on every change: every request the
                // engine makes carries it. One refused for it comes back to Dart as the `needClientToken` event.
                "setClientToken" -> done(result) { GraineCallsHost.setClientToken(call.arguments as? String) }
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
        const val APP = "ai.graine.inapp/app"
    }
}

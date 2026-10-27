package ai.graine.inapp.flutter

import ai.graine.inapp.DeviceStore
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `ai.graine.inapp/app` on Android: what Dart needs to say which app this is
 * and to prove it (sdk/contract/APP-IDENTITY.md §1.2, §3.5, §3.6). Native code
 * only READS and PROVES here; every rule applied to the answers (the digests,
 * when to prove, what to send) is in Dart, held to the contract's vectors by
 * its tests.
 *
 *   declaration      → {platform: "android", id, certificates?}: the package, and the DER bytes of
 *                      each signing certificate — Dart takes their SHA-256
 *   readDebugToken   → String?: development mode's token, kept beside the install id in the SDK's
 *                      own no-backup store — the one its call engine uses too, so an install has one
 *   writeDebugToken    String
 *   prove            {challenge, cloudProjectNumber?} → {kind: "play", token}
 *                      · {error: "missing_dependency" | "unsupported" | "backoff" | "failed", message?}
 *   forgetProofKey     nothing to let go of on Android
 *
 * Results are delivered on the main thread; the package manager and Play
 * Integrity are never waited on there.
 */
internal class GraineFlutterAppIdentity(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "declaration" -> off { declaration(context) }.then(result)
            "readDebugToken" -> off { DeviceStore.of(context).debugToken }.then(result)
            "writeDebugToken" -> {
                val token = call.arguments as? String
                    ?: return result.error("invalid_arguments", "writeDebugToken takes a string.", null)
                off { DeviceStore.of(context).debugToken = token; null }.then(result)
            }
            "prove" -> prove(call) { answer -> result.success(answer) }
            "forgetProofKey" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    /** Work for the background thread, whose answer (null when it threw) reaches Dart on the main thread. */
    private class Off(private val main: Handler, private val work: () -> Any?) {
        fun then(result: MethodChannel.Result) = WORKERS.execute {
            val answer = runCatching(work).getOrNull()
            main.post { result.success(answer) }
        }
    }

    private fun off(work: () -> Any?) = Off(main, work)

    // ── the proof (§3.5) ────────────────────────────────────────────────────

    private fun prove(call: MethodCall, done: (Map<String, Any?>) -> Unit) {
        val args = call.arguments as? Map<*, *>
        val challenge = args?.get("challenge") as? String
        if (challenge.isNullOrEmpty()) return done(mapOf("error" to "failed", "message" to "prove takes {challenge}"))
        if (!playIntegrityPresent()) {
            warnMissingOnce()
            return done(mapOf("error" to "missing_dependency", "message" to MISSING))
        }
        val project = (args["cloudProjectNumber"] as? String)?.trim()?.toLongOrNull()
        // Only now, with the library known to be there, is the class that names its types loaded.
        GraineFlutterPlayIntegrity.request(context, challenge, project, TIMEOUT_MS, done)
    }

    companion object {
        private const val TAG = "Graine"
        private const val TIMEOUT_MS = 20_000L
        private const val MISSING = "Play Integrity is not in this app: add " +
            "implementation(\"com.google.android.play:integrity:1.4.0\") to android/app/build.gradle so it can prove itself."
        private val WORKERS = Executors.newSingleThreadExecutor { r -> Thread(r, "graine-app-identity").apply { isDaemon = true } }

        @Volatile private var warned = false

        /** Read once per process: neither changes while the app runs. */
        @Volatile private var declared: Map<String, Any?>? = null

        /** Whether the app carries Play Integrity — the SDK only compiles against it. */
        fun playIntegrityPresent(): Boolean =
            runCatching { Class.forName("com.google.android.play.core.integrity.IntegrityManagerFactory") }.isSuccess

        private fun warnMissingOnce() {
            if (warned) return
            warned = true
            Log.w(TAG, MISSING)
        }

        /** The package and its signing certificates' DER bytes (§1.2); the certificates left out when unreadable. */
        fun declaration(context: Context): Map<String, Any?>? {
            declared?.let { return it }
            val id = context.packageName?.takeIf { it.isNotEmpty() } ?: return null
            val answer = mutableMapOf<String, Any?>("platform" to "android", "id" to id)
            certificates(context)?.takeIf { it.isNotEmpty() }?.let { answer["certificates"] = it }
            declared = answer
            return answer
        }

        /**
         * API 28+: the signing certificates — every signer of an APK signed by
         * several, else the whole rotation history; API 24–27: the signatures.
         * Any exception: null.
         */
        @Suppress("DEPRECATION")
        private fun certificates(context: Context): List<ByteArray>? = runCatching {
            val pm = context.packageManager
            val pkg = context.packageName
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(pkg, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo
                    ?: return@runCatching null
                val signers = if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
                signers?.map { it.toByteArray() }
            } else {
                pm.getPackageInfo(pkg, PackageManager.GET_SIGNATURES).signatures?.map { it.toByteArray() }
            }
        }.getOrNull()
    }
}

package ai.graine.inapp.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityServiceException
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.model.IntegrityErrorCode
import java.util.concurrent.atomic.AtomicBoolean

/**
 * PLAY INTEGRITY, A CLASSIC REQUEST (APP-IDENTITY.md §3.5) — the ONLY class
 * of the plugin that names Play Integrity's types. The plugin compiles against
 * the library (`compileOnly`) and the app brings it
 * (`implementation("com.google.android.play:integrity:1.4.0")`); this class is
 * loaded only after `GraineFlutterAppIdentity.playIntegrityPresent()` found
 * the library, so an app without it never loads anything of it.
 */
internal object GraineFlutterPlayIntegrity {
    /**
     * A token for [nonce] (Graine's challenge), under [cloudProjectNumber] when
     * the agent named one; [done] is called once, on the main thread:
     * `{kind: "play", token}`, or why not — Google or the network unreachable
     * (`backoff`: tried again later, with the outage grace), no Play Store or
     * Play services on this device (`unsupported`), anything else (`failed`).
     * No answer within [timeoutMs] counts as Google unreachable.
     */
    fun request(context: Context, nonce: String, cloudProjectNumber: Long?, timeoutMs: Long, done: (Map<String, Any?>) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        val settled = AtomicBoolean(false)
        fun settle(answer: Map<String, Any?>) {
            if (settled.compareAndSet(false, true)) main.post { done(answer) }
        }
        main.postDelayed({ settle(mapOf("error" to "backoff", "message" to "Play Integrity did not answer in time")) }, timeoutMs)
        try {
            val request = IntegrityTokenRequest.builder().setNonce(nonce)
            if (cloudProjectNumber != null) request.setCloudProjectNumber(cloudProjectNumber)
            IntegrityManagerFactory.create(context.applicationContext)
                .requestIntegrityToken(request.build())
                .addOnSuccessListener { response -> settle(mapOf("kind" to "play", "token" to response.token())) }
                .addOnFailureListener { error -> settle(failure(error)) }
        } catch (e: Exception) {
            settle(failure(e))
        }
    }

    private fun failure(error: Exception): Map<String, Any?> = when ((error as? IntegrityServiceException)?.errorCode) {
        IntegrityErrorCode.TOO_MANY_REQUESTS,
        IntegrityErrorCode.GOOGLE_SERVER_UNAVAILABLE,
        IntegrityErrorCode.NETWORK_ERROR,
        IntegrityErrorCode.INTERNAL_ERROR,
        -> mapOf("error" to "backoff", "message" to "Google could not be reached")
        IntegrityErrorCode.API_NOT_AVAILABLE,
        IntegrityErrorCode.PLAY_STORE_NOT_FOUND,
        IntegrityErrorCode.PLAY_SERVICES_NOT_FOUND,
        IntegrityErrorCode.CANNOT_BIND_TO_SERVICE,
        -> mapOf("error" to "unsupported", "message" to "Play Integrity is not available on this device")
        else -> mapOf("error" to "failed", "message" to (error.message ?: error.javaClass.simpleName))
    }
}

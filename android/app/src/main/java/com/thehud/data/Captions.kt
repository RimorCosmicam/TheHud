package com.thehud.data

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.thehud.core.HudSnapshot
import java.io.File
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Live captions of what is said nearby, as on the iPhone: Android's recogniser, on the phone where
 * it can be, restarted after each finished stretch since one request is not meant to run long.
 * Each session is saved as it goes, one plain text file.
 */
class CaptionsEngine(private val context: Context, private val onChange: (HudSnapshot.Captions) -> Unit) {
    var state = HudSnapshot.Captions()
        private set(value) { if (value != field) { field = value; onChange(value) } }

    var language: String = defaultLanguage
        set(value) {
            if (value == field) return
            field = value
            if (state.isListening) { stop(); start() }
        }

    private val main = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var log: File? = null
    private var startedAt: Long? = null
    private var listening = false

    val allowed get() = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun toggle() = if (state.isListening) stop() else start()

    fun start() {
        if (listening) return
        if (!allowed) { state = state.copy(status = "NO MICROPHONE ACCESS"); return }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) { state = state.copy(status = "NO SPEECH RECOGNITION"); return }
        listening = true
        val now = System.currentTimeMillis()
        startedAt = now
        log = CaptionsLog.begin(context, now)
        state = HudSnapshot.Captions(isListening = true, status = "STARTING")
        listen()
    }

    fun stop() {
        listening = false
        main.removeCallbacksAndMessages(null)
        recognizer?.run { runCatching { cancel(); destroy() } }
        recognizer = null
        if (state.partial.isNotEmpty()) commit(state.partial)
        state = state.copy(partial = "", isListening = false, status = "OFF")
        startedAt = null
        log = null
    }

    fun tick(now: Long = System.currentTimeMillis()) {
        val start = startedAt ?: return
        state = state.copy(elapsed = HudSnapshot.NowPlaying.time((now - start) / 1000.0))
    }

    private val tag get() = language.uppercase()

    private fun makeRecognizer(): SpeechRecognizer {
        // On the phone where the language's model is there; Google's servers otherwise.
        val onDevice = runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(context) }.getOrDefault(false)
        return if (onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context) else SpeechRecognizer.createSpeechRecognizer(context)
    }

    /** One stretch: until the recogniser calls it finished, then the next straight away. */
    private fun listen() {
        if (!listening) return
        val r = recognizer ?: makeRecognizer().also { recognizer = it }
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { state = state.copy(status = "LISTENING · $tag") }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                if (text.isNotBlank()) state = state.copy(partial = text)
            }
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: state.partial
                commit(text)
                state = state.copy(partial = "")
                again(0)
            }
            override fun onError(error: Int) {
                if (!listening) return
                if (state.partial.isNotEmpty()) { commit(state.partial); state = state.copy(partial = "") }
                when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> fail("NO MICROPHONE ACCESS")
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                        fail("NO SPEECH RECOGNITION FOR $tag")
                    // Silence, nothing understood, or busy: listen again.
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY, SpeechRecognizer.ERROR_CLIENT -> {
                        recognizer?.runCatching { destroy() }; recognizer = null; again(400)
                    }
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER -> {
                        state = state.copy(status = "WAITING FOR THE NETWORK"); again(2000)
                    }
                    else -> again(100)
                }
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 60_000L)
        runCatching { r.startListening(intent) }.onFailure { fail("STOPPED: " + (it.message ?: "").take(60).uppercase()) }
    }

    private fun again(delay: Long) { if (listening) main.postDelayed(::listen, delay) }

    private fun fail(status: String) { stop(); state = state.copy(status = status) }

    private fun commit(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        state = state.copy(lines = (state.lines + trimmed).takeLast(12))
        log?.let { CaptionsLog.append(trimmed, System.currentTimeMillis(), it) }
    }

    companion object {
        val languages = listOf(
            "pt-BR" to "Português (Brasil)", "pt-PT" to "Português (Portugal)", "en-US" to "English (US)",
            "en-GB" to "English (UK)", "es-ES" to "Español (España)", "es-MX" to "Español (México)",
            "fr-FR" to "Français", "de-DE" to "Deutsch", "it-IT" to "Italiano")

        /** The phone's own language where offered; Portuguese for a Brazilian phone, whatever its menus say. */
        val defaultLanguage: String
            get() {
                val l = Locale.getDefault()
                if (l.country == "BR") return "pt-BR"
                val tag = l.toLanguageTag()
                if (languages.any { it.first == tag }) return tag
                return languages.firstOrNull { it.first.startsWith(l.language + "-") }?.first ?: "en-US"
            }
    }
}

/** Saved caption sessions: a plain text file each, in the app's files folder. */
object CaptionsLog {
    data class Session(val file: File, val date: Long, val lines: Int, val preview: String)

    fun directory(context: Context): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, "Captions").apply { mkdirs() }

    fun begin(context: Context, at: Long): File {
        val file = File(directory(context), "Captions " + SimpleDateFormat("yyyy-MM-dd HH.mm.ss", Locale.US).format(Date(at)) + ".txt")
        runCatching {
            file.writeText("Captions — " + DateFormat.getDateTimeInstance(DateFormat.FULL, DateFormat.SHORT).format(Date(at)) + "\n\n")
        }
        return file
    }

    fun append(text: String, at: Long, to: File) {
        runCatching { to.appendText("[" + SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(at)) + "] " + text + "\n") }
    }

    fun sessions(context: Context): List<Session> =
        (directory(context).listFiles() ?: emptyArray()).filter { it.extension == "txt" }.mapNotNull { f ->
            val spoken = runCatching { f.readLines() }.getOrNull()?.filter { it.startsWith("[") } ?: return@mapNotNull null
            Session(f, f.lastModified(), spoken.size, spoken.take(2).joinToString(" ") { it.substringAfter("]").trim() })
        }.sortedByDescending { it.date }

    fun delete(session: Session) { session.file.delete() }
}

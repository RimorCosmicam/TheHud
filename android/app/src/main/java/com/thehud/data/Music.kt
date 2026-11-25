package com.thehud.data

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService
import com.thehud.core.HudSnapshot

/** Nothing of its own: being enabled is what lets the app see other apps' media sessions. */
class MediaListener : NotificationListenerService() {
    override fun onListenerConnected() {
        instance = this
        // Off, TheHud does not stay bound to the phone's notifications either.
        if (com.thehud.HudController.isOff) runCatching { requestUnbind() }
    }
    override fun onListenerDisconnected() { if (instance === this) instance = null }
    override fun onDestroy() { if (instance === this) instance = null; super.onDestroy() }

    companion object {
        private var instance: MediaListener? = null

        /** Off: unbound; on again: bound again, if notification access is still allowed. */
        fun bind(context: Context, on: Boolean) {
            if (on) runCatching { requestRebind(ComponentName(context, MediaListener::class.java)) }
            else instance?.let { runCatching { it.requestUnbind() } }
        }
    }
}

/**
 * Whatever is playing on the phone, from any app with a media session, and its buttons. Android
 * lets an app with notification access see every session, so this is not one player only.
 */
class MusicProvider(private val context: Context, private val onChange: (HudSnapshot.NowPlaying?, Bitmap?) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private var controller: MediaController? = null
    private var started = false
    private val listener = ComponentName(context, MediaListener::class.java)

    val allowed: Boolean
        get() = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            ?.contains(context.packageName) == true

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) { refresh(); pick() }
        override fun onMetadataChanged(metadata: MediaMetadata?) = refresh()
        override fun onSessionDestroyed() { pick() }
    }

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { pick() }

    fun start() {
        if (started || !allowed) { if (!allowed) onChange(null, null); return }
        val manager = context.getSystemService(MediaSessionManager::class.java) ?: return
        started = runCatching { manager.addOnActiveSessionsChangedListener(sessionsChanged, listener, main); true }.getOrDefault(false)
        pick()
    }

    /** Off: no sessions watched, no player followed. */
    fun stop() {
        if (!started) return
        started = false
        runCatching { context.getSystemService(MediaSessionManager::class.java)?.removeOnActiveSessionsChangedListener(sessionsChanged) }
        controller?.unregisterCallback(callback)
        controller = null
    }

    /** The session that is playing, or the most recent one. */
    private fun pick() {
        val manager = context.getSystemService(MediaSessionManager::class.java) ?: return
        val sessions = runCatching { manager.getActiveSessions(listener) }.getOrDefault(emptyList())
        val chosen = sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()
        if (chosen?.sessionToken != controller?.sessionToken) {
            controller?.unregisterCallback(callback)
            controller = chosen
            chosen?.registerCallback(callback, main)
        }
        refresh()
    }

    /** Once a second while playing, for the progress bar. */
    fun tick() {
        if (controller?.playbackState?.state == PlaybackState.STATE_PLAYING) refresh()
    }

    private var artFor: String? = null
    private var art: Bitmap? = null

    private fun refresh() {
        val c = controller
        val m = c?.metadata
        if (c == null || m == null) { onChange(null, null); return }
        val state = c.playbackState
        val playing = state?.state == PlaybackState.STATE_PLAYING
        var position = state?.position ?: 0L
        if (playing && state != null && state.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - state.lastPositionUpdateTime) * state.playbackSpeed).toLong()
        }
        val title = m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: "Unknown"
        val key = title + "|" + c.packageName
        if (key != artFor) {
            artFor = key
            art = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART)
                ?: m.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        }
        val label = runCatching {
            context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(c.packageName, 0)).toString()
        }.getOrDefault("")
        val duration = m.getLong(MediaMetadata.METADATA_KEY_DURATION)
        onChange(HudSnapshot.NowPlaying(title,
            m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: "",
            m.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: "", playing,
            position.coerceAtLeast(0) / 1000.0, if (duration > 0) duration / 1000.0 else 0.0, label), art)
    }

    fun playPause() {
        val t = controller?.transportControls ?: return
        if (controller?.playbackState?.state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
        main.postDelayed(::refresh, 250)
    }

    fun next() { controller?.transportControls?.skipToNext(); main.postDelayed(::refresh, 250) }

    /** Back to the start of the song, or to the one before if it has only just begun. */
    fun previous() {
        val c = controller ?: return
        if ((c.playbackState?.position ?: 0) > 3000) c.transportControls.seekTo(0) else c.transportControls.skipToPrevious()
        main.postDelayed(::refresh, 250)
    }

    fun seek(by: Double) {
        val c = controller ?: return
        val pos = c.playbackState?.position ?: return
        c.transportControls.seekTo((pos + (by * 1000).toLong()).coerceAtLeast(0))
        main.postDelayed(::refresh, 250)
    }
}

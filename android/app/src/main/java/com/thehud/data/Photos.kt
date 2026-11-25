package com.thehud.data

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The phone's photo library for the Photos app, as the iPhone's PhotosProvider: newest first,
 * counted, captioned by when, and the pictures on show loaded off the main thread — small for
 * the gallery's grid, large for the one photo.
 */
class PhotosProvider(private val context: Context, private val scope: CoroutineScope, private val onChange: () -> Unit) {
    private class Photo(val id: Long, val taken: Long)

    private var photos: List<Photo> = emptyList()
    /** The pictures on show, by index into the library. */
    var images: Map<Int, ImageBitmap> = emptyMap()
        private set
    private val cache = HashMap<Pair<Long, Int>, ImageBitmap>()
    private var started = false
    private var wanted: Set<Pair<Int, Int>> = emptySet()

    private val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
    val hasAccess get() = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED ||
        (Build.VERSION.SDK_INT >= 34 && context.checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED)
    val count get() = photos.size

    /** Reads the library once, and again whenever it changes. */
    fun start() {
        if (started || !hasAccess) return
        started = true
        context.contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer)
        reload()
    }

    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) { override fun onChange(selfChange: Boolean) = reload() }

    /** Off: the library no longer watched. */
    fun stop() {
        if (!started) return
        started = false
        context.contentResolver.unregisterContentObserver(observer)
    }

    private fun reload() {
        scope.launch {
            val list = withContext(Dispatchers.IO) { runCatching { query() }.getOrDefault(emptyList()) }
            photos = list
            onChange()
        }
    }

    private fun query(): List<Photo> {
        val columns = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.DATE_ADDED)
        return context.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns, null, null,
            "${MediaStore.Images.Media.DATE_TAKEN} DESC")?.use { c ->
            buildList {
                while (c.moveToNext() && size < 20_000) {
                    val taken = c.getLong(1).takeIf { it > 0 } ?: (c.getLong(2) * 1000)
                    add(Photo(c.getLong(0), taken))
                }
            }
        } ?: emptyList()
    }

    /** "12 OCTOBER 2026". */
    fun caption(index: Int): String = photos.getOrNull(index)?.let {
        SimpleDateFormat("d MMMM yyyy", Locale.getDefault()).format(Date(it.taken)).uppercase()
    } ?: ""

    /** The pictures to have ready: the gallery's page as thumbnails, and one large. */
    fun show(thumbnails: List<Int>, large: Int?) {
        val next = thumbnails.map { it to THUMB }.toMutableSet()
        large?.let { next += it to LARGE }
        if (next == wanted) return
        wanted = next
        val ready = HashMap<Int, ImageBitmap>()
        for ((i, edge) in next) photos.getOrNull(i)?.let { p -> cache[p.id to edge]?.let { ready[i] = it } }
        images = ready
        val missing = next.filter { (i, edge) -> photos.getOrNull(i)?.let { cache[it.id to edge] } == null }
        if (missing.isEmpty()) return
        scope.launch {
            for ((i, edge) in missing) {
                val photo = photos.getOrNull(i) ?: continue
                val bitmap = withContext(Dispatchers.IO) {
                    runCatching {
                        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, photo.id)
                        context.contentResolver.loadThumbnail(uri, Size(edge, edge), null).asImageBitmap()
                    }.getOrNull()
                } ?: continue
                if (cache.size > 120) cache.clear()
                cache[photo.id to edge] = bitmap
                if ((i to edge) in wanted) {
                    images = images + (i to bitmap)
                    onChange()
                }
            }
        }
    }

    private companion object {
        const val THUMB = 360
        const val LARGE = 1600
    }
}

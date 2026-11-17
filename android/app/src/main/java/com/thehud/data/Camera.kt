package com.thehud.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.OrientationEventListener
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.MediaStoreOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.thehud.CameraAction
import com.thehud.core.HudSnapshot
import com.thehud.core.HudSnapshot.Camera.Mode
import com.thehud.core.HudSnapshot.Camera.Status
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * The phone's camera for the glasses, as the iPhone's CameraService, on CameraX: the preview goes
 * to a view on the glasses, photos and video to the gallery (Pictures/TheHud, Movies/TheHud), and
 * the magnifier zooms close, holds the picture still and brightens it.
 *
 * It runs only while it is on the glasses and the app is on a screen of the phone's: Android gives
 * the camera to the app in front. This object is the camera's own lifecycle, resumed while it runs.
 */
class CameraProvider(private val context: Context, private val scope: CoroutineScope,
                     private val onChange: (HudSnapshot.Camera) -> Unit) : LifecycleOwner {
    private val registry = LifecycleRegistry(this).apply { currentState = Lifecycle.State.CREATED }
    override val lifecycle: Lifecycle get() = registry

    var state = HudSnapshot.Camera()
        private set
    /** The picture held still, drawn over the live one. */
    var frozenFrame by mutableStateOf<ImageBitmap?>(null)
        private set

    private val main = ContextCompat.getMainExecutor(context)
    private val handler = Handler(Looper.getMainLooper())
    private val preview = Preview.Builder().build()
    private val photo = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
    private val recorder = Recorder.Builder()
        .setQualitySelector(QualitySelector.from(Quality.FHD, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD)))
        .build()
    private val video = VideoCapture.withOutput(recorder)
    private var provider: ProcessCameraProvider? = null
    private var camera: androidx.camera.core.Camera? = null
    private var recording: Recording? = null
    private var view: PreviewView? = null
    private var wanted = false
    private val clearNotice = Runnable { change { it.copy(notice = "") } }

    /** Photos and videos saved the way up the phone was held. */
    private val orientation = object : OrientationEventListener(context) {
        override fun onOrientationChanged(degrees: Int) {
            if (degrees == ORIENTATION_UNKNOWN) return
            val rotation = when (degrees) {
                in 45..134 -> Surface.ROTATION_270
                in 135..224 -> Surface.ROTATION_180
                in 225..314 -> Surface.ROTATION_90
                else -> Surface.ROTATION_0
            }
            photo.targetRotation = rotation
            if (recording == null) video.targetRotation = rotation
        }
    }

    val allowed get() = context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun change(edit: (HudSnapshot.Camera) -> HudSnapshot.Camera) {
        val next = edit(state)
        if (next == state) return
        state = next
        onChange(next)
    }

    // ------------------------------------------------------------------ running

    /** On while the camera is on the glasses and the app is in front. */
    fun run(on: Boolean) {
        if (on && !allowed) {
            if (wanted) stop()
            wanted = false
            change { it.copy(status = Status.denied) }
            return
        }
        if (on == wanted) return
        wanted = on
        if (on) start() else stop()
    }

    private fun start() {
        registry.currentState = Lifecycle.State.RESUMED
        orientation.enable()
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val p = runCatching { future.get() }.getOrNull()
            if (p == null) { change { it.copy(status = Status.unavailable) }; return@addListener }
            provider = p
            if (wanted) bind()
        }, main)
    }

    private fun stop() {
        recording?.stop()
        orientation.disable()
        camera?.cameraInfo?.cameraState?.removeObservers(this)
        provider?.unbindAll()
        camera = null
        registry.currentState = Lifecycle.State.CREATED
        change { it.copy(status = Status.paused, light = false) }
    }

    /** The camera the state asks for, with the preview, photos and video on it. */
    private fun bind() {
        val p = provider ?: return
        val selector = if (state.front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        if (!runCatching { p.hasCamera(selector) }.getOrDefault(false)) {
            change { it.copy(status = Status.unavailable) }
            return
        }
        camera?.cameraInfo?.cameraState?.removeObservers(this)
        p.unbindAll()
        val cam = runCatching { p.bindToLifecycle(this, selector, preview, photo, video) }.getOrNull()
            // A camera that cannot stream three ways at once still takes photos.
            ?: runCatching { p.bindToLifecycle(this, selector, preview, photo) }.getOrNull()
        camera = cam
        if (cam == null) { change { it.copy(status = Status.unavailable) }; return }
        view?.let { preview.setSurfaceProvider(it.surfaceProvider) }
        cam.cameraInfo.cameraState.observe(this) { s ->
            when {
                s.type == CameraState.Type.OPEN -> change { it.copy(status = Status.running) }
                s.error != null -> change { it.copy(status = Status.paused) }
            }
        }
        val zoom = cam.cameraInfo.zoomState.value
        val maxZoom = floor(minOf(zoom?.maxZoomRatio ?: 1f, 20f).toDouble()).coerceAtLeast(1.0)
        change { it.copy(maxZoom = maxZoom, zoom = minOf(it.zoom, maxZoom)) }
        apply()
    }

    /** Zoom, light and brightness, as the state has them. */
    private fun apply() {
        val cam = camera ?: return
        val zoom = cam.cameraInfo.zoomState.value
        val ratio = state.zoom.toFloat().coerceIn(zoom?.minZoomRatio ?: 1f, zoom?.maxZoomRatio ?: 1f)
        cam.cameraControl.setZoomRatio(ratio)
        if (cam.cameraInfo.hasFlashUnit()) cam.cameraControl.enableTorch(state.light && !state.front)
        val exposure = cam.cameraInfo.exposureState
        if (exposure.isExposureCompensationSupported) {
            val range = exposure.exposureCompensationRange
            val index = if (state.bright && state.mode == Mode.magnify)
                (2f / exposure.exposureCompensationStep.toFloat()).roundToInt().coerceIn(range.lower, range.upper) else 0
            if (index != exposure.exposureCompensationIndex) cam.cameraControl.setExposureCompensationIndex(index)
        }
    }

    /** The glasses' view of the picture. */
    fun attach(view: PreviewView) {
        this.view = view
        preview.setSurfaceProvider(view.surfaceProvider)
    }

    fun detach(view: PreviewView) {
        if (this.view !== view) return
        this.view = null
        preview.setSurfaceProvider(null)
    }

    // ------------------------------------------------------------------ the pad

    fun perform(action: CameraAction) {
        if (state.status != Status.running) return
        when (action) {
            CameraAction.Shutter -> when (state.mode) {
                Mode.photo -> takePhoto()
                Mode.magnify -> saveShown()
                Mode.video -> if (recording != null) recording?.stop() else startRecording()
            }
            is CameraAction.Mode -> {
                if (action.mode == state.mode || state.isRecording) return
                frozenFrame = null
                change { it.copy(mode = action.mode, frozen = false, bright = false,
                    zoom = if (action.mode == Mode.magnify) minOf(HudSnapshot.Camera.MAGNIFIER_ZOOM, it.maxZoom) else 1.0) }
                apply()
            }
            is CameraAction.Zoom -> { change { it.copy(zoom = it.zoom(action.by)) }; apply() }
            CameraAction.Flip -> {
                if (state.isRecording) return
                frozenFrame = null
                change { it.copy(front = !it.front, light = false, zoom = 1.0, frozen = false) }
                bind()
            }
            CameraAction.Freeze -> {
                frozenFrame = if (state.frozen) null else view?.bitmap?.asImageBitmap()
                change { it.copy(frozen = frozenFrame != null) }
            }
            CameraAction.Light -> if (!state.front) { change { it.copy(light = !it.light) }; apply() }
            CameraAction.Bright -> { change { it.copy(bright = !it.bright) }; apply() }
        }
    }

    private fun notice(text: String) {
        change { it.copy(notice = text) }
        handler.removeCallbacks(clearNotice)
        handler.postDelayed(clearNotice, 3000)
    }

    // ------------------------------------------------------------------ photos and video

    private fun values(mime: String, folder: String) = ContentValues().apply {
        put(MediaStore.MediaColumns.DISPLAY_NAME, "TheHud_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()))
        put(MediaStore.MediaColumns.MIME_TYPE, mime)
        put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
    }

    private fun takePhoto() {
        change { it.copy(shotAt = System.currentTimeMillis()) }
        val options = ImageCapture.OutputFileOptions.Builder(context.contentResolver,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values("image/jpeg", "Pictures/TheHud")).build()
        photo.takePicture(options, main, object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(output: ImageCapture.OutputFileResults) = notice("SAVED TO GALLERY")
            override fun onError(e: ImageCaptureException) = notice("COULDN'T TAKE THE PHOTO")
        })
    }

    /** The magnifier keeps what it shows, held still or not. */
    private fun saveShown() {
        val bitmap: Bitmap = frozenFrame?.asAndroidBitmap() ?: view?.bitmap ?: return
        change { it.copy(shotAt = System.currentTimeMillis()) }
        scope.launch(Dispatchers.IO) {
            val resolver = context.contentResolver
            val saved = runCatching {
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values("image/jpeg", "Pictures/TheHud"))!!
                resolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
            }.getOrDefault(false)
            handler.post { notice(if (saved) "SAVED TO GALLERY" else "COULDN'T SAVE") }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startRecording() {
        val options = MediaStoreOutputOptions.Builder(context.contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            .setContentValues(values("video/mp4", "Movies/TheHud")).build()
        var pending = recorder.prepareRecording(context, options)
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
            pending = pending.withAudioEnabled()
        change { it.copy(recordingSince = System.currentTimeMillis()) }
        recording = runCatching {
            pending.start(main) { event ->
                if (event is VideoRecordEvent.Finalize) {
                    recording = null
                    change { it.copy(recordingSince = null) }
                    val kept = !event.hasError() || event.outputResults.outputUri != Uri.EMPTY
                    notice(if (kept) "SAVED TO GALLERY" else "COULDN'T SAVE")
                }
            }
        }.getOrNull()
        if (recording == null) {
            change { it.copy(recordingSince = null) }
            notice("COULDN'T RECORD")
        }
    }
}

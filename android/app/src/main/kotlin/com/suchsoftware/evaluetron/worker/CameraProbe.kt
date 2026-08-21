package com.suchsoftware.evaluetron.worker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Reports what this handset can actually see, and how long it takes to change
 * its mind about which lens it is looking through.
 *
 * Both answers are per-device and neither can be inferred from the model name
 * or the Android version: two handsets of the same year and OS disagree about
 * concurrent capture. So the node measures itself and advertises the result
 * rather than being described by a table maintained elsewhere.
 *
 * Raw characteristics are reported here and angles are derived on the Dart
 * side, which keeps the arithmetic testable without a handset attached.
 */
object CameraProbe {
    private const val OPEN_TIMEOUT_SECONDS = 5L

    /**
     * Lens geometry and concurrency support.
     *
     * Deliberately does not require camera permission: characteristics are
     * readable without it, so a node can describe itself during enrollment
     * before anyone has been asked to grant anything.
     */
    fun inspect(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return unavailable("This device exposes no camera service.")

        return try {
            val ids = manager.cameraIdList
            val lenses = ids.mapNotNull { id -> describe(manager, id) }
            mapOf(
                "available" to lenses.isNotEmpty(),
                "lenses" to lenses,
                "concurrentSupported" to declaresConcurrent(context),
                "concurrentSets" to concurrentSets(manager),
                "hardwareLevel" to primaryHardwareLevel(manager, ids),
                "detail" to null,
            )
        } catch (error: CameraAccessException) {
            unavailable("Camera characteristics were unreadable: ${error.reason}")
        }
    }

    /**
     * Times a full close-one, open-the-other cycle.
     *
     * This is the number that sets the blind window for any node whose HAL
     * refuses to run two lenses together, so it is measured rather than
     * assumed. Requires camera permission, because it genuinely opens the
     * devices, which is why it is a separate call from [inspect].
     */
    fun measureSwitch(
        context: Context,
        firstId: String,
        secondId: String,
        rounds: Int,
    ): Map<String, Any?> {
        if (!hasCameraPermission(context)) {
            throw IllegalStateException("Camera permission has not been granted.")
        }
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: throw IllegalStateException("This device exposes no camera service.")

        val thread = HandlerThread("evaluetron-camera-probe").apply { start() }
        val handler = Handler(thread.looper)
        val samples = mutableListOf<Double>()
        try {
            // The first open pays for a cold HAL start and does not describe
            // the steady-state cost, so it is taken and discarded.
            openThenClose(manager, firstId, handler)
            repeat(rounds.coerceIn(1, 20)) { round ->
                val target = if (round % 2 == 0) secondId else firstId
                val startedNs = SystemClock.elapsedRealtimeNanos()
                openThenClose(manager, target, handler)
                val elapsedNs = SystemClock.elapsedRealtimeNanos() - startedNs
                samples += elapsedNs / 1_000_000.0
            }
        } finally {
            thread.quitSafely()
        }
        return mapOf("samplesMs" to samples)
    }

    private fun openThenClose(manager: CameraManager, id: String, handler: Handler) {
        val opened = CountDownLatch(1)
        var device: CameraDevice? = null
        var failure: String? = null

        manager.openCamera(
            id,
            object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    device = camera
                    opened.countDown()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    failure = "Camera $id disconnected during the probe."
                    opened.countDown()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    failure = "Camera $id reported error $error during the probe."
                    opened.countDown()
                }
            },
            handler,
        )

        if (!opened.await(OPEN_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw IllegalStateException("Camera $id did not open within ${OPEN_TIMEOUT_SECONDS}s.")
        }
        failure?.let { throw IllegalStateException(it) }
        // Closing is part of the switch cost and belongs inside the timed span,
        // because an alternating node pays it every time it changes arc.
        device?.close()
    }

    private fun describe(manager: CameraManager, id: String): Map<String, Any?>? {
        val characteristics = try {
            manager.getCameraCharacteristics(id)
        } catch (error: CameraAccessException) {
            return null
        }
        val focal = characteristics
            .get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            ?.firstOrNull()
            ?: return null
        val size = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            ?: return null

        return mapOf(
            "id" to id,
            "facing" to facingName(characteristics.get(CameraCharacteristics.LENS_FACING)),
            "focalLengthMm" to focal.toDouble(),
            "sensorWidthMm" to size.width.toDouble(),
            "sensorHeightMm" to size.height.toDouble(),
        )
    }

    private fun facingName(facing: Int?): String = when (facing) {
        CameraCharacteristics.LENS_FACING_FRONT -> "front"
        CameraCharacteristics.LENS_FACING_BACK -> "back"
        CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
        else -> "unknown"
    }

    private fun declaresConcurrent(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_CONCURRENT)

    /**
     * The combinations the HAL will genuinely run together.
     *
     * The feature flag on its own promises only that the primary front and back
     * pair works, so a node must not assume any wider lens participates. This
     * is the one answer that cannot be obtained without running on the device.
     */
    private fun concurrentSets(manager: CameraManager): List<List<String>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            manager.concurrentCameraIds.map { set -> set.toList().sorted() }
        } catch (error: CameraAccessException) {
            emptyList()
        }
    }

    private fun primaryHardwareLevel(manager: CameraManager, ids: Array<String>): String {
        val first = ids.firstOrNull() ?: return "unknown"
        val level = try {
            manager.getCameraCharacteristics(first)
                .get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
        } catch (error: CameraAccessException) {
            null
        }
        return when (level) {
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "legacy"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "limited"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "full"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "level3"
            CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "external"
            else -> "unknown"
        }
    }

    private fun hasCameraPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private fun unavailable(detail: String): Map<String, Any?> = mapOf(
        "available" to false,
        "lenses" to emptyList<Map<String, Any?>>(),
        "concurrentSupported" to false,
        "concurrentSets" to emptyList<List<String>>(),
        "hardwareLevel" to "unknown",
        "detail" to detail,
    )
}

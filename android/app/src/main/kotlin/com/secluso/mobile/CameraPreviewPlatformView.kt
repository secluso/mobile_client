//! SPDX-License-Identifier: GPL-3.0-or-later

package com.secluso.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.HandlerThread
import android.util.Range
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.View
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class CameraPreviewPlatformView(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val facing: Int,
    private val width: Int,
    private val height: Int,
    private val fpsMin: Int,
    private val fpsMax: Int
) : PlatformView {
    private val textureView = TextureView(context)
    private val methodChannel = MethodChannel(messenger, "secluso_camera_preview_$viewId")
    private val cameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewSurface: Surface? = null
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var disposed = false
    private var surfaceAvailable = false

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "stop" -> {
                    surfaceAvailable = false
                    closeCamera()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(texture: SurfaceTexture, w: Int, h: Int) {
                surfaceAvailable = true
                start(texture)
            }

            override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, w: Int, h: Int) = Unit

            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                surfaceAvailable = false
                closeCamera()
                return true
            }

            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
        }
    }

    override fun getView(): View = textureView

    override fun dispose() {
        disposed = true
        surfaceAvailable = false
        closeCamera()
        methodChannel.setMethodCallHandler(null)
    }

    private fun start(texture: SurfaceTexture) {
        val validationError = validateConfiguration()
        if (validationError != null) {
            reportError(validationError)
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            reportError("Camera permission is required.")
            return
        }

        try {
            val cameraId = matchingCameraId()
            texture.setDefaultBufferSize(width, height)
            previewSurface = Surface(texture)
            cameraThread = HandlerThread("secluso-camera-preview").also { it.start() }
            cameraHandler = Handler(cameraThread!!.looper)
            cameraManager.openCamera(cameraId, cameraStateCallback, cameraHandler)
        } catch (error: Exception) {
            reportError("Unable to start the selected camera preview.")
            closeCamera()
        }
    }

    private fun validateConfiguration(): String? {
        if (facing != 0 && facing != 1) return "Unsupported camera lens."
        if (width <= 0 || height <= 0) return "Invalid preview resolution."
        if (fpsMin <= 0 || fpsMax <= 0 || fpsMin > fpsMax) {
            return "Invalid preview frame-rate range."
        }
        return null
    }

    private fun matchingCameraId(): String {
        val requestedLens =
            if (facing == 1) CameraCharacteristics.LENS_FACING_FRONT
            else CameraCharacteristics.LENS_FACING_BACK
        val requestedSize = Size(width, height)
        val requestedFps = Range(fpsMin, fpsMax)

        for (cameraId in cameraManager.cameraIdList) {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            if (characteristics.get(CameraCharacteristics.LENS_FACING) != requestedLens) continue

            val sizes = characteristics
                .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(SurfaceTexture::class.java)
                ?.toSet()
                .orEmpty()
            val fpsRanges = characteristics
                .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.toSet()
                .orEmpty()
            if (requestedSize !in sizes || requestedFps !in fpsRanges) {
                continue
            }
            return cameraId
        }
        throw IllegalArgumentException("No camera supports the selected lens and mode.")
    }

    private val cameraStateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            if (disposed || !surfaceAvailable) {
                camera.close()
                return
            }
            cameraDevice = camera
            createSession(camera)
        }

        override fun onDisconnected(camera: CameraDevice) {
            camera.close()
            cameraDevice = null
            if (surfaceAvailable) {
                reportError("Camera preview was disconnected.")
            }
        }

        override fun onError(camera: CameraDevice, error: Int) {
            camera.close()
            cameraDevice = null
            if (surfaceAvailable) {
                reportError("Camera preview failed.")
            }
        }
    }

    private fun createSession(camera: CameraDevice) {
        val surface = previewSurface ?: return
        try {
            camera.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (disposed || !surfaceAvailable) {
                            session.close()
                            return
                        }
                        captureSession = session
                        try {
                            val request = camera.createCaptureRequest(
                                CameraDevice.TEMPLATE_RECORD
                            ).apply {
                                addTarget(surface)
                                set(
                                    CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                                    Range(fpsMin, fpsMax)
                                )
                            }.build()
                            session.setRepeatingRequest(request, null, cameraHandler)
                        } catch (error: Exception) {
                            reportError("Unable to apply the selected camera settings.")
                            closeCamera()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        reportError("Unable to configure the selected camera preview.")
                        closeCamera()
                    }
                },
                cameraHandler
            )
        } catch (error: Exception) {
            reportError("Unable to configure the selected camera preview.")
            closeCamera()
        }
    }

    private fun reportError(message: String) {
        if (!disposed) {
            textureView.post { methodChannel.invokeMethod("onError", message) }
        }
    }

    @Synchronized
    private fun closeCamera() {
        try {
            captureSession?.close()
        } finally {
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            previewSurface?.release()
            previewSurface = null
            cameraThread?.quitSafely()
            cameraThread = null
            cameraHandler = null
        }
    }
}

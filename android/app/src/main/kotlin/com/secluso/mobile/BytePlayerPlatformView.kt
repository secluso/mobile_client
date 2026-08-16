//! SPDX-License-Identifier: GPL-3.0-or-later

package com.secluso.mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.core.view.isVisible
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue

class BytePlayerPlatformView(
    ctx: Context,
    streamId: Int,
    messenger: BinaryMessenger
) : PlatformView {

    private val container: FrameLayout
    private val player: ExoPlayer
    private val spinner: ProgressBar
    private val methodChannel: MethodChannel
    private val textureView: TextureView
    private var thumbnailSent = false

    init {
        methodChannel = MethodChannel(messenger, "byte_player_view_$streamId")
        Log.d("BytePV", "BytePlayerPlatformView ctor for stream $streamId")

        // Grab the shared byte‐queue
        val q: LinkedBlockingQueue<ByteArray> =
            MainActivity.queue(streamId) ?: error("Queue missing")

        // Build an ExoPlayer instance
        val dsFactory = DataSource.Factory { ByteQueueDataSource(q) }
        val mediaSrc = ProgressiveMediaSource.Factory(dsFactory)
            .createMediaSource(MediaItem.fromUri("queue://dummy"))

        // The default load control buffers 2.5s of media before the first frame
        // This is a live feed: start s soon as a fragment is decodable. Keep buffer shallow!
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs = */ 1_000,
                /* maxBufferMs = */ 10_000,
                /* bufferForPlaybackMs = */ 250,
                /* bufferForPlaybackAfterRebufferMs = */ 500,
            )
            .build()

        player = ExoPlayer.Builder(ctx)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dsFactory))
            .setLoadControl(loadControl)
            .build().apply {
                setMediaSource(mediaSrc, 0)
                playWhenReady = true
            }

        // Create a TextureView for video output
        textureView = TextureView(ctx).apply {
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(
                    surfaceTexture: SurfaceTexture,
                    width: Int,
                    height: Int
                ) {
                    Log.d("BytePV", "texture available, attaching to player")
                    player.setVideoSurface(Surface(surfaceTexture))
                    // Now that the surface exists, prepare the stream
                    player.prepare()
                }

                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture) = true
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {
                    maybeSendThumbnail()
                }
            }
        }

        // A little spinner while the first frame buffers
        spinner = ProgressBar(ctx).apply { isIndeterminate = true }

        container = FrameLayout(ctx).apply {
            setBackgroundColor(0xFF000000.toInt())
            addView(
                textureView, FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            addView(spinner, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER })
        }

        // Listen for first‐frame
        player.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                Log.d("BytePV", "first frame rendered")
                spinner.isVisible = false
                maybeSendThumbnail()
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                val width = videoSize.width
                val height = videoSize.height
                val aspectRatio = width.toFloat() / height

                Log.d("NativeStream", "Video size: $width x $height ($aspectRatio)")

                // Send it to Flutter via MethodChannel
                methodChannel.invokeMethod("onAspectRatio", aspectRatio)
            }
          


            override fun onPlayerError(error: PlaybackException) {
                Log.e("BytePV", "PLAYER ERROR", error)
            }
        })
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        player.release()
    }

    private fun maybeSendThumbnail() {
        if (thumbnailSent) {
            return
        }
        val bitmap = textureView.bitmap ?: return
        try {
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            thumbnailSent = true
            methodChannel.invokeMethod("onThumbnailBytes", output.toByteArray())
        } catch (e: Exception) {
            Log.w("BytePV", "thumbnail capture failed", e)
        }
    }
}

//! SPDX-License-Identifier: GPL-3.0-or-later

package com.secluso.mobile

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val values = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return CameraPreviewPlatformView(
            context = context,
            viewId = id,
            messenger = messenger,
            facing = values.intValue("facing"),
            width = values.intValue("width"),
            height = values.intValue("height"),
            fpsMin = values.intValue("fpsMin"),
            fpsMax = values.intValue("fpsMax")
        )
    }

    private fun Map<*, *>.intValue(name: String): Int {
        return (this[name] as? Number)?.toInt() ?: Int.MIN_VALUE
    }
}

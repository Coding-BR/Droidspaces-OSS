package com.anland.consumer

import android.view.Surface

object MainActivity {
    @JvmStatic external fun nativeStart(surface: Surface)
    @JvmStatic external fun nativeStop()
    @JvmStatic external fun nativeSendTouch(action: Int, x: Float, y: Float, pointerId: Int)
    @JvmStatic external fun nativeSendTouchFrame()
    @JvmStatic external fun nativeSendKey(action: Int, keycode: Int)
    @JvmStatic external fun nativeSendMouseMotion(x: Float, y: Float, dx: Float, dy: Float)
    @JvmStatic external fun nativeSendMouseButton(button: Int, pressed: Boolean)
    @JvmStatic external fun nativeSendMouseScroll(axis: Int, value: Float)
    @JvmStatic external fun nativeSetRefreshRate(hz: Float)
}

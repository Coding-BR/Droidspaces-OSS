package com.droidspaces.app.ui.component

import android.view.MotionEvent
import android.view.PointerIcon
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.anland.consumer.MainActivity

@Composable
fun AnlandView(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { context ->
            SurfaceView(context).apply {
                // Hide cursor (so we don't display Android's default mouse pointer overlaying Linux's)
                pointerIcon = PointerIcon.getSystemIcon(context, PointerIcon.TYPE_NULL)

                holder.addCallback(object : android.view.SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: android.view.SurfaceHolder) {
                        MainActivity.nativeStart(holder.surface)
                        // Seed refresh rate
                        val d = display
                        if (d != null) {
                            MainActivity.nativeSetRefreshRate(d.refreshRate)
                        }
                    }

                    override fun surfaceChanged(
                        holder: android.view.SurfaceHolder,
                        format: Int,
                        width: Int,
                        height: Int
                    ) {
                        MainActivity.nativeStart(holder.surface)
                    }

                    override fun surfaceDestroyed(holder: android.view.SurfaceHolder) {
                        MainActivity.nativeStop()
                    }
                })

                // Set up touch and mouse input handlers
                setOnTouchListener { _, event ->
                    handleMotionEvent(event)
                    true
                }

                setOnGenericMotionListener { _, event ->
                    handleGenericMotionEvent(event)
                    true
                }

                // Allow focus
                isFocusable = true
                isFocusableInTouchMode = true
                requestFocus()
            }
        },
        modifier = modifier
    )
}

private fun handleMotionEvent(event: MotionEvent) {
    val action = event.actionMasked
    val pointerIdx = event.actionIndex
    val pointerId = event.getPointerId(pointerIdx)

    // Check if it is a mouse event
    val source = event.source
    val isMouse = (source and android.view.InputDevice.SOURCE_TOUCHSCREEN) != android.view.InputDevice.SOURCE_TOUCHSCREEN &&
            (source and android.view.InputDevice.SOURCE_MOUSE) == android.view.InputDevice.SOURCE_MOUSE

    if (isMouse) {
        // Mouse movement
        var dx = 0f
        var dy = 0f
        if (event.historySize > 0) {
            val last = event.historySize - 1
            dx = event.x - event.getHistoricalX(0, last)
            dy = event.y - event.getHistoricalY(0, last)
        }
        MainActivity.nativeSendMouseMotion(event.x, event.y, dx, dy)

        // Mouse buttons
        val currentBS = event.buttonState
        val buttonMap = arrayOf(
            intArrayOf(MotionEvent.BUTTON_PRIMARY, 0x110), // BTN_LEFT
            intArrayOf(MotionEvent.BUTTON_SECONDARY, 0x111), // BTN_RIGHT
            intArrayOf(MotionEvent.BUTTON_TERTIARY, 0x112), // BTN_MIDDLE
            intArrayOf(MotionEvent.BUTTON_BACK, 0x113), // BTN_SIDE
            intArrayOf(MotionEvent.BUTTON_FORWARD, 0x114) // BTN_EXTRA
        )
        for (btn in buttonMap) {
            if (action == MotionEvent.ACTION_BUTTON_PRESS && event.actionButton == btn[0]) {
                MainActivity.nativeSendMouseButton(btn[1], true)
            } else if (action == MotionEvent.ACTION_BUTTON_RELEASE && event.actionButton == btn[0]) {
                MainActivity.nativeSendMouseButton(btn[1], false)
            }
        }
    } else {
        // Touch events
        when (action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                MainActivity.nativeSendTouch(0, event.getX(pointerIdx), event.getY(pointerIdx), pointerId)
                MainActivity.nativeSendTouchFrame()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                MainActivity.nativeSendTouch(1, event.getX(pointerIdx), event.getY(pointerIdx), pointerId)
                MainActivity.nativeSendTouchFrame()
            }
            MotionEvent.ACTION_MOVE -> {
                for (i in 0 until event.pointerCount) {
                    MainActivity.nativeSendTouch(2, event.getX(i), event.getY(i), event.getPointerId(i))
                }
                MainActivity.nativeSendTouchFrame()
            }
            MotionEvent.ACTION_CANCEL -> {
                for (i in 0 until event.pointerCount) {
                    MainActivity.nativeSendTouch(1, event.getX(i), event.getY(i), event.getPointerId(i))
                }
                MainActivity.nativeSendTouchFrame()
            }
        }
    }
}

private fun handleGenericMotionEvent(event: MotionEvent): Boolean {
    val action = event.actionMasked
    if (action == MotionEvent.ACTION_HOVER_MOVE) {
        MainActivity.nativeSendMouseMotion(
            event.x, event.y,
            event.getAxisValue(MotionEvent.AXIS_RELATIVE_X),
            event.getAxisValue(MotionEvent.AXIS_RELATIVE_Y)
        )
        return true
    }
    if (action == MotionEvent.ACTION_SCROLL) {
        val vScroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL)
        val hScroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
        if (vScroll != 0f) {
            MainActivity.nativeSendMouseScroll(0, -vScroll * 10)
        }
        if (hScroll != 0f) {
            MainActivity.nativeSendMouseScroll(1, hScroll * 10)
        }
        return true
    }
    return false
}

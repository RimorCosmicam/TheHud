package com.thehud.touchpad

/** What the pad's fingers meant, as MiniMate's recognizer reports it. */
sealed interface GestureEvent {
    data class Move(val dx: Int, val dy: Int, val isDragging: Boolean = false) : GestureEvent
    data class Click(val button: Byte, val down: Boolean) : GestureEvent
    /** Scroll steps: positive when the fingers push the content up (natural scrolling). */
    data class Scroll(val vScroll: Int, val hScroll: Int) : GestureEvent
    data class ScrollFling(val velocityX: Float, val velocityY: Float) : GestureEvent
    data class Pinch(val scaleFactor: Float) : GestureEvent
    data object TapClick : GestureEvent
    data object RightClick : GestureEvent
    data object DoubleTapDragStart : GestureEvent
    data object DragEnd : GestureEvent

    companion object {
        const val BUTTON_LEFT: Byte = 1
    }
}

/** The pad's feel; MiniMate's defaults, which were tuned on a Flip's cover screen. */
data class TouchpadSettings(
    val trackingSpeed: Float = 1.0f,
    val acceleration: Float = 1.15f,
    val scrollSpeed: Float = 1.0f,
    val naturalScrolling: Boolean = true,
    val invertCursorY: Boolean = false,
    val momentumScrolling: Boolean = true,
    val momentumFriction: Float = 0.92f,
    val tapToClick: Boolean = true,
    val twoFingerRightClick: Boolean = true,
    val doubleTapDrag: Boolean = true,
    val edgeMarginDp: Float = 12f,
)

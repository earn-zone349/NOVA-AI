package com.nova.ai.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.nova.ai.R
import com.nova.ai.logging.NovaLogger
import kotlin.math.hypot

/** How a button of the panel looks. */
internal enum class PanelStyle { NORMAL, PRIMARY }

/** One button of the panel. */
internal data class PanelButton(
    val label: String,
    val style: PanelStyle = PanelStyle.NORMAL,
    val onClick: () -> Unit
)

/** What the overlay tells its owner. All calls happen on the main thread. */
internal interface BubbleOverlayCallbacks {
    fun onBubbleTap()
    fun onBubbleLongPress()
    fun onStopBadgeTap()
}

/**
 * The floating bubble and its panel, drawn as two small overlay windows over every app.
 * The bubble can be dragged; when let go it sticks to the nearest screen edge and the place is
 * remembered. A red stop badge sits on the bubble while NOVA is busy. The panel shows a status
 * line, a question with choices, or the menu. Only the small areas of the bubble and the panel
 * take touches; everything else on the screen works as usual. Use from the main thread.
 */
internal class BubbleOverlay(
    context: Context,
    private val prefs: BubblePrefs,
    private val callbacks: BubbleOverlayCallbacks
) {

    private val appContext: Context = context.applicationContext
    private val windowManager: WindowManager =
        appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private val density: Float = appContext.resources.displayMetrics.density

    private val bubbleSize: Int = dp(BUBBLE_DP)
    private val boxSize: Int = dp(BOX_DP)
    private val badgeSize: Int = dp(BADGE_DP)
    private val sideShift: Int = boxSize - bubbleSize

    private val box = FrameLayout(appContext)
    private val ring = View(appContext)
    private val bubble = TextView(appContext)
    private val badge = TextView(appContext)

    private val boxParams: WindowManager.LayoutParams = WindowManager.LayoutParams(
        boxSize,
        boxSize,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START }

    private var attached: Boolean = false
    private var layoutRight: Boolean = true
    private var state: BubbleState = BubbleState.IDLE
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var topInset: Int = 0

    private var pulse: ValueAnimator? = null
    private var snap: ValueAnimator? = null

    private var panelView: LinearLayout? = null
    private var panelText: TextView? = null
    private var panelHasButtons: Boolean = false
    private var panelParams: WindowManager.LayoutParams? = null
    private var panelDismiss: (() -> Unit)? = null
    private var panelHideTask: Runnable? = null

    init {
        buildBubble()
        applyState(BubbleState.IDLE)
    }

    // ---------------------------------------------------------------- showing and hiding

    /** Puts the bubble on the screen. Returns false if Android refused (for example no permission). */
    fun show(): Boolean {
        if (attached) return true
        readScreen()
        placeFromPrefs()
        return try {
            windowManager.addView(box, boxParams)
            attached = true
            true
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not show the bubble", e)
            false
        }
    }

    /** Removes the bubble and the panel. */
    fun hide() {
        hidePanel()
        stopPulse()
        snap?.cancel()
        snap = null
        handler.removeCallbacksAndMessages(null)
        if (attached) {
            try {
                windowManager.removeView(box)
            } catch (e: Exception) {
                NovaLogger.w(TAG, "Could not remove the bubble", e)
            }
            attached = false
        }
    }

    /** Call when the screen was turned or the display changed. */
    fun onConfigurationChanged() {
        if (!attached) return
        hidePanel()
        readScreen()
        placeFromPrefs()
        updateBox()
    }

    // ---------------------------------------------------------------- state

    /** Shows [newState] on the bubble. */
    fun setState(newState: BubbleState) {
        if (newState == state) return
        applyState(newState)
    }

    private fun applyState(newState: BubbleState) {
        state = newState
        bubble.text = when (newState) {
            BubbleState.IDLE, BubbleState.LISTENING -> "🎙️"
            BubbleState.SPEAKING -> "🔊"
            BubbleState.THINKING -> "⏳"
            BubbleState.STOPPED -> "⏸️"
        }
        val color: Int = when (newState) {
            BubbleState.IDLE -> COLOR_IDLE
            BubbleState.LISTENING -> COLOR_LISTENING
            BubbleState.SPEAKING -> COLOR_SPEAKING
            BubbleState.THINKING -> COLOR_THINKING
            BubbleState.STOPPED -> COLOR_STOPPED
        }
        bubble.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(dp(2), Color.WHITE)
        }
        bubble.contentDescription = appContext.getString(
            when (newState) {
                BubbleState.IDLE -> R.string.bub_desc_idle
                BubbleState.LISTENING -> R.string.bub_desc_listening
                BubbleState.SPEAKING -> R.string.bub_desc_speaking
                BubbleState.THINKING -> R.string.bub_desc_thinking
                BubbleState.STOPPED -> R.string.bub_desc_stopped
            }
        )
        badge.visibility = if (BubbleStateMapper.showsStopBadge(newState)) View.VISIBLE else View.GONE
        box.alpha = if (newState == BubbleState.IDLE) IDLE_ALPHA else 1f
        if (newState == BubbleState.LISTENING) startPulse() else stopPulse()
    }

    // ---------------------------------------------------------------- panel

    /**
     * Shows a line of text in the panel. While a text-only panel is open its text is replaced in
     * place (used for the live words while listening). With [autoHideMs] above 0 it closes by itself.
     */
    fun showStatus(text: String, kind: MessageKind?, autoHideMs: Long) {
        val label: String = decorate(text, kind)
        val existing: TextView? = panelText
        if (panelView != null && !panelHasButtons && existing != null) {
            existing.text = label
            repositionPanel()
            scheduleAutoHide(autoHideMs)
            return
        }
        showPanel(label, emptyList(), autoHideMs, null)
    }

    /**
     * Shows [text] with [buttons]. [onDismiss] runs when the panel is closed without tapping a
     * button (a tap outside, or the time ran out). With [autoHideMs] above 0 the panel closes by itself.
     */
    fun showPanel(text: String, buttons: List<PanelButton>, autoHideMs: Long, onDismiss: (() -> Unit)?) {
        if (!attached) return
        closePanelWindow()
        panelDismiss = onDismiss
        panelHasButtons = buttons.isNotEmpty()

        val dark: Boolean = isDarkMode()
        val root = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(14), dp(16), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(if (dark) PANEL_DARK else PANEL_LIGHT)
            }
            elevation = dp(8).toFloat()
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            setOnTouchListener { _, event ->
                if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                    dismissByUser()
                    true
                } else {
                    false
                }
            }
        }
        val title = TextView(appContext).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(if (dark) TEXT_ON_DARK else TEXT_ON_LIGHT)
            maxLines = MAX_PANEL_LINES
        }
        root.addView(title)
        for (button in buttons) root.addView(buildButton(button, dark))

        panelView = root
        panelText = title
        panelParams = WindowManager.LayoutParams(
            panelWidth(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START }
        positionPanel()
        try {
            windowManager.addView(root, panelParams)
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Could not show the panel", e)
            panelView = null
            panelText = null
            panelParams = null
            panelDismiss = null
            return
        }
        scheduleAutoHide(autoHideMs)
    }

    /** Closes the panel without telling anyone. */
    fun hidePanel() {
        panelDismiss = null
        closePanelWindow()
    }

    private fun dismissByUser() {
        val callback: (() -> Unit)? = panelDismiss
        panelDismiss = null
        closePanelWindow()
        callback?.invoke()
    }

    private fun closePanelWindow() {
        panelHideTask?.let { handler.removeCallbacks(it) }
        panelHideTask = null
        val view: View? = panelView
        panelView = null
        panelText = null
        panelParams = null
        panelHasButtons = false
        if (view != null) {
            try {
                windowManager.removeView(view)
            } catch (e: Exception) {
                NovaLogger.w(TAG, "Could not remove the panel", e)
            }
        }
    }

    private fun scheduleAutoHide(autoHideMs: Long) {
        panelHideTask?.let { handler.removeCallbacks(it) }
        panelHideTask = null
        if (autoHideMs <= 0L) return
        val task = Runnable { dismissByUser() }
        panelHideTask = task
        handler.postDelayed(task, autoHideMs)
    }

    private fun buildButton(button: PanelButton, dark: Boolean): TextView {
        val primary: Boolean = button.style == PanelStyle.PRIMARY
        val fill: Int = when {
            primary -> COLOR_IDLE
            dark -> BUTTON_DARK
            else -> BUTTON_LIGHT
        }
        val textColor: Int = when {
            primary -> Color.WHITE
            dark -> TEXT_ON_DARK
            else -> COLOR_IDLE
        }
        return TextView(appContext).apply {
            text = button.label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(textColor)
            gravity = Gravity.CENTER
            minHeight = dp(MIN_TOUCH_DP)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            background = RippleDrawable(
                ColorStateList.valueOf(RIPPLE_COLOR),
                roundedFill(fill),
                roundedFill(Color.WHITE)
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
            setOnClickListener {
                panelDismiss = null
                closePanelWindow()
                button.onClick()
            }
        }
    }

    private fun roundedFill(color: Int): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dp(14).toFloat()
        setColor(color)
    }

    private fun decorate(text: String, kind: MessageKind?): String = when (kind) {
        MessageKind.DONE -> "✅ $text"
        MessageKind.ERROR -> "⚠️ $text"
        MessageKind.INFO, null -> text
    }

    private fun panelWidth(): Int =
        minOf(dp(PANEL_MAX_DP), screenWidth - 2 * dp(PANEL_GAP_DP))

    // Measures the panel and puts its window next to the bubble.
    private fun positionPanel() {
        val view: View = panelView ?: return
        val params: WindowManager.LayoutParams = panelParams ?: return
        view.measure(
            View.MeasureSpec.makeMeasureSpec(params.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val point: BubblePoint = BubbleGeometry.panelPosition(
            boxX = boxParams.x,
            boxY = boxParams.y,
            boxWidth = boxSize,
            boxHeight = boxSize,
            panelWidth = params.width,
            panelHeight = view.measuredHeight,
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            gap = dp(PANEL_GAP_DP)
        )
        params.x = point.x
        params.y = point.y
    }

    private fun repositionPanel() {
        val view: View = panelView ?: return
        val params: WindowManager.LayoutParams = panelParams ?: return
        positionPanel()
        try {
            windowManager.updateViewLayout(view, params)
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not move the panel", e)
        }
    }

    // ---------------------------------------------------------------- building the bubble

    private fun buildBubble() {
        ring.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.TRANSPARENT)
            setStroke(dp(3), COLOR_LISTENING)
        }
        ring.alpha = 0f

        bubble.apply {
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            includeFontPadding = false
            isClickable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            setOnClickListener { callbacks.onBubbleTap() }
            setOnLongClickListener {
                callbacks.onBubbleLongPress()
                true
            }
            setOnTouchListener(DragListener())
        }

        badge.apply {
            text = "⏹"
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            background = InsetDrawable(
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(COLOR_BADGE)
                },
                dp(BADGE_INSET_DP)
            )
            contentDescription = appContext.getString(R.string.bub_desc_badge)
            visibility = View.GONE
            setOnClickListener { callbacks.onStopBadgeTap() }
        }

        box.addView(ring, FrameLayout.LayoutParams(bubbleSize, bubbleSize))
        box.addView(bubble, FrameLayout.LayoutParams(bubbleSize, bubbleSize))
        box.addView(badge, FrameLayout.LayoutParams(badgeSize, badgeSize))
        layoutForSide(true)
    }

    // The bubble sits in the corner of the box that touches the screen edge; the badge in the opposite top corner.
    private fun layoutForSide(right: Boolean) {
        layoutRight = right
        val bubbleGravity: Int = Gravity.BOTTOM or (if (right) Gravity.END else Gravity.START)
        val badgeGravity: Int = Gravity.TOP or (if (right) Gravity.START else Gravity.END)
        (ring.layoutParams as FrameLayout.LayoutParams).gravity = bubbleGravity
        (bubble.layoutParams as FrameLayout.LayoutParams).gravity = bubbleGravity
        (badge.layoutParams as FrameLayout.LayoutParams).gravity = badgeGravity
        box.requestLayout()
    }

    // ---------------------------------------------------------------- the pulse around the bubble while listening

    private fun startPulse() {
        if (pulse != null) return
        pulse = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = PULSE_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animator ->
                val progress: Float = animator.animatedValue as Float
                val scale: Float = 1f + PULSE_GROWTH * progress
                ring.scaleX = scale
                ring.scaleY = scale
                ring.alpha = PULSE_ALPHA * (1f - progress)
            }
            start()
        }
    }

    private fun stopPulse() {
        pulse?.cancel()
        pulse = null
        ring.alpha = 0f
        ring.scaleX = 1f
        ring.scaleY = 1f
    }

    // ---------------------------------------------------------------- position

    private fun readScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            screenWidth = bounds.width()
            screenHeight = bounds.height()
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(metrics)
            screenWidth = metrics.widthPixels
            screenHeight = metrics.heightPixels
        }
        val resource: Int = appContext.resources.getIdentifier("status_bar_height", "dimen", "android")
        topInset = if (resource > 0) appContext.resources.getDimensionPixelSize(resource) else 0
    }

    private fun placeFromPrefs() {
        val right: Boolean = prefs.isRightSide()
        layoutForSide(right)
        boxParams.x = if (right) maxOf(0, screenWidth - boxSize) else 0
        boxParams.y = BubbleGeometry.fractionToY(prefs.yFraction(), boxSize, screenHeight, topInset)
    }

    private fun updateBox() {
        if (!attached) return
        try {
            windowManager.updateViewLayout(box, boxParams)
        } catch (e: Exception) {
            NovaLogger.w(TAG, "Could not move the bubble", e)
        }
    }

    // The left edge of the bubble itself (not of the whole box) on the screen.
    private fun bubbleLeft(): Int = if (layoutRight) boxParams.x + sideShift else boxParams.x

    private fun finishDrag() {
        val right: Boolean = BubbleGeometry.isRightSide(bubbleLeft(), bubbleSize, screenWidth)
        if (right != layoutRight) {
            // Flipping the corner moves the bubble inside the box; move the box so the bubble stays where it is.
            boxParams.x += if (right) -sideShift else sideShift
            layoutForSide(right)
        }
        val targetX: Int = if (right) maxOf(0, screenWidth - boxSize) else 0
        snap?.cancel()
        snap = ValueAnimator.ofInt(boxParams.x, targetX).apply {
            duration = SNAP_MS
            addUpdateListener { animator ->
                boxParams.x = animator.animatedValue as Int
                updateBox()
            }
            start()
        }
        prefs.save(right, BubbleGeometry.yToFraction(boxParams.y, boxSize, screenHeight, topInset))
    }

    // ---------------------------------------------------------------- touch: tap, long press, drag

    private inner class DragListener : View.OnTouchListener {
        private val slop: Int = ViewConfiguration.get(appContext).scaledTouchSlop
        private var downX: Float = 0f
        private var downY: Float = 0f
        private var startX: Int = 0
        private var startY: Int = 0
        private var dragging: Boolean = false
        private var longPressed: Boolean = false

        private val longPressTask = Runnable {
            if (!dragging) {
                longPressed = true
                bubble.performLongClick()
            }
        }

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = boxParams.x
                    startY = boxParams.y
                    dragging = false
                    longPressed = false
                    snap?.cancel()
                    handler.postDelayed(longPressTask, ViewConfiguration.getLongPressTimeout().toLong())
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx: Float = event.rawX - downX
                    val dy: Float = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > slop) {
                        dragging = true
                        handler.removeCallbacks(longPressTask)
                        hidePanel()
                    }
                    if (dragging) {
                        boxParams.x = BubbleGeometry.clampX(startX + dx.toInt(), boxSize, screenWidth)
                        boxParams.y = BubbleGeometry.clampY(startY + dy.toInt(), boxSize, screenHeight, topInset)
                        updateBox()
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    handler.removeCallbacks(longPressTask)
                    if (dragging) {
                        finishDrag()
                    } else if (!longPressed) {
                        view.performClick()
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressTask)
                    if (dragging) finishDrag()
                    return true
                }
            }
            return false
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun isDarkMode(): Boolean =
        (appContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun dp(value: Int): Int = (value * density + 0.5f).toInt()

    private companion object {
        const val TAG: String = "BubbleOverlay"

        const val BUBBLE_DP: Int = 56
        const val BADGE_DP: Int = 44
        const val BADGE_INSET_DP: Int = 6
        const val BOX_DP: Int = 84
        const val PANEL_MAX_DP: Int = 300
        const val PANEL_GAP_DP: Int = 12
        const val MIN_TOUCH_DP: Int = 44
        const val MAX_PANEL_LINES: Int = 6

        const val IDLE_ALPHA: Float = 0.85f
        const val PULSE_MS: Long = 1100L
        const val PULSE_GROWTH: Float = 0.45f
        const val PULSE_ALPHA: Float = 0.7f
        const val SNAP_MS: Long = 160L

        val COLOR_IDLE: Int = Color.parseColor("#1E5BFF")
        val COLOR_LISTENING: Int = Color.parseColor("#1B9E5A")
        val COLOR_SPEAKING: Int = Color.parseColor("#7B4DFF")
        val COLOR_THINKING: Int = Color.parseColor("#F29900")
        val COLOR_STOPPED: Int = Color.parseColor("#C62828")
        val COLOR_BADGE: Int = Color.parseColor("#D32F2F")

        val PANEL_LIGHT: Int = Color.parseColor("#FFFFFF")
        val PANEL_DARK: Int = Color.parseColor("#2B2D31")
        val TEXT_ON_LIGHT: Int = Color.parseColor("#202124")
        val TEXT_ON_DARK: Int = Color.parseColor("#E8EAED")
        val BUTTON_LIGHT: Int = Color.parseColor("#E8EEF9")
        val BUTTON_DARK: Int = Color.parseColor("#3C4043")
        val RIPPLE_COLOR: Int = Color.parseColor("#33000000")
    }
}

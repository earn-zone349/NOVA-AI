package com.nova.ai.bubble

/** A position in pixels. */
internal data class BubblePoint(val x: Int, val y: Int)

/**
 * Where the floating bubble and its panel go on the screen. Plain arithmetic with no Android
 * classes, so it can be tested without a phone. All numbers are pixels.
 */
internal object BubbleGeometry {

    /** True if a box at [x] is on the right half of the screen. */
    fun isRightSide(x: Int, boxWidth: Int, screenWidth: Int): Boolean =
        x + boxWidth / 2 >= screenWidth / 2

    /** The x of the box when it sticks to the nearest screen edge. */
    fun snapX(x: Int, boxWidth: Int, screenWidth: Int): Int =
        if (isRightSide(x, boxWidth, screenWidth)) maxOf(0, screenWidth - boxWidth) else 0

    /** Keeps [x] so the box stays fully on the screen. */
    fun clampX(x: Int, boxWidth: Int, screenWidth: Int): Int =
        x.coerceIn(0, maxOf(0, screenWidth - boxWidth))

    /** Keeps [y] between the top inset (status bar) and the bottom of the screen. */
    fun clampY(y: Int, boxHeight: Int, screenHeight: Int, topInset: Int): Int {
        val highest: Int = maxOf(topInset, screenHeight - boxHeight)
        return y.coerceIn(topInset, highest)
    }

    /** How far down the free area the box is, from 0.0 (top) to 1.0 (bottom). */
    fun yToFraction(y: Int, boxHeight: Int, screenHeight: Int, topInset: Int): Float {
        val range: Int = screenHeight - boxHeight - topInset
        if (range <= 0) return 0f
        return ((y - topInset).toFloat() / range).coerceIn(0f, 1f)
    }

    /** The reverse of [yToFraction]; also works after the screen was turned. */
    fun fractionToY(fraction: Float, boxHeight: Int, screenHeight: Int, topInset: Int): Int {
        val range: Int = maxOf(0, screenHeight - boxHeight - topInset)
        val safe: Float = if (fraction.isNaN()) 0f else fraction.coerceIn(0f, 1f)
        return topInset + (range * safe).toInt()
    }

    /**
     * Where the panel goes: centered on the bubble when possible, kept [gap] away from the screen
     * edges, above the bubble if there is room, otherwise below it.
     */
    fun panelPosition(
        boxX: Int,
        boxY: Int,
        boxWidth: Int,
        boxHeight: Int,
        panelWidth: Int,
        panelHeight: Int,
        screenWidth: Int,
        screenHeight: Int,
        gap: Int
    ): BubblePoint {
        val centered: Int = boxX + boxWidth / 2 - panelWidth / 2
        val x: Int = centered.coerceIn(gap, maxOf(gap, screenWidth - panelWidth - gap))

        val above: Int = boxY - gap - panelHeight
        val below: Int = boxY + boxHeight + gap
        val y: Int = when {
            above >= gap -> above
            below + panelHeight <= screenHeight - gap -> below
            else -> maxOf(gap, screenHeight - panelHeight - gap)
        }
        return BubblePoint(x, y)
    }
}

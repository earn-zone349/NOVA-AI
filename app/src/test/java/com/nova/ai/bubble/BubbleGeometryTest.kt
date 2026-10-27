package com.nova.ai.bubble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tests where the bubble and its panel go. Plain JVM test, no phone needed. */
class BubbleGeometryTest {

    private val screenW = 1080
    private val screenH = 2400
    private val box = 220
    private val inset = 80

    @Test
    fun leftHalfIsLeftAndRightHalfIsRight() {
        assertFalse(BubbleGeometry.isRightSide(100, box, screenW))
        assertTrue(BubbleGeometry.isRightSide(800, box, screenW))
    }

    @Test
    fun snapGoesToTheNearestEdge() {
        assertEquals(0, BubbleGeometry.snapX(150, box, screenW))
        assertEquals(screenW - box, BubbleGeometry.snapX(700, box, screenW))
    }

    @Test
    fun clampKeepsTheBoxOnTheScreen() {
        assertEquals(0, BubbleGeometry.clampX(-50, box, screenW))
        assertEquals(screenW - box, BubbleGeometry.clampX(5000, box, screenW))
        assertEquals(inset, BubbleGeometry.clampY(0, box, screenH, inset))
        assertEquals(screenH - box, BubbleGeometry.clampY(9999, box, screenH, inset))
    }

    @Test
    fun fractionRoundTripsAndSurvivesATurnedScreen() {
        val y = 900
        val f = BubbleGeometry.yToFraction(y, box, screenH, inset)
        assertTrue(kotlin.math.abs(y - BubbleGeometry.fractionToY(f, box, screenH, inset)) <= 1)
        // Landscape: the same fraction lands inside the smaller screen.
        val turned = BubbleGeometry.fractionToY(f, box, 1080, inset)
        assertTrue(turned in inset..(1080 - box))
    }

    @Test
    fun badFractionsAreSafe() {
        assertEquals(inset, BubbleGeometry.fractionToY(Float.NaN, box, screenH, inset))
        assertEquals(inset, BubbleGeometry.fractionToY(-3f, box, screenH, inset))
        assertEquals(screenH - box, BubbleGeometry.fractionToY(7f, box, screenH, inset))
        assertEquals(0f, BubbleGeometry.yToFraction(100, box, 100, inset), 0f)
    }

    private fun panel(boxX: Int, boxY: Int, h: Int = 300): BubblePoint =
        BubbleGeometry.panelPosition(boxX, boxY, box, box, 800, h, screenW, screenH, 30)

    @Test
    fun panelGoesAboveTheBubbleWhenThereIsRoom() {
        val p = panel(screenW - box, 1500)
        assertEquals(1500 - 30 - 300, p.y)
    }

    @Test
    fun panelGoesBelowWhenTheBubbleIsAtTheTop() {
        val p = panel(screenW - box, inset)
        assertEquals(inset + box + 30, p.y)
    }

    @Test
    fun panelStaysInsideTheScreenHorizontally() {
        val right = panel(screenW - box, 1500)
        val left = panel(0, 1500)
        assertTrue(right.x >= 30 && right.x + 800 <= screenW - 30)
        assertTrue(left.x >= 30)
    }

    @Test
    fun aVeryTallPanelIsStillClampedOnTheScreen() {
        val p = panel(0, 1200, h = 2300)
        assertTrue(p.y >= 30)
    }
}

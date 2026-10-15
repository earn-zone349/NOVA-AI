package com.nova.ai.vision

import com.nova.ai.core.DetectedElement
import com.nova.ai.core.NovaResult

/** Local computer vision, used only when the accessibility tree is not enough. */
interface VisionEngine {
    /** True if a vision model is installed and ready. */
    fun isAvailable(): Boolean

    /** Finds UI elements in an encoded screenshot ([screenshot] as PNG/JPEG bytes). */
    fun detectElements(screenshot: ByteArray): NovaResult<List<DetectedElement>>
}

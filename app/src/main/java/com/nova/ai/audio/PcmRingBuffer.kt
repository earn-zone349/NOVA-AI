package com.nova.ai.audio

/**
 * Keeps the most recent [capacity] samples of sound. Old sound is overwritten
 * by new sound. Safe to use from several threads.
 */
class PcmRingBuffer(private val capacity: Int) {

    private val data: ShortArray
    private var writeIndex: Int = 0
    private var filled: Int = 0
    private var total: Long = 0L

    init {
        require(capacity > 0) { "capacity must be positive" }
        data = ShortArray(capacity)
    }

    /** Adds the first [length] samples of [frame]. */
    @Synchronized
    fun write(frame: ShortArray, length: Int) {
        val count: Int = length.coerceIn(0, frame.size)
        // If more than the whole buffer arrives at once, only the newest part is kept.
        var source: Int = if (count > capacity) count - capacity else 0
        var remaining: Int = count - source

        while (remaining > 0) {
            val chunk: Int = minOf(remaining, capacity - writeIndex)
            System.arraycopy(frame, source, data, writeIndex, chunk)
            writeIndex = (writeIndex + chunk) % capacity
            source += chunk
            remaining -= chunk
        }
        filled = minOf(capacity, filled + count)
        total += count
    }

    /** Returns a copy of the newest [sampleCount] samples (fewer if not enough is stored). */
    @Synchronized
    fun readLast(sampleCount: Int): ShortArray {
        val count: Int = sampleCount.coerceIn(0, filled)
        val result = ShortArray(count)
        var readIndex: Int = (writeIndex - count + capacity) % capacity
        var destination = 0
        var remaining: Int = count

        while (remaining > 0) {
            val chunk: Int = minOf(remaining, capacity - readIndex)
            System.arraycopy(data, readIndex, result, destination, chunk)
            readIndex = (readIndex + chunk) % capacity
            destination += chunk
            remaining -= chunk
        }
        return result
    }

    /** How many samples are stored right now. */
    @Synchronized
    fun availableSamples(): Int = filled

    /** How many samples were written since the buffer was created. */
    @Synchronized
    fun totalWritten(): Long = total

    /** Forgets all stored sound. */
    @Synchronized
    fun clear() {
        writeIndex = 0
        filled = 0
    }
}

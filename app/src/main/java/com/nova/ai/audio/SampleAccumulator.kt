package com.nova.ai.audio

/** A growing list of sound samples. Not thread-safe: use from one thread. */
internal class SampleAccumulator(initialCapacity: Int) {

    private var data: ShortArray = ShortArray(maxOf(1, initialCapacity))

    /** How many samples are stored. */
    var size: Int = 0
        private set

    /** Adds the first [length] samples of [source]. */
    fun append(source: ShortArray, length: Int) {
        val count: Int = length.coerceIn(0, source.size)
        ensureCapacity(size + count)
        System.arraycopy(source, 0, data, size, count)
        size += count
    }

    /** Removes the last [count] samples. */
    fun trimEnd(count: Int) {
        size = (size - count.coerceAtLeast(0)).coerceAtLeast(0)
    }

    /** A copy of the stored samples. */
    fun toArray(): ShortArray = data.copyOf(size)

    /** Forgets all samples (the memory is kept for reuse). */
    fun clear() {
        size = 0
    }

    private fun ensureCapacity(needed: Int) {
        if (needed <= data.size) return
        var capacity: Int = data.size * 2
        while (capacity < needed) capacity *= 2
        data = data.copyOf(capacity)
    }
}

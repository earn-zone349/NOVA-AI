package com.nova.ai.brain

import com.nova.ai.core.ErrorCode
import com.nova.ai.core.NovaIntent
import com.nova.ai.core.NovaResult
import com.nova.ai.core.VoiceCommand
import com.nova.ai.logging.NovaLogger
import com.nova.ai.nlp.CommandNormalizer
import com.nova.ai.nlp.IntentParser
import com.nova.ai.nlp.NormalizedCommand

/**
 * The first "brain": understands commands with clear rules. Fast, works offline,
 * and never crashes on odd input. A local language model joins later (Phase 39+).
 */
class RuleBasedBrain : AiBrain {

    override fun analyze(
        command: VoiceCommand,
        recentContext: List<VoiceCommand>
    ): NovaResult<NovaIntent> {
        if (command.rawText.isBlank()) {
            return NovaResult.failure(ErrorCode.INVALID_INPUT, "খালি কমান্ড বোঝা যায় না।")
        }
        return try {
            val normalized: NormalizedCommand = CommandNormalizer.normalize(command)
            val context: List<NormalizedCommand> = recentContext
                .takeLast(IntentParser.MAX_CONTEXT)
                .map { CommandNormalizer.normalize(it) }
            NovaResult.Success(IntentParser.parse(normalized, context))
        } catch (e: Exception) {
            NovaLogger.e(TAG, "Intent analysis failed", e)
            NovaResult.failure(ErrorCode.EXECUTION_FAILED, "কমান্ড বিশ্লেষণে সমস্যা হয়েছে।", e)
        }
    }

    private companion object {
        const val TAG: String = "RuleBasedBrain"
    }
}

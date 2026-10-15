package com.nova.ai.models

import com.nova.ai.core.ModelInfo
import com.nova.ai.core.ModelType
import com.nova.ai.core.NovaResult

/** Manages local AI models stored on the device. */
interface LocalModelManager {
    /** Lists all known models, installed or not. */
    fun listModels(): NovaResult<List<ModelInfo>>

    /** Lists models of one [type]. */
    fun listModels(type: ModelType): NovaResult<List<ModelInfo>>

    /** True if the model with [modelId] is installed. */
    fun isInstalled(modelId: String): Boolean

    /** Removes an installed model to free storage. */
    fun delete(modelId: String): NovaResult<Unit>
}

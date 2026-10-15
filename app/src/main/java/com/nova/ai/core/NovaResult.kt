package com.nova.ai.core

/** Machine-readable error categories used across all modules. */
enum class ErrorCode {
    UNKNOWN,
    PERMISSION_DENIED,
    NOT_AVAILABLE,
    NOT_FOUND,
    INVALID_INPUT,
    TIMEOUT,
    CANCELLED,
    SECURITY_BLOCKED,
    EXECUTION_FAILED
}

/** Structured error carried by [NovaResult.Failure]. */
data class NovaError(
    val code: ErrorCode,
    val message: String,
    val cause: Throwable? = null
)

/**
 * Uniform result type for every module call.
 * Modules return this instead of throwing, so callers always handle failure explicitly.
 */
sealed class NovaResult<out T> {

    /** Successful outcome carrying [value]. */
    data class Success<out T>(val value: T) : NovaResult<T>()

    /** Failed outcome carrying a structured [error]. */
    data class Failure(val error: NovaError) : NovaResult<Nothing>()

    /** Returns the value on success, or null on failure. */
    fun getOrNull(): T? = when (this) {
        is Success -> value
        is Failure -> null
    }

    /** Transforms the value on success; passes failure through unchanged. */
    fun <R> map(transform: (T) -> R): NovaResult<R> = when (this) {
        is Success -> Success(transform(value))
        is Failure -> this
    }

    companion object {
        /** Convenience factory for a failure result. */
        fun failure(
            code: ErrorCode,
            message: String,
            cause: Throwable? = null
        ): Failure = Failure(NovaError(code, message, cause))
    }
}

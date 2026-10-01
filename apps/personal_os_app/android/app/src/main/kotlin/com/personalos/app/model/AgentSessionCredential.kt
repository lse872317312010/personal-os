package com.personalos.app.model

/** Runtime-only key storage for user-triggered Agent API requests. */
internal class AgentSessionCredentialStore {
    private val monitor = Any()
    private var credential: CharArray? = null

    val isReady: Boolean
        get() = synchronized(monitor) { credential != null }

    fun install(ownedCredential: CharArray) {
        if (ownedCredential.isEmpty() ||
            ownedCredential.size > MAXIMUM_CREDENTIAL_LENGTH ||
            ownedCredential.any { character -> character.code !in 0x21..0x7E }
        ) {
            ownedCredential.fill('\u0000')
            throw IllegalArgumentException()
        }
        val previous = synchronized(monitor) {
            if (credential === ownedCredential) return
            val value = credential
            credential = ownedCredential
            value
        }
        previous?.fill('\u0000')
    }

    fun <T> useCredential(consumer: (CharArray) -> T): T {
        val copy = synchronized(monitor) {
            credential?.copyOf() ?: throw AgentCompletionFailure(
                AgentCompletionFailureCode.CREDENTIAL_REQUIRED,
            )
        }
        return try {
            consumer(copy)
        } finally {
            copy.fill('\u0000')
        }
    }

    fun clear() {
        val owned = synchronized(monitor) {
            val value = credential
            credential = null
            value
        }
        owned?.fill('\u0000')
    }

    companion object {
        private const val MAXIMUM_CREDENTIAL_LENGTH = 512
    }
}

internal enum class AgentCompletionFailureCode(val wireValue: String) {
    ADAPTER_UNAVAILABLE("agent.adapter_unavailable"),
    CREDENTIAL_REQUIRED("agent.credential_required"),
    INVALID_REQUEST("agent.invalid_request"),
    INVALID_RESPONSE("agent.invalid_response"),
    REQUEST_FAILED("agent.request_failed"),
}

internal class AgentCompletionFailure(
    val failureCode: AgentCompletionFailureCode,
) : Exception()

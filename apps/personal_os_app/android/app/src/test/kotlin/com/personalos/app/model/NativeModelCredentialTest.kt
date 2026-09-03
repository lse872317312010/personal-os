package com.personalos.app.model

import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeModelCredentialTest {
    @Test
    fun replacementAndClearZeroizeOwnedCredentials() {
        val provider = EphemeralNativeModelCredentialProvider()
        val first = "first-secret".toCharArray()
        val second = "second-secret".toCharArray()

        provider.install(first)
        provider.install(second)

        assertArrayEquals(CharArray(first.size), first)
        assertTrue(provider.isReady)

        provider.clear()

        assertArrayEquals(CharArray(second.size), second)
        assertFalse(provider.isReady)
    }

    @Test
    fun blankCredentialIsRejectedAndCleared() {
        val provider = EphemeralNativeModelCredentialProvider()
        val blank = charArrayOf(' ', '\t')

        assertThrows(IllegalArgumentException::class.java) {
            provider.install(blank)
        }

        assertArrayEquals(CharArray(blank.size), blank)
        assertFalse(provider.isReady)
    }

    @Test
    fun adapterDisposalClearsAnUnusedCredential() {
        val provider = EphemeralNativeModelCredentialProvider()
        val owned = "unused-secret".toCharArray()
        provider.install(owned)
        val transport = RecordingTransport(provider)

        transport.dispose()

        assertArrayEquals(CharArray(owned.size), owned)
        assertFalse(transport.runtimeCredentialReady)
    }

    @Test
    fun adapterCanInstallAndClearRuntimeCredentialWithoutAStringCopy() {
        val provider = EphemeralNativeModelCredentialProvider()
        val transport = RecordingTransport(provider)
        val owned = "installed-once".toCharArray()

        transport.installRuntimeCredential(owned)

        assertTrue(transport.runtimeCredentialReady)

        transport.clearRuntimeCredential()

        assertArrayEquals(CharArray(owned.size), owned)
        assertFalse(transport.runtimeCredentialReady)
    }

    @Test
    fun credentialClearAndDisposalCancelTransportWork() {
        val provider = EphemeralNativeModelCredentialProvider()
        val transport = RecordingTransport(provider)
        provider.install("first".toCharArray())

        transport.clearRuntimeCredential()

        assertEquals(1, transport.cancellationCount)

        provider.install("second".toCharArray())
        transport.dispose()

        assertEquals(2, transport.cancellationCount)
        assertFalse(transport.runtimeCredentialReady)
    }

    @Test
    fun nonInstallableProviderRejectsAndClearsSuppliedCredential() {
        val existing = "existing".toCharArray()
        val transport = RecordingTransport(providerFor(existing))
        val rejected = "rejected".toCharArray()

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            transport.installRuntimeCredential(rejected)
        }

        assertEquals(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            failure.failureCode,
        )
        assertArrayEquals(CharArray(rejected.size), rejected)
        assertTrue(transport.runtimeCredentialReady)
    }

    @Test
    fun capabilitySnapshotTracksTheLiveCredentialProvider() {
        val transport = RecordingTransport(providerFor("one-call".toCharArray()))

        val before = nativeModelCapabilities(transport)
        assertEquals(true, before["configured"])
        assertEquals(listOf("externalProcessor"), before["supportedBoundaries"])
        assertEquals(true, before["runtimeCredentialReady"])

        transport.analyze(validCredentialRequest(), byteArrayOf(1).inputStream())

        val after = nativeModelCapabilities(transport)
        assertEquals(true, after["configured"])
        assertEquals(false, after["runtimeCredentialReady"])
    }

    @Test
    fun credentialIsClearedAfterSuccessfulTransportCall() {
        val owned = "runtime-secret".toCharArray()
        val transport = RecordingTransport(providerFor(owned))

        assertTrue(transport.runtimeCredentialReady)

        val result = transport.analyze(validCredentialRequest(), byteArrayOf(1).inputStream())

        assertEquals("native-fixture-v1", result.modelId)
        assertEquals(14, transport.observedLength)
        assertArrayEquals(CharArray(owned.size), owned)
        assertFalse(transport.runtimeCredentialReady)
    }

    @Test
    fun credentialIsClearedAndNotExposedAfterFailure() {
        val owned = "runtime-secret".toCharArray()
        val transport = RecordingTransport(providerFor(owned), fail = true)

        val failure = assertThrows(IllegalStateException::class.java) {
            transport.analyze(validCredentialRequest(), byteArrayOf(1).inputStream())
        }

        assertArrayEquals(CharArray(owned.size), owned)
        assertFalse(failure.toString().contains("runtime-secret"))
    }

    private fun providerFor(owned: CharArray): NativeModelCredentialProvider =
        object : NativeModelCredentialProvider {
            private var available = true

            override val isReady: Boolean
                get() = available

            override fun <T> useCredential(consumer: (CharArray) -> T): T {
                check(available)
                available = false
                return consumeOwnedCredential(owned, consumer)
            }

            override fun clear() {
                available = false
                owned.fill('\u0000')
            }
        }

    private class RecordingTransport(
        credentials: NativeModelCredentialProvider,
        private val fail: Boolean = false,
    ) : CredentialedNativeAppearanceModelTransport(credentials) {
        var observedLength: Int? = null
        var cancellationCount = 0

        override fun cancelTransportWork() {
            cancellationCount++
        }

        override fun analyzeWithCredential(
            request: NativeAppearanceModelRequest,
            media: InputStream,
            credential: CharArray,
        ): NativeAppearanceModelResult {
            observedLength = credential.size
            if (fail) error("provider unavailable")
            return completeCredentialResult()
        }
    }
}

private fun validCredentialRequest(): NativeAppearanceModelRequest =
    NativeAppearanceModelRequest(
        blobRef = "blob://1234567890abcdef",
        observationContext = "front-facing natural light",
        locale = "zh-CN",
        promptVersion = "appearance-v1",
        processingBoundary = NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
    )

private fun completeCredentialResult(): NativeAppearanceModelResult =
    NativeAppearanceModelResult(
        findings = listOf(
            NativeAppearanceFinding(
                dimension = "hair_shape",
                statement = "Visible outline can be reviewed.",
                confidence = 0.8,
                kind = "observableFact",
            ),
        ),
        actions = listOf(
            NativeAppearanceAction(
                title = "Record a comparison",
                rationale = "Build a reviewable baseline.",
                dayOffset = 1,
                requiresHumanConfirmation = true,
            ),
        ),
        modelTraceRef = "trace://native/1",
        modelId = "native-fixture-v1",
        promptVersion = "appearance-v1",
        inputSummaryRef = "audit://input/1",
        risks = emptyList(),
        humanConfirmations = emptyList(),
    )

package com.personalos.app.source

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ControlledSourceMethodChannelContractTest {
    @Test
    fun acceptsOpaqueTokenAndRejectsUriOrPath() {
        assertTrue(
            ControlledSourceMethodChannelContract.isOpaqueToken(
                "native_photo_token_01",
            ),
        )
        assertFalse(
            ControlledSourceMethodChannelContract.isOpaqueToken(
                "content://media/external/images/media/1",
            ),
        )
        assertFalse(
            ControlledSourceMethodChannelContract.isOpaqueToken(
                "/data/user/0/com.personalos.app/photo.jpg",
            ),
        )
    }

    @Test
    fun unknownNativeFailuresCollapseToUnavailable() {
        assertEquals(
            mapOf("errorCode" to "source.unavailable"),
            ControlledSourceMethodChannelContract.safeFailure(
                "java.io.FileNotFoundException: /private/path",
            ),
        )
    }

    @Test
    fun invalidNativeTokenBecomesStableError() {
        assertEquals(
            mapOf("errorCode" to "source.invalid_response"),
            ControlledSourceMethodChannelContract.safeTokenResult(
                "content://private/photo",
            ),
        )
    }

    @Test
    fun safeTokenResultContainsNoSourceMetadata() {
        assertEquals(
            mapOf("token" to "native_photo_token_01"),
            ControlledSourceMethodChannelContract.safeTokenResult(
                "native_photo_token_01",
            ),
        )
    }
}

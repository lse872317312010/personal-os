#!/usr/bin/env python3
"""Static fail-closed checks for the native external model provider boundary."""

from __future__ import annotations

import sys
from pathlib import Path


PROVIDER = Path(
    "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/"
    "OpenAiResponsesAppearanceModelClient.kt"
)
PROTOCOL = Path(
    "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/model/"
    "OpenAiResponsesProtocol.kt"
)
MAIN_ACTIVITY = Path(
    "apps/personal_os_app/android/app/src/main/kotlin/com/personalos/app/"
    "MainActivity.kt"
)
GRADLE = Path("apps/personal_os_app/android/app/build.gradle.kts")
MANIFEST = Path("apps/personal_os_app/android/app/src/main/AndroidManifest.xml")
CONTROLLER = Path("apps/personal_os_app/lib/src/controller/app_controller.dart")
CAPTURE_SCREEN = Path("apps/personal_os_app/lib/src/screens/capture_screen.dart")
DOGFOOD_BUILD = Path("tool/android_mvp/build_debug.sh")


def require_tokens(text: str, path: Path, tokens: tuple[str, ...]) -> list[str]:
    return [f"{path}: missing {token!r}" for token in tokens if token not in text]


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    files = (
        PROVIDER,
        PROTOCOL,
        MAIN_ACTIVITY,
        GRADLE,
        MANIFEST,
        CONTROLLER,
        CAPTURE_SCREEN,
        DOGFOOD_BUILD,
    )
    try:
        source = {path: (root / path).read_text(encoding="utf-8") for path in files}
    except OSError as error:
        print(f"external-provider audit: ERROR: {error}", file=sys.stderr)
        return 2

    provider = source[PROVIDER]
    errors = require_tokens(
        provider,
        PROVIDER,
        (
            '"https://api.openai.com/v1/responses"',
            'private const val OPENAI_HOST = "api.openai.com"',
            "require(endpoint.protocol == \"https\")",
            "connection.instanceFollowRedirects = false",
            "connection.connectTimeout = request.timeoutMillis",
            "connection.readTimeout = request.timeoutMillis",
            'append(",\\\"store\\\":false',
            'put("strict", true)',
            'put("additionalProperties", false)',
            "StreamingBase64OutputStream(",
            "MAXIMUM_RESPONSE_BYTES",
            'connection.setRequestProperty("Authorization"',
            "extractOpenAiCompletedResponse(",
            "completeOpenAiAppearanceResult(",
            "SUPPORTED_OPENAI_MEDIA_TYPES",
            "character.code !in 0x21..0x7E",
            "activeConnection.getAndSet(null)?.disconnect()",
        ),
    )
    errors += require_tokens(
        source[PROTOCOL],
        PROTOCOL,
        (
            'response["status"] != "completed"',
            '"refusal" -> invalidOpenAiResponse()',
            "semanticResult.keys != OPENAI_APPEARANCE_SEMANTIC_KEYS",
            'put("modelTraceRef", completed.traceId)',
        ),
    )
    errors += require_tokens(
        source[MAIN_ACTIVITY],
        MAIN_ACTIVITY,
        (
            "if (BuildConfig.PERSONAL_OS_OPENAI_ENABLED)",
            "BuildConfig.PERSONAL_OS_OPENAI_MODEL",
            "EphemeralNativeModelCredentialProvider()",
        ),
    )
    errors += require_tokens(
        source[GRADLE],
        GRADLE,
        (
            'providers.gradleProperty("personalOsOpenAiEnabled")',
            'providers.gradleProperty("personalOsOpenAiModel")',
            '"PERSONAL_OS_OPENAI_ENABLED"',
            '"PERSONAL_OS_OPENAI_MODEL"',
        ),
    )
    errors += require_tokens(
        source[MANIFEST],
        MANIFEST,
        (
            '<uses-permission android:name="android.permission.INTERNET" />',
            'android:usesCleartextTraffic="false"',
        ),
    )
    errors += require_tokens(
        source[CONTROLLER],
        CONTROLLER,
        (
            "externalTransmissionConfirmationRequired",
            "externalTransmissionConfirmed = false",
            "_validateExternalTransmissionConfirmation(",
            "external_transmission_confirmation_required",
        ),
    )
    errors += require_tokens(
        source[CAPTURE_SCREEN],
        CAPTURE_SCREEN,
        (
            "_confirmExternalTransmission()",
            "external-transmission-confirmation",
            "服务商可能收取 API 费用",
            "仅发送这一次",
        ),
    )
    errors += require_tokens(
        source[DOGFOOD_BUILD],
        DOGFOOD_BUILD,
        (
            'ORG_GRADLE_PROJECT_personalOsOpenAiEnabled:-true',
            'ORG_GRADLE_PROJECT_personalOsOpenAiModel:-gpt-5.4-mini',
            'PERSONAL_OS_MODEL_PROVIDER="openai"',
        ),
    )

    prohibited = (
        "Log.",
        "println(",
        ".readBytes(",
        ".readAllBytes(",
        "instanceFollowRedirects = true",
        "http://api.openai.com",
    )
    errors.extend(
        f"{PROVIDER}: prohibited {token!r}"
        for token in prohibited
        if token in provider
    )
    gradle_lower = source[GRADLE].lower()
    for secret_name in ("openaiapikey", "openai_api_key", "openaisecret"):
        if secret_name in gradle_lower:
            errors.append(f"{GRADLE}: build-time credential name {secret_name!r}")

    if errors:
        print("external-provider audit: FAIL", file=sys.stderr)
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("external-provider audit: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
API = ROOT / "packages/model_gateway_api/lib/src/appearance_analysis.dart"
USE_CASE = ROOT / "packages/application/lib/src/appearance_use_case.dart"
GATEWAY = ROOT / "apps/personal_os_app/lib/src/composition/method_channel_appearance_analysis_gateway.dart"
CONTROLLER = ROOT / "apps/personal_os_app/lib/src/controller/app_controller.dart"
CAPTURE_SCREEN = ROOT / "apps/personal_os_app/lib/src/screens/capture_screen.dart"
GATEWAY_TEST = ROOT / "apps/personal_os_app/test/method_channel_appearance_analysis_gateway_test.dart"
USE_CASE_TEST = ROOT / "packages/application/test/model_gateway_failure_passthrough_test.dart"

checks = {
    API: (
        'final class AppearanceModelGatewayFailure implements Exception',
        "static const mediaTooLarge = 'model.media_too_large';",
        "'model.media_transcode_unavailable'",
        'AppearanceModelGatewayFailureCode.values.contains(code)',
        'AppearanceModelGatewayFailureCode.adapterUnavailable',
    ),
    GATEWAY: (
        'throw AppearanceModelGatewayFailure(_stableFailureCode(error.code));',
        'AppearanceModelGatewayFailureCode.mediaTooLarge',
        'AppearanceModelGatewayFailureCode.mediaTranscodeUnavailable',
        '_ => AppearanceModelGatewayFailureCode.adapterUnavailable',
    ),
    USE_CASE: (
        'on AppearanceModelGatewayFailure catch (error)',
        'throw AppearanceUseCaseFailure(error.code);',
        'AppearanceFailureCode.analysisFailed',
        'Unknown adapter failures are never allowed to expose paths, URIs,',
    ),
    CONTROLLER: (
        'on AppearanceUseCaseFailure catch (error)',
        '_errorCode = error.code;',
    ),
    CAPTURE_SCREEN: (
        "'model.media_too_large'",
        "'model.media_transcode_unavailable'",
    ),
    GATEWAY_TEST: (
        'preserves enumerated native media failure without platform details',
        'isA<AppearanceModelGatewayFailure>()',
        'AppearanceModelGatewayFailureCode.mediaTooLarge',
        "PlatformException(\n        code: 'provider.raw_failure'",
    ),
    USE_CASE_TEST: (
        'preserves enumerated redacted model gateway failures',
        'AppearanceModelGatewayFailureCode.mediaTooLarge',
        'redacts arbitrary adapter failures to analysis_failed',
        "StateError('api-key=secret /data/user/0/private.jpg')",
        'gateway failure contract sanitizes unknown codes',
    ),
}

forbidden = {
    GATEWAY: ('SecureModelGatewayFailure',),
    USE_CASE: (
        'catch (_) {\n      // Model adapters are not allowed to expose paths, URIs, or raw errors.',
    ),
}

errors = []
for path, tokens in checks.items():
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"{path.relative_to(ROOT)}: {exc}")
        continue
    for token in tokens:
        if token not in text:
            errors.append(f"{path.relative_to(ROOT)}: missing {token!r}")
    for token in forbidden.get(path, ()):
        if token in text:
            errors.append(f"{path.relative_to(ROOT)}: forbidden {token!r}")

if errors:
    print("model-failure-passthrough audit: FAIL", file=sys.stderr)
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("model-failure-passthrough audit: PASS")

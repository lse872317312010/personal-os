import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';

final class AnalyzeAppearanceCommand {
  AnalyzeAppearanceCommand({
    required this.profileId,
    required String imageRef,
    required this.actor,
    required String correlationId,
    required this.observationContext,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
    this.locale = 'zh-CN',
    String promptVersion = 'appearance-v1',
    this.processingBoundary = AppearanceProcessingBoundary.onDevice,
  })  : imageRef = _nonBlank(imageRef, 'imageRef'),
        correlationId = _nonBlank(correlationId, 'correlationId'),
        promptVersion = _nonBlank(promptVersion, 'promptVersion'),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final EntityId profileId;
  final String imageRef;
  final ActorRef actor;
  final String correlationId;
  final String observationContext;
  final List<ObjectRef> consentRefs;
  final String locale;
  final String promptVersion;
  final AppearanceProcessingBoundary processingBoundary;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

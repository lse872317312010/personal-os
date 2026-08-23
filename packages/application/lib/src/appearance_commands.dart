import 'package:personal_os_domain/domain.dart';

final class AnalyzeAppearanceCommand {
  AnalyzeAppearanceCommand({
    required this.profileId,
    required String imageRef,
    required this.actor,
    required String correlationId,
    required this.observationContext,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
    this.locale = 'zh-CN',
  })  : imageRef = _nonBlank(imageRef, 'imageRef'),
        correlationId = _nonBlank(correlationId, 'correlationId'),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs);

  final EntityId profileId;
  final String imageRef;
  final ActorRef actor;
  final String correlationId;
  final String observationContext;
  final List<ObjectRef> consentRefs;
  final String locale;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

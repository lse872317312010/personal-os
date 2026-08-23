/// Stable identity of a logical domain object.
final class EntityId {
  EntityId(String value) : value = _requireNonBlank(value, 'EntityId');
  final String value;
  @override
  bool operator ==(Object other) => other is EntityId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

/// Monotonically increasing object revision. Zero means no prior revision.
final class Revision {
  Revision(int value) : value = _requireNonNegative(value, 'Revision');
  final int value;
  Revision get next => Revision(value + 1);
  @override
  bool operator ==(Object other) => other is Revision && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Version of a persisted domain object representation.
final class SchemaVersion {
  SchemaVersion(int value) : value = _requirePositive(value, 'SchemaVersion');
  final int value;
}

/// A reference is pinned to a concrete revision unless [revision] is absent.
/// Mutable/current-state code should prefer pinned references.
final class ObjectRef {
  ObjectRef({required String type, required this.id, this.revision})
      : type = _requireNonBlank(type, 'ObjectRef.type');

  factory ObjectRef.fromJson(Map<String, Object?> json) => ObjectRef(
        type: json['type']! as String,
        id: EntityId(json['id']! as String),
        revision: json['revision'] == null
            ? null
            : Revision(json['revision']! as int),
      );

  final String type;
  final EntityId id;
  final Revision? revision;
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'id': id.value,
        if (revision != null) 'revision': revision!.value,
      };
}

String _requireNonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

int _requireNonNegative(int value, String label) {
  if (value < 0) {
    throw ArgumentError.value(value, label, 'must be non-negative');
  }
  return value;
}

int _requirePositive(int value, String label) {
  if (value <= 0) {
    throw ArgumentError.value(value, label, 'must be positive');
  }
  return value;
}

/// Returns a recursively copied, read-only JSON-like map.
///
/// Map and List containers are copied at every level, so neither mutations to
/// the caller's original containers nor mutations through exposed values can
/// change persisted event state. Scalar and non-JSON leaf objects are retained;
/// the persistence codec remains responsible for rejecting non-JSON values.
Map<String, Object?> deepFreezeMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable({
      for (final entry in source.entries)
        entry.key: deepFreezeValue(entry.value),
    });

Object? deepFreezeValue(Object? value) {
  if (value is Map) {
    if (value.keys.every((key) => key is String)) {
      return Map<String, Object?>.unmodifiable({
        for (final entry in value.entries)
          (entry.key as String): deepFreezeValue(entry.value),
      });
    }
    return Map<Object?, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key: deepFreezeValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(deepFreezeValue));
  }
  return value;
}

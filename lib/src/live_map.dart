import 'dart:collection';

/// A [Map] that calls [_notify] on every mutating operation.
///
/// Optional [wrapKey] and [wrapValue] functions let the generator wrap
/// proxyable key/value types with their `_Rx` proxies as entries enter the
/// map, so field-level mutations on those objects also trigger a rebuild.
///
/// **Key-wrapping constraint:** wrapping keys is only safe when K has
/// value-based equality (`==` / `hashCode` overridden). With Dart's default
/// identity equality, `map[originalKey]` will not find an entry stored under
/// a wrapped key. For identity-based keys, leave [wrapKey] null and only
/// wrap values.
class LiveMap<K, V> with MapMixin<K, V> {
  LiveMap(this._notify, {K Function(K)? wrapKey, V Function(V)? wrapValue})
      : _map = {},
        _wrapKey = wrapKey,
        _wrapValue = wrapValue;

  LiveMap.of(
    Map<K, V> source,
    this._notify, {
    K Function(K)? wrapKey,
    V Function(V)? wrapValue,
  })  : _wrapKey = wrapKey,
        _wrapValue = wrapValue,
        _map = Map.fromEntries(source.entries.map((e) => MapEntry(
              wrapKey != null ? wrapKey(e.key) : e.key,
              wrapValue != null ? wrapValue(e.value) : e.value,
            )));

  final Map<K, V> _map;
  final void Function() _notify;
  final K Function(K)? _wrapKey;
  final V Function(V)? _wrapValue;

  K _maybeWrapKey(K key) => _wrapKey != null ? _wrapKey!(key) : key;
  V _maybeWrapValue(V value) => _wrapValue != null ? _wrapValue!(value) : value;

  // ── required by MapMixin ─────────────────────────────────────────────────

  @override
  V? operator [](Object? key) => _map[key];

  @override
  void operator []=(K key, V value) {
    _map[_maybeWrapKey(key)] = _maybeWrapValue(value);
    _notify();
  }

  @override
  Iterable<K> get keys => _map.keys;

  @override
  int get length => _map.length;

  @override
  V? remove(Object? key) {
    if (!_map.containsKey(key)) return null;
    final removed = _map.remove(key);
    _notify();
    return removed;
  }

  // ── additional mutating operations ───────────────────────────────────────

  @override
  void addAll(Map<K, V> other) {
    for (final e in other.entries) {
      _map[_maybeWrapKey(e.key)] = _maybeWrapValue(e.value);
    }
    _notify();
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> entries) {
    for (final e in entries) {
      _map[_maybeWrapKey(e.key)] = _maybeWrapValue(e.value);
    }
    _notify();
  }

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    final wrappedKey = _maybeWrapKey(key);
    final existed = _map.containsKey(wrappedKey);
    final result = _map.putIfAbsent(
      wrappedKey,
      () => _maybeWrapValue(ifAbsent()),
    );
    if (!existed) _notify();
    return result;
  }

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    final wrappedKey = _maybeWrapKey(key);
    final result = _map.update(
      wrappedKey,
      (v) => _maybeWrapValue(update(v)),
      ifAbsent: ifAbsent != null ? () => _maybeWrapValue(ifAbsent()) : null,
    );
    _notify();
    return result;
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    _map.updateAll((k, v) => _maybeWrapValue(update(k, v)));
    _notify();
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    _map.removeWhere(test);
    _notify();
  }

  @override
  void clear() {
    _map.clear();
    _notify();
  }
}

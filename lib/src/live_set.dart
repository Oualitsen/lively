import 'dart:collection';

/// A [Set] that calls [_notify] on every mutating operation.
///
/// When the element type is proxyable, pass a [wrap] function so that items
/// added to the set are automatically wrapped as reactive proxies — mutations
/// on those items (e.g. `cars.first.color = 'red'`) then also trigger a
/// rebuild.
class LiveSet<T> with SetMixin<T> {
  LiveSet(this._notify, {T Function(T)? wrap}) : _set = {}, _wrap = wrap;

  LiveSet.of(Iterable<T> source, this._notify, {T Function(T)? wrap})
      : _wrap = wrap,
        _set = wrap != null ? Set.of(source.map(wrap)) : Set.of(source);

  final Set<T> _set;
  final void Function() _notify;
  final T Function(T)? _wrap;

  T _maybeWrap(T item) => _wrap != null ? _wrap!(item) : item;

  @override
  int get length => _set.length;

  @override
  Iterator<T> get iterator => _set.iterator;

  @override
  bool contains(Object? element) => _set.contains(element);

  @override
  T? lookup(Object? element) => _set.lookup(element);

  @override
  Set<T> toSet() => _set.toSet();

  @override
  bool add(T value) {
    final added = _set.add(_maybeWrap(value));
    if (added) _notify();
    return added;
  }

  @override
  void addAll(Iterable<T> elements) {
    final before = _set.length;
    _set.addAll(_wrap != null ? elements.map(_wrap!) : elements);
    if (_set.length != before) _notify();
  }

  @override
  bool remove(Object? value) {
    final removed = _set.remove(value);
    if (removed) _notify();
    return removed;
  }

  @override
  void removeAll(Iterable<Object?> elements) {
    final before = _set.length;
    _set.removeAll(elements);
    if (_set.length != before) _notify();
  }

  @override
  void retainAll(Iterable<Object?> elements) {
    final before = _set.length;
    _set.retainAll(elements);
    if (_set.length != before) _notify();
  }

  @override
  void removeWhere(bool Function(T) test) {
    _set.removeWhere(test);
    _notify();
  }

  @override
  void retainWhere(bool Function(T) test) {
    _set.retainWhere(test);
    _notify();
  }

  @override
  void clear() {
    _set.clear();
    _notify();
  }
}

import 'dart:collection';

/// A [List] that calls [_notify] on every mutating operation.
///
/// When the element type is proxyable, pass a [wrap] function so that items
/// added to the list are automatically wrapped as reactive proxies — mutations
/// on those items (e.g. `cars[0].color = 'red'`) then also trigger a rebuild.
///
/// **Remove identity:** when a [wrap] function is provided, items are stored as
/// wrapped instances, not the originals. [remove] uses identity equality, so
/// pass the reference obtained from the list itself (e.g. `list[i]`), not the
/// object you originally added.
class LiveList<T> with ListMixin<T> {
  LiveList(this._notify, {T Function(T)? wrap}) : _list = [], _wrap = wrap;

  LiveList.of(Iterable<T> source, this._notify, {T Function(T)? wrap})
      : _wrap = wrap,
        _list = wrap != null ? List.of(source.map(wrap)) : List.of(source);

  final List<T> _list;
  final void Function() _notify;
  final T Function(T)? _wrap;

  T _maybeWrap(T item) => _wrap != null ? _wrap!(item) : item;

  @override
  int get length => _list.length;

  @override
  set length(int newLength) {
    _list.length = newLength;
    _notify();
  }

  @override
  T operator [](int index) => _list[index];

  @override
  void operator []=(int index, T value) {
    _list[index] = _maybeWrap(value);
    _notify();
  }

  @override
  void add(T element) {
    _list.add(_maybeWrap(element));
    _notify();
  }

  @override
  void addAll(Iterable<T> iterable) {
    _list.addAll(_wrap != null ? iterable.map(_wrap!) : iterable);
    _notify();
  }

  @override
  void insert(int index, T element) {
    _list.insert(index, _maybeWrap(element));
    _notify();
  }

  @override
  void insertAll(int index, Iterable<T> iterable) {
    _list.insertAll(index, _wrap != null ? iterable.map(_wrap!) : iterable);
    _notify();
  }

  @override
  bool remove(Object? element) {
    final removed = _list.remove(element);
    if (removed) _notify();
    return removed;
  }

  @override
  T removeAt(int index) {
    final v = _list.removeAt(index);
    _notify();
    return v;
  }

  @override
  T removeLast() {
    final v = _list.removeLast();
    _notify();
    return v;
  }

  @override
  void removeWhere(bool Function(T) test) {
    _list.removeWhere(test);
    _notify();
  }

  @override
  void retainWhere(bool Function(T) test) {
    _list.retainWhere(test);
    _notify();
  }

  @override
  void clear() {
    _list.clear();
    _notify();
  }

  @override
  void sort([Comparator<T>? compare]) {
    _list.sort(compare);
    _notify();
  }

  @override
  void shuffle([dynamic random]) {
    _list.shuffle(random);
    _notify();
  }
}

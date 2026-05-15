import 'package:flutter/foundation.dart';

/// Base class for all @LiveStore classes.
///
/// Extend this instead of `ChangeNotifier` directly:
///
/// ```dart
/// @LiveStore()
/// class _CartStore extends LiveStoreBase {
///   List<CartItem> items = [];
/// }
/// ```
///
/// The generator produces `class CartStore extends _CartStore` with reactive
/// setter overrides that call `$scheduleNotify()`.
abstract class LiveStoreBase extends ChangeNotifier {
  bool _$dirty = false;

  // Called by generated setter overrides to batch notifications into a single
  // microtask per synchronous mutation block.
  void $scheduleNotify() {
    if (_$dirty) return;
    _$dirty = true;
    Future.microtask(() {
      _$dirty = false;
      notifyListeners();
    });
  }

  /// Trigger [notifyListeners] manually — use this after directly mutating a
  /// nested object that is not tracked by a generated proxy.
  void notify() => $scheduleNotify();

  @mustCallSuper
  @override
  void dispose() => super.dispose();
}

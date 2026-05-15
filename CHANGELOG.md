## 1.0.0

- Initial release.
- `@Live()` annotation generates a thin `StatefulWidget`, an abstract `State` base with microtask-batched `setState`, and a concrete impl that wires reactive setters.
- `@LiveStore()` annotation generates a reactive `ChangeNotifier` from a plain Dart class. Prefix the spec class with `_`; the generator strips the underscore to produce the public class (e.g. `_CartStore` → `CartStore`).
- Reactive scalar fields: every mutable field gets a setter that schedules a batched rebuild / `notifyListeners()` via `Future.microtask`. Multiple assignments in one sync block produce exactly one notification.
- `late final` fields without an initializer become typed constructor parameters — on the generated widget for `@Live()`, or on the generated store class for `@LiveStore()`. `didUpdateWidget` is generated automatically for widget params.
- Known disposable types (`TextEditingController`, `AnimationController`, `FocusNode`, `ScrollController`, `PageController`, `StreamController`, `StreamSubscription`) are disposed/cancelled automatically. Nullable fields use `?.` in all generated lifecycle calls.
- `ChangeNotifier` fields are wired with `addListener` / `removeListener` and re-wired on reassignment. `@LiveStore`-typed fields with inline initializers are additionally auto-disposed (widget owns them).
- Deep object reactivity via generated `_Live<ClassName>` proxy subclasses; proxy setters re-wrap incoming values so reactivity is never lost on reassignment.
- `LiveList<T>`, `LiveSet<T>`, `LiveMap<K, V>` reactive collection wrappers with optional item-level proxy wrapping.
- `notify()` escape hatch for manual rebuild / `notifyListeners()` scheduling.
- `Reactive` widget for surgical subtree rebuilds.

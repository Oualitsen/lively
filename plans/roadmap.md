# lively — feature roadmap

> Candidates are ranked by value-to-complexity ratio and alignment with the
> core philosophy: zero dependencies, pure Flutter + Dart, code generation via
> `build_runner`.

---

## Priority 1 — `Future<T>` / `Stream<T>` field support

### Problem

Async state is the most common Flutter pain point. Today, a developer who wants
to load a `Future<User>` must manually manage a loading flag, an error value,
and the resolved data — three separate reactive fields, three separate setters,
and custom `initState` wiring. The same boilerplate repeats for every async
field on every widget.

### Proposed solution

Declare a `Future<T>` or `Stream<T>` field; the generator emits an
`AsyncValue<T>` (loading / data / error) state with full lifecycle wiring.

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  Future<User> user = UserApi.fetch();   // ← plain Dart, no annotation

  @override
  Widget build(BuildContext context) {
    return switch (userState) {
      AsyncLoading()        => const CircularProgressIndicator(),
      AsyncError(:final e)  => Text('Error: $e'),
      AsyncData(:final v)   => Text(v.name),
    };
  }
}
```

What gets generated:
- A sealed `AsyncValue<T>` type with `AsyncLoading`, `AsyncData<T>`,
  `AsyncError` variants (shipped in the `lively` runtime, not generated per
  field).
- A `<fieldName>State` reactive field of type `AsyncValue<T>`.
- `initState` wiring: `future.then(...)` / `stream.listen(...)` that sets
  `<fieldName>State` and calls `_scheduleRebuild()`.
- `dispose()` cancels the stream subscription if applicable.
- Reassigning the field re-subscribes (old subscription cancelled first).

### Key decisions to make
- Whether `Stream<T>` re-emits on every event or only on distinct values.
- Error boundary: does an unhandled error in the future swallow silently or
  rethrow? (Proposal: store in `AsyncError`, never rethrow.)
- Naming: `userState` vs `$user` vs keeping the same name and changing the
  type. `<name>State` is the clearest.

### Complexity
Medium. The `AsyncValue` sealed type is straightforward. The tricky part is
reassignment semantics for `Stream<T>` (cancel + resubscribe) and making the
generated field name (`userState`) discoverable without surprising the user.

---

## Priority 2 — `@LiveStore` → `InheritedWidget` bridge

### Problem

`@LiveStore` generates a reactive `ChangeNotifier`. To share it across the
widget tree today the developer must reach for Provider, GetIt, or another DI
package — which contradicts the zero-dependency promise and adds significant
boilerplate.

### Proposed solution

Generate an `InheritedWidget` wrapper alongside the store, making it
tree-accessible with no third-party dependency.

```dart
@LiveStore()
class _CartStore {
  List<Item> items = [];
  double get total => items.fold(0, (s, i) => s + i.price);
}
```

Generated (in addition to the existing `CartStore` ChangeNotifier):

```dart
class CartStoreProvider extends InheritedNotifier<CartStore> {
  const CartStoreProvider({
    super.key,
    required CartStore store,
    required super.child,
  }) : super(notifier: store);

  static CartStore of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<CartStoreProvider>();
    assert(provider != null, 'No CartStoreProvider found in widget tree.');
    return provider!.notifier!;
  }
}
```

Usage:

```dart
// Provide
CartStoreProvider(store: CartStore(), child: MyApp())

// Consume — rebuilds automatically when store notifies
final cart = CartStoreProvider.of(context);
```

Because it uses `InheritedNotifier`, dependent widgets rebuild automatically
when `CartStore` calls `notifyListeners()` — no extra wiring needed.

### Key decisions to make
- Opt-in flag on `@LiveStore(inherited: true)` vs always generated.
  Proposal: always generate it; dead code is stripped by tree-shaking and
  having it available by default removes a decision for the user.
- Whether to also generate a `CartStoreProvider.maybeOf` null-safe variant.

### Complexity
Low. `InheritedNotifier` does the heavy lifting. The generator just needs to
emit the wrapper class alongside the existing store output.

---

## Priority 3 — `@computed` fields

### Problem

Derived values that depend on reactive fields are recomputed on every `build()`
call today, even when their inputs haven't changed. For cheap derivations this
is fine; for expensive ones (sorting a large list, parsing structured data) it
causes unnecessary work.

### Proposed solution

A `@computed` annotation on a getter caches the result and only recomputes when
any reactive field it reads has changed since the last computation.

```dart
@Live()
class SearchPage extends _$SearchPage {
  String query  = '';
  List<Item> items = [];

  @computed
  List<Item> get results =>
      items.where((i) => i.name.contains(query)).toList();

  @override
  Widget build(BuildContext context) => ListView(
    children: results.map((i) => Text(i.name)).toList(),
  );
}
```

What gets generated:
- A nullable backing field `List<Item>? _$results`.
- A dirty flag `bool _$resultsDirty = true`.
- An override of every setter that feeds `results` to set `_$resultsDirty = true`.
- The getter returns the cached value when not dirty, recomputes and caches
  when dirty.

### Key decisions to make
- **Dependency tracking strategy.** Two options:
  1. *Static analysis*: parse the getter body at codegen time and enumerate
     which reactive fields it reads. Simple but breaks for helper-method
     indirection.
  2. *All-dirty on any setter*: mark every `@computed` getter dirty whenever
     any reactive setter fires. Simpler, correct, but loses the granularity
     benefit for widgets with many independent computed fields.
  Option 2 is the pragmatic starting point; option 1 can be layered on later.
- Whether `@computed` applies to `@LiveStore` as well as `@Live()` widgets.
  Proposal: yes — the pattern is identical, only the notification mechanism
  differs.

### Complexity
Medium-high. The code shape is straightforward, but the dependency-tracking
decision has long-term architectural implications. Starting with the all-dirty
strategy keeps it simple and correct; the static-analysis path is a future
upgrade.

---

## Not planned

| Idea | Reason skipped |
|------|----------------|
| Utility getters (`get theme`, `get mediaQuery`) | `context` valid only in `build()`; marginal savings; footgun risk |
| `@persist` / local storage wiring | Requires a storage dependency — breaks zero-deps |
| `@debounce` on setters | Arbitrary delay contradicts microtask batching design decision |
| `@readonly` fields | Niche; achievable today with a private field + public getter |
| Route-aware lifecycle hooks | Too framework-specific; Flutter's own Navigator handles this |

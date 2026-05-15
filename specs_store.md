# @LiveStore — implementation spec

> Companion to `specs.md`. Read that first for field classification rules, proxy
> generation, and collection wiring — this document covers only what differs for
> stores.

---

## Overview

`@LiveStore` turns a plain Dart class into a reactive `ChangeNotifier` with the
same zero-boilerplate experience as `@Live()`. The developer writes a class with
normal fields. The generator produces a concrete subclass with reactive
getters/setters and batched `notifyListeners()` — no manual `setState`, no
`ChangeNotifier` boilerplate.

**Same rule: one annotation, zero extra annotations.**

---

## Naming convention

Because the generated concrete class must be publicly usable (`UserStore()`) and
it cannot be placed in a `part` file under the same name as the user's class,
the user's class is written with a **leading underscore** (private spec). The
generator strips the `_` to produce the public class name.

| User writes | Generator creates |
|---|---|
| `class _UserStore extends _$UserStore` | `abstract class _$UserStore extends ChangeNotifier` |
| | `class UserStore extends _UserStore` ← public, instantiable |

This mirrors `@Live()`:

| Pattern | User writes | Generator creates (public) |
|---|---|---|
| Widget | `class CounterPage extends _$CounterPage` | `CounterPageWidget` (append `Widget`) |
| Store | `class _UserStore extends _$UserStore` | `UserStore` (strip `_`) |

---

## What the developer writes

```dart
// user_store.dart
part 'user_store.g.dart';

@LiveStore()
class _UserStore extends _$UserStore {
  // ── DI / constructor params ────────────────────────────────
  late final ApiService api;          // required constructor param
  late final LogService? logger;      // optional constructor param (nullable)

  // ── reactive scalars ───────────────────────────────────────
  String name    = 'Alice';
  int    age     = 30;
  bool   loading = false;

  // ── non-reactive constant ──────────────────────────────────
  final String appTitle = 'My App';

  // ── reactive collection ────────────────────────────────────
  List<String> tags = [];

  // ── disposable resource (auto-disposed) ───────────────────
  TextEditingController nameCtrl = TextEditingController();

  // ── owned child store (auto-disposed, listener wired) ─────
  CartStore cart = CartStore();

  // ── borrowed ChangeNotifier (listener wired, not disposed) ─
  late final SettingsStore settings;  // constructor param

  // ── methods ────────────────────────────────────────────────
  void updateName(String n) {
    name = n;   // reactive setter → _scheduleNotify()
    age++;
  }
}
```

Usage:
```dart
// Construct with DI params:
final store = UserStore(api: myApi, settings: settingsStore);

store.name = 'Bob';      // triggers notifyListeners() (batched)
store.tags.add('dart');  // LiveList → triggers notifyListeners()

// Pass to a @Live() widget:
UserProfileWidget(store: store)
```

---

## What gets generated

```dart
// user_store.g.dart — GENERATED, DO NOT MODIFY

// ── abstract base (ChangeNotifier + microtask batching) ──────

abstract class _$UserStore extends ChangeNotifier {
  bool _dirty = false;

  void _scheduleNotify() {
    if (_dirty) return;
    _dirty = true;
    Future.microtask(() {
      _dirty = false;
      notifyListeners();
    });
  }

  /// Trigger notifyListeners() manually — escape hatch for direct
  /// mutations not intercepted by a setter (e.g. nested object fields
  /// without a proxy).
  void notify() => _scheduleNotify();

  @mustCallSuper
  @override
  void dispose() => super.dispose();
}

// ── public concrete impl ─────────────────────────────────────

class UserStore extends _UserStore {

  // ── constructor params ─────────────────────────────────────
  // (set before any other initialization so they are readable from
  //  the parent class's field initializers if needed)

  UserStore({
    required ApiService api,
    LogService? logger,
    required SettingsStore settings,
  }) {
    super.api      = api;
    super.logger   = logger;
    super.settings = settings;

    // ── wire borrowed ChangeNotifier params ──────────────────
    settings.addListener(_scheduleNotify);

    // ── init reactive collections ────────────────────────────
    _$tags = LiveList.of(super.tags, _scheduleNotify);

    // ── wire owned child store ───────────────────────────────
    cart.addListener(_scheduleNotify);
  }

  // ── reactive scalar setters ──────────────────────────────────
  @override set name(String v)    { super.name    = v; _scheduleNotify(); }
  @override set age(int v)        { super.age     = v; _scheduleNotify(); }
  @override set loading(bool v)   { super.loading = v; _scheduleNotify(); }

  // ── owned ChangeNotifier / @LiveStore setter (re-wires listener) ─
  @override
  set cart(CartStore v) {
    super.cart.removeListener(_scheduleNotify);
    super.cart = v;
    v.addListener(_scheduleNotify);
    _scheduleNotify();
  }

  // ── reactive collection ──────────────────────────────────────
  late LiveList<String> _$tags;

  @override List<String> get tags => _$tags;

  @override
  set tags(List<String> v) {
    _$tags = LiveList.of(v, _scheduleNotify);
    _scheduleNotify();
  }

  // ── dispose ──────────────────────────────────────────────────
  @override
  void dispose() {
    nameCtrl.dispose();          // known disposable
    settings.removeListener(_scheduleNotify);  // borrowed CN — only remove
    cart.removeListener(_scheduleNotify);
    cart.dispose();              // owned @LiveStore — also dispose
    super.dispose();
  }
}
```

---

## Field classification rules

Same first-match-wins order as `@Live()`, with two differences:

| Field declaration | @Live() | @LiveStore() |
|---|---|---|
| `late final T x` (no init, not CN) | Widget constructor param | Store constructor param |
| `late final T x` (no init, T extends CN) | Widget param + listener + `didUpdateWidget` | Store constructor param + listener (no `didUpdateWidget`) |
| Everything else | Same | Same |

> `late final T x = expr` behaves identically in both: if CN, listener wired on
> first access; no param, no setter, no `didUpdateWidget`.

### Constructor params — `late final` without initializer

`late final` fields without an initializer become named constructor parameters
on the generated `UserStore(...)` class. Non-nullable → `required`. Nullable →
optional (defaults to `null`).

```dart
late final ApiService  api;       // required named param
late final LogService? logger;    // optional named param
late final SettingsStore settings; // required; also wires CN listener
```

Params are set via `super.field = value` at the TOP of the generated constructor
body — before collection init and listener wiring — so they are readable anywhere
inside the constructor.

### Auto-dispose rule for `@LiveStore` fields

A field whose type is annotated with `@LiveStore` **and** has an inline
initializer is treated as **owned**: the generator calls `.dispose()` on it
inside `dispose()`, in addition to removing the listener.

A `late final` field (no initializer) is **borrowed** — listener is removed in
`dispose()` but `.dispose()` is NOT called.

```dart
CartStore cart    = CartStore();   // owned  → removeListener + .dispose()
late final SettingsStore settings; // borrowed → removeListener only
late final SettingsStore s = GetIt.instance.get(); // borrowed → removeListener only
```

This rule applies both inside `@LiveStore` classes (nested stores) and inside
`@Live()` widgets (see Integration section).

---

## Integration with `@Live()` widgets

Since the generated `UserStore` extends `ChangeNotifier`, all three `@Live()`
declaration styles work automatically — the existing `@Live()` CN detection
handles registration and unregistration with no extra logic.

The only new behaviour is **auto-dispose of owned stores**:

### Case 1 — borrowed param: `late final UserStore store`

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  late final UserStore store;  // required widget param
}
```

Generated in the impl:
```dart
@override
void initState() {
  super.store = widget.store;
  super.initState();
  store.addListener(_scheduleRebuild);
}

@override
void didUpdateWidget(ProfilePageWidget old) {
  super.didUpdateWidget(old);
  bool _changed = false;
  if (widget.store != old.store) {
    old.store.removeListener(_scheduleRebuild);
    super.store = widget.store;
    store.addListener(_scheduleRebuild);
    _changed = true;
  }
  if (_changed) _scheduleRebuild();
}

@override
void dispose() {
  store.removeListener(_scheduleRebuild);
  // NO store.dispose() — widget does not own this store
  super.dispose();
}
```

### Case 2 — owned: `UserStore store = UserStore()`

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  UserStore store = UserStore(api: myApi, settings: s);
}
```

Generated:
```dart
@override
void initState() {
  super.initState();
  store.addListener(_scheduleRebuild);
}

@override
set store(UserStore v) {
  final _old = super.store;
  _old.removeListener(_scheduleRebuild);
  super.store = v;
  v.addListener(_scheduleRebuild);
  _scheduleRebuild();
}

@override
void dispose() {
  store.removeListener(_scheduleRebuild);
  store.dispose();   // owned @LiveStore — widget disposes it
  super.dispose();
}
```

### Case 3 — service-located: `late final UserStore store = GetIt.instance.get()`

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  late final UserStore store = GetIt.instance.get<UserStore>();
}
```

Generated:
```dart
@override
void initState() {
  super.initState();
  store.addListener(_scheduleRebuild);  // triggers lazy init
}

@override
void dispose() {
  store.removeListener(_scheduleRebuild);
  // NO store.dispose() — service locator owns it
  super.dispose();
}
```

### Auto-dispose detection in `@Live()`

The generator detects owned `@LiveStore` fields by checking two conditions:
1. The field type (or any of its direct supertypes) is annotated with `@LiveStore`
2. The field is **not** `final` and **has** an inline initializer

Both must be true to add `.dispose()`. The same ChangeNotifier listener wiring
that applies to all CN fields still runs regardless.

---

## Nested stores — `@LiveStore` inside `@LiveStore`

```dart
@LiveStore()
class _AppStore extends _$AppStore {
  UserStore userStore = UserStore(api: myApi, settings: s);  // owned
}
```

`UserStore` is a `ChangeNotifier`, so it is classified as an owned CN field.
The generator wires it in the constructor and disposes it:

```dart
class AppStore extends _AppStore {
  AppStore() {
    userStore.addListener(_scheduleNotify);
  }

  @override
  set userStore(UserStore v) {
    super.userStore.removeListener(_scheduleNotify);
    super.userStore = v;
    v.addListener(_scheduleNotify);
    _scheduleNotify();
  }

  @override
  void dispose() {
    userStore.removeListener(_scheduleNotify);
    userStore.dispose();  // owned @LiveStore
    super.dispose();
  }
}
```

Mutation chain: `userStore.name = 'Bob'` → `UserStore.notifyListeners()` →
`AppStore._scheduleNotify()` → `AppStore.notifyListeners()`. One microtask
per sync block at each level.

---

## Build ordering

`@Live()` and `@LiveStore()` are processed by the same `LivelyGenerator` in
a single `generate()` call per source file. This guarantees that proxy classes
shared between a `@Live` widget and a `@LiveStore` class in the same file are
emitted exactly once (shared `_emittedByFile` state).

For cross-file detection (e.g. `@Live()` widget detecting that a field type is
`@LiveStore` for auto-dispose), `build_runner` processes files in dependency
order: if `profile_page.dart` imports `user_store.dart`, `user_store.dart` is
analyzed first, so the `@LiveStore` annotation is visible on `_UserStore` when
the widget generator runs.

---

## Package structure additions

```
lively/
└── lib/
    └── src/
        └── annotations.dart   # add LiveStore class

lively_generator/
└── lib/
    ├── builder.dart            # register LivelyGenerator (replaces LiveWidgetGenerator)
    └── src/
        └── generator.dart     # add _generateStore(); refactor to Generator base
```

---

## Key decisions log

- Store user class uses `_` prefix (`_UserStore`) so the generator can emit
  the public concrete class (`UserStore`) with the same name users expect.
  Mirrors the `@Live()` convention of appending `Widget` to get the public name.
- `_scheduleNotify()` mirrors `_scheduleRebuild()` exactly — same microtask
  batching, same `_dirty` flag, but calls `notifyListeners()` instead of
  `setState()`.
- `notify()` escape hatch mirrors `@Live()` — same use case: mutations on nested
  objects not tracked by a proxy.
- `late final` (no init) in a store = constructor param, same semantics as
  `@Live()` widget params. Allows typed DI without extra annotations.
- Borrowed CN fields (params, service-located) → listener only, no `.dispose()`.
  Owned CN fields (inline init, `@LiveStore`-typed) → listener + `.dispose()`.
  Same auto-dispose heuristic as known disposable types in `@Live()`.
- `@Live()` and `@LiveStore()` share a single `Generator` subclass so proxy
  classes are deduplicated across both annotation types in the same file.
- No `didUpdateWidget` for stores — stores are not rebuilt by a parent widget
  passing new values. The setter re-wiring pattern handles replacement when a
  store field is reassigned.
- Known disposable types (`TextEditingController`, etc.) inside a store are
  auto-disposed in `dispose()` — same `_disposeMap` as `@Live()`.

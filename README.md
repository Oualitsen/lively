# lively

**Reactive Flutter widgets and stores with zero boilerplate.**

Write a plain Dart class. Add `@Live()` or `@LiveStore()`. Run `build_runner`.  
That's it — your widget or store is fully reactive.

```dart
@Live()
class CounterPage extends _$CounterPage {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(children: [
        Text('$count'),
        ElevatedButton(
          onPressed: () => count++, // ← just assign, rebuild happens
          child: const Text('+'),
        ),
      ]),
    ),
  );
}
```

No `setState`. No `ValueNotifier`. No `StreamController`. No `ChangeNotifier` boilerplate.  
Just a class, a field, and an assignment.

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  lively: ^1.0.0

dev_dependencies:
  lively_generator: ^1.0.0
  build_runner: ^2.0.0
```

Add `part 'your_file.g.dart';` to your source file, then run:

```sh
dart run build_runner build
# or watch mode:
dart run build_runner watch
```

---

## What gets generated

### `@Live()` — reactive widget

| Generated | Role |
|---|---|
| `CounterPageWidget` | Thin `StatefulWidget` — use this in your tree |
| `_$CounterPage` | Abstract `State` base with microtask batching |
| `_CounterPageImpl` | Concrete `State` that wires reactive setters |

### `@LiveStore()` — reactive store

| Generated | Role |
|---|---|
| `_$CartStore` | Abstract `ChangeNotifier` base with microtask batching |
| `CartStore` | Concrete class with reactive setters — instantiate this |

You write the logic. The generator writes the boilerplate.

---

## Features

### Reactive fields — automatic `setState`

Any mutable field that appears in `build()` gets a setter override that
schedules a batched rebuild via `Future.microtask`. Multiple assignments in
the same synchronous block produce exactly **one** rebuild.

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  String name = 'Alice';
  int    age  = 30;

  @override
  Widget build(BuildContext context) => Text('$name, $age');

  void birthday() {
    name = 'Alice (older)'; // schedules rebuild
    age++;                  // dirty flag already set — no extra rebuild
  }                         // → ONE rebuild fires after the sync block
}
```

### Reactive fields — all mutable fields are wired

Every mutable field gets a setter that schedules a rebuild. Call `notify()` when
you need a rebuild that wouldn't happen automatically (e.g. direct mutation of a
private field or an untracked object).

```dart
@Live()
class MyPage extends _$MyPage {
  int    counter = 0;  // wired — setter schedules rebuild ✓
  String log     = ''; // also wired

  @override
  Widget build(BuildContext context) => Text('$counter');
}
```

### Widget parameters — `late final` fields

`late final` fields **without an initializer** become constructor parameters
on the generated widget. Non-nullable types become `required`; nullable types
are optional. When the parent rebuilds with new values, the widget updates
automatically — no manual `didUpdateWidget` needed.

```dart
@Live()
class CounterPage extends _$CounterPage {
  late final int    initialValue; // required param
  late final String? title;       // optional param

  int count = 0;

  @override
  void initState() {
    super.initState(); // params are ready here
    count = initialValue;
  }
}

// Usage:
CounterPageWidget(initialValue: 10)
CounterPageWidget(initialValue: 0, title: 'My Counter')
```

### Disposable resources — automatic cleanup

Known disposable types are detected by type alone — no annotation required.
Nullable fields use `?.` calls so `null` values are safely skipped.

| Type | Cleanup |
|---|---|
| `TextEditingController` | `.dispose()` |
| `AnimationController` | `.dispose()` |
| `FocusNode` | `.dispose()` |
| `ScrollController` | `.dispose()` |
| `PageController` | `.dispose()` |
| `StreamController` | `.close()` |
| `StreamSubscription` | `.cancel()` |

```dart
@Live()
class FormPage extends _$FormPage {
  TextEditingController nameCtrl  = TextEditingController();
  FocusNode             nameFocus = FocusNode();
  TextEditingController? optCtrl; // nullable — disposed with ?.dispose()
  // ↑ all disposed automatically — no @override dispose() needed
}
```

### `ChangeNotifier` integration

Fields whose type extends `ChangeNotifier` are automatically wired with
`addListener` / `removeListener`. When the model calls `notifyListeners()`, the
widget rebuilds. Three declaration styles are supported:

**Mutable field** — widget owns the instance; setter re-wires on replacement:
```dart
@Live()
class UserPage extends _$UserPage {
  UserModel model = UserModel();
  // model.rename('Bob') → notifyListeners() → rebuild ✓
  // model = UserModel() → old listener removed, new one added ✓
}
```

**`late final` param** — instance injected from outside; `didUpdateWidget`
re-wires when the parent swaps the store:
```dart
@Live()
class UserPage extends _$UserPage {
  late final UserModel model; // required constructor param

  @override
  Widget build(BuildContext context) => Text(model.name);
}

// Usage:
UserPageWidget(model: sharedModel)
```

**`late final` with initializer** — lazily resolved at first access (e.g.
from a service locator); listener wired in `initState`, removed in `dispose`:
```dart
@Live()
class UserPage extends _$UserPage {
  late final UserModel model = GetIt.instance.get<UserModel>();
}
```

### `@LiveStore` — shareable reactive state

`@LiveStore` turns a plain Dart class into a reactive `ChangeNotifier` with the
same zero-boilerplate experience as `@Live()`. Use it when state needs to live
outside a single widget — across navigation, shared between siblings, or injected
as a dependency.

**Naming convention:** prefix your spec class with `_`. The generator strips the
underscore to produce the public class name, mirroring how `@Live()` appends
`Widget`.

```dart
// cart_store.dart
part 'cart_store.g.dart';

@LiveStore()
class _CartStore extends _$CartStore {
  List<CartItem> items = [];

  double get total => items.fold(0.0, (sum, item) => sum + item.price);

  void add(CartItem item)    => items.add(item);
  void remove(CartItem item) => items.remove(item);
  void clear()               => items.clear();
}
```

The generator produces:

```dart
// cart_store.g.dart — GENERATED
abstract class _$CartStore extends ChangeNotifier {
  void _scheduleNotify() { /* Future.microtask batching */ }
  void notify() => _scheduleNotify(); // manual escape hatch
  @mustCallSuper @override void dispose() => super.dispose();
}

class CartStore extends _CartStore {
  late LiveList<CartItem> _$items;
  @override List<CartItem> get items => _$items;
  @override set items(List<CartItem> v) { _$items = LiveList.of(v, _scheduleNotify); _scheduleNotify(); }

  CartStore() {
    _$items = LiveList.of(super.items, _scheduleNotify);
  }
}
```

#### Using a store in a `@Live()` widget

Since `CartStore` is a `ChangeNotifier`, all three `@Live()` declaration patterns
work automatically.

**Owned** — widget creates, wires, and disposes the store:
```dart
@Live()
class CartPage extends _$CartPage {
  // Inline initializer → lively detects ownership →
  // adds cart.addListener in initState and cart.dispose() in dispose().
  final CartStore cart = CartStore();

  @override
  void initState() {
    super.initState();
    cart.addListener(notify); // wire manually when field is `final`
  }

  @override
  void dispose() {
    cart.removeListener(notify);
    cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('${cart.items.length} items');
}
```

**Borrowed param** — store lives outside, widget borrows it:
```dart
@Live()
class CartPage extends _$CartPage {
  late final CartStore cart; // required constructor param
                              // addListener/removeListener/didUpdateWidget auto-generated
                              // cart.dispose() NOT called — caller owns the store
}

// Usage:
CartPageWidget(cart: sharedCart)
```

**Service-located** — lazy resolution, listener wired on first access:
```dart
@Live()
class CartPage extends _$CartPage {
  late final CartStore cart = GetIt.instance.get<CartStore>();
  // addListener in initState, removeListener in dispose — no dispose() call
}
```

#### DI constructor params

`late final` fields without an initializer become named constructor parameters
on the generated store class — the same pattern as widget params with `@Live()`:

```dart
@LiveStore()
class _CartStore extends _$CartStore {
  late final ApiService  api;    // required — CartStore({required ApiService api, ...})
  late final Logger?     logger; // optional
  List<CartItem> items = [];
}

final cart = CartStore(api: getIt<ApiService>());
```

Params are set at the top of the generated constructor, before listener wiring
and collection initialisation, so they are safe to access from any field
initializer.

#### Nested stores

A `@LiveStore` field inside another `@LiveStore` is auto-wired the same way as
any other `ChangeNotifier` field. Mutations on the child bubble up through
`notifyListeners()`:

```dart
@LiveStore()
class _AppStore extends _$AppStore {
  CartStore cart = CartStore(); // owned child store
  // → addListener in ctor, removeListener + .dispose() in dispose()
  // → cart.items.add(...) → CartStore.notifyListeners() → AppStore._scheduleNotify()
}
```

#### File-ordering note

Put `@LiveStore` classes in a **separate file** from the `@Live()` widgets that
reference the generated store class. `build_runner` generates files in dependency
order; if both are in the same file, the generated store type is not yet visible
when the widget is analysed.

```
cart_store.dart   ← @LiveStore here
cart_page.dart    ← import 'cart_store.dart'; @Live here
```

### Deep object reactivity — `_Live` proxy subclasses

For plain mutable classes (no annotation needed), `lively_generator`
generates a `_Live<ClassName>` proxy subclass that intercepts every field
setter and triggers a rebuild. This works recursively through nested objects.

```dart
class Address { String street = '123 Main'; String city = 'Springfield'; }
class User    { String name = 'Alice'; int age = 30; Address address = Address(); }

@Live()
class UserPage extends _$UserPage {
  User user = User();

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(user.name),
    Text(user.address.street),
  ]);

  void move() {
    user.name            = 'Bob';           // rebuild ✓
    user.address.street  = '456 Oak Ave';   // rebuild ✓ — deep mutation
  }
}
```

**Constraints:** the nested class must have a no-arg (or all-optional)
constructor; `final` / `sealed` classes fall back to plain reactive setters;
private fields (`_`) are never proxied.

### Reactive collections — `LiveList`, `LiveSet`, `LiveMap`

`List<T>`, `Set<T>`, and `Map<K, V>` fields are backed by reactive wrappers
that notify on every structural mutation (`add`, `remove`, `clear`, etc.).
When `T` / `V` / `K` is a proxyable class, items are automatically wrapped as
`_Live<T>` proxies on entry — so field-level mutations on items also trigger
rebuilds with no manual call needed. Works in both `@Live()` widgets and
`@LiveStore` classes.

```dart
class Car { String make = 'Toyota'; String color = 'white'; }

@Live()
class GaragePage extends _$GaragePage {
  List<Car> cars = [];

  void addCar()        => cars.add(Car());       // structural → rebuild ✓
  void paintRed(Car c) => c.color = 'red';       // item mutation → rebuild ✓
  void remove(Car c)   => cars.remove(c);         // structural → rebuild ✓
}
```

### `notify()` — manual escape hatch

Every `@Live()` class and `@LiveStore` class inherits a `notify()` method that
manually schedules a rebuild / `notifyListeners()`. Use it when you mutate state
that isn't tracked automatically.

```dart
logEntry = 'updated'; // silent field
notify();             // explicit rebuild / notifyListeners()
```

### `final` fields — non-reactive constants

Fields declared `final` with an initializer are passed through unchanged — no
setter, no backing field, no rebuild.

```dart
@Live()
class MyPage extends _$MyPage {
  final String appName = 'My App'; // plain constant, no codegen
}
```

---

## Field classification — quick reference

### `@Live()` widget fields

| Declaration | Classification | Effect |
|---|---|---|
| `late final T x` (no init) | Widget param | Required constructor arg; set before `initState` |
| `late final T? x` (nullable, no init) | Widget param | Optional constructor arg |
| `late final T x` where T extends CN (no init) | Widget param + listener | Param **and** `addListener`; `didUpdateWidget` re-wires on swap |
| `late final T x = expr` where T extends CN | Listener only | `addListener` in `initState`; no param, no setter |
| `final T x = v` | Constant | No codegen |
| `TextEditingController x` | Disposable | Auto-disposed in `dispose()` |
| `T x` where T is `@LiveStore` with init | Owned store | Listener + `dispose()` in `dispose()` |
| `T x` where T extends ChangeNotifier | ChangeNotifier | Listener wired; setter re-wires on replacement |
| `T x` where T is a proxyable class | Proxy object | `_LiveT` subclass generated |
| `List<T> x` / `Set<T> x` / `Map<K,V> x` | Collection | Backed by `LiveList` / `LiveSet` / `LiveMap` |
| `T x` (primitive / other) | Reactive scalar | Setter always calls `_scheduleRebuild()` |

### `@LiveStore` class fields

Same classification rules apply, with these differences:

| Declaration | Classification | Effect |
|---|---|---|
| `late final T x` (no init, not CN) | Constructor param | `CartStore({required T x})` |
| `late final T x` (no init, T extends CN) | Constructor param + listener | Param + `addListener` in constructor |
| `late final T x = expr` (T extends CN) | Listener only | `addListener` in constructor |
| `T x` where T is `@LiveStore` with init | Owned store | Listener + `dispose()` in `dispose()` |
| Everything else | Same as `@Live()` | — |

---

## Design philosophy

- **Two annotations.** `@Live()` for widget-local state, `@LiveStore()` for shareable state. No other annotations needed.
- **Zero runtime dependencies.** Pure Flutter + Dart — no rxdart, no GetX, no Provider.
- **Zero new concepts.** Fields are fields. Assignments are assignments. The generator handles everything else.
- **Microtask batching.** Multiple field mutations in one synchronous block produce exactly one rebuild / `notifyListeners()`, with no arbitrary delay.
- **Predictable rebuilds.** Every mutable field is wired — no silent non-rebuilds from helper-method blind spots. Use `notify()` for the rare case where you need manual control.
- **Keep widgets small.** Full widget rebuilds are cheap when widgets are focused. Split large widgets rather than reaching for granular rebuild primitives.

---

## Comparison with other approaches

### Scope

Lively covers both **local widget state** (`@Live()`) and **shareable reactive
state** (`@LiveStore()`). It does not provide dependency injection or a global
store container — use Riverpod or Provider on top for the injection layer if you
need it. They compose naturally.

---

### Feature matrix

| | setState | ChangeNotifier + Provider | Riverpod | Bloc / Cubit | MobX | GetX | **Lively** |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Setup | none | package | package | package | package + codegen | package | package + codegen |
| New concepts to learn | none | `notifyListeners`, `Consumer` | providers, `ref`, `AsyncValue` | events, states, streams | `@observable`, `@action`, `Observer` | `.obs`, `Obx` | **none** |
| Code generation | — | — | optional | — | required | — | required |
| Local widget state | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Shared / global state | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Computed / derived values | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ |
| Deep object reactivity | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Auto-dispose controllers | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Batched rebuilds | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Runtime Flutter dependency | Flutter | Provider | Riverpod | flutter_bloc | mobx | get | **Flutter only** |

---

### Side-by-side: a counter with two fields

**Plain `setState`**
```dart
class _CounterState extends State<CounterPage> {
  int count = 0;
  String label = 'hits';

  @override
  Widget build(BuildContext context) => Column(children: [
    Text('$count $label'),
    ElevatedButton(
      onPressed: () => setState(() { count++; }),
      child: const Text('+'),
    ),
  ]);
}
```

**ChangeNotifier + Provider**
```dart
class CounterModel extends ChangeNotifier {
  int count = 0;
  String label = 'hits';

  void increment() { count++; notifyListeners(); }
}

// in widget tree — must be provided above this widget
class CounterPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final m = context.watch<CounterModel>();
    return Column(children: [
      Text('${m.count} ${m.label}'),
      ElevatedButton(onPressed: context.read<CounterModel>().increment,
          child: const Text('+')),
    ]);
  }
}
```

**MobX** (closest conceptual alternative)
```dart
part 'counter.g.dart';

class CounterStore = _CounterStore with _$CounterStore;

abstract class _CounterStore with Store {
  @observable int count = 0;
  @observable String label = 'hits';

  @action void increment() => count++;
}

// in widget:
class CounterPage extends StatelessWidget {
  final store = CounterStore();
  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) => Column(children: [
      Text('${store.count} ${store.label}'),
      ElevatedButton(onPressed: store.increment, child: const Text('+')),
    ]),
  );
}
```

**Lively**
```dart
@Live()
class CounterPage extends _$CounterPage {
  int count = 0;
  String label = 'hits';

  @override
  Widget build(BuildContext context) => Column(children: [
    Text('$count $label'),
    ElevatedButton(
      onPressed: () => count++,
      child: const Text('+'),
    ),
  ]);
}
```

---

### When to use Lively

**Good fit:**
- Form pages, detail screens, local UI state (loading flags, tab selection, input values).
- Widgets that own their state entirely — nothing needs to be shared.
- Shared state objects (`@LiveStore`) passed to multiple widgets via constructor params or a service locator.
- Teams that want plain Dart classes without learning a reactive framework.
- Projects where you already use `build_runner` (e.g. for JSON serialisation).

**Not a good fit:**
- You need computed/derived values that update automatically (`@computed` in MobX, `Provider.select`, `ref.watch` selectors in Riverpod).
- You need time-travel debugging or strict audit trails of state changes (Bloc is better here).
- You want to avoid a build step entirely (GetX or plain `ValueNotifier` have no codegen).

---

### Lively vs MobX — the closest comparison

Both use `build_runner`. The key differences:

| | MobX | Lively |
|---|---|---|
| Store / widget separation | always split — store class required | optional — `@Live()` embeds state in the widget; `@LiveStore()` extracts it |
| Widget wrapping needed | `Observer(builder: ...)` wraps every reactive subtree | plain `build()` — no wrapper |
| Granularity | rebuilds only the `Observer` that accessed the changed value | rebuilds the whole widget (use `Reactive` to opt in to subtree granularity) |
| Auto-dispose | no | yes — controllers disposed by type detection |
| Deep object reactivity | no | yes — `_Live<T>` proxies intercept nested field setters |
| Computed values | yes — `@computed` | no |
| Concepts to learn | `@observable`, `@action`, `@computed`, `Observer`, `reaction`, `autorun` | none |

MobX is the right choice when you need fine-grained `Observer` subtrees or
computed values. Lively is the right choice when you want plain field assignments
with no ceremony, and optionally shareable store objects without learning a new
reactive model.

---

## The `Reactive` wrapper — surgical opt-in

When profiling reveals a genuine performance bottleneck, use the `Reactive`
widget to rebuild only a subtree when specific values change.

```dart
Reactive(
  watch: [counter],
  builder: () => Text('$counter'),
)
```

This is rarely needed. Most widgets are fast enough with plain `setState`.

---

## Related tools

If your Flutter app communicates with a **GraphQL API**, check out
[GraphLink](https://pub.dev/packages/graphlink) — a code generator that reads
a `.graphql` schema and produces fully-typed Dart/Flutter clients (and
optionally Java or Spring Boot server stubs) with zero runtime dependency.
Works well alongside Lively: generate your GraphQL layer once with `glink`,
then use Lively for the rest of your app's code generation needs.

> **GraphQL user?** Pair Lively with [GraphLink](https://pub.dev/packages/graphlink)
> to auto-generate your typed Flutter GraphQL client from a `.graphql` schema.

- pub.dev: https://pub.dev/packages/graphlink
- GitHub: https://github.com/Oualitsen/graphlink
- Docs: https://graphlink.dev/docs/index.html

# lively — AI Agent Usage Guide

> This guide is written for an AI agent generating or assisting with `lively`-based Flutter code.
> Read it fully before producing any code. The rules are strict and order-dependent.

---

## What lively does

`lively` is a Flutter code-generation package. The developer writes a plain Dart class; `build_runner` generates the full `StatefulWidget` + `State` boilerplate. The result:

- Reactive fields with batched `setState` via `Future.microtask()`
- Auto-disposal of known resource types
- Deep reactivity through proxy objects and live collections
- Zero runtime dependencies beyond Flutter itself

Two annotations exist: `@Live()` for widgets, `@LiveStore()` for reactive `ChangeNotifier` stores.

---

## Setup

**User's `pubspec.yaml`:**
```yaml
dependencies:
  lively: ^1.0.0

dev_dependencies:
  lively_generator: ^1.0.0
  build_runner: ^2.0.0
```

**Every source file using these annotations must declare a part file:**
```dart
part 'my_file.g.dart';
```

**Run generation:**
```bash
dart run build_runner build
# or watch mode:
dart run build_runner watch
```

---

## @Live() — Reactive Widgets

### Minimal example

```dart
// counter_page.dart
part 'counter_page.g.dart';

@Live()
class CounterPage extends _$CounterPage {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => count++,  // triggers rebuild automatically
      child: Text('$count'),
    );
  }
}
```

**Usage in widget tree:**
```dart
CounterPageWidget()   // generated name = class name + "Widget"
```

### Naming rule

| User writes | Generated widget name |
|---|---|
| `class FooPage extends _$FooPage` | `FooPageWidget` |
| `class MyScreen extends _$MyScreen` | `MyScreenWidget` |

The user class always extends `_$ClassName` (leading `_$`). The generated file provides that abstract base.

---

## Field classification — @Live()

**First-match-wins order. Apply top to bottom.**

| Priority | Field declaration | Behavior |
|---|---|---|
| 1 | `late final T x` (no init, T not CN, not disposable) | Widget constructor param |
| 2 | `late final T x` (no init, T extends ChangeNotifier) | Widget param + CN listener + `didUpdateWidget` |
| 3 | `late final T x = expr` (T extends ChangeNotifier) | CN listener only — no param, no setter |
| 4 | `final T x = expr` (not late) | Non-reactive constant — no codegen |
| 5 | Disposable type with initializer | Auto-disposed in `dispose()` |
| 6 | ChangeNotifier subclass (mutable field, has init) | Listener wired; setter re-wires on replacement |
| 7 | Plain user-defined class (mutable) | `_Live<ClassName>` proxy generated — deep reactivity |
| 8 | `List<T>` | Backed by `LiveList<T>` |
| 9 | `Set<T>` | Backed by `LiveSet<T>` |
| 10 | `Map<K, V>` | Backed by `LiveMap<K, V>` |
| 11 | Everything else mutable | Reactive scalar — setter calls `_scheduleRebuild()` |

**Disposable types** (checked before ChangeNotifier):
- `TextEditingController` → `.dispose()`
- `AnimationController` → `.dispose()`
- `FocusNode` → `.dispose()`
- `StreamController` → `.close()`
- Other known disposables → `.dispose()` or `.close()` or `.cancel()` depending on type

---

## Widget constructor params — `late final` fields

`late final` without an initializer = widget parameter. Params are set before `initState()` runs.

```dart
@Live()
class ProfilePage extends _$ProfilePage {
  late final String title;    // required param (non-nullable)
  late final int?   subtitle; // optional param (nullable → defaults to null)

  int count = 0;

  @override
  void initState() {
    super.initState();
    // title and subtitle are already set here — safe to read
  }
}
```

**Generated widget:**
```dart
ProfilePageWidget(title: 'Hello')           // subtitle omitted — OK
ProfilePageWidget(title: 'Hello', subtitle: 42)
```

**Rules:**
- Non-nullable `late final T x` → `required` named param
- Nullable `late final T? x` → optional named param (no `required`)
- `late final T x = expr` (has initializer) → NOT a param; treated as a non-reactive constant

---

## Reactive scalars

Every mutable non-final field becomes reactive. All setters call `_scheduleRebuild()` unconditionally — there is no analysis of what `build()` reads.

```dart
String name = 'John';   // setter generated → any assignment triggers rebuild
int age     = 25;
bool loading = false;

final String appTitle = 'My App';  // final → NO setter, NO reactivity
```

**Batching:** Multiple assignments in one sync block schedule exactly one rebuild via `Future.microtask()`.

```dart
name = 'Jane';  // schedules microtask
age  = 30;      // microtask already scheduled — skipped
// one rebuild fires after the sync block
```

---

## Reactive collections

### List and Set

```dart
List<String> tags  = [];
Set<String>  roles = {};
```

Backed by `LiveList<String>` and `LiveSet<String>`. Every mutating operation triggers a rebuild:

```dart
tags.add('flutter');
tags.remove('flutter');
tags.clear();
tags[0] = 'dart';
roles.add('admin');
```

### Map

```dart
Map<String, Car> garage = {};
```

Backed by `LiveMap<String, Car>`. Structural ops always trigger rebuild:

```dart
garage['tesla'] = Car();    // rebuild
garage.remove('tesla');     // rebuild
garage.clear();             // rebuild
```

**Key wrapping constraint:** Key wrapping is safe only for types with value-based equality (`String`, `int`, etc.). Avoid using identity-based objects as map keys — lookup breaks after wrapping because the proxy is a different object.

### Item-level mutation (when T is proxyable)

When `T` is a plain user-defined class, items entering a collection are wrapped in `_LiveT`. Mutations on any item also trigger a rebuild:

```dart
cars.add(Car());          // stored as _LiveCar internally
cars[0].color = 'red';   // _LiveCar setter → rebuild ✓
```

---

## Proxy objects — deep reactivity

When a mutable field's type is a plain user-defined class (not a known disposable, not ChangeNotifier, not a collection, not a primitive), the generator produces a `_Live<ClassName>` subclass.

```dart
class Address {
  String street = '123 Main St';
  String city   = 'Springfield';
}

class User {
  String  name    = 'Alice';
  Address address = Address();
}

@Live()
class UserPage extends _$UserPage {
  User user = User();
}
```

All of these trigger rebuilds automatically:
```dart
user.name = 'Bob';                    // ✓
user.address.street = '456 Oak Ave';  // ✓ (nested proxy)
user = User();                        // ✓ (re-wraps with new proxy)
```

**Proxy constraints — when proxy is NOT generated:**
- Class is `final` or `sealed` (cannot be subclassed)
- Class has no no-arg (or all-optional) constructor
- Private fields (`_field`) on nested classes — cannot be overridden from outside the library
- `final` fields on nested classes — not overridden, pass through as-is
- Cycles (`A → B → A`) — second encounter treated as a leaf, no proxy at that depth

When proxy cannot be generated, field falls back to plain reactive scalar (rebuilds only on reference replacement, not on deep mutation).

---

## ChangeNotifier integration

Three patterns, all auto-detected:

### Pattern 1 — owned mutable field

```dart
UserModel user = UserModel();
```

- `addListener` in `initState`
- setter removes old listener, adds new one, schedules rebuild
- `removeListener` in `dispose` (NOT `.dispose()` — ownership is ambiguous)

### Pattern 2 — borrowed param (`late final`, no init)

```dart
late final UserModel store;
```

- Widget constructor param (required)
- `addListener` in `initState` (after param is set)
- `didUpdateWidget` re-wires listener when parent passes a new store instance
- `removeListener` in `dispose`

### Pattern 3 — service-located (`late final` with init)

```dart
late final UserModel store = GetIt.instance.get<UserModel>();
```

- `addListener` in `initState` (triggers lazy init)
- `removeListener` in `dispose`
- No constructor param, no setter, no `didUpdateWidget`

---

## Escape hatch — `notify()`

Call `notify()` (generated on the State) to force a rebuild when a mutation isn't intercepted by a setter. Example: direct mutation of a private backing field, or a nested object without a proxy.

---

## @LiveStore() — Reactive Stores

### Purpose

Turns a plain class into a reactive `ChangeNotifier`. Use for shared state that multiple widgets observe.

### Naming convention — CRITICAL

The user writes the class with a **leading underscore**. The generator strips it to produce the public name.

| User writes | Generated public class |
|---|---|
| `class _UserStore extends _$UserStore` | `UserStore` |
| `class _AppStore extends _$AppStore` | `AppStore` |

```dart
// user_store.dart
part 'user_store.g.dart';

@LiveStore()
class _UserStore extends _$UserStore {
  String name = 'Alice';
  int    age  = 30;
}
```

```dart
// Usage:
final store = UserStore();
store.name = 'Bob';  // triggers notifyListeners() (batched)
```

### Field classification — @LiveStore()

Same first-match-wins order as `@Live()`, with these differences:

| Field | @Live() | @LiveStore() |
|---|---|---|
| `late final T x` (no init, not CN) | Widget param | Constructor param |
| `late final T x` (no init, T extends CN) | Widget param + listener + `didUpdateWidget` | Constructor param + listener (no `didUpdateWidget`) |
| Everything else | Same | Same |

### Constructor params in stores

```dart
@LiveStore()
class _UserStore extends _$UserStore {
  late final ApiService  api;       // required: UserStore(api: ...)
  late final LogService? logger;    // optional: UserStore(logger: ...)
  late final SettingsStore settings; // required + CN listener wired
}
```

Params are set at the TOP of the generated constructor body, before any listener wiring or collection init.

### Owned vs. borrowed @LiveStore fields

| Declaration | Ownership | dispose() behavior |
|---|---|---|
| `CartStore cart = CartStore()` | Owned (has inline init) | `removeListener` + `cart.dispose()` |
| `late final SettingsStore s` (param) | Borrowed | `removeListener` only |
| `late final SettingsStore s = GetIt.instance.get()` | Borrowed | `removeListener` only |

This same rule applies inside `@Live()` widgets holding `@LiveStore`-typed fields.

### Batching in stores

Same microtask batching as `@Live()`, but calls `notifyListeners()` instead of `setState()`. The method is `_scheduleNotify()` internally, and `notify()` is the public escape hatch.

---

## Integration — @LiveStore inside @Live()

Since generated stores extend `ChangeNotifier`, all three CN patterns from above apply automatically. The only extra behavior is auto-dispose detection.

**Borrowed param — NO dispose:**
```dart
@Live()
class ProfilePage extends _$ProfilePage {
  late final UserStore store;  // widget param; widget does NOT own it
}
// dispose() → removeListener only
```

**Owned inline — YES dispose:**
```dart
@Live()
class ProfilePage extends _$ProfilePage {
  UserStore store = UserStore(api: myApi, settings: s);  // widget owns it
}
// dispose() → removeListener + store.dispose()
```

**Service-located — NO dispose:**
```dart
@Live()
class ProfilePage extends _$ProfilePage {
  late final UserStore store = GetIt.instance.get<UserStore>();
}
// dispose() → removeListener only
```

**Auto-dispose detection conditions (both must be true):**
1. Field type is annotated with `@LiveStore` (or has `@LiveStore`-annotated supertype)
2. Field is NOT `final` AND HAS an inline initializer

---

## Nested stores — @LiveStore inside @LiveStore

```dart
@LiveStore()
class _AppStore extends _$AppStore {
  UserStore userStore = UserStore(api: myApi, settings: s);  // owned
}
```

`UserStore` is a ChangeNotifier, classified as owned CN field. Constructor wires listener; `dispose()` calls `removeListener` + `userStore.dispose()`.

Mutation chain: `userStore.name = 'Bob'` → `UserStore.notifyListeners()` → `AppStore._scheduleNotify()` → `AppStore.notifyListeners()`. One microtask per sync block at each level.

---

## Reactive widget — `Reactive`

Use for surgical rebuilds of a subtree when profiling shows a real problem. Do not reach for this by default — full widget rebuilds on small widgets are fast enough.

```dart
Reactive(
  watch: [name],
  builder: () => Text(name),
)
```

Rebuilds only when `name` changes (detected by `listEquals` on the `watch` list), not when other fields change.

---

## Package structure

```
lively/
├── lib/
│   ├── lively.dart             # public API: exports @Live, @LiveStore, Reactive, LiveList, LiveSet, LiveMap
│   └── src/
│       ├── annotations.dart    # Live, LiveStore
│       ├── reactive.dart       # Reactive widget
│       ├── live_list.dart      # LiveList<T>
│       ├── live_set.dart       # LiveSet<T>
│       └── live_map.dart       # LiveMap<K, V>
├── test/
│   └── live_collections_test.dart
└── lively_generator/
    ├── lib/
    │   ├── builder.dart        # build_runner entry point
    │   └── src/
    │       └── generator.dart  # GeneratorForAnnotation<Live> + @LiveStore logic
    └── test/
        └── generator_test.dart
```

---

## Complete @Live() example

```dart
part 'profile_page.g.dart';

@Live()
class ProfilePage extends _$ProfilePage {
  // widget params (required + optional)
  late final String title;
  late final int?   subtitle;

  // reactive scalars
  String name     = 'John';
  int    age      = 25;
  bool   isLoading = false;

  // non-reactive constant
  final String appTitle = 'My App';

  // auto-disposed resources
  TextEditingController nameCtrl = TextEditingController();
  FocusNode             focusNode = FocusNode();
  StreamController      counter   = StreamController();

  // reactive collection
  List<String> tags = [];

  @override
  void initState() {
    super.initState();
    // title and subtitle are already available here
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(title),
      Text(name),
      TextField(controller: nameCtrl),
      ElevatedButton(
        onPressed: () {
          name = 'Jane';  // both in one sync block
          age  = 30;      // ONE rebuild fires
        },
        child: const Text('Update'),
      ),
    ]);
  }
}

// Usage:
ProfilePageWidget(title: 'My Profile')
ProfilePageWidget(title: 'My Profile', subtitle: 42)
```

---

## Complete @LiveStore() example

```dart
part 'user_store.g.dart';

@LiveStore()
class _UserStore extends _$UserStore {
  // constructor params (DI)
  late final ApiService  api;
  late final LogService? logger;

  // reactive scalars
  String name    = 'Alice';
  int    age     = 30;
  bool   loading = false;

  // non-reactive constant
  final String appTitle = 'My App';

  // reactive collection
  List<String> tags = [];

  // auto-disposed resource
  TextEditingController nameCtrl = TextEditingController();

  // owned child store (listener wired + auto-disposed)
  CartStore cart = CartStore();

  // borrowed CN (listener wired, not disposed)
  late final SettingsStore settings;

  void updateName(String n) {
    name = n;
    age++;  // batched — one notifyListeners()
  }
}

// Usage:
final store = UserStore(api: myApi, settings: settingsStore);
store.name = 'Bob';
store.tags.add('dart');
```

---

## Quick decision table for field declarations

| I want... | Write this |
|---|---|
| A required widget param | `late final String title;` |
| An optional widget param | `late final String? title;` |
| A reactive field | `String name = 'John';` |
| A non-reactive constant | `final String appTitle = 'App';` |
| An auto-disposed controller | `TextEditingController ctrl = TextEditingController();` |
| A reactive list | `List<String> items = [];` |
| A reactive map | `Map<String, User> users = {};` |
| Borrowed ChangeNotifier param | `late final MyStore store;` (in @Live()) or store (in @LiveStore()) |
| Owned ChangeNotifier | `MyStore store = MyStore();` |
| Service-located store | `late final MyStore store = GetIt.instance.get();` |
| Force a rebuild manually | Call `notify()` inside the class |

---

## Common mistakes to avoid

1. **Wrong base class.** `@Live()` → `extends _$ClassName`. `@LiveStore()` → `extends _$_ClassName` (leading underscore on both the user class and the base). The user class for stores has a `_` prefix.

2. **Missing `part` directive.** Every file using these annotations needs `part 'filename.g.dart';` at the top.

3. **Using `final` when you want a param.** `final String title = 'x'` is a non-reactive constant, not a param. Use `late final String title;` (no initializer) for a param.

4. **Expecting deep reactivity without proxy support.** If the nested class is `final`, `sealed`, has no accessible default constructor, or uses private fields — deep mutation won't trigger rebuilds. Only reference replacement does.

5. **Using identity-based objects as Map keys.** `Map<Car, String>` where `Car` doesn't override `==`/`hashCode` will break after key wrapping. Use primitives or value-equality types as keys.

6. **Calling `.dispose()` on a borrowed ChangeNotifier.** `lively` deliberately does NOT call `.dispose()` on borrowed CNs (params, service-located). If the widget/store owns the CN, give it an inline initializer so auto-dispose activates.

7. **Expecting `notify()` to be available outside the class.** `notify()` is a protected escape hatch on the generated base — call it from inside the user class only.

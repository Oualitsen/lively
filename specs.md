# lively — implementation spec

> Zero dependencies. Pure Flutter + Dart. Code generation via `build_runner`.

---

## Overview

`lively` is a code-generation package that makes Flutter widgets reactive with
zero boilerplate. The developer writes a plain Dart class with normal fields and a
`build()` method. The generator produces the full `StatefulWidget` + `State`
boilerplate, with getters/setters and batched `setState` triggered automatically.

**One annotation. Zero extra annotations. Zero runtime dependencies.**

---

## What the developer writes

```dart
// profile_page.dart
part 'profile_page.g.dart';

@Live()
class ProfilePage extends _$ProfilePage {
  late final String title;    // widget constructor param — required
  late final int?   subtitle; // widget constructor param — optional (nullable)

  String name = 'John';
  int age = 25;
  bool isLoading = false;

  final String appTitle = 'My App'; // final → not reactive, not disposed

  TextEditingController nameCtrl = TextEditingController(); // auto-disposed
  AnimationController animCtrl = AnimationController(...);  // auto-disposed
  FocusNode focusNode = FocusNode();                        // auto-disposed
  StreamController counter = StreamController();            // auto-closed

  @override
  void initState() {
    super.initState(); // title and subtitle are already set here
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const CircularProgressIndicator();
    return Column(children: [
      Text(title),
      Text(name),
      Text('$age'),
      TextField(controller: nameCtrl),
      ElevatedButton(
        onPressed: () {
          name = 'Jane'; // both fire in the same sync block
          age  = 30;     // only ONE rebuild is scheduled
        },
        child: const Text('Update'),
      ),
    ]);
  }
}
```

Usage in the widget tree:
```dart
ProfilePageWidget(title: 'My Profile')          // subtitle is optional
ProfilePageWidget(title: 'My Profile', subtitle: 42)
```

---

## What gets generated

```dart
// profile_page.g.dart — GENERATED, DO NOT MODIFY

abstract class _$ProfilePage extends StatefulWidget {
  const _$ProfilePage({super.key});

  Widget build(BuildContext context);

  @override
  State createState() => _ProfilePageState();
}

class _ProfilePageState extends State {

  // ── reactive backing fields ──────────────────────────────
  String _name      = 'John';
  int    _age       = 25;
  bool   _isLoading = false;

  // ── getters ─────────────────────────────────────────────
  String get name      => _name;
  int    get age       => _age;
  bool   get isLoading => _isLoading;

  // ── setters — trigger batched rebuild ───────────────────
  set name(String v)    { _name = v;       _scheduleRebuild(); }
  set age(int v)        { _age = v;        _scheduleRebuild(); }
  set isLoading(bool v) { _isLoading = v;  _scheduleRebuild(); }

  // ── non-reactive passthrough (final fields) ─────────────
  final String appTitle = 'My App';

  // ── disposable resources (forwarded from widget class) ──
  TextEditingController nameCtrl = TextEditingController();
  AnimationController   animCtrl = AnimationController(...);
  FocusNode             focusNode = FocusNode();
  StreamController counter   = StreamController();

  // ── microtask batching ──────────────────────────────────
  bool _dirty = false;

  void _scheduleRebuild() {
    if (_dirty) return;
    _dirty = true;
    Future.microtask(() {
      _dirty = false;
      if (mounted) setState(() {});
    });
  }

  // ── dispose ─────────────────────────────────────────────
  @override
  void dispose() {
    nameCtrl.dispose();  // TextEditingController → .dispose()
    animCtrl.dispose();  // AnimationController   → .dispose()
    focusNode.dispose(); // FocusNode             → .dispose()
    counter.close();     // StreamController      → .close()
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(context);
}
```

---

## Field classification rules

| Field type                                          | Effect |
|-----------------------------------------------------|--------|
| `late final T x` (no init, T not CN)                | Widget constructor param; set before `initState`; `didUpdateWidget` on change |
| `late final T x` (no init, T extends CN)            | Widget param **and** `addListener` in `initState`; `didUpdateWidget` re-wires listener on store swap |
| `late final T x = expr` (T extends CN)              | `addListener` in `initState` only; no param, no setter, no `didUpdateWidget` |
| `final T x = expr` (not late)                       | Non-reactive constant; no codegen |
| `TextEditingController`, `AnimationController`, etc. | Auto-disposed via `.dispose()` / `.close()` / `.cancel()` |
| `ChangeNotifier` subclass (mutable field)           | Listener wired in `initState`; setter re-wires on field replacement |
| `List<T>`                                           | Backed by `LiveList<T>`; structural ops notify; items auto-proxied if T is proxyable |
| `Set<T>`                                            | Backed by `LiveSet<T>`; same as List |
| `Map<K, V>`                                         | Backed by `LiveMap<K, V>`; K/V auto-proxied when proxyable |
| plain user-defined class (mutable field)            | `_Live<ClassName>` proxy subclass generated; deep field mutations notify |
| everything else mutable                             | Reactive scalar; setter calls `_scheduleRebuild()` |

> Classification order (first match wins):
> `late final` (no init) → `late final` (with init, CN only) → `final` → disposable → ChangeNotifier → proxyable object → `List<T>` → `Set<T>` → `Map<K,V>` → reactive scalar
>
> Known disposable types are checked **before** ChangeNotifier — they are
> handled via `.dispose()` only, even though they also extend ChangeNotifier.

---

## Widget parameters — `late final` fields

`late final` fields **without an initializer** become constructor parameters
on the generated `StatefulWidget`. They are forwarded into the State before
`initState()` runs, so the user's `initState` override can read them safely.

```dart
@Live()
class CounterPage extends _$CounterPage {
  late final int    initialValue; // required param — non-nullable
  late final String label;        // required param — non-nullable
  late final Color? tint;         // optional param — nullable, defaults to null

  int count = 0;

  @override
  void initState() {
    super.initState();   // params already set — safe to read
    count = initialValue;
  }
}

// Usage:
CounterPageWidget(initialValue: 10, label: 'Score')
CounterPageWidget(initialValue: 0,  label: 'Laps', tint: Colors.blue)
```

```dart
// What gets generated:

class CounterPageWidget extends StatefulWidget {
  const CounterPageWidget({
    required this.initialValue,
    required this.label,
    this.tint,           // nullable → not required
    super.key,
  });

  final int    initialValue;
  final String label;
  final Color? tint;

  @override
  State<CounterPageWidget> createState() => _CounterPageImpl();
}

class _CounterPageImpl extends CounterPage {
  @override
  void initState() {
    super.initialValue = widget.initialValue; // set BEFORE super.initState()
    super.label        = widget.label;
    super.tint         = widget.tint;
    super.initState();                        // user override runs here
    ...
  }
}
```

### Rules

- `late final int x` (no `= ...`) → **required** named parameter on the widget.
- `late final int? x` (nullable, no `= ...`) → **optional** named parameter (defaults to `null`).
- `late final int x = 0` (has an initializer) → **not** a widget param; treated as a non-reactive constant like `final`.
- `final int x = 0` (existing behaviour) → non-reactive constant, unchanged.

Params are set via `super.field = widget.field` before `super.initState()` is
called, so they are always readable inside any `initState` override the user
writes.

---

## All mutable fields are wired — no build() AST analysis

Every mutable reactive field gets a setter override that calls
`_scheduleRebuild()` unconditionally. There is no analysis of which fields are
read inside `build()`. This is intentional: selective wiring creates silent
non-rebuilds when a field is only read via a helper method called from `build()`.

```dart
@Live()
class MyWidget extends _$MyWidget {
  int counter = 0;   // setter wired → _scheduleRebuild()
  String log  = '';  // setter wired → _scheduleRebuild()

  @override
  Widget build(BuildContext context) => Text('$counter');
}
```

Both `counter` and `log` get setter overrides. Use `notify()` as an explicit
escape hatch when you need a rebuild that wouldn't happen automatically (e.g.
direct mutation of a private backing field, or an object that isn't tracked).

---

## Microtask batching — how it works

When multiple setters fire in the same synchronous block, only one rebuild
is scheduled. This is done via `Future.microtask()`, which runs immediately
after the current sync block finishes — no timer, no frame delay, no deps.

```dart
name = 'Jane';  // _dirty = true, microtask scheduled
age  = 30;      // _dirty already true — skipped
                // sync block ends
                // microtask fires → _dirty = false → setState()
                // result: ONE rebuild, not two
```

---

## Reactive collections — LiveList and LiveSet

`List<T>` and `Set<T>` fields are replaced at runtime by `LiveList<T>` and
`LiveSet<T>` wrappers that intercept every mutating operation and call
`_scheduleRebuild`. This applies both to fields declared directly on the widget
class and to `List`/`Set` fields on nested proxy objects.

### Structural changes (always tracked)

```dart
List<String> tags = [];
Set<String>  roles = {};

// all of these trigger a rebuild:
tags.add('flutter');
tags.remove('flutter');
tags.clear();
tags[0] = 'dart';
roles.add('admin');
roles.removeWhere((r) => r.startsWith('a'));
```

### Item-level mutation tracking (when T is proxyable)

When the element type `T` is a plain user-defined class (proxyable), items are
automatically wrapped with `_LiveT` as they enter the collection. Mutating a
field on any item then also triggers a rebuild — no manual `notify()` needed.

```dart
class Car {
  String make  = 'Toyota';
  String color = 'white';
}

List<Car> cars = [];

cars.add(Car());          // stored as _LiveCar internally
cars[0].color = 'red';   // _LiveCar.color setter → _scheduleRebuild() ✓
cars.remove(cars[0]);     // structural change → _scheduleRebuild() ✓
```

### What gets generated

```dart
// backing field uses LiveList / LiveSet
late LiveList<Car> _$cars;

// getter returns the LiveList (which implements List<Car>)
@override List<Car> get cars => _$cars;

// setter re-wraps the new value
@override set cars(List<Car> v) {
  _$cars = LiveList.of(v, _scheduleRebuild,
               wrap: (e) => _LiveCar.from(e, _scheduleRebuild));
  _scheduleRebuild();
}

// initState seeds the LiveList from the field initializer
@override void initState() {
  super.initState();
  _$cars = LiveList.of(super.cars, _scheduleRebuild,
               wrap: (e) => _LiveCar.from(e, _scheduleRebuild));
}
```

When `T` is a primitive (`String`, `int`, etc.) the `wrap` argument is omitted
and `LiveList`/`LiveSet` behave as plain reactive wrappers with no item proxying.

### Maps — LiveMap with key and value wrapping

`Map<K, V>` fields are backed by `LiveMap<K, V>`. Structural operations
(`[key] = value`, `remove`, `clear`, `addAll`, etc.) always trigger a rebuild.
When K and/or V are proxyable, they are wrapped with `_RxK`/`_RxV` as entries
enter the map.

```dart
Map<String, Car> garage = {};   // String key (primitive), Car value (proxyable)

garage['tesla'] = Car();        // value wrapped as _LiveCar → rebuild ✓
garage['tesla']!.color = 'red'; // _LiveCar.color setter → rebuild ✓
garage.remove('tesla');         // structural change → rebuild ✓
```

**Key wrapping — important constraint**

Key wrapping is safe **only** when K overrides `==` and `hashCode` with
value-based equality. Dart's default equality is identity-based: wrapping a
key creates a new object with a different identity, so `map[originalKey]`
would not find the stored entry.

```dart
// SAFE — String has value equality, lookup works after wrapping
Map<String, Car> garage = {};

// UNSAFE — Car uses identity equality (default); map[originalCar] fails
// after wrapping because _LiveCar is a different object
Map<Car, String> labels = {};   // ← avoid unless Car overrides == / hashCode
```

When K is a primitive (`String`, `int`, etc.) or a class with value-based
equality, key wrapping is transparent and correct. For identity-based keys,
use `Map<IdentityKey, ProxyableValue>` (only V gets wrapped) — the most
common real-world pattern.

### Inside proxy objects

`List<T>`, `Set<T>`, and `Map<K, V>` fields on nested proxy objects (e.g.
`User.cars`, `User.garage`) are also backed by `LiveList`/`LiveSet`/`LiveMap`, with
the same `_notify` callback propagating up to `_scheduleRebuild`. The wrap
function uses `notify` (the constructor parameter) in initializer lists and
`_notify` (the field) in setters:

```dart
// Inside _LiveUser.from(User src, VoidCallback notify):
_cars   = LiveList.of(src.cars,   notify, wrap: (e) => _LiveCar.from(e, notify));
_garage = LiveMap.of(src.garage,  notify,
            wrapValue: (v) => _LiveCar.from(v, notify));

// Inside _LiveUser.set cars / set garage:
_cars   = LiveList.of(v, _notify, wrap: (e) => _LiveCar.from(e, _notify));
_garage = LiveMap.of(v,  _notify,
            wrapValue: (v) => _LiveCar.from(v, _notify));
```

---

## Proxy objects — automatic deep reactivity

For any mutable field whose type is a plain user-defined class (not a known
disposable, not a `ChangeNotifier`, not a `List`, not a dart:core primitive),
the generator produces a `_Rx<ClassName>` proxy subclass that overrides every
mutable field setter to call `_scheduleRebuild`. The same `_notify` callback
propagates through the entire object tree, so mutations at any depth trigger
exactly one rebuild.

```dart
// What the developer writes — no annotation, no ChangeNotifier
class Address {
  String street = '123 Main St';
  String city   = 'Springfield';
}

class User {
  String  name    = 'Alice';
  int     age     = 30;
  Address address = Address();
}

@Live()
class UserModelPage extends _$UserModelPage {
  User user = User();

  @override
  Widget build(BuildContext context) {
    // All of these trigger a rebuild automatically:
    // user.name = 'Bob';
    // user.age++;
    // user.address.street = '456 Oak Ave';
    ...
  }
}
```

```dart
// What gets generated

class _LiveAddress extends Address {
  final VoidCallback _notify;
  String _street;
  String _city;

  _LiveAddress.from(Address src, VoidCallback notify)
      : _notify = notify,
        _street = src.street,
        _city   = src.city;

  @override String get street => _street;
  @override set street(String v) { _street = v; _notify(); }
  @override String get city   => _city;
  @override set city(String v)   { _city   = v; _notify(); }
}

class _LiveUser extends User {
  final VoidCallback _notify;
  String         _name;
  int            _age;
  _LiveAddress     _address;   // nested proxy — same _notify
  LiveList<Car>    _cars;      // LiveList — structural + item mutations tracked
  LiveSet<String>  _hobbies;   // LiveSet  — structural changes tracked

  _LiveUser.from(User src, VoidCallback notify)
      : _notify  = notify,
        _name    = src.name,
        _age     = src.age,
        _address = _LiveAddress.from(src.address, notify),
        _cars    = LiveList.of(src.cars, notify,
                       wrap: (e) => _LiveCar.from(e, notify)),
        _hobbies = LiveSet.of(src.hobbies, notify);

  @override String      get name    => _name;
  @override set name(String v)      { _name = v; _notify(); }
  @override int         get age     => _age;
  @override set age(int v)          { _age  = v; _notify(); }
  @override _LiveAddress  get address => _address;
  @override set address(Address v)  { _address = _LiveAddress.from(v, _notify); _notify(); }
  @override List<Car>   get cars    => _cars;
  @override set cars(List<Car> v)   { _cars = LiveList.of(v, _notify, wrap: (e) => _LiveCar.from(e, _notify)); _notify(); }
  @override Set<String> get hobbies => _hobbies;
  @override set hobbies(Set<String> v) { _hobbies = LiveSet.of(v, _notify); _notify(); }
}

// in the widget impl
@override
void initState() {
  super.initState();
  super.user = _LiveUser.from(user, _scheduleRebuild); // wrap on init
}

@override
set user(User v) {
  super.user = _LiveUser.from(v, _scheduleRebuild); // re-wrap on reassignment
  _scheduleRebuild();
}
```

### Constraints

- The nested class must have a no-arg (or all-optional) default constructor.
  If it doesn't, the generator skips proxy generation and the field falls back
  to a plain reactive setter (rebuilds only on reference replacement).
- Classes marked `final` or `sealed` cannot be subclassed — they are skipped
  and fall back the same way.
- Private fields (names starting with `_`) on the nested class are never
  proxied. Outside the defining library they can't be overridden. This applies
  equally whether the class is in the same file or a different one.
- `final` fields on nested classes are not proxied — they pass through as-is.
- Cycles (`A` → `B` → `A`) are handled via an `inProgress` set; the second
  encounter of a type in a cycle is treated as a leaf (no proxy generated at
  that depth).
- Each proxy class is emitted once per source file regardless of how many
  widget fields use the same type.

---

## ChangeNotifier integration — automatic listener wiring

Three declaration styles are supported. All wire `addListener` /
`removeListener` automatically. None call `.dispose()` on the notifier —
ownership is ambiguous; override `dispose()` yourself if the widget owns it.

### Mutable field

```dart
UserModel user = UserModel();
```

Generated: setter re-wires listener on field replacement.

```dart
@override
void initState() {
  super.initState();
  user.addListener(_scheduleRebuild);
}

@override
set user(UserModel v) {
  final _old = super.user;
  _old.removeListener(_scheduleRebuild);
  super.user = v;
  v.addListener(_scheduleRebuild);
  _scheduleRebuild();
}

@override
void dispose() {
  user.removeListener(_scheduleRebuild);
  super.dispose();
}
```

### `late final` param (no initializer)

```dart
late final UserModel store;  // becomes a required constructor param
```

Generated: constructor param + listener + `didUpdateWidget` re-wires when
the parent passes a new store instance.

```dart
@override
void initState() {
  super.store = widget.store;   // param set before super.initState()
  super.initState();
  store.addListener(_scheduleRebuild);
}

@override
void didUpdateWidget(MyWidget old) {
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
  super.dispose();
}
```

### `late final` with initializer

```dart
late final UserModel store = GetIt.instance.get<UserModel>();
```

Generated: listener only — no constructor param, no setter, no
`didUpdateWidget`. The lazy initializer fires on first access in `initState`.

```dart
@override
void initState() {
  super.initState();
  store.addListener(_scheduleRebuild); // triggers lazy init
}

@override
void dispose() {
  store.removeListener(_scheduleRebuild);
  super.dispose();
}
```

---

## Reactive wrapper — optional, for granular rebuilds

Use `Reactive` when you need only a subtree to rebuild, not the whole widget.
Reach for it only when profiling shows a real perf problem — plain setState
on small widgets is fast enough 99% of the time.

```dart
// Only rebuilds when `name` changes, not when `age` changes
Reactive(
  watch: [name],
  builder: () => Text(name),
)
```

```dart
// lib/src/reactive.dart
class Reactive extends StatefulWidget {
  final List<dynamic> watch;
  final Widget Function() builder;
  const Reactive({super.key, required this.watch, required this.builder});

  @override
  State<Reactive> createState() => _ReactiveState();
}

class _ReactiveState extends State<Reactive> {
  @override
  void didUpdateWidget(Reactive old) {
    super.didUpdateWidget(old);
    if (!listEquals(widget.watch, old.watch)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder();
}
```

---

## Package structure

```
lively/
├── lib/
│   ├── lively.dart             # exports annotation, Reactive, collections
│   └── src/
│       ├── annotations.dart       # @Live()
│       ├── reactive.dart          # Reactive wrapper widget
│       ├── live_list.dart         # LiveList<T>
│       ├── live_set.dart          # LiveSet<T>
│       └── live_map.dart          # LiveMap<K, V>
├── test/
│   └── live_collections_test.dart # LiveList / LiveSet / LiveMap unit tests
├── lively_generator/
│   ├── lib/
│   │   └── src/
│   │       ├── generator.dart     # GeneratorForAnnotation<Live>
│   │       └── builder.dart       # builder() entry point
│   └── test/
│       └── generator_test.dart    # generator output tests
└── build.yaml
```

---

## build.yaml

```yaml
targets:
  $default:
    builders:
      lively_generator:
        generate_for:
          - lib/**/*.dart
```

---

## User pubspec

```yaml
dependencies:
  lively: ^1.0.0

dev_dependencies:
  lively_generator: ^1.0.0
  build_runner: ^2.0.0
```

---

## Key decisions log

- No `Rx` wrapper — plain Dart fields with generated getters/setters are enough
- No `@noRx` — use `final` to opt a field out of reactivity
- No `@dispose` — generator detects known disposable types automatically
- No rxdart — `Future.microtask()` replaces stream-based batching
- No `StreamGroup` or `async` package — zero runtime deps
- Microtask chosen over debounce: no arbitrary delay, correct Dart event loop semantics
- Full widget rebuilds are acceptable — keep widgets small as a general practice
- `Reactive` wrapper available as a surgical opt-in for perf-sensitive subtrees
- `LiveList<T>` / `LiveSet<T>` / `LiveMap<K,V>` wrap collection fields — structural mutations always notify; when element/value/key types are proxyable, items are auto-wrapped with `_LiveT` so field-level mutations on items also notify
- Map key wrapping is safe only for value-equality key types; identity-based keys (Dart default) break `map[originalKey]` lookup after wrapping — document this clearly
- `late final` (no initializer) chosen as the widget-param signal — it is the natural Dart idiom for "set exactly once before first read", requires no extra annotation, and is visually distinct from `final x = value` (non-reactive constant) and `int x = 0` (reactive field)
- `late final T x` where T extends ChangeNotifier and has no initializer is dual-classified: it acts as both a widget constructor param and a ChangeNotifier field — `didUpdateWidget` re-wires the listener when the parent passes a new store instance
- `late final T x = expr` where T extends ChangeNotifier is listener-only: the lazy initializer fires on first access in `initState`; no param, no setter, no `didUpdateWidget` needed
- Wrap function uses the `notify` **parameter** (not `this._notify`) in constructor initializers to avoid illegal `this` access in Dart initializer lists
- All mutable fields are wired unconditionally — no build() AST analysis; selective wiring was rejected because it creates silent non-rebuilds when a field is read only via a helper method called from `build()`; `notify()` is the escape hatch
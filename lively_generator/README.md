# lively_generator

Code generator for the [lively](https://pub.dev/packages/lively) package.

This package is a `dev_dependency`. It is not imported directly — `build_runner`
discovers it automatically via `build.yaml`.

## Setup

```yaml
# pubspec.yaml
dependencies:
  lively: ^1.0.0

dev_dependencies:
  lively_generator: ^1.0.0
  build_runner: ^2.0.0
```

Add `part 'your_file.g.dart';` to every source file that uses `@Live()` or `@LiveStore()`, then run:

```sh
dart run build_runner build
# or watch mode:
dart run build_runner watch
```

---

## AI Agent Usage Guide

> This section is written for AI agents (Copilot, Claude, Cursor, etc.) generating or assisting with `lively`-based Flutter code.
> Read it fully before producing any code. The rules are strict and order-dependent.

### @Live() — Reactive Widgets

#### Minimal example

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

#### Naming rule

| User writes | Generated widget name |
|---|---|
| `class FooPage extends _$FooPage` | `FooPageWidget` |
| `class MyScreen extends _$MyScreen` | `MyScreenWidget` |

The user class always extends `_$ClassName` (leading `_$`). The generated file provides that abstract base.

---

### Field classification — @Live()

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

### Widget constructor params — `late final` fields

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

**Rules:**
- Non-nullable `late final T x` → `required` named param
- Nullable `late final T? x` → optional named param (no `required`)
- `late final T x = expr` (has initializer) → NOT a param; treated as a non-reactive constant

---

### Reactive scalars

Every mutable non-final field becomes reactive. All setters call `_scheduleRebuild()` unconditionally.

**Batching:** Multiple assignments in one sync block schedule exactly one rebuild via `Future.microtask()`.

```dart
name = 'Jane';  // schedules microtask
age  = 30;      // microtask already scheduled — skipped
// one rebuild fires after the sync block
```

---

### @LiveStore() — Reactive Stores

#### Naming convention — CRITICAL

The user writes the class with a **leading underscore**. The generator strips it to produce the public name.

| User writes | Generated public class |
|---|---|
| `class _UserStore extends _$UserStore` | `UserStore` |
| `class _AppStore extends _$AppStore` | `AppStore` |

#### Field classification — @LiveStore()

Same first-match-wins order as `@Live()`, with these differences:

| Field | @Live() | @LiveStore() |
|---|---|---|
| `late final T x` (no init, not CN) | Widget param | Constructor param |
| `late final T x` (no init, T extends CN) | Widget param + listener + `didUpdateWidget` | Constructor param + listener (no `didUpdateWidget`) |
| Everything else | Same | Same |

#### Owned vs. borrowed @LiveStore fields

| Declaration | Ownership | dispose() behavior |
|---|---|---|
| `CartStore cart = CartStore()` | Owned (has inline init) | `removeListener` + `cart.dispose()` |
| `late final SettingsStore s` (param) | Borrowed | `removeListener` only |
| `late final SettingsStore s = GetIt.instance.get()` | Borrowed | `removeListener` only |

---

### ChangeNotifier integration — three patterns

**Pattern 1 — owned mutable field:**
```dart
UserModel user = UserModel();
// addListener in initState; setter re-wires; removeListener in dispose (NOT .dispose())
```

**Pattern 2 — borrowed param (`late final`, no init):**
```dart
late final UserModel store;
// widget constructor param; addListener in initState; didUpdateWidget re-wires; removeListener in dispose
```

**Pattern 3 — service-located (`late final` with init):**
```dart
late final UserModel store = GetIt.instance.get<UserModel>();
// addListener in initState; removeListener in dispose; no param, no setter
```

---

### Proxy objects — deep reactivity

When a mutable field's type is a plain user-defined class, the generator produces a `_Live<ClassName>` subclass.

**Proxy constraints — when proxy is NOT generated:**
- Class is `final` or `sealed`
- Class has no no-arg (or all-optional) constructor
- Private fields (`_field`) on nested classes
- Cycles (`A → B → A`) — second encounter treated as a leaf

When proxy cannot be generated, the field falls back to plain reactive scalar.

---

### Common mistakes to avoid

1. **Wrong base class.** `@Live()` → `extends _$ClassName`. `@LiveStore()` → user class has a `_` prefix: `class _StoreName extends _$StoreName`.

2. **Missing `part` directive.** Every file using these annotations needs `part 'filename.g.dart';` at the top.

3. **Using `final` when you want a param.** `final String title = 'x'` is a non-reactive constant. Use `late final String title;` (no initializer) for a param.

4. **Expecting deep reactivity without proxy support.** If the nested class is `final`, `sealed`, has no accessible default constructor, or uses private fields — only reference replacement triggers rebuilds.

5. **Using identity-based objects as Map keys.** `Map<Car, String>` where `Car` doesn't override `==`/`hashCode` will break after key wrapping.

6. **Calling `.dispose()` on a borrowed ChangeNotifier.** `lively` does NOT call `.dispose()` on borrowed CNs. Only owned CNs (with inline initializer) are auto-disposed.

7. **Expecting `notify()` outside the class.** `notify()` is a protected escape hatch — call it from inside the user class only.

---

### Quick decision table for field declarations

| I want... | Write this |
|---|---|
| A required widget param | `late final String title;` |
| An optional widget param | `late final String? title;` |
| A reactive field | `String name = 'John';` |
| A non-reactive constant | `final String appTitle = 'App';` |
| An auto-disposed controller | `TextEditingController ctrl = TextEditingController();` |
| A reactive list | `List<String> items = [];` |
| A reactive map | `Map<String, User> users = {};` |
| Borrowed ChangeNotifier param | `late final MyStore store;` |
| Owned ChangeNotifier | `MyStore store = MyStore();` |
| Service-located store | `late final MyStore store = GetIt.instance.get();` |
| Force a rebuild manually | Call `notify()` inside the class |

---

For full documentation, examples, and framework comparisons see the
[lively README](https://pub.dev/packages/lively).

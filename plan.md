# RxObject proxy generation — implementation plan

## Goal

For any mutable field whose type is a plain user-defined class, generate a
`_Rx<ClassName>` proxy subclass that intercepts all field mutations and calls
`_scheduleRebuild`. Recursion is built in from day 0: nested objects get their
own proxy, sharing the same `_notify` callback so any depth of mutation
triggers exactly one rebuild.

---

## Steps

### 1 — Primitive detection helper

```dart
bool _isPrimitive(FieldElement f) {
  final lib = f.type.element?.library;
  return lib != null && lib.isDartCore;
}
```

Covers `int`, `double`, `String`, `bool`, `num`, `Object`, and everything else
from `dart:core` — all of which are treated as leaf nodes inside a proxy.

---

### 2 — Subclassability guards

In `_isProxyable`, reject classes that can't be safely subclassed:

```dart
if (element.isFinal || element.isSealed) return false;
```

`final class` prevents subclassing outside its defining library.
`sealed class` is implicitly final outside the library too.

In `_generateProxies`, skip private fields — they are library-private and
cannot be overridden from the generated `.g.dart` file:

```dart
.where((f) => ... && !f.name.startsWith('_'))
```

---

### 3 — Default-constructor guard

```dart
bool _hasDefaultConstructor(ClassElement cls) {
  final ctor = cls.unnamedConstructor;
  if (ctor == null) return false;
  if (ctor.isSynthetic) return true; // implicit default
  return ctor.parameters.every((p) => !p.isRequired);
}
```

A class without a callable no-arg constructor cannot be safely subclassed by
the proxy (we'd have to satisfy the parent constructor with unknown args).
Such fields fall back to plain reactive setters.

---

### 3 — Proxyable field detection

```dart
bool _isProxyable(FieldElement f) {
  if (_isPrimitive(f)) return false;
  if (_isDisposable(f)) return false;
  if (_isChangeNotifier(f)) return false;
  if (_isDartList(f)) return false;
  final element = f.type.element;
  if (element is! ClassElement) return false;
  return _hasDefaultConstructor(element);
}
```

---

### 4 — Classification order in `_generate()`

```
final → disposable → changeNotifier → proxyable → dartList → reactive
```

New: collect `proxyFields` list.

---

### 5 — Recursive proxy generation

New instance-level state (persists across calls within a build, scoped per
source file to avoid cross-file deduplication bugs):

```dart
String _currentFileKey = '';
final Map<String, Set<String>> _emittedByFile = {};
```

New method `_generateProxies(ClassElement cls, Set<String> inProgress)`:

1. If `cls.name` already in `_emittedByFile[fileKey]` → return `''` (already emitted)
2. If `cls.name` in `inProgress` → return `''` (cycle — stop here)
3. If `!_hasDefaultConstructor(cls)` → return `''`
4. Add `cls.name` to `inProgress` (immutable copy per branch)
5. For each mutable field on `cls`:
   - **primitive** → backing `_field` + `@override` getter + setter calling `_notify()`
   - **proxyable** → recurse into nested type; backing `_Rx<Type> _field` + getter + setter wrapping `.from()`
   - **everything else** → skip (leaf — disposable, ChangeNotifier, List)
6. Mark `cls.name` as emitted in `_emittedByFile[fileKey]`
7. Return string: nested proxy code + `_Rx<ClassName>` class definition

Constructor pattern (avoids double-wrapping, propagates same callback):
```dart
_RxUser.from(User src, VoidCallback notify)
    : _notify  = notify,
      _name    = src.name,
      _address = _RxAddress.from(src.address, notify);
```

---

### 6 — Wire proxy fields in `_buildImpl()`

Only fields whose proxy was actually emitted are wired (track via
`effectiveProxyFields`).

**Setter override** — re-wraps on reassignment:
```dart
@override
set user(User v) {
  super.user = _RxUser.from(v, _scheduleRebuild);
  _scheduleRebuild();
}
```

**`initState` extension** — wraps the initial field value created by the
user's field initializer:
```dart
super.user = _RxUser.from(user, _scheduleRebuild);
```

(`super.user = ...` bypasses our override setter and writes directly to the
parent's field. `user` (no prefix) reads the field initializer value via the
inherited getter.)

---

### 7 — `generateForAnnotatedElement` update

Set `_currentFileKey` from `buildStep.inputId.path` and init
`_emittedByFile[_currentFileKey]` before calling `_generate()`.

Prepend all proxy classes to the output for the annotated widget.

---

### 8 — Example update (`user_model_page.dart`)

Replace the ChangeNotifier demo with a plain-object demo showing two-level
nesting:

```dart
class Address { String street = '123 Main St'; String city = 'Springfield'; }
class User    { String name = 'Alice'; int age = 30; Address address = Address(); }

@RxWidget()
class UserModelPage extends _$UserModelPage {
  User user = User();
  // user.name = 'Bob'             → rebuild
  // user.age++                    → rebuild
  // user.address.street = '...'   → rebuild
}
```

---

### 9 — Tests (post-implementation)

- Proxy class generated for plain object field
- Recursive proxy for two-level nesting
- Cycle detection: no infinite recursion, second occurrence treated as leaf
- Primitive fields inside proxy → backing field + getter + setter
- Class without default constructor → skips proxy, falls back to reactive
- `initState` wraps the initial value
- Setter re-wraps on reassignment
- Same proxy class emitted only once per file (deduplication)

---

## Files changed

| File | Change |
|---|---|
| `lively_generator/lib/src/generator.dart` | Core implementation |
| `specs.md` | Documentation |
| `plan.md` | This file |
| `example/lib/user_model_page.dart` | Updated demo |
| `lively_generator/test/generator_test.dart` | New tests |

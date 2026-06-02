# lively — handover

> State of the codebase as of 2026-06-01. Read this before picking up any work.

---

## What was implemented in this session

### 1. `@computed` fields (Priority 3 — done)

**Annotation:** `@computed` (in `lively/lib/src/annotations.dart`, exported from `lively.dart`)

**What it does:** Annotate a getter to cache its result. The generator produces:
- A nullable backing field `ReturnType? _$name`
- A dirty flag `bool _$nameDirty = true` (starts true so first access computes)
- An overridden getter that recomputes via `super.name` when dirty, then caches
- Every reactive setter (scalar, collection, proxy, CN) injects `_$nameDirty = true` before scheduling a rebuild

**Strategy:** All-dirty — any setter marks ALL computed getters dirty. No static dependency analysis.

**Works in:** `@Live()` widgets and `@LiveStore` classes.

---

### 2. `Future<T>` / `Stream<T>` field support (Priority 1 — done)

**What it does:** Declare a `Future<T>` or `Stream<T>` field and the generator wires it fully.

**`AsyncValue<T>` sealed type** — new file `lively/lib/src/async_value.dart`:
```dart
sealed class AsyncValue<T> {}
final class AsyncLoading<T> extends AsyncValue<T> { const AsyncLoading(); }
final class AsyncData<T> extends AsyncValue<T> { final T value; ... }
final class AsyncError<T> extends AsyncValue<T> { final Object error; final StackTrace stackTrace; ... }
```

**For each `Future<T>` field (e.g. `Future<String> username`):**
- `AsyncValue<String> _$usernameState = const AsyncLoading()` — backing state
- `int _$usernameGen = 0` — generation counter to ignore stale completions
- `AsyncValue<String> get usernameState` — public state getter
- Setter that resets to `AsyncLoading`, increments the generation counter, and rewires the future
- `initState` wiring: `username.then(...).catchError(...)` with `mounted` check
- `buildUsername({required data, loading?, error?})` helper — `loading` defaults to `CircularProgressIndicator()`, `error` defaults to `SizedBox.shrink()`

**For each `Stream<T>` field (e.g. `Stream<double> price`):**
- Same state backing as Future
- `StreamSubscription<double>? _$priceSub` — subscription tracker
- Setter cancels old subscription before starting new one
- `initState` wiring: `_$priceSub = price.listen(...)`
- `dispose`: `_$priceSub?.cancel()`
- `buildPrice({required data, loading?, error?})` helper

**In `@LiveStore`:**
- Same state/subscription generation, no `build<Name>` helper
- Uses `_$asyncDisposed` flag (generated only when async fields exist) instead of `mounted`
- Constructor wiring instead of `initState`

**User-facing example:**
```dart
@Live()
class ProfilePage extends _$ProfilePage {
  Future<String> username = Api.fetchUsername();
  Stream<double> price = PriceApi.watch('BTC');

  @override
  Widget build(BuildContext context) => Column(children: [
    buildUsername(data: (v) => Text(v)),
    buildPrice(
      data: (v) => Text('\$$v'),
      loading: () => const Text('Loading price...'),
    ),
  ]);
}
```

---

### 3. Build-time validation (done)

**What it does:** Throws a clear `InvalidGenerationSourceError` when:
- A `@Live()` class does not extend `_$ClassName`
- A `@LiveStore()` class does not extend `_$PublicName`

**Implementation detail:** Uses AST-based check (`ClassDeclaration.extendsClause.superclass.name2.lexeme`) because the generated base class doesn't exist at analysis time, so element-based supertype resolution returns null.

---

## Roadmap status

| Priority | Feature | Status |
|---|---|---|
| 1 | `Future<T>` / `Stream<T>` field support | ✅ Done |
| 2 | `@LiveStore` → `InheritedWidget` bridge | ✅ Done (was already done before this session) |
| 3 | `@computed` fields | ✅ Done |

**The roadmap is fully implemented.** All three priorities are done.

---

## Key files

| File | Role |
|---|---|
| `lively/lib/src/annotations.dart` | `Live`, `LiveStore`, `Computed` annotations |
| `lively/lib/src/async_value.dart` | `AsyncValue<T>` sealed type |
| `lively/lib/lively.dart` | Public exports |
| `lively_generator/lib/src/generator.dart` | Main generator — all code generation logic |
| `lively_generator/lib/src/dart_code_gen_utils.dart` | Code generation utilities |
| `lively_generator/test/generator_test.dart` | All generator tests |
| `lively_generator/CHANGELOG.md` | Version 1.1.0 changelog |

---

## Architecture notes

- `LivelyGenerator extends Generator` — processes both `@Live()` and `@LiveStore()` in a single `generate()` call per file so proxy classes are deduplicated across both annotation types
- Field classification is **first-match-wins** — the order in the `for (final f in fields)` loop determines priority. The current order is: `late final` no-init → `final`/`late final` with init → `Future<T>` → `Stream<T>` → disposable → ChangeNotifier → proxyable → List → Set → Map → reactive scalar
- `@computed` dirty marks are injected into **every** reactive setter as a `List<String>` spread (`...dirtyMarks`)
- `dirtyStr` is the same marks as a pre-joined string for inline injection into multi-line statement strings (async callbacks)
- AST check in `_checkPartDirective` runs before `_generate`/`_generateStore` — it validates both the `part` directive and the `extends` clause in one async pass
- Tests use `testBuilder` from `package:build_test` — they check the **text** of the generated output, not compilation

---

## Next steps (if any)

The roadmap is complete. Possible follow-up work:
- Publish version 1.1.0 to pub.dev
- Add `@Live()` / `@LiveStore()` entries to the README field classification tables for `Future<T>`, `Stream<T>`, and `@computed`
- Consider adding `@LiveStore` async field support to the README docs
- Consider a `maybeOf` companion for `InheritedNotifier` provider (already generated)

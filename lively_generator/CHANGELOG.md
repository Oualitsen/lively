## 1.1.1

- Fix: `build<FieldName>()` helpers are now declared as concrete stubs on the abstract `_$ClassName` base, so calling them inside the user's `build()` method passes static analysis without errors.
- Fix: `@LiveStore()` fields are now recognised as `ChangeNotifier` subtypes even when their generated base class (`_$StoreName`) is not yet resolved during the current build step.
- Generator now emits `$gen` and `$changed` (no leading underscore) for internal local variables to satisfy the `no_leading_underscores_for_local_identifiers` lint rule in the generated output.

## 1.1.0

- **`Future<T>` / `Stream<T>` field support** — declare a `Future<T>` or `Stream<T>` field and the generator produces an `<fieldName>State` of type `AsyncValue<T>` (starts as `AsyncLoading`), full lifecycle wiring in `initState`/`dispose`, and a `build<FieldName>({required data, loading, error})` helper method. The `loading` and `error` params default to `CircularProgressIndicator` and `SizedBox.shrink()`. Reassigning the field resets to `AsyncLoading` and re-subscribes (old stream subscription is cancelled). Works in both `@Live()` widgets and `@LiveStore` classes. The `AsyncValue<T>` sealed type (`AsyncLoading`, `AsyncData`, `AsyncError`) is shipped in the `lively` runtime.
- **`@computed` fields** — annotate a getter with `@computed` to cache its result and only recompute when any reactive field changes. The generator emits a nullable backing field, a dirty flag (starts `true`), and an overridden getter that recomputes lazily. Every reactive setter (scalar, collection, proxy, ChangeNotifier) marks all `@computed` getters dirty before scheduling a rebuild. Works in both `@Live()` widgets and `@LiveStore` classes.
- Generator now throws a clear `InvalidGenerationSourceError` when a `@Live()` class does not extend `_$ClassName`, or a `@LiveStore()` class does not extend `_$StoreName`. The error message includes the exact fix required, so you get an actionable build-time message instead of non-compilable generated code.

## 1.0.1

- Added example demonstrating `@Live()` and `@LiveStore()` annotated classes.
- Updated README with full AI agent usage guide and field classification reference.
- Fixed `homepage`, added `repository` and `issue_tracker` to pubspec.

## 1.0.0

- Initial release.
- `LivelyGenerator` processes both `@Live()` and `@LiveStore()` annotations in a single `generate()` call per file, ensuring proxy classes are deduplicated across both annotation types.
- `@Live()`: emits a `StatefulWidget` wrapper, an abstract `State` base, and a concrete impl. Classifies fields into widget params (`late final`), disposables, `ChangeNotifier`, owned `@LiveStore`, proxy objects, `LiveList`, `LiveSet`, `LiveMap`, and reactive scalars.
- `@LiveStore()`: emits an abstract `ChangeNotifier` base (`_$StoreName`) and a public concrete class (`StoreName`). Classifies fields identically to `@Live()` with the addition of DI constructor params from `late final` fields without initializers.
- Generates `_Live<ClassName>` proxy subclasses for plain mutable objects, with recursive nesting and cycle detection.
- All generated dispose / addListener / removeListener calls use `?.` for nullable field types.
- Emits `@mustCallSuper` on base `initState` and `dispose` stubs.
- Logs build-time warnings for proxy fallbacks (final/sealed classes, missing default constructor) and map key identity issues.

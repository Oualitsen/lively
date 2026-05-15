## 1.0.0

- Initial release.
- `LivelyGenerator` processes both `@Live()` and `@LiveStore()` annotations in a single `generate()` call per file, ensuring proxy classes are deduplicated across both annotation types.
- `@Live()`: emits a `StatefulWidget` wrapper, an abstract `State` base, and a concrete impl. Classifies fields into widget params (`late final`), disposables, `ChangeNotifier`, owned `@LiveStore`, proxy objects, `LiveList`, `LiveSet`, `LiveMap`, and reactive scalars.
- `@LiveStore()`: emits an abstract `ChangeNotifier` base (`_$StoreName`) and a public concrete class (`StoreName`). Classifies fields identically to `@Live()` with the addition of DI constructor params from `late final` fields without initializers.
- Generates `_Live<ClassName>` proxy subclasses for plain mutable objects, with recursive nesting and cycle detection.
- All generated dispose / addListener / removeListener calls use `?.` for nullable field types.
- Emits `@mustCallSuper` on base `initState` and `dispose` stubs.
- Logs build-time warnings for proxy fallbacks (final/sealed classes, missing default constructor) and map key identity issues.

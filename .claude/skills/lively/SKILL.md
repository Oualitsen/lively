---
name: lively
description: Use when writing, reviewing, or generating Flutter code for the lively package — creating @Live() reactive widgets, @LiveStore() ChangeNotifier stores, reactive fields/collections (LiveList/LiveSet/LiveMap), proxy objects, or predicting/reviewing generated *.g.dart output. Triggers on tasks involving lively's annotations, field-classification rules, batched setState/notifyListeners, auto-dispose, or ChangeNotifier listener wiring.
---

# lively

Code-gen package that turns plain Dart classes into reactive Flutter
`StatefulWidget`s (`@Live()`) or `ChangeNotifier` stores (`@LiveStore()`) with
zero runtime deps and zero extra annotations.

**Before writing or reviewing any lively code, read `AGENT_GUIDE.md`** at the
repo root — it is the authoritative, agent-oriented reference with the full
field-classification table, generated-output examples, and a "common mistakes"
checklist. `specs.md` (widgets) and `specs_store.md` (stores) are the
underlying design specs if you need rationale beyond the guide ("Key decisions
log" sections).

## The one rule that matters most

**Field declaration syntax IS the API.** There are no extra annotations —
the generator classifies every field by its *declaration shape* alone
(`late final` vs `final` vs plain mutable, presence/absence of an initializer,
the field's type). Get the shape right and the generator does the rest; get it
wrong and you silently get a constant, a param, or a non-reactive field instead
of what you wanted. Always classify a field by walking the first-match-wins
order in `AGENT_GUIDE.md` before writing it.

Quick cheat-sheet (full table + generated code in `AGENT_GUIDE.md`):

| Want | Write |
|---|---|
| Required widget/store param | `late final String title;` |
| Optional (nullable) param | `late final String? title;` |
| Reactive field (rebuilds on assign) | `String name = 'John';` |
| Non-reactive constant | `final String appTitle = 'App';` |
| Auto-disposed controller | `TextEditingController c = TextEditingController();` |
| Reactive list/set/map | `List<String> items = [];` |
| Borrowed ChangeNotifier/store | `late final MyStore store;` (param, not disposed) |
| Owned ChangeNotifier/store | `MyStore store = MyStore();` (listener + disposed) |
| Service-located store | `late final MyStore store = GetIt.instance.get();` |
| Manual rebuild escape hatch | call `notify()` from inside the class |

## Naming conventions (don't mix these up)

- `@Live()`: user writes `class FooPage extends _$FooPage` → generator emits
  `FooPageWidget`.
- `@LiveStore()`: user writes `class _UserStore extends _$UserStore`
  (**leading underscore on both**) → generator emits public `UserStore`.
- Every file needs `part 'filename.g.dart';` at the top.

## When generating or predicting `.g.dart` output

Walk each field through the classification order in `AGENT_GUIDE.md` /
`specs.md` §"Field classification rules" (late final no-init → late final
with-init+CN → final → disposable → ChangeNotifier → proxyable object →
List → Set → Map → reactive scalar), then mirror the corresponding generated
snippet from the spec (setter shape, `_scheduleRebuild`/`_scheduleNotify`
calls, `initState`/`dispose`/`didUpdateWidget` wiring, proxy class shape).
Don't invent new generated shapes — match what the specs show exactly,
including ordering (params set before `super.initState()`/before other ctor
work, listeners wired after).

## Common pitfalls (see "Common mistakes to avoid" in AGENT_GUIDE.md for full list)

1. `final String x = 'a'` is a constant, not a param — use `late final String x;` for a param.
2. `@LiveStore()` user class needs the `_` prefix; `@Live()` does not.
3. Don't expect deep-mutation reactivity through `final`/`sealed`/no-default-ctor/private-field nested classes — only reference replacement rebuilds those.
4. Never call `.dispose()` on a *borrowed* ChangeNotifier/store (param or service-located) — only *owned* (inline-initialized) ones get disposed.
5. `Map<K, V>` with identity-equality keys breaks after key-wrapping — keys must have value-based `==`/`hashCode` (or keep K a primitive).
6. All mutable fields get setters wired unconditionally (no `build()` AST analysis) — this is intentional, not a bug to "optimize away".

## Local commands

This project uses `fvm` — prefix all `dart`/`flutter` invocations with `fvm`
(e.g. `fvm dart run build_runner build`).

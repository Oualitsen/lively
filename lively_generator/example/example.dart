// This file shows the source code that lively_generator processes.
// Run `dart run build_runner build` to generate the `.g.dart` output.

import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

part 'example.g.dart';

// ── @Live() ───────────────────────────────────────────────────────────────────

/// A counter widget with a required title param and a reactive [count] field.
///
/// lively_generator produces:
///   - [CounterPageWidget]  — the StatefulWidget you place in the tree
///   - [_$CounterPage]      — abstract State base with microtask batching
///   - [_CounterPageImpl]   — concrete State that wires reactive setters
@Live()
class CounterPage extends _$CounterPage {
  late final String title; // required constructor param on CounterPageWidget

  int count = 0; // reactive scalar — setter schedules a rebuild

  TextEditingController noteCtrl = TextEditingController(); // auto-disposed

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$count', style: Theme.of(context).textTheme.displayLarge),
            ElevatedButton(
              onPressed: () => count++, // plain assignment → one rebuild
              child: const Text('+'),
            ),
          ]),
        ),
      );
}

// ── @LiveStore() ──────────────────────────────────────────────────────────────

/// A shareable reactive store.
///
/// lively_generator produces:
///   - [_$CartStore]  — abstract ChangeNotifier base with microtask batching
///   - [CartStore]    — concrete class with reactive setters; instantiate this
@LiveStore()
class _CartStore extends _$CartStore {
  List<String> items = []; // backed by LiveList — add/remove trigger notify

  double get total => items.length * 9.99; // plain getter, no codegen needed

  void add(String item) => items.add(item);
  void clear() => items.clear();
}

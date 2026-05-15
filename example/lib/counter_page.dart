import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

part 'counter_page.g.dart';

@Live()
class CounterPage extends _$CounterPage {
  // ── in build() → setter gets _scheduleRebuild() wired ──────────────────
  int count = 0;

  // ── NOT in build() → no setter override; mutations are silent ──────────
  // Changing lastAction never schedules a rebuild on its own.
  // When count and lastAction change together, only ONE rebuild fires —
  // the one scheduled by count's setter.
  String lastAction = '';

  void _tap(int delta) {
    count += delta;           // schedules a rebuild
    lastAction = delta > 0    // silent — piggybacks on count's rebuild
        ? 'incremented'
        : 'decremented';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text('taps', style: theme.textTheme.titleMedium),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: count > 0 ? () => _tap(-1) : null,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(width: 24),
                FilledButton(
                  onPressed: () => _tap(1),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
               // lastAction = 'reset';
               count = 0;
              },
              child:  Text('Reset'),
            ),
          ],
        ),
      ),
      // lastAction is absent from build() entirely.
      // Check counter_page.g.dart: set count → _scheduleRebuild()
      //                             set lastAction → no _scheduleRebuild()
    );
  }
}

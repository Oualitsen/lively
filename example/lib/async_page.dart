import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

part 'async_page.g.dart';

// Simulates a slow network call.
Future<String> _fetchUser() async {
  await Future.delayed(const Duration(seconds: 2));
  return 'Alice';
}

// Simulates a live price stream.
Stream<double> _priceStream() async* {
  var price = 100.0;
  while (true) {
    await Future.delayed(const Duration(seconds: 1));
    price += (price * 0.01 * (DateTime.now().millisecond % 3 - 1));
    yield double.parse(price.toStringAsFixed(2));
  }
}

@Live()
class AsyncPage extends _$AsyncPage {
  Future<String> user = _fetchUser();
  Stream<double> price = _priceStream();

  String filter = '';

  @computed
  String get upperFilter => filter.toUpperCase();

  void reload() => user = _fetchUser();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Async + Computed')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Future<String> user:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            buildUser(
              data: (name) => Text(
                'Hello, $name!',
                style: theme.textTheme.headlineSmall,
              ),
              loading: () => const Row(children: [
                CircularProgressIndicator(),
                SizedBox(width: 12),
                Text('Loading user…'),
              ]),
              error: (e) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: reload,
              child: const Text('Reload user'),
            ),
            const Divider(height: 32),
            Text('Stream<double> price:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            buildPrice(
              data: (p) => Text(
                '\$$p',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              loading: () => const Text('Waiting for first tick…'),
            ),
            const Divider(height: 32),
            Text('@computed upperFilter:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Type something',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => filter = v,
            ),
            const SizedBox(height: 8),
            Text(
              upperFilter.isEmpty ? '(empty)' : upperFilter,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

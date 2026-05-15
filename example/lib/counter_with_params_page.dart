import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

part 'counter_with_params_page.g.dart';

@Live()
class CounterWithParamsPage extends _$CounterWithParamsPage {
  late final int initialValue;
  late final String label;

  int count = 0;

  @override
  void initState() {
    super.initState();
    count = initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$count', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(onPressed: () => count--, child: const Icon(Icons.remove)),
                const SizedBox(width: 24),
                FilledButton(onPressed: () => count++, child: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => count = initialValue,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}

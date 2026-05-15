import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

import 'model/address.dart';
import 'model/car.dart';
import 'model/user.dart';

part 'user_model_page.g.dart';

@Live()
class UserModelPage extends _$UserModelPage {
  User user = User();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RxObject demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── scalar fields ──────────────────────────────────────
          Text('Name: ${user.name}'),
          Text('Age:  ${user.age}'),
          Row(children: [
            ElevatedButton(onPressed: () => user.name = 'Bob',   child: const Text('name → Bob')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => user.name = 'Alice', child: const Text('name → Alice')),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => user.age++,          child: const Text('age++')),
          ]),

          const Divider(height: 32),

          // ── nested object ──────────────────────────────────────
          Text('Street: ${user.address.street}'),
          Text('City:   ${user.address.city}'),
          Row(children: [
            ElevatedButton(
              onPressed: () => user.address.street = '456 Oak Ave',
              child: const Text('street → 456 Oak Ave'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => user.address.city = 'Shelbyville',
              child: const Text('city → Shelbyville'),
            ),
          ]),

          const Divider(height: 32),

          // ── List<Car> ──────────────────────────────────────────
          Text('Cars (${user.cars.length}):'),
          for (final car in user.cars)
            Row(children: [
              Text('  ${car.make} — ${car.color}'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => car.color = car.color == 'white' ? 'red' : 'white',
                child: const Text('toggle color'),
              ),
              TextButton(
                onPressed: () => user.cars.remove(car),
                child: const Text('remove'),
              ),
            ]),
          Row(children: [
            ElevatedButton(
              onPressed: () => user.cars.add(Car()..make = 'Toyota'),
              child: const Text('+ Toyota'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => user.cars.add(Car()..make = 'BMW'),
              child: const Text('+ BMW'),
            ),
          ]),

          const Divider(height: 32),

          // ── Set<String> ────────────────────────────────────────
          Text('Hobbies: ${user.hobbies.join(', ')}'),
          Row(children: [
            ElevatedButton(
              onPressed: () => user.hobbies.add('cycling'),
              child: const Text('+ cycling'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => user.hobbies.add('reading'),
              child: const Text('+ reading'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => user.hobbies.clear(),
              child: const Text('clear'),
            ),
          ]),

          const Divider(height: 32),

          // ── Map<String, Car> ───────────────────────────────────
          Text('Garage (${user.garage.length}):'),
          for (final entry in user.garage.entries)
            Row(children: [
              Text('  [${entry.key}] ${entry.value.make} — ${entry.value.color}'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => entry.value.color =
                    entry.value.color == 'white' ? 'red' : 'white',
                child: const Text('toggle color'),
              ),
              TextButton(
                onPressed: () => user.garage.remove(entry.key),
                child: const Text('remove'),
              ),
            ]),
          Row(children: [
            ElevatedButton(
              onPressed: () => user.garage['A${user.garage.length + 1}'] = Car()..make = 'Tesla',
              child: const Text('+ Tesla'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => user.garage['B${user.garage.length + 1}'] = Car()..make = 'BMW',
              child: const Text('+ BMW'),
            ),
          ]),
        ],
      ),
    );
  }
}

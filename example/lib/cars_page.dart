import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

import 'model/car.dart';

part 'cars_page.g.dart';

// cars is a List<Car> referenced in build() →
//   • generator wraps it with LiveList<Car>
//   • Car is proxyable → each item stored as _RxCar
//   • car.color = '...' triggers a rebuild automatically — no notify() needed
//   • cars.add / remove triggers a rebuild automatically
@Live()
class CarsPage extends _$CarsPage {
  List<Car> cars = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cars (${cars.length})'),
      ),
      body: Column(
        children: [
          Expanded(
            child: cars.isEmpty
                ? const Center(child: Text('No cars yet. Add one below.'))
                : ListView.builder(
                    itemCount: cars.length,
                    itemBuilder: (context, i) {
                      final car = cars[i];
                      final isRed = car.color == 'red';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRed ? Colors.red : Colors.white,
                          child: Icon(
                            Icons.directions_car,
                            color: isRed ? Colors.white : Colors.grey,
                          ),
                        ),
                        title: Text(car.make),
                        subtitle: Text(car.color),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              // Deep mutation on _RxCar — triggers rebuild
                              // with no notify() call.
                              onPressed: () =>
                                  car.color = isRed ? 'white' : 'red',
                              child: Text(isRed ? '→ white' : '→ red'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => cars.remove(car),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () => cars.add(Car()),
                  child: const Text('+ Toyota'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => cars.add(Car()..make = 'BMW'),
                  child: const Text('+ BMW'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => cars.add(Car()..make = 'Tesla'),
                  child: const Text('+ Tesla'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

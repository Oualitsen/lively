import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

import 'cart_page.dart';
import 'cars_page.dart';
import 'counter_page.dart';
import 'counter_with_params_page.dart';
import 'todo_page.dart';
import 'user_model_page.dart';

part 'main.g.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lively demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const _ShellWidget(), // generated thin widget
    );
  }
}

// The user's class is the State. The widget used in the tree is _ShellWidget.
@Live()
class _Shell extends _$_Shell {
  int selectedIndex = 0;

  static const _pages = [
    CounterPageWidget(),
    TodoPageWidget(),
    CarsPageWidget(),
    UserModelPageWidget(),
    CounterWithParamsPageWidget(initialValue: 10, label: 'Params Demo'),
    CartPageWidget(),
  ];
  static const _labels = ['Counter', 'Todos', 'Cars', 'RxObject', 'Params', 'Store'];
  static const _icons = [
    Icons.add_circle_outline,
    Icons.list_alt_outlined,
    Icons.directions_car_outlined,
    Icons.person_outline,
    Icons.tune,
    Icons.shopping_cart_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => selectedIndex = i,
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}

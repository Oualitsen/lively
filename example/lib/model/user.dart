import 'package:example/model/address.dart';
import 'package:example/model/car.dart';

class User {
  String name = 'Alice';
  int age = 30;
  Address address = Address();
  List<Car> cars = [];
  Set<String> hobbies = {};
  Map<String, Car> garage = {};
}

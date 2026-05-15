import 'package:flutter/foundation.dart';
import 'package:lively/lively.dart';

part 'cart_store.g.dart';

final class CartItem {
  const CartItem({required this.name, required this.price});
  final String name;
  final double price;
}

@LiveStore()
class _CartStore extends _$CartStore {
  List<CartItem> items = [];

  double get total => items.fold(0.0, (sum, item) => sum + item.price);

  void add(CartItem item) => items.add(item);
  void remove(CartItem item) => items.remove(item);
  void clear() => items.clear();
}

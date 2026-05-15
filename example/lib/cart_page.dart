import 'package:flutter/material.dart';
import 'package:lively/lively.dart';

import 'cart_store.dart';

part 'cart_page.g.dart';

// CartPage is a @Live() widget. The cart store is held as a ChangeNotifier
// and wired via ListenableBuilder so mutations to cart.items trigger only the
// parts of the tree that need updating.

@Live()
class CartPage extends _$CartPage {
  // Store is final — lively ignores it (no reactive setter needed).
  // ListenableBuilder below handles rebuilding from cart notifications.
  final CartStore cart = CartStore();

  static const _catalog = [
    CartItem(name: 'Flutter T-Shirt', price: 29.99),
    CartItem(name: 'Dart Mug', price: 14.99),
    CartItem(name: 'Dev Sticker Pack', price: 9.99),
    CartItem(name: 'Mechanical Keyboard', price: 149.99),
    CartItem(name: 'USB-C Hub', price: 49.99),
  ];

  @override
  void initState() {
    super.initState();
    cart.addListener(notify); // wire store → widget rebuild
  }

  @override
  void dispose() {
    cart.removeListener(notify);
    cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cartItems = cart.items;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cart (${cartItems.length})'),
        actions: [
          if (cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear',
              onPressed: cart.clear,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Catalog', style: theme.textTheme.titleMedium),
          ),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _catalog.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final item = _catalog[i];
                final inCart = cartItems.contains(item);
                return _CatalogCard(
                  item: item,
                  inCart: inCart,
                  onTap: () =>
                      inCart ? cart.remove(item) : cart.add(item),
                );
              },
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Your cart', style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: cartItems.isEmpty
                ? Center(
                    child: Text(
                      'Tap an item above to add it.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: cartItems.length,
                    itemBuilder: (context, i) {
                      final item = cartItems[i];
                      return ListTile(
                        title: Text(item.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('\$${item.price.toStringAsFixed(2)}',
                                style: theme.textTheme.bodyMedium),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => cart.remove(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleMedium),
                  Text(
                    '\$${cart.total.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.inCart,
    required this.onTap,
  });

  final CartItem item;
  final bool inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: inCart ? theme.colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 104,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  inCart
                      ? Icons.check_circle_outline
                      : Icons.add_shopping_cart,
                  color: inCart ? theme.colorScheme.primary : null,
                  size: 22,
                ),
                const SizedBox(height: 6),
                Text(item.name,
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  '\$${item.price.toStringAsFixed(2)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

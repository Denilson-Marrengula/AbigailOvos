import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';
import 'stock_movement_page.dart';

/// Stock central partilhado, com preços e movimentos do vendedor.
class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.controller});
  final SellerController controller;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String query = '';

  Future<void> _newMovement() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StockMovementPage(controller: widget.controller),
      ),
    );
    if (!mounted) return;
    await widget.controller.refreshStock();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Stock atualizado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final products = controller.products;
        if (products == null) {
          final error = controller.productsError ?? controller.stockError;
          if (error == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: StateMessage(
              icon: Icons.cloud_off_outlined,
              message: error,
              actionLabel: 'Tentar novamente',
              onAction: controller.refreshStock,
            ),
          );
        }
        final filtered = products
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
        return RefreshIndicator(
          onRefresh: controller.refreshStock,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.medium),
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Pesquisar no stock',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.medium),
              if (products.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _newMovement,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Atualizar stock'),
                ),
                const SizedBox(height: AppSpacing.small),
              ],
              if (controller.stockError != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    title: Text(
                      controller.stockError!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: controller.loadStock,
                      child: const Text('Repetir'),
                    ),
                  ),
                ),
              if (filtered.isEmpty)
                StateMessage(
                  icon: Icons.inventory_2_outlined,
                  message: products.isEmpty
                      ? 'Ainda não existem itens de stock.'
                      : 'Nenhum item encontrado.',
                ),
              for (final product in filtered)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.warehouse_outlined),
                    ),
                    title: Text(product.name),
                    subtitle: Text(
                      '${formatMoney(product.price)} / ${product.unit}\n${controller.balances[product.id] == null ? 'Stock indisponível' : 'Físico: ${formatQuantity(controller.balances[product.id]!.physical)} · Reservado: ${formatQuantity(controller.balances[product.id]!.reserved)}'}${product.active ? '' : ' · Inativo'}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Disponível'),
                        _Balance(
                          quantity: controller.balances[product.id]?.available,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.small),
              Text(
                'O stock disponível desconta as quantidades reservadas em pedidos.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.quantity});
  final num? quantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = quantity;
    if (value == null) return const Text('—');
    if (value <= 0) {
      return Chip(
        label: const Text('Sem stock'),
        backgroundColor: theme.colorScheme.errorContainer,
        labelStyle: TextStyle(color: theme.colorScheme.onErrorContainer),
      );
    }
    return Text(
      formatQuantity(value),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

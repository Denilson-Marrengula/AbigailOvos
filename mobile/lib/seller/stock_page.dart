import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../auth/auth_service.dart';
import 'product_form_page.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';
import 'stock_movement_page.dart';
import 'stock_alert.dart';

/// Stock central partilhado, com preços e movimentos do vendedor.
class StockPage extends StatefulWidget {
  const StockPage({
    super.key,
    required this.controller,
    required this.onExpired,
    this.isAdmin = false,
  });
  final SellerController controller;
  final VoidCallback onExpired;
  final bool isAdmin;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String query = '';
  bool changingProduct = false;

  Future<void> _productForm([Product? product]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormPage(
          auth: widget.controller.auth,
          onExpired: widget.onExpired,
          product: product,
        ),
      ),
    );
    if (!mounted) return;
    await widget.controller.refreshStock();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Produto guardado.')));
    }
  }

  Future<void> _toggleProduct(Product product) async {
    if (changingProduct) return;
    final action = product.active ? 'Desativar' : 'Reativar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action produto?'),
        content: Text(
          product.active
              ? 'O produto deixará de aparecer para os vendedores. O stock e o histórico serão preservados.'
              : 'O produto voltará a aparecer para os vendedores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || changingProduct) return;
    setState(() => changingProduct = true);
    try {
      await widget.controller.auth.setProductActive(
        product.id,
        !product.active,
      );
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.message} Verifique o estado na lista.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resultado desconhecido. Verifique o estado na lista.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        await widget.controller.refreshStock();
        if (mounted) setState(() => changingProduct = false);
      }
    }
  }

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

  Future<void> _minimumStock(Product product) async {
    final result = await showDialog<({String? value})>(
      context: context,
      builder: (context) => _MinimumStockDialog(product: product),
    );
    if (!mounted || result == null || changingProduct) return;
    setState(() => changingProduct = true);
    try {
      await widget.controller.auth.setMinimumStock(product.id, result.value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock mínimo atualizado.')),
        );
      }
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${e.message} Verifique o mínimo na lista antes de repetir.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resultado desconhecido. Verifique o mínimo na lista antes de repetir.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        await widget.controller.refreshStock();
        if (mounted) setState(() => changingProduct = false);
      }
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
              FilledButton.icon(
                onPressed: changingProduct ? null : _productForm,
                icon: const Icon(Icons.add),
                label: const Text('Novo produto'),
              ),
              const SizedBox(height: AppSpacing.small),
              if (widget.isAdmin)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.small),
                  child: Text(
                    'Para dar entrada de stock, utilize a área Stock de uma conta de vendedor.',
                  ),
                ),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Pesquisar no stock',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.medium),
              if (!widget.isAdmin && products.isNotEmpty) ...[
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
              if (products.any((p) => !p.minimumStockSupported))
                const Text(
                  'Stock mínimo indisponível neste servidor. Atualize o servidor para configurar alertas.',
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatMoney(product.price)} / ${product.unit}\n${controller.balances[product.id] == null ? 'Stock indisponível' : 'Físico: ${formatQuantity(controller.balances[product.id]!.physical)} · Reservado: ${formatQuantity(controller.balances[product.id]!.reserved)}'}${product.active ? '' : ' · Inativo'}',
                        ),
                        if (product.minimumStock != null)
                          Text(
                            'Mínimo: ${product.minimumStock} ${product.unit}',
                          ),
                        if (stockAlert(
                              product,
                              controller.balances[product.id],
                            ) ==
                            StockAlert.low)
                          Text(
                            'Stock baixo',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        if (controller.balances[product.id] != null &&
                            stockAlert(
                                  product,
                                  controller.balances[product.id],
                                ) ==
                                StockAlert.unavailable)
                          const Text('Alerta de mínimo indisponível'),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Disponível'),
                            _Balance(
                              quantity:
                                  controller.balances[product.id]?.available,
                            ),
                          ],
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Opções do produto ${product.name}',
                          enabled: !changingProduct,
                          onSelected: (value) {
                            if (value == 'edit') {
                              _productForm(product);
                            } else if (value == 'minimum') {
                              _minimumStock(product);
                            } else if (value == 'status') {
                              _toggleProduct(product);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar produto'),
                            ),
                            if (product.minimumStockSupported &&
                                (widget.isAdmin || product.active))
                              const PopupMenuItem(
                                value: 'minimum',
                                child: Text('Stock mínimo'),
                              ),
                            if (widget.isAdmin)
                              PopupMenuItem(
                                value: 'status',
                                child: Text(
                                  product.active
                                      ? 'Desativar produto'
                                      : 'Reativar produto',
                                ),
                              ),
                          ],
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

class _MinimumStockDialog extends StatefulWidget {
  const _MinimumStockDialog({required this.product});
  final Product product;

  @override
  State<_MinimumStockDialog> createState() => _MinimumStockDialogState();
}

class _MinimumStockDialogState extends State<_MinimumStockDialog> {
  late final TextEditingController field = TextEditingController(
    text: widget.product.minimumStock ?? '',
  );

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = field.text.trim();
    final valid = RegExp(r'^\d{1,17}([.,]\d{1,2})?$').hasMatch(text);
    return AlertDialog(
      title: Text('Stock mínimo: ${widget.product.name}'),
      content: TextField(
        controller: field,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Mínimo em ${widget.product.unit}',
          helperText: 'Alerta quando o disponível for igual ou inferior.',
          errorText: text.isNotEmpty && !valid
              ? 'Indique uma quantidade válida.'
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        if (widget.product.minimumStock != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (value: null)),
            child: const Text('Remover mínimo'),
          ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, (value: text.replaceAll(',', '.')))
              : null,
          child: const Text('Guardar'),
        ),
      ],
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
    if (value == null) return const Text('Indisponível');
    if (value <= 0) {
      return Text(
        'Sem stock',
        style: TextStyle(color: theme.colorScheme.error),
      );
    }
    return Text(
      formatQuantity(value),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

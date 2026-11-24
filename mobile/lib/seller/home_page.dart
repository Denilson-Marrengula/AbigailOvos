import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../design/overview_widgets.dart';
import 'seller_controller.dart';
import 'stock_alert.dart';

class SellerHomePage extends StatelessWidget {
  const SellerHomePage({
    super.key,
    required this.controller,
    required this.session,
    required this.onOpenTab,
    required this.onNewSale,
  });

  final SellerController controller;
  final AuthSession session;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onNewSale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final noStock =
            controller.loadingProducts ||
                controller.loadingStock ||
                controller.stockError != null ||
                controller.products == null ||
                controller.balances.length != controller.products!.length
            ? 'Indisponível'
            : controller.balances.values
                  .where((balance) => balance.available <= 0)
                  .length
                  .toString();
        final hasError =
            controller.productsError != null ||
            controller.customersError != null ||
            controller.stockError != null;
        final alerts = controller.products
            ?.where((p) => p.active)
            .map((p) => stockAlert(p, controller.balances[p.id]))
            .toList();
        final lowStock =
            alerts == null ||
                controller.loadingProducts ||
                controller.loadingStock ||
                controller.stockError != null ||
                (controller.products?.any(
                      (p) => p.active && !p.minimumStockSupported,
                    ) ??
                    false) ||
                alerts.any((a) => a == StockAlert.unavailable)
            ? 'Indisponível'
            : alerts.where((a) => a == StockAlert.low).length.toString();

        return RefreshIndicator(
          onRefresh: controller.refreshAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OverviewHeader(
                        username: session.username,
                        role: 'Vendedor',
                        description:
                            'Registe pedidos e vendas de forma simples.',
                        action: FilledButton.icon(
                          onPressed: onNewSale,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Nova venda'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Visão geral',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Atualizar dados',
                            onPressed: controller.refreshAll,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      Text(
                        'Dados da última consulta ao servidor',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final scale = MediaQuery.textScalerOf(context)
                              .scale(1);
                          final columns =
                              constraints.maxWidth < 230 || scale > 1.8
                              ? 1
                              : (constraints.maxWidth < 360 || scale > 1.3
                                    ? 2
                                    : 3);
                          final width =
                              (constraints.maxWidth - (columns - 1) * 8) /
                              columns;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SizedBox(
                                width: width,
                                child: _StatCard(
                                  icon: Icons.egg_alt_outlined,
                                  label: 'Itens de stock',
                                  value:
                                      controller.products?.length.toString() ??
                                      'Indisponível',
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _StatCard(
                                  icon: Icons.warning_amber_outlined,
                                  label: 'Stock baixo',
                                  value: lowStock,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _StatCard(
                                  icon: Icons.people_outline,
                                  label: 'Clientes',
                                  value:
                                      controller.customers?.length.toString() ??
                                      'Indisponível',
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _StatCard(
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Sem stock',
                                  value: noStock,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (hasError) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Alguns dados não puderam ser carregados. Atualize para tentar novamente.',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Acesso rápido',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OverviewActionTile(
                        icon: Icons.warehouse_outlined,
                        title: 'Stock e preços',
                        subtitle: 'Consultar e atualizar quantidades',
                        onTap: () => onOpenTab(1),
                      ),
                      OverviewActionTile(
                        icon: Icons.people_outline,
                        title: 'Clientes',
                        subtitle: 'Consultar clientes registados',
                        onTap: () => onOpenTab(2),
                      ),
                      OverviewActionTile(
                        icon: Icons.receipt_long_outlined,
                        title: 'Vendas e pedidos',
                        subtitle: 'Entregas e pagamentos pendentes',
                        onTap: () => onOpenTab(3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

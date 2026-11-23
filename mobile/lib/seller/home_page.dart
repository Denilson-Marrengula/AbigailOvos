import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../design/app_logo.dart';
import '../design/app_theme.dart';
import 'seller_controller.dart';

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
            ? '—'
            : controller.balances.values
                  .where((balance) => balance.available <= 0)
                  .length
                  .toString();
        final hasError =
            controller.productsError != null ||
            controller.customersError != null ||
            controller.stockError != null;

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
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.forest, Color(0xFF24634D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AppLogo(size: 60),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ABIGAILOVOS',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: const Color(0xFFF5DF9A),
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        'Olá, ${session.username}',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Perfil: Vendedor',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Registe pedidos e vendas de forma simples.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: onNewSale,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: const Color(0xFF172A20),
                                minimumSize: const Size.fromHeight(48),
                              ),
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text('Nova venda'),
                            ),
                          ],
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
                                      '—',
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _StatCard(
                                  icon: Icons.people_outline,
                                  label: 'Clientes',
                                  value:
                                      controller.customers?.length.toString() ??
                                      '—',
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
                      _ActionTile(
                        icon: Icons.warehouse_outlined,
                        title: 'Stock e preços',
                        subtitle: 'Consultar e atualizar quantidades',
                        onTap: () => onOpenTab(1),
                      ),
                      _ActionTile(
                        icon: Icons.people_outline,
                        title: 'Clientes',
                        subtitle: 'Consultar clientes registados',
                        onTap: () => onOpenTab(2),
                      ),
                      _ActionTile(
                        icon: Icons.receipt_long_outlined,
                        title: 'Vendas e pedidos',
                        subtitle: 'Acompanhar operações',
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
      color: theme.colorScheme.surfaceContainerLow,
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

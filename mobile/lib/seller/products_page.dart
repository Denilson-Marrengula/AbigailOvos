import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.controller});
  final SellerController controller;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final products = controller.products;
        if (products == null) {
          if (controller.productsError == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: StateMessage(
              icon: Icons.cloud_off_outlined,
              message: controller.productsError!,
              actionLabel: 'Tentar novamente',
              onAction: controller.loadProducts,
            ),
          );
        }
        final query = _query.trim().toLowerCase();
        final filtered = products
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
        return Column(
          children: [
            SearchField(
              controller: _search,
              hint: 'Pesquisar produto',
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.loadProducts,
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          StateMessage(
                            icon: Icons.inventory_2_outlined,
                            message: products.isEmpty
                                ? 'Ainda não existem produtos.'
                                : 'Nenhum produto encontrado.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.medium),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.egg_alt_outlined),
                              ),
                              title: Text(product.name),
                              subtitle: Text(
                                'Unidade: ${product.unit}${product.active ? '' : ' · Inativo'}',
                              ),
                              trailing: Text(
                                formatMoney(product.price),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

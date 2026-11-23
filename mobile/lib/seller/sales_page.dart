import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    super.key,
    required this.controller,
    required this.isAdmin,
    required this.onExpired,
    required this.onNewSale,
  });
  final SellerController controller;
  final bool isAdmin;
  final VoidCallback onExpired;
  final VoidCallback onNewSale;
  @override
  State<SalesPage> createState() => SalesPageState();
}

class SalesPageState extends State<SalesPage> {
  List<SaleRecord>? sales;
  String? error;
  bool busy = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.controller.auth.sales();
      if (mounted) {
        setState(() {
          sales = result;
          error = null;
        });
      }
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        setState(() {
          sales = null;
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          sales = null;
          error = 'Não foi possível carregar as vendas.';
        });
      }
    }
  }

  Future<void> _action(SaleRecord sale, String action, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text('Confirmar esta operação para ${sale.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await widget.controller.auth.changeSale(sale.id, action);
      await Future.wait([_load(), widget.controller.refreshStock()]);
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() => _load();

  @override
  Widget build(BuildContext context) {
    final status = ['PENDING', 'DELIVERED', 'CANCELLED'][tab];
    final filtered = sales?.where((s) => s.delivery == status).toList();
    return Column(
      children: [
        if (!widget.isAdmin)
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: busy ? null : widget.onNewSale,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nova venda'),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Pendentes')),
              ButtonSegment(value: 1, label: Text('Concluídas')),
              ButtonSegment(value: 2, label: Text('Canceladas')),
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.first),
          ),
        ),
        Expanded(
          child: error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : filtered == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: filtered.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text('Nenhuma operação neste estado.'),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final sale = filtered[index];
                            return Card(
                              child: ExpansionTile(
                                title: Text(sale.customerName),
                                subtitle: Text(
                                  '${formatMoney(sale.totalText ?? sale.total.toStringAsFixed(2))} · ${sale.payment == 'PAID' ? 'Pago' : 'Pagamento pendente'}',
                                ),
                                children: [
                                  for (final line in sale.items)
                                    ListTile(dense: true, title: Text(line)),
                                  ListTile(
                                    dense: true,
                                    title: Text('Vendedor: ${sale.seller}'),
                                  ),
                                  if (!widget.isAdmin)
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        if (sale.delivery == 'PENDING')
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => _action(
                                                    sale,
                                                    'deliver',
                                                    'Registar entrega',
                                                  ),
                                            child: const Text('Entregar'),
                                          ),
                                        if (sale.delivery != 'CANCELLED' &&
                                            sale.payment == 'PENDING')
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => _action(
                                                    sale,
                                                    'pay',
                                                    'Registar pagamento',
                                                  ),
                                            child: const Text('Marcar pago'),
                                          ),
                                        if (sale.delivery == 'PENDING' &&
                                            sale.payment == 'PENDING')
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => _action(
                                                    sale,
                                                    'cancel',
                                                    'Cancelar pedido',
                                                  ),
                                            child: const Text(
                                              'Cancelar pedido',
                                            ),
                                          ),
                                      ],
                                    ),
                                  if (sale.delivery == 'PENDING' &&
                                      sale.payment == 'PAID')
                                    const ListTile(
                                      dense: true,
                                      title: Text(
                                        'Cancelamento de pedido pago requer tratamento de reembolso, ainda indisponível.',
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

class SaleFormPage extends StatefulWidget {
  const SaleFormPage({
    super.key,
    required this.controller,
    required this.onExpired,
  });
  final SellerController controller;
  final VoidCallback onExpired;
  @override
  State<SaleFormPage> createState() => _SaleFormPageState();
}

class _SaleFormPageState extends State<SaleFormPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final search = TextEditingController();
  final quantities = <String, TextEditingController>{};
  String? customerId;
  bool newCustomer = false;
  bool deliverNow = true;
  bool paid = false;
  bool saving = false;
  String? error;
  Map<String, dynamic>? submitted;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    search.dispose();
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    if (submitted == null) {
      if ((!newCustomer && customerId == null) ||
          (newCustomer && name.text.trim().isEmpty)) {
        setState(
          () =>
              error = 'Selecione um cliente ou indique o nome do novo cliente.',
        );
        return;
      }
      final items = <Map<String, dynamic>>[];
      for (final product in widget.controller.products!.where(
        (p) => p.active,
      )) {
        final raw = quantities[product.id]!.text.trim().replaceAll(',', '.');
        if (raw.isEmpty) continue;
        if (!RegExp(r'^\d{1,17}(\.\d{1,2})?$').hasMatch(raw) ||
            (double.tryParse(raw) ?? 0) <= 0) {
          setState(
            () => error =
                'Indique quantidades positivas com até duas casas decimais.',
          );
          return;
        }
        items.add({
          'productId': product.id,
          'quantity': raw,
          'expectedUnitPrice': product.price,
        });
      }
      if (items.isEmpty) {
        setState(
          () => error = 'Indique a quantidade de pelo menos um produto.',
        );
        return;
      }
      submitted = {
        'id': createOperationId(),
        if (newCustomer)
          'customer': {'name': name.text.trim(), 'phone': phone.text.trim()}
        else
          'customerId': customerId,
        'items': items,
        'deliverNow': deliverNow,
        'paid': paid,
      };
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.auth.createSale(submitted!);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        setState(() {
          if (e.definitelyRejected) submitted = null;
          error = e.definitelyRejected
              ? e.message
              : '${e.message}\nPode repetir o mesmo envio. Se sair, verifique a lista antes de criar outra operação.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Resultado desconhecido. Repita o mesmo envio ou verifique a lista antes de criar outra operação.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final locked = saving || submitted != null;
    final products = controller.products;
    final customers = controller.customers;
    final typedName = name.text.trim().toLowerCase();
    final typedPhone = normalizePhone(phone.text);
    final possibleDuplicates = (customers ?? const <Customer>[])
        .where((customer) {
          return (typedName.isNotEmpty &&
                  customer.name.trim().toLowerCase() == typedName) ||
              (typedPhone != null &&
                  normalizePhone(customer.phone) == typedPhone);
        })
        .take(3)
        .toList();
    if (products != null) {
      for (final product in products.where((p) => p.active)) {
        quantities.putIfAbsent(product.id, TextEditingController.new);
      }
    }
    final estimate =
        products?.fold<double>(
          0,
          (sum, product) =>
              sum +
              (double.tryParse(product.price) ?? 0) *
                  (double.tryParse(
                        quantities[product.id]?.text.replaceAll(',', '.') ?? '',
                      ) ??
                      0),
        ) ??
        0;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova venda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (products == null || customers == null) ...[
            const Text(
              'É necessário carregar produtos e clientes antes de iniciar.',
            ),
            TextButton(
              onPressed: () async {
                await controller.refreshAll();
                if (mounted) setState(() {});
              },
              child: const Text('Tentar novamente'),
            ),
          ] else ...[
            SwitchListTile(
              title: const Text('Novo cliente'),
              value: newCustomer,
              onChanged: locked ? null : (v) => setState(() => newCustomer = v),
            ),
            if (newCustomer) ...[
              TextField(
                controller: name,
                enabled: !locked,
                maxLength: 150,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Nome do cliente'),
              ),
              TextField(
                controller: phone,
                enabled: !locked,
                maxLength: 40,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Telefone (opcional)',
                ),
              ),
              if (possibleDuplicates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Possível cliente já registado: ${possibleDuplicates.map((c) => c.name).join(', ')}. Pode selecioná-lo desativando “Novo cliente”.',
                  ),
                ),
            ] else ...[
              TextField(
                controller: search,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Pesquisar cliente por nome ou telefone',
                ),
                onChanged: (_) => setState(() {}),
              ),
              DropdownButtonFormField<String>(
                initialValue: customerId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: customers
                    .where(
                      (c) =>
                          c.id == customerId ||
                          c.name.toLowerCase().contains(
                            search.text.toLowerCase().trim(),
                          ) ||
                          (c.phone ?? '').contains(search.text.trim()),
                    )
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.name}${c.phone == null ? '' : ' · ${c.phone}'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: locked
                    ? null
                    : (v) => setState(() => customerId = v),
                isExpanded: true,
              ),
            ],
            const SizedBox(height: 16),
            const Text('Produtos e quantidades'),
            if (products.where((p) => p.active).isEmpty)
              const Text('Não há produtos disponíveis.'),
            for (final product in products.where((p) => p.active))
              ListTile(
                title: Text(product.name),
                subtitle: Text('${product.price} MT / ${product.unit}'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: quantities[product.id],
                    enabled: !locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Qtd.'),
                  ),
                ),
              ),
            Text('Total indicativo: ${estimate.toStringAsFixed(2)} MT'),
            SwitchListTile(
              title: const Text('Entregar agora'),
              subtitle: Text(
                deliverNow ? 'Venda concluída' : 'Pedido para entregar depois',
              ),
              value: deliverNow,
              onChanged: locked ? null : (v) => setState(() => deliverNow = v),
            ),
            SwitchListTile(
              title: const Text('Pagamento recebido'),
              value: paid,
              onChanged: locked ? null : (v) => setState(() => paid = v),
            ),
            if (paid && !deliverNow)
              const Text(
                'Pedidos pagos não podem ser cancelados nesta versão; o reembolso ainda não está disponível.',
              ),
            const Text(
              'O servidor calcula o valor final com os preços atuais e verifica o stock disponível.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (error != null && !locked)
              TextButton(
                onPressed: () async {
                  await controller.refreshAll();
                  if (mounted) setState(() {});
                },
                child: const Text('Atualizar produtos e clientes'),
              ),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(
                saving
                    ? 'A guardar...'
                    : submitted == null
                    ? 'Confirmar venda'
                    : 'Repetir envio',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
    this.initialTab = 0,
  }) : assert(initialTab >= 0 && initialTab < 5);
  final SellerController controller;
  final bool isAdmin;
  final VoidCallback onExpired;
  final VoidCallback onNewSale;
  final int initialTab;
  @override
  State<SalesPage> createState() => SalesPageState();
}

class SalesPageState extends State<SalesPage> {
  List<SaleRecord>? sales;
  String? error;
  final customerFilter = TextEditingController();
  final productFilter = TextEditingController();
  final sellerFilter = TextEditingController();
  DateTimeRange? period;
  int page = 0;
  bool hasMore = false;
  bool busy = false;
  bool confirming = false;
  late int tab;
  int _loadGeneration = 0;
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
    _load();
  }

  @override
  void dispose() {
    customerFilter.dispose();
    productFilter.dispose();
    sellerFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        sales = null;
        error = null;
      });
    }
    try {
      final result = await widget.controller.auth.searchSales(
        page: page,
        customer: customerFilter.text,
        product: productFilter.text,
        seller: widget.isAdmin ? sellerFilter.text : null,
        state: const [
          'PENDING_DELIVERY',
          'PENDING_PAYMENT',
          'DELIVERED',
          'CANCELLED',
          'ALL',
        ][tab],
        from: period?.start,
        to: period?.end,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() {
          sales = result.items;
          hasMore = result.hasMore;
          error = null;
        });
      }
    } on AuthException catch (e) {
      if (mounted && generation == _loadGeneration && e.sessionExpired) {
        widget.onExpired();
      }
      if (mounted && generation == _loadGeneration) {
        setState(() {
          sales = null;
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          sales = null;
          error = 'Não foi possível carregar as vendas.';
        });
      }
    }
  }

  Future<void> _action(SaleRecord sale, String action, String label) async {
    if (busy || confirming) return;
    setState(() => confirming = true);
    PaymentMethod? method;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(label),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action == 'pay'
                      ? 'Marcar o pagamento de ${sale.customerName} como pago? Isso não comprova o recebimento externo.'
                      : 'Confirmar esta operação para ${sale.customerName}?',
                ),
                if (action == 'pay')
                  DropdownButtonFormField<PaymentMethod>(
                    decoration: const InputDecoration(
                      labelText: 'Meio de pagamento',
                    ),
                    isExpanded: true,
                    items: [
                      for (final option in PaymentMethod.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => method = value),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: action == 'pay' && method == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (confirmed != true || busy) return;
    setState(() => busy = true);
    try {
      await widget.controller.auth.changeSale(
        sale.id,
        action,
        paymentMethod: method,
      );
      await Future.wait([_load(), widget.controller.refreshStock()]);
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.definitelyRejected
                  ? e.message
                  : '${e.message} Verifique o estado da operação antes de repetir.',
            ),
          ),
        );
      }
      if (!e.sessionExpired && mounted) {
        await Future.wait([_load(), widget.controller.refreshStock()]);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resultado desconhecido. Verifique o estado da operação antes de repetir.',
            ),
          ),
        );
        await Future.wait([_load(), widget.controller.refreshStock()]);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() => _load();

  Future<void> _choosePeriod() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: period,
      helpText: 'Data de registo da operação (Maputo)',
    );
    if (selected == null || !mounted) return;
    setState(() => period = selected);
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    final filtered = sales
        ?.where(
          (sale) => switch (tab) {
            0 => sale.delivery == 'PENDING',
            1 =>
              (sale.delivery == 'PENDING' || sale.delivery == 'DELIVERED') &&
                  sale.payment == 'PENDING',
            2 => sale.delivery == 'DELIVERED',
            3 => sale.delivery == 'CANCELLED',
            _ => true,
          },
        )
        .toList();
    return Column(
      children: [
        if (!widget.isAdmin)
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: busy || confirming ? null : widget.onNewSale,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nova venda'),
            ),
          ),
        ExpansionTile(
          title: const Text('Pesquisar e filtrar'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            TextField(
              controller: customerFilter,
              decoration: const InputDecoration(labelText: 'Cliente'),
            ),
            TextField(
              controller: productFilter,
              decoration: const InputDecoration(labelText: 'Produto'),
            ),
            if (widget.isAdmin)
              TextField(
                controller: sellerFilter,
                decoration: const InputDecoration(
                  labelText: 'Utilizador do vendedor',
                ),
              ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _choosePeriod,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    period == null
                        ? 'Data de registo'
                        : '${_date(period!.start)} a ${_date(period!.end)}',
                  ),
                ),
                if (period != null)
                  TextButton(
                    onPressed: () => setState(() => period = null),
                    child: const Text('Limpar datas'),
                  ),
                FilledButton(
                  onPressed: () {
                    setState(() => page = 0);
                    _load();
                  },
                  child: const Text('Pesquisar'),
                ),
              ],
            ),
            const Text(
              'O período usa a data de registo, no horário de Maputo.',
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Por entregar')),
              ButtonSegment(value: 1, label: Text('Por pagar')),
              ButtonSegment(value: 2, label: Text('Entregues')),
              ButtonSegment(value: 3, label: Text('Canceladas')),
              ButtonSegment(value: 4, label: Text('Todas')),
            ],
            selected: {tab},
            onSelectionChanged: (value) {
              setState(() {
                tab = value.first;
                page = 0;
              });
              _load();
            },
          ),
        ),
        if (tab == 0 || tab == 1)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Pedidos por entregar e por pagar aparecem nas duas listas.',
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
                              key: ValueKey(sale.id),
                              child: ExpansionTile(
                                title: Text(sale.customerName),
                                subtitle: Text(
                                  '${sale.seller} · ${formatMoney(sale.totalText ?? sale.total.toStringAsFixed(2))}\n'
                                  '${switch (sale.delivery) {
                                    'PENDING' => 'Por entregar',
                                    'DELIVERED' => 'Entregue',
                                    'CANCELLED' => 'Cancelada',
                                    _ => 'Entrega desconhecida',
                                  }} · ${sale.payment == 'PAID' ? 'Marcado como pago' : 'Pagamento pendente'}',
                                ),
                                children: [
                                  for (final line in sale.items)
                                    ListTile(dense: true, title: Text(line)),
                                  ListTile(
                                    dense: true,
                                    title: Text('Vendedor: ${sale.seller}'),
                                  ),
                                  if (sale.payment == 'PAID')
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        'Meio de pagamento: ${paymentMethodLabel(sale.paymentMethod)}',
                                      ),
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (sale.delivery == 'PENDING')
                                        TextButton(
                                          onPressed: busy || confirming
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
                                          onPressed: busy || confirming
                                              ? null
                                              : () => _action(
                                                  sale,
                                                  'pay',
                                                  'Marcar como pago',
                                                ),
                                          child: const Text('Marcar pago'),
                                        ),
                                      if (!widget.isAdmin &&
                                          sale.delivery == 'PENDING' &&
                                          sale.payment == 'PENDING')
                                        TextButton(
                                          onPressed: busy || confirming
                                              ? null
                                              : () => _action(
                                                  sale,
                                                  'cancel',
                                                  'Cancelar pedido',
                                                ),
                                          child: const Text('Cancelar pedido'),
                                        ),
                                    ],
                                  ),
                                  if (sale.delivery == 'PENDING' &&
                                      sale.payment == 'PAID')
                                    const ListTile(
                                      dense: true,
                                      title: Text(
                                        'Pedido pago não pode ser cancelado; reembolso indisponível nesta versão.',
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
        ),
        if (sales != null && (page > 0 || hasMore))
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: page == 0
                    ? null
                    : () {
                        setState(() => page--);
                        _load();
                      },
                child: const Text('Anterior'),
              ),
              Text('Página ${page + 1}'),
              TextButton(
                onPressed: !hasMore
                    ? null
                    : () {
                        setState(() => page++);
                        _load();
                      },
                child: const Text('Seguinte'),
              ),
            ],
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
  final productSearch = TextEditingController();
  final quantities = <String, TextEditingController>{};
  String? customerId;
  bool newCustomer = false;
  bool deliverNow = true;
  bool paid = false;
  PaymentMethod? paymentMethod;
  bool saving = false;
  String? error;
  Map<String, dynamic>? submitted;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    search.dispose();
    productSearch.dispose();
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    final retryingUnknown = submitted != null;
    if (submitted == null) {
      if (paid && paymentMethod == null) {
        setState(() => error = 'Selecione o meio de pagamento.');
        return;
      }
      if ((!newCustomer && customerId == null) ||
          (newCustomer && name.text.trim().isEmpty)) {
        setState(
          () =>
              error = 'Selecione um cliente ou indique o nome do novo cliente.',
        );
        return;
      }
      if (newCustomer) {
        final key = customerPhoneKey(phone.text);
        if (key == null) {
          setState(
            () => error = 'Indique um telefone válido para o novo cliente.',
          );
          return;
        }
        if (widget.controller.customers!.any(
          (customer) => customerPhoneKey(customer.phone) == key,
        )) {
          setState(
            () => error = 'Este telefone já está registado. Selecione o cliente existente.',
          );
          return;
        }
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
        if (paid) 'paymentMethod': paymentMethod!.code,
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
      if (e.code == 'CUSTOMER_PHONE_EXISTS') {
        await widget.controller.loadCustomers();
      }
      if (mounted) {
        setState(() {
          if (e.definitelyRejected && !retryingUnknown) submitted = null;
          error = e.definitelyRejected && !retryingUnknown
              ? e.message
              : '${e.message}\nO resultado anterior pode ser desconhecido. Repita o mesmo envio; se sair, verifique a lista antes de criar outra operação.';
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
    final newPhoneKey = customerPhoneKey(phone.text);
    final phoneMatches = (customers ?? const <Customer>[])
        .where(
          (customer) =>
              newPhoneKey != null &&
              customerPhoneKey(customer.phone) == newPhoneKey,
        )
        .toList();
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
            Text(
              '1. Produtos e quantidades',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: productSearch,
              enabled: !locked,
              decoration: const InputDecoration(
                labelText: 'Pesquisar produto',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (products.where((p) => p.active).isEmpty)
              const Text('Não há produtos disponíveis.'),
            for (final product in products.where(
              (p) =>
                  p.active &&
                  p.name.toLowerCase().contains(
                    productSearch.text.trim().toLowerCase(),
                  ),
            ))
              ListTile(
                title: Text(product.name),
                subtitle: Text(
                  '${product.price} MT / ${product.unit}\n'
                  '${controller.balances[product.id] == null ? 'Stock indisponível' : 'Disponível na última consulta: ${formatQuantity(controller.balances[product.id]!.available)} ${product.unit}'}',
                ),
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
            const SizedBox(height: 16),
            Text('2. Cliente', style: Theme.of(context).textTheme.titleMedium),
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
                  labelText: 'Telefone (obrigatório)',
                ),
              ),
              if (phoneMatches.length == 1)
                TextButton(
                  onPressed: locked
                      ? null
                      : () => setState(() {
                          newCustomer = false;
                          customerId = phoneMatches.first.id;
                          search.clear();
                          error = null;
                        }),
                  child: Text(
                    'Usar cliente existente: ${phoneMatches.first.name}',
                  ),
                ),
              if (phoneMatches.length > 1)
                const Text(
                  'Vários clientes têm este telefone. Peça ao administrador para rever os registos.',
                ),
              if (possibleDuplicates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Possível cliente já registado: ${possibleDuplicates.map((c) => c.name).join(', ')}. Desative “Novo cliente” para selecionar.',
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
            Text(
              '3. Rever e confirmar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (newCustomer && name.text.trim().isNotEmpty)
              Text('Cliente: ${name.text.trim()} (novo)')
            else if (!newCustomer && customerId != null)
              for (final customer in customers.where((c) => c.id == customerId))
                Text('Cliente: ${customer.name}'),
            for (final product in products.where(
              (p) =>
                  p.active &&
                  (double.tryParse(
                            quantities[p.id]?.text.replaceAll(',', '.') ?? '',
                          ) ??
                          0) >
                      0,
            ))
              ListTile(
                dense: true,
                title: Text(product.name),
                subtitle: Text(
                  '${quantities[product.id]!.text.trim()} ${product.unit} · ${product.price} MT por ${product.unit}',
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
              onChanged: locked
                  ? null
                  : (v) => setState(() {
                      paid = v;
                      if (!v) paymentMethod = null;
                    }),
            ),
            if (paid)
              DropdownButtonFormField<PaymentMethod>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Meio de pagamento',
                ),
                isExpanded: true,
                items: [
                  for (final option in PaymentMethod.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: locked
                    ? null
                    : (value) => setState(() => paymentMethod = value),
              ),
            if (paid)
              const Text('A marcação não comprova o recebimento externo.'),
            if (paid && !deliverNow)
              const Text(
                'Pedido pago não pode ser cancelado; reembolso indisponível nesta versão.',
              ),
            const Text(
              'O servidor verifica o stock e calcula o valor com os preços atuais.',
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

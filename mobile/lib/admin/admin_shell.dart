import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../design/app_logo.dart';
import '../seller/seller_widgets.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.auth, required this.session});
  final AuthService auth;
  final AuthSession session;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;
  bool leaving = false;

  void _logout({String? notice}) {
    widget.auth.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginPage(auth: widget.auth, notice: notice),
      ),
      (_) => false,
    );
  }

  void _expired() {
    if (leaving) return;
    leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _logout(notice: 'A sessão terminou. Inicie sessão novamente.');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          const AppLogo(size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ['Vendedores', 'Clientes', 'Relatórios'][index],
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Terminar sessão',
          onPressed: _logout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: IndexedStack(
      index: index,
      children: [
        SellersPage(auth: widget.auth, onExpired: _expired),
        AdminCustomersPage(auth: widget.auth, onExpired: _expired),
        AdminReportsPage(auth: widget.auth, onExpired: _expired),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => setState(() => index = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.badge_outlined),
          selectedIcon: Icon(Icons.badge),
          label: 'Vendedores',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Clientes',
        ),
        NavigationDestination(
          icon: Icon(Icons.assessment_outlined),
          selectedIcon: Icon(Icons.assessment),
          label: 'Relatórios',
        ),
      ],
    ),
  );
}

Future<T> _guard<T>(Future<T> Function() action, VoidCallback onExpired) async {
  try {
    return await action();
  } on AuthException catch (e) {
    if (e.sessionExpired) onExpired();
    rethrow;
  }
}

Widget _loadFailure(Object? error, VoidCallback retry) => Center(
  child: StateMessage(
    icon: Icons.cloud_off_outlined,
    message: error is AuthException
        ? error.message
        : 'Não foi possível carregar os dados.',
    actionLabel: 'Tentar novamente',
    onAction: retry,
  ),
);

class SellersPage extends StatefulWidget {
  const SellersPage({super.key, required this.auth, required this.onExpired});
  final AuthService auth;
  final VoidCallback onExpired;
  @override
  State<SellersPage> createState() => _SellersPageState();
}

class _SellersPageState extends State<SellersPage> {
  late Future<List<SellerAccount>> sellers;
  bool changing = false;
  @override
  void initState() {
    super.initState();
    sellers = _fetch();
  }

  Future<List<SellerAccount>> _fetch() =>
      _guard(widget.auth.sellers, widget.onExpired);
  Future<void> _refresh() async {
    final next = _fetch();
    if (mounted) {
      setState(() {
        sellers = next;
      });
    }
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _form([SellerAccount? seller]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerFormPage(
          auth: widget.auth,
          onExpired: widget.onExpired,
          seller: seller,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _toggle(SellerAccount seller) async {
    final action = seller.enabled ? 'Desativar' : 'Reativar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action vendedor?'),
        content: Text(
          seller.enabled
              ? 'A conta ${seller.username} deixará de poder iniciar sessão. O histórico será preservado.'
              : 'A conta ${seller.username} poderá iniciar sessão novamente.',
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
    if (confirmed != true || !mounted || changing) return;
    setState(() => changing = true);
    try {
      await _guard(
        () => widget.auth.setSellerEnabled(seller.id, !seller.enabled),
        widget.onExpired,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              seller.enabled ? 'Vendedor desativado.' : 'Vendedor reativado.',
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.message} Verifique o estado na lista.')),
        );
      }
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível confirmar a alteração. Verifique a lista.',
            ),
          ),
        );
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: changing ? null : _form,
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Novo vendedor'),
    ),
    body: FutureBuilder<List<SellerAccount>>(
      future: sellers,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _loadFailure(snapshot.error, _refresh);
        final list = [...snapshot.data!]
          ..sort(
            (a, b) => (a.displayName ?? a.username).toLowerCase().compareTo(
              (b.displayName ?? b.username).toLowerCase(),
            ),
          );
        return RefreshIndicator(
          onRefresh: _refresh,
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    StateMessage(
                      icon: Icons.badge_outlined,
                      message: 'Ainda não existem vendedores.',
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final seller = list[i];
                    return Card(
                      child: ListTile(
                        title: Text(
                          seller.displayName?.isNotEmpty == true
                              ? seller.displayName!
                              : seller.username,
                        ),
                        subtitle: Text(
                          '${seller.username} · ${seller.enabled ? 'Ativo' : 'Inativo'}${seller.phone == null ? '' : '\n${seller.phone}'}',
                        ),
                        isThreeLine: seller.phone != null,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Opções do vendedor',
                          enabled: !changing,
                          onSelected: (value) {
                            if (value == 'edit') {
                              _form(seller);
                            } else {
                              _toggle(seller);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar dados'),
                            ),
                            PopupMenuItem(
                              value: 'status',
                              child: Text(
                                seller.enabled ? 'Desativar' : 'Reativar',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}

class SellerFormPage extends StatefulWidget {
  const SellerFormPage({
    super.key,
    required this.auth,
    required this.onExpired,
    this.seller,
  });
  final AuthService auth;
  final VoidCallback onExpired;
  final SellerAccount? seller;
  @override
  State<SellerFormPage> createState() => _SellerFormPageState();
}

class _SellerFormPageState extends State<SellerFormPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController phone;
  final username = TextEditingController();
  final password = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.seller?.displayName ?? widget.seller?.username ?? '',
    );
    phone = TextEditingController(text: widget.seller?.phone ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final contact = phone.text.trim().isEmpty ? null : phone.text.trim();
    try {
      if (widget.seller == null) {
        await _guard(
          () => widget.auth.createSeller(
            username.text.trim(),
            password.text,
            name.text.trim(),
            contact,
          ),
          widget.onExpired,
        );
      } else {
        await _guard(
          () => widget.auth.updateSeller(
            widget.seller!.id,
            name.text.trim(),
            contact,
          ),
          widget.onExpired,
        );
      }
      password.clear();
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => error = e.definitelyRejected
              ? e.message
              : '${e.message}\nVerifique a lista antes de voltar a criar a conta.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Resultado desconhecido. Verifique a lista antes de voltar a criar a conta.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.seller == null ? 'Novo vendedor' : 'Editar vendedor'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: name,
                  enabled: !saving,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Introduza o nome.'
                      : null,
                ),
                TextFormField(
                  controller: phone,
                  enabled: !saving,
                  maxLength: 40,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone (opcional)',
                  ),
                ),
                if (widget.seller == null) ...[
                  TextFormField(
                    controller: username,
                    enabled: !saving,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Utilizador'),
                    validator: (v) =>
                        !RegExp(r'^[a-zA-Z0-9._-]{3,100}$')
                            .hasMatch(v?.trim() ?? '')
                        ? 'Use 3–100 letras, números, ponto, traço ou sublinhado.'
                        : null,
                  ),
                  TextFormField(
                    controller: password,
                    enabled: !saving,
                    obscureText: true,
                    maxLength: 72,
                    decoration: const InputDecoration(
                      labelText: 'Palavra-passe inicial',
                      helperText: 'Mínimo de 12 caracteres ASCII imprimíveis.',
                    ),
                    validator: (v) =>
                        !RegExp(r'^[\x20-\x7E]{12,72}$').hasMatch(v ?? '') ||
                            (v ?? '').trim().isEmpty
                        ? 'Use 12–72 caracteres ASCII imprimíveis.'
                        : null,
                  ),
                ] else
                  Text('Utilizador: ${widget.seller!.username}'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'A guardar...' : 'Guardar'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AdminCustomersPage extends StatefulWidget {
  const AdminCustomersPage({
    super.key,
    required this.auth,
    required this.onExpired,
  });
  final AuthService auth;
  final VoidCallback onExpired;
  @override
  State<AdminCustomersPage> createState() => _AdminCustomersPageState();
}

class _AdminCustomersPageState extends State<AdminCustomersPage> {
  late Future<List<Customer>> customers;
  String query = '';
  @override
  void initState() {
    super.initState();
    customers = _fetch();
  }

  Future<List<Customer>> _fetch() =>
      _guard(widget.auth.customers, widget.onExpired);
  Future<void> _refresh() async {
    final next = _fetch();
    if (mounted) {
      setState(() {
        customers = next;
      });
    }
    try {
      await next;
    } catch (_) {
      /* FutureBuilder apresenta o erro. */
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Customer>>(
    future: customers,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) return _loadFailure(snapshot.error, _refresh);
      final list = snapshot.data!
          .where(
            (c) =>
                c.name.toLowerCase().contains(query) ||
                (c.phone ?? '').toLowerCase().contains(query),
          )
          .toList();
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Lista de clientes. O estado ativo ainda não está definido.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Pesquisar cliente',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        StateMessage(
                          icon: Icons.people_outline,
                          message: 'Nenhum cliente encontrado.',
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (context, i) => Card(
                        child: ListTile(
                          title: Text(list[i].name),
                          subtitle: Text(list[i].phone ?? 'Sem contacto'),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      );
    },
  );
}

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({
    super.key,
    required this.auth,
    required this.onExpired,
  });
  final AuthService auth;
  final VoidCallback onExpired;
  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  late Future<SalesReport> report;
  Future<List<SaleRecord>>? details;
  @override
  void initState() {
    super.initState();
    report = _fetch();
  }

  Future<SalesReport> _fetch() =>
      _guard(widget.auth.salesReport, widget.onExpired);
  Future<List<SaleRecord>> _fetchDetails() =>
      _guard(widget.auth.sales, widget.onExpired);
  Future<void> _refresh() async {
    final next = _fetch();
    final nextDetails = details == null ? null : _fetchDetails();
    // Attach error handlers immediately to both concurrent requests.
    final waiting = <Future<void>>[
      next.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      if (nextDetails != null)
        nextDetails.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ];
    if (mounted) {
      setState(() {
        report = next;
        details = nextDetails;
      });
    }
    await Future.wait(waiting);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SalesReport>(
    future: report,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) return _loadFailure(snapshot.error, _refresh);
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Resumo de todas as operações registadas.'),
            ListTile(
              title: const Text('Pedidos pendentes'),
              trailing: Text('${data.pendingOrders}'),
            ),
            ListTile(
              title: const Text('Vendas entregues'),
              trailing: Text('${data.deliveredSales}'),
            ),
            ListTile(
              title: const Text('Operações canceladas'),
              trailing: Text('${data.cancelledOperations}'),
            ),
            ListTile(
              title: const Text('Pagamentos pendentes'),
              subtitle: const Text('Exclui operações canceladas'),
              trailing: Text('${data.pendingPayments}'),
            ),
            const Divider(),
            Text(
              'Valores das operações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ListTile(
              title: const Text('Valor das vendas entregues'),
              subtitle: const Text('Independentemente do pagamento'),
              trailing: Text(formatMoney(data.deliveredAmount)),
            ),
            ListTile(
              title: const Text('Marcado como pago'),
              subtitle: const Text('Inclui pedidos ainda não entregues'),
              trailing: Text(formatMoney(data.markedPaidAmount)),
            ),
            ListTile(
              title: const Text('Pagamento pendente'),
              subtitle: const Text('Pedidos e vendas não cancelados'),
              trailing: Text(formatMoney(data.pendingPaymentAmount)),
            ),
            const Divider(),
            Text(
              'Vendas entregues por vendedor',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (data.sellers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Ainda não há vendas entregues.'),
              ),
            for (final seller in data.sellers)
              ListTile(
                title: Text(seller.seller),
                subtitle: Text(formatMoney(seller.deliveredAmount)),
                trailing: Text('${seller.deliveredCount}'),
              ),
            const Text(
              'Os valores pagos refletem apenas o estado marcado na aplicação; não comprovam recebimentos externos.',
            ),
            const Divider(),
            ExpansionTile(
              title: const Text('Operações registadas'),
              subtitle: const Text('Consultar detalhes'),
              onExpansionChanged: (open) {
                if (open && details == null) {
                  setState(() {
                    details = _fetchDetails();
                  });
                }
              },
              children: [
                if (details != null)
                  FutureBuilder<List<SaleRecord>>(
                    future: details,
                    builder: (context, detailsSnapshot) {
                      if (detailsSnapshot.connectionState !=
                          ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (detailsSnapshot.hasError) {
                        return _loadFailure(detailsSnapshot.error, _refresh);
                      }
                      final operations = detailsSnapshot.data!;
                      if (operations.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Ainda não há operações registadas.'),
                        );
                      }
                      return Column(
                        children: [
                          for (final sale in operations) _saleDetails(sale),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _saleDetails(SaleRecord sale) => Card(
    child: ExpansionTile(
      title: Text(sale.customerName),
      subtitle: Text(
        '${sale.seller} · ${formatMoney(sale.totalText ?? sale.total.toStringAsFixed(2))}',
      ),
      children: [
        ListTile(
          dense: true,
          title: Text(
            'Entrega: ${switch (sale.delivery) {
              'PENDING' => 'Pendente',
              'DELIVERED' => 'Entregue',
              'CANCELLED' => 'Cancelada',
              _ => 'Estado desconhecido',
            }}',
          ),
        ),
        ListTile(
          dense: true,
          title: Text(
            sale.payment == 'PAID'
                ? 'Pagamento: marcado como pago'
                : 'Pagamento: pendente',
          ),
        ),
        if (sale.createdAt != null)
          ListTile(
            dense: true,
            title: Text('Registada em: ${_formatDate(sale.createdAt!)}'),
          ),
        for (final item in sale.items) ListTile(dense: true, title: Text(item)),
      ],
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

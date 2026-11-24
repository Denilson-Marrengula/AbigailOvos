import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../design/app_logo.dart';
import '../design/app_navigation_drawer.dart';
import '../design/overview_widgets.dart';
import '../seller/seller_controller.dart';
import '../seller/sales_page.dart';
import '../seller/seller_widgets.dart';
import '../seller/stock_page.dart';
import 'sales_report_pdf.dart';
import 'audit_page.dart';
import 'activity_report_page.dart';
import 'activity_report_pdf.dart' show reportCount;
import 'report_charts.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.auth, required this.session});
  final AuthService auth;
  final AuthSession session;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const _sections = [
    AppNavigationSection(
      label: 'Início',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    AppNavigationSection(
      label: 'Vendedores',
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge,
    ),
    AppNavigationSection(
      label: 'Stock',
      icon: Icons.warehouse_outlined,
      selectedIcon: Icons.warehouse,
    ),
    AppNavigationSection(
      label: 'Clientes',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    AppNavigationSection(
      label: 'Relatórios',
      icon: Icons.assessment_outlined,
      selectedIcon: Icons.assessment,
    ),
  ];

  int index = 0;
  bool leaving = false;
  bool loggingOut = false;
  late final SellerController stock;

  @override
  void initState() {
    super.initState();
    stock = SellerController(widget.auth)..addListener(_stockChanged);
  }

  void _stockChanged() {
    if (stock.sessionExpired) _expired();
  }

  @override
  void dispose() {
    stock.removeListener(_stockChanged);
    stock.dispose();
    super.dispose();
  }

  void _select(int selected) {
    if (selected == index) return;
    if (selected == 2) stock.refreshStock();
    setState(() => index = selected);
  }

  Future<void> _logout({String? notice}) async {
    if (loggingOut) return;
    loggingOut = true;
    leaving = true;
    String? warning;
    try {
      await widget.auth.logout();
    } catch (_) {
      warning = 'Saiu deste dispositivo, mas não foi possível confirmar o encerramento no servidor. A sessão expira automaticamente.';
    }
    if (!mounted) return;
    final message = [notice, warning].whereType<String>().join('\n');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          auth: widget.auth,
          notice: message.isEmpty ? null : message,
        ),
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
    drawer: AppNavigationDrawer(
      username: widget.session.username,
      role: 'Administrador',
      sections: _sections,
      selectedIndex: index,
      onSelected: _select,
      onLogout: _logout,
    ),
    appBar: AppBar(
      leading: const AppMenuButton(),
      title: Row(
        children: [
          const AppLogo(size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _sections[index].label,
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
    body: switch (index) {
      0 => AdminDashboardPage(
        auth: widget.auth,
        controller: stock,
        username: widget.session.username,
        onOpenTab: _select,
        onExpired: _expired,
      ),
      1 => SellersPage(auth: widget.auth, onExpired: _expired),
      2 => StockPage(controller: stock, onExpired: _expired, isAdmin: true),
      3 => AdminCustomersPage(auth: widget.auth, onExpired: _expired),
      _ => AdminReportsPage(auth: widget.auth, onExpired: _expired),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: _select,
      destinations: [for (final section in _sections) section.destination],
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

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    required this.auth,
    required this.controller,
    required this.username,
    required this.onOpenTab,
    required this.onExpired,
  });
  final AuthService auth;
  final SellerController controller;
  final String username;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onExpired;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<SalesReport> report;

  @override
  void initState() {
    super.initState();
    report = _fetch();
  }

  Future<SalesReport> _fetch() =>
      _guard(widget.auth.salesReport, widget.onExpired);

  Future<void> _refresh() async {
    final next = _fetch();
    setState(() => report = next);
    try {
      await next;
    } catch (_) {
      /* FutureBuilder apresenta o erro. */
    }
  }

  Future<void> _openPending(int initialTab) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Pedidos e pagamentos')),
          body: SalesPage(
            controller: widget.controller,
            isAdmin: true,
            onExpired: widget.onExpired,
            onNewSale: () {},
            initialTab: initialTab,
          ),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SalesReport>(
    future: report,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _loadFailure(snapshot.error, _refresh),
            OutlinedButton.icon(
              onPressed: () => _openPending(0),
              icon: const Icon(Icons.pending_actions_outlined),
              label: const Text('Ver pendências'),
            ),
          ],
        );
      }
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            OverviewHeader(
              username: widget.username,
              role: 'Administrador',
              description: 'Acompanhe as operações da equipa.',
            ),
            const SizedBox(height: 20),
            Text(
              'Visão geral',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Resumo de todas as operações registadas.'),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Pedidos pendentes'),
                subtitle: const Text('Por entregar. Toque para consultar.'),
                trailing: Text('${data.pendingOrders}'),
                onTap: () => _openPending(0),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('Vendas entregues'),
                subtitle: Text(formatMoney(data.deliveredAmount)),
                trailing: Text('${data.deliveredSales}'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Pagamento pendente'),
                subtitle: Text(formatMoney(data.pendingPaymentAmount)),
                trailing: Text('${data.pendingPayments}'),
                onTap: () => _openPending(1),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openPending(0),
              icon: const Icon(Icons.pending_actions_outlined),
              label: const Text('Ver pendências'),
            ),
            const Text(
              'Consulte Relatórios para os restantes dados e impressão.',
            ),
            const SizedBox(height: 24),
            Text(
              'Acesso rápido',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            OverviewActionTile(
              icon: Icons.badge_outlined,
              title: 'Vendedores',
              subtitle: 'Gerir contas e perfis',
              onTap: () => widget.onOpenTab(1),
            ),
            OverviewActionTile(
              icon: Icons.warehouse_outlined,
              title: 'Stock e preços',
              subtitle: 'Consultar produtos e quantidades',
              onTap: () => widget.onOpenTab(2),
            ),
            OverviewActionTile(
              icon: Icons.people_outline,
              title: 'Clientes',
              subtitle: 'Consultar clientes registados',
              onTap: () => widget.onOpenTab(3),
            ),
            OverviewActionTile(
              icon: Icons.assessment_outlined,
              title: 'Relatórios',
              subtitle: 'Consultar resultados e imprimir',
              onTap: () => widget.onOpenTab(4),
            ),
          ],
        ),
      );
    },
  );
}

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

  Future<void> _delete(SellerAccount seller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar vendedor?'),
        content: Text(
          'A conta ${seller.username} será apagada e não poderá voltar a iniciar sessão. As vendas e os movimentos de stock antigos mantêm a identificação do responsável. O nome de utilizador ficará reservado e não poderá ser reutilizado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar vendedor'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || changing) return;
    setState(() => changing = true);
    try {
      await _guard(() => widget.auth.deleteSeller(seller.id), widget.onExpired);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vendedor apagado. O histórico foi preservado.'),
          ),
        );
      }
    } on AuthException catch (e) {
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
        await _refresh();
        if (mounted) setState(() => changing = false);
      }
    }
  }

  Future<void> _resetPassword(SellerAccount seller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redefinir palavra-passe?'),
        content: Text(
          'Confirme a identidade de ${seller.username} antes de continuar. A palavra-passe atual deixará de funcionar. Será criada uma palavra-passe temporária válida por 24 horas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redefinir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || changing) return;
    setState(() => changing = true);
    try {
      final temporary = await _guard(
        () => widget.auth.resetSellerPassword(seller.id),
        widget.onExpired,
      );
      if (!mounted) return;
      final expiry = temporary.expiresAt.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Palavra-passe temporária'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Utilizador: ${seller.username}'),
                const SizedBox(height: 12),
                SelectableText(temporary.value),
                const SizedBox(height: 12),
                Text(
                  'Válida até ${two(expiry.day)}/${two(expiry.month)}/${expiry.year} às ${two(expiry.hour)}:${two(expiry.minute)} (hora do dispositivo).',
                ),
                const Text(
                  'Mostrada apenas agora. Entregue-a por um canal seguro e não partilhe capturas de ecrã. O vendedor deverá alterá-la no primeiro acesso.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.definitelyRejected
                  ? e.message
                  : '${e.message} A palavra-passe anterior pode ter sido invalidada; confirme a identidade e gere outra se necessário.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resultado desconhecido. A palavra-passe anterior pode ter sido invalidada; confirme a identidade e gere outra se necessário.',
            ),
          ),
        );
      }
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
                            } else if (value == 'status') {
                              _toggle(seller);
                            } else if (value == 'delete') {
                              _delete(seller);
                            } else if (value == 'password-reset') {
                              _resetPassword(seller);
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
                            if (seller.enabled)
                              const PopupMenuItem(
                                value: 'password-reset',
                                child: Text('Redefinir palavra-passe'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Apagar vendedor'),
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
                        ? 'Use de 3 a 100 letras, números, ponto, traço ou sublinhado.'
                        : null,
                  ),
                  TextFormField(
                    controller: password,
                    enabled: !saving,
                    obscureText: true,
                    maxLength: 72,
                    decoration: const InputDecoration(
                      labelText: 'Palavra-passe inicial',
                      helperText: 'De 12 a 72 caracteres. Temporária, válida por 24 horas.',
                    ),
                    validator: (v) =>
                        !RegExp(r'^[\x20-\x7E]{12,72}$').hasMatch(v ?? '') ||
                            (v ?? '').trim().isEmpty
                        ? 'Use de 12 a 72 caracteres ASCII imprimíveis.'
                        : null,
                  ),
                  const Text(
                    'O vendedor terá de alterar a palavra-passe no primeiro acesso.',
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
    this.printer,
  });
  final AuthService auth;
  final VoidCallback onExpired;
  final Future<bool> Function(SalesReport, DateTime)? printer;
  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  late Future<SalesReport> report;
  Future<List<SaleRecord>>? details;
  DateTimeRange? period;
  bool printing = false;
  @override
  void initState() {
    super.initState();
    report = _fetch();
  }

  Future<SalesReport> _fetch() => _guard(
    () => widget.auth.salesReport(from: period?.start, to: period?.end),
    widget.onExpired,
  );
  Future<List<SaleRecord>> _fetchDetails() => _guard(
    () async => (await widget.auth.searchSales(state: 'ALL')).items,
    widget.onExpired,
  );

  DateTime get _maputoToday {
    final now = DateTime.now().toUtc().add(const Duration(hours: 2));
    return DateTime(now.year, now.month, now.day);
  }

  void _period(DateTimeRange? value) {
    setState(() => period = value);
    _refresh();
  }

  Future<void> _choosePeriod() async {
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: period,
      helpText: 'Período dos eventos (Maputo)',
    );
    if (chosen != null && mounted) _period(chosen);
  }

  void _openAudit() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AuditPage(auth: widget.auth, onExpired: widget.onExpired),
    ),
  );

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

  Future<void> _print() async {
    if (printing) return;
    setState(() => printing = true);
    try {
      // Não imprimir a cópia possivelmente desatualizada apresentada no ecrã.
      final latest = await _fetch();
      if (!mounted) return;
      await (widget.printer ?? printSalesReport)(latest, DateTime.now());
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível preparar o relatório para impressão.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SalesReport>(
    future: report,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            Expanded(child: _loadFailure(snapshot.error, _refresh)),
            if (period != null)
              TextButton(
                onPressed: () => _period(null),
                child: const Text('Voltar ao histórico completo'),
              ),
            TextButton(
              onPressed: _openAudit,
              child: const Text('Histórico administrativo'),
            ),
          ],
        );
      }
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              data.periodStart == null
                  ? 'Todos os eventos registados.'
                  : 'Eventos de ${data.periodStart} a ${data.periodEnd}, horário de Maputo.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () {
                    final today = _maputoToday;
                    _period(DateTimeRange(start: today, end: today));
                  },
                  child: const Text('Hoje'),
                ),
                TextButton(
                  onPressed: () {
                    final today = _maputoToday;
                    _period(
                      DateTimeRange(
                        start: today.subtract(const Duration(days: 6)),
                        end: today,
                      ),
                    );
                  },
                  child: const Text('Últimos 7 dias'),
                ),
                TextButton(
                  onPressed: () {
                    final today = _maputoToday;
                    _period(
                      DateTimeRange(
                        start: DateTime(today.year, today.month),
                        end: today,
                      ),
                    );
                  },
                  child: const Text('Este mês'),
                ),
                TextButton(
                  onPressed: _choosePeriod,
                  child: const Text('Escolher período'),
                ),
                if (period != null)
                  TextButton(
                    onPressed: () => _period(null),
                    child: const Text('Todo o histórico'),
                  ),
              ],
            ),
            Text(
              data.eventDatesSupported
                  ? 'Eventos: data da entrega, marcação de pagamento ou cancelamento. Pendências: atuais, de todo o histórico.'
                  : 'Pendências: situação atual de todo o histórico.',
            ),
            if (!data.eventDatesSupported)
              const Text(
                'Este servidor não informa as datas dos eventos; atualize-o antes de consultar períodos.',
              )
            else if (data.unknownDeliveredDates +
                    data.unknownPaidDates +
                    data.unknownCancelledDates >
                0)
              Text(
                'Sem data no histórico: ${reportCount(data.unknownDeliveredDates, 'entrega', 'entregas')}, ${reportCount(data.unknownPaidDates, 'pagamento', 'pagamentos')} e ${reportCount(data.unknownCancelledDates, 'cancelamento', 'cancelamentos')}. ${data.periodStart == null ? 'Incluídos no histórico total.' : 'Excluídos dos totais do período.'}',
              ),
            OutlinedButton.icon(
              onPressed: _openAudit,
              icon: const Icon(Icons.history),
              label: const Text('Histórico administrativo'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivityReportPage(
                    auth: widget.auth,
                    onExpired: widget.onExpired,
                  ),
                ),
              ),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Relatórios semanais e mensais'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: printing ? null : _print,
              icon: const Icon(Icons.print_outlined),
              label: Text(
                printing ? 'A preparar...' : 'Imprimir relatório escrito',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pagamentos marcados não comprovam recebimento externo.',
            ),
            SalesReportCharts(report: data),
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(2),
              },
              children: [
                _summaryRow('Operação', 'Qtd.', 'Valor', heading: true),
                _summaryRow(
                  'Vendas entregues',
                  '${data.deliveredSales}',
                  formatMoney(data.deliveredAmount),
                ),
                _summaryRow(
                  'Marcado como pago',
                  '${data.markedPaid}',
                  formatMoney(data.markedPaidAmount),
                ),
                _summaryRow(
                  'Pagamentos pendentes',
                  '${data.pendingPayments}',
                  formatMoney(data.pendingPaymentAmount),
                ),
                _summaryRow(
                  'Pedidos pendentes',
                  '${data.pendingOrders}',
                  'Não aplicável',
                ),
                _summaryRow(
                  'Operações canceladas',
                  '${data.cancelledOperations}',
                  'Não aplicável',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const ExpansionTile(
              title: Text('Como ler o resumo'),
              childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Entregas e pagamentos são independentes.'),
                      Text(
                        'Pagamentos marcados podem incluir pedidos por entregar.',
                      ),
                      Text('Pagamentos pendentes incluem pedidos não pagos.'),
                      Text('Pendências são atuais e excluem cancelamentos.'),
                      Text(
                        'No relatório detalhado, dívida inclui apenas entregas não pagas de valor positivo.',
                      ),
                    ],
                  ),
                ),
              ],
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
            const Divider(),
            ExpansionTile(
              title: const Text('Operações registadas'),
              subtitle: const Text('Primeiras 20, sem filtro de período'),
              onExpansionChanged: (open) {
                if (open && details == null) {
                  setState(() {
                    details = _fetchDetails();
                  });
                }
              },
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _AdminOperationsPage(
                        auth: widget.auth,
                        onExpired: widget.onExpired,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar todas as operações'),
                ),
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

  TableRow _summaryRow(
    String label,
    String count,
    String amount, {
    bool heading = false,
  }) => TableRow(
    children: [
      for (final value in [label, count, amount])
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            value,
            style: heading
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
        ),
    ],
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
        if (sale.payment == 'PAID')
          ListTile(
            dense: true,
            title: Text(
              'Meio de pagamento: ${paymentMethodLabel(sale.paymentMethod)}',
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

class _AdminOperationsPage extends StatefulWidget {
  const _AdminOperationsPage({required this.auth, required this.onExpired});
  final AuthService auth;
  final VoidCallback onExpired;

  @override
  State<_AdminOperationsPage> createState() => _AdminOperationsPageState();
}

class _AdminOperationsPageState extends State<_AdminOperationsPage> {
  late final SellerController controller = SellerController(widget.auth);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pesquisar operações')),
    body: SalesPage(
      controller: controller,
      isAdmin: true,
      onExpired: widget.onExpired,
      onNewSale: () {},
      initialTab: 4,
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 2));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

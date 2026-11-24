import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../design/app_logo.dart';
import '../design/app_navigation_drawer.dart';
import 'customers_page.dart';
import 'home_page.dart';
import 'seller_controller.dart';
import 'sales_page.dart';
import 'stock_page.dart';

class SellerShell extends StatefulWidget {
  const SellerShell({super.key, required this.auth, required this.session});
  final AuthService auth;
  final AuthSession session;
  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  static const _sections = [
    AppNavigationSection(
      label: 'Início',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
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
      label: 'Vendas',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
  ];
  late final SellerController _controller;
  final _salesKey = GlobalKey<SalesPageState>();
  int _index = 0;
  bool _leaving = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _controller = SellerController(widget.auth)..addListener(_onChanged);
    _controller.refreshAll();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_controller.sessionExpired) _sessionExpired();
  }

  void _sessionExpired() {
    if (!_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _logout(notice: 'A sessão terminou. Inicie sessão novamente.');
        }
      });
    }
  }

  Future<void> _logout({String? notice}) async {
    if (_loggingOut) return;
    _loggingOut = true;
    _leaving = true;
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

  Future<void> _newSale() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SaleFormPage(controller: _controller, onExpired: _sessionExpired),
      ),
    );
    if (!mounted) return;
    if (saved == true) setState(() => _index = 3);
    await Future.wait([
      _controller.refreshAll(),
      if (_salesKey.currentState != null) _salesKey.currentState!.refresh(),
    ]);
  }

  void _selectTab(int index) {
    if (_index != index) setState(() => _index = index);
    if (index == 3) _salesKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppNavigationDrawer(
        username: widget.session.username,
        role: 'Vendedor',
        sections: _sections,
        selectedIndex: _index,
        onSelected: _selectTab,
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
                _sections[_index].label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Terminar sessão',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          SellerHomePage(
            controller: _controller,
            session: widget.session,
            onOpenTab: _selectTab,
            onNewSale: _newSale,
          ),
          StockPage(controller: _controller, onExpired: _sessionExpired),
          CustomersPage(controller: _controller, onNewCustomer: null),
          SalesPage(
            key: _salesKey,
            controller: _controller,
            isAdmin: widget.session.isAdmin,
            onExpired: _sessionExpired,
            onNewSale: _newSale,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: [for (final section in _sections) section.destination],
      ),
    );
  }
}

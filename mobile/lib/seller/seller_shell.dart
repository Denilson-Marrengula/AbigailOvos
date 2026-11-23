import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../design/app_logo.dart';
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
  static const _titles = ['Início', 'Stock', 'Clientes', 'Vendas'];
  late final SellerController _controller;
  final _salesKey = GlobalKey<SalesPageState>();
  int _index = 0;
  bool _leaving = false;

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

  void _logout({String? notice}) {
    widget.auth.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginPage(auth: widget.auth, notice: notice),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_titles[_index], overflow: TextOverflow.ellipsis),
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
            onOpenTab: (i) => setState(() => _index = i),
            onNewSale: _newSale,
          ),
          StockPage(controller: _controller),
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
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.warehouse_outlined),
            selectedIcon: Icon(Icons.warehouse),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Vendas',
          ),
        ],
      ),
    );
  }
}

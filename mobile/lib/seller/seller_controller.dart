import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';

/// Estado partilhado pelas páginas do vendedor (produtos, clientes e stock).
class SellerController extends ChangeNotifier {
  SellerController(this.auth);
  final AuthService auth;

  List<Product>? products;
  String? productsError;
  bool loadingProducts = false;

  List<Customer>? customers;
  String? customersError;
  bool loadingCustomers = false;

  Map<String, StockBalance> balances = const {};
  String? stockError;
  bool loadingStock = false;

  bool sessionExpired = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<T?> _guard<T>(
    Future<T> Function() action,
    void Function(String message) onError,
  ) async {
    try {
      return await action();
    } on AuthException catch (error) {
      if (error.sessionExpired) sessionExpired = true;
      onError(error.message);
    } catch (_) {
      onError('Não foi possível carregar os dados.');
    }
    return null;
  }

  Future<void> loadProducts() async {
    loadingProducts = true;
    productsError = null;
    notifyListeners();
    final result = await _guard(auth.products, (m) => productsError = m);
    products = result;
    loadingProducts = false;
    notifyListeners();
  }

  Future<void> loadCustomers() async {
    loadingCustomers = true;
    customersError = null;
    notifyListeners();
    final result = await _guard(auth.customers, (m) => customersError = m);
    customers = result == null ? null : _sorted(result);
    loadingCustomers = false;
    notifyListeners();
  }

  Future<void> loadStock() async {
    loadingStock = true;
    stockError = null;
    balances = const {};
    notifyListeners();
    final list = products ?? await _guard(auth.products, (m) => stockError = m);
    if (list != null) {
      products ??= list;
      final results = await _guard<List<StockBalance>>(
        () => Future.wait(list.map((p) => auth.stockBalance(p.id))),
        (m) => stockError = m,
      );
      if (results != null) {
        balances = {
          for (var i = 0; i < list.length; i++) list[i].id: results[i],
        };
      }
    }
    loadingStock = false;
    notifyListeners();
  }

  Future<void> refreshStock() async {
    await loadProducts();
    if (products != null) {
      await loadStock();
    } else {
      balances = const {};
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([loadProducts(), loadCustomers()]);
    if (products != null) {
      await loadStock();
    } else {
      balances = const {};
      notifyListeners();
    }
  }

  Future<void> createStockMovement(Map<String, dynamic> request) async {
    try {
      await auth.createStockMovement(request);
    } on AuthException catch (error) {
      if (error.sessionExpired) {
        sessionExpired = true;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Regista o cliente no servidor. Lança [AuthException] se falhar.
  Future<void> addCustomer(String name, String? phone) async {
    try {
      final created = await auth.createCustomer(name, phone);
      if (customers != null) customers = _sorted([...customers!, created]);
      notifyListeners();
      if (customers == null) await loadCustomers();
    } on AuthException catch (error) {
      if (error.sessionExpired) {
        sessionExpired = true;
        notifyListeners();
      }
      rethrow;
    }
  }

  List<Customer> _sorted(List<Customer> list) {
    final copy = [...list];
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }
}

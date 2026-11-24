import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

/// A list of the backend's existing, deliberately limited audit events.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.auth, required this.onExpired});
  final AuthService auth;
  final VoidCallback onExpired;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  static const _size = 30;
  int page = 0;
  late Future<List<AuditRecord>> events;

  @override
  void initState() {
    super.initState();
    events = _fetch();
  }

  Future<List<AuditRecord>> _fetch() async {
    try {
      return await widget.auth.auditEvents(page: page, size: _size);
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      rethrow;
    }
  }

  void _changePage(int next) => setState(() {
    page = next;
    events = _fetch();
  });

  String _date(DateTime value) {
    final maputo = value.toUtc().add(const Duration(hours: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(maputo.day)}/${two(maputo.month)}/${maputo.year} ${two(maputo.hour)}:${two(maputo.minute)}';
  }

  String _action(String code) => switch (code) {
    'SALE_CREATED' => 'Venda ou pedido registado',
    'SALE_DELIVERED' => 'Entrega registada',
    'SALE_CANCELLED' => 'Pedido cancelado',
    'SALE_MARKED_PAID' => 'Pagamento marcado',
    'STOCK_MOVEMENT_CREATED' => 'Movimento de stock',
    'PRODUCT_CREATED' => 'Produto criado',
    'PRODUCT_UPDATED' => 'Produto alterado',
    'PRODUCT_STATUS_SET' => 'Estado do produto alterado',
    'PRODUCT_MINIMUM_STOCK_SET' => 'Stock mínimo alterado',
    'CUSTOMER_CREATED' => 'Cliente criado',
    'CUSTOMER_UPDATED' => 'Cliente alterado',
    'SELLER_CREATED' => 'Vendedor criado',
    'SELLER_DELETED' => 'Vendedor eliminado',
    'SELLER_STATUS_SET' => 'Estado do vendedor alterado',
    'SELLER_PROFILE_UPDATED' => 'Perfil do vendedor alterado',
    'SELLER_PASSWORD_RESET' => 'Palavra-passe do vendedor redefinida',
    'PASSWORD_CHANGED' => 'Palavra-passe alterada',
    'LOGIN_SUCCEEDED' => 'Sessão iniciada',
    'LOGIN_FAILED' => 'Tentativa de acesso recusada',
    _ => code,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Histórico administrativo')),
    body: FutureBuilder<List<AuditRecord>>(
      future: events,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error is AuthException
                      ? (snapshot.error as AuthException).message
                      : 'Não foi possível carregar o histórico.',
                ),
                TextButton(
                  onPressed: () => _changePage(page),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }
        final rows = snapshot.data!;
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Horário de Maputo. Histórico não retroativo; não é completo nem inviolável. As páginas podem mudar.',
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Não há eventos nesta página.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final event = rows[index];
                        return Card(
                          child: ExpansionTile(
                            title: Text(_action(event.action)),
                            subtitle: Text(
                              '${_date(event.occurredAt)} · ${event.actor}',
                            ),
                            children: [
                              ListTile(
                                title: Text('Tipo: ${event.targetType}'),
                                subtitle: Text('Referência: ${event.targetId}'),
                              ),
                              ListTile(
                                title: Text(
                                  event.detail.isEmpty
                                      ? 'Sem detalhes adicionais'
                                      : event.detail,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: page == 0 ? null : () => _changePage(page - 1),
                  child: const Text('Anterior'),
                ),
                Text('Página ${page + 1}'),
                TextButton(
                  onPressed: rows.length < _size
                      ? null
                      : () => _changePage(page + 1),
                  child: const Text('Seguinte'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

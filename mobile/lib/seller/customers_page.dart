import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_service.dart';
import '../design/app_theme.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({
    super.key,
    required this.controller,
    required this.onNewCustomer,
  });
  final SellerController controller;
  final VoidCallback? onNewCustomer;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Customer customer, String query) {
    if (query.isEmpty) return true;
    if (customer.name.toLowerCase().contains(query)) return true;
    final digits = normalizePhone(query);
    final phone = normalizePhone(customer.phone);
    return digits != null && phone != null && phone.contains(digits);
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Número copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.onNewCustomer == null
          ? null
          : FloatingActionButton.extended(
              onPressed: widget.onNewCustomer,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Novo cliente'),
            ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final customers = controller.customers;
          if (customers == null) {
            if (controller.customersError == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: StateMessage(
                icon: Icons.cloud_off_outlined,
                message: controller.customersError!,
                actionLabel: 'Tentar novamente',
                onAction: controller.loadCustomers,
              ),
            );
          }
          final query = _query.trim().toLowerCase();
          final filtered = customers.where((c) => _matches(c, query)).toList();
          return Column(
            children: [
              SearchField(
                controller: _search,
                hint: 'Pesquisar por nome ou telefone',
                onChanged: (value) => setState(() => _query = value),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.loadCustomers,
                  child: filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            StateMessage(
                              icon: Icons.people_outline,
                              message: customers.isEmpty
                                  ? (widget.onNewCustomer == null
                                        ? 'Ainda não existem clientes.'
                                        : 'Ainda não existem clientes. Registe o primeiro.')
                                  : 'Nenhum cliente encontrado.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.medium,
                            AppSpacing.medium,
                            AppSpacing.medium,
                            96,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final customer = filtered[index];
                            final phone = customer.phone;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(_initial(customer.name)),
                                ),
                                title: Text(customer.name),
                                subtitle: Text(phone ?? 'Sem contacto'),
                                trailing: phone == null
                                    ? null
                                    : const Icon(Icons.copy_outlined, size: 20),
                                onTap: phone == null
                                    ? null
                                    : () => _copyPhone(phone),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CustomerFormPage extends StatefulWidget {
  const CustomerFormPage({super.key, required this.controller});
  final SellerController controller;
  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null; 
    final digits = normalizePhone(text);
    if (digits == null || digits.length < 8 || digits.length > 9) {
      return 'Número inválido. Ex.: 84 123 4567 ou +258 84 123 4567';
    }
    return null;
  }

  Customer? _duplicate(String name, String? phone) {
    final wanted = name.trim().toLowerCase();
    final digits = normalizePhone(phone);
    for (final customer in widget.controller.customers ?? const <Customer>[]) {
      if (customer.name.trim().toLowerCase() == wanted) return customer;
      if (digits != null && normalizePhone(customer.phone) == digits) {
        return customer;
      }
    }
    return null;
  }

  Future<bool> _confirmDuplicate(Customer existing) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Possível duplicado'),
        content: Text(
          'Já existe um cliente semelhante: ${existing.name}'
          '${existing.phone == null ? '' : ' (${existing.phone})'}. '
          'Quer registar mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registar'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final existing = _duplicate(name, phone);
    if (existing != null && !await _confirmDuplicate(existing)) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.addCustomer(name, phone);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível registar o cliente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Novo cliente')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [LengthLimitingTextInputFormatter(150)],
                  decoration: const InputDecoration(
                    labelText: 'Nome do cliente',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Introduza o nome do cliente.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.medium),
                TextFormField(
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    LengthLimitingTextInputFormatter(40),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefone (opcional)',
                    hintText: '84 123 4567',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePhone,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.large),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registar cliente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

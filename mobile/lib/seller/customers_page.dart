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

  Future<void> _edit(Customer customer) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CustomerFormPage(controller: widget.controller, customer: customer),
      ),
    );
    if (!mounted) return;
    // Uma resposta perdida também pode corresponder a uma alteração guardada.
    await widget.controller.loadCustomers();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cliente atualizado.')));
    }
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
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Opções do cliente ${customer.name}',
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _edit(customer);
                                    } else if (value == 'copy' &&
                                        phone != null) {
                                      _copyPhone(phone);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Editar cliente'),
                                    ),
                                    if (phone != null)
                                      const PopupMenuItem(
                                        value: 'copy',
                                        child: Text('Copiar telefone'),
                                      ),
                                  ],
                                ),
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
  const CustomerFormPage({super.key, required this.controller, this.customer});
  final SellerController controller;
  final Customer? customer;
  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  bool _confirming = false;
  bool _unknownResult = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = widget.customer?.name ?? '';
    _phone.text = widget.customer?.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (customerPhoneKey(value) != null) return null;
    return 'Telefone obrigatório e válido. Ex.: 84 123 4567 ou +258 84 123 4567';
  }

  Customer? _duplicateName(String name) {
    final wanted = name.trim().toLowerCase();
    for (final customer in widget.controller.customers ?? const <Customer>[]) {
      if (customer.id == widget.customer?.id) continue;
      if (customer.name.trim().toLowerCase() == wanted) return customer;
    }
    return null;
  }

  Customer? _duplicatePhone(String phone) {
    final key = customerPhoneKey(phone);
    if (key == null) return null;
    for (final customer in widget.controller.customers ?? const <Customer>[]) {
      if (customer.id != widget.customer?.id &&
          customerPhoneKey(customer.phone) == key) {
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
          '${widget.customer == null ? 'Quer registar mesmo assim?' : 'Quer guardar a alteração mesmo assim?'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.customer == null ? 'Registar' : 'Guardar'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    if (_saving ||
        _confirming ||
        _unknownResult ||
        !_form.currentState!.validate()) {
      return;
    }
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final phoneOwner = _duplicatePhone(phone);
    if (phoneOwner != null) {
      setState(
        () => _error =
            'Este telefone já está registado para ${phoneOwner.name}. Use outro número.',
      );
      return;
    }
    final existing = _duplicateName(name);
    if (existing != null) {
      setState(() => _confirming = true);
      final confirmed = await _confirmDuplicate(existing);
      if (!mounted) return;
      setState(() => _confirming = false);
      if (!confirmed) return;
    }
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.customer == null) {
        await widget.controller.addCustomer(name, phone);
      } else {
        await widget.controller.updateCustomer(
          widget.customer!.id,
          name,
          phone,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (error) {
      if (error.code == 'CUSTOMER_PHONE_EXISTS') {
        await widget.controller.loadCustomers();
      }
      if (mounted) {
        setState(() {
          _unknownResult = !error.definitelyRejected;
          _error = _unknownResult
              ? '${error.message} Resultado desconhecido. Volte à lista e verifique antes de repetir.'
              : error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknownResult = true;
          _error = 'Resultado desconhecido. Volte à lista e verifique antes de repetir.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.customer == null ? 'Novo cliente' : 'Editar cliente',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.customer != null) ...[
                  const Text(
                    'O nome atualizado será apresentado também nas vendas e pedidos anteriores.',
                  ),
                  const SizedBox(height: AppSpacing.medium),
                ],
                TextFormField(
                  controller: _name,
                  enabled: !_saving && !_confirming && !_unknownResult,
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
                  enabled: !_saving && !_confirming && !_unknownResult,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    if (widget.customer == null)
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                    LengthLimitingTextInputFormatter(40),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefone (obrigatório)',
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
                  onPressed: _saving || _confirming || _unknownResult
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          widget.customer == null
                              ? 'Registar cliente'
                              : 'Guardar alterações',
                        ),
                ),
                if (_unknownResult)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Voltar à lista'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

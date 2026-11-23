import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'seller_controller.dart';
import 'seller_widgets.dart';

class StockMovementPage extends StatefulWidget {
  const StockMovementPage({super.key, required this.controller});
  final SellerController controller;

  @override
  State<StockMovementPage> createState() => _StockMovementPageState();
}

class _StockMovementPageState extends State<StockMovementPage> {
  final form = GlobalKey<FormState>();
  final quantity = TextEditingController();
  final reason = TextEditingController();
  String? productId;
  String type = 'ENTRY';
  String adjustmentDirection = 'INCREASE';
  bool saving = false;
  bool confirming = false;
  String? error;
  Map<String, dynamic>? submitted;

  static const typeLabels = {
    'ENTRY': 'Entrada',
    'ADJUSTMENT': 'Ajuste',
    'LOSS': 'Perda',
    'BREAKAGE': 'Quebra',
  };

  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    super.dispose();
  }

  String get direction => type == 'ENTRY'
      ? 'INCREASE'
      : type == 'ADJUSTMENT'
      ? adjustmentDirection
      : 'DECREASE';

  Future<void> _save() async {
    if (saving || confirming) return;
    if (submitted == null) {
      if (!form.currentState!.validate()) return;
      final product = widget.controller.products!.firstWhere(
        (p) => p.id == productId,
      );
      final amount = quantity.text.trim().replaceAll(',', '.');
      setState(() => confirming = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar movimento'),
          content: Text(
            '${typeLabels[type]} · ${product.name}\n'
            '${direction == 'INCREASE' ? 'Aumentar' : 'Reduzir'}: $amount ${product.unit}\n'
            'Motivo: ${reason.text.trim()}',
          ),
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
      if (!mounted) return;
      setState(() => confirming = false);
      if (confirmed != true) return;
      submitted = {
        'operationId': createOperationId(),
        'productId': product.id,
        'type': type,
        'direction': direction,
        'quantity': amount,
        'reason': reason.text.trim(),
      };
    }

    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.createStockMovement(submitted!);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          if (e.definitelyRejected) submitted = null;
          error = e.definitelyRejected
              ? e.message
              : '${e.message}\nO resultado é desconhecido. Repita o mesmo envio; se sair, verifique o saldo antes de criar outro movimento.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Resultado desconhecido. Repita o mesmo envio; se sair, verifique o saldo antes de criar outro movimento.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = (widget.controller.products ?? const <Product>[])
        .where((p) => p.active)
        .toList();
    final locked = saving || confirming || submitted != null;
    final balance = productId == null
        ? null
        : widget.controller.balances[productId];
    return Scaffold(
      appBar: AppBar(title: const Text('Atualizar stock')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    decoration: const InputDecoration(
                      labelText: 'Item de stock',
                    ),
                    isExpanded: true,
                    items: products
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.name} · ${p.unit}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: locked
                        ? null
                        : (value) => setState(() => productId = value),
                    validator: (value) =>
                        value == null ? 'Selecione um item.' : null,
                  ),
                  if (balance != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Físico: ${formatQuantity(balance.physical)} · Reservado: ${formatQuantity(balance.reserved)} · Disponível: ${formatQuantity(balance.available)}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de movimento',
                    ),
                    items: typeLabels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: locked
                        ? null
                        : (value) {
                            if (value != null) setState(() => type = value);
                          },
                  ),
                  if (type == 'ADJUSTMENT') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: adjustmentDirection,
                      decoration: const InputDecoration(
                        labelText: 'Direção do ajuste',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'INCREASE',
                          child: Text('Aumentar stock'),
                        ),
                        DropdownMenuItem(
                          value: 'DECREASE',
                          child: Text('Reduzir stock'),
                        ),
                      ],
                      onChanged: locked
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => adjustmentDirection = value);
                              }
                            },
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: quantity,
                    enabled: !locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                    validator: (value) {
                      final raw = (value ?? '').trim().replaceAll(',', '.');
                      if (!RegExp(r'^\d{1,17}(\.\d{1,2})?$').hasMatch(raw) ||
                          (double.tryParse(raw) ?? 0) <= 0) {
                        return 'Indique uma quantidade positiva com até duas casas decimais.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: reason,
                    enabled: !locked,
                    maxLength: 255,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Indique o motivo.'
                        : null,
                  ),
                  const Text(
                    'O servidor verifica o stock disponível, incluindo as reservas dos pedidos.',
                  ),
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
                    onPressed: saving || confirming ? null : _save,
                    child: Text(
                      saving
                          ? 'A guardar...'
                          : submitted == null
                          ? 'Rever movimento'
                          : 'Repetir envio',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

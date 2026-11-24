import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

/// Os preços são enviados como texto decimal, sem conversão para ponto flutuante.
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({
    super.key,
    required this.auth,
    required this.onExpired,
    this.product,
  });

  final AuthService auth;
  final VoidCallback onExpired;
  final Product? product;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController unit;
  late final TextEditingController price;
  bool saving = false;
  bool unknownResult = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.product?.name ?? '');
    unit = TextEditingController(text: widget.product?.unit ?? '');
    price = TextEditingController(text: widget.product?.price ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    unit.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || unknownResult || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final decimal = price.text.trim().replaceAll(',', '.');
      if (widget.product == null) {
        await widget.auth.createProduct(
          name.text.trim(),
          unit.text.trim(),
          decimal,
        );
      } else {
        await widget.auth.updateProduct(
          widget.product!.id,
          name.text.trim(),
          unit.text.trim(),
          decimal,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (e.sessionExpired) widget.onExpired();
      if (mounted) {
        setState(() {
          unknownResult = !e.definitelyRejected;
          error = unknownResult
              ? '${e.message} O resultado é desconhecido. Volte à lista e verifique antes de repetir.'
              : e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          unknownResult = true;
          error = 'Resultado desconhecido. Volte à lista e verifique antes de repetir.';
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.product == null ? 'Novo produto' : 'Editar produto'),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.product == null)
              const Text(
                'O produto começa sem stock. Registe depois uma entrada na área do vendedor.',
              ),
            TextFormField(
              controller: name,
              enabled: !saving && !unknownResult,
              maxLength: 150,
              decoration: const InputDecoration(labelText: 'Nome do produto'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Introduza o nome.'
                  : null,
            ),
            TextFormField(
              controller: unit,
              enabled: !saving && !unknownResult && widget.product == null,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: 'Unidade',
                helperText: widget.product == null
                    ? 'Por exemplo, bandeja ou unidade.'
                    : 'A unidade não pode ser alterada nesta tela.',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Introduza a unidade.'
                  : null,
            ),
            TextFormField(
              controller: price,
              enabled: !saving && !unknownResult,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Preço em MT',
                helperText: 'Até duas casas decimais.',
              ),
              validator: (value) =>
                  RegExp(r'^\d{1,17}([.,]\d{1,2})?$')
                      .hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Introduza um preço válido, por exemplo 100,50.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving || unknownResult ? null : _save,
              child: Text(saving ? 'A guardar...' : 'Guardar'),
            ),
            if (unknownResult)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar à lista'),
              ),
          ],
        ),
      ),
    ),
  );
}

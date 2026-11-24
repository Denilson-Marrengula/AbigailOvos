import 'package:flutter/material.dart';

import 'auth_service.dart';

/// Temporary credentials never enter either application shell.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  bool saving = false;
  bool unknown = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || unknown || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.auth.changePassword(current.text, next.text);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        unknown = e.sessionExpired || !e.definitelyRejected;
        error = unknown
            ? 'Não foi possível confirmar a alteração. Volte ao início e tente entrar com a nova palavra-passe. Se necessário, peça outra ao administrador.'
            : e.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          unknown = true;
          error = 'Resultado desconhecido. Volte ao início e tente entrar com a nova palavra-passe.';
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alterar palavra-passe')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Antes de continuar, substitua a palavra-passe temporária.',
              ),
              TextFormField(
                controller: current,
                enabled: !saving && !unknown,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Palavra-passe temporária',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Introduza a palavra-passe temporária.'
                    : null,
              ),
              TextFormField(
                controller: next,
                enabled: !saving && !unknown,
                obscureText: true,
                maxLength: 72,
                decoration: const InputDecoration(
                  labelText: 'Nova palavra-passe',
                  helperText: 'De 12 a 72 caracteres ASCII imprimíveis.',
                ),
                validator: (value) {
                  if (!RegExp(r'^[\x20-\x7E]{12,72}$').hasMatch(value ?? '') ||
                      (value ?? '').trim().isEmpty) {
                    return 'Use de 12 a 72 caracteres ASCII imprimíveis.';
                  }
                  return value == current.text
                      ? 'Escolha uma palavra-passe diferente.'
                      : null;
                },
              ),
              TextFormField(
                controller: confirmation,
                enabled: !saving && !unknown,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nova palavra-passe',
                ),
                validator: (value) => value == next.text
                    ? null
                    : 'As palavras-passe não coincidem.',
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
                onPressed: saving || unknown ? null : _save,
                child: const Text('Alterar palavra-passe'),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('Voltar ao início'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

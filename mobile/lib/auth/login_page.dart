import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/app_logo.dart';
import '../seller/seller_shell.dart';
import '../admin/admin_shell.dart';
import 'auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth, this.notice});
  final AuthService auth;

  final String? notice;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.auth.login(
        _username.text.trim(),
        _password.text,
      );
      _password.clear();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => session.isAdmin
              ? AdminShell(auth: widget.auth, session: session)
              : SellerShell(auth: widget.auth, session: session),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível iniciar sessão.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AbigailOvos')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 112)),
                    const SizedBox(height: AppSpacing.large),
                    Text(
                      'Iniciar sessão',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Text('Aceda com a sua conta AbigailOvos.'),
                    if (widget.notice != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      Text(
                        widget.notice!,
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.large),
                    TextFormField(
                      controller: _username,
                      enabled: !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Utilizador',
                        border: OutlineInputBorder(),
                      ),
                      autofillHints: const [AutofillHints.username],
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Introduza o utilizador.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    TextFormField(
                      controller: _password,
                      enabled: !_loading,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Palavra-passe',
                        border: OutlineInputBorder(),
                      ),
                      autofillHints: const [AutofillHints.password],
                      validator: (value) => value == null || value.isEmpty
                          ? 'Introduza a palavra-passe.'
                          : null,
                      onFieldSubmitted: (_) => _login(),
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
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

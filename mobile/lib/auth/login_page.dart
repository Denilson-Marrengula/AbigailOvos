import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/app_logo.dart';
import '../legal/legal_draft_page.dart';
import '../seller/seller_shell.dart';
import '../admin/admin_shell.dart';
import 'auth_service.dart';
import 'change_password_page.dart';

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
  String? _notice;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    final auth = widget.auth;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final session = await auth.login(_username.text.trim(), _password.text);
      if (!mounted) {
        try {
          await auth.logout();
        } catch (_) {
          // The server session can remain valid until expiry if revocation fails.
        }
        return;
      }
      _password.clear();
      if (session.mustChangePassword) {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => ChangePasswordPage(auth: auth)),
        );
        String? warning;
        try {
          await auth.logout();
        } catch (_) {
          warning = 'Não foi possível confirmar o encerramento no servidor. A sessão expira automaticamente.';
        }
        if (mounted) {
          setState(
            () => _notice =
                warning ??
                (changed == true
                    ? 'Palavra-passe alterada. Inicie sessão novamente.'
                    : null),
          );
        }
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => session.isAdmin
              ? AdminShell(auth: auth, session: session)
              : SellerShell(auth: auth, session: session),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível iniciar sessão.');
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _loading = false);
      }
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
                    if (_notice != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      Text(
                        _notice!,
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
                      textInputAction: TextInputAction.next,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Introduza a palavra-passe.'
                          : null,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).nextFocus(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.medium),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: AppSpacing.medium),
                      const Text(
                        'A ligar ao servidor. A resposta pode demorar um pouco.',
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
                    const SizedBox(height: AppSpacing.medium),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LegalDraftPage(
                                document: LegalDocument.privacy,
                              ),
                            ),
                          ),
                          child: const Text('Política de privacidade'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LegalDraftPage(
                                document: LegalDocument.terms,
                              ),
                            ),
                          ),
                          child: const Text('Termos e condições'),
                        ),
                      ],
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

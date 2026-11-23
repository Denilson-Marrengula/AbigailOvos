import 'package:flutter/material.dart';

import 'design/app_theme.dart';
import 'design/info_panel.dart';
import 'auth/auth_service.dart';
import 'auth/login_page.dart';

void main() => runApp(const AbigailOvosApp());

class AbigailOvosApp extends StatelessWidget {
  const AbigailOvosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AbigailOvos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.create(Brightness.light),
      darkTheme: AppTheme.create(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        if (!const bool.fromEnvironment('ISOLATED_TEST')) {
          return child ?? const SizedBox.shrink();
        }
        return Column(
          children: [
            Material(
              color: Colors.amber.shade700,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      'AMBIENTE DE TESTE — NÃO USAR DADOS REAIS',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: LoginPage(
        notice: const bool.fromEnvironment('ISOLATED_TEST')
            ? 'Base isolada de teste: não introduza dados reais.'
            : null,
        auth: HttpAuthService(
          const String.fromEnvironment('API_BASE_URL'),
          developmentCertificate: const String.fromEnvironment(
            'DEV_CERT_PEM_BASE64',
          ),
        ),
      ),
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.large),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.egg_alt_outlined,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.medium),
                      Expanded(
                        child: Text(
                          'AbigailOvos',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'GESTÃO COMERCIAL',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    'Bem-vindo ao AbigailOvos',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.medium),
                  Text(
                    'Uma aplicação para administradores e vendedores.',
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.extraLarge),
                  const InfoPanel(
                    icon: Icons.construction_rounded,
                    title: 'Em desenvolvimento',
                    description:
                        'O acesso seguro e a ligação ao servidor ainda estão a ser preparados. '
                        'Não utilize esta versão para operações reais.',
                  ),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    'Produtos · Clientes · Stock',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

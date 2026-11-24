import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/app_theme.dart';
import 'design/info_panel.dart';
import 'auth/auth_service.dart';
import 'auth/login_page.dart';

void main() => runApp(const AbigailOvosApp());

class AbigailOvosApp extends StatefulWidget {
  const AbigailOvosApp({super.key});

  @override
  State<AbigailOvosApp> createState() => _AbigailOvosAppState();
}

class _AbigailOvosAppState extends State<AbigailOvosApp> {
  late final AuthService auth;
  late final Timer splashTimer;
  bool starting = true;

  @override
  void initState() {
    super.initState();
    auth = HttpAuthService(
      const String.fromEnvironment('API_BASE_URL'),
      developmentCertificate: const String.fromEnvironment(
        'DEV_CERT_PEM_BASE64',
      ),
    );
    splashTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => starting = false);
    });
  }

  @override
  void dispose() {
    splashTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AbigailOvos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.create(Brightness.light),
      darkTheme: AppTheme.create(Brightness.dark),
      themeMode: ThemeMode.system,
      home: starting ? const StartupScreen() : LoginPage(auth: auth),
    );
  }
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: AppColors.forest,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.forest,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      backgroundColor: AppColors.forest,
      body: Center(
        child: Image.asset(
          'assets/splash_egg.png',
          width: 240,
          height: 240,
          semanticLabel: 'AbigailOvos',
        ),
      ),
    ),
  );
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

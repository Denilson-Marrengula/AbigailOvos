import 'package:flutter/material.dart';

import '../design/app_theme.dart';

enum LegalDocument { privacy, terms }

class LegalDraftPage extends StatelessWidget {
  const LegalDraftPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    final title = privacy ? 'Política de privacidade' : 'Termos e condições';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.large),
          children: [
            Text('Texto em preparação', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.small),
            const Text(
              'Este documento é um rascunho. Não é uma versão final nem substitui a revisão jurídica antes do lançamento.',
            ),
            const SizedBox(height: AppSpacing.large),
            if (privacy) ...[
              Text(
                'Informações na aplicação',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'A aplicação foi concebida para registar contas de utilizadores, clientes, vendas, pedidos e movimentos de stock.',
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                'Informações por definir',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'Antes da publicação, é necessário identificar o responsável e o contacto de privacidade, confirmar as finalidades e os tipos de dados, os prestadores envolvidos, os prazos de conservação e os direitos aplicáveis.',
              ),
            ] else ...[
              Text('Estado do serviço', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'As condições de utilização estão em preparação e ainda não foram aprovadas.',
              ),
              const SizedBox(height: AppSpacing.large),
              Text('Condições por definir', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.small),
              const Text(
                'Antes da publicação, é necessário identificar o responsável pelo serviço e definir as condições de acesso e utilização, o contacto de suporte e as demais condições aplicáveis.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

# Critérios para lançamento

## Apresentação

- Usar botões de cantos discretamente arredondados, sem formato de pílula.
- Não incluir avaliações, depoimentos, métricas ou contadores inventados. Resumos operacionais devem ser obtidos de dados reais e indicar quando não estão disponíveis.
- Não usar emojis como ícones, travessões no texto da interface, animações excessivas, fotografias artificiais apresentadas como reais ou etiquetas de aplicação feita com IA.
- Usar a identidade e o favicon AbigailOvos. Não adicionar imagens ou alegações comerciais sem confirmação.

## Domínio e proteção

- Não lançar em produção antes de ligar um domínio próprio controlado pelo responsável. O endereço `railway.app` existente é exclusivamente para testes com dados fictícios e não é um domínio de lançamento.
- Configurar e verificar DNS, certificado HTTPS válido, renovação e ligação da aplicação ao domínio final. Testar autenticação, permissões, cópias de segurança e recuperação antes de usar dados reais.
- Validar operacionalmente a recuperação segura do administrador e as sessões revogáveis. Por decisão do responsável, não haverá segundo fator; proteger palavras-passe e rever os riscos de credenciais comprometidas. A recuperação de vendedores e a migração V11 passaram em testes locais, mas falta validação no dispositivo e na infraestrutura; HTTP Basic continua provisório.
- Implementar e ensaiar cópias diárias cifradas no disco próprio escolhido, alertas e restauro independente; definir retenção e proteção de chaves. A existência de uma exportação ou uma cópia anterior não comprova que a recuperação funciona.
- Validar TiDB Cloud para migrações, transações, restrições e concorrência de stock; preparar a configuração de TLS e limites de confiança do Render. Não assumir equivalência completa com MySQL ou com o Railway de teste.
- Validar a regra de telefone obrigatório e único, incluindo concorrência e reconciliação de clientes anteriores; não aplicar a V12 nem fundir dados sem cópia restaurada e plano aprovado. Ver [duplicados-clientes.md](duplicados-clientes.md).
- Gerar e proteger uma chave de assinatura Android própria e validar a distribuição e recuperação da chave. APKs assinados com a chave de depuração são apenas para testes. A configuração local de release ainda não foi validada: ver [assinatura-android.md](assinatura-android.md).
- O projeto atual é uma aplicação Mobile; a pré-visualização no navegador não está adaptada para login nem é um site de produção. Um eventual site público requer definição de âmbito e validação própria.

## Documentos legais

- As páginas de política de privacidade e termos incluídas na aplicação são **rascunhos visivelmente identificados**. Não publicar nem apresentar como documentos legais finais.
- Antes do lançamento, confirmar a identidade e o contacto do responsável, a jurisdição e legislação aplicáveis, os dados tratados, finalidades, prestadores, eventuais transferências, períodos de conservação e procedimentos para direitos e pedidos de privacidade.
- Definir as condições de acesso, utilização e suporte e obter revisão jurídica apropriada. Não assumir requisitos legais, prazos ou garantias que não tenham sido confirmados.

## Verificação final

- Validar as telas em Android, com diferentes tamanhos e acessibilidade. A estrutura iOS ainda precisa de compilação e teste num Mac e num dispositivo.
- Validar o fluxo autenticado completo no ambiente adequado, sem dados reais enquanto a segurança e o restauro não estiverem concluídos.
- Confirmar que as versões distribuídas contêm as alterações aprovadas. O APK instalado anteriormente não é atualizado automaticamente pelas alterações de código.

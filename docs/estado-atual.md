# Estado de desenvolvimento

## Mobile

- O vendedor tem uma tela inicial com acesso direto a uma nova venda, stock, clientes e operações. Os números são obtidos da última consulta ao servidor e não são simulados.
- A tela de stock reúne os itens, preços e quantidades físicas, reservadas e disponíveis. O vendedor pode solicitar entradas, ajustes, perdas e quebras, com motivo e confirmação.
- O cliente é selecionado ou registado durante uma venda ou pedido; a interface alerta sobre possíveis duplicados, mas a deteção não é uma garantia de unicidade.
- O administrador tem telas próprias para criar, listar, editar, desativar e reativar vendedores, consultar clientes e ver um resumo de operações. A classificação de clientes ativos ainda não foi definida ou implementada.
- O relatório administrativo obtém totais decimais agregados no servidor: operações entregues, pagamentos marcados e pendentes e desempenho dos vendedores. Cancelamentos são contados à parte; marcar como pago não comprova recebimento externo. Os detalhes são carregados a pedido, ainda sem paginação ou filtro por período.
- O logótipo fornecido está em `mobile/assets/logo.png` e no ícone Android. O ficheiro original tinha extensão `.svg`, mas continha dados PNG.

## Integridade e segurança

- O servidor valida permissões, quantidade, preço, tipo de movimento e stock disponível. O stock reservado não pode ser consumido por um movimento que deixaria o disponível negativo.
- Vendas e movimentos de stock usam identificadores de operação para permitir reenvio idêntico sem duplicação. O Mobile mantém esses identificadores apenas enquanto o formulário estiver aberto; após interrupção deve verificar o servidor antes de criar outra operação.
- Os preços e quantidades são enviados como texto decimal e validados pelo servidor, que calcula o total. O valor exibido antes da confirmação é indicativo.
- A divisão de permissões ainda não está completa: a API continua a permitir ao administrador gerir o catálogo de produtos, embora o papel desejado seja mais restrito. É necessário definir quem mantém o catálogo antes de retirar essa capacidade.
- HTTP Basic sobre HTTPS é provisório. Faltam proteção contra tentativas abusivas, recuperação de acesso, auditoria completa e avaliação de segurança. Não usar a aplicação para operações reais.

## Validação e dados

- Foi preparada uma configuração Docker Compose para testes isolados num servidor Linux em `deploy/staging/`: MySQL sem porta publicada e API HTTPS ligada apenas ao loopback. Ainda não foi executada ou validada com Docker, nem existe servidor remoto configurado. Ver as condições e limitações em `deploy/staging/README.md`.
- Em 09/11/2026 passaram 41 testes Maven, 18 testes Flutter e `flutter analyze`. A interface foi também testada com ecrã estreito e texto ampliado; os testes Flutter usam serviços simulados.
- Cenários HTTPS/MySQL isolados verificaram vendas, reservas, movimentos, permissões e reenvios simultâneos. São testes pontuais, não uma garantia para todas as situações de concorrência ou recuperação.
- A base habitual permanece na versão V4. V5–V7 foram testadas apenas em bases isoladas, incluindo uma cópia restaurada da base habitual. A cópia de segurança e as bases restauradas contêm dados sensíveis e não foram eliminadas. Ver [validacao-vendas.md](validacao-vendas.md).
- Foi gerado o APK debug `mobile/build/app/outputs/flutter-apk/app-debug.apk` como **AbigailOvos Teste**, com identificador Android separado, ligado à base isolada com dados fictícios. A versão instalada anteriormente no telefone não inclui as alterações mais recentes de início, stock e relatórios; a atualização ainda não foi instalada nem validada no dispositivo, que não foi detetado.
- A operação offline, pagamentos integrados, reembolsos, devoluções e relatórios financeiros completos continuam por implementar.

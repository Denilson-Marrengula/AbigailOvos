# Validação de vendas — 8 de novembro de 2026

## Resultados

- V1–V7 foram aplicadas numa base MySQL 8.4.13 nova e isolada. O Hibernate validou o esquema.
- Foi criada uma cópia de segurança da base de desenvolvimento em `C:\Users\HP\development\abigailovos-backups\`, com acesso ao ficheiro restringido ao utilizador local. O ficheiro foi restaurado numa base isolada e as tabelas verificadas por checksum antes da atualização.
- Numa segunda cópia restaurada com a mesma codificação e ordenação da base de origem, as migrações V5–V7 foram aplicadas. Os campos anteriores de contas e produtos e os dados de clientes e movimentos foram comparados com a origem; a base original permaneceu em V4.
- O teste HTTPS com MySQL isolado verificou autenticação, CSRF, criação, repetição do pedido com o mesmo identificador, reserva, stock insuficiente, entrega, pagamento, cancelamento e permissões. Num teste com dois pedidos simultâneos para uma unidade disponível, um foi aceite e o outro recusado.
- Um teste adicional enviou simultaneamente a mesma operação duas vezes: as duas respostas referiram a mesma venda, sem duplicar o cliente ou a reserva. A gestão de vendedores foi testada com HTTPS e MySQL isolado para criação com perfil, edição, desativação, reativação e negação de acesso a vendedor.
- No MySQL isolado foram testados movimentos de stock pelo vendedor, recusa ao administrador, respeito pelas reservas, impedimento de saldo negativo e reenvio simultâneo do mesmo movimento sem duplicação. A coluna histórica `administrator` continua a guardar o utilizador responsável.
- Em 09/11/2026, um teste HTTPS/MySQL isolado confirmou que vendedor não acede ao relatório e que uma venda entregue e paga e um pedido pendente alteram corretamente os totais decimais e o desempenho por vendedor. Testes H2 adicionais cobrem cancelados, relatório vazio, valores elevados e acesso não autenticado.
- Em 09/11/2026 a migração V8 de auditoria foi aplicada à base MySQL isolada de testes de vendas, anteriormente em V7; o Flyway e o Hibernate validaram o esquema. A base habitual não foi migrada. Em H2 testaram-se o controlo de acesso à auditoria, a ausência de segredos no retorno, reenvios sem duplicação e reversão da operação quando a auditoria falha. Um teste HTTPS/MySQL isolado confirmou a gravação de eventos de criação de vendedor, vendas e stock e a recusa de consulta ao vendedor.
- Os testes Flutter e a análise estática passaram. Estes testes usam serviços simulados e **não** substituem o teste no dispositivo.

## Limites e cuidados

- A primeira tentativa de migração de uma cópia falhou porque a base de destino foi criada com ordenação diferente da origem. Foi preservada e não foi reparada; a experiência foi repetida numa nova cópia com a mesma configuração da base original. Ao restaurar, verificar a codificação e ordenação da base e das colunas relacionadas por chaves estrangeiras.
- A versão do Flyway em uso avisa que o MySQL 8.4 é mais recente do que as versões oficialmente testadas por essa versão do Flyway. É necessária avaliação antes de produção.
- As duas bases restauradas contêm cópias de dados da base habitual. O utilizador do servidor de testes isolado não tem acesso a elas; não foram apagadas. A cópia de segurança também contém dados sensíveis e deve ser protegida.
- O teste concorrente cobriu apenas um cenário; são necessários mais testes de carga, falhas e recuperação. A autenticação, auditoria, devoluções, reembolsos, pagamentos parciais e sincronização offline não estão prontas para produção.
- A versão de testes do APK usa uma base diferente e dados fictícios. Não introduzir dados reais. Uma versão anterior foi instalada no telemóvel; as alterações recentes da tela inicial, do stock e dos relatórios ainda precisam de validação no dispositivo.
- Antes de aplicar qualquer migração na base habitual: obter autorização, impedir alterações durante o procedimento, criar nova cópia de segurança, testar o restauro, confirmar as versões e ordenações, definir recuperação e validar os dados após a operação.
    

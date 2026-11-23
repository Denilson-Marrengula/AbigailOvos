# Primeira fase: base do AbigailOvos

## Objetivo e âmbito

Preparar a base de uma única aplicação Mobile para administradores e vendedores: autenticação, permissões, produtos, clientes e stock central. A aplicação e o backend devem respeitar as permissões de cada utilizador.

Uma primeira implementação online de vendas e pedidos está em desenvolvimento e ainda requer validação integrada. A sincronização offline completa, os relatórios e o dashboard ficam para fases posteriores. A base deve, no entanto, ser concebida tendo em conta a futura utilização offline e a sincronização.

## Tecnologias e dados existentes

- Backend e API: Java 21 e Spring Boot. Uma única aplicação Mobile em Flutter para ambos os perfis; não está prevista aplicação Web.
- MySQL para a base de dados central e SQLite para armazenamento local no Mobile, com vista ao funcionamento offline.
- Foi confirmado que ainda não existe uma base de dados anterior para migrar. As regras seguintes aplicam-se caso venham a existir dados a preservar.
- A nova implementação deve preservar os clientes, produtos, pedidos e registos de stock existentes. Antes de qualquer migração, identificar a origem e a estrutura dos dados, criar e verificar uma cópia de segurança e definir um plano de migração e recuperação.
- Usar migrações de esquema versionadas e controladas; testar a migração e a recuperação numa cópia dos dados, verificar quantidades e integridade dos registos e só depois aplicar em produção. Não eliminar nem substituir dados anteriores sem validação e autorização.

## Preparação para sincronização

- Usar identificadores UUID para os registos que possam ser criados ou sincronizados entre dispositivos, incluindo os criados offline.
- Registar datas de criação e atualização, com uma convenção de fuso horário consistente. As datas do dispositivo não devem, por si só, determinar a resolução de conflitos.
- Conceber operações de sincronização para serem idempotentes: o reenvio da mesma operação não deve criar duplicados. Definir e guardar um identificador estável para cada operação sincronizada.
- A implementação completa da fila, sincronização e resolução de conflitos fica para uma fase posterior; os seus detalhes continuam por definir.

## Utilizadores e acesso

- **Administrador:** a regra pretendida é consultar relatórios e clientes ativos e gerir vendedores. A definição de cliente ativo ainda está pendente.
- **Vendedor:** consulta stock, preços e clientes, regista movimentos de stock e cria vendas ou pedidos, podendo criar um cliente durante a operação.
- A configuração de permissões existente ainda não implementa integralmente a divisão solicitada: o backend continua a permitir ao administrador gerir produtos; é preciso definir quem mantém esse catálogo sem interromper a operação.
- Cada utilizador deve autenticar-se e ter permissões adequadas ao seu perfil. As restrições de acesso devem ser verificadas pelo sistema, não apenas escondendo opções na interface.
- As operações relevantes devem poder ser associadas ao utilizador responsável, preparando a futura auditoria.

### Segurança de acesso

- A API deve autenticar os pedidos protegidos e validar as permissões em cada endpoint, incluindo o acesso aos recursos individuais; a interface não é uma fronteira de segurança.
- Guardar palavras-passe apenas como hashes produzidos por um algoritmo apropriado para palavras-passe, nunca em texto simples. Definir e validar uma política de comprimento e de escolha de palavras-passe, sem registar as palavras-passe em logs.
- A recuperação de acesso deve confirmar a identidade do utilizador e usar um mecanismo de utilização única e validade limitada, sem revelar se uma conta existe.
- Prever bloqueio ou limitação temporária após tentativas de autenticação falhadas, com procedimento de recuperação e registo do evento. Os limites e a duração ainda precisam de definição.
- Proteger as comunicações e os dados sensíveis, incluindo os guardados localmente no dispositivo. O método concreto de autenticação e o tratamento de sessões e dispositivos ainda precisam de definição.

## Produtos

- O administrador pode manter o cadastro de produtos disponíveis para venda.
- O vendedor pode consultar os produtos autorizados para a sua operação.
- O cadastro deverá permitir identificar o produto, a unidade de venda e o preço. As unidades concretas e eventuais conversões ainda precisam de confirmação.

## Clientes

- Vendedores registam novos clientes durante a criação de uma venda ou pedido; administradores e vendedores podem consultá-los. O estado ativo dos clientes e as respetivas regras precisam de definição.
- Todos os vendedores podem consultar o cadastro completo de clientes.
- O cadastro deve identificar o cliente e permitir guardar os contactos necessários à operação. Os campos obrigatórios e as regras para detetar clientes duplicados ainda precisam de definição.

## Stock central

- Existe um stock central partilhado por todos os vendedores.
- O vendedor pode registar movimentos de entrada, ajuste, perda e quebra. Cada movimento regista o tipo, produto, quantidade, motivo, data e utilizador responsável; os ajustes indicam se aumentam ou diminuem o stock. O administrador consulta o histórico.
- O saldo deve ser consistente com os movimentos registados. Correções devem ser rastreáveis, preservando o histórico em vez de apagar movimentos anteriores.
- Ajustes, perdas e quebras não podem deixar o saldo negativo; o movimento deve ser rejeitado quando não houver stock suficiente.
- Uma venda imediata confirmada atualiza o stock. Um pedido guardado é confirmado e reserva stock transaccionalmente; um formulário ainda não enviado não reserva. O cancelamento de pedido não pago liberta a reserva e a entrega não deve duplicar a saída física.
- Vendas offline sem stock suficiente devem permanecer em conflito, sem confirmação automática nem stock negativo, até resolução administrativa auditável.

## Critérios de aceitação iniciais

1. Um utilizador autenticado só consegue aceder às funcionalidades permitidas pelo seu perfil; um vendedor não acede à gestão administrativa de vendedores.
2. O administrador consegue gerir vendedores e consultar clientes e relatórios. A classificação de clientes ativos ainda precisa de definição.
3. O vendedor consegue consultar produtos e clientes e criar clientes durante uma venda ou pedido no Mobile.
4. O stock apresentado corresponde ao stock central partilhado, e as alterações podem ser rastreadas ao responsável.
5. A primeira versão de vendas é online; sincronização offline e pagamentos integrados não são pressupostos.
6. Uma migração dos dados existentes só é aplicada após cópia de segurança verificada, teste de recuperação e validação dos dados migrados.
7. A API impede operações não autorizadas; a recuperação de acesso e a proteção contra tentativas falhadas respeitam as regras de segurança definidas acima.
8. Cada entrada, ajuste, perda ou quebra de stock fica associada ao produto, quantidade, motivo, data e utilizador responsável.

## Decisões pendentes

- Dados obrigatórios de vendedores, clientes e produtos; política de ativação e desativação de utilizadores e produtos.
- Método de autenticação e gestão de sessões e dispositivos; parâmetros concretos da política de palavras-passe e do bloqueio de contas.
- Unidades de venda, conversões, preços e eventual controlo de lotes e validade.
- Regras detalhadas dos movimentos de stock, incluindo quantidades permitidas e tratamento de saldo insuficiente.
- Que dados e operações da primeira fase devem estar disponíveis offline, e como resolver duplicações ou alterações concorrentes na sincronização.
- Procedimento detalhado de resolução administrativa de conflitos e tratamento de preços alterados enquanto o dispositivo está offline.
- Infraestrutura, mecanismos concretos de proteção dos dados e requisitos de implantação.

# AbigailOvos

O projeto está em desenvolvimento. Os requisitos e as decisões pendentes estão em [docs/primeira-fase.md](docs/primeira-fase.md); o estado, os testes e as lacunas estão em [docs/estado-atual.md](docs/estado-atual.md) e [docs/diagnostico-tecnico.md](docs/diagnostico-tecnico.md).

Para preparar um servidor Linux de **testes isolados**, consultar [deploy/staging/README.md](deploy/staging/README.md). A configuração ainda não foi validada com Docker, não publica a base de dados e não abre a API à internet; não serve para produção ou dados reais.

## Backend

Requisitos: JDK 21 e Maven 3. O projeto Maven encontra-se em `backend/`.

```powershell
cd backend
mvn test
```

Para executar um teste específico: `mvn -Dtest=AbigailOvosApplicationTest test`.

Neste ambiente o JDK 21 está em `C:\Program Files\Java\jdk-21.0.12.1`, mas o Java predefinido pode ser outra versão. Para executar os testes com o JDK 21 sem alterar a configuração global do Windows:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21.0.12.1'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
mvn test
```

O backend está em desenvolvimento: existem APIs iniciais para produtos, clientes, vendas, pedidos, movimentos de stock e contas persistidas com BCrypt. Há um procedimento inicial para o primeiro administrador; recuperação de acesso e proteção contra tentativas abusivas ainda faltam. A configuração atual não está preparada para produção. A aplicação Mobile Flutter, única para administradores e vendedores, tem áreas distintas para os dois perfis; a aplicação Web foi substituída.

### Base de dados e API de produtos

O arranque do backend requer `DB_URL`, `DB_USERNAME` e `DB_PASSWORD`. As migrações Flyway estão desativadas por defeito; `DB_MIGRATIONS_ENABLED=true` permite aplicá-las a uma base nova e dedicada. Não aplicar migrações a uma base existente sem antes avaliar o esquema e verificar a cópia de segurança. Existem migrações V1–V7. Em 08/11/2026, V1–V7 foram testadas numa base MySQL nova e V5–V7 numa cópia restaurada da base de desenvolvimento; a base original continuou em V4. Consultar [a validação de vendas](docs/validacao-vendas.md) e não tratar o teste isolado como validação de produção.

Neste ambiente existe um serviço XAMPP MariaDB 10.4 chamado `mysql`; isso não confirma que um servidor MySQL esteja disponível nem que as credenciais e uma base de teste isolada estejam configuradas. Não alterar bases existentes para testar.

Foi criada separadamente uma instância MySQL 8.4.13 de desenvolvimento, acessível apenas em `127.0.0.1:3307`, com a base `abigailovos`. Os binários estão em `C:\Users\HP\development\mysql-8.4.13-winx64`, os dados em `C:\Users\HP\development\abigailovos-mysql-data` e as credenciais locais em `C:\Users\HP\development\abigailovos-mysql-credentials.txt`. Não partilhar nem adicionar esse ficheiro ao repositório. A instância foi iniciada como processo, não como serviço Windows, pelo que terá de ser reiniciada após o encerramento do processo ou do computador.

Os endpoints de produtos incluem `GET /api/products`, `GET /api/products/{id}`, `POST /api/products`, `PUT /api/products/{id}` e `PATCH /api/products/{id}/status` (`{"active":true}` ou `false`). As leituras exigem perfil `ADMIN` ou `SELLER`; alterações exigem `ADMIN`. Vendedores não veem produtos inativos; administradores podem reativá-los. `GET /api/me` devolve o perfil autenticado; `GET` e `POST /api/users` permitem ao administrador listar contas e criar vendedores. A proteção CSRF do Spring está ativa e HTTP Basic requer TLS; não expor esta configuração temporária em produção.

`PATCH /api/users/{id}/status`, com `{"enabled":false}` ou `{"enabled":true}`, permite ao administrador desativar ou reativar vendedores; não permite alterar o estado de administradores. A implementação atual usa HTTP Basic e não implementa tokens ou revogação de sessões offline.

`POST /api/users` aceita nome (`displayName`) e telefone opcionais no mesmo pedido de criação de vendedor; `PUT /api/users/{id}/profile` permite ao administrador editar esses dados. A política de estado ativo dos clientes ainda não está definida.

### Primeiro administrador (procedimento inicial)

Depois de configurar a base dedicada e verificar as migrações, pode executar o backend uma única vez em modo não Web com `SPRING_MAIN_WEB_APPLICATION_TYPE=none`, `ABIGAIL_BOOTSTRAP_ENABLED=true`, `ABIGAIL_BOOTSTRAP_USERNAME` e `ABIGAIL_BOOTSTRAP_PASSWORD`, além das variáveis `DB_*` habituais. Opcionalmente, `ABIGAIL_BOOTSTRAP_SELLER_USERNAME` e `ABIGAIL_BOOTSTRAP_SELLER_PASSWORD` criam um vendedor na mesma transacção. O nome aceita 3–100 caracteres ASCII de letras, números, ponto, traço e sublinhado; a palavra-passe deve ter 12–72 caracteres ASCII imprimíveis. O procedimento recusa qualquer base que já contenha contas. Execute apenas uma instância durante a inicialização; o processo não foi concebido para inicializações concorrentes. Remova as variáveis de inicialização após o uso e não coloque segredos no código, em argumentos de linha de comandos ou no histórico do terminal. Esta funcionalidade não substitui a configuração de segurança de produção.

Para operações que alteram dados, o cliente autenticado deve obter `GET /api/csrf`, preservar o cookie de sessão e enviar o valor `token` no cabeçalho indicado por `headerName`, junto com a autenticação. O Mobile implementa este fluxo para vendas, mas ainda necessita de teste ponta a ponta no dispositivo. A autenticação HTTP Basic só deve ser usada com HTTPS verificado, incluindo na ligação do dispositivo ao servidor.

Os endpoints `GET /api/customers` e `GET /api/customers/{id}` permitem leitura por `ADMIN` e `SELLER`. O cliente novo é registado na mesma transação da venda ou pedido; a criação isolada está bloqueada. Nome é obrigatório e telefone é opcional; regras de duplicação e sincronização continuam pendentes.

`GET /api/stock/{productId}` consulta saldo físico (`quantity`), reservado (`reserved`) e disponível (`available`). `POST /api/stock/movements` permite ao vendedor registar entrada, ajuste, perda ou quebra; o administrador consulta o histórico em `GET /api/stock/{productId}/movements`. O pedido exige `operationId` UUID, `productId`, `type`, `direction`, `quantity` e `reason`. Reenviar o mesmo identificador e os mesmos dados não duplica o movimento; reutilizá-lo com outros dados é recusado. O nome do utilizador autenticado é guardado na coluna histórica `administrator`, apesar do nome da coluna. O identificador de reenvio é mantido no formulário apenas enquanto estiver aberto; se a aplicação fechar após uma falha de comunicação, verificar o stock antes de lançar outro movimento. O saldo disponível não pode ficar negativo.

### Vendas e pedidos em desenvolvimento

`GET /api/sales` lista operações; vendedores criam por `POST /api/sales` e usam `PATCH /api/sales/{id}/deliver`, `/cancel` e `/pay`. A criação exige UUID estável, cliente existente ou dados de novo cliente, itens com quantidades e preços esperados, e estados iniciais de entrega e pagamento. O backend valida preço e disponibilidade, calcula o total e guarda os preços históricos. Pedidos pendentes reservam stock; entrega regista saída e cancelamento liberta reserva. O mesmo UUID com o mesmo pedido pode ser reenviado sem criar outra venda. Os pedidos pagos não podem ser cancelados até existir um processo de reembolso; devoluções, pagamentos parciais e retificações não estão implementados. A segurança, histórico completo de auditoria, concorrência e migração no MySQL ainda exigem validação. O identificador de reenvio é mantido apenas enquanto o formulário está aberto; após interrupção deve consultar a lista antes de repetir uma operação.

`GET /api/reports/sales` é exclusivo do administrador e agrega no servidor os estados e valores, com montantes decimais em texto. Os cancelados são contados separadamente e excluídos dos valores de pagamento; os valores entregues são independentes do pagamento. O total marcado como pago inclui pedidos ainda não entregues e não comprova recebimentos externos. O desempenho por vendedor inclui apenas operações entregues. Não há filtros por período; a consulta dos detalhes é opcional e ainda carrega todas as operações, sem paginação.

Não apontar ferramentas de migração para a base de dados anterior até que a sua origem e estrutura sejam identificadas e exista uma cópia de segurança verificada e um plano de recuperação.

## Mobile

Em `mobile/`, executar `flutter test` e `flutter analyze`. O login consulta `/api/me` com HTTP Basic exclusivamente sobre HTTPS com certificado válido; configurar o endereço com `flutter run --dart-define=API_BASE_URL=https://servidor.example/`. Sem esta configuração o login apresenta erro. A tela de stock reúne preços e quantidades e permite ao vendedor registar movimentos; não existe uma página de produtos separada. O formulário de venda permite selecionar ou registar cliente, informar produtos, entrega e pagamento. A área administrativa permite gerir vendedores e consultar clientes e resumo de operações; a classificação de clientes ativos ainda não foi implementada. As alterações recentes ainda precisam de validação no telemóvel. A credencial é mantida em memória e descartada ao sair. Ainda não há recuperação de acesso, sessão persistente, sincronização offline ou segurança pronta para produção. Não usar para operações reais.

A tela inicial do vendedor oferece acesso direto a uma nova venda, stock, clientes e operações, além de um resumo da última consulta. Os números são obtidos do servidor e mostram `—` quando indisponíveis; não existem dados de demonstração inseridos na interface.

O logótipo está em `mobile/assets/logo.png` e é usado no login, nas áreas dos dois perfis e no ícone Android. O ficheiro fornecido com extensão `.svg` tinha, na realidade, conteúdo PNG; a cópia preserva os dados originais sem acrescentar dependências de SVG.

Para testes neste computador foi criado um certificado local de curta duração em `C:\Users\HP\development\abigailovos-tls-dev`; a chave e a palavra-passe são privadas e não devem ser partilhadas. O backend de teste pode usar HTTPS em `127.0.0.1:8443`; no emulador o endereço correspondente é `https://10.0.2.2:8443/`. Num telemóvel ligado por USB, `adb reverse tcp:8443 tcp:8443` permite usar `https://127.0.0.1:8443/`. Em builds **debug**, `DEV_CERT_PEM_BASE64` permite confiar no certificado público PEM local apenas nesses endereços; nunca inclui a chave privada e não é aceite em release. O certificado não é uma configuração de produção e expira ao fim de 90 dias.

Para instalar uma segunda aplicação de teste sem substituir a habitual, o build debug suporta `--android-project-arg=isolatedTest=true`, que usa o identificador `com.abigailovos.abigailovos.teste` e o nome **AbigailOvos Teste**. O aviso no login é ativado com `--dart-define=ISOLATED_TEST=true`. A instância isolada local foi configurada em `https://127.0.0.1:18443/`; no telemóvel é necessário `adb reverse tcp:18443 tcp:18443` e o certificado público de desenvolvimento. Esta versão contém dados fictícios e não deve ser usada para dados reais.

O perfil Spring `production` exige terminação TLS directa com `TLS_KEYSTORE_PATH` (por exemplo `file:/caminho/servidor.p12`) e `TLS_KEYSTORE_PASSWORD`, ativa TLS 1.2/1.3, cookies seguros e a exigência de HTTPS. Use um certificado de entidade confiável que corresponda ao domínio, proteja a chave privada e configure a renovação. Não abra uma porta HTTP para clientes: redirecionar um pedido HTTP não protege credenciais já enviadas. O perfil não confia em cabeçalhos de proxy; uma implantação atrás de proxy precisa de configuração e validação específicas antes de alterar isso. Não usar o certificado local de teste em produção.

O perfil TLS não torna o sistema pronto para produção: HTTP Basic ainda exige revisão, e faltam bloqueio de tentativas, recuperação de acesso, gestão de sessões e testes de segurança e integração.

O projeto Android gerado usa atualmente a chave de depuração também para o build `release`. Não distribuir nem publicar esse artefacto: antes da publicação é necessário configurar uma chave de assinatura própria e protegida, além de concluir e testar o sistema.

# Configuração do Render: implementada, não publicada

**Estado: código e Blueprint prontos, sem serviço Render criado e sem segredos reais.** O perfil `render` foi acrescentado ao backend e os testes locais passaram. Foi criado `render.yaml` na raiz com os valores não secretos e `sync: false` para os segredos. Nada foi publicado, nenhuma variável com valor real foi introduzida e a conta de execução TiDB continua por criar/validar. O perfil `production` mantém-se próprio para TLS direto e **não** deve ser usado no Render.

**Decisão do responsável (24/11/2026):** o Web Service apontará para `abigailovos_tidb_test_4292b79106cb4fac`, que passa a ser a base do piloto. Não serão executados nela ensaios de escrita, migrações automáticas nem criação de administrador. O esquema, as contas, a cópia e o restauro exigem procedimento separado e autorização específica.

Render termina TLS no balanceador e encaminha HTTP ao serviço na porta `PORT` (por omissão `10000`). Por isso o perfil `render` não ativa `server.ssl.*` e não usa `requiresChannel().requiresSecure()`; em substituição, recusa pedidos que não chegaram através da borda HTTPS.

## 1. O que ficou implementado

| Ficheiro | Efeito |
| --- | --- |
| `backend/src/main/resources/application-render.properties` | Escuta em `0.0.0.0:${PORT:10000}`, `server.forward-headers-strategy=none`, sessões obrigatórias, cookies `Secure`/`HttpOnly`/`SameSite=Strict`, origem pública e confirmação da borda sem valores permissivos por omissão. |
| `backend/src/main/java/com/abigailovos/security/RenderSecurityGuard.java` | Guarda de arranque falha-fechada do perfil `render`. Recusa arranque sem sessões, com HTTPS direto, sem confirmação da borda, com origem pública inválida, com `DB_URL` insegura/incompleta, com migrações/bootstrap ativados ou sem `ABIGAIL_AUTH_ORIGIN_KEY` válida (32 bytes em Base64 canónico). Mensagens não incluem segredos. |
| `backend/src/main/java/com/abigailovos/security/RenderEdgeFilter.java` | Recusa HTTP direto ao contentor e qualquer `X-Forwarded-Proto` que não seja um único valor `https`. Cabeçalhos repetidos ou com valores em vírgula são ambíguos e recusados. O cabeçalho é apenas sinal de recusa: não é usado para confiar na origem do cliente nem para modificar `request.isSecure()`. |
| `backend/src/main/java/com/abigailovos/security/RenderEdgeConfiguration.java` | Regista o filtro antes da cadeia Spring Security, apenas no perfil `render`. |
| `backend/src/main/java/com/abigailovos/health/HealthController.java` | `GET /api/health` responde `200` com `ok`, `Cache-Control: no-store`, sem dados da base ou configuração. |
| `backend/src/main/java/com/abigailovos/security/SecurityConfiguration.java` | `/api/health` em `permitAll`; continua sem Basic no modo sessões. |
| `backend/src/main/java/com/abigailovos/security/LoginOriginFilter.java` | Health check não consome o balde por origem, para não esgotar o limite dos utilizadores. |
| `backend/Dockerfile` | `PORT=10000`, `EXPOSE 10000 8443`. O `SERVER_PORT=8443` do Compose de staging continua a prevalecer nesse ambiente. |
| `render.yaml` | Blueprint com `runtime: docker`, `rootDir: backend`, health check `/api/health`, deploy manual e segredos em `sync: false`. |

O limite por origem continua a usar `request.getRemoteAddr()`, como no railway-test. Atrás do Render isso pode significar que todos os utilizadores partilham o mesmo endereço de entrada e, por isso, o mesmo balde; não foi adotada nenhuma resolução de `X-Forwarded-For` sem validação da cadeia real do fornecedor. Ver [proxy-render.md](proxy-render.md).

## 2. Checklist para a consola do Render

Não executar estes passos sem a conta do responsável, decisão de plano e autorização para publicar. Não partilhar valores de segredos na conversa, em ficheiros versionados, argumentos ou logs.

1. **Criar Web Service** a partir do repositório, com `backend` como diretório de contextos/Dockerfile e o ramo escolhido. Não reutilizar o serviço Railway nem o perfil `railway-test`.
2. **Região e plano**: decidir antes de criar. O plano Free pode adormecer e os tempos do Mobile são limitados; ver o limite descrito em [README.md](README.md). Confirmar franquia, faturação e alertas.
3. **Variáveis de ambiente** (todas na consola Render, como segredos quando aplicável):

   | Nome | Valor esperado |
   | --- | --- |
   | `SPRING_PROFILES_ACTIVE` | `render` |
   | `ABIGAIL_RENDER_PUBLIC_ORIGIN` | `https://<nome-do-serviço>.onrender.com` ou o domínio próprio exato, sem caminho, utilizador, consulta ou fragmento |
   | `ABIGAIL_RENDER_EDGE_CONFIRMED` | `true` apenas depois de confirmada a terminação TLS e o redirecionamento HTTP→HTTPS na borda do Render |
   | `ABIGAIL_AUTH_ORIGIN_KEY` | 32 bytes aleatórios em Base64 canónico, gerados e guardados pelo responsável fora do repositório |
   | `DB_URL` | `jdbc:mysql://<host>:<porta>/<base>?sslMode=VERIFY_IDENTITY`, sem utilizador nem palavra-passe na cadeia e sem `allowPublicKeyRetrieval=true` |
   | `DB_USERNAME` | Conta de execução com menos privilégios, distinta da conta administrativa e da conta de migrações |
   | `DB_PASSWORD` | Segredo exclusivo da conta de execução |
   | `DB_MIGRATIONS_ENABLED` | `false` |
   | `ABIGAIL_BOOTSTRAP_ENABLED` | `false` |
   | `PORT` | `10000`, ou deixar o valor por omissão do Render |

   Não definir `TLS_KEYSTORE_PATH`, `TLS_KEYSTORE_PASSWORD`, `SPRING_PROFILES_ACTIVE=production`, Basic nem `SERVER_PORT=8443` neste serviço. A ausência de qualquer variável obrigatória faz a aplicação falhar no arranque — não alterar a guarda para a fazer arrancar.

   Ao aplicar o Blueprint, o Render pede os valores `sync: false`. Em `DB_URL`, indicar a cadeia `jdbc:mysql://<host>:<porta>/abigailovos_tidb_test_4292b79106cb4fac?sslMode=VERIFY_IDENTITY`, sem credenciais na URL.

4. **Health check**: configurar o caminho `/api/health` no serviço. Não usar `/api/csrf`, porque consome o limite por origem.
5. **Rede TiDB**: confirmar a regra de entrada para as faixas de saída da região Render escolhida. A regra atual do computador não cobre a aplicação alojada. Não alargar regras existentes sem confirmação.
6. **Domínio**: opcional para o piloto interno. Se for usado, o valor de `ABIGAIL_RENDER_PUBLIC_ORIGIN` tem de ser o domínio final exato.

## 3. Validação depois do primeiro deploy

1. Os logs mostram arranque normal e nenhuma variável secreta.
2. `GET /api/health` devolve `200 ok` e não consome o limite de login.
3. Um HTTP público é redirecionado para HTTPS antes de responder; um pedido direto ao contentor sem `X-Forwarded-Proto: https` recebe `403`.
4. Um `X-Forwarded-Proto` repetido, vazio ou com vírgula é recusado quando chega diretamente ao contentor.
5. `GET /api/csrf` e o comportamento da sessão mostram cookies com `Secure`, `HttpOnly` e `SameSite=Strict`. Não executar login nem escritas de ensaio na base do piloto; login e operações reais ficam para depois da cópia/restauro e de autorização específica.
6. A conta de execução não consegue aplicar migrações nem criar o primeiro administrador.
7. Não ensaiar falha da base, concorrência no limitador nem escritas nessa base. Confirmar apenas plano, região, alertas e comportamento do serviço sem alterar dados. Se algum controlo falhar, parar e corrigir; não baixar a guarda.

## 4. O que este ficheiro não faz

Não cria serviços, não gera chaves, não altera regras TiDB, não publica, não valida a cadeia de cabeçalhos real do Render, não substitui o ensaio de restauro nem autoriza dados reais.

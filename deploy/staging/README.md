# Preparação de servidor de testes isolado

Esta configuração é uma **preparação, ainda não validada num servidor Docker**. É apenas para dados e contas fictícios, não para produção. O MySQL fica numa rede interna, sem porta publicada; a API HTTPS escuta somente em `127.0.0.1:18443` do servidor. O acesso remoto de teste deve ser feito por túnel SSH, apenas por pessoas autorizadas. Não abrir esta porta à internet nem usar encaminhamento público enquanto a autenticação, proteção contra abuso e auditoria não estiverem concluídas.

## Pré-requisitos

- Servidor Linux dedicado a testes, atualizado, com acesso SSH restrito, firewall, Docker Engine e Docker Compose plugin; o daemon Docker e os seus administradores têm acesso aos segredos e dados dos contentores.
- Copiar o projeto para o servidor. Em seguida executar os comandos abaixo a partir da pasta `deploy/staging` no servidor. Não copiar a base habitual nem credenciais existentes.
- Criar um ficheiro PKCS12 **de teste** com certificado, chave privada e palavra-passe. O certificado deve corresponder ao nome usado pelo cliente. Não incluir chave privada ou palavra-passe no projeto. O UID 10001 do contentor tem de conseguir ler o ficheiro; restringir também o acesso no servidor.
- Em ambiente público real será necessário um domínio e certificado válidos, além das outras medidas de segurança. Um certificado de teste não deve ser adicionado às autoridades de confiança do dispositivo para produção.

## Configuração inicial

1. Criar `.env` privado a partir de `.env.example` (`umask 077; cp .env.example .env` e `chmod 600 .env`). Preencher as três palavras-passe com valores **diferentes**, longos e aleatórios, e `STAGING_TLS_KEYSTORE` com o caminho absoluto do PKCS12 no servidor. Para evitar problemas de interpretação pelo Compose, usar por exemplo valores hexadecimais gerados independentemente com `openssl rand -hex 32`. Não enviar o ficheiro a outras pessoas nem guardá-lo no código.
2. Confirmar que o caminho e o acesso ao PKCS12 estão corretos. A configuração nunca inclui a chave no build da imagem. O conteúdo de `.env` e as variáveis dos contentores são sensíveis; não publicar saídas de `docker compose config`, inspeções, ficheiros de configuração ou relatórios de diagnóstico que as exponham.
3. Criar e aguardar a base dedicada:

   ```sh
   docker compose up -d --wait db
   docker compose build api
   ```

   O volume `staging_mysql` é persistente e não contém dados automaticamente até à inicialização. O utilizador MySQL da aplicação tem acesso à base de testes; o MySQL não publica porta no anfitrião. Não reutilizar um volume de outra instalação. Alterar palavras-passe em `.env` posteriormente **não** altera automaticamente contas já existentes no MySQL.

4. **Uma única vez e apenas numa base nova e vazia**, executar migrações e criar o primeiro administrador fictício. A inicialização recusa bases que já contenham contas. Os nomes aceitam 3–100 caracteres ASCII de letras, números, ponto, traço ou sublinhado; a palavra-passe aceita 12–72 caracteres ASCII imprimíveis. Usar credenciais exclusivas de teste.

   ```bash
   read -r -p 'Nome do administrador de teste: ' ABIGAIL_BOOTSTRAP_USERNAME
   read -r -s -p 'Palavra-passe de teste: ' ABIGAIL_BOOTSTRAP_PASSWORD; printf '\n'
   export ABIGAIL_BOOTSTRAP_USERNAME ABIGAIL_BOOTSTRAP_PASSWORD
   docker compose run --rm --no-deps \
     -e SPRING_MAIN_WEB_APPLICATION_TYPE=none \
     -e DB_MIGRATIONS_ENABLED=true \
     -e ABIGAIL_BOOTSTRAP_ENABLED=true \
     -e ABIGAIL_BOOTSTRAP_USERNAME -e ABIGAIL_BOOTSTRAP_PASSWORD api
   unset ABIGAIL_BOOTSTRAP_USERNAME ABIGAIL_BOOTSTRAP_PASSWORD
   ```

   Verificar o sucesso antes de continuar. Não repetir para tentar reparar falhas nem iniciar várias instâncias ao mesmo tempo. Caso a migração falhe, investigar e preservar o volume; o Flyway pode ter aplicado parte das alterações. Migrações futuras exigem avaliação, cópia de segurança e ensaio de restauro. O arranque normal mantém `DB_MIGRATIONS_ENABLED=false`.

5. Iniciar a API: `docker compose up -d api`. Confirmar o estado com `docker compose ps` e verificar os registos sem divulgar dados ou segredos. O servidor valida o esquema existente, usa TLS direto e não confia em cabeçalhos de proxy.

## Verificação remota sem exposição pública

No computador autorizado, criar um túnel SSH mantendo-o aberto:

```sh
ssh -N -L 18443:127.0.0.1:18443 utilizador@servidor-de-teste
```

Usar um cliente que valide o certificado e o nome nele contido. Por exemplo, para um certificado de teste com nome `api.staging.test`, copiar **apenas o certificado público** ao computador autorizado e executar:

```sh
curl --cacert certificado-publico.pem --resolve api.staging.test:18443:127.0.0.1 https://api.staging.test:18443/api/me
```

Sem credenciais, uma resposta HTTP 401 indica que a aplicação respondeu; não demonstra que o login ou as operações funcionam. Não usar `--insecure`, não enviar credenciais sobre HTTP e não divulgar o certificado privado. Os controlos de firewall e a acessibilidade devem ser verificados a partir do exterior do servidor; o túnel não substitui a gestão de acesso SSH.

O APK debug atual foi configurado para o certificado e endereço locais de outro ambiente. **Não está configurado nem validado para este servidor.** Será necessário um build de teste apropriado e, para um domínio público, um certificado válido; testar o acesso do telefone antes de qualquer distribuição.

## Dados, paragem e limitações

- `docker compose stop` para os serviços sem eliminar o volume. Não usar `docker compose down -v`, `docker volume rm` ou recriar a base se existir informação a preservar.
- O volume persistente não é uma cópia de segurança. Antes de usar qualquer dado importante, definir cópias externas cifradas, retenção, controlo de acesso e ensaios de restauro. Este ambiente deve conter somente dados fictícios.
- As imagens de base usam tags de versão e não estão fixadas por digest; devem ser revistas, atualizadas e testadas antes de qualquer implantação. Ainda não foram feitos testes de carga, restauro, exposição, segurança ou integração do contentor nesta configuração.
- Não usar este ambiente para operações reais: faltam, entre outras medidas, proteção contra tentativas abusivas, recuperação de acesso e auditoria completa.

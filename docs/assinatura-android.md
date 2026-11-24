# Preparação da assinatura Android

O projeto deixou de configurar a chave de depuração como assinatura de `release`. A configuração local de release requer um keystore e credenciais fornecidos externamente; a compilação de depuração para testes continua separada. **A alteração não foi compilada nem testada, não foi gerada nenhuma chave e não existe um APK de lançamento aprovado.**

## Antes de gerar uma chave

- Definir quem é responsável, se a distribuição será direta ou por uma loja, a identidade da aplicação e como guardar e recuperar a chave ao longo de toda a vida da aplicação. Se for utilizada uma loja, avaliar separadamente a chave de upload e a assinatura gerida pela loja.
- Gerar uma chave própria apenas após confirmação do responsável, num ambiente seguro e sem palavras-passe em argumentos, código, histórico do terminal ou capturas. Guardar o keystore fora do repositório e proteger as cópias e a recuperação em local separado. As regras `.gitignore` ajudam, mas não protegem ficheiros já rastreados, cópias ou logs.
- Perder a chave pode impedir futuras atualizações. Android não permite normalmente atualizar uma aplicação já instalada com outra assinatura. O APK de teste `.teste` usa a chave debug e não é uma versão de produção; antes de qualquer substituição, identificar aplicação, assinatura e dados no dispositivo. Não desinstalar uma aplicação existente nem apagar os seus dados para contornar um erro de assinatura sem plano, cópia verificada e autorização.

## Configuração prevista

O Gradle lê `ABIGAIL_ANDROID_KEYSTORE_PATH`, `ABIGAIL_ANDROID_KEYSTORE_PASSWORD`, `ABIGAIL_ANDROID_KEY_ALIAS` e `ABIGAIL_ANDROID_KEY_PASSWORD` do ambiente do processo de compilação. As quatro têm de estar preenchidas, o ficheiro tem de existir e não pode ser o `debug.keystore` usual nem usar o alias `androiddebugkey`. Esta verificação simples não comprova que uma chave renomeada seja segura: é preciso conferir o certificado real.

O nome das variáveis não é um convite para incluir segredos num ficheiro versionado ou no histórico. Definir um meio seguro de fornecê-los ao processo, com acesso mínimo; variáveis de ambiente também podem ser expostas a processos e diagnósticos do mesmo utilizador. Não adicionar o keystore nem as senhas ao APK, ao repositório ou aos documentos do projeto.

Após implementar os restantes controlos e com autorização, testar uma compilação release em ambiente isolado, confirmar que falha sem credenciais, verificar certificado e impressões digitais do APK com ferramenta Android apropriada e comparar com a chave aprovada. Depois validar instalação e atualizações num dispositivo de teste, sem remover aplicações ou dados existentes. O build e o lançamento só podem ser considerados após todos os critérios de [requisitos-lancamento.md](requisitos-lancamento.md).

## Verificação preparada do APK

Foi preparado `deploy/verificar-apk.ps1` para conferir a assinatura de um APK **já compilado**, usando `apksigner` do Android SDK. Não gera chaves, não assina, não publica e não contacta a nuvem. Foi ensaiado apenas com o APK de depuração existente: detetou o certificado `Android Debug` e recusou-o no modo de lançamento; não foi usado com uma chave própria, que ainda não existe.

- Inspeção sem aprovação (para registar o certificado): executar o script com `-Apk <caminho>\app-release.apk -InspectOnly`. Mostra o signatário e a impressão digital SHA-256, mas não confirma a chave aprovada.
- Bloqueio de lançamento: o operador fornece `-ExpectedFingerprintSha256` com o valor registado **fora deste repositório**. O script recusa certificados de depuração, múltiplos signatários e impressões digitais diferentes. Não aceita a comparação sem esse valor.
- O script **não** prova o identificador da aplicação nem o endereço do servidor usado no build. Confirmar o pacote no dispositivo (`com.abigailovos.abigailovos`, sem o sufixo `.teste`) e o `API_BASE_URL` definido na compilação; um APK com outro servidor pode ter a mesma assinatura.

Na compilação release, as quatro variáveis de ambiente do Gradle devem ser fornecidas ao processo por um meio seguro, fora do repositório e do histórico do terminal; o endereço da API entra por `--dart-define=API_BASE_URL=...` e ainda não foi decidido para o piloto. Nenhuma chave, palavra-passe ou impressão digital real deve ser escrita neste ficheiro, noutros documentos do projeto ou na conversa.

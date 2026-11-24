# Verificação de leitura do computador ao TiDB

**Ligação de leitura comunicada como bem-sucedida pelo responsável.** Em 23/11/2026, após informar que adicionou uma regra para um único endereço, o responsável comunicou a mensagem de sucesso deste programa. Mais tarde escolheu a base consultada para o piloto real; o programa de ensaio fictício passou a recusar esse nome em qualquer host. O resultado e a lista final de regras não foram verificados independentemente. Usar somente após confirmação do responsável, numa instância exclusivamente fictícia, sem dados reais ou outros dados importantes. Não aplicar estes passos à base operacional. Esta verificação não cria contas nem tabelas e não executa migrações.

## Antes de executar

- Confirmar pessoalmente a instância correta no painel TiDB. Na sua janela **Connect**, consultar host, porta e nome de utilizador. **Não copiar para a conversa a cadeia de ligação completa**, que pode conter a palavra-passe. Não gerar nem redefinir a palavra-passe se já existir uma guardada.
- Verificar que o computador e a conta Windows são de confiança. A palavra-passe será introduzida numa consola local sem eco, mas ficará temporariamente na memória do processo Java e não está protegida contra software malicioso, outros processos privilegiados ou recolha de memória. Não enviar fotografias ou capturas do ecrã de credenciais.
- A conta administrativa `.root` serve apenas para esta primeira leitura, não para a aplicação ou ensaios operacionais. Falta preparar e validar uma conta exclusiva de teste com privilégios limitados à base fictícia.
- O programa usa o nome de base de ensaio explícito e `sslMode=VERIFY_IDENTITY`; rejeita outros formatos de base ou host fora de `tidbcloud.com`. A identidade TLS refere-se ao host fornecido: **não comprova que se escolheu a instância correta**. Zero tabelas visíveis depende dos privilégios e não prova que toda a instância esteja vazia.

## Execução, após confirmação

Abrir uma janela PowerShell normal do próprio Windows, não a conversa nem uma consola cujas entradas sejam gravadas por terceiros. No computador atual, após verificar que os caminhos continuam corretos e confirmar uma base fictícia diferente da reservada ao piloto, substituir `BASE_FICTICIA_AQUI` pelo nome dessa base na linha seguinte, que não contém palavra-passe:

```powershell
& 'C:\Program Files\Java\jdk-21.0.12.1\bin\java.exe' -cp "$env:USERPROFILE\.m2\repository\com\mysql\mysql-connector-j\9.4.0\mysql-connector-j-9.4.0.jar" "$env:USERPROFILE\Documents\NetBeansProjects\AbigailOvos\deploy\render-tidb\TidbReadOnlyProbe.java" 'BASE_FICTICIA_AQUI'
```

Quando o programa solicitar, introduzir **no próprio PowerShell** o host, a porta, o utilizador administrativo completo terminado em `.root` e, por último, a palavra-passe guardada. Durante a digitação da palavra-passe, os caracteres não são apresentados. Não escrever a palavra-passe na linha de comando nem no SQL Editor.

Se o programa informar sucesso, isso confirma uma ligação verificada ao host indicado e os valores consultados **nessa sessão**. Não confirma integridade de dados, permissões mínimas, migrações, concorrência, ligação do Render ou restauro. Se não iniciar, recusar a consola, não ligar ou apresentar outro resultado, parar; não desativar TLS, não mudar permissões nem enviar credenciais, endereços ou capturas sensíveis para pedir ajuda.

## Testes e limites

O código foi ensaiado localmente com ligações simuladas; o Connector/J 9.4.0 instalado interpretou a opção `sslMode` como `VERIFY_IDENTITY` sem abrir uma ligação. A execução sem consola interativa foi recusada. O responsável relatou a execução bem-sucedida no computador, sem observação independente. A mensagem indica ligação TLS verificada, ausência de tabelas visíveis e configuração esperada na sessão, mas não comprova a identidade da instância pretendida, isolamento, permissões mínimas, migrações, concorrência ou restauro. O software do computador e o armazenamento temporário continuam a ser pressupostos de confiança.

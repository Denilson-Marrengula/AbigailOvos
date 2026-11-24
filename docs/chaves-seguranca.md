# Chaves e recuperação: plano ainda não validado

**Não foram geradas chaves reais nem escolhido um local de recuperação.** Antes de usar dados reais é necessário definir responsáveis, confirmar como recuperar as chaves fora deste computador e testar o procedimento com dados fictícios. Não enviar chaves, palavras-passe ou códigos nesta conversa e não os colocar no repositório, em argumentos de comandos ou em logs.

## Chaves distintas

1. **Autenticador histórico:** o segundo fator foi retirado por decisão do responsável. `ABIGAIL_MFA_KEY` já não é exigida para o login atual, mas eventuais dados cifrados, chaves e cópias históricas não devem ser apagados ou alterados automaticamente. A inscrição anterior está desativada; um regresso a software antigo exige plano específico.
2. **Limite por origem:** `ABIGAIL_AUTH_ORIGIN_KEY` é uma chave aleatória independente de 32 bytes em Base64, para não guardar endereços em texto claro. A mudança da chave altera os identificadores das origens e pode reiniciar temporariamente os limites; antes de rodá-la será preciso proteger o perímetro, coordenar todas as réplicas e testar o procedimento. O limite não substitui proteção contra ataques distribuídos.
3. **Cifra das cópias:** `age` utiliza um destinatário público para cifrar e uma identidade privada para decifrar. A identidade privada não pode ficar apenas no mesmo disco ou depender exclusivamente do DPAPI deste Windows. Sem ela não se recupera a cópia. O protótipo aceita apenas dados fictícios e nenhuma identidade real foi gerada.
4. **Assinatura Android:** a chave da aplicação é diferente das anteriores; perdê-la pode impedir atualizações normais do APK. Ainda não foi gerada. Ver [assinatura-android.md](assinatura-android.md).

## Regras para o procedimento futuro

- Gerar cada chave com um gerador criptográfico confiável, nunca reutilizar chaves entre finalidades e limitar quem pode aceder a cada uma. A API precisa da chave de limite por origem através de configuração protegida; o Mobile não deve conter essa chave nem credenciais da base.
- Guardar uma cópia de recuperação protegida e independente deste computador e dos serviços na nuvem, acessível a uma pessoa autorizada após verificação de identidade. Escolher mais tarde o suporte, local, responsáveis e controlo de acesso; não presumir que uma cópia de segurança sem a chave é recuperável.
- Evitar dependências circulares: perder um dispositivo ou o computador não pode impedir simultaneamente o acesso ao local das chaves e ao procedimento de recuperação. Proteger também contra roubo e acesso indevido, não apenas perda.
- Ensaiar num ambiente isolado a perda da palavra-passe e das chaves, a restauração com a chave correta e a recusa de chave incorreta ou dados alterados. Confirmar identidade por um canal independente antes de uma recuperação administrativa; os operadores locais preparados ainda não provam quem é a pessoa física.
- Após restaurar uma base, invalidar sessões antigas de forma controlada, verificar relógios e chaves e seguir [copias-disco.md](../deploy/render-tidb/copias-disco.md) antes de reabrir a API. Não criar tarefas, alterar uma base existente, substituir segredos ou publicar sem autorização específica.

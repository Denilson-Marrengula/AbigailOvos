# Preparação: prevenir clientes duplicados

**Estado: implementação local testada automaticamente, ainda não publicada nem validada no dispositivo.** Foi escolhida a regra de telefone obrigatório e único por cliente. Dois clientes que partilham um número não poderão ter cadastros separados com esse número; é necessária uma decisão operacional para o caso de partilha ou de quem não tiver telefone. Não inventar números para contornar a regra.

## Regra em desenvolvimento

- Clientes continuam partilhados por todos os vendedores. Na criação dentro de uma venda ou pedido e na edição, o backend valida o telefone e calcula uma chave de comparação. A aplicação ajuda a pesquisar e selecionar um cliente existente; nomes iguais dão aviso, mas podem pertencer a pessoas diferentes.
- Sem indicativo, números com 8 ou 9 algarismos são tratados como de Moçambique. `84 123 4567`, `+258 84 123 4567`, `00258 84 123 4567` e `258841234567` representam a mesma chave. Outros países requerem `+` ou `00` e um número internacional estruturalmente válido. A verificação não confirma que o número existe ou pertence ao cliente.
- O backend mantém uma chave normalizada com índice único na base para rejeitar duplicados, incluindo pedidos simultâneos de vendedores diferentes. Um conflito não deve criar cliente, venda, reserva ou evento de negócio; o utilizador pode atualizar a lista e escolher explicitamente o cliente correto. O mesmo telefone ao editar o próprio cliente é permitido.
- Foi preparada uma verificação no arranque para recusar o serviço se a coluna obrigatória ou o índice único de uma única coluna não forem visíveis nos metadados. A verificação passou em H2, mas não foi validada em MySQL ou TiDB e não impede que alguém com privilégios de esquema altere a base depois do arranque; a conta normal deve ter permissões mínimas e as alterações de esquema ser controladas.
- O Mobile novo exige que o servidor anuncie `customerPhoneUnique` antes de criar ou editar um cliente. Isto não protege aplicações antigas ou chamadas diretas quando ligadas a um servidor antigo. O Railway V9 continua com a regra anterior.
- Um número único **não garante identidade única**: a mesma pessoa pode usar outro número, e diferentes pessoas podem ter nomes iguais. Não associar ou fundir automaticamente clientes apenas por nome ou sem confirmação do responsável.
- A sincronização offline e a resolução de conflitos ainda não existem. Quando forem implementadas, deverão manter o identificador estável da operação, não criar automaticamente clientes repetidos e permitir confirmar a associação ao existente sem perder vendas, pedidos, reservas ou histórico.

## V12 e dados anteriores

`V12__customer_phone_unique` é uma migração Java Flyway. Antes de alterar a tabela, examina os contactos existentes com a política congelada `CustomerPhoneV1`. Se houver números em falta, inválidos ou repetidos após normalização, recusa a migração e informa apenas contagens, sem expor telefones. Não completa contactos, não funde nem apaga clientes. Quando os dados estiverem reconciliados, preenche a chave sem mudar a apresentação original e acrescenta a restrição de unicidade.

Em 15/11/2026, passou em MySQL 8.4 isolado com dados fictícios: um caso válido preservou o telefone e a venda, e contactos inválidos ou equivalentes recusaram a migração antes da alteração da tabela de clientes. Não foi ensaiada na cópia final do Railway nem em TiDB. Mesmo quando a verificação inicial passa, DDL MySQL/TiDB pode falhar parcialmente depois de alterar a tabela; não executar `clean`, `repair`, apagamentos ou reenvios automáticos para contornar falhas. Os códigos de normalização usados pela V12 são históricos e não devem ser alterados após a aplicação; mudanças futuras requerem nova migração e política versionada.

Antes de atualizar uma base existente:

1. Obter autorização, suspender as gravações durante todo o processo, criar uma cópia consistente e verificar o restauro numa instância independente.
2. Identificar em ambiente protegido os clientes sem contacto válido e os grupos que normalizam para o mesmo número. Os dados pessoais e telefones não devem ser colocados em logs ou relatórios públicos. O levantamento seguro e a resolução administrativa ainda precisam de procedimento e teste.
3. O responsável deve confirmar cada identidade e decidir como corrigir os contactos ou tratar clientes efetivamente duplicados. **Não existe ainda função de fusão de clientes**; não alterar referências de vendas nem eliminar registos manualmente sem um plano próprio aprovado e testado numa cópia.
4. Ensaiar as migrações V10–V17 numa restauração atualizada, verificar números, clientes, vendas, pagamentos, stock e auditoria e preparar um plano de recuperação. Se o levantamento não puder ser resolvido com segurança, não avançar.
5. Só depois dos testes e de nova autorização, coordenar a atualização da base, do backend e dos APKs. A base Railway de teste continua V9, a base habitual V4; a cópia do Railway de 13/11 é preliminar e não substitui uma cópia final com gravações suspensas.

O backend antigo não conhece `phone_key`: não o manter a gravar em paralelo com o novo após a V12. Se for necessário regressar a uma versão anterior, manter as gravações suspensas e aprovar um plano de recuperação; o backend antigo poderia alterar um telefone sem atualizar a respetiva chave. Uma reversão não deve sobrepor dados novos com uma cópia anterior.

## Testes locais e pendentes

Em 15/11/2026 passaram testes locais para formatos equivalentes, contactos inválidos, duplicados, vendas, auditoria, capacidade no HTTPS simulado e interface, além dos três cenários de migração MySQL descritos acima. Os ensaios TiDB opcionais, o levantamento de contactos na cópia final e a validação no dispositivo continuam pendentes.

Para o ensaio MySQL optativo será necessário, além dos esquemas V9/V10 já previstos, criar previamente três bases locais novas e vazias `abigailovos_v12_isolated_ok`, `abigailovos_v12_isolated_invalid` e `abigailovos_v12_isolated_duplicate`. Os testes só se ligam a `127.0.0.1` na porta explicitamente indicada por `ABIGAIL_MYSQL_V9_PORT`; não apagam as bases, e uma execução que falhe deliberadamente pode deixar registos de migração falhada. Não apontar para bases habituais ou com dados importantes.

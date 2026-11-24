# Análise aprofundada do Kyte: regras e segurança

## Estado da investigação

Análise iniciada em 23/11/2026 a pedido do responsável. Esta etapa reúne
**documentação pública do Kyte**, a observação anterior de rótulos da sessão Web
e uma comparação com o código local do AbigailOvos. O funcionamento descrito
pelos guias pode depender da versão, do plano e das permissões do utilizador.
Os resultados efetivamente observados nos ensaios estão identificados abaixo;
os restantes pontos continuam a ser informação documental ou testes pendentes.

O responsável confirmou que a sessão é uma **conta de testes** e autorizou
registos fictícios. Foi criado um produto de teste e um cliente de teste,
identificados abaixo. Não foram alterados ou apagados registos anteriores, nem
guardados nomes, valores ou conteúdos privados. A partir do pedido para
trabalhar em segundo plano, a sessão anterior foi operada por acessibilidade,
sem pedir foco ou mover o rato, exceto a tentativa de seleção referida na
tabela. Foi entretanto preparada uma janela Chrome com perfil temporário
separado; o responsável iniciou sessão nela e o marcador do produto fictício
confirmou o acesso à mesma conta de teste. Os ensaios seguintes usaram uma
ponte de depuração local por canal privado nessa janela, sem pedir foco nem
mover o rato. A sessão anterior não foi copiada e o agente não leu credenciais
ou cookies. Como qualquer perfil autenticado do Chrome, o perfil temporário
pode conter dados da sessão até ser fechado e limpo com a autorização adequada.

### Ensaios já realizados

| Ensaio | Observação nesta conta de teste | Limite |
| --- | --- | --- |
| Produto `TESTE-ABIGAIL-8F42A6` | Criado com dados fictícios e gestão de stock ativada. O produto foi encontrado na lista e, ao abrir o próprio registo de teste, confirmou-se a quantidade inicial introduzida. | O estado de publicação no catálogo não foi confirmado; não foram alterados produtos anteriores. |
| Cliente `TESTE-CLIENTE-8F42A6` | Criado e encontrado na lista, introduzindo apenas o nome fictício; não foram fornecidos telefone, endereço ou e-mail. | A aceitação sem telefone aplica-se apenas ao ensaio nesta conta e não altera a regra do AbigailOvos. |
| Utilizador | O responsável introduziu, na janela isolada, um endereço que controla e uma palavra-passe de teste. O utilizador `TESTE-UTILIZADOR-8F42A6` apareceu na lista; a ficha apresenta controlos de permissões e o controlo administrativo foi observado como inativo. Após a reinicialização, o responsável relatou que a tentativa de entrada numa nova janela foi recusada com a mensagem «Este usuário não está autorizado a utilizar um dispositivo pessoal». | A mensagem foi relatada pelo responsável; a identidade da sessão e a origem da decisão não foram verificadas. O agente não recolheu o endereço nem a palavra-passe; a receção do e-mail e as restantes permissões efetivas ainda não foram confirmadas. |
| Pedido | Criado um pedido com o cliente e o produto fictícios. O estado observado passou de pendente a confirmado; o stock apresentado permaneceu igual enquanto pendente e diminuiu uma unidade após a confirmação. | Foi um único ensaio, não prova de regras de reserva ou concorrência. Durante uma tentativa anterior de seleção em segundo plano, o Chrome ficou em primeiro plano; esse método foi interrompido. |
| Venda | Foi concluída uma venda direta com o produto e o cliente fictícios, selecionando o meio manual Dinheiro. A venda apareceu no histórico, os seus detalhes referiam o produto, o cliente e Dinheiro, e o stock apresentado diminuiu mais uma unidade. | A marcação não demonstra qualquer pagamento real. |
| Estatísticas | A interface mostrou controlos para faturamento, vendas, ticket médio, lucro e pagamentos. Após a venda, os marcadores do produto e do cliente fictícios apareceram em áreas de ranking de produtos e clientes. | Não foram recolhidos valores nem validados os cálculos ou períodos dos relatórios. |

Os registos fictícios criados permanecem na conta de teste; não serão apagados
ou cancelados sem autorização específica. A confirmação de stock foi feita
apenas no produto fictício, não em produtos existentes. O pedido de teste
confirmado permanece na conta. Uma seleção anterior, não submetida, pode
continuar visível na sessão original.

## Produtos e stock

Segundo o [guia de registo de produtos](https://docs.kyteapp.com/pt-BR/articles/7861102-como-cadastrar-produtos-por-unidade-no-kyte),
o Kyte Web apresenta campos de nome e preço e opções como custo, categoria,
código, descrição, imagens, exibição no catálogo e stock mínimo. O guia
descreve estes campos, mas não foi verificado quais são obrigatórios nesta
conta nem se um produto novo fica publicado por defeito. No ensaio isolado,
nome, preço e stock fictícios foram suficientes para guardar um produto.

O [guia de stock](https://docs.kyteapp.com/pt-BR/articles/7861101-como-atualizar-seu-estoque-de-produtos)
descreve a introdução da **quantidade total atual**, não apenas da entrada;
o [guia de movimentações](https://docs.kyteapp.com/pt-BR/articles/7861171-como-controlar-as-movimentacoes-de-estoque)
diz que alterações manuais e vendas constam do histórico. Isto não demonstra,
por si só, as garantias de concorrência ou a regra de stock negativo do Kyte.

No AbigailOvos local, administradores e vendedores podem criar e editar
produtos; só administradores alteram o estado ativo. O stock distingue saldo
físico, reservado e disponível, e os movimentos são registados com responsável.
A reserva e a validação do preço e do stock são tratadas no backend. Ver
[`SalesController.java`](../backend/src/main/java/com/abigailovos/sales/SalesController.java)
e [`StockService.java`](../backend/src/main/java/com/abigailovos/stock/StockService.java).
Não substituir esses movimentos por simples edição de saldo por causa do Kyte.

## Clientes

O [guia de clientes](https://docs.kyteapp.com/pt-BR/articles/7861169-como-cadastrar-seus-clientes)
descreve no Kyte Web nome, contactos, endereço e campos adicionais, incluindo
uma opção para permitir fiado. O guia menciona verificação de endereços pelo
Google Maps; não foi testado quando ou que dados são enviados. A existência de
um campo na documentação não prova a sua obrigatoriedade nesta conta. Nesta
conta de teste foi possível criar um cliente com nome fictício sem preencher
telefone, endereço ou e-mail; não foram ensaiadas outras validações.

No AbigailOvos, todos os vendedores consultam os clientes; um cliente novo é
criado no âmbito da venda ou pedido, com nome e telefone obrigatório e telefone
normalizado único. Fiado, histórico por cliente e recolha de documentos de
identidade não estão aprovados por esta análise.

## Pedidos, vendas e pagamentos

Segundo os guias de [pedidos](https://docs.kyteapp.com/pt-BR/articles/7861106-como-registrar-um-pedido-pessoalmente)
e [venda presencial](https://docs.kyteapp.com/pt-BR/articles/7915515-registrando-uma-venda-presencial),
o Kyte Web permite selecionar produtos e cliente, rever itens e escolher entre
guardar um pedido e concluir uma venda. Os guias também descrevem alteração de
preços, descontos e opções de entrega. A documentação afirma que pedidos
presenciais são inicialmente pendentes e que a confirmação atualiza o stock e
impede a edição. O ensaio observado concordou com a alteração do stock após a
confirmação, mas não foi comprovado se há reserva antes da confirmação, se a
edição é impedida ou como se comportam pedidos concorrentes.

O Kyte documenta [estados personalizáveis](https://docs.kyteapp.com/pt-BR/articles/7861156-como-ativar-o-status-de-pedido)
e um [cancelamento que não pode ser restaurado](https://docs.kyteapp.com/pt-BR/articles/7861145-como-cancelar-um-pedido).
O guia de [pagamentos múltiplos](https://docs.kyteapp.com/pt-BR/articles/7861122-como-registrar-mais-de-um-pagamento-na-mesma-venda)
indica que a função está disponível apenas no aplicativo móvel, não na Web.
Não se testaram cancelamentos, devoluções nem efeitos financeiros reais.

No AbigailOvos, entrega e pagamento são estados independentes. Um pedido
pendente confirmado reserva stock; ao entregar é registada a saída. Apenas um
pedido pendente não pago pode ser cancelado, libertando a reserva. O pagamento
integral é uma marcação manual com um meio, não confirmação junto do operador.
Descontos, pagamento misto e reembolso não estão implementados ou aprovados.

## Estatísticas e relatórios

O [guia de resultados](https://docs.kyteapp.com/pt-BR/articles/7861107-visualize-os-resultados-de-seu-negocio)
lista faturamento, vendas, ticket médio, lucro e rankings. O guia alerta que as
estatísticas somam vendas fechadas pela **data de criação do pedido**, enquanto
o relatório de vendas exportado usa a **data de fechamento** para vendas
fechadas e inclui também pedidos não fechados; cancelados não aparecem em
nenhum dos dois. Não foi testado se essas regras se aplicam integralmente à
sessão Web observada.

O [guia de exportação](https://docs.kyteapp.com/pt-BR/articles/7861123-exporte-os-relatorios-de-seu-negocio)
distingue o aplicativo móvel da Web e indica restrições por plano e perfil; na
Web descreve exportação de produtos e clientes, não do relatório de vendas.
Outro guia descreve impressão da [página de transações da Web](https://docs.kyteapp.com/pt-BR/articles/12004741-como-visualizar-o-historico-de-vendas-no-kyte-web)
para PDF pelo navegador, o que é diferente de exportar os dados de vendas em
CSV. Não foram exportados dados da conta observada.

O relatório local do AbigailOvos agrega operações pendentes, entregues,
canceladas e pagamentos, com desempenho por vendedor; o código atual não tem
filtro por período nesse endpoint. Ver
[`SalesReportController.java`](../backend/src/main/java/com/abigailovos/sales/SalesReportController.java).
Em evoluções futuras, definir explicitamente datas, estados incluídos, fuso
horário e significado de cada total antes de comparar números.

## Utilizadores e segurança

O [guia de utilizadores](https://docs.kyteapp.com/pt-BR/articles/7861116-como-registrar-um-usuario-no-kyte)
descreve utilizador principal, administrador e utilizadores com permissões
individuais, incluindo acesso a transações alheias, edição de produtos,
descontos, fiado e uso de dispositivo pessoal. A criação solicita um endereço de e-mail e o guia diz que
os dados de acesso são enviados ao utilizador. O
[guia de edição](https://docs.kyteapp.com/pt-BR/articles/7861159-como-alterar-dados-dos-usuarios)
orienta a sair e entrar novamente após alterações; isso não comprova revogação
imediata de sessões. O [guia de recuperação](https://docs.kyteapp.com/pt-BR/articles/7861136-como-redefinir-senhas-no-kyte)
descreve confirmação por código de e-mail para recuperação de acesso de contas
com login por e-mail.

Na tentativa de acesso comunicada acima, a mensagem sobre dispositivo pessoal
é coerente com a existência dessa permissão, mas não demonstra, por si só, que
alterá-la resolverá o bloqueio ou que a restrição é aplicada no servidor. A
permissão não foi alterada durante a retoma; o acesso às outras áreas continua
por testar com o perfil de utilizador de teste identificado.

Nenhuma destas descrições comprova como o Kyte guarda senhas, valida
permissões no servidor, cifra dados, limita tentativas ou revoga sessões. Não
foi efetuada auditoria de segurança nem teste de intrusão e não é possível
classificar a segurança do Kyte a partir desta observação.

No código local do AbigailOvos, as regras de perfil são aplicadas no backend,
o acesso de vendedores a operações é filtrado por proprietário e existem
sessões revogáveis, limitação de tentativas e registo de auditoria. Isso não
substitui a validação operacional, o teste de recuperação e as cópias descritos
em [validacao-seguranca-copias.md](validacao-seguranca-copias.md).

## Melhorias locais inspiradas na comparação

O responsável aprovou estas cinco melhorias para desenvolvimento local. Não
foram aprovadas a instalação no telefone, a publicação ou a aplicação de
migrações numa base existente. O código e os testes locais não substituem a
validação no dispositivo e no ambiente de destino:

1. **Venda mais simples:** o formulário foi reorganizado em secções de seleção de
   produtos e quantidades, escolha do cliente e revisão final, com resumo dos
   itens e total indicativo. Aproveita as APIs atuais e mantém separados
   entrega e pagamento, a validação no servidor e o reenvio seguro.
2. **Consulta de operações:** foram acrescentados pesquisa e filtros por cliente,
   produto ou período às listas existentes. Já há separação por entregar, por
   pagar, entregues e canceladas. Manter no servidor o isolamento das vendas
   de cada vendedor; a paginação é feita na API e o período usa a criação.
3. **Relatórios mais claros:** é possível escolher um período e comparar
   entregas, pagamentos marcados, valores pendentes e desempenho por vendedor.
   O responsável escolheu a data do evento e o horário de Maputo. A V17 adiciona
   datas de entrega, marcação do pagamento e cancelamento; dados antigos sem
   essas datas ficam desconhecidos, não são adivinhados. Pendências mostram a
   situação atual de todo o histórico. Marcações manuais não comprovam
   recebimentos externos.
4. **Alertas de stock:** são destacados produtos sem stock disponível,
   indicador que já existe no painel do vendedor. O mínimo opcional por produto
   alerta quando o disponível é igual ou inferior; requer a V17 e não substitui
   movimentos por edição livre do saldo.
5. **Histórico administrativo:** foi criada uma tela para os eventos de auditoria
   já consultáveis pela API do administrador. A auditoria existente é inicial,
   não retroativa e incompleta, pelo que a tela não deve prometer um histórico
   integral ou inviolável.

Rankings, catálogo, descontos, pagamentos mistos e outras funções exigem
decisões e regras próprias. O modo offline continua previsto para uma fase
posterior. Antes de utilizar dados reais, continuam obrigatórias as validações
operacionais e cópias descritas em [primeira-versao-uso.md](primeira-versao-uso.md).

## Plano de ensaio pendente

Continuar apenas na conta e condições explicitamente confirmadas, usando dados
fictícios identificáveis como teste e sem modificar registos existentes:

1. **Parcialmente concluído:** produto e cliente fictícios criados. Falta
   verificar o estado de publicação do produto e outras validações.
2. **Parcialmente concluído:** o pedido fictício foi guardado e confirmado e o
   stock apresentado foi comparado antes e depois. Uma venda direta fictícia
   foi concluída, encontrada no histórico e associada a uma nova redução de
   stock; os marcadores fictícios foram vistos nas estatísticas. Falta validar
   os cálculos e os períodos. Não presumir que o cancelamento restaure todos os
   efeitos.
3. Comparar estados de entrega e pagamento e verificar, com dados fictícios,
   que datas e estados entram nos relatórios. Evitar exportar dados reais.
4. Testar permissões apenas com contas de teste autorizadas. O utilizador de
   teste já aparece na lista, mas a entrada na janela separada foi recusada;
   falta confirmar o acesso e as restantes permissões com esse perfil. Não
   solicitar nem guardar palavras-passe ou códigos.
5. Registar resultados observados separadamente do que os guias afirmam.
   Não apagar ou alterar os registos de ensaio sem autorização específica.

Os ensaios podem afetar stock, catálogo, estatísticas e mensagens enviadas a
terceiros. Também não autorizam alterações às regras do AbigailOvos.

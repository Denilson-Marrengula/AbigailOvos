# Kyte como referência para o AbigailOvos

## Âmbito e fontes

Pesquisa documental realizada em 23/11/2026, a pedido do responsável, para
identificar padrões de utilização que possam inspirar o AbigailOvos sem alterar
as suas regras de negócio. Foram consultadas fontes públicas do Kyte e o código
local do AbigailOvos.

Esta comparação descreve o estado observado no início da pesquisa. As melhorias
posteriormente aprovadas para desenvolvimento local e os respetivos limites
estão em [análise aprofundada](analise-aprofundada-kyte.md) e
[estado atual](estado-atual.md); o texto histórico abaixo não substitui esses
documentos para saber o que já foi alterado.

**Limite da pesquisa inicial:** não foi disponibilizado um APK do Kyte e não
havia um telemóvel ligado. Nessa fase não executámos nem analisámos o binário do
Kyte, nem consultámos contas ou dados privados. Foram examinadas descrições,
imagens e amostras de demonstrações pré-gravadas publicadas pelo próprio Kyte.
Depois, com o endereço fornecido e a sessão já iniciada pelo responsável, foram
observados apenas rótulos genéricos do Kyte Web, como descrito abaixo. Estas
referências podem variar conforme a versão ou o plano e não demonstram a
implementação interna, a segurança ou o tratamento de falhas.

Fontes públicas consultadas:

- [Venda presencial no Kyte](https://docs.kyteapp.com/pt-BR/articles/7915515-registrando-uma-venda-presencial).
- [Registo de pedidos no Kyte](https://docs.kyteapp.com/pt-BR/articles/7861106-como-registrar-um-pedido-pessoalmente).
- [Atualização do stock no Kyte](https://docs.kyteapp.com/pt-BR/articles/7861101-como-atualizar-seu-estoque-de-produtos).
- [Histórico de vendas no Kyte](https://docs.kyteapp.com/pt-BR/articles/7861173-como-visualizar-o-historico-de-suas-vendas-no-app-de-kyte).
- [Vários meios de pagamento no Kyte](https://docs.kyteapp.com/pt-BR/articles/7861122-como-registrar-mais-de-um-pagamento-na-mesma-venda).
- [Página oficial do Kyte](https://www.kyteapp.com/pt) e imagens públicas da
  [página do aplicativo no Google Play](https://play.google.com/store/apps/details?id=com.kyte&hl=pt_BR).

Para o AbigailOvos foram consultados principalmente
[`sales_page.dart`](../mobile/lib/seller/sales_page.dart),
[`stock_page.dart`](../mobile/lib/seller/stock_page.dart),
[`customers_page.dart`](../mobile/lib/seller/customers_page.dart),
[`SalesController.java`](../backend/src/main/java/com/abigailovos/sales/SalesController.java)
e [primeira-versao-uso.md](primeira-versao-uso.md). O código local continua em
desenvolvimento e não constitui validação operacional no telefone ou em produção.

## Observações nas demonstrações públicas

Foram examinados seis quadros distribuídos por cada uma das três animações
publicadas nos guias de venda, stock e pagamento acima. São amostras limitadas de
gravações, não um teste interativo nem uma descrição completa do aplicativo.

- Na demonstração de venda, vê-se um menu lateral e uma grelha de produtos com
  imagens, nomes e preços, além de um botão na parte inferior. A gravação também
  mostra uma tela para indicar quantidade e remover um produto. O AbigailOvos
  pode inspirar-se na seleção clara e na revisão de itens, sem pressupor a
  existência de fotografias, categorias ou alterações de preço por venda.
- A mesma demonstração mostra opções de entrega e edição do preço para aquela
  venda. São recursos do exemplo Kyte, não regras já aprovadas ou implementadas
  no AbigailOvos.
- Na demonstração de stock, vê-se a ficha de um produto e uma tela para definir
  stock mínimo. O AbigailOvos já distingue físico, reservado e disponível; não
  existe uma regra de stock mínimo configurável nesta etapa.
- Na demonstração de pagamentos, vê-se um carrinho com itens e total, a escolha
  de meios de pagamento e um recibo. O exemplo usa vários pagamentos; no
  AbigailOvos permanece um único meio para o pagamento integral.

Para identificar as gravações examinadas, os ficheiros temporários obtidos dos
respetivos guias tinham estes SHA-256 e totais de quadros:

| Guia | Quadros | SHA-256 da gravação |
| --- | ---: | --- |
| Venda presencial | 2177 | `16c1498dd2cb1e6f7f8bc6dcb4d62587e9aedbe774060ac0df13b69193cea16e` |
| Ativação do stock | 584 | `6721adcab5bba074afa194f40949b877c0db3b69299761c16c26ec7bb0de7bd2` |
| Vários pagamentos | 1131 | `51b8036bb6ae0c502b67e972c2eca6f9ce1ef6ad504f1863dc8acd11b811e7d6` |

## Observação limitada do Kyte Web

Na sequência do endereço `https://web.kyteapp.com/orders` fornecido pelo
responsável e do seu pedido para abrir as outras páginas, foi selecionada a aba
existente do navegador. A observação usou a interface de acessibilidade do
Windows, **não** a captura de navegador do REA. A navegação limitou-se aos menus
e à abertura de um filtro; não foram abertos registos individuais, escolhidos
estados, nem criados, alterados ou apagados registos. Também não foram guardados
nomes de clientes, valores ou conteúdos dos registos. As seguintes observações
são parciais e dependem da conta, do plano, da versão e dos controlos acessíveis
naquele momento. Esta descrição refere-se à observação inicial; os ensaios
fictícios autorizados posteriormente estão registados na
[análise aprofundada](analise-aprofundada-kyte.md).

| Área aberta | Rota observada | Rótulos e controlos genéricos observados |
| --- | --- | --- |
| Pedidos | `/orders` | Título de pedidos, campo associado a cliente e filtro de estado. Ao abrir o filtro surgiram, pelo menos, as opções pendente, confirmado e pago; não foi verificado se a lista é completa. |
| Produtos | `/products` | Referências visíveis a produtos, categorias e filtros. |
| Catálogo | `/catalog` | Referências a catálogo e um campo de edição com rótulo associado; não foi introduzido conteúdo nem verificada a função do campo. |
| Clientes | `/customers` | Referências visíveis a clientes e um campo de pesquisa. |
| Histórico | `/sales` | Referências a vendas, filtros e vendedor, com campos associados a produtos e clientes. A lógica dos filtros não foi testada. |
| Estatísticas | `/analytics` | Controlos associados a faturamento e vendas e referência a período. Não foram recolhidos valores nem verificados cálculos. |
| Utilizadores | `/users` | Referência genérica a utilizadores; as funções e permissões desta área não foram verificadas. |

O Kyte Web é uma referência separada do aplicativo móvel; não se pode concluir
que as telas ou permissões sejam idênticas. A seleção de um item, a gravação de
uma venda, as alterações de stock e a aplicação dos filtros não foram testadas.
Alguns outros atalhos do menu não foram identificados com segurança e não foram
abertos; a tabela não é uma lista exaustiva das áreas disponíveis.

O REA analisou também, como texto inerte e sem usar a sessão do responsável, o
ficheiro JavaScript público `static/js/main.dd038f7f.js`, com 4 178 271 bytes e
SHA-256 `065294578db668cdecf517dd679ce40de71879bcbe43c6becb69802df36d7c48`.
A análise estática produziu a evidência
`ev_eabe486c18a76e8aaf984edc38e749663ec7781d821aa2ed4ae87923daf041c0`, mas a
cobertura ficou parcial por limite de memória. O rastreio exato de `/orders`
(`ev_9ff8610c4f6fd704fab042252f84a9d4ef70fc9cab628e635bdbf1b0ba94b867`)
não encontrou correspondência no grafo incompleto; isso **não** prova ausência
da funcionalidade. Uma pesquisa textual independente encontrou a cadeia
`/orders` no ficheiro, mas não estabelece o seu comportamento em execução.
Nenhuma conclusão sobre segurança, permissões ou processamento no servidor foi
retirada desse código.

### Possíveis ideias para o AbigailOvos

- Manter as áreas de trabalho fáceis de encontrar pelo menu e dar destaque à
  pesquisa de clientes e à consulta de pedidos; o menu lateral já existe no
  projeto local.
- Avaliar, numa etapa futura, uma consulta de histórico com filtros claros por
  cliente, produto ou vendedor, sempre respeitando as permissões do backend.
  A observação do Kyte não confirmou o funcionamento dos seus filtros.
- Apresentar os indicadores e o período de referência de forma compreensível,
  sem assumir cálculos ou opções que não foram verificados no Kyte.
- Manter entrega e pagamento como estados independentes no AbigailOvos, em vez
  de importar diretamente os rótulos do filtro de pedidos do Kyte.

Estas são sugestões de organização e não autorizam a implementação de catálogo,
novos filtros ou outras funcionalidades sem requisitos e aprovação próprios.

## Comparação dos fluxos

A [análise aprofundada de regras e segurança](analise-aprofundada-kyte.md)
separa o que os guias públicos descrevem dos testes ainda pendentes.

| Área | Referência pública do Kyte | AbigailOvos local e limite a preservar |
| --- | --- | --- |
| Navegação | As imagens públicas mostram menu lateral e áreas dedicadas a vendas e produtos. | Já existe menu lateral e barra inferior para ambos os perfis. As opções continuam diferentes para administrador e vendedor. |
| Venda | O guia descreve seleção de produtos, revisão dos itens, associação de cliente e conclusão. | O vendedor escolhe ou regista o cliente, introduz quantidades dos produtos e escolhe estados de entrega e pagamento num formulário. Um fluxo mais visual pode reorganizar estes passos sem mudar o pedido enviado ao servidor. |
| Cliente | O Kyte documenta associação de um contacto e cadastro de clientes. | Todos os vendedores consultam os clientes; um cliente novo é criado durante a venda ou pedido. Nome e telefone são obrigatórios e o telefone normalizado é único. Não acrescentar cadastro isolado sem decisão. |
| Preços e descontos | O Kyte documenta alterações de preço e descontos na venda. | O servidor verifica o preço esperado contra o preço atual e calcula o total. Descontos ou preços livres não estão implementados e exigiriam regras e alterações próprias. |
| Entrega e pedido | O Kyte descreve pedidos pendentes e confirmação posterior. | Entrega e pagamento têm estados independentes. Um pedido pendente registado reserva stock; uma entrega confirmada regista a saída. Não substituir estas regras pelos estados do Kyte. |
| Pagamento | O Kyte documenta vários meios numa mesma venda. | O pagamento é registado integralmente com um meio: e-Mola, M-Pesa, banco ou dinheiro. É uma marcação manual, não uma confirmação do operador. Pagamentos parciais ou mistos não estão implementados. |
| Stock | O guia do Kyte descreve a atualização da quantidade total no produto. | O AbigailOvos apresenta saldo físico, reservado e disponível. O vendedor regista entradas, ajustes, perdas ou quebras; o histórico e as reservas não devem ser substituídos por uma simples alteração de saldo. |
| Histórico e relatórios | O Kyte documenta pesquisa, filtros por período, vendedor e meio de pagamento, e exportação CSV. | O Mobile separa operações por entregar, por pagar, entregues e canceladas. O relatório administrativo pode gerar PDF, mas os filtros por período, paginação e exportação CSV não estão implementados. |

## Regras que não devem mudar por causa da referência

1. O stock central é partilhado e a API valida o stock disponível e o preço;
   uma indicação apresentada no telefone não substitui essa validação.
2. Cada vendedor consulta e altera apenas as próprias vendas e pedidos. O
   administrador consulta todas as operações e pode assistir na entrega e no
   pagamento, mas não cria vendas nem cancela pedidos de outros vendedores.
3. Não permitir que movimentos ou vendas deixem o stock disponível negativo.
   Cancelar um pedido pendente não pago liberta a reserva.
4. Manter a confirmação explícita de entrega e pagamento, a identificação do
   vendedor e os meios de pagamento já existentes. Uma marcação de pagamento não
   comprova o recebimento externo; pedidos pagos não podem ser cancelados nesta
   versão porque o tratamento de reembolso não existe.
5. A primeira versão continua online. O modo offline e a sincronização são
   requisitos para uma fase posterior, não uma capacidade já implementada.
6. Não alterar bases existentes, executar migrações, publicar serviços ou
   instalar APKs por causa desta pesquisa. Essas ações exigem os procedimentos
   e autorizações próprios do projeto.

## Sugestão para uma etapa posterior, ainda não autorizada

Reorganizar o registo de venda em passos mais claros, inspirados no fluxo
documentado pelo Kyte, mas mantendo o modelo atual do AbigailOvos:

1. Escolher os produtos existentes e as quantidades, com acesso claro ao preço e
   ao stock disponível quando a consulta estiver acessível. Identificar dados
   indisponíveis ou potencialmente desatualizados; o servidor continua a
   decidir se a operação pode ser aceite.
2. Selecionar um cliente ou registar nome e telefone, conservando a prevenção de
   duplicados e a criação conjunta com a operação.
3. Rever os itens e o **total indicativo**, escolher entrega e pagamento de
   forma independente e enviar a venda ou o pedido ao servidor.

Isto é uma proposta de interface, não uma decisão de adicionar fotografias de
produtos, descontos, pagamentos mistos, recibos individuais, catálogo online ou
sincronização offline. Essas funcionalidades precisam de requisitos próprios e
aprovação antes de qualquer implementação.

Ao redesenhar este fluxo, manter o identificador estável e o mesmo pedido ao
repetir um envio com resultado desconhecido. Não desbloquear os campos nem criar
uma nova operação automaticamente depois de uma resposta perdida. Preservar os
avisos existentes, a validação do servidor e os testes de permissões, stock,
preço, duplicação e falhas de rede. O total apresentado antes da confirmação é
indicativo; não prometer que o pagamento foi verificado externamente.

## Questões em aberto

- Que ecrã ou operação concreta do Kyte o responsável considera mais importante?
- O fluxo de venda proposto deve ser aprovado antes de alterar o formulário?
- Quando houver referências adicionais, correspondem à mesma versão do Kyte e
  ao perfil utilizado pelo responsável?
- Alterações a preços, descontos, pagamentos parciais, histórico por cliente ou
  funcionalidades offline interessam ao negócio e justificam regras próprias?

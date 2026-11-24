# Primeira versão para utilização real

**Objetivo:** uma primeira versão funcional e segura para a operação diária, inicialmente **online**. O responsável decidiu que a operação offline e a sincronização serão uma fase posterior; continuam a ser requisitos do projeto e não devem ser apresentadas como concluídas.

Em 24/11/2026, o responsável reforçou que pretende entregar **o mais cedo possível uma primeira versão funcional à equipa**, deixando as restantes melhorias para atualizações posteriores. Priorizar autenticação por perfil, clientes, produtos, stock, vendas e encomendas, com marcação manual de pagamento. Operação offline e melhorias adicionais não bloqueiam esta versão. Esta prioridade não comprova que o serviço, os dados ou a distribuição estão prontos, nem substitui a validação de segurança, stock e recuperação antes de usar dados reais.

**Estado: ainda não pronta para utilização real.** As alterações locais posteriores à V10 passaram em testes automáticos isolados, mas não foram publicadas nem validadas ponta a ponta. O Railway V9 e os APKs existentes são exclusivamente para testes com dados fictícios.

O responsável pretende começar com um piloto de sete dias com dados reais, num ambiente novo e separado. Preparação, limites e preservação dos registos após o período estão em [piloto-dados-reais.md](piloto-dados-reais.md).

## O que a primeira versão deve permitir

- Autenticação por palavra-passe e acesso por perfil, com recuperação segura e sessões revogáveis. O responsável decidiu retirar o segundo fator também da versão para uso real; é necessário reconhecer o risco acrescido caso uma palavra-passe seja comprometida.
- Administrador gere vendedores, pode criar e editar produtos, altera o estado ativo dos produtos, consulta clientes e stock, acompanha operações e relatórios, e pode concluir entregas e marcar pagamentos mantendo o vendedor original e o autor da ação. Cancelamento de pedido de outro vendedor não foi autorizado.
- Vendedor consulta todos os clientes e o stock central; cria e edita produtos e preços; regista movimentos manuais; cria vendas e pedidos; consulta e altera apenas as próprias operações. O telefone dos clientes é obrigatório e único após normalização; a mesma pessoa com outro número ainda pode ser duplicada.
- Vendas e pedidos são registados e confirmados pelo backend, com verificação de stock e preço. Um pedido pendente confirmado reserva stock. Pagamentos integrais são marcações manuais por e-Mola, M-Pesa, banco ou dinheiro; a aplicação não confirma o pagamento junto do operador ou banco.
- Consultar pendências de entrega e pagamento, resumo administrativo e relatório para impressão. A impressão precisa de ser validada no dispositivo e numa impressora ou destino escolhido.

## Limite da versão online

- É necessária internet para autenticar, consultar e registar operações. Sem ligação ou resposta do servidor, a aplicação não deve apresentar uma venda, pagamento, entrega ou movimento como confirmado nem prometer sincronização posterior.
- Se a ligação falhar depois do envio, o resultado pode ser desconhecido. O reenvio idêntico da venda ou do movimento de stock usa o mesmo identificador enquanto o formulário permanece aberto, mesmo que um reenvio posterior seja recusado; após fechar ou perder a aplicação, deve-se consultar o estado antes de criar outra operação. Para stock, o vendedor pode pedir ao administrador que verifique o histórico. Não existe fila persistente nem recuperação automática no dispositivo. Existem testes automáticos locais, mas falta validação no dispositivo e em falhas reais de rede.
- A implementação futura offline terá de proteger dados locais, identificar operações, sincronizar idempotentemente e resolver com segurança conflitos de stock, preços e clientes. Essa funcionalidade continua pendente e não é necessária para iniciar a versão online escolhida.

## Condições obrigatórias antes de usar dados reais

1. Concluir a validação operacional da recuperação de acesso e das sessões revogáveis; verificar permissões, isolamento de vendas, proteção contra tentativas e auditoria. A senha inicial e as senhas redefinidas de vendedores são temporárias no código local e passaram em testes automáticos, mas ainda precisam de ensaio no dispositivo.
2. Implementar uma cópia diária cifrada no disco escolhido, alertas de falha e recuperação de chave; restaurar e verificar a cópia numa instância independente. Ver [copias-disco.md](../deploy/render-tidb/copias-disco.md).
3. Preparar ambientes separados no Render e TiDB, validar TLS, proxy, migrações, restrições, concorrência de stock e compatibilidade. Confirmar custos e obter autorização antes de criar serviços pagos ou publicar.
4. Rever eventuais clientes anteriores sem telefone ou com duplicados; nunca apagar ou fundir históricos automaticamente. Antes de migrar uma base existente, suspender gravações, obter cópia atualizada, verificar o restauro, ensaiar as migrações nessa cópia e obter autorização. Ver [duplicados-clientes.md](duplicados-clientes.md).
5. Gerar e proteger uma chave Android própria, preparar distribuição e atualizações sem perder dados e validar o APK no dispositivo. Os APKs debug anteriores não são para produção.
6. Configurar domínio próprio e HTTPS, concluir revisão jurídica dos documentos e definir responsáveis pelo acesso, dados, cópias e incidentes. Ver [requisitos-lancamento.md](requisitos-lancamento.md).
7. Complementar os testes automatizados e ensaios MySQL já realizados com dados fictícios: faltam TiDB, cópias e restauro, além de outros cenários de concorrência, permissões e falhas. Validar também telefone, rede e impressão. Depois de analisar os resultados, pedir aprovação para qualquer publicação e introdução de dados reais.

O plano detalhado, os resultados parciais e as condições de isolamento estão em [validacao-seguranca-copias.md](validacao-seguranca-copias.md).

Estas condições não autorizam alterar o Railway, criar serviços pagos, migrar bases, instalar APKs ou iniciar operações reais. Cada ação externa ou potencialmente destrutiva exige confirmação própria.

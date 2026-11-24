# Diagnóstico técnico

Diagnóstico inicial de 8 de novembro de 2026, atualizado com os testes locais de 15 de novembro. Para resultados e limitações detalhados, consultar [estado-atual.md](estado-atual.md).

## Estado atual

- Backend Spring Boot com BCrypt, proteção CSRF e APIs para produtos, clientes, utilizadores, stock, pedidos e vendas. O acesso é controlado pelo Spring Security. Por decisão do responsável, o modo local usa sessões e palavra-passe sem segundo fator; o Railway V9 e o modo legado ainda usam HTTP Basic provisório.
- Uma venda imediata regista a saída de stock; um pedido guardado reserva stock, e a entrega ou cancelamento movimenta ou liberta a reserva. Preços de venda são preservados. O mesmo identificador de pedido é reutilizável durante o mesmo envio, incluindo reenvios simultâneos com os mesmos dados.
- O Mobile tem áreas separadas de vendedor e administrador. O vendedor consulta preços e quantidades na mesma tela de stock, regista movimentos e cria vendas ou pedidos; o administrador consulta clientes e um resumo de operações e gere vendedores. As alterações recentes ainda precisam de validação no telemóvel.
- A base MySQL habitual permanece em V4. As migrações V5–V7 foram testadas numa cópia restaurada e numa base isolada; o procedimento e as limitações constam em [validacao-vendas.md](validacao-vendas.md). A base habitual não foi migrada.

## Lacunas para utilização real

- A autenticação continua provisória: o modo legado tem limitação básica em memória por endereço, partilhada em NAT/proxy e perdida ao reiniciar. O modo de sessões e a recuperação passaram em testes locais, mas faltam validação ponta a ponta, verificação de origem no proxy, gestão e recuperação de chaves, reforço contra abuso e avaliação independente de segurança. Sem segundo fator, uma palavra-passe administrativa comprometida pode permitir acesso. HTTP Basic não deve ser usado com dados reais.
- Há eventos de auditoria transacionais para operações principais após a migração V8, sem segredos nem corpos de pedidos. O modo local também prevê eventos de autenticação conhecida, mas não regista todos os acessos ou tentativas nem valores anteriores; a conta de base de dados ainda pode alterar registos e não existe retenção definida. A consulta tem interface Mobile local para o administrador, mas a auditoria não é retroativa nem inviolável.
- A definição de cliente ativo ainda está pendente; o administrador vê a lista de clientes sem classificação de atividade. A nova regra de isolamento das vendas e assistência administrativa passou em testes automáticos locais, mas continua apenas no código local; o Railway V9 mantém o comportamento antigo.
- O relatório do administrador é um resumo de estados e operações, não um relatório financeiro de recebimentos. Pagamento marcado como pago não comprova pagamento externo. Os meios de pagamento integrais estão em desenvolvimento; faltam pagamentos parciais, reembolsos, devoluções e cancelamento de pedidos pagos.
- O resumo local agrega no servidor e filtra eventos por período; pendências permanecem uma fotografia atual. A consulta paginada aplica a verificação exata de proprietário antes de formar cada página, podendo ter de percorrer resultados anteriores; desempenho em históricos grandes ainda não foi validado. As páginas podem mudar com novas gravações, e detalhes e resumo são pedidos separados que podem refletir momentos diferentes.
- Os identificadores de reenvio de vendas e movimentos de stock existem apenas enquanto os respetivos formulários permanecem abertos. Uma interrupção da aplicação exige verificar os dados antes de criar outra operação; ainda não existem fila SQLite, sincronização offline ou resolução de conflitos.
- Os testes do backend em H2 e os cenários HTTPS/MySQL isolados não substituem testes de carga e concorrência abrangentes, recuperação de falhas ou validação completa no dispositivo. Os testes Flutter utilizam dados simulados.
- O APK de desenvolvimento usa chave de depuração; o projeto ainda não está preparado para distribuição ou operações reais.
- A estrutura iOS foi criada, mas a compilação, assinatura, ligação HTTPS e comportamento em simulador e iPhone ainda não foram validados. O identificador iOS é provisório e uma compilação de teste não cria automaticamente uma instalação separada.

## Regras de referência

- Valores monetários usam precisão decimal no servidor; o cliente envia preço e quantidade como texto decimal para não alterar o valor na serialização. O total mostrado antes da confirmação é indicativo e o backend rejeita preços desatualizados.
- Guardar um pedido pendente já o confirma e reserva stock; um formulário ainda não enviado não reserva. O cancelamento de pedido não pago liberta a reserva e a entrega não duplica a saída física.
- Os meios de pagamento previstos incluem numerário, M-Pesa, e-Mola e transferência; marcar uma operação como paga não comprova recebimentos externos.
- Se vier a existir operação offline, vendas com stock insuficiente devem permanecer em conflito, sem confirmação automática nem stock negativo, até resolução auditável.

# Diagnóstico técnico — 8 de novembro de 2026

## Estado atual

- Backend Spring Boot com autenticação HTTP Basic provisória, BCrypt, proteção CSRF e APIs para produtos, clientes, utilizadores, stock, pedidos e vendas. O acesso é controlado pelo Spring Security.
- Uma venda imediata regista a saída de stock; um pedido guardado reserva stock, e a entrega ou cancelamento movimenta ou liberta a reserva. Preços de venda são preservados. O mesmo identificador de pedido é reutilizável durante o mesmo envio, incluindo reenvios simultâneos com os mesmos dados.
- O Mobile tem áreas separadas de vendedor e administrador. O vendedor consulta preços e quantidades na mesma tela de stock, regista movimentos e cria vendas ou pedidos; o administrador consulta clientes e um resumo de operações e gere vendedores. As alterações recentes ainda precisam de validação no telemóvel.
- A base MySQL habitual permanece em V4. As migrações V5–V7 foram testadas numa cópia restaurada e numa base isolada; o procedimento e as limitações constam em [validacao-vendas.md](validacao-vendas.md). A base habitual não foi migrada.

## Lacunas para utilização real

- A autenticação continua provisória: faltam recuperação de acesso, limitação de tentativas, gestão completa de sessões, reforço e avaliação independente de segurança, e auditoria completa. HTTP Basic não deve ser usado sem HTTPS validado.
- A definição de cliente ativo ainda está pendente; o administrador vê a lista de clientes sem classificação de atividade. O backend ainda permite ao administrador gerir produtos, apesar da divisão de tarefas solicitada; é preciso definir quem mantém o catálogo. Não tratar a configuração atual de permissões como definitiva.
- O relatório do administrador é um resumo de estados e operações, não um relatório financeiro de recebimentos. Pagamento marcado como pago não comprova pagamento externo. Faltam meios de pagamento, parciais, reembolsos, devoluções e cancelamento de pedidos pagos.
- O resumo agrega dados no servidor, mas não possui filtro por período; os detalhes carregam todas as operações sem paginação, o que limitará o desempenho quando o histórico crescer. Os detalhes e o resumo são pedidos separados e podem refletir momentos diferentes.
- Os identificadores de reenvio de vendas e movimentos de stock existem apenas enquanto os respetivos formulários permanecem abertos. Uma interrupção da aplicação exige verificar os dados antes de criar outra operação; ainda não existem fila SQLite, sincronização offline ou resolução de conflitos.
- Os testes do backend em H2 e os cenários HTTPS/MySQL isolados não substituem testes de carga e concorrência abrangentes, recuperação de falhas ou validação completa no dispositivo. Os testes Flutter utilizam dados simulados.
- O APK de desenvolvimento usa chave de depuração; o projeto ainda não está preparado para distribuição ou operações reais.

## Regras de referência

- Valores monetários usam precisão decimal no servidor; o cliente envia preço e quantidade como texto decimal para não alterar o valor na serialização. O total mostrado antes da confirmação é indicativo e o backend rejeita preços desatualizados.
- Guardar um pedido pendente já o confirma e reserva stock; um formulário ainda não enviado não reserva. O cancelamento de pedido não pago liberta a reserva e a entrega não duplica a saída física.
- Os meios de pagamento previstos incluem numerário, M-Pesa, e-Mola e transferência; marcar uma operação como paga não comprova recebimentos externos.
- Se vier a existir operação offline, vendas com stock insuficiente devem permanecer em conflito, sem confirmação automática nem stock negativo, até resolução auditável.

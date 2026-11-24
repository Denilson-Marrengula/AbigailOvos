# Migração V9 e preservação de vendedores

A V9 cria uma reserva permanente para cada nome de utilizador existente, em minúsculas. Após a migração, novas contas também reservam o nome na mesma transação. Ao apagar uma conta de vendedor, as vendas e os movimentos antigos mantêm o nome registado e a reserva impede a reutilização. Esta regra só protege os nomes que foram reservados: é necessário investigar identificadores históricos sem conta antes da migração.

## Validação isolada em 11/11/2026

- Um MySQL 8.4.13 novo, temporário e ligado ao loopback recebeu apenas dados fictícios; não foi usada a base habitual nem a do Railway. As migrações V1 a V8 foram aplicadas e foram inseridos utilizador, venda, item e movimento de stock fictícios. A V9 foi aplicada e os dados e a reserva foram verificados.
- Numa segunda base temporária, nomes `Ana` e `ANA` foram permitidos propositadamente usando comparação binária na tabela anterior. A V9 foi recusada e as duas contas de origem continuaram presentes.
- **A falha não é uma reversão completa do esquema**: o DDL do MySQL não é transacional como no H2. Pode ficar uma tabela criada e uma entrada de migração falhada. Não assumir que basta executar novamente, nem executar `clean` ou `repair` como solução automática. Em caso de falha, suspender a atualização e seguir um plano de recuperação com cópia verificada.
- Flyway registou um aviso de que a versão disponível suporta oficialmente até MySQL 8.1; o teste pontual em 8.4 não elimina essa limitação. Testes de concorrência das contas foram feitos em H2, não constituem validação completa de concorrência em MySQL.

## Atualização do Railway de teste em 11/11/2026

Com autorização do utilizador, foi obtido um dump pela rede privada usando um serviço auxiliar temporário. O dump foi cifrado antes de sair do serviço; o serviço auxiliar e a chave SSH temporária foram removidos. A cópia final foi obtida com a API de teste parada, verificada, restaurada num MySQL local independente e migrada para V9 nesse restauro. Foram verificados três utilizadores, ausência de colisões e responsáveis históricos sem conta, preservação das tabelas anteriores e correspondência das reservas.

A V9 foi depois aplicada ao MySQL Railway de teste e o backend foi atualizado. As migrações automáticas foram desativadas após o arranque. Foram confirmados HTTPS, login administrativo e consultas de contas, produtos e relatório; as operações novas e a impressão continuam por validar no telefone. A cópia cifrada e as limitações da chave de restauro local estão descritas em [railway-test.md](../deploy/railway-test.md). Durante a pausa houve uma alteração da configuração regional da API, também registada nesse documento.

## Procedimento para futuras atualizações

1. Confirmar com o responsável o ambiente e uma janela de indisponibilidade. Só dados fictícios. Impedir novas gravações durante a cópia, verificação e migração; guardar a configuração da versão anterior sem expor credenciais.
2. Obter uma cópia de segurança consistente e protegida e **testar o restauro numa base independente**. Confirmar versão do esquema e que V1 a V8 validam; verificar que a V9 ainda não foi aplicada e que não há tentativas falhadas anteriores.
3. Analisar nomes inválidos ou diferentes apenas em maiúsculas/minúsculas. Uma verificação inicial é `SELECT LOWER(username), COUNT(*) FROM app_users GROUP BY LOWER(username) HAVING COUNT(*) > 1`. A reserva usa nomes ASCII válidos, por isso examinar separadamente eventuais nomes históricos introduzidos fora da aplicação.
4. Comparar os nomes de `sales.seller` e `stock_movements.administrator` com `app_users.username`. Se houver operações com responsáveis sem conta atual, não avançar até se decidir como preservar e reservar esses identificadores; V9 copia apenas contas existentes. Rever também outros identificadores históricos e a auditoria.
5. Depois de aprovados o plano e a cópia, testar a migração numa restauração independente da própria base de teste e verificar saldos, pedidos, vendedores e reservas. Só depois planear a aplicação controlada da V9 e a troca do backend. Em caso de falha, manter as gravações suspensas e avaliar o restauro; não sobrepor dados novos com uma cópia antiga.
6. Após a atualização, verificar com dados fictícios login, criação e edição de produto pelos dois perfis, movimentos de stock, eliminação com preservação de histórico e bloqueio de reutilização. Instalar o APK de teste separado e verificar o PDF e a impressão no dispositivo.

Este procedimento não autoriza futuras atualizações, não substitui uma política de backup/restauro e não torna o ambiente adequado a produção.

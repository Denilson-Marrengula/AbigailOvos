# AbigailOvos

Projeto de gestão de vendas, encomendas, clientes e stock de ovos. A stack decidida é Java 21, Spring Boot, Flutter, MySQL e SQLite. `backend/` e `mobile/` são estruturas iniciais; consultar `README.md` para comandos e limitações.

## Requisitos do domínio

- Uma aplicação Mobile Flutter para administradores e vendedores, com permissões específicas por perfil validadas pelo backend; a aplicação Web foi substituída.
- O stock central é partilhado por todos os vendedores e atualizado após a confirmação das vendas.
- Todos os vendedores consultam todos os clientes; movimentos administrativos não podem deixar o stock negativo.
- O Mobile deve permitir registar operações offline e sincronizá-las posteriormente.
- As encomendas devem ser acompanhadas desde o registo até à entrega; pagamentos, receitas e vendas fazem parte da gestão financeira.
- A aplicação inclui relatórios e dashboard de desempenho comercial e atividades dos vendedores. O sistema deve assegurar autenticação, proteção dos dados e auditoria das operações.
- Não existe atualmente base de dados anterior; preservar quaisquer dados futuros através de migrações controladas e cópias de segurança. Consultar `docs/primeira-fase.md` para requisitos e decisões pendentes.

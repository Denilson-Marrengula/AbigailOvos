# Ensaio de restauro com dados fictícios: guião preparado, não executado

**Estado: procedimento para aprovação.** Nenhuma exportação TiDB real, chave, tarefa agendada ou instância de restauro foi criada. Este guião serve para ensaiar a recuperação **antes** de existirem dados reais. Não restaurar sobre uma base ativa, não reutilizar credenciais operacionais e não apagar cópias ou contas ao terminar. A cópia automática Starter com retenção de um dia não substitui este ensaio. Ver [copias-disco.md](copias-disco.md) e [validacao-seguranca-copias.md](../../docs/validacao-seguranca-copias.md).

## 1. Condições para começar

- Autorização específica para criar uma instância de destino, confirmação da franquia e de eventuais custos.
- Instância de origem e de destino identificadas pelo nome e região; destino **vazio e independente**.
- Apenas dados fictícios na origem. Se a instância passar a conter dados reais, não repetir estes ensaios nela.
- Ferramentas com origem e versão fixadas e verificadas (`ticloud` ou alternativa aprovada, `age`, `age-keygen`, `tar`). Não instalar nem confiar numa ferramenta sem rever integridade.
- Chave de cifra de ensaio, sintética, guardada fora da pasta da cópia; a chave real ainda não foi gerada. Nunca usar a chave sintética fora do ensaio.

## 2. Antes da exportação — registar a origem

Preencher numa folha de ensaio, sem secretos:

| Campo | Valor observado |
| --- | --- |
| Identidade da instância/região e esquema de origem | |
| Hora de início e fim da exportação | |
| Lista de tabelas e contagem de linhas por tabela | |
| Histórico Flyway aplicado (versão mais alta e entradas) | |
| Número de contas, produtos, clientes, vendas, movimentos e eventos de auditoria fictícios | |
| Ferramenta, versão e hash verificados | |
| Identificador do snapshot, se a ferramenta o indicar | |

Uma contagem por tabela não prova integridade, mas deteta perdas evidentes após o restauro.

## 3. Exportar, cifrar e publicar o manifesto

1. Criar a exportação consistente do esquema correto, incluindo **todas as tabelas, esquemas e histórico Flyway**. O formato predefinido da CLI pode não ser suficiente; escolher e validar explicitamente.
2. Confirmar conclusão, identificador inequívoco e inventário completo de ficheiros e tamanhos. Detetar ficheiros ignorados, em falta, duplicados ou com tamanho inesperado. Não aceitar apenas o código de saída zero: a documentação consultada descreve downloads que podem terminar sem erro apesar de ficheiros ignorados.
3. Descarregar para uma pasta **nova e exclusiva**, sem reutilizar nomes. Não registar URLs com autorização temporária.
4. Cifrar e autenticar com `age` e chave sintética de ensaio; verificar os hashes das ferramentas, impedir ligações simbólicas e não apagar a origem em texto claro. O protótipo [Protect-LocalExport.ps1](backup/Protect-LocalExport.ps1) apenas faz esta etapa com dados fictícios.
5. Publicar o manifesto de sucesso **só depois** de exportação, inventário, download e cifra terminarem. Falha, ficheiro parcial, espaço insuficiente, disco ausente ou tempo excedido não podem marcar sucesso nem substituir a última cópia.
6. Guardar o hash local resultado. Um hash local não prova integridade da origem nem capacidade de restauro.

## 4. Restaurar no destino independente

1. Confirmar mais uma vez que o destino está vazio e que é o identificador correto.
2. Decifrar com a chave de ensaio e restaurar o conteúdo. Medir o tempo decorrido.
3. Recriar utilizadores e permissões: o fornecedor indica que o restauro de cópias Starter/Essential cria uma instância nova e **não repõe contas nem privilégios**. Não presumir que uma exportação os preserva. Usar contas de ensaio e privilégios mínimos; não copiar credenciais operacionais.
4. Verificar que a versão do esquema corresponde à esperada e que as migrações não são reaplicadas sobre dados existentes.
5. Comparar contagens e relações com a folha da secção 2: clientes, telefones normalizados únicos, produtos, vendas, itens, pagamentos, movimentos de stock, reservas e eventos de auditoria.

## 5. Verificar com a aplicação

- Arrancar o backend contra a base restaurada com variáveis de ensaio, migrações automáticas desligadas e inicialização de administrador desligada.
- Confirmar que as contas fictícias entram com palavra-passe, que CSRF e sessões funcionam e que um vendedor não acede a operações de outro vendedor.
- Num cenário fictício: criar venda com cliente novo, verificar reserva, entregar uma venda, marcar pagamento, registar entrada e perda de stock e confirmar que o saldo disponível nunca fica negativo. Reenviar o mesmo identificador de operação e confirmar que não duplica.
- Confirmar que os eventos de auditoria do ensaio foram gravados na mesma transação e que a consulta administrativa os apresenta.
- Antes de reabrir uma base restaurada em operação: manter servidores e gravações parados, confirmar a base correta, invalidar sessões de forma controlada com o operador preparado, verificar relógios e chaves. No ensaio, fazer isto apenas no destino isolado. O operador não foi autorizado nem ensaiado interativamente numa base existente.

## 6. Critérios de aceitação do ensaio

| Verificação | Resultado | Observação |
| --- | --- | --- |
| Exportação identificada e inventário completo | | |
| Cifra e manifesto publicados apenas após sucesso | | |
| Restauro em instância vazia e independente | | |
| Contas e permissões recriadas e verificadas | | |
| Esquema, migrações e contagens conferidos | | |
| Vendas, reservas, stock e auditoria verificados na aplicação | | |
| Sessões antigas invalidadas no destino isolado | | |
| Tempo de restauro medido e aceite | | |
| Falhas simuladas sem falso sucesso | | |

## 7. Paragem imediata se

- A instância de origem contiver dados reais ou importantes.
- A identidade da instância, do snapshot ou do destino não puder ser confirmada.
- O download ignorar ficheiros ou o inventário não fechar.
- A chave de cifra não estiver disponível de forma independente do disco da cópia.
- Um teste parecer "bem-sucedido" sem restauro verificado.
- Alguém propuser restaurar sobre a base ativa para resolver uma falha.

## 8. Depois do ensaio

Registar resultados, tempos, falhas e decisões sem credenciais. Não apagar a instância, a base, as cópias, as contas nem os registos automaticamente. Só depois de este ensaio passar e de os restantes controlos de segurança serem validados é que se pode pedir autorização para o piloto com dados reais.

# Preparação do agendamento e aviso no Windows

**Decisão:** uma cópia diária às **20:00 na hora local deste computador**, com aviso apenas no Windows. Este é um plano de implementação, não uma tarefa criada ou uma cópia funcional. Não ativar sobre uma base existente sem autorização e validação do restauro.

## Funcionamento previsto

1. Uma tarefa do Agendador de Tarefas inicia o futuro processo de cópia às 20:00. A opção de iniciar quando possível após uma execução perdida deve ser considerada, mas tem de ser ensaiada com o computador desligado e em suspensão; não se deve presumir que acordará a máquina ou que existirá internet.
2. O processo terá de impedir duas exportações simultâneas, identificar o snapshot e a instância corretos, proteger a área temporária, cifrar e só então publicar atomicamente um manifesto de sucesso. Não alterar o manifesto de sucesso se a exportação, transferência ou cifra falhar. O processo real TiDB e esse produtor do manifesto **ainda não existem**.
3. Depois de uma falha, o processo deverá apresentar o aviso local. Uma verificação independente também deverá ocorrer quando o utilizador Windows iniciar sessão, para avisar quando não houver uma cópia recente, incluindo depois de o computador ter estado desligado. Não apresentar o resultado da verificação de cabeçalho e hash como prova de restauro.
4. `Show-BackupAlert.ps1` é um protótipo para essa janela; apenas chama o verificador de manifesto, não cria a cópia. O utilizador não receberá email nem aviso no telefone. Se não houver sessão interativa ou se o próprio monitor, o Agendador ou o computador falharem, a janela pode não ser apresentada. Uma segunda cópia independente e verificação periódica continuam necessárias.

## Condições antes de criar tarefas

- Validar com dados fictícios exportação consistente e completa, fonte, formato, proteção do texto claro temporário, ferramentas, cifra, chave recuperável separada, espaço, integridade e restauro numa instância TiDB independente. O ficheiro `.age` sintético e o hash não provam a recuperação.
- Definir um diretório local protegido e conta Windows própria ou explicitamente autorizada. A tarefa de aviso tem de correr na sessão interativa correta; não confiar numa janela criada em sessão de serviço não interativa. Não colocar segredos em argumentos, XML de tarefa, histórico ou logs.
- Escolher e testar um mecanismo de exclusão mútua e de recuperação após bloqueio deixado por falha, sem apagar ou substituir ficheiros que possam conter dados importantes. A retenção e qualquer eliminação de cópias antigas continuam por aprovar.
- Testar falha de download, falta de espaço, processo interrompido, tarefa sobreposta, hora/relógio incorreto, computador desligado às 20:00, sessão Windows ausente, início tardio, alerta ao entrar e ausência de resposta do utilizador. Confirmar que falhas não substituem a última cópia e não produzem falso sucesso.
- Só depois dos testes e de nova confirmação explícita criar ou ativar tarefas neste computador. Registar os nomes, responsável, horário, localização e procedimento de desativação sem registar credenciais. Não se criou qualquer tarefa, nem se enviou email.

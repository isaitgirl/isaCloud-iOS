# Log por perfil: o que guardar para 12 h ou mais (19/11/2026)

**Estado:** implementado na branch `fix/c32-timeouts-e-log-longo` (build 118 no .dev). A lista completa está em `docs/log-perfil-12h-classificacao.csv` (uma linha por tipo de mensagem, com decisão, categoria, ocorrências e bytes).

## Como ficou
- Desligado por padrão (chave `IsaCloudLogLongo`, valor padrão registrado no `defaultsDB`). Só o dono liga, na tela de Depuração, com o período 2, 6, 12 ou 24 h; vale a partir da próxima abertura de cada processo.
- Formato: texto puro, uma linha por mensagem (`data hora L [proc] [fila] [classe] mensagem`), legível com `grep` e `awk`. Newlines viram ` ⏎ ` e cada linha tem no máximo 1500 caracteres.
- Sem compactação nos arquivos gravados nesta versão: 25 MB por arquivo, rotação a cada 24 h, até 40 arquivos ou 1 GB, em `Library/logs-long/{app,appex}/`. A compactação acontece só na exportação ("Compartilhar log longo", gzip).
- O rawlog continua igual e faz o papel do anel verbose de curto prazo.
- Limite de taxa: no máximo 40 linhas por segundo para cada texto; o excedente vira `[suppressed N lines of ...]`.
- Linha-resumo `LONGLOG 10s` a cada 10 s, com stanzas e gravações de transação descartadas e o total de linhas descartadas e mantidas.

## Base da medição
- Seis logs de produção de 19/11 (04:27 a 09:11 local, app e extensão juntos): 786 mil linhas, 617 MB, 715 tipos de mensagem (formato + classe de origem).
- Ritmo: cerca de 130 MB por hora, ou **1,5 GB em 12 h** no formato atual. Hoje a retenção é de 4 arquivos de 128 MB (`HelperTools.m:3214-3219`), ou seja, 1 a 2 h.

## Decisões e peso (fração dos bytes das 786 mil linhas)
| Decisão | Categoria | Peso | O que é |
|---|---|---|---|
| MANTER | informação (a revisar) | 2,1% | linhas info que não são de ciclo de vida/conexão/banco; lista abaixo |
| MANTER | conexão | 1,9% | `connect`/`disconnect`, caminho de rede, smacks, MAM, timeouts, "Sleeping" (com limite de taxa) |
| MANTER | medição | 0,8% | SPIN, registros do C20 e C30, atividade/memória, estado do push |
| MANTER | ciclo de vida | 0,7% | primeiro/segundo plano, congelar/descongelar, trava `MainApp`, tarefas de fundo, IPC, "ALL ACCOUNTS IDLE" |
| MANTER | banco | 0,6% | transações de escrita longas, checkpoint concluído, persistState lento, abertura/fechamento do banco |
| MANTER | aviso e erro | 0,4% | tudo em warn e error |
| RESUMIR | contador a cada 10 s | 23,2% | gatilhos de transação, persistState, "Synchronously handling", "Parse finished": viram **uma linha por 10 s** (stanzas, saves, saves pulados, fila de parse, tempo médio e máximo) |
| ANEL | ruído por stanza ou objeto | 65,3% | transações por stanza, filas de notificação, participantes de sala, KVO, I/O de rede por pacote, `_outputQueue` |
| ANEL | debug/verbose sem uso | 4,9% | o resto |

**Resultado:** o arquivo longo guarda cerca de **6,5% dos bytes mais as linhas-resumo**, ou seja, uns **100 MB brutos em 12 h** (cerca de **5 a 8 MB compactados**), contra 1,5 GB hoje. Daria para estender para 48 h.

## Principais mensagens que ficam fora do arquivo longo (vão para o anel de 10 a 20 min)
- `Running/Added transaction trigger` e `Inside transaction end trigger` (6,4% cada), `Would now call realPersistState` (6,2%).
- `Synchronously handling next stanza` (3,7%), `Queueing notification` e `Notifications in queue` (3,6% e 3,5%), `Parse finished for new <…> stanza` (3,0%).
- `Starting/Started/Ending/Ended transaction` (cerca de 2,7% cada) e `Freezing sendQueue`/`sendQueue is frozen` (cerca de 2,7% cada).
- `Adding participant`, `Got muc presence`, `Publishing participants list update` (2,3%, 2,2% e 2,1%).

## A revisar com você antes de implementar (info que hoje ficaria no arquivo longo)
Removing/Updating syncError notifications, Processing message stanza (delayedReplay), Handling members list update, Saving incoming message node, pubsub handlers, Refreshing contact, Updating unread (badge), SRV entries, "ping response received". Proposta: manter só as de syncError e as de ping/SRV; as demais vão para o anel.

## Regras de cuidado
- "Sleeping %f seconds because parse queue has…" é aviso, mas aparece milhares de vezes numa rajada: manter com **limite de taxa** (uma por minuto por conta, mais o total).
- Mensagens com dados pessoais (JIDs de participantes, ids de stanza, texto) ficam só no anel.
- Cada processo (app e extensão) aplica o mesmo perfil e escreve no mesmo diretório.

## Interruptor (proposta)
- Chave `IsaCloudLogLongo` no `defaultsDB` do grupo de apps, **desligada por padrão**. Ligada pela tela de Depuração; vale a partir da próxima abertura de cada processo (o log é configurado no início). Registrar valor padrão e migração antes da tela que a lê (lição do C18).
- **Desligada:** comportamento de hoje, sem nenhuma mudança para quem recebe pelo TestFlight.
- **Ligada:** perfil acima, rotação em 32 MB, compactação em fila de baixa prioridade fora do congelamento, retenção por tempo (12 h ou mais) e anel verbose de 2 × 32 MB.
- Depuração ganha um seletor de período para exportar (2 h, 6 h, 12 h), porque 12 h compactadas ainda podem ficar grandes para compartilhar.

# Canal leve: canais grandes por "pull", como o Telegram e os Canais do WhatsApp (24/11/2026)

Análise, sem código. O objetivo é este: **com o app em segundo plano, o celular recebe quase só o que importa (mensagem direta, menção e PM)**, e o resto dos canais grandes é buscado no arquivo (MAM) quando o app abre. Tudo continua compatível com o protocolo e com os outros clientes.

## Por que agora

- Em 24/11 a Isadora tirou a conta `isadora@xmpp.social.br` do app de produção. Era a conta que estava nos canais grandes, e com ela não dava para manter o app estável: crash de manhã, consumo de bateria e o app meio travado.
- A enxurrada de **presenças** foi resolvida no servidor em 20/11: fila do smacks em 5000 e compactação de presença no `mod_csi_battery_saver` (ver `docs/analise-trafego-canais.md`). As **mensagens** dos canais continuam chegando ao vivo, e cada uma acorda o app ou a extensão, passa pelo parse e grava no banco, inclusive de madrugada e com o iOS congelando o processo.
- Na prática, qualquer canal a partir de ~150–200 pessoas já gera volume demais para o modelo "push de tudo".

## Como os grandes fazem

- **WhatsApp:** grupo tem limite de ~1.024 pessoas. O que passa de um milhão são os **Canais**, que são de uma via e funcionam por **pull**: nada chega ao aparelho em tempo real; a aba busca o que mudou quando é aberta.
- **Telegram:** nos canais e supergrupos grandes o servidor não empurra cada mensagem para o aparelho inativo. O aparelho guarda um contador por canal e pede a diferença (`getChannelDifference`) quando abre o canal.
- **A regra dos dois:** conversa pequena é push, tudo em tempo real. Canal grande é pull: o servidor guarda e o aparelho busca quando abre.
- **XMPP clássico:** entrar na sala é receber tudo ao vivo, para sempre. O MIX (XEP-0369) traria o modelo do servidor guardando, mas não tem suporte no Prosody 13 de produção nem no Monal.

## A proposta

### Quais salas são "leves"

- **Pelo tipo, não pelo tamanho.** O padrão é: **canal** (sala aberta, o `mucType` "channel" do Monal) é leve; **grupo** (só para membros, `mucType` "group") continua push. É a mesma divisão que o `mod_cloud_notify_quiet` já usa (`muc_group` x `muc_channel`). Assim não depende de um número mágico de participantes: a sala de família continua ao vivo e qualquer canal público é leve.
- A pessoa pode trocar sala por sala (interruptor "Canal leve" na tela de detalhes).
- **Só pode ser leve uma sala com MAM** (`urn:xmpp:mam:2` nas features da sala, que o Monal já guarda em `_roomFeatures`). Sem arquivo, não há de onde buscar depois.
- **Vale para os canais federados também**, que hoje são o maior problema. O filtro roda no **nosso** servidor, na sessão do usuário, e não importa onde a sala mora. Só a busca depois depende do MAM da sala remota; Gajim, Prosody e Conversations têm.

### Servidor: o que muda (no `mod_csi_battery_saver`, na sessão de quem pediu)

1. **Ativação explícita.** Depois do bind, o app manda `<iq type='set'><enable xmlns='urn:xmpp:isacloud:muc-light:0'><room jid='...'/>…</enable></iq>` com a lista das salas leves. O servidor guarda a lista **na sessão**; ela sobrevive à retomada do smacks, porque o objeto da sessão é o mesmo, e é mandada de novo a cada sessão nova ou quando a lista muda.
   - O servidor anuncia a feature `urn:xmpp:isacloud:muc-light:0` no disco#info da conta. Sem a feature, o app não manda nada.
   - O Conversations, o Gajim ou outro aparelho na mesma conta não mandam o `enable` e continuam exatamente como hoje.
   - A lista não vai nos bookmarks: o Monal reescreve os bookmarks e poderia apagar uma extensão. Assim cada aparelho escolhe o seu.
2. **Com o cliente inativo (CSI) ou hibernado:** mensagem `groupchat` de sala leve que **não** é importante é **descartada**, em vez de ir para o buffer ou para a fila do smacks. Com o `csi_battery_saver_filter_muc = true` (ligado em 24/11), "importante" quer dizer que menciona o usuário ou o apelido dele na sala, ou que tem `subject`.
   - O descarte acontece no `session.send` do battery saver, **antes** da fila do smacks. Assim a fila não cresce, e o `mod_cloud_notify` não gera push para essas mensagens: ele dispara em `smacks-hibernation-stanza-queued`, e nada chega lá. Menos push quer dizer menos vezes que a extensão acorda.
   - Menção continua passando. Ela entra na fila e gera o push de alerta, que o quiet v3 já trata.
   - Também é descartado o resto do `groupchat` da sala leve: estado de digitação, marcador, reação, correção e retratação. As que importam ficam no MAM da sala e vêm junto na busca.
3. **Contador.** Por sala, o servidor conta as mensagens descartadas e guarda a hora da primeira. `<iq type='get'><deferred xmlns='urn:xmpp:isacloud:muc-light:0'/></iq>` devolve `{sala, desde, quantas}` e zera. Serve para a interface ("há mensagens novas") e para o log; não é a fonte da verdade da busca (ver abaixo).
4. **Presença** de ocupante da sala leve continua pela compactação que já está no ar, para a lista, o `@` e a contagem continuarem certos.
5. **Opções e medição**, no estilo do quiet: `csi_battery_saver_muc_light = true|false` (desliga tudo sem tirar o módulo), métrica `deferred_total{room_kind=local|remote}` e log por sessão em `info` só quando o `enable` chega.

### App: o que muda

1. **Interruptor e padrão.** Coluna nova por sala (padrão: canal com MAM é leve, grupo não), com migração e valor padrão antes da tela que a lê, para não repetir o C18. Texto novo com tradução pt-BR no override.
2. **Mandar o `enable`** depois do bind e das entradas nas salas, e de novo quando a lista muda, só se o servidor tiver a feature. A extensão de notificação manda a mesma lista, porque também é cliente inativo.
3. **Marcar o começo do buraco.** Ao mandar CSI inactive, o app grava `lightGapStart` (hora local, por conta) no banco. É isso que torna a busca robusta: ela não depende de o servidor lembrar a sessão, então funciona também depois de uma sessão nova, com o app morto, reiniciado etc.
4. **Buscar ao abrir, só no app principal e em primeiro plano** (a extensão nunca busca):
   - **Fase A (mais simples):** ao ficar ativo, para cada sala leve, uma consulta MAM `start = lightGapStart − 1 min`, paginada com RSM, uma sala de cada vez para não martelar servidores remotos, com deduplicação pelo `stanza-id` (o `checkForDuplicates` do `addMessageToChatBuddy:` já faz isso). Depois zera o `lightGapStart`.
   - **Fase B (pull de verdade):** busca só quando a pessoa abre o canal; na lista, o contador do servidor aparece como "N novas" até a busca. É o comportamento do Telegram.
5. **Não confiar no `lastStanzaId` da sala** para fechar o buraco: a menção que chegou ao vivo o atualiza, e a busca normal "depois do último id" pularia tudo o que veio antes dela. Por isso a busca é por horário (item 4).

## Riscos e como tratar

| Risco | O que acontece | Tratamento |
|---|---|---|
| **Ordem das mensagens** | O app ordena por `message_history_id` (ordem de inserção), não pelo horário. A menção que chegou ao vivo às 03:00 fica **antes** das mensagens de 01:00–02:59 buscadas de manhã. | **Decidido (Isadora, 24/11/2026): reinserir.** Na transação da busca, apagar e inserir de novo, na posição certa, as poucas mensagens da sala que chegaram ao vivo durante o buraco (só menções), preservando lida/não lida e reações. A alternativa, ordenar as salas pelo horário do servidor, ficou de fora por mexer em mais lugares do app. |
| **Sala remota sem MAM ou com retenção curta** | A busca não traz tudo. | Sala sem `mam:2` não pode ser leve. Se a resposta do MAM começar depois do `lightGapStart`, mostrar um divisor "algumas mensagens antigas não puderam ser carregadas". |
| **Buraco muito grande** (dias fora) | Milhares de mensagens por sala. | Limite por sala na fase A (ex.: 1.000, o resto pelo "carregar mais" que já existe); na fase B isso some, porque só busca ao abrir. |
| **Contador de não lidas** | Na fase A, o número só aparece depois da busca; com o app fechado, o ícone conta só mensagens diretas e menções. | Isso é desejado (é o que ela quer). Na fase B, o contador do servidor aparece na lista. |
| **Push de mensagem de canal** | Some para as salas leves (só menção avisa). | É o objetivo. O quiet v3 já fazia isso para salas remotas. |
| **Mensagem própria enviada de outro aparelho** | Também é `groupchat` da sala e seria descartada para este aparelho. | Vem na busca do MAM; não é importante em segundo plano. |
| **Servidor sem o módulo** (conta de outro provedor) | Sem a feature, o app não manda o `enable` e tudo fica como hoje. | Nada a fazer: o ganho é para contas dos nossos VirtualHosts (isacloud.im, xmpp.social.br, voz.social.br). |

### Como reinserir as menções (decidido em 24/11/2026; conferido no código)

"Reinserir" aqui quer dizer **dar um `message_history_id` novo** às poucas mensagens que chegaram ao vivo durante o buraco, depois de gravar as buscadas no MAM. Assim elas ficam no fim, na ordem do horário. Tudo numa transação só, por sala:

1. Separar as linhas da sala com `timestamp >= lightGapStart` que já estavam no banco antes da busca (as menções ao vivo).
2. Gravar as mensagens do MAM, em ordem, com `checkForDuplicates`, pulando as que já existem (as próprias menções).
3. Para cada menção separada, em ordem de horário: copiar a linha com um id novo (o próximo do `AUTOINCREMENT`), mover para o id novo as tabelas que apontam para ela e apagar a linha velha. O que aponta para `message_history_id`:
   - `filetransfer_info` e `reactions`, com chave estrangeira e `ON DELETE CASCADE`. Por isso a ordem é copiar, mover o `UPDATE ... SET message_history_id = novo` e só então apagar a velha; apagar antes levaria anexos e reações junto;
   - o índice de busca `message_search` (FTS5, `rowid` = id da mensagem, ver `MLMessageSearch.m`): remover o `rowid` velho e indexar o novo;
   - `buddylist.latest_read_message_history_id`: a lista de não lidas usa `id > latest_read AND unread = 1`. A menção já lida continua com `unread = 0` e não volta a contar; as mensagens do buraco entram com `unread = 1`;
   - as **notificações já entregues** guardam o id em `userInfo[@"historyId"]` (`MLNotificationManager.m`). A da menção movida precisa ser trocada pela do id novo, ou o toque nela não acha a mensagem.
4. **Respostas (XEP-0461, build 128) não quebram.** O vínculo é guardado como texto: a coluna `isacloud_quote_id` da resposta tem o `messageid`/`stanzaid` da original, e `historyIdOfQuotedMessageId:` acha o `message_history_id` na hora de mostrar (conferido em 24/11). Valem os dois sentidos:
   - uma resposta que cita a menção movida acha o id novo, porque a cópia mantém `messageid` e `stanzaid`;
   - a menção que é ela mesma uma resposta continua citando a original, porque a cópia leva a coluna `isacloud_quote_id`.

   Cuidados:
   - a cópia tem que levar **todas** as colunas, inclusive as do isaCloud (`isacloud_quote_id`). Fazer com `INSERT ... SELECT` listando as colunas da tabela, e não à mão;
   - se a conversa estiver aberta durante a busca, ela guarda os ids na memória (o brilho e o salto até a original): avisar a tela para recarregar depois da transação.

   **Bônus:** hoje, uma resposta ao vivo que cita uma mensagem do buraco aparece "sem vínculo"; depois da busca, a original existe e o vínculo se resolve sozinho.
5. **Menções XEP-0513 (planejadas):** a referência aponta para um trecho do corpo e um JID, não para o `message_history_id`. Não são afetadas.

Como só as menções do período são movidas (poucas por noite), o custo é pequeno. Nenhum id muda fora da sala e do buraco.

## Servidor: implementado (24/11/2026, sem commit no repo `isacloud-custom-plugins`)

Feito por um executor e revisado.

- **Onde:** `mod_csi_battery_saver.lua`, com os trechos marcados `-- isaCloud muc-light`.
- **O que tem:**
  - a feature `urn:xmpp:isacloud:muc-light:0` no disco#info da conta;
  - o `enable` (lista de salas da sessão; lista vazia desliga) e o `deferred` (`<room jid since count/>`, que zera os contadores);
  - o descarte no `session.send` do battery saver;
  - a métrica `muc_light_deferred{room_kind=local|remote}`.
- **Opções:** `csi_battery_saver_muc_light` (padrão `true`) e `csi_battery_saver_muc_light_max_rooms` (padrão 1000). Com `filter_muc` desligado, o módulo avisa no log, porque aí nada seria adiado.
- **Ajuste na revisão:** só mensagens de **ocupante** (`sala/apelido`) são descartadas. As mensagens da própria sala, sem apelido (mudança de configuração 104, moderação), continuam chegando.
- **Decisão sobre mensagens sem corpo:** `groupchat` de ocupante sem corpo (digitação, marcador, reação) também é descartada com o app inativo. É ruído em segundo plano, e reação, correção e retratação ficam no MAM da sala.
- **Testes:** harness com as libs do trunk (`scratchpad/csi-test/`):
  - `test_csi.lua`: 12 ok;
  - `test_light.lua`: 27 ok, cobrindo sem `enable`, as duas salas (local e remota), menção passando, sala fora da lista, `type=chat`, o `deferred` e a segunda consulta vazia, ativo entregando, lista vazia desligando, a mensagem da própria sala e as métricas.
- **Ativação:** subir o arquivo e rodar `module:reload("csi_battery_saver")`. Até um app mandar o `enable`, nada muda para ninguém: o módulo só anuncia a feature.

## App, fase A: implementada (24/11/2026, branch `feature/canal-leve`, sem commit)

Feita por executores e revisada; compila no simulador. Não testada no aparelho.

- **Onde:**
  - `DataLayerMigrations.m` (migração isaCloud 10);
  - `DataLayer` (configuração, intervalo e a troca de ids);
  - `xmpp.m` (`enable`, `deferred` e intervalo no CSI);
  - `MLMucProcessor` (a busca por sala e o fim do intervalo);
  - `ChatView.swift`, `MLNotificationManager.m` e `ContactDetails.swift` (o interruptor "Canal leve", com tradução pt-BR).
- **Ajustes na revisão:**
  - **App inativo de novo durante a busca:** o início do intervalo era mantido, e o fim da busca apagava o intervalo; o que o servidor adiou depois disso nunca era buscado. Agora o primeiro `inactive` com um intervalo aberto fica guardado, e o fim da busca abre um intervalo novo a partir dele, em vez de apagar. Se o app já estiver ativo, ele busca na hora.
  - **Sessão nova (sem retomada):** a lista de salas da busca dependia de saber se a sala tem MAM, o que só se sabe depois de entrar. Logo depois do bind, a lista vinha vazia e o intervalo era apagado antes de qualquer busca. Agora a busca usa as salas leves pela configuração:
    - uma sala que está entrando, ou ainda não entrou nos primeiros 2 minutos da sessão, segura o intervalo;
    - uma sala que nunca entra deixa de segurar depois disso;
    - sala sem MAM não tem o que buscar.
- **Achados no teste no `.dev` (24/11/2026, 15:40–16:20):**
  - **Retomada:** o app fica ativo antes de a conexão voltar, então a busca pulava. Agora ela roda também no fim da retomada (smacks resume).
  - **Abertura a frio:** o app ficava "inativo" para o servidor durante todo o primeiro uso, porque o atalho `nowForegroundedAtLaunch` só trocava as flags. Agora ele chama `setClientActive` em cada conta.
  - **Resultado:**
    - o servidor adiou mensagens dos canais leves (`muc_light_deferred` local e remoto);
    - ao abrir, a busca rodou em todos os canais leves das duas contas em cerca de 2 s, sem duplicar;
    - no conversations, 7 mensagens novas e 1 mensagem ao vivo movida para a ordem certa.
  - **Falta:** a noite no TestFlight, com push de menção, bateria e crash de manhã.

## Primeira noite no TestFlight (build 131, 24→25/11/2026)

Conta isadora@xmpp.social.br (id 47 no app de produção), 14 canais leves. Fonte: log longo `isacloud-log-longo-131-20261125-0837` e a métrica do servidor às 9h de 25/11.

- **Sem crash:** nenhum relatório de crash. O app foi suspenso limpo às 21:23 (lock liberado), o iOS o encerrou de madrugada, e ele abriu a frio às 03:56.
- **Pushes:** 33 entre 17:32 e 08:12, só 7 entre 21h e 8h. A extensão iniciou 1 vez entre 22h e 7h.
- **Buscas:** cada abertura buscou os 14 canais em 2 a 6 s. Por exemplo, 516 mensagens novas às 19:42, 165 às 03:56 e 875 às 08:16, sem duplicar.
- **Servidor:** 366 mensagens descartadas no xmpp.social.br (230 de salas remotas, 136 locais) desde o reload.
- **Furo no servidor: `<markable/>`.**
  - **O que acontece:** o `is_important` dá "importante" a toda mensagem com o namespace `urn:xmpp:chat-markers:0`, e esse teste vem antes da regra de `groupchat`. O `<markable/>` é só um pedido de recibo, mas Conversations, Gajim e outros o põem em mensagens comuns de canal.
  - **Efeito:** essas mensagens não são descartadas. Elas esvaziam a fila e acordam o aparelho por push.
  - **Medido:** as 57 mensagens de canal leve que chegaram enfileiradas com o app inativo tinham `markable`. Foram 34 no guiaxmpp, 11 no gajim, 10 no conversations e 2 no commteam. Na amostra do MAM, 84% das mensagens do gajim e 71% das do commteam têm `markable`.
  - **Correção proposta:** nas salas leves, decidir a importância por uma regra própria de canal, que ignora `markable` e marcadores: assunto, convite, menção (usuário ou apelido) e mensagem cifrada. O resto é descartado e contado.
- **Busca repetida no app.**
  - **O que acontece:** o `isaCloudNoteClientInactive` guarda o "inativo durante a lacuna" mesmo quando nenhuma busca está rodando. Isso acontece, por exemplo, quando o app acorda em segundo plano com a lacuna aberta.
  - **Efeito:** no fim da busca seguinte, o app busca de novo a partir dessa hora. Às 08:16 houve uma segunda busca desde as 04:22. Não duplica nada, mas repete consultas ao MAM.
  - **Correção proposta:** só guardar se a busca já começou em alguma sala (`_isaCloudGapStartedRooms` ou `_isaCloudGapDoneRooms` não vazios). Antes disso, o início da lacuna já cobre o momento.
- **Pequeno:** 3 consultas `deferred` voltaram com erro (`(null)`), ao acordar em segundo plano. Não afetam a busca, que usa o MAM.

## Teste das correções no `.dev` (25/11/2026, 9h35 às 10h52)

As três contas foram usadas: 1 = poli@isacloud.im, 2 = poli2@isacloud.im e 5 = isadora@xmpp.social.br, esta com 14 canais leves.

- **App, busca repetida: corrigida.**
  - Nos 7 despertares em segundo plano, as três contas registraram "no fill running, the gap start covers it".
  - Ao abrir às 10:51, cada conta fez uma única busca desde 09:37. Vieram 568 mensagens no development, 54 no guiaxmpp e 40 no conversations, em uns 25 s.
- **"enable/deferred got an error: (null)" não é erro.**
  - O app congela antes de a resposta chegar e o tratador expira.
  - O servidor respondeu depois: às 10:16:58, "enable answered (result) after 494628 ms".
- **Servidor: o reload não tinha sido feito.** O log do Prosody não tem "Unloading module" nem "Successfully loaded module". As 6 mensagens com `markable` que ainda passaram vêm do código antigo, então o teste do markable fica para depois do reload.
- **Retomadas recusadas na conta 5 do `.dev`.**
  - **O que aconteceu:** 4 retomadas seguidas recusadas a partir das 10:16, com "Too many unacked stanzas remaining".
  - **A primeira:** a sessão entrou nos 14 canais grandes às 9h35, no meio da tarde europeia. Com o código antigo, cada mensagem com `markable` esvazia a fila do CSI na fila do smacks.
  - **Depois, um ciclo:** cada despertar abre sessão nova e entra de novo nos canais. A presença 110 libera a lista de ocupantes de cada sala e enche a fila outra vez.
  - **Em produção:** o app não teve nenhuma recusa à noite (142 retomadas).
  - **O que acompanhar:** se o ciclo continua depois do reload com o código novo. Se continuar, a próxima peça é não liberar a lista de ocupantes de sala leve no 110 enquanto o app está inativo.
- **Risco do reload, corrigido antes de fazê-lo.** O `module.unload` tirava o filtro de todas as sessões, e o reload só o recolocava no próximo `<inactive/>`. Agora o módulo o reinstala ao carregar nas sessões com `session.state == "inactive"`. Teste em `scratchpad/csi-test/test_rearm.lua`: 6 ok, mais os 36 do canal leve e os 12 da compactação.

## Custo estimado

- **Servidor:** ~150–200 linhas de Lua no `mod_csi_battery_saver`: o `enable` e o `deferred` por IQ, o descarte no `session.send` que já existe e a métrica. Dá para testar com o mesmo harness de 20/11 (`scratchpad/csi-test/test_csi.lua`).
- **App, fase A:** a coluna e o interruptor, o `enable`, o `lightGapStart` e a busca ao ficar ativo, com a correção da ordem. Uns poucos dias.
- **App, fase B:** contador na lista e busca só ao abrir. Depois da fase A, se ela incomodar.

## Como medir

1. Ligar o módulo no servidor; pelo log, só a sessão do app isaCloud com o `enable` é afetada.
2. Recolocar a conta do xmpp.social.br no iPhone com 2 ou 3 canais grandes marcados como leves; deixar uma madrugada.
3. **Rawlog de manhã:** `groupchat` recebidas com o app inativo, por sala (as leves devem estar perto de zero, fora menções); quantas vezes a extensão iniciou (pushes); `<failed>`, `<enabled>` e `<resumed>` do smacks.
4. **Servidor:** a métrica `deferred_total` e os pushes do quiet.
5. **Aparelho:** nenhum `.ips` do app ou da extensão; a bateria nos Ajustes (uso em segundo plano do isaCloud); ao abrir, os canais completos, na ordem certa, e a lista de participantes certa.

## O que foi conferido para escrever isto

- `MLMucProcessor.m`: a busca no MAM da sala na entrada (`queryMamCatchupForMuc:afterStanzaId:`, ou pelo horário com `setMAMQueryAfterTimestamp:`) e o `lastStanzaIdForMuc`.
- `DataLayer.m`: a tela da conversa lê as mensagens por `ORDER BY message_history_id`, e `addMessageToChatBuddy:` já tem `checkForDuplicates`.
- `mod_cloud_notify.lua` (trunk): o push para sessão hibernada sai do `smacks-hibernation-stanza-queued`.
- `mod_csi.lua`: o estado fica em `session.state`.
- `mod_csi_battery_saver.lua` (o nosso, com a compactação de 20/11): o `filter_muc` decide menção pelo usuário ou pelo apelido na sala (`track_muc_joins`).

## Teste com o código novo no servidor (25/11/2026, 11:49 às 12:29)

O arquivo do módulo no servidor foi conferido: 515 linhas, o mesmo hash do repo e o `is_light_important`. No reload das 11:49:35, o filtro voltou em 264 sessões inativas: 142 no isacloud.im, 76 no xmpp.social.br e 31 no voz.social.br, entre outras.

- **Nenhuma mensagem de canal leve passou** com o app inativo nas 3 contas do `.dev`: nem com corpo, nem `markable`, nem `displayed`. O detector continua achando as 1.022 presenças que o servidor segurou, então não é falha dele.
- **Retomadas:** a xmpp.social.br retomou a sessão nos 4 despertares, sem nenhuma recusa por "Too many unacked".
- **Busca ao abrir (12:27):** uma por conta, em 6 s. Vieram 152 mensagens no ia, 74 no guiaxmpp, 68 no support e 67 no conversations, sem nenhuma movida.
- **Métrica no fim:** 370 remotas e 213 locais no xmpp.social.br; 364 locais e 14 remotas no isacloud.im.
- **Pendente no repo `isacloud-custom-plugins`:** commit da reinstalação do filtro ao carregar. O arquivo já está no ar.

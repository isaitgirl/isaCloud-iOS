# Tráfego de canais e o spinner ao abrir o app (17/11/2026)

Medição feita nos logs do iPhone da Isadora em 17/11/2026 (06:52–08:43, 4 rawlogs do app).
O ponto de partida foi a queixa de que, ao abrir o app e mandar uma mensagem ou foto, o spinner fica girando por muitos segundos.

## O que os números mostram

### O tráfego é quase todo presença, e quase todo de canais federados

| Tipo | Quantidade |
|---|---|
| Presenças de MUC | 9.888 |
| Mensagens de grupo ao vivo | 167 |
| Mensagens de grupo atrasadas (catch-up) | 99 |

97% do tráfego das salas é presença (entra, sai, muda status). As salas que mais mandam presença:

| Sala | Presenças |
|---|---|
| support@conference.monocles.eu | 3029 |
| conversations@conference.siacs.eu | 1902 |
| guiaxmpp@conference.isacloud.cc | 1663 |
| gajim@conference.gajim.org | 782 |
| monal@chat.yax.im | 503 |
| prosody@conference.prosody.im | 451 |
| rede-soberania-digital@canais.xmpp.social.br | 438 |
| commteam@muc.xmpp.org | 409 |
| ia@conference.isacloud.cc | 223 |
| monal-alpha@chat.yax.im | 158 |

98% dessas presenças (9.896) chegam pela conta do **xmpp.social.br**. Só 180 chegam pela conta do im.isacloud.cc.
Isso importa: o que muda no servidor só vale para a conta do servidor onde a mudança roda.

### O catch-up é rápido. O que demora é a fila de presenças

Abertura das 08:03:05:

- A sessão foi **retomada** (Stream Management `<resumed>`), não houve reentrada nas salas.
- O catch-up do MAM terminou em 3 s numa conta e em 7 s na outra (08:03:08 e 08:03:12).
- O servidor despejou o que guardou enquanto o app estava suspenso: 442 presenças em 08:03:09 e 619 em 08:03:10.
- A partir de 08:03:18, a fila de entrada (`_parseQueue`) ficou **cheia, com ~257 itens, sem esvaziar** até o app voltar para o fundo (08:03:42). Na abertura das 08:11:30 aconteceu igual.
- Nesse período o app processou só **~7 presenças por segundo, ~130 ms cada**.

Em 20 s de fila cheia (08:03:20–08:03:40) foram 144 presenças recebidas, 292 transações de banco e 1.454 linhas de `realPersistState`.
Cada stanza recebida vira uma transação própria: `freezeSendQueue`, processamento, `persistState` (serializa o estado inteiro da conta) e gravação no SQLite.

### Por que isso trava o envio

A fila de entrada é FIFO, uma stanza de cada vez. Tudo o que o envio precisa esperar entra no fim dessa fila:

- **Foto:** o app pede um slot de upload (IQ, XEP-0363). A resposta só é tratada depois das ~257 presenças da frente, o que dá **~30 s** a 130 ms cada.
- **Texto:** a mensagem sai, mas a confirmação do servidor (`<a/>` do Stream Management) e o eco do MAM também esperam a fila. Por isso o relógio/spinner fica girando.
- Durante cada transação o `freezeSendQueue` segura a fila de saída, então até o envio em si espera a stanza atual terminar.

Em resumo: o spinner é o app digerindo um backlog de presenças de canais federados, uma por uma, com uma gravação completa de estado em cada.

## O que fazer, em ordem de efeito

### 1. No app: não gravar o estado inteiro a cada stanza (o maior ganho)

A 130 ms por presença, o gargalo é nosso.
Hoje `persistState` roda depois de cada stanza para guardar o contador `h` do Stream Management.

- **Agrupar as gravações:** gravar o estado no máximo a cada ~1 s, ou a cada N stanzas, e sempre ao ir para o fundo.
  Se o app morrer no meio, o servidor reenvia o que não foi confirmado. Presença repetida é inofensiva e mensagem repetida já é descartada pelo stanza-id.
- **Presença de MUC sem transação própria:** para presença, que só atualiza a lista de participantes, não congelar a fila de saída nem chamar `persistState`.
- **Respostas na frente da fila:** IQ `result`/`error` de pedidos que o próprio app fez (upload, por exemplo) passam na frente das presenças.

Com só a primeira mudança, a expectativa é ir de ~7 para centenas de presenças por segundo, e o backlog some em poucos segundos.
É uma mudança delicada no núcleo do Monal (`xmpp.m`, `persistState`/`realPersistState`). Precisa de análise própria antes de mexer.

### 2. No app: menos presença dos canais grandes

- Opção por sala de **não entrar em segundo plano** ou de sair dos canais federados grandes quando o app fica muito tempo no fundo.
  Ao abrir, entra pedindo só o histórico que falta (`<history maxstanzas='0'/>` e MAM).
- É mais trabalho e muda o comportamento visível (a lista de participantes demora a aparecer). Fica para depois do item 1.

### 3. No servidor: o mod_cloud_notify_quiet

Arquivo: `isacloud-custom-plugins/share/lua/5.4/mod_cloud_notify_quiet.lua` (v2, 28/10/2026).
Ele resolve **push**, não presença: decide o que vira notificação, o que vira push silencioso e o que é descartado.
O push silencioso (`content-available`) acorda o app em segundo plano, que reconecta e faz catch-up inteiro. Nos logs, isso aconteceu às 08:14:24, 08:14:48, 08:32:38, 08:33:04 e 08:42:42.
Menos push silencioso significa menos acordadas e menos crashes de suspensão (C20, C28, C30).

Lembrete: o módulo só age nas contas do servidor onde está carregado. Para a conta do xmpp.social.br, que recebe quase todo o tráfego, só vale se ele rodar lá.

#### 3a. Salas de outros servidores: hoje toda mensagem vira alerta

Em `classify_groupchat`, quando a sala não é local (`get_room` devolve `nil`), o módulo devolve `"important"`.
Resultado: **toda mensagem com corpo de qualquer canal federado vira notificação com som**.

Proposta: tratar a sala remota como canal e alertar só em menção, descobrindo o apelido pelos marcadores (PEP, `urn:xmpp:bookmarks:1`).

```diff
@@ opções
 local muc_group_policy = muc_option("cloud_notify_quiet_muc_group", "alert");
 local muc_channel_policy = muc_option("cloud_notify_quiet_muc_channel", "mentions");
+-- salas de outros servidores: não dá para saber se é grupo ou canal
+local muc_remote_policy = muc_option("cloud_notify_quiet_muc_remote", "mentions");
+
+local xmlns_bookmarks2 = "urn:xmpp:bookmarks:1";
+local mod_pep = module:depends("pep");
+
+-- Apelido que a pessoa usa na sala, pelos marcadores (XEP-0402), ou nil.
+local function bookmark_nick(user_bare, room_jid)
+	local username, host = jid.split(user_bare);
+	if not username or host ~= module.host then return nil; end
+	local ok, service = pcall(mod_pep.get_pep_service, username);
+	if not ok or not service then return nil; end
+	local ok_items, items = service:get_items(xmlns_bookmarks2, true, { room_jid });
+	local item = ok_items and items and items[room_jid];
+	local conference = item and item:get_child("conference", xmlns_bookmarks2);
+	return conference and conference:get_child_text("nick") or nil;
+end
```

```diff
@@ local function classify_groupchat(stanza)
 	if not room then
-		return "important"; -- sala de outro servidor: sem como saber, alerta
+		if muc_remote_policy == "alert" then return "important"; end
+		if muc_remote_policy == "background" then return "muc-quiet"; end
+		-- "mentions": criptografado não dá para ler, então alerta
+		if is_encrypted(stanza) then return "muc-mention"; end
+		local room_jid = jid.bare(stanza.attr.from);
+		local nick = bookmark_nick(jid.bare(stanza.attr.to), room_jid);
+		if nick and jid.resource(stanza.attr.from) == nick then
+			return "muc-self"; -- eco de mensagem minha mandada por outro aparelho
+		end
+		-- is_mention só usa room.jid
+		if is_mention(stanza, { jid = room_jid }, nick) then
+			return "muc-mention";
+		end
+		return "muc-quiet";
 	end
```

Sem marcador com apelido, ainda funciona a menção por referência ao JID (XEP-0372).
Conferir no Prosody 13: a assinatura de `service:get_items(node, actor, ids)` em `util/pubsub.lua` e se `true` como `actor` passa nas permissões. Se der trabalho, ler direto do store `pep_urn:xmpp:bookmarks:1`.

Para grupos pequenos federados em que se quer alerta de tudo, a pessoa usa o padrão `"alert"` na opção nova.

#### 3b. Mensagem comum de canal: descartar em vez de push silencioso

Hoje `muc-quiet` vira `background`, ou seja, acorda o app a cada mensagem de canal.
Não precisa mexer no código; basta a opção que o módulo já lê:

```lua
cloud_notify_quiet_actions = {
	["muc-quiet"] = "drop";
}
```

Efeito: o contador de não lidas do canal só atualiza quando o app abrir, o que já acontece hoje na prática.
Grupos (`muc_group = "alert"`) não passam por `muc-quiet`, então continuam iguais.

#### 3c. Limitar push silencioso por aparelho

Mesmo com 3b, sobram silenciosos de recibo de leitura, reação, correção, eco de mensagem minha etc.
Proposta: no máximo um silencioso a cada 2 minutos por registro de push. Os que têm pressa ficam de fora.

```diff
@@ opções
+local background_cooldown = module:get_option_period("cloud_notify_quiet_background_cooldown", "2 minutes");
+-- limpam notificação ou encerram chamada: não podem esperar
+local cooldown_exempt = module:get_option_set("cloud_notify_quiet_cooldown_exempt",
+	{ "read-marker", "retract", "call-signal" });
+local last_background = {}; -- [jid .. node] = os.time() do último silencioso
```

```diff
@@ local function handle_push(event)
 	elseif action == "background" then
+		if background_cooldown > 0 and not cooldown_exempt:contains(reason) then
+			local key = tostring(event.push_info.jid) .. "\0" .. tostring(event.push_info.node);
+			local now = os.time();
+			if (last_background[key] or 0) + background_cooldown > now then
+				metric_decisions:with_labels("drop", "cooldown"):add(1);
+				event.reason = "isaCloud quiet filter: cooldown";
+				return true;
+			end
+			last_background[key] = now;
+		end
 		to_background(event);
 	end
```

A métrica de decisões (`cooldown`) mostra quanto foi cortado.
A tabela `last_background` cresce com os registros e só zera no reload. Se pesar, trocar por `util.cache` com tamanho fixo.
O ideal é medir antes com `cloud_notify_quiet_dry_run = true` e as métricas.

#### 3d. Presença nas salas do próprio servidor

Vale para guiaxmpp e ia (`conference.isacloud.cc`), que juntas deram 1.886 presenças.

- `muc_room_default_presence_broadcast` (repassar só a presença de moderadores): **descartado** em 17/11/2026.
  Os participantes precisam ver quem está no canal.
- `mod_csi_battery_saver` (já está nos plugins): enquanto o app está inativo, guarda só a última presença de cada participante.
  Nos logs a repetição foi pequena (93 de 849 no pico), então ajuda pouco no caso medido. Não é prioridade.

## Resumo

| Mudança | Onde | O que resolve |
|---|---|---|
| Agrupar `persistState` e tirar presença da transação | App | O spinner (o maior ganho) |
| Resposta de IQ na frente da fila | App | Upload de foto preso atrás das presenças |
| Sala remota alerta só em menção (3a) | Módulo | Notificação de toda mensagem de canal federado |
| `muc-quiet` = drop (3b) | Config | App acordando a cada mensagem de canal |
| Limite de silencioso (3c) | Módulo | Acordadas repetidas em seguida |

Nada disso foi implementado. Os diffs do módulo são sugestão para revisar e testar com `dry_run`.

## Análise do persistState (17/11/2026)

### Onde vão os 130 ms de cada presença

Um segundo da fila cheia (08:03:25, conta do xmpp.social.br), por presença:

| Etapa | Tempo |
|---|---|
| Processar a presença (`processPresence`, banco) | ~11 ms |
| `realPersistState` no fim da transação | ~60 ms |
| `realPersistState` de novo, depois de soltar as notificações | ~60 ms |

Cada gravação serializa **111 KB** de estado (30 stanzas sem confirmação, 28 handlers de IQ, features em cache, OMEMO...).
São **duas gravações completas por presença**: uma pelo gatilho dentro da transação (`persistState` chamado no processamento) e outra pelo `[self persistState]` que o laço de parse (`prepareXMPPParser`) chama depois de `queueNotificationsInBlock`.
Ou seja, ~90% do tempo de cada stanza é gravar o estado.

### Por que o freio que já existe não pegou

O build 109 já tem `isaCloudPersistStateThrottled` (no máximo uma gravação por segundo), mas só liga quando
`!_catchupDone && self.inCatchup.count > 0`.

- `inCatchup` só tem itens no catch-up por **MAM**, que acontece quando a sessão não é retomada.
- Hoje a sessão foi **retomada** (Stream Management). O que chega é o reenvio do que o servidor guardou, e `inCatchup` ficou vazio o tempo todo (`{}`), mesmo com `_catchupDone = NO`.
- Resultado: o freio nunca ligou e cada presença gravou o estado duas vezes.

### Mudança proposta (pequena)

Ligar o freio também quando há fila acumulada, não só no catch-up por MAM:

```objc
//isaCloud: also throttle while the smacks replay after a resume (or any backlog) is being processed
BOOL catchingUp = !self->_catchupDone || [self->_parseQueue operationCount] > 4;
```

O `_parseQueue` é acessado de outra fila; `operationCount` é só leitura e serve como sinal aproximado.

- As gravações forçadas continuam iguais: desconexão, socket fechado, fim do catch-up, app indo para suspensão (`isaCloudSuspendedFast`), e o timer de 1 s grava o que ficou pendente.
- A segunda gravação por stanza cai no mesmo freio (menos de 1 s depois da primeira), então some sem mexer no laço de parse.
- **Risco:** se o app morrer entre gravações, o contador `h` salvo fica até 1 s atrás. Na retomada o servidor reenvia essas stanzas: presença repetida é inofensiva, mensagem repetida é descartada pelo id. É o mesmo risco já aceito no catch-up por MAM.
- **Expectativa:** de ~7 para ~80 presenças/s (só os ~11 ms de processamento), e o backlog de ~250 cai de ~35 s para ~3 s.

Um segundo passo, se ainda precisar: diminuir os 111 KB (por exemplo, não serializar `cachedStreamFeatures` e handlers que não mudaram). É mais invasivo e fica para depois de medir o primeiro.

## MAM dos canais só ao abrir (avaliação)

Pergunta: dá para ter só o contador de não lidas dos canais e buscar as mensagens quando a pessoa entra no canal?

### Como é hoje

- O MAM do canal só roda quando o app **entra de novo na sala** (sessão não retomada). Busca tudo depois do último stanza-id salvo, limitado pela janela de histórico do canal (padrão 7 dias), em páginas.
- Na sessão retomada, como hoje de manhã, não há MAM de canal nenhum: o atraso foi o persistState.
- Rolar para cima no chat já busca páginas antigas (`setMAMQueryMostRecentForContact:before:`).

### Dá para fazer

1. **Contador sem baixar mensagens:** ao entrar na sala, em vez do catch-up, uma consulta MAM depois do último stanza-id com `<max>0</max>`. O servidor responde só o total (RSM `<count>`).
   O Prosody devolve o total sempre que `max = 0` (`mod_muc_mam.lua`: `total = use_total or qmax == 0`), e o ejabberd também.
   O número vai para um campo novo de "não lidas no servidor" do canal, mostrado na lista.
2. **Ao abrir o canal:** buscar a página mais recente (`before` vazio, ~30–50 mensagens) com o aviso "Carregando…".
   Rolar para cima busca a página seguinte com o código que já existe.
3. **O buraco:** entre o último stanza-id salvo e a página baixada fica um intervalo que o banco do Monal hoje supõe contínuo.
   Precisa de um marcador de "lacuna" por canal: rolar até ele busca para trás até encostar no histórico local, e aí o marcador some.

### Cuidados

- **Menções:** sem baixar as mensagens, o app não sabe se alguém citou você. Para canais do isaCloud, o push de menção do servidor cobre. Para canais federados, só se o servidor da conta também filtrar.
- **Leitura entre aparelhos (XEP-0490):** o marcador de "lido até" vem por PEP, então o contador pode ser calculado a partir dele.
- **Grupos** continuam com o catch-up completo; isso é só para canais.
- O ponto 3 mexe no modelo de histórico (DataLayer e o chat em SwiftUI). É a parte cara.

### Recomendação

Fazer primeiro a mudança do persistState: é pequena e ataca o spinner medido hoje.
O MAM sob demanda melhora a abertura depois de muito tempo fora (sessão não retomada) e reduz banco e bateria, mas é uma frente própria, com o marcador de lacuna como maior trabalho.
Um meio-termo barato: manter o catch-up, mas com limite de quantidade (só as últimas ~50 mensagens, além da janela de dias) e o marcador de lacuna só quando passar disso.

## Resultado (build 115, 17/11/2026)

A mudança do freio foi aplicada (`!_catchupDone || parseQueue > 4`), com as medições `isaCloud SPIN:`.
No `.dev`, em três aberturas depois de segundos ou minutos no fundo:

| | Build 114 (manhã) | Build 115 (.dev) |
|---|---|---|
| Fila acumulada ao abrir | ~257, sem esvaziar por ~35 s | 5 a 44 stanzas, esvaziou em 0,0 a 0,3 s |
| Pedido de upload | atrás da fila (~30 s) | 45 a 113 ms |
| Confirmação de mensagem | atrás da fila | 115 a 502 ms |

Falta conferir uma abertura depois de horas no fundo (milhares de presenças) e no 5G.
As medições ficam em Depuração → Logfiles → "Medições de desempenho" e em `Library/isacloud-spin.log` (puxar com `devicectl ... --domain-type appGroupDataContainer --source Library/isacloud-spin.log`).
O limite de ~50 mensagens no catch-up dos canais e o MAM sob demanda continuam só analisados.

## Como o WhatsApp lida com isso, e o MIX (17/11/2026)

O WhatsApp não fica dentro dos limites do iOS por mágica: ele **não mantém conexão em segundo plano**.
- Em segundo plano só chega push (APNs); o servidor guarda as mensagens e, ao abrir, o app conecta e puxa a fila do usuário.
- Grupo não é sala: o cliente não entra no grupo nem recebe presença de cada participante. O servidor guarda a lista de membros e distribui a mensagem. A lista só é buscada quando a pessoa abre o grupo.
- "Online" e "digitando" só chegam para a conversa aberta.
- Chamadas usam PushKit com CallKit.

O problema do XMPP em canais grandes é o MUC (XEP-0045), que repassa a presença de cada participante a todos.
**MIX (XEP-0369)** foi feito para isso (lista de membros no servidor, via PEP, sem presença por participante), mas está **Experimental, na versão 0.14.6, sem revisão de conteúdo desde 01/12/2020** (conferido em xmpp.org em 17/11/2026). Só serviria em salas nossas, com clientes que falem MIX; não ajuda nos canais federados.

## Proposta: `mod_muc_presence_quiet` (não implementada)

Módulo Prosody no estilo do `cloud_notify_quiet` (`dry_run`, log por decisão, métrica de decisões), para reduzir a presença de sala **entregue ao usuário**. Não mexe no que os outros participantes veem do usuário (a ideia de `muc_room_default_presence_broadcast` com só moderadores foi descartada por isso).

### Por que no servidor de casa do usuário

- A presença de sala chega ao usuário pela rota `presence/full`. Descartar ali, **antes da fila do Stream Management**, também esvazia a fila de hibernação, e some a enxurrada ao abrir o app (1.000+ presenças em 2 s em 17/11/2026).
- O `mod_csi_battery_saver` do isaCloud só **segura** a presença de sala enquanto o app está inativo (fila de até 256) e solta tudo ao ficar ativo; não remove nada. E remover repetidas ajuda pouco: no pico, 756 de 849 presenças eram de pessoas diferentes (~11% de repetição).
- Vale para as contas dos VirtualHosts do isaCloud: `isacloud.im`, `xmpp.social.br` e `voz.social.br` são todos do mesmo Prosody (correção de 20/11/2026: a conta do xmpp.social.br, com 98% das presenças, **também é nossa**).

### Regra

Passam: presença do próprio usuário (código 110, que o app usa para saber que entrou na sala), erros e remoções (kick, ban), moderadores e admins, e quem **falou na sala** dentro de uma janela configurável (o módulo vê as mensagens do grupo passando por `message/full`). O resto é descartado: entrada e saída de quem só lê.

Opções previstas: `muc_presence_quiet_window` (janela de "quem falou", por exemplo 7 dias), `muc_presence_quiet_min_rate` (só ligar para salas com muita rotatividade, por exemplo mais de 50 presenças/hora), lista de salas excluídas e `dry_run`. Salas locais pequenas e grupos (members-only, não anônimos) ficam de fora.

### Efeito no app (conferido no código)

- **`@` de menção:** `mentionNicks()` em `ChatView.swift` usa `getMembersAndParticipants` e filtra só quem está `online`, e quem marca `online` é a presença. Com o módulo, o `@` sugeriria só quem fala ou modera. Digitar o nick de quem não aparece continua funcionando (a menção do app é texto).
- **Contagem ao lado do nome do canal** (`mucPersonCount`, `countMucPersons`): conta os participantes registrados no banco, então cairia de centenas para as dezenas de quem fala. Enganaria quem lê como "quantas pessoas estão no canal".
- **Lista de participantes** do canal: ficaria só com quem fala e modera.
- **Grupos:** sem mudança, porque ficam de fora do filtro.

### Ajustes para reduzir o efeito

1. Janela de "quem falou" maior (7 dias).
2. No app, usar o total de ocupantes que a sala informa (`muc#roominfo_occupants`) na contagem, em vez de contar o que está no banco. Mudança pequena, mas no app.
3. Ligar só para salas com muita rotatividade.

### A conferir antes de implementar

- Que o Monal aceita sem erro mensagem de um nick que não está na lista de participantes.
- Que marcar "entrou na sala" depende só da presença com código 110.
- Que o hook `presence/full` roda antes da fila de hibernação do `mod_smacks` no Prosody 13 (medir com a métrica do módulo em `dry_run`).

Decisão em 17/11/2026: **só documentar**, nada foi implementado.

## Item 2 (entrar nas salas só sob demanda): menções e o contador (17/11/2026)

Decisão de 17/11/2026: o item 2 (contador de não lidas por MAM com `max=0` e entrada na sala só quando a pessoa abre o canal) foi **aprovado como direção**; nada foi implementado. Este trecho registra como ficam as menções.

### Como é hoje (conferido no código)

- **Cor do contador** (`MLContactCell.m`): num canal marcado "só menções" (`isMentionOnly`), o contador é **cinza** e vira **vermelho** quando há menção não lida. Não existe rosa. Canal silenciado fica sempre cinza, mesmo com menção.
- **Outros sinais:** um "@" antes do sino e a prévia em negrito quando o contador está vermelho.
- **Como a menção é detectada:** `-[DataLayer hasUnreadMentionInMuc:forAccount:withNames:]` procura o nick, o nome, a parte local do JID ou o JID, só como palavra inteira (`+[HelperTools text:mentionsAnyOfNames:]`), no texto das mensagens não lidas **que já estão no banco** (até 500). A mesma regra decide a notificação (`MLNotificationManager.m`).
- **Ao abrir o canal:** vai para a primeira mensagem não lida (`firstUnreadHistoryId`). **Não existe** o "@" flutuante do WhatsApp para pular de menção em menção.

### O problema que o item 2 cria

A consulta MAM com `max=0` devolve só o total (RSM `count`), sem texto. O app saberia "há N novas", mas não se uma delas cita a pessoa. O contador de canais "só menções" ficaria sempre cinza e a menção só seria descoberta ao abrir o canal.

### Opções, em ordem de custo

1. **Página recente nos canais "só menções".** Baixar as últimas ~100 mensagens depois da última lida (mensagens, não presenças), uma vez por canal. Se houver menção, o contador fica vermelho. Se houver mais que isso, mostra "99+" cinza, e uma menção mais antiga só aparece ao abrir. Canais que não são "só menções" ficam só com o contador.
2. **"@" flutuante (à la WhatsApp).** O app guarda os ids das mensagens com menção não lida e o botão leva de uma em uma, em ordem, com o número restante. Só enxerga menções já no banco: ao abrir o canal, busca páginas para trás até a última lida (com teto). É uma funcionalidade nova da tela de conversa (`ChatView.swift`) e vale por si só, mesmo sem o item 2.
3. **Canais do isaCloud:** o `mod_cloud_notify_quiet` já classifica o push como `muc-mention`; o app poderia marcar o canal com menção sem baixar nada. Só vale para canais do nosso servidor, então é um bônus.

### Compatibilidade

Tudo acima usa só XEPs padrão (MAM XEP-0313, bookmarks XEP-0402, referências XEP-0372); nenhum cliente de outro lugar é afetado. A regra de compatibilidade do projeto fica: estender sem substituir, mudanças de comportamento do servidor só por opt-in negociado (feature anunciada pelo app), namespace próprio para o que for nosso, e conferir com Conversations, Gajim, Dino e o Monal oficial depois de cada mudança do servidor. **MIX fica fora** enquanto estiver Experimental e sem clientes.

## Medição de 20/11/2026: a enxurrada é quase toda reentrada, não movimento

Rawlogs do iPhone de 20/11, 06:37–07:15 (app e extensão, contas do isacloud.cc e do xmpp.social.br), presenças de sala classificadas por ocupante (sala + apelido):

| Tipo | Presenças |
|---|---|
| Ocupante já visto, presença repetida sem mudança de `show`/`status` | 3.251 |
| Ocupante visto pela primeira vez no trecho (lista inicial ou entrada real) | 1.938 |
| Mudança real de `show`/`status` | 197 |
| Própria presença (código 110, o app entrando na sala) | 106 |
| Saída (`unavailable`) | **11** |

- O movimento real (gente entrando e saindo) é pequeno: **11 saídas** em ~35 min. O volume vem da **lista inteira de ocupantes que o servidor manda a cada vez que o app entra na sala** (XEP-0045 obriga). A sala `guiaxmpp@conference.isacloud.cc` sozinha deu 2.235 presenças, 1.994 delas repetidas.
- O app entra de novo nas salas a cada **sessão nova** (sem retomar o Stream Management). No trecho houve **10 sessões novas** (6 da extensão, 4 do app) contra 22 retomadas.
- O app apaga a lista ao entrar (`cleanupParticipantsListFor:` em `MLMucProcessor.m`, antes de `sendJoinPresenceFor:`) e remonta com a lista que chega. Por isso um filtro no servidor que corte repetidas, ou o filtro "quem falou em 7 dias" do `mod_muc_presence_quiet`, esvaziaria a lista, o `@` e a contagem.

### Caminhos que mantêm lista, `@` e contagem

1. **Menos sessões novas (app):** entender por que app e extensão perdem a retomada um do outro. Cada sessão nova a menos poupa a lista inteira de todas as salas, nas duas contas.
2. **Reentrada com diferença (servidor do isaCloud + app, opt-in):** um módulo guarda, por usuário e sala, a última presença entregue de cada ocupante; na reentrada manda só quem entrou, quem saiu (como `unavailable`) e quem mudou. O app anuncia a feature e deixa de apagar a lista ao entrar. Lista, `@` e contagem ficam exatos. Vale para as contas de todos os VirtualHosts do isaCloud (isacloud.im, xmpp.social.br, voz.social.br).
3. **O filtro "quem falou em 7 dias" sai da mesa:** corta justamente o que o app usa e não ataca a origem da enxurrada.
4. **fpush não serve para isso:** ele só recebe os pedidos de push e não vê nem filtra presença.

## Por que as sessões novas acontecem (20/11/2026)

### O que o log mostra

Toda sessão nova do trecho veio logo depois de uma retomada recusada pelo servidor:

```
<failed xmlns='urn:xmpp:sm:3'><error type='cancel'><resource-constraint/>
<text>Too many unacked stanzas remaining, session can't be resumed</text></error></failed>
```

- Conta do xmpp.social.br (a que está nos canais grandes): **10 retomadas recusadas, 1 aceita**.
- Conta do isacloud.cc: **10 retomadas, todas aceitas**.

Não é coisa do app nem da extensão perderem a sessão uma da outra: é o servidor que recusa.

### O que o Prosody faz (conferido no código do trunk e no `prosody.cfg.lua`)

- `mod_smacks` guarda as stanzas não confirmadas numa fila de tamanho fixo, `smacks_max_queue_size`, **padrão 500**. A config não define esse valor.
- A fila é circular (`util.queue` com sobrescrita): passou de 500, a mais antiga é descartada. Na retomada, `smqueue:resumable()` vê que faltam stanzas e devolve o erro `overflow`, que é o texto acima.
- `smacks_hibernation_time = 86400` não ajuda aqui: a sessão não expira, ela **transborda**.
- `mod_csi_battery_saver` (cópia própria em `isacloud-custom-plugins`) segura presenças enquanto o app está inativo. Mas qualquer mensagem de grupo com texto é "importante" e despeja a fila inteira. Nos canais movimentados isso acontece o tempo todo, então as presenças vão quase direto para a fila do smacks.

### O ciclo

1. O app é suspenso. As salas continuam mandando mensagens e presenças, que ficam na fila do smacks sem confirmação.
2. Passa de 500 e a retomada é recusada. Com a lista inteira de uma única sala grande isso já acontece: a `guiaxmpp` sozinha deu 2.235 presenças.
3. Sessão nova: o app entra de novo em todas as salas e recebe a lista inteira de cada uma (milhares de presenças).
4. Se o app é suspenso antes de confirmar tudo isso, a fila já está acima de 500 e a próxima retomada também falha. Volta ao passo 3.

A conta do isacloud.cc não está nos canais grandes e nunca chega a 500. Por isso retoma sempre.

### Por que a Guia XMPP aparece mais que os canais maiores (Gajim, Prosody, Conversations)

Medido por entrada em cada sala no mesmo trecho:

- **Guia XMPP:** é sala do nosso próprio servidor, sem s2s no caminho. A lista inteira (~229 ocupantes) chega em 5 a 15 s a cada entrada, enquanto o app ainda está acordado. Por isso ela inteira aparece no log, ~10 vezes.
- **Gajim (481 ocupantes), Prosody (376) e Conversations (148):** vêm por s2s e a lista chega devagar. A do Gajim levou 3 min para entregar 273 presenças. Muitas entradas registraram 0 ou poucas presenças, porque o app ou a extensão já tinham sido suspensos.
- O resto dessas listas não some: cai na fila do smacks com o app congelado. Esses canais são **combustível invisível** do transbordo. Pesam tanto quanto a Guia ou mais, mas não aparecem no log do app.
- O `mod_default_bookmarks` não tem papel nisso. Ele só age com a lista de bookmarks vazia (conta nova). Quem entra na Guia a cada sessão é o app, como em todas as salas.

### Propostas (servidor, do mais barato ao mais completo)

1. **Aumentar a fila do smacks** no `prosody.cfg.lua` (global ou nos VirtualHosts isacloud.im, xmpp.social.br e voz.social.br), por exemplo `smacks_max_queue_size = 5000`. A fila é por sessão hibernada, e com `smacks_max_hibernated_sessions = 2` o custo fica em alguns MB por usuário pesado, no pior caso. É uma linha de config e um reload, e quebra o ciclo do passo 4. O preço é que, na retomada, o servidor reenvia tudo o que estava na fila. Isso é bem menos do que a lista inteira de todas as salas de uma sessão nova.
2. **Compactar presença de sala no `mod_csi_battery_saver`** enquanto o cliente está inativo. Presenças de ocupante (sem o código 110) vão para um mapa por JID de origem (`sala/apelido`) em vez da fila, e a última vence. Esse mapa não é despejado pelas mensagens "importantes", só no `csi-client-active`, no fim da hibernação ou ao passar de um teto. A semântica de presença é preservada, porque só o estado mais recente de cada ocupante importa: `unavailable` depois de `available` fica `unavailable`, e a troca de apelido (303) é uma presença do apelido antigo. Assim a fila do smacks recebe no máximo uma presença por ocupante, e as repetidas somem.
3. **Reentrada com diferença** (item 2 da seção anterior) continua valendo para quando houver sessão nova, mas com 1 e 2 ela passa a ser rara.

Medir depois de aplicar: contar `<failed` e `<resumed` por conta nos rawlogs (no trecho de hoje foram 10 e 1 na conta do xmpp.social.br).

### O que foi feito (20/11/2026)

- **Fila do smacks:** `smacks_max_queue_size = 5000`, configurado no servidor pela Isadora. O 24 h de hibernação fica: a wiki do Monal para admins pede pelo menos 24 h de timeout de sessão, porque o Monal entra e retoma muito por causa do desenho do push. A mesma página recomenda 2000 a 4000 de fila para quem está em canais movimentados.
- **Compactação no `mod_csi_battery_saver`** (cópia própria em `isacloud-custom-plugins/share/lua/5.4/`):
  - Enquanto o cliente está inativo, presença de ocupante (disponível ou `unavailable`, sem o código 110) vai para um buffer por `sala/apelido`, e a última vence.
  - Mensagens "importantes" não despejam esse buffer.
  - Ele é liberado em quatro casos:
    - quando o cliente fica ativo;
    - no fim da hibernação, depois do que já estava na fila;
    - quando chega a presença própria (110) de uma sala, e aí só os ocupantes daquela sala, antes da 110, para manter a ordem do XEP-0045 7.2.3 (a lista termina com a própria presença);
    - quando passa do teto.
  - Opções: `csi_battery_saver_compact_muc_presence` (padrão `true`, desliga a compactação sem tirar o módulo) e `csi_battery_saver_muc_presence_max` (padrão 1000).
  - Testado fora do servidor com um harness que usa o `util.stanza`, o `util.jid` e o `util.queue` do trunk, com 12 verificações. Elas cobrem compactação, ordem antes da 110, liberação ao ficar ativo, fim da hibernação, teto e nenhuma compactação com o cliente ativo.
- **Para validar em produção:**
  - a contagem de `<failed` contra `<resumed` da conta do xmpp.social.br nos rawlogs das próximas manhãs;
  - a lista de participantes e o `@` continuam completos depois de uma noite com o app suspenso.

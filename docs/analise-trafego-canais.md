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
- Só vale para contas **hospedadas no servidor do isaCloud**. A conta do xmpp.social.br da Isadora (98% das presenças dos logs de 17/11) não é afetada.

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

# Análise: enquetes (polls) compatíveis com o Fluux no isaCloud Android

> Documento de análise. Nada foi implementado. Objetivo: registrar como o Fluux faz,
> o que o isaCloud já tem, onde estão as lacunas de compatibilidade e um plano de
> implementação em fases.

## 1. Resumo

O Fluux **não usa XEP-0472** nem pubsub. Ele definiu um protocolo próprio, `urn:fluux:poll:0`,
especificado em `~/projects/js/fluux-messenger/docs/XEP-POLL_PROTOCOL.md`, em que:

- a enquete é uma **mensagem de grupo (`type="groupchat"`)** com um elemento `<poll>`
  (título, descrição, opções com emoji) **mais** um `<body>` textual de fallback;
- **o voto é uma reação XEP-0444** no emoji da opção, na própria mensagem da enquete;
- a contagem é feita no **mapa de reações** da mensagem no cliente;
- o criador pode fechar a enquete com uma mensagem `<poll-closed message-id="...">`.

Ou seja, "fallback por emoji de reação" não é um modo alternativo do Fluux: **o voto já é
sempre reação**. O fallback existe em outro nível — o `<body>` textual permite que clientes que
não conhecem `urn:fluux:poll:0` (caso do isaCloud hoje) vejam a enquete legível e votem
manualmente reagindo com `1️⃣`, `2️⃣`, etc.

Consequência prática: a compatibilidade é **alcançável** porque depende só de coisas que o
isaCloud já implementa (XEP-0444 + stanza-id/origin-id em MUC). É um trabalho de **_parser_ +
modelo + UI**, sem mudança de servidor (Prosody).

Escopo da v1 já decidido (§8): só grupo/canal, sem esconder em grupo criptografado e com
encerramento de enquete incluído.

## 2. Protocolo do Fluux (o que precisa ser replicado)

Namespace: `urn:fluux:poll:0`
(`packages/fluux-sdk/src/core/namespaces.ts:180`, constante `NS_POLL`)

### 2.1 Mensagem da enquete

```xml
<message to="sala@conference.exemplo" type="groupchat" id="poll-uuid">
  <body>📊 Poll: Almoço?
1️⃣ Pizza
2️⃣ Sushi
3️⃣ Tacos</body>

  <poll xmlns="urn:fluux:poll:0" allow-multiple="false" hide-results="false" deadline="2026-11-30T18:00:00Z">
    <title>Almoço?</title>
    <description>opcional</description>
    <option emoji="1️⃣">Pizza</option>
    <option emoji="2️⃣">Sushi</option>
    <option emoji="3️⃣">Tacos</option>
  </poll>

  <fallback xmlns="urn:xmpp:fallback:0" for="urn:fluux:poll:0"><body/></fallback>
  <store xmlns="urn:xmpp:hints"/>
</message>
```

Detalhes relevantes (`packages/fluux-sdk/src/core/modules/Poll.ts:109-163`):

| Item | Regra |
|---|---|
| `<title>` | obrigatório, não vazio |
| `<option>` | mínimo 2; `emoji` obrigatório; texto = rótulo |
| `allow-multiple` | `"true"` = múltipla escolha (default `false`; o atributo **só é enviado quando true**) |
| `hide-results` | `"true"` = esconde contagem até o usuário votar (idem, omitido quando false) |
| `deadline` | ISO 8601; voto bloqueado depois disso (só no cliente) |
| Emojis padrão | `1️⃣ … 9️⃣` (`POLL_OPTION_EMOJIS`), máx. 9 opções; emojis customizados permitem mais |
| `<body>` | `📊 Poll: <título>` + descrição (se houver) + uma linha `<emoji> <rótulo>` |
| `<id>` da mensagem | UUID do cliente, **sem `<origin-id>` separado** |
| Onde aparece | só MUC (grupo/canal). 1:1 não é suportado pelo Fluux |

O `<body>` é sempre enviado. Clientes que não conhecem a extensão mostram o texto; clientes que
conhecem usam `<fallback for="urn:fluux:poll:0"><body/></fallback>` (XEP-0428) para **descartar**
esse body e renderizar o cartão.

### 2.2 Voto (XEP-0444)

```xml
<message to="sala@conference.exemplo" type="groupchat" id="vote-uuid">
  <reactions xmlns="urn:xmpp:reactions:0" id="<stanza-id da mensagem da enquete>">
    <reaction>2️⃣</reaction>
  </reactions>
  <store xmlns="urn:xmpp:hints"/>
</message>
```

Regras de voto (`Poll.ts:178-209`, `poll.ts:219-262`):

- **Único**: remove todos os emojis de opção da enquete do conjunto de reações do usuário,
  exceto o novo voto; **preserva** reações que não são de opção (ex.: `👍`). Clicar de novo na
  mesma opção remove o voto.
- **Múltiplo**: comportamento normal de "toggle" de reação.
- O cliente envia **o conjunto completo de reações** do usuário (substituição), não um delta.
- O id referenciado é o **stanza-id** em MUC (comentário no código: "For MUC, prefer stanzaId
  (server-assigned, stable)… Other clients (e.g. Gajim) reference messages by stanzaId").

### 2.3 Contagem (`packages/fluux-sdk/src/core/poll.ts:147-215`)

- **Múltipla escolha**: `count = nº de reações do emoji da opção`.
- **Escolha única**: cada eleitor conta **apenas na última opção** (na ordem das opções) em que
  reagiu — tolera cliente legado que reagiu com vários números. Depois filtra por isso.
- Total de eleitores = união dos conjuntos (quem votou em 2 opções conta 1).
- Com `hide-results="true"`, nada de contagem/progresso antes de o usuário votar.

### 2.4 Fechamento (`Poll.ts:222-283`)

```xml
<message type="groupchat" id="close-uuid">
  <body>📊 Poll closed: Almoço?
1️⃣ Pizza: 3
2️⃣ Sushi: 7</body>
  <poll-closed xmlns="urn:fluux:poll:0" message-id="poll-uuid">
    <title>Almoço?</title>
    <tally emoji="1️⃣" label="Pizza" count="3" voters="nick1,nick2,nick3"/>
    <tally emoji="2️⃣" label="Sushi" count="7" voters="..."/>
  </poll-closed>
  <fallback xmlns="urn:xmpp:fallback:0" for="urn:fluux:poll:0"><body/></fallback>
  <store xmlns="urn:xmpp:hints"/>
</message>
```

- `<poll-closed>` é uma **mensagem nova** que aponta para a original por `message-id`.
- `message-id` = **id de cliente** da mensagem da enquete (o UUID), não o stanza-id.
- `voters` = apelidos (nicks) no MUC; serve para o receptor reconciliar o mapa de reações.
- Verificação do receptor (`Chat.ts:2711-2745`), quando a original está no store:
  remetente é o criador (occupant-id, senão nick), título idêntico e emojis de `tally`
  pertencentes às opções. Se falhar, descarta o `poll-closed`.
- Se a original não estiver disponível (entrou depois), o Fluux aceita o resultado de imediato e
  **verifica depois** via MAM (`{urn:xmpp:mam:2}ids`).
- Também existe IQ `poll-results` (get/result/error) para perguntar o placar ao cliente criador —
  exigência de o criador estar online. É opcional no nosso caso.

### 2.5 UI do Fluux (referência visual)

`apps/fluux/src/components/conversation/PollCard.tsx` + `PollClosedCard.tsx` +
`PollCreator.tsx`: cartão dentro do balão, barra de progresso por opção com cor derivada do
rótulo (XEP-0392), contagem/percentual, marca do "meu voto", rodapé com total de votos,
prazo, "Vote para ver os resultados" e botão de fechar para o criador.

## 3. O que o isaCloud já tem

| Peça | Onde | Situação |
|---|---|---|
| Namespace de reações | `xml/Namespace.java:20` (`REACTIONS`) | ✅ |
| Modelo XML tipado | `im/conversations/android/xmpp/model/reactions/{Reactions,Reaction}.java` | ✅ |
| Envio de reações (conjunto completo) | `xmpp/manager/ReactionManager.java:143-235` | ✅ `sendReactions(Message, Collection<String>)` |
| Recebimento/agregação em MUC | `ReactionManager.java:30-141` | ✅ exige occupant-id (XEP-0421) |
| Persistência | `entities/Message.java` (`REACTIONS`, `values.put(REACTIONS, Reaction.toString(...))`) | ✅ JSON por mensagem |
| Agregação para UI | `entities/Reaction.java:135-164` (`aggregated()` = emoji → contagem + `ourReactions`) | ✅ |
| Componente de UI de reação | `ChipGroup reactions` em `item_message_start.xml:141` / `item_message_end.xml:130` + `BindingAdapters.setReactionsOnReceived/Sent` + `MessageAdapter.java:2218-2240` | ✅ |
| XEP-0428 (fallback) | `im/conversations/android/xmpp/model/fallback/Fallback.java`, uso em `parser/MessageParser.java:365-374` | ✅ para reações e retração |
| Extensões por anotação | `@XmlPackage/@XmlElement` + `ExtensionFactory` (mapa gerado) | ✅ padrão do projeto |
| Colunas extras isaCloud | `Message.STICKER` (`isacloudSticker`), `Message.QUOTE_ID`, `DatabaseBackend` versão **58** | ✅ mesmo padrão a seguir para `poll` |
| Limite de reações por usuário | `model/reactions/Restrictions.java`, checado em `XmppActivity.sendReactions:352-364` | ⚠️ pode interferir (ver 4.5) |

Não existe hoje: nada de `poll`, `urn:fluux:poll:0`, XEP-0472 ou pubsub de enquete. Ou seja, o
isaCloud hoje é exatamente o "cliente legado" que mostra o `<body>` e permite votar reagindo à
mão — desde que o usuário ache `1️⃣` no teclado de emojis.

## 4. Lacunas e riscos de compatibilidade

### 4.1 Id de referência — compatível ✅

Fluux usa stanza-id em MUC; o isaCloud usa `message.getServerMsgId()` em MUC
(`ReactionManager.java:177`). Alinhado — voto de um aparece no outro.

Cuidado no sentido inverso: se o isaCloud **criar** a enquete com `<origin-id>` diferente do
`id`, um `<poll-closed>` posterior pode não ser casado pelo Fluux (ele procura por `id` e por
stanza-id — ver §8.2 do doc deles). No isaCloud, `MessageGenerator.preparePacket` faz
`packet.setId(message.getUuid())` e só adiciona `OriginId(uuid)` **quando a sala não tem ids
estáveis** (`MessageGenerator.java:66-71`) — ou seja, os dois valores são sempre iguais e o
casamento funciona. Não é preciso mudar nada, apenas não criar um id paralelo no envio da
enquete.

### 4.2 occupant-id obrigatório para reagir em MUC ⚠️

`ReactionManager.processReactions` ignora reações em MUC sem occupant-id, e `sendReactions`
recusa enviar sem occupant-id (`java:162-166`). Isso é limitação **já existente** de reações do
isaCloud, mas ela agora passa a bloquear enquete também: em sala cujo serviço não anuncia
XEP-0421, o Fluux vota e o isaCloud não. Vale checar no Prosody de produção/teste
(`muc_occupantid`/disco `urn:xmpp:occupant-id:0`) antes de prometer suporte.

### 4.3 Normalização de emoji ⚠️

A chave da opção tem que ser **exatamente** a sequência enviada (`1️⃣` = U+0031 U+FE0F U+20E3).
O isaCloud agrega por `Reaction.normalizedReaction()` → `Emoticons.normalizeToVS16`
(`utils/Emoticons.java:99-103`), que só mexe num conjunto fixo de emojis text-default; para
keycaps nada muda. Então: montar as chaves a partir do **atributo `emoji` recebido**, sem
"reconstruir" o emoji por conta própria, e nunca oferecer no seletor interno uma variante sem
VS16 — senão o voto some da contagem do Fluux.

### 4.4 Nada de pubsub, nada de servidor ✅

Não é preciso mexer no Prosody, nem em PEP/MAM especial. `mod_mam` já arquiva mensagens com
`<store/>`; `<poll>` e `<poll-closed>` chegam pelo MAM como qualquer mensagem.

### 4.5 Limite de reações por usuário ⚠️

`Restrictions` (disco `urn:xmpp:reactions:0:restrictions`) pode impor `max_reactions_per_user`.
`XmppActivity.sendReactions` recusa acima do limite. Se a sala impõe 1, enquete de **múltipla
escolha** fica inviável e até "1 voto + 👍" estoura. Mitigação na UI: esconder múltipla escolha
quando o limite for 1; ou avisar. (O Fluux não lê essa restrição — outra assimetria.)

### 4.6 Grupos criptografados ⚠️ (decidido: não esconder)

Em grupo com OMEMO, o `<poll>` viaja no stanza em texto claro (o corpo é que vai cifrado) — é o
mesmo padrão já usado pelo isaCloud para `<sticker>` e `isacloudQuote`
(`MessageGenerator.java:78-85`, "goes on the outer stanza (also with PGP/OMEMO)").

**Decisão da v1:** não esconder a opção "Enquete" em grupo criptografado. Consequências aceitas:

- o servidor (e qualquer relay) consegue ler pergunta e opções — não é conteúdo E2EE;
- funcionalmente **não quebra**: quem decifra o corpo vê o texto de fallback, e quem conhece
  `urn:fluux:poll:0` vê o cartão, porque o elemento está fora do payload cifrado;
- os votos (reações) seguem o mesmo regime de texto claro já usado hoje pelas reações.

Futuro: se quisermos E2EE de verdade, o `<poll>` teria que ir dentro do payload cifrado — o que
exige um dialeto próprio e sai da compatibilidade com o Fluux. Fica fora de escopo.

Decidido também: **sem aviso na interface** sobre falta de cifra, para manter coerência com
reações, figurinhas e citações, que já trafegam da mesma forma nesses grupos.

### 4.7 Escopo MUC (decidido: só grupo/canal)

O Fluux só cria enquete em sala, e a v1 do isaCloud segue o mesmo recorte. Em 1:1 não haverá
cartão nem botão de criar; a mensagem recebida com `<poll>` aparece como texto normal (body de
fallback), e reação manual continua possível, mas sem semântica de enquete.

Consequência para o parser: o body só deve ser suprimido em MUC, igual ao Fluux
(`ROOM_ONLY_FALLBACK_TARGETS`) — em 1:1 o `<body>` é exibido normalmente.

### 4.8 Body de fallback x body duplicado

Se o isaCloud renderizar o cartão e também o `<body>`, o usuário vê a enquete duas vezes. A
solução já existe no projeto: usar `Fallback.get(packet, Poll.class, Body.class)` como é feito
para `Reactions` e `Retract` (`MessageParser.java:365-374`) para **descartar o body**. Precisa
registrar a extensão `Poll` para que `ExtensionFactory.id(Poll.class)` resolva o namespace.

Detalhe do lado do Fluux: o `<body>` da enquete só é descartado **em sala**
(`utils/fallbackRegistry.ts:30-36`, `ROOM_ONLY_FALLBACK_TARGETS`) — em 1:1 ele mostra o texto.
O isaCloud deve fazer igual, até porque não vamos renderizar cartão em 1:1.

### 4.9 Identidade do eleitor: nick x occupant-id ⚠️

O Fluux guarda reações em sala como **emoji → apelido (nick)**, enquanto o isaCloud guarda
`Reaction(reaction, received, from, trueJid, occupantId)` e agrega por `occupantId`
(`entities/Reaction.java:78-91`). Isso não atrapalha o voto (cada cliente conta no seu próprio
mapa), mas atrapalha o `voters` do `<poll-closed>`:

- ao **enviar** `<poll-closed>`, preencher `voters` com **nicks**, não com occupant-id;
- ao **receber** `<poll-closed>` do Fluux, **não reconciliar** o mapa de reações local com o
  `voters` (eles são nicks e entrariam como `Reaction` sem occupantId, corrompendo a agregação).
  O certo é guardar o `tally` recebido no poll/`pollClosed` da mensagem e só exibir o placar
  congelado; o mapa de reações continua sendo a fonte de verdade para o "meu voto".

Vale registrar também que o `<poll>` carrega o criador no lado do Fluux como
`poll.creatorId = occupantId` (`Chat.ts:2568-2576`), o que dá o critério para "pode encerrar".

### 4.10 O Fluux não esconde enquete em sala sem suporte a reação

O Fluux calcula `room.supportsReactions` (`MUC.ts:1493-1511`,
`roomCapabilities.ts:35-54`) para desabilitar o seletor de reação normal, mas **não usa esse
gate** no cartão de enquete: em sala sem occupant-id ele ainda oferece votar. No isaCloud, que
recusa enviar reação em MUC sem occupant-id, a UI de enquete **deve** ser escondida nessa
situação (`MucOptions.occupantId()` / `Restrictions`), senão o usuário toca e nada acontece.

### 4.11 Não duplicar os votos como chips de reação

O Fluux remove os emojis de opção da linha normal de reações (`MessageBubble.tsx:529-545`) para
o voto não aparecer duas vezes (barra da enquete + chip). O isaCloud precisa fazer o mesmo no
`MessageAdapter`/`BindingAdapters`: ao renderizar cartão de enquete, filtrar do `ChipGroup` os
emojis que são opções — mantendo `👍` e outros intactos (é justamente o que a regra de escolha
única do Fluux preserva).

## 5. Arquitetura proposta

### 5.1 Modelo XML

Novo pacote `im/conversations/android/xmpp/model/poll/`:

```
package-info.java   @XmlPackage(namespace = Namespace.POLL)   // "urn:fluux:poll:0"
Poll.java           @XmlElement  title/description/option, atributos allow-multiple,
                                 hide-results, deadline
Poll.Option.java    @XmlElement  emoji (attr) + texto
PollClosed.java     @XmlElement  message-id (attr) + title/description/tally
PollClosed.Tally.java @XmlElement emoji, label, count, voters
```

Registrar `Namespace.POLL = "urn:fluux:poll:0"` em `xml/Namespace.java`, com comentário
`// isaCloud: enquetes compatíveis com o Fluux (urn:fluux:poll:0)`.

### 5.2 Parser

Em `parser/MessageParser.java`:

1. tratar `<poll>` como extensão conhecida (e o body como fallback dela);
2. `<poll-closed message-id>`: guardar dados e resolver a mensagem original por
   `remoteMsgId` (que é o `id` do remetente) — `Conversation.findMessageWithRemoteId` existe;
3. persistir o poll na mensagem.

### 5.3 Entidade e banco

- `Message.POLL = "isacloudPoll"` (TEXT, JSON), no padrão de `STICKER`/`QUOTE_ID`,
  com `getPoll()/setPoll()` e `values.put(POLL, Services.GSON.toJson(poll))`;
- atenção: `IndividualMessage.fromCursor` (`entities/IndividualMessage.java:100-190`) duplica a
  leitura do cursor e precisa ser atualizado junto, como já é feito para `STICKER`;
- `DatabaseBackend`: coluna na criação da tabela + migração `oldVersion < 59`, subindo
  `DATABASE_VERSION` para 59 (padrão de `hasColumn` usado em `< 56`/`< 57`);
- se optarmos por um `Message.TYPE_POLL`, revisar as consultas que hoje só conhecem os tipos
  existentes (`DatabaseBackend.java:1492,1607`, `MessageUtils.java:159,243,294`,
  `Conversation.java:372,545,950,1094`). Alternativa mais barata: **não** criar tipo novo — a
  enquete continua sendo `TYPE_TEXT` com um poll anexado, o que evita mexer nessas consultas;
- classe de domínio imutável `entities/Poll.java` (título, descrição, opções, flags, deadline,
  `closedAt`/tally) — serializável em GSON como `Reaction`.

### 5.4 Regras (`PollTally` / `Polls` util)

Porta direta de `poll.ts` (é código puro, ~100 linhas):

```java
static List<Tally> tally(Poll poll, Aggregated reactions)   // escolha única e múltipla
static int totalVoters(Poll poll, Aggregated reactions)
static Set<String> myVotes(Poll poll, Aggregated reactions) // ourReactions ∩ emojis
static boolean isExpired(Poll poll, Instant now)
static List<String> enforceSingleVote(current, newVote, pollEmojis)
```

Identidade do votante: contar por `Reaction.occupantId` (chave estável do isaCloud e a mesma
usada no "meu voto" via `Aggregated.ourReactions`). Não tentar espelhar a identidade do Fluux
(nick) dentro do modelo — ver 4.9.

### 5.5 Envio

Novo `PollManager` (ou métodos em `ReactionManager`):
- `sendPoll(Conversation, Poll)` — monta a mensagem groupchat com body de fallback, `<poll>`,
  `<fallback for>` e `<store/>`, envia via caminho normal de mensagem (`sendMessagePacket`) para
  já ganhar status/eco/DB;
- `vote(Message, String optionEmoji)` — calcula o novo conjunto e delega para
  `ReactionManager.sendReactions(...)` (já existente, já persiste e atualiza a UI);
- `closePoll(Message)` — só o criador; monta `<poll-closed>` com `tally`+`voters`, envia.

### 5.6 UI

- **Cartão no balão**: novo bloco `poll` em `item_message_content.xml` (o `<merge>` reaproveitado
  pelos dois balões), escondido por padrão como o `link_preview`: título, descrição, linhas de
  opção (barra + rótulo + contagem) e rodapé. Branch em `MessageAdapter.render` **antes** do
  texto (`MessageAdapter.java:2166-2190`): `if (message.hasPoll()) displayPollMessage(...)`.
  Não precisa de novo `viewType` — os view holders `START`/`END` servem.
- **Chips de reação**: filtrar os emojis de opção antes de chamar
  `BindingAdapters.setReactionsOnReceived/Sent` (ver 4.11).
- **Criação**: nova entrada no enum `im/conversations/android/model/AttachmentChoice`
  (`Type.POLL` + `attachment_choice_poll`) e no bloco `ATTACHMENT_CHOICES`
  (`ConversationFragment.java:215-266`), com tratamento em `handleAttachmentChoice`
  (`:2626-2651`). Dialog com título, 2 a 9 opções, múltipla escolha, ocultar resultados e prazo
  opcional — **apenas o conjunto padrão `1️⃣…9️⃣`, sem seletor de emoji** (§8). Visível só em
  MUC e só se a sala tem occupant-id; **não** gatear por criptografia (decisão 4.6). Atenção: o
  mesmo enum alimenta a preferência de "ação rápida" em `InterfaceSettingsFragment`.
- **Fechamento**: menu de contexto da mensagem (`onCreateContextMenu`/`populateContextMenu`,
  `ConversationFragment.java:2150-2301`) → "Encerrar enquete", só para o criador
  (`outgoing && poll && !closed && !expired`) e se ainda aberta.
- **Mensagem de `poll-closed` recebida**: como o Fluux, ela é uma mensagem própria — renderizar
  um cartão de resultado congelado e, quando a original for encontrada por `remoteMsgId`, marcar
  o poll dela como encerrado (sem mexer no mapa de reações — ver 4.9).
- **Fallback**: mensagem com `<poll>` fora de MUC (1:1) mostra o `<body>` textual normalmente —
  é o comportamento de cliente legado. Em grupo criptografado o cartão é renderizado igual
  (o `<poll>` vai fora do payload cifrado; ver 4.6).
- **Opcional (paridade fina)**: faixa/banner de "enquete sem resposta" como o
  `PollBanner.tsx` do Fluux, usando estado local de "já votou/descartei".
- **i18n**: strings novas em `values/strings.xml` e `values-pt-rBR/strings.xml` (não existe
  `values-pt-r`), no mesmo bloco das strings de anexo/reação.

### 5.7 Detalhes de UX herdados do Fluux

- `hide-results`: ocultar barras/contagens até o usuário votar; mostrar "Vote para ver os
  resultados";
- `deadline`: desabilitar opções e mostrar "Encerrada em <data>";
- múltipla escolha: indicar "Selecione uma ou mais";
- cor por opção: **paleta isaCloud** (rosa principal com variações neutras), não as cores por
  rótulo (XEP-0392) do Fluux — decisão em §8.

## 6. Plano em fases

Escopo da v1 já fechado: só grupo/canal, sem gate de criptografia, com encerramento incluído.

| Fase | Entrega | Compatível com Fluux |
|---|---|---|
| 1 | Modelo XML + parser + coluna no banco + cartão **somente leitura** (mostra opções e placar, body suprimido em MUC) | Lê e conta enquetes do Fluux |
| 2 | Voto por toque na opção (único e múltiplo) usando `sendReactions` | Vota e é contado pelo Fluux |
| 3 | Criação de enquete (dialog + envio) e **encerramento** (`<poll-closed>` + verificação de criador) | Cria e fecha dos dois lados |
| 4 (opcional) | IQ `poll-results`, verificação retroativa por MAM, edição, banner de enquete sem resposta | Paridade fina |

Fase 1 já resolve o pedido de "fallback": quem não renderiza vê o texto; quem renderiza vê o
cartão. Fase 2 é o coração. Fase 3 fecha a v1 (o encerramento é conveniência: o placar por
reações já é ao vivo, mas o resultado congelado evita "voto tardio" e dá o recorte oficial).

## 7. Como validar

- Simulador com conta do `isacloud.im` + Fluux web (`~/projects/js/fluux-messenger`) na mesma
  sala: criar no Fluux → votar no isaCloud → conferir contagem nos dois; criar no isaCloud →
  votar no Fluux.
- Conferir stanza real no log do isaCloud (`adb logcat`) para garantir `reactions@id` =
  stanza-id e `<reaction>1️⃣</reaction>` com VS16.
- Casos de borda: voto duplo em enquete de escolha única vindo de cliente legado; enquete
  `hide-results`; `deadline` vencido; sala sem occupant-id; sala com
  `max_reactions_per_user=1`.
- Fechamento: isaCloud fecha com `voters` em nicks; Fluux deve aceitar (título e emojis batem).
- Testes unitários: seguir `src/test/java/im/conversations/android/xmpp/EmojiReactionsTest.java`
  (`XmlElementReader`) para validar parse de `<poll>`/`<poll-closed>` em texto e para as regras
  de contagem (`PollTally`) — a lógica é pura e testável sem aparelho.

## 8. Decisões

### 8.1 Fechadas (v1)

1. **Escopo:** só grupo/canal (MUC), como o Fluux. Sem cartão nem criação em 1:1.
2. **Grupo criptografado:** não esconder a opção; o `<poll>` trafega sem E2EE na v1, com o
   servidor podendo ler pergunta e opções. Trade-off aceito, **sem aviso na interface** (mesmo
   comportamento já adotado para reações, figurinhas e citações).
3. **Encerramento:** entra na v1 (fase 3), com `<poll-closed>` e verificação de criador.
4. **Emojis das opções:** só o conjunto padrão `1️⃣…9️⃣` (até 9 opções). Sem seletor de emoji
   customizado na criação. Enquetes recebidas com emojis customizados (criadas no Fluux) são
   lidas e votadas normalmente, porque a chave vem do atributo `emoji` do stanza.
5. **IQ `poll-results` e verificação retroativa por MAM:** fora da v1 (fase 4, opcional).
6. **Cor das barras:** paleta isaCloud (rosa principal com variações neutras), não XEP-0392.

Não há itens pendentes para iniciar a fase 1.

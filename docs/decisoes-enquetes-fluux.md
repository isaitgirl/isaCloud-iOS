# Decisões: enquetes compatíveis com o Fluux (fases 1, 2, 3A e 3B)

> Complementa `docs/analise-enquete-fluux.md`. Este documento registra o que foi implementado nas
> **fases 1 e 2**: modelo XML, parser, entidades e banco (dados), o cartão de enquete e a votação
> por toque na opção (XEP-0444), além da **fase 3A**: criação de enquete (dialog + envio) e da
> **fase 3B**: encerramento pelo criador (`<poll-closed>`, confirmação, verificação no recebimento).

## 1. Namespace e modelo XML

- `Namespace.POLL = "urn:fluux:poll:0"`.
- Pacote novo `im/conversations/android/xmpp/model/poll/` no padrão de `model/reactions/`
  (`@XmlPackage` no `package-info` e `@XmlElement` em cada classe):
  - `Poll` (`<poll>`) — `title`, `description`, `option`, atributos `allow-multiple`,
    `hide-results` e `deadline`;
  - `Option` (`<option>`) — atributo `emoji`, conteúdo = rótulo;
  - `PollClosed` (`<poll-closed>`) — atributo `message-id`, `title`, `description`, `tally`;
  - `Tally` (`<tally>`) — atributos `emoji`, `label`, `count`, `voters`.
- Os elementos filhos (`title`, `description`) não têm classe própria; são lidos com
  `findChildContent(...)` porque herdam o namespace do `<poll>` pelo XML.
- Os setters de `allow-multiple`/`hide-results` só gravam o atributo quando o valor é `true`
  e o removem quando é `false`, igual ao Fluux.

## 2. Entidades e persistência

- `entities/Poll.java` e `entities/PollClosed.java` são serializadas com
  `im.conversations.android.json.Services.GSON`, no mesmo esquema de `entities/Reaction.java`
  (`toString(x)` / `fromString(String)`, retornando `null` para JSON vazio ou inválido).
- `Message.POLL = "isacloudPoll"` e `Message.POLL_CLOSED = "isacloudPollClosed"` (TEXT).
- `IndividualMessage.fromCursor` lê as colunas de forma defensiva (`getColumnIndex == -1`),
  como já é feito para `isacloudSticker`, porque a busca usa cursores antigos.
- `DATABASE_VERSION` passou de 58 para **59**, com as colunas no `CREATE TABLE` e migração
  idempotente (`hasColumn`) para quem já tem banco.

## 3. Mapeamento XML → entidade

| XML | Entidade | Observação |
|---|---|---|
| `title` | `Poll.title` | obrigatório; vazio invalida a enquete |
| `description` | `Poll.description` | vazio vira `null` |
| `option/emoji` | `PollOption.emoji` | guardado **exatamente** como veio (VS16 incluso) |
| `option` (conteúdo) | `PollOption.label` | |
| `allow-multiple`/`hide-results` | flags | ausência = `false` |
| `deadline` (ISO 8601) | `Poll.deadline` (`Long`, epoch millis) | data inválida vira `null` |
| `tally/count` | `Tally.count` | valor inválido ou negativo vira `0` |
| `tally/voters` (CSV) | `Tally.voters` (`List<String>`) | vazio/ausente vira lista vazia |

## 4. Parser

- O `<body>` textual da enquete só é tratado como fallback (`Fallback.get(packet, Poll.class,
  Body.class)`) em **sala** (`type="groupchat"`). Em 1:1 o body continua sendo exibido, como
  no Fluux (`ROOM_ONLY_FALLBACK_TARGETS`).
- Uma mensagem que só traz `<poll>` (sem body) também é persistida, com body vazio.
- `<poll-closed>` é anexado à mensagem como `PollClosed`; não há verificação de criador nem
  busca da mensagem original nesta fase.

## 5. Diferenças/decisões em relação ao Fluux

1. **Body do `<poll-closed>` não é suprimido.** O protocolo também marca o body do
   `poll-closed` como fallback, mas nesta fase nada renderiza esse cartão; suprimi-lo deixaria
   a mensagem vazia para o usuário. Reavaliar quando a UI da fase 3 existir.
2. **Body da enquete continua salvo no banco**, mesmo quando é fallback. A supressão é apenas
   na decisão de "tem conteúdo"; a UI (fase 2 em diante) decide não exibir o texto quando
   renderiza o cartão. Enquanto não há UI, o usuário vê o texto legível.
3. **Opções sem `emoji` ou sem rótulo são descartadas** no mapeamento, como no Fluux
   (`opt.emoji && opt.label`), porque não são votáveis nem exibíveis. Se sobrarem menos de duas,
   a enquete é considerada inválida.
4. **`count` inválido ou negativo vira `0`** (o XSD exige inteiro não negativo).
5. **`voters` não é reconciliado** com o mapa de reações do isaCloud (ver §4.9 da análise):
   são nicks, e o isaCloud agrega por `occupant-id`. Nesta fase o tally é guardado cru.
6. **Sem novo `Message.TYPE_*`**: a enquete continua sendo `TYPE_TEXT` com o poll anexado.

## 6. UI da fase 1 (somente leitura)

- **Utilitário**: `utils/Polls.java` porta a contagem de `poll.ts` do Fluux. Identidade do eleitor:
  `occupantId`, senão `from` (JID/nick), senão `trueJid`. A chave da opção vem do atributo `emoji`
  recebido; `normalizeToVS16` só é usado para casar a reação, nunca para reconstruir o emoji.
- **Cartão**: bloco `poll_card` em `item_message_content.xml` (escondido por padrão, como o
  `link_preview`), com título, descrição opcional, indicador de múltipla escolha, uma linha por
  opção (`item_poll_option.xml`: emoji, rótulo, marca do meu voto, contagem e barra) e rodapé.
  Nada é clicável nesta fase.
- **Quando aparece**: só em `MODE_MULTI`, quando a mensagem tem `<poll>` **ou** `<poll-closed>`.
  Em 1:1 o body textual continua sendo exibido como cliente legado.
- **Body**: escondido sempre que o cartão é renderizado, inclusive quando o stanza não trouxe
  `<fallback>` (o parser guarda o body; a decisão de exibir é da UI).
- **Rodapé**: `Resultado final · N votos` quando há `pollClosed` (placar congelado do tally, sem
  reconciliar nicks); `Enquete encerrada` quando o deadline venceu; `Vote para ver os resultados`
  em `hide-results` sem voto local; `Nenhum voto ainda`; ou o plural de votos.
- **Trilha da barra**: o `ProgressBar` horizontal herdava a trilha em 25% de alfa e parecia uma
  barra cheia em cinza quando a opção tinha zero votos; ficou em 13% (`0x22`) para o preenchimento
  rosa ser o único destaque.
- **Chips de reação**: `Polls.aggregatedWithoutOptions` remove do `ChipGroup` apenas os emojis que
  são opções da enquete (inclusive no `poll-closed`), preservando `👍` e outras reações.
- **Cores**: rosa da marca (`message_bubble_outgoing`, claro/escuro) nas barras quando o balão é
  recebido/neutro; no balão enviado rosa, barras na cor do texto para contraste. Fundo do cartão é
  translúcido derivado do balão, no mesmo padrão do cartão de link.
- **Testes**: `PollsTest` cobre escolha única, múltipla, eleitor legado com dois números, total sem
  duplicar, `myVotes`, `hasVoted`, deadline e filtro de chips.

## 7. Validação no emulador (fase 1)

AVD `isaPoll_API36` (API 36, x86_64, pt-BR) em `emulator-5556`, build
`assembleConversationsFreeDev -PabiFilter=x86_64`, conta `poli2@isacloud.im`. Enquetes enviadas
por script (`@xmpp/client`) para o canal de teste `enquete-teste@conference.isacloud.cc`.

Validado:

| Cenário | Resultado |
|---|---|
| Enquete com 3 opções, sem votos | título, descrição, opções e `Nenhum voto ainda`; body de fallback não duplicado |
| Voto legado com `1️⃣` + `2️⃣` (escolha única) | contou só no último (`Sushi` 1, demais 0) e `1 voto` |
| Voto de outra conta (`cookie@autozona.cc`) | barra rosa, contagem 1 e sem marca de "meu voto" |
| `hide-results` sem voto | `Vote para ver os resultados`, sem contagem/barra |
| `deadline` no passado | `Enquete encerrada` |
| `<poll-closed>` recebido | cartão com placar congelado e `Resultado final · 1 voto` |
| Chips de reação | votos não aparecem como chip (sem duplicação) |
| Tema claro e escuro | legível nos dois |

Observações para a fase 2:

- O check de "meu voto" marca todas as opções em que a conta reagiu (mesmo quando o tally de
  escolha única conta apenas a última). Só é visível em teste com a mesma conta nas duas pontas;
  com a votação implementada o cliente sempre envia o conjunto correto.
- `poll-closed` é renderizado como cartão próprio e **não** marca a mensagem original como
  encerrada; isso é da fase 3 (resolver por `remoteMsgId`).
- Enquete vencida por deadline continua mostrando o placar (o Fluux faz o mesmo); só o rodapé muda.
- Mantido o canal de teste `enquete-teste@conference.isacloud.cc` para a fase 2 — apagar depois.

## 8. Fase 2 — votação por toque (implementada)

- **Regra pura** em `Polls.toggleVote(poll, currentReactions, optionEmoji)`, porta de
  `enforceSingleVote`/`enforceMultiVote` do Fluux:
  - escolha única: remove **todos** os emojis de opção e adiciona a opção tocada; tocar de novo na
    opção já escolhida só remove o voto;
  - múltipla escolha: toggle apenas daquela opção;
  - reações que não são opção (ex.: 👍) são preservadas, na ordem original, e o emoji novo entra no
    fim; o resultado não tem duplicatas.
- **Normalização**: a comparação usa `Emoticons.normalizeToVS16` dos dois lados, mas o emoji
  enviado é sempre o **cru** de `poll.options[i].emoji` (nunca reconstruído). Para keycaps o
  `normalizeToVS16` é identidade (`1️⃣` continua exigindo VS16 exato); ele unifica apenas os
  emojis text-default com tabela fixa (ex.: `❤` ↔ `❤️`).
- `Polls.canVote(poll)` = poll não nulo e deadline (quando existir) no futuro. O encerramento por
  `<poll-closed>` é decidido pela mensagem, não pela enquete.
- **Envio**: `XmppActivity.sendReactions(message, reactions, rememberQuickReactions)`; o voto usa
  `false` para não poluir as reações rápidas. A assinatura antiga delega com `true`. O envio
  continua sendo o conjunto completo de reações no stanza-id da mensagem, como o Fluux espera, e
  passa pelas restrições de reação da sala (com os toasts existentes).
- **Clique**: habilitado só quando a mensagem tem `<poll>`, não tem `<poll-closed>`, `canVote`,
  a conversa é `MODE_MULTI` e existe occupant-id (mesma condição do `ReactionManager` para reagir
  em MUC). Caso contrário a linha fica como na fase 1, sem ripple e sem listener.
- **UX**: a linha clicável ganha o ripple do tema (`selectableItemBackground`), foco de teclado e
  `contentDescription` com emoji + rótulo; as demais mantêm a aparência legível, **sem** alpha de
  "desabilitado" (o rodapé já sinaliza "Enquete encerrada"/"Resultado final").
- O estado de "meu voto" (check + negrito) é atualizado pelo próprio `ReactionManager`, que
  persiste as reações e chama `updateConversationUi()`.
- **Modo de seleção**: `isPollVotable` também exige `!selectionMode`; o `setSelectionState` já
  dispara `notifyDataSetChanged`, então as linhas voltam a ficar clicáveis ao sair da seleção.
  Sem esse guarda, um toque durante a seleção votaria em vez de selecionar a mensagem.

## 9. Validação da votação no emulador

Mesmo setup da fase 1 (`isaPoll_API36` em `5556`, conta `poli2@isacloud.im`) e um observador
conectado como `cookie@autozona.cc` imprimindo as stanzas `<reactions>` que chegam à sala.

| Ação no app | Stanza observada | UI |
|---|---|---|
| tocar em "Café" (escolha única) | `reactions id=<stanza-id do poll> ["1️⃣"]` | Café 1, check, `1 voto` |
| tocar de novo em "Café" | `reactions id=<mesmo> []` | `Nenhum voto ainda` |
| tocar em "Café" e depois em "Chá" | `["1️⃣"]` e depois **`["2️⃣"]`** | só Chá marcado |
| múltipla escolha: "Yoga" e "Corrida" | `["1️⃣"]` e depois `["1️⃣","2️⃣"]` | duas barras, cada uma com 1 |
| tocar em opção de enquete com `deadline` vencido | nenhuma stanza | nada muda |
| tocar em opção do cartão de `poll-closed` | nenhuma stanza | nada muda |
| entrar em modo de seleção e tocar na opção | nenhuma stanza | linha sem clique |

O `id` das reações é sempre o **stanza-id** da mensagem da enquete, e o emoji vai cru (com VS16),
como o Fluux espera. O resultado final da fase 2 fica compatível tanto na leitura quanto no voto.

## 10. Fase 3A — criação de enquete (implementada)

- **Entrada**: `AttachmentChoice.Type.POLL` + `attachment_choice_poll`, no menu do clipe, com
  `quickAction = false` (o enum também alimenta a preferência de ação rápida). Ícone reaproveitado
  (`ic_format_align_left_24dp`), porque o projeto não tem um vetor de enquete.
- **Onde aparece**: só em `MODE_MULTI`. O `onCreateView` roda antes da conversa ser definida, então
  a escolha é inflada e a visibilidade é recalculada em `reInit` (`updatePollAttachmentChoiceVisibility`).
  Em 1:1 a entrada fica `GONE`; se a conversa mudar, o mesmo fragmento se ajusta.
- **Bloqueio de envio**: `handleAttachmentChoice` exige `MODE_MULTI` **e** `occupantId()` da sala
  (mesma condição da votação/reação em MUC). Sem isso, mostra o toast `poll_unavailable` e não abre
  o dialog.
- **`<body>` de fallback**: `Polls.buildFallbackBody` replica `buildPollFallbackBody` do Fluux —
  `📊 Poll: <título>`, descrição (se houver) em linha própria e `<emoji> <rótulo>` por opção, com
  `\n` e sem linha em branco extra. O `📊 Poll:` é fixo, mesmo em pt-BR, para paridade.
- **Stanza**: `MessageGenerator.preparePacket` adiciona o `<poll>` e
  `<fallback for="urn:fluux:poll:0"><body/></fallback>` **no stanza externo**, como sticker e
  citação. Com PGP/OMEMO o `<poll>` continua fora do payload cifrado (decisão 8.1.2) e o body de
  fallback passa pelo caminho de criptografia existente.
- **`Poll.toElement()`**: monta o elemento com os setters do modelo (`allow-multiple`/`hide-results`
  só quando verdadeiros). O `deadline` é convertido de epoch millis para ISO 8601; a criação ainda
  não oferece prazo, mas enquetes recebidas com prazo sobrevivem ao round-trip.
- **Dialog** (`CreatePollDialog` + `dialog_create_poll.xml`/`item_poll_option_edit.xml`):
  pergunta obrigatória, descrição opcional, 2 a 9 opções com os emojis padrão `1️⃣…9️⃣` fixos por
  posição (renumerados ao remover, como o Fluux faz no envio), "Adicionar opção" oculto em 9 e
  remover só com mais de duas linhas. Checkboxes de múltipla escolha e ocultar resultados. Sem
  campo de prazo nesta v1.
- **Validação**: o botão "Criar" fica desabilitado até a pergunta estar preenchida e haver duas
  opções não vazias; opções vazias entre as preenchidas são descartadas no envio. Se por algum
  motivo a validação for contornada, o dialog mostra erro e não fecha.
- **Envio**: `ConversationFragment.createPoll` monta `Message` com o body de fallback e a
  `conversation.getNextEncryption()`, anexa o `Poll` e usa o `sendMessage` normal (status, eco e
  banco), fechando o menu de anexos. O encerramento (`<poll-closed>` + menu) fica para a fase 3B.
- **Testes**: `PollsTest` cobre o body com e sem descrição (string exata) e o round-trip
  `Poll.toElement()` → `Poll.from(...)`, incluindo a ausência dos atributos falsos.

## 11. Fase 3B — encerramento de enquete (implementada)

### 11.1 Estado "encerrada" na mensagem original

- `Message.POLL_CLOSED_AT = "isacloudPollClosedAt"` (`NUMBER`, epoch millis), com
  `getPollClosedAt()/setPollClosedAt(...)`; `NULL` significa enquete aberta.
- A mensagem original **não duplica** o tally congelado: ela só ganha o instante de fechamento. O
  placar oficial continua sendo o tally da mensagem de `<poll-closed>`.
- `DatabaseBackend` passou de 59 para **60**, com a coluna no `CREATE TABLE` e migração idempotente
  (`hasColumn`). `IndividualMessage.fromCursor` lê a coluna de forma defensiva (cursores de busca).

### 11.2 Envio do `<poll-closed>`

- `PollClosed.toElement()` monta `message-id`, `<title>`, `<description>` e um `<tally>` por opção
  (emoji, label, count e `voters` em CSV, omitido quando vazio). Para isso o modelo XML ganhou
  `setTitle`/`setDescription` no mesmo padrão do `<poll>`.
- `Polls.buildClosed(poll, pollMessageId, reactions)` reutiliza `tally(...)` (escolha única com
  last-write-wins por eleitor e múltipla escolha) e converte o eleitor para **nick**
  (`Jid.getResource()`), caindo para o JID e depois para o `occupant-id` quando não há resource —
  é o formato que o Fluux espera no atributo `voters` (§4.9 da análise).
- `Polls.buildClosedBody(closed)` gera o body de fallback `📊 Poll encerrada: <título>` com uma
  linha `<emoji> <label>: <count>` por opção. É só exibição para clientes legados; o Fluux lê o
  elemento estruturado. Difere do `📊 Poll closed:` do Fluux de propósito (texto pt-BR), mantendo o
  heading fixo do mesmo jeito que a criação usa `📊 Poll:`.
- `MessageGenerator.preparePacket` adiciona `<poll-closed>` e
  `<fallback for="urn:fluux:poll:0"><body/></fallback>` no stanza externo, como o `<poll>`.

### 11.3 Ação "Encerrar enquete"

- Item `close_poll` em `message_context.xml`, logo depois de `quote_message`.
- **Visibilidade**: só quando a mensagem tem `<poll>`, não tem `<poll-closed>`, não está marcada
  como encerrada (`getPollClosedAt()`), o status **não** é `STATUS_RECEIVED` (o criador é quem
  enviou), não está deletada nem falhou, a conversa é `MODE_MULTI` e a sala tem `occupant-id`.
  Mesmo critério da votação: sem occupant-id a sala não aceitaria as reações/voto.
- **Confirmação** (`MaterialAlertDialogBuilder`) antes de enviar: encerrar congela o placar para
  todos e não dá para reabrir.
- `ConversationFragment.closePoll(Message)`: `message-id` = `remoteMsgId` (id de cliente) com
  fallback para o `uuid`; monta o tally, envia a mensagem nova pelo fluxo normal (`sendMessage`,
  com `conversation.getNextEncryption()`) e **depois** marca a original com
  `setPollClosedAt(System.currentTimeMillis())`, persiste com `updateMessage(original, false)` e
  chama `updateConversationUi()`.

### 11.4 Recebimento

- `MessageParser`, após montar a mensagem de fechamento em MUC: procura a original por
  `findMessageWithRemoteId(message-id, counterpart)` e, se não achar, por
  `findMessageWithUuid(message-id)` (mensagens nossas podem estar sem `remoteMsgId`).
- **Verificação** (XEP-POLL §5.6): a original precisa ter `<poll>`, o título do `<poll-closed>`
  precisa ser idêntico e todos os emojis do tally precisam existir nas opções (subconjunto é
  aceito; emoji desconhecido rejeita). A identidade do criador é comparada por `occupant-id`
  quando as duas mensagens têm um; senão pelo nick (`Jid.getResource()` da mensagem de
  fechamento contra o da original).
- Verificado: `setPollClosedAt(timestamp da mensagem)` + `updateMessage(original, false)`.
  Rejeitado: nada muda na original (a mensagem de fechamento continua mostrando o placar
  congelado que veio no stanza).
- O eco da nossa própria mensagem (`status != STATUS_RECEIVED`) não repete o trabalho: o
  `closePoll` local já marcou a original. Sem original em memória (entrou depois) nada é feito —
  verificação retroativa por MAM fica para a fase 4.

### 11.5 UI

- `displayPollMessage` calcula `ended = message.getPollClosedAt() != null` (o nome `closed` já é o
  `PollClosed` da mensagem).
- Sem clique quando `frozen` (mensagem de fechamento) ou `ended`; `isPollVotable` também exige
  `getPollClosedAt() == null`.
- Rodapé: `frozen` → "Resultado final · N votos"; `ended` → "Enquete encerrada · N votos";
  `expired` → "Enquete encerrada"; depois os estados da fase 1. A original encerrada continua
  mostrando o placar ao vivo das reações, como no Fluux, só sem voto.
- Nenhum chip/estado visual novo.

### 11.6 Testes

`PollsTest` ganhou: escolha única com eleitor legado que reagiu com dois números (contagem e
nicks), múltipla escolha, `voters` vazio sem reações, body exato do encerramento, round-trip
`PollClosed.toElement()` → `PollClosed.from(...)` (message-id, título, descrição, tallies e
voters) e a verificação de título/emojis (`Polls.matchesClosedPoll`).



## 12. Validação das fases 3A e 3B no emulador

Mesmo setup (`isaPoll_API36` em `5556`, `poli2@isacloud.im`, sala de teste), com um segundo
cliente (`@xmpp/client`) como `cookie@autozona.cc` observando a sala.

### 12.1 Criação

- Enquete criada pelo menu do clipe saiu na sala exatamente no formato do Fluux:
  ```xml
  <message type="groupchat" id="<uuid>">
    <poll xmlns="urn:fluux:poll:0">
      <title>Almoco</title>
      <option emoji="1️⃣">Pizza</option>
      <option emoji="2️⃣">Sushi</option>
    </poll>
    <fallback xmlns="urn:xmpp:fallback:0" for="urn:fluux:poll:0"><body/></fallback>
    <body>📊 Poll: Almoco
  1️⃣ Pizza
  2️⃣ Sushi</body>
  </message>
  ```
  O `id` é o UUID local (o servidor acrescenta `stanza-id`), os atributos falsos são omitidos e o
  body de fallback só é usado por clientes que não conhecem a extensão.
- Segunda enquete com as duas caixas marcadas saiu com `allow-multiple="true" hide-results="true"`
  e o cartão exibiu "Selecione uma ou mais opções" e "Vote para ver os resultados".
- O dialog aceita 2 a 9 opções (emoji fixo por posição, renumerado ao remover), título obrigatório e
  descrição opcional; o botão "Criar" fica desabilitado até o formulário ser válido. O conteúdo
  ficou dentro de um `NestedScrollView` para 9 opções não empurrarem os botões para fora da tela.
- Sem campo de prazo nesta v1 (enquetes com `deadline` vindas do Fluux continuam funcionando).

### 12.2 Encerramento

| Cenário | Resultado |
|---|---|
| Encerrar enquete própria pelo menu | stanza `<poll-closed message-id="<uuid do poll>">` com 1 `<tally>` por opção; a original passa a "Enquete encerrada" e não aceita mais toque |
| Receber `<poll-closed>` do criador (outra conta) | original marcada como "Enquete encerrada · 1 voto"; mensagem de fechamento com "Resultado final · 1 voto" |
| Receber `<poll-closed>` de quem **não** é o criador | rejeitado: a original continua aberta ("1 voto") e só a mensagem de fechamento mostra o tally recebido |
| Enquete encerrada com zero votos | rodapé "Resultado final" (sem "0 voto") |

Detalhe do último item: em pt-BR o CLDR trata 0 como `quantity="one"` ("0 voto"), então
`withVoteCount(...)` omite a contagem quando não há votos, em vez de exibir o plural errado.

### 12.3 Pendências conhecidas (fase 4)

- IQ `poll-results` e verificação retroativa por MAM não foram implementados.
- Encerrar uma enquete **nossa** a partir de outro cliente (ex.: Fluux web) depende de a original
  ter `occupantId` persistido; sem ele, a comparação cai para nick e a original pode não ser
  marcada (a mensagem de fechamento continua correta).
- `voters` é gravado em nicks; nicks com vírgula quebrariam o CSV (limitação do protocolo do Fluux).
- O dialog de criação não oferece prazo nem emoji customizado.

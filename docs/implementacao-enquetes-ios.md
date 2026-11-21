# Implementação de enquetes no isaCloud iOS (handoff)

> Instruções para quem for implementar `urn:fluux:poll:0` no app iOS
> (`~/projects/swift/isaCloud-iOS`, fork do Monal). O Android já tem a v1 pronta; este
> documento descreve o protocolo, o que já existe no iOS, o que falta e as decisões que
> **não podem divergir**, para os dois apps conversarem entre si e com o Fluux.
>
> Referências no repo Android: `docs/analise-enquete-fluux.md` (análise completa) e
> `docs/decisoes-enquetes-fluux.md` (decisões e validação). Protocolo do outro cliente:
> `~/projects/js/fluux-messenger/docs/XEP-POLL_PROTOCOL.md`.

## 1. Resumo

Enquete não é XEP-0472 nem pubsub: é uma **mensagem de grupo** com um elemento `<poll>` e um
`<body>` textual de fallback. **O voto é uma reação XEP-0444** no emoji da opção, e o placar é
calculado no cliente a partir das reações. O criador encerra com uma mensagem nova
`<poll-closed>`.

Escopo da v1 (já decidido no Android, manter igual):

- só grupo/canal (MUC); 1:1 não tem cartão nem criação;
- em grupo criptografado (OMEMO) a enquete **funciona, mas trafega em claro** — o `<poll>` vai no
  stanza externo, como `<sticker/>`/`<isacloud-quote>`; sem aviso na UI;
- criação e encerramento na v1;
- só o conjunto padrão de emojis `1️⃣…9️⃣` na criação (até 9 opções), sem emoji customizado e
  sem campo de prazo (enquetes com `deadline` vindas do Fluux continuam aceitas);
- sem IQ `poll-results` e sem verificação retroativa por MAM (fase 4, opcional).

## 2. O protocolo no fio (não inventar variações)

### 2.1 Enquete

```xml
<message to="sala@conference.exemplo" type="groupchat" id="<uuid>">
  <body>📊 Poll: Almoço?
1️⃣ Pizza
2️⃣ Sushi</body>
  <poll xmlns="urn:fluux:poll:0">
    <title>Almoço?</title>
    <description>opcional</description>
    <option emoji="1️⃣">Pizza</option>
    <option emoji="2️⃣">Sushi</option>
  </poll>
  <fallback xmlns="urn:xmpp:fallback:0" for="urn:fluux:poll:0"><body/></fallback>
  <store xmlns="urn:xmpp:hints"/>
</message>
```

- Atributos `allow-multiple` e `hide-results`: **só enviar quando `true`** (ausência = falso).
  `deadline` é ISO 8601: o parser deve aceitar **com e sem frações de segundo** (JS `toISOString` manda `.000Z`; o formatador de `HelperTools.m:2968` exige frações, então tentar os dois).
- `<option emoji>` é a chave do voto: gravar o emoji **exatamente como veio**, sem normalizar nem
  reconstruir. Keycap é `U+0031 U+FE0F U+20E3` (em Swift: `"\u{0031}\u{FE0F}\u{20E3}"`).
- Corpo de fallback: `📊 Poll: <título>` + descrição (se houver) + uma linha `<emoji> <rótulo>`
  por opção. O prefixo `📊 Poll:` é fixo (mesmo em pt-BR) — clientes legados exibem esse texto.
- `<id>` = UUID do cliente. O iOS sempre manda `<origin-id>` com o **mesmo** valor do `id` (`XMPPMessage.m:68`): é inofensivo, só não criar um id diferente. Título obrigatório, ≥2 opções.

### 2.2 Voto

```xml
<message to="sala@conference.exemplo" type="groupchat" id="<uuid>">
  <reactions xmlns="urn:xmpp:reactions:0" id="<stanza-id da mensagem da enquete>">
    <reaction>2️⃣</reaction>
  </reactions>
  <store xmlns="urn:xmpp:hints"/>
</message>
```

- O `id` é o **stanza-id** em MUC (o iOS já faz isso em `xmpp.m:4367`).
- O cliente envia o **conjunto completo** de reações do usuário (substituição), não um delta.
- **Escolha única**: remover todos os emojis de opção do conjunto e adicionar o escolhido;
  tocar de novo na opção escolhida remove o voto; reações que não são opção (ex.: 👍) são
  preservadas.
- **Múltipla escolha**: toggle apenas daquela opção.
- Enviar sempre o emoji **cru** da opção, nunca uma variante normalizada.

### 2.3 Encerramento

```xml
<message to="sala@conference.exemplo" type="groupchat" id="<uuid>">
  <body>📊 Poll encerrada: Almoço?
1️⃣ Pizza: 3
2️⃣ Sushi: 7</body>
  <poll-closed xmlns="urn:fluux:poll:0" message-id="<id da mensagem da enquete>">
    <title>Almoço?</title>
    <tally emoji="1️⃣" label="Pizza" count="3" voters="ana,bia"/>
    <tally emoji="2️⃣" label="Sushi" count="7"/>
  </poll-closed>
  <fallback xmlns="urn:xmpp:fallback:0" for="urn:fluux:poll:0"><body/></fallback>
</message>
```

- `message-id` = **id de cliente** da enquete (o `id` do stanza, não o stanza-id).
- `voters` = **nicks** separados por vírgula (não use occupant-id aqui). Atributo opcional: se o nick não for conhecido, **omitir** (nunca mandar JID).
- Só o criador encerra. Ao receber, verificar antes de congelar a original:
  remetente é o criador (no iOS: `participantJid` em grupo, depois occupant-id, depois nick), título idêntico e todo
  emoji de `tally` presente nas opções.

### 2.4 Contagem (copiar a regra do Fluux)

- Múltipla escolha: `count = nº de eleitores que reagiram com o emoji daquela opção`.
- Escolha única: cada eleitor conta **apenas na última opção** (na ordem das opções) em que
  reagiu — tolera cliente legado que reagiu com vários números. Ex.: reagiu `1️⃣` e `2️⃣` →
  conta só em `2️⃣`.
- Total de eleitores = união dos conjuntos (quem votou em N opções conta 1).
- `hide-results`: não mostrar contagem/barra até o usuário ter votado.
- `deadline` vencido: bloquear voto e mostrar "Encerrada" (só no cliente).

## 3. O que o isaCloud iOS já tem

| Peça | Onde | Situação |
|---|---|---|
| Núcleo XMPP (Obj-C) | `Monal/Classes/xmpp.m` | ✅ |
| Parser de stanza | `Monal/Classes/MLMessageProcessor.m` (`processMessage`) | ✅ |
| Consulta de extensões | `check:` / `findFirst:` / `find:` (sintaxe `{ns}elemento<attr=valor>@attr`) | ✅ |
| **Reações XEP-0444** | recebimento `MLMessageProcessor.m:508-677`; envio `xmpp.m:4367` (`sendReactions:forMessage:`) | ✅ completa |
| Armazenamento de reações | tabela `reactions` (`DataLayerMigrations.m:977`), agregação em `MLMessage.reactions` / `MLReactionsEntry` | ✅ |
| stanza-id / occupant-id | `MLMessageProcessor.m:306-314` / `:361-367` | ✅ |
| Fallback body de reação (XEP-0428) | `MLMessageProcessor.m:510-525` | ✅ (só para reações) |
| Envio com extensões customizadas | `xmpp.m:4211-4301` (sticker e citação) | ✅ padrão a seguir |
| Bolha própria do app | `GifMessageBubble` em `GifPickerView.swift:144`, usada em `ChatView.swift:1459/1473` | ✅ modelo para o cartão |
| Menu de contexto | `ChatView.swift:290` (`MessageAction`), `:347` (`menuItems`), `:1494` | ✅ |
| Menu do clipe | `ChatInputBar.swift:104-158` (`attachMenu`) | ✅ |
| Persistência | SQLite via `DataLayer` + migrações isaCloud (`DataLayerMigrations.m:1257`, hoje até a versão 8) | ✅ |
| i18n | `isaCloud/localization/{Base,pt-BR}.lproj/Localizable.strings` | ✅ |
| Testes de parsing | `Monal/MonalXMPPUnitTests/ParserTest.m` | ✅ modelo |

**O que não existe:** nada de `poll`/`enquete` no repo; nenhum elemento desconhecido é
preservado (a árvore `MLXMLNode` é transitória e não há coluna de XML cru), então um `<poll>`
sem tratamento **desaparece** — não dá para "ler depois".

## 4. Modelo de dados proposto

Espelhar o Android: três colunas JSON em `message_history`, em vez de tabela nova. As reações
já vivem na tabela `reactions`, que continua sendo a fonte do placar ao vivo.

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `isacloud_poll` | TEXT | JSON da definição: `{title, description?, allowMultiple, hideResults, deadline?, options:[{emoji,label}]}` |
| `isacloud_poll_closed` | TEXT | JSON do tally recebido/enviado: `{messageId, title, description?, tally:[{emoji,label,count,voters:[...]}]}` |
| `isacloud_poll_closed_at` | INTEGER | epoch millis; marca a **original** como encerrada (sem duplicar o tally nela) |

Passos:

1. `DataLayerMigrations.m`: nova entrada `updateISACloudDB:db toVersion:9` com
   `ALTER TABLE message_history ADD COLUMN ...` — seguir a regra do arquivo: cada passo precisa
   ser **idempotente** (checar a coluna antes).
2. `DataLayer.h/.m`: setters/getters seguindo `isSticker`/`quotedMessageId`
   (`DataLayer.m:2342-2378`).
3. `MLMessage.h/.m`: propriedades `poll`, `pollClosed`, `pollClosedAt` lidas em
   `fillMessage:fromDictionary:` (`MLMessage.m:78-115`), tolerantes a chave ausente.
4. `MLMessageProcessor.m`: ler `<poll>` / `<poll-closed>` logo depois de obter o `historyId`
   (modelo: bloco da citação em `:795`).

Alternativa (tabela própria, como `reactions`) só vale se surgir consulta por enquete; para v1
as colunas bastam.

## 5. Plano em fases

Espelha o Android (fases 1→3). Cada fase é entregável e testável.

### Fase 1 — leitura + cartão somente leitura

1. `MLMessageProcessor.m`: reconhecer `{urn:fluux:poll:0}poll`
   * título obrigatório e ≥2 opções com emoji e rótulo; senão ignorar o elemento;
   * gravar via `DataLayer`;
   * **não** remover o body: a UI decide esconder.
2. `MLMessageProcessor.m`: reconhecer `{urn:fluux:poll:0}poll-closed`, gravar no
   `pollClosed` da mensagem de fechamento e, se a original for encontrada
   (`getReactionHistoryIDForMessageIdOrStanzaId:` serve de modelo, mas em MUC só casa por **stanza-id**; o `poll-closed` aponta o id de **cliente**: criar consulta nova por `messageid` no mesmo chat),
   verificar criador/título/emojis e gravar `poll_closed_at` na original.
3. `ChatView.swift`: no `messageBuilder` (`:1437`), se `message.poll != nil || pollClosed != nil`
   e a conversa é MUC, renderizar `PollMessageBubble` (clone de `GifMessageBubble`) e **suprimir
   o texto** do balão (o body é só fallback).
4. Cartão: título, descrição, opções com emoji + rótulo + contagem + barra, rodapé com total e
   estados ("Nenhum voto ainda", "Voto para ver os resultados", "Encerrada").
5. Filtrar os emojis de opção do rodapé de reações (`ChatViewMessage.reactions`), para o voto não
   aparecer duas vezes — preservar 👍 e outros.

### Fase 2 — votação

1. Helper de votação (código puro, testável): dado `poll`, conjunto atual do usuário e emoji
   tocado, devolver o novo conjunto completo (regras da §2.2).
2. Toque na linha da opção → `account.sendReactions(novoConjunto, for: message)`.
   O método já persiste localmente e emite `kMonalUpdatedMessageNotice` — a UI atualiza sozinha.
3. Habilitar o toque **somente** com: `poll != nil`, `pollClosed == nil`, `pollClosedAt == nil`,
   deadline no futuro, conversa MUC, `message.stanzaId != nil` e a sala anunciando
   `urn:xmpp:occupant-id:0` (mesma condição de `canReactTo` em `ChatView.swift:~1700`).
4. Não registrar os emojis de voto na LRU de reações recentes (`RecentReactions.swift`), se o
   caminho de envio passar por lá.

### Fase 3 — criação e encerramento

1. **Criação**: item "Enquete" no `attachMenu` (`ChatInputBar.swift:104`), visível só em MUC com
   occupant-id. Dialog com pergunta, descrição opcional, 2–9 opções (emoji fixo por posição) e
   as caixas "múltipla escolha"/"ocultar resultados". Ao confirmar:
   * gravar o JSON da enquete em `isacloud_poll` **antes** de enviar, indexado pelo `messageId`
     (mesmo padrão da citação em `xmpp.m:4272` e da figurinha em `:4251`);
   * enviar pelo fluxo normal de mensagem (`MLXMPPManager.sendMessageAndAddToHistory`), com o
     body de fallback já no texto — assim status/eco/MAM funcionam como qualquer mensagem.
2. **Anexar no stanza**: em `xmpp.m:4211-4301`, se houver enquete para aquele `messageId`,
   adicionar `<poll>` + `<fallback for="urn:fluux:poll:0"><body/></fallback>`; se houver
   `poll-closed`, adicionar `<poll-closed message-id=...>` + o mesmo fallback.
3. **Bloquear "Editar"** (`MessageAction.edit`, `ChatView.swift:~410`) em mensagem com `poll`/`poll-closed`: editar mudaria o texto de fallback e deixaria o `<poll>` desatualizado.
4. **Encerrar**: item novo no `MessageAction` (`ChatView.swift:290/347`), visível só quando a
   mensagem é nossa, tem `poll`, não está encerrada, é MUC com occupant-id. Confirmar com um
   alerta e enviar a mensagem de fechamento (mesmo caminho do item 2), calculando o tally das
   reações atuais e `voters` em **nicks**. `MLReactionsEntry.mucNick` só existe em canal; em grupo buscar o nick nos participantes da sala e, se não achar, omitir `voters` (não usar JID);
   em seguida gravar `poll_closed_at` na original e recarregar a mensagem.
5. i18n: chaves em `isaCloud/localization/Base.lproj/Localizable.strings` e
   `pt-BR.lproj/Localizable.strings` (nunca em `Monal/localization/external/`).

### Fase 4 (opcional)

IQ `poll-results` e verificação retroativa por MAM. O Android não implementou; só vale se algum
cliente passar a consultar.

## 6. Armadilhas específicas do iOS

- **`stanzaId` pode ser nulo** logo após enviar uma mensagem (só chega com o eco do servidor).
  Sem stanza-id não há como votar — desabilitar o toque até ele existir.
- **Reação em MUC exige `urn:xmpp:occupant-id:0`** nas features da sala (`ChatView.swift:~1700`,
  `MLMessageProcessor.m:632`). Em sala sem isso, enquete deve aparecer como cartão, mas sem voto.
- **Identidade do eleitor muda por tipo de sala**: canal usa `occupant_id`, grupo/1:1 usa `jid`
  (`MLMessageProcessor.m:618-629`, `xmpp.m:4344-4352`). O helper de votação precisa usar a mesma
  chave que o app usa para "minhas reações", senão o check de "meu voto" erra.
- **Não reconciliar `voters` do `<poll-closed>` com a tabela `reactions`**: são nicks, não
  jid/occupant-id; misturar corrompe a agregação. Exibir o tally congelado direto.
- **VS16 / keycap (BUG EXISTENTE, tratar ANTES de tudo):** `HelperTools.createReactionsSetFromString`
  (`HelperTools.m:4482`) tira todo `U+FE0F` e reanexa no **fim** do cluster se o primeiro caractere está em
  `_validVs16Emojis` (que inclui `0-9 # *`). Resultado: `1️⃣` (`0031 FE0F 20E3`) volta do banco como
  `0031 20E3 FE0F`, que não bate com a opção e, pior, o toque de reação (`ChatView.swift:~1685`) reenvia o conjunto
  lido do banco, mandando um keycap malformado (o voto some no Android e no Fluux). Correção: (1) no parser,
  se o cluster contém `U+20E3`, remontar como `base + FE0F + 20E3`; (2) no helper de votação, comparar por
  chave normalizada (sem `FE0F`) e mandar sempre o emoji **cru** de `poll.options[i].emoji`.
  Teste unitário obrigatório do round-trip `1️⃣…9️⃣` (envio → banco → leitura).
- **`hide-results`**: sem voto do usuário, esconder contagem e barra (mas manter o título e as
  opções).
- **Restrição de reações por usuário**: o servidor pode anunciar
  `urn:xmpp:reactions:0:restrictions` com `max_reactions_per_user`. Se for 1, múltipla escolha e
  "voto + 👍" falham; vale checar antes de prometer a feature na sala.
- **OMEMO**: em grupo members-only o corpo é cifrado, mas o `<poll>` vai em claro (como
  `<file-sharing/>`). É decisão da v1; não tentar colocar o elemento dentro do payload cifrado,
  senão quebra a compatibilidade com o Fluux e com o Android.
- **Não alterar o fork do ExyteChat** para o cartão: usar o `messageBuilder`, como o
  `GifMessageBubble` já faz.

## 7. Testes

- **Unitário de parsing**: seguir `Monal/MonalXMPPUnitTests/ParserTest.m` (stream XML completo →
  `MLBasePaser` → asserções com `find:`/`check:`). Cobrir `<poll>` válido, inválido (sem título,
  <2 opções), flags ausentes/presentes e `<poll-closed>` com `tally`/`voters`.
- **Unitário de envio**: seguir `StickerFileSharingTests.swift` (monta `MLXMLNode` na mão e valida
  `xmlString`): `<poll>` com `allow-multiple="true" hide-results="true"`, opções com emoji cru, e
  `<poll-closed>` com `message-id` e tallies.
- **Unitário das regras**: tally (single com last-write-wins, múltipla, total sem duplicar),
  toggle do voto, `deadline`, `hide-results`.
- **Integração manual** (mesma sala usada pelo Android): `enquete-teste@conference.isacloud.cc`
  no `isacloud.im`. Fluxos a validar:
  1. Android cria → iOS lê, vota e o Android conta;
  2. iOS cria → Android lê e vota → iOS conta;
  3. Android encerra → iOS marca a original e mostra o resultado congelado;
  4. iOS encerra → Android idem;
  5. voto legado com `1️⃣`+`2️⃣` em enquete de escolha única conta só no último;
  6. `hide-results` antes/depois de votar;
  7. `poll-closed` de quem não é o criador é ignorado.
- No Android há um script `@xmpp/client` (Node, não versionado) que entra na sala, cria/vota/
  encerra e imprime as stanzas — útil para gerar os casos acima sem depender da UI.

## 8. Checklist de aceite

- [ ] `<poll>` enviado pelo iOS é lido pelo Android e pelo Fluux (título, descrição, opções).
- [ ] Enquete criada no Fluux aparece com cartão no iOS e o corpo de fallback não é duplicado.
- [ ] Voto do iOS aparece no Android como reação com o **stanza-id** correto e sem duplicar.
- [ ] Escolha única no iOS substitui o voto (o Android não vê dois números no mesmo eleitor).
- [ ] Múltipla escolha acumula.
- [ ] Encerrar no iOS: Android marca a original e mostra "Enquete encerrada".
- [ ] Encerrar no Android: iOS idem.
- [ ] Enquete encerrada não aceita mais toque nos dois apps.
- [ ] Sala sem `occupant-id`: cartão aparece, voto desabilitado, nada quebra.
- [ ] Grupos/canais e 1:1: 1:1 mostra só o texto legado.
- [ ] Textos novos em inglês e pt-BR.

## 9. Referência de implementação no Android

Portar a lógica (não a arquitetura) destes arquivos:

| Arquivo | O que contém |
|---|---|
| `src/main/java/eu/siacs/conversations/utils/Polls.java` | tally, toggle do voto, `buildFallbackBody`, `buildClosed`, `buildClosedBody`, verificação título/emojis |
| `src/main/java/eu/siacs/conversations/entities/{Poll,PollClosed}.java` | modelo + JSON |
| `src/main/java/im/conversations/android/xmpp/model/poll/*` | modelo XML (`@XmlElement`) |
| `src/main/java/eu/siacs/conversations/parser/MessageParser.java` | parse, supressão do body, verificação do criador |
| `src/main/java/eu/siacs/conversations/generator/MessageGenerator.java` | anexo de `<poll>`/`<poll-closed>` no stanza externo |
| `src/main/java/eu/siacs/conversations/ui/adapter/MessageAdapter.java` | cartão, estados, filtro dos chips |
| `src/main/java/eu/siacs/conversations/ui/ConversationFragment.java` + `ui/widget/CreatePollDialog.java` | criação e encerramento |

Cuidado ao portar: no Android o placar vem de `Message.getReactions()` (lista de `Reaction`); no
iOS vem de `MLMessage.reactions` (`NSOrderedSet<MLReactionsEntry>`), em que **cada entry é um
usuário e carrega o conjunto de emojis daquele usuário** — a iteração é por entry, não por reação
individual.

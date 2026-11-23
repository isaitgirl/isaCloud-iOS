# Guia: reply XEP-0461 (fases 1 e 2) no isaCloud Android e no isaCloud Web

Escrito em 23/11/2026, depois das fases 1 e 2 entrarem no iOS (build 128, PR 89 do app e PR 24 do fork do ExyteChat).
Este guia diz **o que cada app precisa fazer** para falar o reply igual ao iOS. A regra do que vai no stanza é o
[contrato](contrato-reply-xep0461.md); se algo aqui divergir dele, vale o contrato, e quem achar a divergência avisa
para corrigir nos três apps.

- **Fase 1 (protocolo):** mandar e ler `<reply>` e `<fallback>`, sem mudar a tela.
- **Fase 2 (toque):** tocar na citação de uma resposta leva até a mensagem original.

## 1. O que o iOS faz hoje (a referência)

### Envio
Uma resposta com o ID da original conhecido, **e** com o corpo começando pela citação, leva:

```xml
<message type='groupchat' to='sala@conference.exemplo.im' id='…'>
  <body>&gt; Ana: 📷 Foto
Que lindo!</body>
  <reply xmlns='urn:xmpp:reply:0' to='sala@conference.exemplo.im/Ana' id='STANZA-ID-DA-ORIGINAL'/>
  <fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
    <body start='0' end='10'/>
  </fallback>
  <isacloud-quote xmlns='urn:isacloud:quote:0' id='STANZA-ID-DA-ORIGINAL'/>
</message>
```

- **`id`:** em grupo e canal, **só** o `stanza-id` dado pela sala. Se ele não existe (por exemplo, a minha mensagem antes do eco da sala), a resposta vai **sem** `<reply>`, só com a citação em texto. Em 1:1, o `origin-id` da original, e na falta dele o `id` do stanza.
- **`to`:** o autor da original, achado no banco. Em grupo, `sala/apelido`; em 1:1, o JID sem recurso do contato; se a original é minha, o JID da minha conta. Sem a original no banco, vai sem `to` (é um SHOULD).
- **`<fallback>`:** `start='0'` e `end` = o fim do bloco citado do começo do corpo, **incluindo** a quebra de linha que o separa da resposta. O `end` é exclusivo e contado em **pontos de código Unicode** (seção 4).
- **Sem fallback, sem reply:** se a pessoa apagou a citação do campo, ou se nada vem depois dela, não vai nem `<reply>` nem `<fallback>`.
- **`<isacloud-quote>`:** continua indo, com o **mesmo** `id`, só quando a original é foto, GIF ou figurinha. É para os apps que ainda não leem `<reply>` continuarem mostrando a miniatura (seção 5).
- **OMEMO (o legado, `eu.siacs.conversations.axolotl`):** os três elementos vão **fora** do `<encrypted>`. Só o `<body>` é cifrado. As posições do fallback valem para o corpo **antes** de cifrar.
- **Disco:** o app anuncia `urn:xmpp:reply:0`.

### Leitura
- `<reply>@id` primeiro; se não houver, `<isacloud-quote>@id`. O ID fica guardado com a mensagem.
- Vale para mensagens ao vivo, do MAM e de carbons.
- A original é achada, **na mesma conversa**, pelo `stanza-id` (grupo e canal) ou pelo `origin-id` e o ID da mensagem (1:1).
- O iOS **não esconde** o trecho do fallback: ele já desenha a citação a partir do corpo. Quem desenha um cartão próprio (como o Web) deve esconder o trecho do fallback para não citar em dobro.

### Toque na citação (fase 2)
- Tocar no **primeiro** bloco citado de uma resposta leva até a original.
- Se a original não está na tela, o app carrega do banco as mensagens entre ela e o que está à mostra e rola até ela.
- **A lista continua visível durante o pulo.** No iOS, o primeiro desenho escondia a lista enquanto rolava (como faz a abertura pela busca), e isso deixava a conversa em branco por cerca de 1 segundo. A Isadora reprovou. Não repetir.
- **Original ausente, retratada ou longe demais:** um aviso curto, "Mensagem original indisponível" (em inglês, "Original message unavailable"), por uns 2,5 s, sem diálogo.
- **Citação antiga, sem ID** (só texto): o toque não faz nada.

### Servidor
O `mod_mam` e o `mod_muc_mam` do Prosody guardam o stanza inteiro (só tiram os chatstates). Então `<reply>`,
`<fallback>` e `<isacloud-quote>` voltam pelo histórico, e o toque funciona também em mensagens antigas.

## 2. isaCloud Android (fork do Conversations)

Base: [decisoes-reply-real-android.md](decisoes-reply-real-android.md), de 10/11/2026. Ali estão os nomes do código de
lá (`MessageUtils.prepareQuote()`, coluna `isacloudQuoteId` no banco 57, `pendingScrollToMessageUuid`,
`applyPendingSearchScroll()`). **Antes de começar, confira se o Conversations upstream já trouxe XEP-0461** desde a
release em que o fork está; se trouxe, mescle e ajuste a ele em vez de escrever do zero.

### Fase 1
1. **Envio:** onde a resposta é montada, junte `<reply>` e `<fallback>` seguindo a seção 1. O ID sai da mesma regra que o `isacloud-quote` já usa, mas para **qualquer** tipo de mensagem (texto, áudio, arquivo, localização…). O `to` sai da mensagem original.
2. **`isacloud-quote`:** continue mandando, só para foto, GIF e figurinha, com o mesmo ID.
3. **Fallback:** calcule o `end` contando **pontos de código** (seção 4). No Java, `body.codePointCount(0, fimDoBlocoEmUtf16)`; **nunca** `String.length()`.
4. **OMEMO:** `<reply>`, `<fallback>` e `isacloud-quote` vão **fora** da criptografia, como o `isacloud-quote` já vai.
5. **Leitura:** leia `<reply>@id` com precedência sobre `isacloud-quote@id`. Guardar o `to` é opcional (a análise de lá prevê colunas `replyToId` e `replyToTo`; é decisão local, não muda o que vai no stanza).
6. **Disco:** anuncie `urn:xmpp:reply:0` (`ServiceDiscoveryResult`/lista de features).
7. **Testes de unidade** com a tabela da seção 4.

### Fase 2
1. Torne o bloco citado clicável **só** quando a mensagem tem o ID da original.
2. No toque, ache a original pelo ID na mesma conversa e reaproveite o pulo da busca (`pendingScrollToMessageUuid` + `applyPendingSearchScroll()`), que já carrega uma página de histórico quando precisa. **Sem esconder a lista** durante o pulo (seção 1).
3. Original ausente, retratada ou longe demais: um `Toast` (ou `Snackbar`) curto, "Mensagem original indisponível".
4. O clique no bloco não pode roubar o toque longo do menu nem o deslizar para responder. Links dentro da citação: no iOS eles não são clicáveis e a Isadora disse que não precisa; no Android, se já são, mantenha.
5. Texto novo de interface com tradução pt-BR.

## 3. isaCloud Web (fork do Converse.js 14, `~/projects/js/isaCloud-Web`)

O Converse 14 **já tem XEP-0461**: monta o fallback (`addReplyFallback` em `src/headless/shared/model-with-messages.js`),
conta o `end` em pontos de código (`[...quote].length`), manda `<reply>` e `<fallback>` (`createMessageStanza`), lê o
`<reply>` (`src/headless/shared/parsers.js`), esconde o fallback na exibição (`src/headless/shared/message.js`),
anuncia `urn:xmpp:reply:0` no disco (`src/headless/plugins/chat/plugin.js`) e tem o cartão de contexto com rolagem e
destaque (`src/shared/chat/reply-context.js`). Em grupo, o ID é o `stanza-id` (`getReferenceID` → `getArchiveID`).
O que falta são **ajustes ao contrato**, de preferência num plugin `isacloud-*` próprio (como `isacloud-polls`), para
não mexer no núcleo do Converse:

### W1. OMEMO legado: hoje o Web não manda o reply
- Com OMEMO 2 (SCE), o Web põe `<reply>` e `<fallback>` **dentro** do `<content>` cifrado (`getSCEExtensions` em `src/headless/plugins/omemo/utils.js`). Está certo para quem fala OMEMO 2.
- Com o OMEMO **legado**, que é o que o iOS e o Android usam, nada disso vai: `createMessageStanza` só põe `<reply>` quando `!is_encrypted`, e o comentário do `getSCEExtensions` diz que o OMEMO 1 "degrada". Resultado: uma resposta cifrada do Web chega ao iOS e ao Android sem referência.
- **Fazer:** quando a mensagem sai em OMEMO legado, acrescentar `<reply>` e `<fallback>` **fora** do `<encrypted>`, como manda o contrato (por exemplo, no hook `createMessageStanza` ou depois da cifragem). O `end` é o do corpo em texto, antes de cifrar.
- **Na leitura:** conferir que uma mensagem OMEMO legado vinda do iOS, com `<reply>` em texto aberto, preenche `reply_to_id`. Se o parser do OMEMO só procura metadados dentro do conteúdo cifrado, ler também do stanza.

### W2. Ler o `isacloud-quote`
O Android de hoje e as mensagens antigas do iOS só trazem `<isacloud-quote id='…'/>`. Na leitura, se não houver
`<reply>`, usar o `id` do `isacloud-quote` como `reply_to_id` (sem `reply_to`). Sem isso, essas respostas aparecem só
como citação em texto, sem o cartão nem a rolagem.

### W3. Mandar o `isacloud-quote` na transição
Ao responder a **foto, GIF ou figurinha**, acrescentar `<isacloud-quote xmlns='urn:isacloud:quote:0' id='…'/>` com o
mesmo ID do `<reply>`, fora da criptografia. Enquanto o Android não ler `<reply>`, é o que mostra a miniatura lá.

### W4. Original fora da tela
O `scrollToRepliedMessage` só funciona se a original já está carregada no DOM; se não está, não acontece nada.
- **Fazer:** se a original não está carregada, buscar no MAM em volta do `stanza-id` dela (ou carregar páginas até achá-la) e então rolar. Não esconder a lista durante a busca.
- Se não achar, ou se a original foi retratada: mostrar "Mensagem original indisponível" por uns 2,5 s.

### W5. Formato da citação (só conferir)
O Web cita como `> Nome:` numa linha e o texto nas linhas seguintes, cortado em 80 pontos de código. O iOS cita como
`> Nome: texto` numa linha só. Os dois formatos são válidos: o `<fallback>` cobre o bloco inteiro e cada app desenha a
seu modo. Só conferir no iOS que a resposta do Web aparece como uma citação só, sem linha solta.

## 4. Contagem das posições (a armadilha principal)

A XEP-0426 conta em **pontos de código Unicode**, sobre o corpo já decodificado do XML (`&gt;` conta 1), sem
normalizar, com `end` exclusivo.

| Plataforma | Certo | Errado |
|---|---|---|
| Swift (iOS) | `texto.unicodeScalars.count` | `String.count`, `NSString.length`, `NSRange` |
| Java (Android) | `s.codePointCount(0, s.length())`; `s.offsetByCodePoints(0, n)` para voltar | `String.length()` (UTF-16) |
| JavaScript (Web) | `[...s].length`, `Array.from(s)` | `s.length`, `slice` com índice UTF-16 |

Casos que os três apps devem passar (os mesmos dos testes do iOS, em `QuoteFormattingTests`):

| Corpo | `end` esperado |
|---|---|
| `> Ana: oi\nTudo bem?` | **10** |
| `> 📷 Foto\nLindo!` | **9** (em UTF-16 seriam 10) |
| `> Ana: 🎞️ GIF\nKkk` | **14** (o `🎞️` são 2 pontos de código; em UTF-16 seriam 15) |
| `> João: ação\nOk` | **13** (acentos compostos; não normalizar) |
| `> Ana\n> Vamos?\nBoa ideia!` | **15** (o bloco tem duas linhas) |
| `Só um texto\n> Ana: oi` | sem fallback e sem reply (a citação não está no começo) |
| `> Ana: oi` | sem fallback e sem reply (nada depois da citação) |

**Limitação aceita no iOS:** o bloco é a sequência de linhas que começam com `>` no começo do corpo. Se a pessoa
digitar uma linha começando com `> ` logo depois da citação, ela entra no fallback. Quem monta o fallback a partir da
citação que o próprio app inseriu (como o Web) não tem esse problema; o resultado no stanza é o mesmo nos casos normais.

## 5. Transição (a ordem importa)

1. **Todos leem `<reply>`** e continuam lendo `isacloud-quote`. O iOS já faz; o Android e o Web (W2) precisam.
2. **Todos mandam `<reply>` + `<fallback>`**, mais `isacloud-quote` nas respostas a foto, GIF e figurinha. O iOS já faz; o Android precisa; o Web precisa de W1 e W3.
3. **Só depois de alguns builds com os três apps atualizados**, todos param de mandar `isacloud-quote`. A **leitura** fica para sempre, por causa do histórico.

Se um app parar de mandar `isacloud-quote` antes de os outros lerem `<reply>`, a miniatura some entre eles.

## 6. Como testar entre os apps

Para cada par (iOS ↔ Android, iOS ↔ Web, Android ↔ Web), num 1:1 **com OMEMO** e num canal:
1. Responder a um texto, a uma foto e a um vídeo.
2. Do outro lado: a resposta aparece com a citação (ou o cartão), sem citação em dobro, e o toque leva à original.
3. Responder, apagar a citação do campo e mandar: chega como mensagem comum, sem referência.
4. Responder a uma mensagem e depois retratar a original: o toque mostra "Mensagem original indisponível".
5. Um cliente de fora com XEP-0461 (Gajim, Dino, Cheogram) mostra as respostas de forma nativa. No iOS isso foi conferido no Gajim.
6. No log, conferir que o `end` do fallback bate com o texto citado (seção 4).

## 7. Depois disso

- **Fase 3 no iOS:** notificação sem o trecho citado (mexe na extensão de notificação) e cartão para `<reply>` que chega **sem** fallback.
- **Fios (XEP-0201):** análise em [analise-fios-xep0201.md](analise-fios-xep0201.md). O fio se ancora no `<reply>`, então depende dos três apps falarem o reply igual. O contrato dos fios vem depois deste guia estar feito nos três.

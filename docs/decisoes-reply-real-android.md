# Decisão: reply real de mensagens (XEP-0461)

Status: **avaliação revista em 10/11/2026**. Nada de XEP-0461 foi implementado. A base atual já tem
citação textual para todos os tipos de mídia e o elemento próprio `<isacloud-quote>` para foto, GIF e
figurinha, com miniatura. O reply real passa a ser avaliado incluindo **foto, figurinha, vídeo e
áudio** como mensagens citadas.

## Contexto atual (release 62, banco 57)

O que já existe:

- **Citação textual para qualquer mídia**: `MessageUtils.prepareQuote()` usa
  `classifyQuotableMedia()` e gera rótulos como `📷 Foto`, `🎞️ GIF`, `🎭 Figurinha`, `🎥 Vídeo`,
  `🎤 Mensagem de áudio`, `📎 Arquivo` e `📍 Localização`. O corpo nunca usa a URL/OOB da mídia.
- **`<isacloud-quote>`**: elemento `urn:isacloud:quote:0` com apenas o `id` da mensagem citada. Hoje é
  enviado **somente** quando a original é foto, GIF ou figurinha. O `id` é o `stanza-id` em
  grupo/canal e o id do stanza (ou `origin-id`, quando existir) em 1:1.
- **Miniatura na citação**: foto, GIF e figurinha mostram a miniatura dentro da barra da citação,
  abaixo do autor/rótulo, quando o arquivo já está no aparelho. A implementação usa
  `quoteId`/`isacloudQuoteId`, cache próprio (`getQuoteThumbnail`) e `QuoteThumbnailSpan`.
- **Banco 57** com a coluna `isacloudQuoteId` e migração idempotente.
- **Busca com “ir para mensagem”**: `pendingScrollToMessageUuid` e `applyPendingSearchScroll()` já
  localizam uma mensagem por UUID, rolam até ela e carregam uma página de histórico quando necessário.

O que **não** existe:

- namespace/modelo XEP-0461 (`urn:xmpp:reply:0`), envio e leitura de `<reply>`;
- campo com o JID do autor da mensagem citada (`to`);
- clique na citação para pular até a original;
- referência para vídeo, áudio, arquivo ou localização;
- reply em que a **nova** mensagem é uma mídia (o fluxo atual envia texto **ou** anexo, nunca os dois).

A branch `c3` continua sendo referência de protocolo/UI, mas não é código reaproveitável na `custom`.

## Veredito

É viável e não exige mudança de servidor. A XEP-0461 é o formato de interoperabilidade; o
`<isacloud-quote>` deve continuar existindo como compatibilidade com as versões atuais do isaCloud e
com o iOS.

A avaliação por tipo de mídia citada:

| Original citada | Situação hoje | Trabalho para reply real |
|---|---|---|
| Texto | citação textual | baixo: `<reply>`, referência no banco, clique |
| Foto | rótulo + `<isacloud-quote>` + miniatura | baixo: `<reply>` reutiliza o mesmo `id`; clique |
| GIF | rótulo + `<isacloud-quote>` + miniatura (1º quadro) | baixo: idem |
| Figurinha | rótulo + `<isacloud-quote>` + miniatura | baixo: idem |
| Vídeo | só rótulo | médio: passar a gerar id, cartão e miniatura de vídeo; sem player inline no MVP |
| Áudio | só rótulo | médio: passar a gerar id e cartão com ícone/duração; sem waveform no MVP |
| Arquivo | só rótulo | baixo/médio: mesmo fluxo do vídeo, com nome do arquivo |
| Localização | só rótulo | baixo: mesmo fluxo, sem miniatura |

Complexidade geral: **média**. Risco: **médio**. O ponto mais delicado continua sendo a identidade da
mensagem original entre origin-id, stanza-id e MAM; a mídia acrescenta outro ponto: **o arquivo pode
não estar no aparelho**, e o cartão não pode depender dele.

> A XEP-0461 ainda é **Experimental** (versão 0.2.1, fevereiro de 2026). Isso não impede o uso, mas
> recomenda manter o fallback textual e o elemento próprio durante a transição.

## Dois escopos que não podem ser confundidos

1. **Responder a uma mídia** (a original é foto, figurinha, vídeo ou áudio). É o foco principal deste
   documento. A resposta continua sendo uma mensagem normal, geralmente de texto; o que muda é levar
   a referência e permitir o cartão/clique.
2. **Responder com mídia** (a nova mensagem é uma mídia, eventualmente com texto). Depende de mudar o
   compositor e o envio de “texto OU mídia” para “texto e/ou mídia”. Está analisado em
   [`responder-com-midia.md`](responder-com-midia.md) e fica para uma fase posterior.

## 1. Protocolo

Criar o modelo no padrão das extensões existentes:

- `Namespace.REPLY = "urn:xmpp:reply:0"`;
- `im.conversations.android.xmpp.model.reply.Reply` com `to` e `id`;
- `MessageParser`: ler `<reply>` do stanza já desembrulhado (MAM/carbon), no mesmo ponto em que hoje
  lê `IsacloudQuote`;
- `MessageGenerator.preparePacket()`: adicionar `<reply>` em **qualquer** mensagem que tenha
  referência, inclusive mídia, OMEMO e PGP. O elemento fica **fora** da criptografia, como o
  `<isacloud-quote>` e a marca de figurinha;
- anunciar `urn:xmpp:reply:0` em disco/caps. A XEP exige o feature quando o cliente implementa
  replies.

Exemplo do stanza da resposta:

```xml
<message type='chat' to='contato@exemplo' id='resposta-123'>
  <body>&gt; Ana:
&gt; 📷 Foto
Legal!</body>
  <reply xmlns='urn:xmpp:reply:0' to='ana@exemplo/recurso' id='ID-DA-ORIGINAL'/>
  <isacloud-quote xmlns='urn:isacloud:quote:0' id='ID-DA-ORIGINAL'/>
  <fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
    <body start='0' end='N'/>
  </fallback>
</message>
```

### 1.1. `id` e `to` corretos

A XEP-0461 é mais específica que o `<isacloud-quote>`:

| Conversa | `id` | `to` |
|---|---|---|
| 1:1, mensagem recebida | `origin-id` (XEP-0359) se existir; senão o `id` do stanza | JID completo do autor (`from`); o bare é aceito em 1:1 |
| 1:1, mensagem enviada | `origin-id`/UUID local; senão o id do stanza | JID da própria conta (o autor da original é você) |
| Grupo/canal | **somente** o `stanza-id` dado pela sala (XEP-0359) | JID do ocupante autor (`sala@conferencia/nick`) ou o JID real, quando conhecido |
| Grupo/canal sem `stanza-id` | **não é possível responder pela XEP** | — |
| Mensagem privada em grupo | tratar como 1:1 | JID do autor |

Observações:

- Em grupo, a XEP proíbe usar o `id` do stanza; sem `stanza-id` a resposta deve continuar só textual.
- O `to` é informativo para a interface e para o retry; a resolução local deve priorizar o `id`.
- O código atual já escolhe bem o id para foto/GIF/figurinha em `getQuotableMessageId()`. A mudança é
  **generalizar** essa escolha para vídeo, áudio (e, opcionalmente, arquivo/localização) e acrescentar
  o `to`.

### 1.2. Fallback textual

Manter o corpo com o bloco citado (`> autor:` + rótulo ou trecho) e indicar o trecho com XEP-0428:

```xml
<fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
  <body start='0' end='N'/>
</fallback>
```

Regras:

- `end` é o fim do bloco citado no corpo, contando os caracteres enviados.
- Só enviar o fallback quando o corpo **começar** com o bloco citado. Se a pessoa apagar a citação do
  compositor, não enviar `<reply>` nem fallback.
- Em uma resposta cuja nova mensagem é só mídia, o corpo pode ser URL/OOB e não ter bloco citado;
  nesse caso, não enviar fallback.
- Quem recebe e **renderiza** a mensagem original (cartão/bloco clicável) não deve mostrar o fallback
  duplicado. Quem não consegue resolver a original pode mostrá-lo.

### 1.3. Coexistência com `<isacloud-quote>`

Durante a transição, o recomendado é:

- **enviar os dois** para foto, GIF e figurinha, com o mesmo `id`;
- **enviar só `<reply>`** para texto, vídeo, áudio, arquivo e localização (o `<isacloud-quote>` atual
  não os cobre);
- na recepção, **preferir `<reply>`** e usar `<isacloud-quote>` como fallback quando `<reply>` não
  estiver presente (mensagens antigas e versões anteriores do app/iOS);
- guardar as duas referências sem duplicar a miniatura: `replyToId` é a referência principal;
  `quoteId` continua servindo de espelho para o formato antigo.

Isso evita quebrar a miniatura nas versões atuais e permite que clientes com XEP-0461 (Dino, Gajim
etc.) mostrem o reply corretamente.

## 2. Persistência

Adicionar duas colunas nullable em `messages`:

- `replyToId`: id da mensagem original (`origin-id`, id do stanza ou `stanza-id`);
- `replyToTo`: JID do autor daquela mensagem.

Detalhes:

- `Message.REPLY_TO_ID` e `Message.REPLY_TO_TO`;
- campos + getters/setters em `Message`;
- `Message.fromCursor()` lê as colunas depois do construtor, sem mexer no construtor de 25
  parâmetros;
- `Message.getContentValues()` grava os campos;
- `DatabaseBackend`: `DATABASE_VERSION` **57 → 58**, duas colunas no `onCreate()` e migração
  idempotente no `onUpgrade()` (checar `hasColumn` antes de criar, como já é feito para
  `isacloudQuoteId`).

Não é necessário índice para o MVP: a busca da original acontece na lista carregada e, quando muito,
em uma consulta por conversa. Se a consulta por id se mostrar frequente, avaliar um índice depois.

### 2.1. Precedência na leitura

- Se o stanza tiver `<reply>`: preencher `replyToId` e `replyToTo`.
- Se tiver apenas `<isacloud-quote>`: preencher `quoteId`; para exibição, tratar `quoteId` como
  referência sem `to`.
- Se tiver os dois: preencher ambos com o mesmo id; a UI usa `replyToId ?? quoteId`.
- Ao responder a uma mensagem antiga que só tem `quoteId`, resolver a original localmente e derivar o
  `to` dela antes de enviar o `<reply>`.

## 3. Composição

Reaproveitar o gesto e o menu atuais:

- `quoteMessage(Message)` passa a guardar `pendingReply` (id + to) além do texto inserido;
- `getQuotableMessageId()` deixa de ser restrito a foto/GIF/figurinha e passa a cobrir vídeo e áudio;
  criar um helper equivalente para o `to`;
- `sendMessage()` cria a mensagem normalmente e, se houver `pendingReply` e o corpo ainda contiver a
  linha citada, aplica `message.setReplyTo(...)`;
- `messageSent()` e `reInit()` limpam o `pendingReply`;
- se a pessoa apagar a citação do compositor, o envio não leva `<reply>`;
- o “Desfazer” do X já restaura `pendingQuoteId`/`pendingQuoteLine`; deve restaurar também o `to`;
- edição de mensagem não altera a referência;
- rascunho/rotação/troca de conversa: o texto é preservado, mas o `pendingReply` pode se perder. É uma
  limitação aceitável no MVP, igual à do `<isacloud-quote>` atual.

### 3.1. Envio de mídia (fase posterior)

Hoje `sendMessage()` faz:

```text
se há anexos -> commitAttachments() e retorna
senão -> envia texto
```

Portanto o `pendingReply` atual **não** chega a uma mensagem de mídia. Para “responder com mídia” será
preciso:

1. validar permissões, trust/OMEMO, PGP e presença **antes** de enviar qualquer parte;
2. enviar o texto (com a referência) e, só então, os anexos na ordem;
3. garantir que o `<reply>` vá no stanza da mensagem que realmente carrega a referência;
4. limpar o compositor apenas quando o conjunto for aceito.

Esse é o mesmo problema de ordem/duplicidade descrito em `responder-com-midia.md`; não deve ser
misturado com o MVP de “responder a mídia”.

## 4. Exibição

### 4.1. Reutilizar o bloco citado como cartão

A citação atual já é visualmente um cartão: barra à esquerda, autor, rótulo/trecho e, quando houver,
miniatura. Criar um segundo cartão acima do corpo duplicaria a informação e mexeria no crop e no
“Ver mais/Ver menos”.

Recomendação revista:

- **quando o corpo começa com bloco citado e existe referência**: manter o bloco atual, torná-lo
  clicável e acrescentar um indicador discreto de resposta (por exemplo `↩` ou sublinhado no autor);
- **quando chega `<reply>` sem bloco citado** (cliente externo que não manda fallback): mostrar um
  `reply_preview` compacto acima do `message_body`, resolvido a partir da original;
- **quando a referência não resolve**: mostrar só o bloco citado/fallback e não quebrar o clique.

O clique pode ser implementado com um `ClickableSpan` sobre o primeiro bloco de citação (o
`ClickableMovementMethod` já é usado no balão) ou com um listener no `TextView` que descobre se o
toque caiu dentro do `QuoteSpan`. A primeira opção é mais previsível e funciona com o crop.

### 4.2. Miniatura por tipo de mídia

| Tipo | Miniatura na citação | Observação |
|---|---|---|
| Foto | sim | já implementado, 200 × 80 dp, cantos de 6 dp |
| GIF | sim, 1º quadro | já implementado, sem ícone de play |
| Figurinha | sim, o próprio PNG | já implementado |
| Vídeo | sim, primeiro quadro | `FileBackend.getQuoteThumbnail()` já extrai frame de vídeo; avaliar ícone de play discreto |
| Áudio | não | mostrar ícone/emoji + rótulo e, se disponível, duração; nunca reservar espaço vazio |
| Arquivo | não | mostrar nome do arquivo já usado no rótulo |
| Localização | não | manter `📍 Localização`; miniatura de mapa fica fora do MVP |

Regras:

- a miniatura só aparece se o arquivo estiver local e o decode for seguro; se não, mostra só o rótulo;
- usar o cache próprio (`getQuoteThumbnail`, chave com sufixo `_quote`) para não colidir com o
  thumbnail do balão;
- não decodificar vídeo/áudio em tamanho cheio na lista;
- no estado retraído, se a citação for cortada, a miniatura é escondida junto com o trecho; ao
  expandir, volta (comportamento atual);
- o clique na citação deve continuar funcionando mesmo sem miniatura e mesmo com a mídia não baixada.

### 4.3. Áudio

Áudio não tem thumbnail. O cartão deve mostrar algo como:

```text
↩ Ana
🎤 Mensagem de áudio · 0:42
```

A duração pode vir do arquivo local (`MediaMetadataRetriever`) ou de metadados já existentes; se não
houver, omitir. Não é necessário waveform nem player no cartão no MVP: tocar no cartão leva à mensagem
original, onde o player atual funciona.

### 4.4. Crop e “Ver mais/Ver menos”

O mecanismo atual de crop (`Config.MAX_MESSAGE_LINES`, `MAX_QUOTE_LINES`) deve continuar valendo. O
`ClickableSpan` precisa sobreviver ao corte e à expansão. Se o crop remover o bloco citado inteiro, o
clique simplesmente deixa de existir naquele estado; ao expandir, volta.

## 5. Navegação até a original

Reutilizar o mecanismo de “ir para mensagem pesquisada”:

- ao clicar no bloco/cartão, resolver a original por `replyToId`/`quoteId`;
- procurar por `uuid`, `remoteMsgId` e `serverMsgId` (a mesma ordem tolerante já usada em
  `MessageAdapter.matchesQuoteId()`);
- se estiver na lista, usar `setSelectionFromTop(pos, altura / 3)`;
- se não estiver, generalizar `pendingScrollToMessageUuid` para aceitar a resolução por id e reaplicar
  depois de `refresh()`/`loadMessageContext()`;
- se continuar ausente, mostrar um aviso curto (“Mensagem original não encontrada”) em vez de não
  fazer nada.

O carregamento de histórico já existe em `applyPendingSearchScroll()` e deve ser commitado/estável
antes desta feature para não virar dependência de código não versionado.

## 6. Fallback e interoperabilidade

O cartão e o scroll são **locais**: com o id, o app resolve a original na conversa. O que leva o id de
um cliente para outro é a XEP-0461 (ou o `<isacloud-quote>`, entre clientes isaCloud).

| Cenário | Resultado |
|---|---|
| isaCloud novo → isaCloud novo | cartão/bloco clicável + miniatura para foto/GIF/figurinha; vídeo/áudio com cartão e clique |
| isaCloud novo → isaCloud antigo | citação textual; miniatura só para foto/GIF/figurinha via `<isacloud-quote>`; vídeo/áudio só rótulo |
| isaCloud novo → cliente com XEP-0461 | cartão de reply do cliente; miniatura isaCloud não é exibida, mas o reply funciona |
| Cliente com XEP-0461 → isaCloud novo | cartão/clique; se não houver fallback textual, o cartão é sintetizado a partir da original |
| Cliente sem XEP-0461 → isaCloud novo | só citação textual; sem id, não há cartão nem clique |
| MAM sem `<reply>` | o cartão só funciona em tempo real; validar o arquivamento no isacloud.im |

- O servidor não precisa entender a extensão, mas o MAM precisa arquivar `<reply>`,
  `<isacloud-quote>` e o `<fallback>`.
- Se um cliente externo mandar apenas a citação, sem `<reply>`, o isaCloud não tem como saber a
  original de forma confiável.
- Não remover a leitura de `<isacloud-quote>` enquanto houver mensagens antigas no histórico.

## 7. Escopo recomendado do MVP

- XEP-0461 para **texto, foto, GIF, figurinha, vídeo e áudio**.
- Responder a mídia continua sendo uma resposta de **texto** com rótulo; não é “responder com mídia”.
- Enviar `<isacloud-quote>` junto para foto/GIF/figurinha; não enviar para vídeo/áudio.
- Reutilizar o bloco citado como cartão clicável; cartão separado apenas quando não houver fallback.
- Miniatura para foto/GIF/figurinha/vídeo; áudio só com ícone/rótulo/duração.
- Clique leva à original, com carregamento de uma página de histórico.
- Sem player inline, sem waveform, sem mapa, sem thumbnail de arquivo.
- Sem mudança no formato do rascunho.
- Sem reply por notificação/atalho de mídia.

## 8. Fora de escopo (fases seguintes)

- **Responder com mídia** (nova mensagem é foto/áudio/vídeo), com texto + anexo no mesmo envio.
- Vários anexos na mesma resposta.
- Player/waveform no cartão de áudio; player no cartão de vídeo.
- Miniatura de mapa para localização.
- Carregamento automático de várias páginas de histórico.
- Replies em mensagens privadas de grupo com regras próprias de MAM.
- Backfill de mensagens antigas sem id.

## 9. Arquivos afetados

| Arquivo | Mudança |
|---|---|
| `xml/Namespace.java` | constantes `REPLY` e, se necessário, `FALLBACK` já existente |
| `model/reply/Reply.java` + `package-info.java` | novo modelo XEP-0461 |
| `model/fallback/…` | modelo para o fallback XEP-0428, se ainda não houver |
| `parser/MessageParser.java` | ler `<reply>` e `<fallback>`; manter leitura de `<isacloud-quote>` |
| `generator/MessageGenerator.java` | escrever `<reply>`, `<isacloud-quote>` e fallback |
| `entities/Message.java` | `replyToId`, `replyToTo`, cursor e ContentValues |
| `persistance/DatabaseBackend.java` | versão 58 e migração idempotente |
| `ui/ConversationFragment.java` | `pendingReply`, `to`, envio, clique e scroll |
| `ui/adapter/MessageAdapter.java` | bloco clicável, cartão sem fallback, miniatura de vídeo, áudio |
| `ui/text/QuoteSpan.java` / `QuoteThumbnailSpan.java` | suporte ao clique/indicador, se necessário |
| `persistance/FileBackend.java` | reutilizar `getQuoteThumbnail` para vídeo; duração de áudio |
| `res/values/strings.xml` + `values-pt-rBR` | textos de “Responder”, cartão, áudio e erro |
| `utils/MessageUtils.java` | generalizar referência de reply para todas as mídias |

## 10. Riscos e mitigação

1. **Id errado entre origin-id, stanza-id e id do stanza** — seguir a XEP: origin-id quando existir;
   em grupo, somente `stanza-id`; sem ele, não enviar `<reply>`.
2. **`to` em grupo** — usar o JID do ocupante autor (`from`) ou o JID real quando conhecido; não usar
   o JID bare da sala como se fosse o autor. O `id` é o que resolve a mensagem.
3. **MAM sem `<reply>`/`<isacloud-quote>`** — validar no servidor; se não arquivar, o fallback textual
   continua funcionando, mas o clique só vale para mensagens em tempo real.
4. **Duplicação cartão + citação** — reutilizar o bloco citado; só criar cartão separado quando não
   houver fallback. Remover o fallback da renderização quando a original for resolvida.
5. **Mídia não baixada** — cartão/clique não dependem do arquivo; miniatura é opcional. Não reservar
   espaço vazio.
6. **Vídeo** — decodificar frame em background, com cache e limite de tamanho; nunca no bind da lista.
7. **Áudio** — duração pode não estar disponível; omitir em vez de mostrar valor errado. Não criar
   player no cartão no MVP.
8. **Mensagem original fora do histórico carregado** — alvo pendente + `loadMessageContext`; aviso se
   não resolver.
9. **Edição/retração/exclusão da original** — o id pode deixar de resolver; mostrar “mensagem original
   indisponível” e não quebrar o clique.
10. **OMEMO/PGP** — `<reply>` e `<isacloud-quote>` ficam fora da criptografia; o id não é conteúdo, mas
    valide com o servidor/cliente que o elemento não é descartado.
11. **Conflito com upstream** — mudanças cirúrgicas, sem mexer no construtor de `Message`; comentários
    `isaCloud:` nos pontos alterados.
12. **Responder com mídia** — não misturar com o MVP; o fluxo de anexos tem ordem, trust e PGP
    próprios e pode duplicar envio.
13. **Mensagem privada em grupo** — testar separadamente; o `stanza-id` pode vir de outro arquivo.

## 11. Alternativas descartadas

- **Só tornar a citação atual clicável, sem protocolo** — resolve apenas no aparelho que respondeu;
  não é reply real e não dá referência a outros clientes.
- **Guardar apenas um ponteiro local** — funciona só em um aparelho.
- **Portar a branch c3** — arquitetura diferente (RecyclerView, Room, Paging); custo e risco altos.
- **Colocar o id escondido no texto da citação** — polui o body, quebra clientes e não é padrão.
- **Adivinhar a original pelo texto citado** — frágil com mensagens repetidas, editadas ou de mídia.
- **Criar um cartão novo sempre, ignorando o bloco citado** — duplica a citação, conflita com miniatura
  e com o crop; só faz sentido quando não há fallback.
- **Usar `<isacloud-quote>` como protocolo definitivo** — não é padrão, não cobre texto e não
  interopera com clientes externos.

## 12. Estimativa

| Etapa | Estimativa |
|---|---|
| Protocolo + banco + parser/generator + disco | 2–3 dias |
| Referência e envio para texto/foto/GIF/figurinha | 1–2 dias |
| Bloco clicável + scroll + histórico | 1–2 dias |
| Vídeo (id, cartão, miniatura) | 1–2 dias |
| Áudio (id, cartão, duração) | 1 dia |
| Coexistência `<isacloud-quote>` e testes de migração | 1 dia |
| Matriz de testes manuais | 2–3 dias |

MVP com texto + foto/GIF/figurinha + vídeo + áudio: **7–10 dias**. Versão robusta, com reply com
mídia, múltiplos anexos, player no cartão e cobertura completa de OMEMO/PGP: **2–3 semanas**.

## 13. Validação prevista

- 1:1: responder a texto, foto, GIF, figurinha, vídeo e áudio; conferir cartão e clique nos dois
  aparelhos.
- Grupo e canal: mesma coisa; testar canal somente leitura e grupo sem `stanza-id`.
- Cliente externo com XEP-0461 (Dino/Gajim, se disponível): conferir envio e recebimento.
- Cliente sem XEP-0461: conferir que a citação textual continua legível.
- MAM: sair e entrar, ou limpar histórico local, e conferir o cartão após recarregar.
- OMEMO em 1:1 e grupo; PGP, se configurado.
- Responder a mensagem antiga fora da lista carregada.
- Vídeo/áudio ainda não baixado: rótulo/cartão sem miniatura e clique funcionando.
- Editar, retrair e apagar a mensagem original.
- Rascunho, rotação, troca de conversa e tablet.
- Tema claro/escuro, fonte grande (1,5 e 2,0), tela estreita (320/360 dp) e RTL.
- Migração 57 → 58 com banco real, rodando duas vezes sem estragar dados.
- Crop: citação longa com e sem miniatura; “Ver mais/Ver menos”; clique após expandir.

## 14. Decisões pendentes

1. Enviar `<reply>` **e** `<isacloud-quote>` para foto/GIF/figurinha durante a transição, ou só
   `<reply>`? (recomendado: os dois)
2. O bloco citado vira clicável (recomendado) ou um cartão separado acima do corpo?
3. Vídeo leva ícone de play na miniatura da citação?
4. Áudio mostra duração no cartão ou apenas “Mensagem de áudio”?
5. “Responder com mídia” entra agora ou fica para a fase 2?
6. O rótulo do menu continua “Quote” ou vira “Reply”?
7. O clique deve carregar histórico automaticamente quando a original não estiver na lista?

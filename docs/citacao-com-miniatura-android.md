# Citação com miniatura: instruções para o isaCloud Android

Status: **iOS em desenvolvimento** (branch `feature/citacao-com-miniatura`, sem build de TestFlight ainda). Android: **a fazer**, depois que o iOS estiver validado no `.dev`.

Este documento é o que o agente do Android precisa para replicar o comportamento. Ele vale junto com [`docs/decisoes.md`](decisoes.md) (entrada de 06/11/2026) e com [`docs/exytechat-fork.md`](exytechat-fork.md), que trata só do iOS.

## 1. O que queremos

Quando alguém responde (citação) a uma **foto**, um **GIF** ou uma **figurinha**, a citação mostra uma **miniatura** da mídia citada, se ela já estiver no aparelho. Sem pulo até a mensagem original.

Vale **só entre clientes isaCloud**. Em outros clientes (Conversations, Monal etc.), a citação continua sendo o texto de sempre, com o rótulo (`> 📷 Foto`, `> 🎞️ GIF`, `> 🎭 Figurinha`). Isso é intencional: o corpo da mensagem não muda.

Fora do escopo desta fase: vídeo, áudio, arquivo e localização (continuam só com o rótulo), e a legenda.

## 2. Contrato (não mudar sem combinar com o iOS)

### 2.1. O corpo da mensagem não muda

A resposta continua mandando o corpo como hoje: a citação em texto (`> autor: trecho` ou `> 📷 Foto`), seguida da resposta. Quem não conhece o elemento abaixo vê exatamente o que vê hoje.

### 2.2. O elemento extra

Um elemento próprio do isaCloud, no stanza da **mensagem nova** (a resposta):

```xml
<isacloud-quote xmlns='urn:isacloud:quote:0' id='ID-DA-MENSAGEM-CITADA'/>
```

- `id`: o ID da mensagem citada.
  - Em **1:1**: o ID do stanza da mensagem citada (`id` do stanza).
  - Em **grupo e canal**: o `stanza-id` que o servidor da sala colocou nela (XEP-0359). É o mesmo ID que o cliente guarda como `stanzaid` na mensagem.
- Só é enviado quando a mensagem citada é **foto, GIF ou figurinha**, já conhecida no banco, com ID disponível. Se não houver ID (por exemplo, um grupo sem `stanza-id` conhecido), **não** envia o elemento.
- Não colocar conteúdo, nome de arquivo nem chave de criptografia nesse elemento. Só o ID.
- Em mensagens com OMEMO, o elemento fica **fora** do conteúdo cifrado, como a marca de figurinha (`<sticker/>`). Isso é aceito: o ID não revela o conteúdo.

### 2.3. Como o receptor usa o elemento

- Se o stanza tiver `{urn:isacloud:quote:0}isacloud-quote`, guardar o `id` na mensagem (campo novo, ver seção 4).
- Na hora de exibir, procurar a mensagem citada no banco (mesma conta; mesmo contato em 1:1, mesma sala em grupo; pelo `id` de 1:1 ou pelo `stanza-id` de grupo).
- Se achar a mensagem citada **e** ela for foto, GIF ou figurinha com **arquivo local já baixado**, mostra a miniatura **na citação**.
- Se não achar, ou não houver arquivo, mostra só o rótulo de texto (como hoje). **Nunca** deixar de mostrar a mensagem por falta do elemento ou da miniatura.

## 3. O que o Android já tem (leitura do código, branch `custom`)

Caminho: `~/projects/java/isaCloudMessenger`.

| O quê | Onde | Observação |
|---|---|---|
| Citação em texto | `ui/util/QuoteHelper.java` | `>` e `»` marcam a citação |
| Desenho da citação | `ui/adapter/MessageAdapter.java` (`handleTextQuotes`, `applyQuoteSpan`) e `ui/text/QuoteSpan.java` | Barra vertical e níveis (`Config.QUOTE_MAX_DEPTH`) |
| Responder | `ui/ConversationFragment.java`, `quoteText(String)` | **Só texto**: não há resposta a mídia |
| Figurinha | `im/conversations/android/xmpp/model/sticker/Sticker.java` (XEP-0449) e `entities/Message.java` (`STICKER`, coluna `isacloudSticker`) | Já reconhece a figurinha recebida |
| Namespaces | `xmpp/.../Namespace.java` | Tem `FALLBACK_INDICATION` (`urn:xmpp:fallback:0`). **Não tem** XEP-0461 nem XEP-0428 |

**Lacuna principal:** o Android não permite responder a foto, GIF nem figurinha (só a texto). Por isso a parte "responder a mídia" é pré-requisito desta feature no Android.

## 4. Banco (Android)

- Campo novo em `Message` e uma coluna nova (ex.: `isacloudQuoteId`, TEXT, NULL) na tabela de mensagens do isaCloud.
- Migração **própria do isaCloud**, nunca na escada do Conversations/Monal. Cada passo deve poder rodar de novo sem estragar nada (checar se a coluna existe antes de criar).
- Não alterar colunas nem passos que já existem.
- Antes de mexer no banco, validar com um banco real (exportado do aparelho ou de um `.dev`), não só com uma linha fabricada. Isso já pegou dois bugs no iOS.

## 5. Interface (Android)

1. **Responder a mídia:** o gesto de puxar (ou o menu de toque longo) de foto, GIF e figurinha monta a citação com o rótulo (texto igual ao do iOS, com o emoji na frente da palavra), e guarda o `id` da mensagem citada para o envio.
2. **Envio:** ao enviar, se houver `id` guardado, incluir o elemento da seção 2.2 no stanza. Ao cancelar ou enviar, limpar o `id` guardado.
3. **Miniatura na citação:** a citação mostra a miniatura acima do texto, com cantos arredondados, altura pequena (até ~64 dp). GIF usa o primeiro quadro. Usar o cache de miniaturas que o app já tiver; não carregar o arquivo original em tamanho cheio na lista.
4. **Sem miniatura:** o rótulo de texto continua sendo a citação. Não mostrar espaço vazio.

## 6. Casos de borda

- Mensagem citada apagada ou não encontrada: só o rótulo.
- Arquivo ainda não baixado: só o rótulo. (No iOS, o app baixa a mídia sozinho quando ela chega; no Android, conferir se o download automático já cobre a mensagem citada.)
- Resposta a uma resposta: a citação aninhada segue como hoje (níveis de citação). A miniatura só aparece no nível da mídia citada.
- Grupo sem `stanza-id` conhecido: não envia o elemento; a resposta vira só texto.
- Figurinha: a miniatura é a própria figurinha (PNG pequeno).

## 7. Testes de aceitação (Android)

1. **Dois isaCloud, 1:1:** responder a uma foto recebida. A citação mostra a miniatura nos dois aparelhos.
2. **Dois isaCloud, grupo:** responder a um GIF enviado por outra pessoa no grupo. A miniatura aparece (usa o `stanza-id`).
3. **Figurinha:** responder a uma figurinha. A miniatura aparece.
4. **Cliente de fora (Conversations ou Monal):** a mesma resposta chega com a citação em texto (rótulo), sem erro e sem texto estranho.
5. **Mídia não baixada:** só o rótulo, sem erro.
6. **Mensagem apagada:** só o rótulo, sem erro.
7. **Migração:** o app abre com um banco que já existe (versão anterior), sem perder mensagens; rodar a migração duas vezes não quebra nada.
8. **iOS para Android:** uma resposta enviada pelo iOS (com o elemento) mostra a miniatura no Android, com o mesmo `id`. Testar nas versões de iOS em uso (18 a 27), já que o iOS é o cliente de referência.

## 8. Ordem sugerida no Android

1. Responder a foto, GIF e figurinha (só o rótulo, como no iOS). Sem isso, o resto não tem o que citar.
2. Enviar o elemento `isacloud-quote` (seção 2.2) e guardar o `id`.
3. Receber o elemento, guardar o `id` (migração, seção 4).
4. Mostrar a miniatura na citação (seção 5, item 3).
5. Rodar os testes da seção 7.

## 9. Pontos a conferir com o iOS antes de fechar

- O `id` em grupo é o `stanza-id` que o servidor deu. Confirmar que o Android guarda esse valor para a mensagem de grupo e que o iOS guarda o mesmo (campo `stanzaid`).
- Mesmo nome e namespace do elemento nos dois apps (`urn:isacloud:quote:0`, `isacloud-quote`).
- Quando o padrão XEP-0461 chegar ao Monal, esse elemento vira o formato de transição. Não apagar a leitura do elemento antes de a referência padrão estar em uso, para as mensagens antigas continuarem com miniatura.

# Figurinha a partir de GIF

**Status:** análise com as decisões tomadas em 13/11/2026. Nada implementado. Substitui a análise de 04/11/2026, resumida no fim.
**Relacionado:** `docs/analise-figurinhas.md`, `docs/ferramenta-de-figurinhas.md` (guia para o Android), `docs/analise-gif-klipy.md` (versões dos GIFs), `docs/figurinha-de-gif-android.md` (guia desta feature para o isaCloud Android).

## Pedido

No seletor de GIF, uma opção **"Enviar como figurinha"**. Marcada, o GIF escolhido vai como figurinha e **fica salvo na biblioteca de figurinhas**. Sempre na **menor versão** do GIF.

## Resumo

Dá para fazer, e sem mudança de banco nem de protocolo: o marcador `<sticker/>` já existe e o envio de figurinha já passa pelo upload comum. O trabalho está em três lugares:

1. **Biblioteca:** hoje só guarda PNG. Precisa guardar GIF também.
2. **Exibição:** a figurinha hoje é imagem parada. A de GIF precisa animar na conversa e na grade.
3. **Android e builds antigos:** uma figurinha GIF chega como quadro parado em quem ainda não foi atualizado.

Esforço estimado: **médio-baixo**, um PR só no iOS, mais a atualização do guia do Android.

## Como funciona hoje

- **GIF:** `GifPickerView.pick` baixa `originalURL` (a maior versão de até 2 MB) e chama `onPick`. Em `ChatView`, o arquivo entra na barra como `ChatInputAttachment(kind: .animatedGif)` e sai pelo botão Enviar.
- **Figurinha:** `sendSticker` chama `uploadAndSendFile(sticker.url, isSticker: true)`. Figurinha não passa pela compressão de imagem. O `xmpp.m` acrescenta o `<sticker xmlns='urn:xmpp:stickers:0'/>` pelo flag `isacloud_sticker` da mensagem.
- **Biblioteca (`StickerLibrary` em `Stickers.swift`):** `<grupo>/stickers/<id>.png` + `index.json`. `add(pngData:)` evita duplicata pelo SHA-256. O nome do arquivo é sempre `.png`.
- **Balão:** em `ChatView.messageBuilder`, o ramo da figurinha vem **antes** do ramo do GIF e usa `GifMessageBubble(isSticker: true)`, que desenha `StickerImageView` (um `UIImage`, ou seja, só o primeiro quadro).
- **"Salvar figurinha":** copia os bytes do arquivo recebido para `add(pngData:)`, seja qual for o formato.

## A menor versão

A menor versão de cada provedor **já é a prévia da grade**:

| Provedor | Menor versão animada | Largura | Observação |
|---|---|---|---|
| GIPHY | `fixed_width_small` | 100 px | Se faltar, a prévia cai em `fixed_width_small_still` (parada) |
| KLIPY | `xs.gif` | ~170 px, ~110 KB | Se faltar, a prévia usa `sm.gif` |

Vantagem: o arquivo **já está no cache HTTP**, porque a pessoa acabou de vê-lo na grade. O envio fica quase instantâneo e não consome outra chamada ao provedor.

**Ponto de atenção:** a figurinha aparece com 128 pt, que no iPhone são 384 px. Os 100 px do GIPHY ficam ampliados quase 4 vezes e podem parecer borrados. Duas saídas:

- **A. A menor, como pedido.** Mais leve. Pode borrar no GIPHY.
- **B. A menor com pelo menos ~200 px de largura.** GIPHY `fixed_width` (200 px), KLIPY `sm` (220 px). Fica umas 2 a 3 vezes maior em bytes, mas ainda bem abaixo do GIF normal.

**Decidido (13/11/2026): A.** Começar pela menor e olhar no iPhone. Se borrar, mudar para B, que é só trocar a lista de versões.

O modelo `GiphyGif` hoje tem só `previewURL` e `originalURL`. Com A, a figurinha usa `previewURL`, mas **só quando a prévia é animada** (no GIPHY, recusar a `_still`). Por isso convém um terceiro campo `stickerURL`, preenchido só quando há versão animada (e que também serve se um dia formos para B). Como `GiphyGif` vai para o cache de "em alta" (Codable), o campo novo precisa ser opcional ou o arquivo do cache tem que mudar de nome (`<provedor>-v3.json`), como foi feito no build 103.

## Fluxo proposto

1. No seletor de GIF, um **interruptor "Figurinha"** na barra de cima, ao lado do menu do provedor. **Começa desligado toda vez que o seletor abre.**
2. Desligado: tudo como hoje.
3. Ligado, ao tocar num GIF:
   - baixa a menor versão;
   - grava na biblioteca (`add(data:format: .gif)`). Se o mesmo GIF já estiver lá, reaproveita a entrada pelo hash e não duplica;
   - envia **na hora** pelo `sendSticker`, como a folha de figurinhas faz, sem passar pela barra de anexos;
   - fecha o seletor e mostra o aviso passageiro "Figurinha salva" (texto que já existe).

**Lembrar a escolha: não (decidido em 13/11/2026).** O interruptor é só um `@State` da tela, para ninguém mandar figurinha sem querer. Não há chave nova no `defaultsDB`.

## O que muda no código

| Arquivo | Mudança |
|---|---|
| `Stickers.swift` | `StickerEntry` ganha `format` opcional (`nil` = PNG, assim o `index.json` atual continua válido sem migração). O arquivo passa a ser `<id>.png` ou `<id>.gif`. `add(pngData:)` vira `add(data:format:)`, com o formato detectado pelos primeiros bytes (`GIF8` ou `\x89PNG`). A grade da folha **anima** os GIFs com `AnimatedGifView`, que já existe (decidido em 13/11/2026). |
| `GiphySearch.swift` | A URL da figurinha (prévia animada, ou `stickerURL` na opção B) e um `downloadSticker` que grava `.gif` no temporário. |
| `GifPickerView.swift` | Interruptor na barra, `onPickSticker` além do `onPick`. `GifMessageBubble(isSticker:)` anima quando o arquivo é GIF, mantendo os 128 pt, sem balão e o toque que abre o visualizador. |
| `ChatView.swift` | Closure nova do seletor (grava e chama `sendSticker`). No `messageBuilder`, o ramo da figurinha passa a valer também para `image/gif`. "Salvar figurinha" grava com o formato certo. |
| Traduções | "Figurinha" (interruptor) e o rótulo de acessibilidade, com pt-BR no override do isaCloud. |
| Testes | `GifVariantPolicy`/parse (qual URL vai para a figurinha), `StickerLibrary` (índice antigo sem `format`, GIF e PNG convivendo, deduplicação). |

Não muda: banco, `xmpp.m`, `MLXMPPManager`, upload e compressão (figurinha já pula a compressão; o GIF vai como está, `image/gif` pela extensão).

## Bug que aparece mesmo sem esta feature

Hoje, se alguém mandar uma figurinha GIF (de outro app, ou do isaCloud depois desta mudança) e um aparelho com o build atual tocar em **"Salvar figurinha"**, o GIF é gravado como `<id>.png`. A figurinha fica parada e, se for reenviada, sobe com extensão `.png` e conteúdo GIF. A detecção de formato por bytes no `add` resolve isso. Entra no mesmo PR.

## Compatibilidade

- **Builds do iOS até o 108:** a figurinha GIF aparece **parada** (primeiro quadro), sem balão. Não quebra, só não anima.
- **isaCloud Android:** depende de como a figurinha é desenhada lá. Se ela usa decodificação de imagem parada, mostra o primeiro quadro. O guia `ferramenta-de-figurinhas.md` §2 diz **[compatibilidade]** "`image/png`, 512×512". Isso passa a ser "PNG 512×512 **ou GIF animado** de tamanho livre", e o Android precisa animar. O que o Android precisa fazer está em `docs/figurinha-de-gif-android.md`; o §2 do guia geral é atualizado no PR do iOS.
- **Monal original e Conversations:** ignoram o `<sticker/>` e mostram como GIF comum, o que é aceitável. No Conversations, não verificado se anima. Testar no `.dev`.
- **XEP-0449:** não restringe o formato a PNG, até onde lemos. Ela mesma recomenda deixar a pessoa desligar figurinhas animadas. Por ora não oferecemos isso; fica anotado.

## Alternativa para pensar depois

GIPHY e KLIPY têm **busca de figurinhas** própria (`/stickers/search`), com GIFs de **fundo transparente**. Ficam bem mais parecidas com figurinha do que um GIF retangular sem balão. Daria para ter, no seletor, uma aba "Figurinhas" usando o mesmo fluxo acima. Seria outra análise (limites da API, termos de uso, contagem de chamadas).

## Decisões (13/11/2026)

1. **Versão:** a menor pura (A). Se borrar no iPhone, passar para B.
2. **Interruptor:** volta desligado a cada abertura do seletor.
3. **Grade da folha de figurinhas:** os GIFs animam.

## Análise anterior (04/11/2026)

Avaliou três formas de perguntar: alerta no Enviar (A, descartada), chip GIF/Figurinha na miniatura do anexo (B) e diálogo logo após tocar no GIF (C, recomendada). Nenhuma foi feita. O pedido de agora (interruptor no seletor, envio direto e salvar na biblioteca) é mais simples que B e C, porque não passa pela barra de anexos. Os dois pontos que ela levantou continuam valendo e estão cobertos acima: o balão precisa animar, e "Salvar figurinha" precisa entender GIF (em vez de sumir, como ela sugeria).

# Enviar GIF ou figurinha: como perguntar

**Status:** análise. Nenhuma opção foi implementada. Data: 04/11/2026.
**Relacionado:** `docs/analise-figurinhas.md` (figurinha por XEP-0449), `docs/ferramenta-de-figurinhas.md` (guia para o Android), `docs/feature-enviar-midia-da-camera.md`.

## Pedido

Ao enviar um GIF, o app deve perguntar (ou deixar marcar) se ele vai como GIF normal ou como figurinha.

## Como funciona hoje

- **GIF.** `GifPickerView.pick` baixa o arquivo do GIPHY e chama `onPick`. Em `ChatView`, o arquivo entra na barra de entrada como `ChatInputAttachment(kind: .animatedGif)`. No envio, `sendFromInputBar` chama `uploadAndSendFile(attachment.url)` sem marcador.
- **Figurinha.** `sendSticker` envia direto, com `isSticker: true`. Em `xmpp.m` (por volta da linha 4183), a mensagem sai com `<sticker xmlns='urn:xmpp:stickers:0'/>`. O marcador já existe, então esta feature não precisa de mudança de protocolo nem de banco.

## Opções

| Opção | Como | Risco |
|---|---|---|
| A. Perguntar no envio | Alerta ao tocar em Enviar | Médio. Mexe no caminho de envio: `inputModel.send()` limpa os anexos antes de qualquer resposta. Com vários GIFs fica confuso. |
| B. Marcar na miniatura | Chip "GIF / Figurinha" no anexo, padrão GIF | Baixo a médio. Sem interrupção, mas pode passar despercebido e enviar GIF quando se queria figurinha. Mexe no modelo do anexo e nos testes da barra de entrada. |
| **C. Perguntar no seletor** | Diálogo logo após tocar no GIF: "GIF", "Figurinha", "Cancelar" | **Baixo.** Muda `GifPickerView.pick`, a closure de `onPick` em `ChatView` e ganha um campo `isSticker` (padrão `false`) em `ChatInputAttachment`. `sendFromInputBar` passa esse valor para `uploadAndSendFile`. |

**Recomendação: C.** É a pergunta literal, feita no momento em que o usuário escolhe o GIF, e não toca no caminho de envio.

## Ponto que pesa mais que a escolha

A figurinha é imagem estática hoje. Se um GIF virar figurinha:

1. O balão (`GifMessageBubble` com `isSticker: true`) mostra só o primeiro quadro, pelo `StickerImageView`. É preciso um ramo animado para `image/gif` marcado como figurinha (`ChatView` por volta da linha 1201 e `GifPickerView` por volta da linha 231).
2. "Salvar figurinha" deve sumir para GIF (`ChatView` por volta da linha 352), porque a biblioteca guarda só PNG.

## Pontos em aberto

- **XEP-0449 e GIF animado:** não verificado. A documentação fala em imagem. Conversations e outros apps podem mostrar o GIF parado. Precisa de teste com o Conversations.
- **Textos novos** ("Enviar como GIF ou figurinha?", "GIF", "Figurinha", "Cancelar"): precisam de tradução pt-BR no override do isaCloud, e o texto final deve ser confirmado com a Isadora antes de entrar.
- **Testes:** simulador em iOS 18 e 27. Se o modelo `ChatInputAttachment` mudar, `ChatInputModelTests` precisa ser atualizado.
- **Merge com o Monal:** os arquivos envolvidos (`GifPickerView.swift`, `ChatView.swift`, `ChatInputModel.swift`, `ChatInputBar.swift`) já são majoritariamente do isaCloud, então o risco de conflito com o Monal é baixo.

## Decisão pendente

Escolher entre C (recomendada) e B. A opção A fica descartada, salvo pedido explícito.

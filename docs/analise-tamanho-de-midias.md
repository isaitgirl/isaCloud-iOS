# Análise: tamanho das mídias na conversa (06/11/2026)

**Pedido:** mostrar sempre o tamanho das mídias (fotos e vídeos apenas) na janela de conversa, tanto nas recebidas quanto nas enviadas. Não entram as miniaturas de respostas e citações.

**Conclusão:** viável, com mudança pequena e sem impacto nos merges com o Monal. A mudança fica no fork do ExyteChat e em `ChatView.swift`. Nada foi implementado ainda.

## Como está hoje

- **A janela de conversa é SwiftUI.** Ela usa `Monal/Classes/ChatView.swift` sobre o fork do ExyteChat. O `Monal/Classes/chatViewController.m` é o caminho antigo do Monal e não é o que o usuário vê.
- **Foto ou vídeo ainda não baixado** (estado `headers`) já mostra o tamanho. O placeholder de arquivo usa `File.size` no `FileView` do fork.
- **Foto ou vídeo já baixado** (estado `complete`, o caso comum com download automático) **não mostra o tamanho**. `ChatViewMessage.attachments` (`ChatView.swift`, em torno da linha 2465) monta o `Attachment` só com id, URL, tipo e mimeType. O `Attachment` do fork (`Sources/ExyteChat/Model/Attachment.swift`) não tem campo de tamanho.
- **Mídia enviada:** o tamanho já é gravado no envio (`uploadInfo["size"]`, `Monal/Classes/MLXMPPManager.m`, linha 853). O dado existe nos dois lados; falta exibi-lo.
- **Tamanho de quem já foi baixado:** `MLFiletransfer.m` (em torno da linha 448) grava o tamanho do arquivo em cache ao concluir o download, então o valor está disponível para o balão.

## O que mudaria

1. **Fork do ExyteChat:**
   - `Attachment` ganha `size: Int?` opcional, com `nil` por padrão. Quem já usa o tipo não quebra, e o `Codable` continua compatível.
   - `AttachmentCell` desenha uma pílula no canto inferior esquerdo: fundo preto a 50%, texto branco, `.formatted(.byteCount(style: .file))`.
   - A pílula só aparece em `.image` e `.video`, quando o tamanho é maior que zero e o upload não está em andamento.
2. **App (`ChatView.swift`):** `ChatViewMessage.attachments` passa `size: fileInfo.size` ao criar o `Attachment`.
3. **Fora do escopo:** as miniaturas de citação e de resposta (têm caminho próprio, em torno da linha 2195 de `ChatView.swift`) e o Monal.

## Pontos para decidir

- **GIF:** tem mimeType `image/gif`, então cai no mesmo caminho de imagem. Como o pedido é só fotos e vídeos, a recomendação é excluir. Incluir é só mais uma condição.
- **Figurinhas (`isSticker`):** excluir.
- **Álbum de fotos** (grade de 2 colunas, células de 100 pt): um texto curto como "1,2 MB" cabe, mas fica apertado. Recomenda-se mostrar também ali e conferir no simulador.
- **Foto enviada:** o número certo é o do arquivo que sai, já comprimido pelo app (`MLFiletransfer.imageFileNeedsCompression`). Assim remetente e destinatário veem o mesmo valor. Se fosse o tamanho do original da galeria, os dois divergiriam.
- **Vídeo enviado:** se a compressão de vídeo em andamento (branch `feature/comprimir-video-galeria`, ver `docs/analise-comprimir-videos.md`) entrar num build, o número passa a ser o do vídeo comprimido. Continua coerente com o que o destinatário recebe.
- **Duração do vídeo:** fora do pedido, mas `mediaDuration` já existe em `MLFiletransferInfo`. Poderia entrar na mesma pílula ("12 MB · 0:42").

## Riscos

- **Colisão com a hora:** a hora e o cadeado de mídia sem legenda ficam no canto inferior direito (`MessageView.swift`, em torno da linha 364 do fork). O canto esquerdo parece livre, mas precisa ser confirmado no simulador.
- **Merge com o Monal:** nenhum. ExyteChat e `ChatView.swift` são de uso próprio do isaCloud.
- **Fork do ExyteChat:** segue a rotina de `docs/exytechat-fork.md`. Branch novo a partir de `isaCloud`, PR para `isaCloud` com `isaitgirl` como revisora, prints de antes e depois com dados de teste, e `Package.resolved` atualizado depois do merge. A ordem é fork primeiro, depois o app.
- **Texto:** `.byteCount(style: .file)` é localizado pelo sistema, então não há string nova de tradução.
- **iOS 18 a 27:** a API já é usada em `FileView`, sem risco de versão.

## Ampliação (09/11/2026): áudio e GIF também

**Pedido novo:** mostrar o tamanho de fotos, vídeos, **áudios e GIFs**; figurinhas continuam fora.

- **Áudio:** o balão de áudio baixado é do fork (`Recording`, em `Sources/ExyteChat/Model/Message.swift`, desenhado por `RecordWaveform.swift`, que hoje mostra só a duração). `ChatViewMessage.recording` (`ChatView.swift`) monta o `Recording` com duração, URL e mimeType. Mudança: `Recording` ganha `size: Int?` opcional e o texto da duração vira "0:42 · 120 KB". Áudio ainda não baixado já cai no placeholder de arquivo, que mostra o tamanho.
- **GIF:** o GIF animado não usa o balão do ExyteChat: é o `GifMessageBubble` do app (`Monal/Classes/GifPickerView.swift`), o mesmo das figurinhas. Mudança só no app: um parâmetro de tamanho opcional e a mesma pílula no canto inferior esquerdo; a figurinha passa `nil`.
- **Fonte do número:** `MLFiletransferInfo.size` (NSNumber) para os quatro tipos; sem tamanho conhecido, nada aparece.
- **Esforço revisto:** pequeno a médio, cerca de um dia: um PR do fork (`Attachment.size`, pílula no `AttachmentCell`, `Recording.size` e o texto do `RecordWaveform`) e um PR do app (passar os tamanhos e a pílula no `GifMessageBubble`).
- **Branch:** é independente da compressão de vídeo; implementar num branch próprio a partir de `isaCloud` deixa os PRs menores (a análise ficou nesta branch só por acaso).

## Esforço e recomendação

- **Esforço:** pequeno, cerca de uma tarde, incluindo testes nos simuladores de iOS 18 e 27 e no `isaCloud.dev`.
- **Recomendação:** implementar, com GIF e figurinhas fora, o álbum incluído e o tamanho do arquivo que sai (o comprimido, no caso de foto).

## Testes previstos (quando for implementar)

- Foto e vídeo recebidos já baixados, mostrando o tamanho.
- Foto e vídeo enviados, conferindo que o número bate com o arquivo que saiu.
- Mídia em upload: a pílula não aparece até o envio terminar.
- Álbum com várias fotos e a foto única.
- Hora e cadeado de mídia sem legenda não colidem com a pílula.
- Tamanhos de texto "Pequeno" e "Gigante" (`ChatTextSize`).
- Conferência nos simuladores iOS 18 e 27, com capturas em `docs/screenshots/`.

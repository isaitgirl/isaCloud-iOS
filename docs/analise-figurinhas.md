# Figurinhas criadas pelas pessoas (análise pré-implementação)

Status: **decidido e em implementação (03/11/2026).** Pedido da Isadora: figurinhas parecidas com as do WhatsApp, criadas a partir de uma foto, com **recorte** e **texto** (dentro ou fora da imagem, mas fazendo parte da figurinha). **Sem remover o fundo** nesta primeira versão. As figurinhas ficam **salvas** e podem ser **favoritadas**.

## Resumo

O caminho mais simples é **copiar o desenho dos GIFs**, que o app já tem de ponta a ponta:

- **Envio:** a figurinha é uma imagem PNG pequena (512×512) enviada pelo upload HTTP normal (XEP-0363).
- **Marcador:** a mensagem leva um marcador `<sticker xmlns='urn:xmpp:stickers:0'/>` (XEP-0449), que diz "isto é uma figurinha".
- **Na conversa:** o isaCloud mostra a figurinha **sem balão**, como já faz com o GIF (`GifMessageBubble` no `messageBuilder` do `ChatView`), sem mexer no fork do ExyteChat.
- **Outros apps:** quem não conhece figurinhas (Conversations, Monal original, isaCloud Android de hoje) vê **uma imagem comum**. Nada quebra.
- **Biblioteca:** as figurinhas salvas ficam numa pasta do grupo do app, com um índice pequeno (favorita, data e último uso). É local, sem sincronização nesta fase.
- **Editor:** feito em SwiftUI, sem biblioteca de terceiros. O recorte é um quadrado com pinça e arrasto. O texto pode ser arrastado, com cor e contorno, e a imagem final é gerada com o `ImageRenderer` (iOS 16+).

Estimativa: **média**. São umas 4 telas novas, mas quase tudo é código novo do isaCloud. Os toques no Monal são poucos e marcados.

## O que já existe e serve de base

| Peça | Onde | Como serve |
|---|---|---|
| Seletor de GIF em folha | `GifPickerView.swift`, `ChatInputBar.swift` (`onSearchGif`), `ChatView.swift` (`showGifPicker`) | modelo para a folha de figurinhas |
| Mensagem de GIF sem balão do ExyteChat | `GifMessageBubble` e `GifReactionsFooter` em `GifPickerView.swift`; `ChatView.swift` (~1170, `messageBuilder`) | modelo para `StickerMessageView`, com a hora e as reações reaproveitadas |
| Anexo na barra e envio por upload | `ChatInputAttachment.Kind` (`image`, `animatedGif`, `file`), `uploadAndSendFile` no `ChatView`, `MLFiletransfer` | caminho de envio da figurinha |
| Escolher foto | biblioteca e câmera no clipe | entrada do editor |
| Rótulos de citação e notificação | `MessageForward.mediaEmoji`, `QuoteFormatting.attachmentLabel` | ganhar o caso "Figurinha" |
| Escada de banco do isaCloud | `+migrateISACloudDB:` em `DataLayerMigrations.m` | guardar o marcador recebido |

## Protocolo: como a figurinha viaja

**Recomendado: imagem por upload + marcador XEP-0449.**

```xml
<message type='chat'>
  <body>https://upload.isacloud.im/…/abc.png</body>
  <x xmlns='jabber:x:oob'><url>https://upload.isacloud.im/…/abc.png</url></x>
  <sticker xmlns='urn:xmpp:stickers:0'/>
</message>
```

- **XEP-0449 (Stickers)** está como *Experimental* (0.2.0, 2026). A mensagem de figurinha leva `<sticker/>` **e** `<file-sharing/>` (XEP-0447), com metadados e hash (XEP-0300). O pacote (`pack`) é opcional. **Não estamos em conformidade:** mandamos só o `<sticker/>` e a imagem por OOB, como qualquer imagem. Quem reconhece `<sticker/>` numa mensagem de arquivo trata como figurinha; quem não reconhece vê a imagem. Esta análise dizia antes que "basta o `<sticker/>`", o que era leitura errada da XEP (corrigido em 04/11/2026).
- **Quem suporta:** só há relatos informais de Cheogram (Android) e Movim, que não confirmei. Conversations e Gajim não suportam. Não há implementação de figurinhas nos clones locais do Conversations e do isaCloud Android. Por isso o marcador serve principalmente **para o próprio isaCloud** (iOS agora, Android depois).
- **Por que não reconhecer pelo nome do arquivo:** com OMEMO, o Monal troca o nome do upload por um UUID (`MLFiletransfer.m` ~907), então o nome não chega. Detectar pela forma da imagem (PNG quadrado com transparência) erraria com fotos comuns.
- **OMEMO:** o Monal criptografa só o corpo, então o `<sticker/>` vai fora da criptografia. Isso revela "foi uma figurinha", não o conteúdo, e a imagem continua criptografada (`aesgcm://`). Vale registrar, mas não impede.
- **Opção 2 (planejada, não implementada): conformidade com a XEP-0449.** Acrescentar o `<file-sharing xmlns='urn:xmpp:sfs:0'>` junto do `<sticker/>`, com `<file>` (`media-type` `image/png`, `size`, `dimensions` 512×512, `<hash>` SHA-256 da XEP-0300) e `<sources><url-data>` apontando para o mesmo URL do upload. Passos: (1) hash do PNG no iOS com CryptoKit e no Android com o hash que o Conversations já calcula; (2) montar o elemento no envio (`xmpp.m` no iOS, `MessageGenerator` no Android); (3) no receptor, aceitar figurinha também quando vier com `file-sharing`; (4) testar com Conversations, Monal e Monocles que a mensagem continua sendo entregue como imagem e que nada quebra; (5) confirmar com o Monal antes do merge, porque ele não tem SFS e a regra vale para o protocolo, não só para o isaCloud. Risco: mudança de protocolo, que o CLAUDE.md manda validar antes do merge com o Monal.

## Guardar o marcador recebido

O app precisa lembrar que a mensagem é figurinha depois de reabrir. Duas opções:

1. **Coluna `isacloud_sticker` em `message_history`.** É a migração 5 da escada do isaCloud, ou o próximo número livre, que pode rodar de novo sem estragar nada. Ela é gravada quando a mensagem chega ou é enviada com o marcador. **Recomendada:** é simples e funciona com MAM e com o histórico.
2. Uma tabela à parte `isacloud_stickers(message_history_id)`. Não mexe em `message_history`, mas precisa de JOIN.

Toques no Monal (marcados com `//isaCloud:`), que geram atrito médio no merge:
- `MLMessageProcessor.m`: ler `{urn:xmpp:stickers:0}sticker` e marcar a mensagem.
- `MLMessage`: uma propriedade `isSticker`, lida do banco.
- Envio: no `sendMessageAndAddToHistory` com upload, acrescentar o filho `<sticker/>` quando o anexo é figurinha (ou um parâmetro no `uploadInfo`).

## Experiência (como no WhatsApp)

1. **Entrada:** um item "Figurinhas" no clipe, ao lado de "GIF". Abre uma folha com três abas: **Favoritas**, **Todas** (as mais usadas primeiro) e **＋ Criar**.
2. **Enviar:** tocar numa figurinha envia na hora, como no WhatsApp, sem passar pela barra de anexos.
3. **Criar:**
   1. escolher uma foto (biblioteca ou câmera);
   2. **recortar** num quadrado com pinça e arrasto (opção de recorte redondo é extra);
   3. **texto:** tocar em "Aa", digitar, escolher a cor e o contorno (branco com borda preta, que é o padrão das figurinhas), arrastar e redimensionar. O texto pode ficar **fora da foto**, porque a tela é um quadrado de 512 com margem transparente: a foto fica menor dentro dele e o texto ocupa a sobra;
   4. **salvar** gera um PNG 512×512 com fundo transparente fora da foto. A figurinha vai para "Todas" e pode ser enviada em seguida.
4. **Favoritar:** estrela no toque longo da folha. Ao longo da figurinha na folha aparecem "Favoritar", "Remover dos favoritos" e "Apagar".
5. **Figurinha recebida:** o toque longo na mensagem ganha "Salvar figurinha" (e "Favoritar"), que copia o arquivo baixado para a biblioteca.
6. **Na conversa:** a figurinha aparece sem balão, com uns 150 pt, a hora embaixo e as reações como no GIF. Ela também ganha os rótulos "Figurinha" na citação, na resposta e na notificação.

## Biblioteca local

- **Pasta:** `<grupo do app>/stickers/`, com um `<uuid>.png` por figurinha e um `index.json` com `id`, `created`, `lastUsed`, `favorite` e `sha256` (para não salvar a mesma duas vezes).
- **Por que não no banco:** não precisa de migração, não toca no Monal e é fácil de apagar, exportar e sincronizar depois. Se crescer, pode ir para o banco pela escada do isaCloud.
- **Limites:** cada figurinha tem 512×512 e cerca de 100 a 300 KB em PNG. Cem figurinhas são ~20 MB.
- **Backup:** fica no grupo do app, então vai no backup do iCloud do aparelho, como o banco.

## Fases

| Fase | O quê | Esforço |
|---|---|---|
| **1 (MVP)** | editor (recorte + texto), biblioteca local, favoritar, enviar, mostrar sem balão, "Salvar figurinha" da recebida, rótulos e traduções | médio (4 telas novas, 3 toques no Monal, 1 migração) |
| 2 | **remover o fundo** com o Vision (`VNGenerateForegroundInstanceMaskRequest`, iOS 17+; nosso mínimo é o iOS 18, então está disponível sem biblioteca) | pequeno |
| 3 | sincronizar a biblioteca entre aparelhos e com o Android (pacote pessoal em PEP, nó `urn:xmpp:stickers:0` da XEP-0449, ou um nó do isaCloud como nos arquivados) | médio |
| 4 | figurinhas animadas (GIF/WebP curto), importar pacotes | médio |

A fase 2 é bem mais fácil do que parece: o mesmo recurso que o app Fotos usa ("levantar o objeto") está aberto aos apps desde o iOS 17.

## Riscos e cuidados

- **Atrito de merge:** fica em três pontos do Monal (receber, guardar e enviar o marcador). Todo o resto é arquivo novo.
- **Interoperabilidade:** os outros apps veem uma imagem PNG quadrada com transparência, o que é aceitável. O isaCloud Android precisaria do mesmo marcador para mostrar sem balão.
- **Texto sem tradução:** "Stickers", "Create sticker", "Save sticker", "Favorite", "Sticker" (rótulo) e os textos do editor precisam de pt-BR no override do isaCloud.
- **Acessibilidade:** a XEP-0449 recomenda permitir desligar figurinhas. Para imagens estáticas o risco é baixo; vale pensar quando houver animadas.
- **Teste:** iOS 18.6 e 27 (o `ImageRenderer` e os gestos de pinça); envio com e sem OMEMO, em grupo e 1:1, recebimento pelo Conversations (deve aparecer como imagem) e figurinha recebida do MAM depois de reabrir.

## Decisões da Isadora (03/11/2026)

1. **Marcador XEP-0449:** sim. 2. **Entrada:** item "Figurinhas" no clipe, ao lado de "GIF". 3. **Envio imediato ao tocar.** 4. **~150 pt** na conversa. 5. **Recorte quadrado ou retangular** (o retangular fica centralizado no quadro de 512 com margem transparente). 6. **Remoção de fundo já no MVP** (Vision, iOS 17+), se não custar muito.

O marcador foi testado com o Conversations nos próprios testes do `.dev` e chega como imagem normal.

## Plano de implementação

- **Banco:** migração **5** da escada do isaCloud, com a coluna `isacloud_sticker INTEGER NOT NULL DEFAULT 0` em `message_history`, que pode rodar de novo sem estragar nada. A sincronização de arquivados, que tinha reservado a 5, passa para a 6. `DataLayer` ganha `setStickerForHistoryId:` e `isStickerMessageId:forAccount:` (aditivos). `MLMessage` ganha `isSticker`.
- **Receber:** `MLMessageProcessor.m`, depois de gravar a mensagem de arquivo, faz `if {urn:xmpp:stickers:0}sticker` e marca a mensagem.
- **Enviar:** `uploadInfo[@"isSticker"]` em `sendMessageAndAddToHistory` marca a mensagem; `xmpp.m sendMessage` acrescenta `<sticker xmlns='urn:xmpp:stickers:0'/>` quando a mensagem é figurinha, o que vale também para o reenvio.
- **App (arquivo novo `Stickers.swift`):** biblioteca (`<grupo>/stickers/`, PNG + `index.json`), folha (Favoritas, Todas, Criar), editor (foto, recorte quadrado ou retangular, remover fundo, textos), renderização em PNG 512×512 e balão sem fundo de ~150 pt (reaproveitando o `GifMessageBubble`). Também "Salvar figurinha" no menu da mensagem e o rótulo "Figurinha" na citação.
- **Fora do MVP:** sincronização, figurinhas animadas, rótulo na notificação e na lista de conversas (ficam "Imagem").

## Decisões que estavam abertas (para registro)

1. **Marcador XEP-0449** (recomendado) ou só imagem, sem diferenciar da foto?
2. **Entrada:** item "Figurinhas" no clipe (recomendado, como o GIF) ou botão próprio na barra?
3. **Envio imediato ao tocar** (como no WhatsApp) ou passar pela barra de anexos, como o GIF?
4. **Tamanho na conversa:** ~150 pt (recomendado) ou outro?
5. **Recorte:** só quadrado, ou também redondo/livre?
6. **Remoção de fundo:** já entra no MVP, já que o Vision deixa barato, ou fica mesmo para depois?

## Fontes

- [XEP-0449: Stickers](https://xmpp.org/extensions/xep-0449.html) (Experimental, 0.2.0)
- [Slixmpp, plugin XEP-0449](https://slixmpp.readthedocs.io/en/latest/api/plugins/xep_0449.html) (só a biblioteca)
- [Log dos operadores XMPP, 13/02/2026](https://logs.xmpp.org/operators/2026-02-13) (relato informal sobre o Cheogram)

## Implementação e testes (03/11/2026)

- **Código:**
  - **Monal:** `DataLayerMigrations.m` (passo 5), `DataLayer` (`setStickerForHistoryId:`, `isStickerMessageId:forAccount:`), `MLMessage.isSticker`, `MLMessageProcessor.m` (receber), `MLXMPPManager.m` e `xmpp.m` (enviar).
  - **isaCloud:** arquivo novo `Stickers.swift`, `GifPickerView.swift` (`GifMessageBubble` com `isSticker`), `ChatView.swift` (folha, envio, "Salvar figurinha", rótulo na citação), `ChatInputBar.swift` (item no clipe) e as traduções.
  - **Recorte retangular:** só 4:3 horizontal por enquanto.
  - **Strings que já existiam:** foram mantidas, como "Excluir" e "Cancelar"; a aba "Todas" usa a chave "All stickers".
- **iOS 27:**
  - **Editor e biblioteca:** folha vazia, editor quadrado e retangular, texto fora da foto, salvar, favoritar e "Favoritas" funcionaram.
  - **Envio e recebimento:** o envio pelo canal de teste funcionou; o marcador foi gravado no envio e no recebimento (outra conta no mesmo simulador). A figurinha aparece sem balão e, num grupo, com o nome acima. "Salvar figurinha" mostra "Figurinha salva" e não duplica o mesmo PNG.
  - **Remover fundo:** falha no simulador ("Não foi possível remover o fundo") sem travar.
- **iOS 18.6:** a figurinha chegou pelo histórico, com `isacloud_sticker=1` nas duas cópias e 0 na foto comum, e aparece sem balão. A migração foi para a versão 5 e roda de novo sem erro (0,008 s numa cópia com 2642 mensagens).
- **Problema antigo encontrado no teste:** com várias contas do mesmo aparelho na mesma sala, o download do mesmo arquivo falha com "já existe um item com o mesmo nome" no `documentCache`, e a mensagem ganha um "!" com o erro de download. Acontece também com foto comum (49 mensagens antigas no simulador), então não vem das figurinhas. Com o erro, o menu da mensagem fica só com "Reenviar" e "Excluir localmente".
- **Capturas:** `docs/screenshots/2026-11-03-15*-iphone-17-ios27-figurinhas-*.png` e `2026-11-03-15*-iphone-xr-ios18-figurinhas-recebida-pelo-historico.png`.
- **Falta:** remover o fundo e o fluxo completo no iPhone, figurinha recebida do Conversations, OMEMO 1:1 e o rótulo na notificação e no encaminhamento (ficaram "Imagem").

### Teste no iPhone e correções (03/11/2026, tarde)

- **Remoção de fundo:** funcionou no iPhone. Foi a figurinha do relógio com o texto "perdi a hora".
- **"!" na cookie:** o canal de teste estava moderado e a sala respondeu `forbidden` ("You do not currently have permission to speak in this chat"). O app mostrou o erro do servidor corretamente.
- **"!" na poli, mesmo com a figurinha entregue:** era o problema antigo do download duplicado entre contas do mesmo aparelho, agravado porque `DataLayer setMessageId:andJid:errorType:` grava o erro por `messageid` e sala, sem a conta. **Corrigido** em `MLFiletransfer.m`: um arquivo que já está no cache vale como baixado. Testado nos dois simuladores, com as figurinhas novas sem erro nas duas contas.
- **Não corrigido (fica para depois, se aparecer de novo):** o erro gravado sem a conta. Com a correção acima ele deixa de disparar nesse caso.

### Ajustes pedidos pela Isadora (03/11/2026)
- **Tamanho na conversa:** 150 pt → **128 pt**, porque as do WhatsApp pareciam menores (`GifMessageBubble.stickerSide`).
- **"Criar figurinha"** abre o seletor de fotos direto, já que escolher foto é o único começo possível. Se ela cancelar, volta à tela com o botão "Escolher foto".
- **Campo de texto** na linha inteira, com o botão de excluir, e as cores embaixo. Durante a digitação os botões (foto, fundo, Aa) somem e a tela rola até as cores, para tudo caber acima do teclado. A barra de cores sobre o teclado foi tentada e descartada: no iOS 27 ela cobre o campo.


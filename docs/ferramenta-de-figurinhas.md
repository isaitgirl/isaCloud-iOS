# Ferramenta de figurinhas: guia para a implementação no Android

Este documento descreve como as figurinhas foram feitas no isaCloud para iOS (build 88, 03/11/2026). Serve para o agente que vai construir a mesma ferramenta no isaCloud para Android (fork do Conversations). O que precisa ser **igual nas duas plataformas** vem marcado com **[compatibilidade]**, porque é o que faz uma figurinha enviada por uma aparecer certa na outra. O resto é desenho de tela, que pode seguir as convenções do Android.

Análise e decisões completas do iOS: `docs/analise-figurinhas.md`. Decisões curtas: `docs/decisoes.md`, seção "Figurinhas criadas pelas pessoas".

## 1. O que a ferramenta faz

- **Criar:** a pessoa cria uma figurinha a partir de uma foto, com recorte, remoção de fundo opcional e textos com contorno, que podem ficar sobre a foto ou fora dela.
- **Biblioteca:** as figurinhas ficam guardadas no aparelho, com abas "Favoritas" e "Todas".
- **Enviar:** tocar numa figurinha envia na hora, sem confirmação.
- **Na conversa:** a figurinha aparece **sem balão**, menor que uma foto.
- **Recebida:** dá para salvar na biblioteca uma figurinha recebida.
- **Outros clientes:** quem não conhece figurinhas (Conversations original, Monal, Gajim) vê uma **imagem comum**. Nada quebra.

## 2. Protocolo [compatibilidade]

A figurinha é **uma imagem enviada como qualquer foto**, pelo HTTP Upload (XEP-0363) e pelo OOB (`jabber:x:oob`). Ela leva **um marcador** da XEP-0449 (Stickers, *Experimental*, 0.2.0):

```xml
<message type='chat' to='lu@isacloud.im' id='…'>
  <body>https://upload.isacloud.im/file_share/…/E91D….png</body>
  <x xmlns='jabber:x:oob'><url>https://upload.isacloud.im/file_share/…/E91D….png</url></x>
  <sticker xmlns='urn:xmpp:stickers:0'/>
  <!-- receipts, markable, store hint etc. como em qualquer mensagem -->
</message>
```

- **Elemento:** `<sticker xmlns='urn:xmpp:stickers:0'/>` vazio, sem atributo `pack`. Não usamos SFS (XEP-0447) nem hashes (XEP-0300) porque o Monal não tem SFS. A XEP diz que receptores devem tratar como figurinha a mensagem com `<sticker/>` **e** `<file-sharing/>`. Como não mandamos o `<file-sharing/>`, **não estamos em conformidade**. O reconhecimento é regra nossa, não da XEP: **o `<sticker/>` numa mensagem de arquivo** marca a figurinha no isaCloud. A conformidade está planejada em `docs/analise-figurinhas.md` (opção 2).
- **Com OMEMO:** o corpo cifrado tem o link `aesgcm://…` e o `<sticker/>` vai **fora** da criptografia. Isso revela que é uma figurinha, mas não qual, porque a imagem continua cifrada. No iOS o marcador é acrescentado depois do bloco que monta corpo/OOB ou OMEMO, então vale nos dois casos.
- **Reconhecer pelo elemento, nunca pelo nome do arquivo:** com OMEMO, o Monal troca o nome do upload por um UUID, e o nome não chega. Reconhecer pelo formato da imagem (PNG quadrado com transparência) também erraria com fotos comuns.
- **Tipo e tamanho:** `image/png`, **512×512 px**, fundo transparente fora da foto, tipicamente de 100 a 300 KB.
- **Reenvio:** quem reenvia uma figurinha que falhou manda o marcador de novo. No iOS o marcador é decidido pelo flag guardado com a mensagem, não pela tela de envio (ver §3).
- **Testado:** o Conversations recebe a mensagem como imagem comum (teste da Isadora no `.dev`).

## 3. Guardar o marcador [compatibilidade de comportamento]

A figurinha precisa continuar sem balão depois de reabrir o app e quando chega pelo MAM. Por isso o marcador é **gravado com a mensagem**:

- **iOS:** coluna `message_history.isacloud_sticker INTEGER NOT NULL DEFAULT 0`, criada pela migração 5 da escada própria do isaCloud. A migração pode rodar de novo sem estragar nada: só cria a coluna se ela não existir.
- **Ao receber:** se a mensagem é de arquivo e tem `{urn:xmpp:stickers:0}sticker`, ela é marcada **antes** de o objeto da mensagem ser montado para a tela.
- **Ao enviar:** o envio passa `isSticker` junto com os dados do upload. A mensagem é marcada logo depois de entrar no histórico, e o envio do stanza consulta o flag pelo `messageid` para pôr o `<sticker/>`.
- **No Android:** o equivalente natural é um campo na tabela de mensagens do Conversations, com migração da escada própria do fork. O ponto de leitura é o parser de mensagens (`MessageParser`): ao achar o elemento, marcar a mensagem. Se o Conversations tiver um campo genérico de metadados/extensões na mensagem, pode servir sem coluna nova.

## 4. Biblioteca local

- **Onde:** uma pasta própria no armazenamento do app. No iOS é `<grupo do app>/stickers/`, com um `<uuid>.png` por figurinha e um `index.json`. Não usa banco, para não precisar de migração e ser fácil de apagar, exportar ou sincronizar depois.
- **Índice (iOS):** lista de `{id, created, lastUsed, favorite, sha256}`. `created` e `lastUsed` são datas, e o `JSONEncoder` padrão do iOS grava segundos desde 2001. Se um dia o índice for sincronizado entre plataformas, mudar para ISO 8601.
- **Sem duplicata:** o `sha256` do PNG impede salvar a mesma figurinha duas vezes. Salvar uma figurinha recebida que já está na biblioteca devolve a existente e conta como "salva".
- **Ordem em "Todas":** `lastUsed` decrescente, depois `created`. Enviar atualiza o `lastUsed`.
- **Robustez:** índice corrompido recomeça vazio, sem travar. Arquivo ausente sai do índice. O índice é gravado de forma atômica.
- **Sincronizar entre aparelhos ou com o iOS:** ficou fora do MVP. Se vier, a ideia é um pacote pessoal em PEP (nó `urn:xmpp:stickers:0` da XEP-0449) ou um nó do isaCloud, como foi feito com os arquivados.

## 5. Telas e comportamento (decisões da Isadora)

| Ponto | Decisão |
|---|---|
| Entrada | item **"Figurinhas"** no menu do clipe, logo depois de "GIF" (ícone de rosto sorridente) |
| Folha | abas **"Favoritas"** e **"Todas"**, botão **"+"** para criar, grade de 4 por linha; estado vazio "Nenhuma figurinha ainda" com o botão "Criar figurinha" |
| Enviar | **tocar envia na hora** e fecha a folha (como no WhatsApp) |
| Toque longo na folha | "Favoritar" ou "Remover dos favoritos" e "Excluir", com confirmação "Excluir figurinha?" |
| Criar | **o seletor de fotos abre direto**, porque escolher foto é o único começo possível; se a pessoa cancelar, a tela mostra o botão "Escolher foto" |
| Recorte | **Sempre quadrado** (a moldura tracejada); a foto se move e se amplia com pinça e arrasto sob a moldura; nunca deixa espaço vazio dentro da moldura. O recorte livre com alças foi feito e descartado em 04/11/2026 |
| Remover fundo | botão **"Remover fundo"**, que alterna com **"Restaurar fundo"**; se falhar, aviso "Não foi possível remover o fundo" e a foto continua como estava |
| Texto | botão **"Aa"** acrescenta um texto; arrastar move, pinça muda o tamanho; o texto pode ficar **fora da foto**, na margem transparente; o campo ocupa a **linha inteira**, com a lixeira no fim, e as **cores ficam embaixo** do campo |
| Teclado | durante a digitação somem os botões de foto, fundo e Aa, e a tela rola para o campo e as cores ficarem acima do teclado |
| Na conversa | **sem balão**, **128 pt** (começou com 150, e a Isadora achou grande perto do WhatsApp), hora e status embaixo, reações como no GIF; em grupos, o **nome de quem mandou fica acima, sem balão cinza** |
| Recebida | toque longo na mensagem: **"Salvar figurinha"**; confirma com um **aviso passageiro "Figurinha salva"** acima da caixa de texto, no lugar do "Enviando…", que some em 2 s, sem janela para fechar |
| Citação/resposta | rótulo "🎭 Figurinha"; encaminhamento e notificação continuam como "Imagem" |

## 6. Como a imagem é montada (para ficar igual nas duas plataformas)

- **Quadro de 512×512.** A moldura de recorte ocupa a largura menos **6% de margem** de cada lado. A altura é igual à largura (moldura quadrada). A moldura fica centralizada e o resto do quadro é transparente.
- **Posições em frações do lado.** Centro do texto e deslocamento da foto vão de 0 a 1, então a prévia (320 pt no iOS) e o PNG final usam os mesmos números.
- **Texto:**
  - **Fonte:** arredondada e pesada (`.rounded`, `.heavy` no iOS), com tamanho de 11% do lado vezes a escala do texto.
  - **Cores:** branco, preto, amarelo, rosa e azul.
  - **Contorno:** preto em todas, menos no texto preto, que leva contorno branco. A espessura é 0,8% do lado vezes a escala, e é desenhada com o mesmo texto repetido em 8 direções atrás do preenchimento.
  - **Largura e posição:** no máximo 90% do lado, com texto centralizado.
- **Foto:** antes de editar, a foto é desvirada (orientação) e reduzida, porque 512 px de saída não pedem mais.
- **Saída:** PNG com transparência, renderizado em escala 1. Textos vazios são ignorados.
- **No editor,** a área transparente aparece com fundo **xadrez**.

## 7. Remover fundo

- **iOS:** Vision, `VNGenerateForegroundInstanceMaskRequest` (iOS 17 ou mais novo; o mínimo do app é o 18) com `generateMaskedImage(ofInstances:from:croppedToInstancesExtent: true)`, rodando fora da thread principal. Funciona no iPhone; no simulador falha, e o app mostra o aviso.
- **Android, equivalente sugerido:** ML Kit **Subject Segmentation** (`com.google.mlkit:subject-segmentation`), que devolve a máscara ou o bitmap do objeto em primeiro plano, sem servidor. Ele baixa o modelo pelo Google Play Services. Se o fork não puder depender do Play Services, a alternativa é o Selfie Segmentation do MediaPipe (só pessoas) ou um modelo TFLite embutido. Vale decidir com a Isadora antes.
- **Comportamento igual:** recorta ao contorno do objeto, permite desfazer e, se falhar, avisa sem travar.

## 8. Na conversa (renderização)

- **iOS:** o construtor de mensagens do ExyteChat já tinha um ramo próprio para GIF (`GifMessageBubble`). A figurinha reaproveita esse componente com `isSticker: true`: imagem estática do arquivo local, sem balão, 128×128 em *aspect fit*.
- **Fallback:** se o arquivo ainda não foi baixado, a mensagem cai na visualização normal de imagem até baixar.
- **Android:** no adaptador de mensagens do Conversations, um tipo de linha próprio para "imagem marcada como figurinha", sem o fundo do balão, com o tamanho fixo e a hora embaixo.

## 9. Textos (inglês na chave, pt-BR no override do isaCloud)

`Stickers`=Figurinhas, `Sticker`=Figurinha, `Favorites`=Favoritas, `All stickers`=Todas, `Create sticker`=Criar figurinha, `No stickers yet`=Nenhuma figurinha ainda, `No favorite stickers yet`=Nenhuma figurinha favorita ainda, `Favorite`=Favoritar, `Remove from favorites`=Remover dos favoritos, `Delete sticker?`=Excluir figurinha?, `Save sticker`=Salvar figurinha, `Sticker saved`=Figurinha salva, `Could not save the sticker`=Não foi possível salvar a figurinha, `Create`=Criar, `Choose photo`=Escolher foto, `Remove background`=Remover fundo, `Restore background`=Restaurar fundo, `Could not remove the background`=Não foi possível remover o fundo, `Text`=Texto. "Excluir" e "Cancelar" já existiam no Monal e foram reaproveitados.

## 10. Erros em que esbarramos (e que podem aparecer no Android)

1. **Duas contas do mesmo aparelho na mesma sala.** As duas recebem a mesma figurinha e baixam o mesmo arquivo para o mesmo nome de cache (o hash da URL). A segunda cópia falhava com "arquivo já existe" e marcava a mensagem com "!". Como o erro era gravado por `messageid` e sala, sem a conta, o "!" caía também na mensagem que a outra conta tinha enviado. **Correção no iOS:** se a cópia falha e o arquivo já está no cache, ele vale como baixado. Não vem das figurinhas, mas aparece logo no teste.
2. **Sala moderada.** A figurinha enviada por uma conta sem voz volta com `forbidden` ("You do not currently have permission to speak in this chat") e fica com "!". É o comportamento certo, não um defeito. Lembrar disso ao testar em canais.
3. **Aviso pedido enquanto o menu da mensagem fecha não aparece** (iOS/SwiftUI). Por isso o "Figurinha salva" é atrasado em 0,3 s e virou um aviso passageiro.
4. **Teclado cobrindo as cores do texto.** Uma barra de cores sobre o teclado também cobria o campo no iOS 27. Resolvido escondendo os botões durante a digitação e rolando até as cores.
5. **Upload pela extensão de compartilhar sem "Enviando…".** Não é das figurinhas, mas é da mesma área. Detalhes em `docs/decisoes.md`.

## 11. Como testar (o que fizemos no iOS)

- **Biblioteca:** criar com recorte quadrado, texto dentro e fora da foto, salvar, favoritar, excluir.
- **Envio 1:1 e em grupo:** conferir que a mensagem gravada tem o flag e que o stanza leva `urn:xmpp:stickers:0`.
- **Outra plataforma:** receber no Conversations, que deve mostrar como imagem comum.
- **Histórico:** reabrir o app e receber pelo MAM em outro aparelho; a figurinha deve continuar sem balão (no iOS isso foi conferido no banco: flag 1 nas duas cópias e 0 na foto comum).
- **Salvar a recebida:** salvar uma figurinha recebida, inclusive a mesma duas vezes, que não duplica.
- **Remover fundo:** testar no aparelho de verdade.
- **Banco real:** rodar a migração numa cópia do banco real antes (no iOS: 0,008 s com 2642 mensagens).

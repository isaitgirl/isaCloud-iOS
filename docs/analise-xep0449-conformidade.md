# Figurinhas em conformidade com a XEP-0449 (roadmap 155): análise iOS e Android

Escrito em 16/11/2026. **Só análise, nada implementado.** Complementa `docs/analise-figurinhas.md` (opção 2) e `docs/ferramenta-de-figurinhas.md`.

## 1. O que a XEP pede e o que fazemos hoje

XEP-0449 (Stickers), *Experimental*, 0.2.0 (01/05/2026). O exemplo da própria XEP:

```xml
<message to='juliet@shakespeare.lit' id='sharing-a-file'>
  <body>😘</body>
  <sticker xmlns='urn:xmpp:stickers:0'/>
  <file-sharing xmlns='urn:xmpp:sfs:0'>
    <file xmlns='urn:xmpp:file:metadata:0'>
      <media-type>image/png</media-type>
      <size>67016</size>
      <dimensions>512x512</dimensions>
      <hash xmlns='urn:xmpp:hashes:2' algo='sha-256'>gw+6xd…DsY=</hash>
    </file>
    <sources>
      <url-data xmlns='http://jabber.org/protocol/url-data' target='https://…/sticker.png'/>
    </sources>
  </file-sharing>
</message>
```

Regras de quem recebe: tratar como figurinha a mensagem com `<sticker/>` **e** `<file-sharing/>`; mostrar a imagem inline, nunca só como arquivo para baixar; oferecer jeito de desligar animações.

O que o isaCloud manda hoje (iOS e Android, igual): `<body>URL</body>`, `<x xmlns='jabber:x:oob'><url>URL</url></x>` e `<sticker/>`. Falta o `<file-sharing/>`. Quem recebe reconhece figurinha só pelo `<sticker/>`, o que é regra nossa, não da XEP.

## 2. Por que vale a pena (e o que não muda)

- **Ganho real:** figurinha nossa passa a ser reconhecida por apps que seguem a XEP, e nós passamos a reconhecer figurinha de apps que mandam só `<file-sharing/>` (sem OOB). Hoje ela chegaria como mensagem sem arquivo.
- **Ganho de tamanho/forma:** o receptor sabe tipo, tamanho e dimensões antes de baixar; o hash permite conferir o arquivo.
- **Não muda:** quem não conhece figurinha continua vendo uma imagem pelo corpo + OOB. Nada quebra.
- **Quem implementa de verdade a XEP-0449 hoje é incerto** (só relatos informais, ver `analise-figurinhas.md`). O ganho prático imediato é pequeno; é sobretudo correção de protocolo.

## 3. Decisões de desenho (valem para as duas plataformas)

**[compatibilidade]** = precisa ser igual no iOS e no Android.

1. **[compatibilidade] Conteúdo do `<file-sharing/>`:** `disposition='inline'`; `<file>` com `media-type`, `size` (bytes do arquivo enviado), dimensões e `<hash algo='sha-256'>` em **base64** (XEP-0300; nossa biblioteca iOS guarda o SHA-256 em hexadecimal, então converter); `<sources>` com um `<url-data target='URL'/>`.
2. **[compatibilidade] Dimensões:** o exemplo da XEP-0449 usa `<dimensions>512x512</dimensions>`, o da XEP-0447/0446 usa `<width>` e `<height>`. As duas XEPs divergem. Proposta: **enviar os dois** (inofensivo) e **aceitar os dois** ao receber. Confirmar no texto da XEP-0446 antes de fechar.
3. **[compatibilidade] Corpo e OOB continuam**, para os clientes antigos. A XEP-0447 diz que um corpo de reserva deve ser marcado com `<fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:sfs:0'/>`. Proposta: **incluir o marcador de fallback só depois de testar** com Conversations, Monal e Monocles que nenhum deles esconde o corpo (hoje o Conversations usa fallback só em respostas). Se algum esconder, deixar sem o marcador e registrar o desvio.
4. **[compatibilidade] OMEMO: não mandar `<file-sharing/>` em conversa criptografada.** O `<file-sharing/>` vai fora da criptografia (o corpo é o único que vai dentro). Ele carregaria a URL em claro, e o `aesgcm://` com a chave está justamente na URL; o hash do PNG em claro também diria ao servidor *qual* figurinha é (dá para comparar com figurinhas conhecidas). O jeito certo seria a XEP-0448 (arquivo criptografado dentro do payload), que nenhum dos dois apps implementa. **Em chat criptografado, fica como hoje** (só `<sticker/>`, que já revela "é figurinha" mas não qual). Isso é um desvio consciente da XEP e precisa ficar escrito.
5. **[compatibilidade] Receber:** figurinha = `<sticker/>` + (`<file-sharing/>` **ou** OOB). Quando não houver OOB nem corpo com URL, usar o `url-data` da `<sources>` como endereço do arquivo. Só `https`. Ignorar fontes que não sejam `url-data` (ex.: `jinglepub`).
6. **Hash ao receber:** conferir após o download; se não bater, **registrar no log e mostrar mesmo assim** na primeira versão (não bloquear, porque o servidor de upload pode recomprimir). Decisão da Isadora, se quiser rejeitar.
7. **Fora desta frente:** `pack` (pacotes), XEP-0448, sincronização da biblioteca.

## 4. O que implementar no iOS

Tudo com marca `//isaCloud:`; o Monal não tem SFS, então é código nosso e não conflita com o upstream, exceto nos dois pontos já tocados.

| Onde | Mudança |
|---|---|
| `xmpp.m` (`sendMessage:…`, ~linha 4250, junto de onde já se acrescenta o `<sticker/>`) | quando é figurinha **e não é OMEMO**, acrescentar `<file-sharing>` com os metadados. Vale também no reenvio. |
| origem dos metadados | calcular do arquivo local em cache da mensagem (PNG de até ~300 KB, barato): tipo, tamanho, dimensões e SHA-256 (CryptoKit, ou `CC_SHA256` no Objective-C). Nada novo no banco: o arquivo está em `MLMessage.fileInfo`/cache; confirmar o acesso na implementação. |
| `MLMessageProcessor.m` (~linha 706, classificação de arquivo) | hoje só é arquivo se `body == oob url`. Acrescentar: se há `<sticker/>` + `<file-sharing>` com `url-data` https e **não** há OOB, usar esse URL como corpo e tipo `kMessageTypeFiletransfer`. Mesmo teste do `isSticker` que já existe (~780). |
| `Stickers.swift` | converter o hash hexadecimal da biblioteca para base64 se for reaproveitado; senão calcular na hora. |
| Testes de unidade | montar o nó com e sem OMEMO; receber figurinha só com `file-sharing`; receber com os dois; dimensões em `dimensions` e em `width/height`; URL `http` ignorada. |
| Traduções | nenhuma (sem texto de UI). |

Esforço: **pequeno a médio** (1 PR). O risco está no receber (mexe na classificação de mensagem do Monal) e na regra de fallback.

## 5. O que implementar no Android (isaCloudMessenger)

Estado lido no clone local (`~/projects/java/isaCloudMessenger`, release 2.21.0-66): existe `Sticker` (marcador), `Namespace.STICKERS`, `MessageGenerator` (`addExtension(new Sticker())`, linha 67) e `MessageParser` (`packet.hasExtension(Sticker.class)`, linha 528). Existe a classe `Hash`, mas **não há** nada de `file-sharing`/SFS (`urn:xmpp:sfs:0`), `file:metadata` nem `url-data`.

| Onde | Mudança |
|---|---|
| `Namespace.java` | constantes `urn:xmpp:sfs:0`, `urn:xmpp:file:metadata:0`, `http://jabber.org/protocol/url-data`, `urn:xmpp:hashes:2` (conferir se já existe). |
| Modelos novos em `im/conversations/android/xmpp/model/` | `FileSharing`, `FileMetadata`, `Sources`, `UrlData`, no mesmo estilo de `Sticker`/`oob`. Reaproveitar `Hash`. |
| `MessageGenerator.generateChat` | quando `message.isSticker()` e a mensagem **não** é OMEMO/PGP, acrescentar `FileSharing` com tipo, tamanho, dimensões, hash e fonte. Tipo e tamanho já vêm de `getFileParams()`; dimensões e hash saem do arquivo local. |
| `MessageParser` (~linha 528) | quando há `Sticker` + `FileSharing` e **não** há OOB, usar o `url-data` como endereço do arquivo (`message.setBody(url)` e o mesmo caminho que hoje trata o OOB); manter o `setSticker(true)`. |
| Cuidado com MAM | já existe o tratamento de duplicata que marca `sticker` (linha ~650); conferir que a mensagem com `file-sharing` casa com a cópia local. |
| Texto de UI | nenhum. |

Esforço: **médio** no Android, porque os modelos de SFS são novos. Nada de banco.

## 6. Ordem sugerida e testes

1. **Decidir** os pontos 2, 3 e 6 da seção 3 (dimensões, fallback, hash).
2. iOS e Android **no mesmo dia** (a regra da seção 3 vale para o protocolo), receber primeiro, enviar depois.
3. Testes cruzados: iOS ↔ Android, e os dois com Conversations e Monal original (a mensagem tem de continuar chegando como imagem); em chat 1:1, grupo, com e sem OMEMO; reenvio; figurinha vinda do histórico (MAM) depois de reabrir.
4. Um receptor que só manda `<file-sharing/>` (sem OOB) pode ser simulado à mão com um stanza de teste no Prosody.

## 7. Resumo do que precisa ser feito

- **Enviar** (iOS e Android): `<file-sharing>` com tipo, tamanho, dimensões, SHA-256 base64 e `url-data`, **só fora de OMEMO**; corpo + OOB continuam.
- **Receber** (iOS e Android): aceitar figurinha sem OOB, usando o `url-data` como endereço.
- **Android a mais:** criar os modelos de SFS (iOS não precisa, lê pelo XML genérico).
- **Decisões da Isadora:** dimensões (os dois formatos?), marcador `fallback` (só depois de testar?), hash que não bate (registrar ou rejeitar?), e confirmar o desvio em chat criptografado.
- **Sem texto de UI, sem banco, sem tradução.**

## 8. Implementado no iOS (16/11/2026)

Branch `feature/figurinha-xep0449`. Decisões da seção 3 seguidas: dimensões nos dois formatos (enviadas e aceitas), sem marcador `fallback` por enquanto, OMEMO sem `<file-sharing/>`. Código marcado com `//isaCloud:`.

**Feito**
- **Envio** (`xmpp.m`, `sendMessage:…withLMCId:`, junto do `<sticker/>`): quando a figurinha não vai criptografada (mesmo critério do bloco OMEMO), sai `<file-sharing disposition='inline'>` com `<file>` (`media-type`, `size`, `dimensions` `LxA`, `width`, `height`, `hash` sha-256 em base64) e `<sources>` com o `url-data` da URL do upload. Os metadados saem do PNG no cache da mensagem (`MLFiletransfer.m`, `isaCloudFileSharingNodeForUrl:`). Vale no reenvio, que usa a mesma linha do banco. Corpo e OOB continuam.
- **Recebimento** (`MLMessageProcessor.m`): mensagem fora de OMEMO com `<sticker/>`, sem OOB válido e com fonte `url-data` https vira arquivo, com essa URL como corpo. Fontes que não são https ou não são `url-data` (ex.: `jinglepub`) são ignoradas.
- **Testes** (`Monal/MonalXMPPUnitTests/StickerFileSharingTests.swift`): metadados de um PNG de 512x512 (tamanho, dimensões, hash conferido com CryptoKit), arquivo que não é imagem e arquivo ausente (sem `file-sharing`), URL https escolhida entre as fontes, http e fonte de outro tipo ignoradas.
- Consulta nova no banco: `DataLayer mimeTypeOfOutboundFiletransferMessageId:forAccount:` (tipo MIME da mensagem de saída, para achar o arquivo no cache).

**Não feito (de propósito, nesta versão)**
- **Conferir o hash no download.** O hash do recebimento não é guardado no banco, então não há contra o que comparar no download. Para fazer, é preciso guardar o hash (coluna nova ou outra forma) e comparar em `MLFiletransfer downloadFileForHistoryID`, com `DDLogWarn` e exibição mesmo assim, como decidido. Fica para a próxima etapa.
- **Marcador `<fallback/>`** (seção 3, ponto 3): fica para depois de testar com Conversations, Monal e Monocles.
- **Android** (seção 5): nada feito nesta branch.
- **Teste cruzado** (seção 6): iOS para Android e para Conversations, em chat 1:1, grupo, com e sem OMEMO, reenvio e MAM, a ser feito no `.dev`.

**Desvios conscientes**
- Em chat criptografado, o `<file-sharing/>` não sai (ponto 4). Figurinha enviada sem criptografia numa conversa OMEMO (reenvio ou "enviar sem criptografia") sai com o `<file-sharing/>`, porque o envio em si já é em claro.

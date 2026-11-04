# Análise: comprimir imagens ao enviar

Data: 04/11/2026. Status: **plano aprovado no critério, ainda não implementado.**

Pergunta: como redimensionar imagens no envio pelo isaCloud, com a opção em Anexos: **Sempre**, **Apenas grandes** ou **Nunca**.

## Decisões

- **Critério de "grande":** arquivo acima de 2 MB (2 × 1024 × 1024 bytes). Escolha da Isadora.
- **Lado máximo ao reduzir:** 1920 px, igual ao Android (`Config.IMAGE_SIZE`).
- **Padrão para quem atualiza:** "Apenas grandes".
- **Qualidade JPEG:** o slider que já existe (`ImageUploadQuality`, padrão 80%) continua valendo para as imagens recompactadas.
- **GIF:** nunca é reduzido.

## Estado atual

**iOS**
- Não há redução de dimensões. Uma foto de 12 MP vai na resolução cheia, recomprimida em JPEG.
- A qualidade já está em **Anexos → Upload Settings**. O toggle "Upload Original Images" (`uploadImagesOriginal`) desliga a recompressão.
- Todo envio de imagem em memória passa por `+[MLFiletransfer prepareUIImageUpload:]` ([MLFiletransfer.m:711](../Monal/Classes/MLFiletransfer.m:711)). Chamadores: [HelperTools.m:1653](../Monal/Classes/HelperTools.m:1653), [HelperTools.m:1674](../Monal/Classes/HelperTools.m:1674) e [chatViewController.m:1697](../Monal/Classes/chatViewController.m:1697).
- A foto da câmera é gravada como JPEG 0.9 em [SwiftuiHelpers.swift:493](../Monal/Classes/SwiftuiHelpers.swift:493). **Falta confirmar** se ela passa por `prepareUIImageUpload` ou vai como arquivo.

**Android (`isaCloudMessenger`)**
- `picture_compression` tem `never`, `auto` e `always`.
- Em `XmppConnectionService.attachImage`, só `never` é checado. `auto` e `always` seguem o mesmo caminho, então "Apenas imagens grandes" hoje equivale a "Sempre". Não copiar isso.
- `FileBackend.copyImageToPrivateStorage` reduz para 1920 px e baixa a qualidade (75, −5 por passo) até ficar abaixo de 512 KB.

## Plano

**Modos**
- `never`: envia o original (comportamento de `uploadImagesOriginal`).
- `large`: se o arquivo passar de 2 MB, reduz para 1920 px e recomprime com a qualidade do slider. Abaixo disso, envia como está.
- `always`: sempre reduz para 1920 px e recomprime.

**Arquivos**
1. `MLFiletransfer.m`: função nova de redução com `CGImageSourceCreateThumbnailAtIndex` (ver orientação abaixo). `prepareUIImageUpload:` decide pelo modo.
2. `HelperTools.m` (~1650 e ~1666): trocar a checagem de `uploadImagesOriginal` pelo modo novo.
3. `GeneralSettings.swift`: preferência `imageCompressionMode` no `AttachmentSettings`, com seletor de três opções. O slider continua.
4. `MLXMPPManager.m`: migração de `uploadImagesOriginal = YES` para `never`, no estilo do upgrade de `ImageUploadQuality` (linha ~103).

## Orientação e metadados (ponto sensível)

O iOS grava a foto com os pixels na orientação do sensor (em geral paisagem) e guarda a rotação real num metadado EXIF (`kCGImagePropertyOrientation`). Uma selfie vertical é um exemplo: os pixels saem deitados e só o metadado diz que ela é vertical.

Consequências para a compressão:
- **Redução sem tratar a orientação deixa a foto de lado.** `CGImageSourceCreateThumbnailAtIndex` só aplica a rotação do EXIF se `kCGImageSourceCreateThumbnailWithTransform` for `true`. Precisa ligar essa opção.
- **Não gravar a orientação duas vezes.** Se os pixels já estiverem girados e o EXIF ainda disser "rotacionar", o receptor gira de novo. O JPEG gerado precisa sair com orientação 1 (normal) ou sem o campo.
- **Conferir também o `UIImage` vindo de `NSItemProvider`** (compartilhar): o `imageOrientation` pode ser diferente de `.up`. A forma mais segura é redesenhar com `UIGraphicsImageRenderer`, que aplica a orientação nos pixels. Só que redesenhar é mais pesado em memória que o thumbnail do ImageIO.

**Metadados:** ao reduzir, o JPEG novo perde os demais metadados, inclusive a localização GPS. Só acontece com fotos reduzidas (acima de 2 MB no modo "Apenas grandes"). Para fotos menores, e no modo "Nunca", os metadados permanecem como hoje. Isso é uma mudança de comportamento e precisa ser mencionada ao usuário.

**Teste de orientação, obrigatório:** enviar fotos acima de 2 MB em paisagem e em retrato (selfie), nos três modos, e conferir no receptor (simulador e outro cliente) que saem na orientação certa.

## Riscos e merge

- Não muda protocolo nem banco. A imagem segue como JPEG por HTTP Upload, então qualquer cliente recebe.
- Toca em pontos do Monal (`MLFiletransfer.m`, `HelperTools.m`, `GeneralSettings.swift`, `MLXMPPManager.m`), em poucas linhas. Registrar em `docs/decisoes.md` para os merges futuros.
- O critério de 2 MB difere do Android (512 KB). Anotar isso.

## Pontos em aberto

- Na imagem só em memória (sem arquivo original), o "tamanho" é o JPEG codificado com a qualidade do slider. Confirmar como exibir isso ao usuário.
- Confirmar o caminho da foto da câmera.

**Status em 04/11/2026**
- Feito e no commit `d10b11976` (branch `feature/comprimir-imagens`): modos, orientação EXIF, normalização de fotos com tag, indicador, fila de fundo, log de cada foto.
- Confirmado: a câmera e a galeria passam pelo caminho de arquivo; a tela antiga (`chatViewController`) só abre com a opção de depuração "showNewChatView" desligada, então fica como está.
- Em revisão: redução na outbox do app principal (a extensão só copia) e no encaminhar (a mesma regra do envio normal, reduzindo uma vez para todos os destinos).
- Pendente (não implementado): **cor P3**. A redução converte para RGB comum; fotos em Display P3 podem perder cor. Correção: manter o espaço de cores da foto original na recodificação. Ainda não medido. Entrada no `ROADMAP.md` (item 148).
- Pendente: Android (`getRotation` ignora orientações 2, 4, 5 e 7), com outro agente.

## Progresso e segundo plano

**Como o Android faz hoje** (`isaCloudMessenger`)
- A compressão de imagem roda em `FILE_ATTACHMENT_EXECUTOR`, um executor de uma thread só (`XmppConnectionService.java:205`), chamado por `attachImageToConversation` → `copyImageToPrivateStorage`.
- **Não há serviço em primeiro plano nem notificação de progresso para imagem.** Só o vídeo chama `startOngoingVideoTranscodingForegroundNotification()` (`AttachFileToConversationRunnable.java:77`) e mostra o progresso (`updateFileAddingNotification`, a partir do progresso do transcoder).
- O serviço em primeiro plano geral depende da opção `enable_foreground_service` (`AppSettings.java:250`), que é do usuário. Sem ela, o Android pode suspender o processo se a compressão demorar.
- Se a compressão falhar (`ImageCompressionException`), o Android manda o arquivo original como arquivo, sem reduzir. Esse fallback vale a pena copiar.
- Portanto, no Android, sair do app durante a compressão de uma imagem funciona porque a compressão é curta, não porque existe um mecanismo de segundo plano. Não verifiquei em aparelho esse comportamento.

**Proposta para o iOS**
- **Indicador:** fase "Preparando imagem…" no campo de envio, antes de "Enviando…" (`ChatInputModel.isUploading`). Com lote, mostrar a contagem.
- **Fila de fundo:** a redução roda fora da thread principal.
- **Segundo plano:** envolver o lote com `beginBackgroundTaskWithExpirationHandler`, no padrão de `MonalAppDelegate.m:1499`. Sem fila longa, o prazo de alguns segundos basta.
- **Falha:** se a redução falhar, enviar o original, como o Android faz. Não travar o envio.
- **Interrupção:** a gravação é atômica. Limpar `tmp.<uuid>` órfãos no início do app.
- **Extensão de compartilhamento:** confirmar se o caminho do NSItemProvider roda na extensão. Se rodar, adiar a redução para o app principal (`sendAllOutboxes`), por causa do limite de tempo e de memória das extensões.

## Validação

- Simuladores iOS 18.6 e iOS 27: fotos de teste acima e abaixo de 2 MB, nos três modos, em retrato e paisagem.
- Capturas em `docs/screenshots/` (nome no padrão do CLAUDE.md).
- Ao final, atualizar o `isaCloud.dev` no iPhone, sem subir build.

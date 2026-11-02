# Enviar foto ou vídeo direto da câmera (clipe da caixa de mensagem)

Análise e implementação de 02/11/2026 (feito; testado no iPhone pela Isadora). Roadmap: ver a linha "Câmera no clipe".

## Objetivo

Um item "Câmera" no menu do clipe que abre a câmera do iOS, captura foto ou vídeo e coloca o resultado na barra de anexos, como as mídias escolhidas da biblioteca. O envio acontece quando a pessoa toca em enviar. **Escopo mínimo, uso imediato:** a mídia **não** é salva na biblioteca de Fotos.

## O que já existe

- `attachMenu` em `ChatInputBar.swift`: Fotos e vídeos, Colar, Arquivo, GIF, Localização.
- `addPickedMedias(_:)` em `ChatView.swift` recebe `[(url: URL, isVideo: Bool)]` e cria os anexos (vídeo entra como `.file`, foto como `.image`); `uploadAndSendFile` envia na hora do envio.
- `SystemMediaPicker` (`SwiftuiHelpers.swift`) devolve o mesmo formato, copiando o arquivo para uma pasta temporária própria.
- `Monal-Info.plist` já tem `NSCameraUsageDescription` e `NSMicrophoneUsageDescription`.
- O chat antigo (`chatViewController.m`, `showCameraPermissionWarning`) já usava `UIImagePickerController` com foto e vídeo e um alerta com atalho para Ajustes quando a permissão está negada (strings "Camera permissions missing", "Monal is not allowed to access the camera", "Settings", "OK").

## Desenho

1. `CameraPicker` (`UIViewControllerRepresentable` de `UIImagePickerController`, `sourceType = .camera`, `mediaTypes = [public.image, public.movie]`) em `SwiftuiHelpers.swift`, ao lado do `SystemMediaPicker`.
   - Foto: `jpegData` (a orientação é aplicada) gravada em `<temp>/<UUID>/IMG-<UUID>.jpg`.
   - Vídeo: copiar `info[.mediaURL]` para `<temp>/<UUID>/<nome>.MOV` (o arquivo do sistema some depois).
   - Devolve `(url, isVideo)` pelo mesmo caminho de `addPickedMedias`.
   - Qualidade de vídeo: padrão do sistema (média), para o upload não pesar.
2. `ChatInputBar.swift`: botão "Câmera" (`camera`) e `onAttachCamera`, só se `UIImagePickerController.isSourceTypeAvailable(.camera)`.
3. `ChatView.swift`: `@State showCamera`, `.fullScreenCover` com o `CameraPicker`. Antes de abrir, checar `AVCaptureDevice.authorizationStatus(for: .video)`: pedir acesso se `.notDetermined`; se `.denied`/`.restricted`, mostrar o alerta de permissão (strings acima, já traduzidas).
4. Tradução: "Camera" → "Câmera" no `pt-BR` do isaCloud (`isaCloud/localization/pt-BR.lproj/Localizable.strings`).

## Riscos e limites

- **Merge com o Monal:** baixo (struct novo e poucas linhas em arquivos que já têm código nosso).
- **Simulador sem câmera:** o botão não aparece lá; a captura só se valida no iPhone (`.dev`). Nos simuladores (iOS 18.6 e 27) conferir só que o menu continua igual.
- Não salvar na galeria foi decisão da Isadora (02/11/2026); se quiser depois, `NSPhotoLibraryAddUsageDescription` já existe.
- Vídeo longo em qualidade média ainda pode passar do limite de upload do servidor; o fluxo de erro de upload já existente se aplica.

## Como testar (iPhone, `isaCloud.dev`)

1. Abrir uma conversa → clipe → Câmera (primeiro uso: permissão de câmera e, no vídeo, de microfone).
2. Foto: tirar, "Usar Foto" → aparece miniatura na barra de anexos → enviar → chega como imagem.
3. Vídeo: gravar, "Usar Vídeo" → anexo → enviar → chega como vídeo.
4. Cancelar a captura: nada é anexado.
5. Permissão negada em Ajustes: o alerta aparece com atalho para Ajustes.
6. Anexar foto da câmera junto com texto e com uma foto da biblioteca.

# Visualizador de imagens: só a foto tocada (04/11/2026)

## Pedido

- Ao tocar numa foto da conversa, o visualizador abre direto no "modo zoom" (foto limpa), sem precisar de um toque extra.
- As miniaturas só apareciam depois desse toque. Como o Monal/isaCloud não tem envio agrupado (álbum) como o WhatsApp, não faz sentido mostrar todas as mídias da conversa: o visualizador mostra **só a foto tocada**.

## Como era (análise)

- O visualizador é do fork do ExyteChat: `Sources/ExyteChat/Views/Attachments/FullscreenMediaPages.swift`. É aberto por `fullScreenCover` em `Views/ChatView.swift` do fork.
- `showMinis` começava em `true` e controlava, juntos, o cabeçalho (X, contador "n/total", compartilhar) e a fileira de miniaturas. O toque na foto alternava os dois.
- A lista de anexos era **toda a mídia já baixada das mensagens carregadas** na conversa, na ordem cronológica: `sections.flatMap { rows → message.attachments }`. No app, `ChatViewMessage.attachments` (`ChatView.swift`) só devolve mensagem de arquivo com download completo que seja imagem ou vídeo (GIF e figurinha são imagens). As miniaturas ainda tiravam os anexos com envio em andamento ou com falha (`fullUploadStatus`).
- Sem filtro por remetente nem por tipo; só entrava o que estava carregado na lista (histórico mais antigo não aparecia).

## Decisão

1. **Só o anexo tocado.** Opção nova do fork, **desligada por padrão** (o fork segue o comportamento original do ExyteChat), que o isaCloud liga: `.fullscreenSingleAttachment(true)`, no mesmo formato de `timeAlwaysBelowText`. Com um anexo só, o contador e as miniaturas saem (`showMinis`, `minisView`).
2. **Controles sempre visíveis, sem alternar com o toque:** um X (fechar) redondo e translúcido no canto superior esquerdo e o compartilhar no canto superior direito, ambos respeitando a área segura. O toque na foto deixa de alternar qualquer coisa. O compartilhar continua também no toque longo da mensagem na conversa (build 83).
3. **Escolhida:** manter o compartilhar no visualizador, em vez de só o X. Já existia e funcionava; tirar não economizava código, e deixar evita voltar à conversa para salvar ou mandar a foto.
4. **Descartado por ora:** arrastar para baixo para fechar (padrão do iOS), porque briga com o `ZoomableContainer` (pinça e toque duplo) e pede mais teste. Entra se sentirmos falta.
5. **Descartado:** mudar o `MediaViewer.swift` do Monal (a "Mídia Compartilhada" do perfil do contato). É outro visualizador e mexer nele aumentaria o atrito com o Monal.

## Onde mexe

- Fork (ExyteChat): `FullscreenMediaPages.swift`, `ChatView.swift` (o `fullScreenCover`), `ChatCustomizationParameters.swift` e `PublicAPI.swift` (a opção). Entra como mudança nº 21 em `docs/exytechat-fork.md`.
- App: ligar a opção no `ExyteChatView` de `Monal/Classes/ChatView.swift` e atualizar a revisão no `Package.resolved`.
- Conflito com o Monal: praticamente nenhum (o Monal não mexe nesse visualizador).

## O que testar (iOS 18.6 e 27)

- Foto única, foto com várias outras na conversa (só a tocada abre), GIF, figurinha e vídeo (o toque no vídeo não pode brigar com play/pause).
- Pinça e toque duplo para ampliar continuam iguais.
- X e compartilhar dentro da área segura e sem cobrir o conteúdo (iPhone XR com iOS 18; iOS 27).
- Compartilhar oferece "Salvar Imagem" e "Salvar Vídeo".

## Resultado

- **Fork:** branch local `feature/visualizador-foto-unica` do ExyteChat, commit `d0f7165` (não enviado ao GitHub; sem PR ainda). A opção `fullscreenSingleAttachment` vem desligada; o app liga em `ChatView.swift`, junto de `.timeAlwaysBelowText(true)`.
- **Builds:** iOS 18.6 e iOS 27 compilam; `.dev` do iPhone instalado com o código (build à mão com `-skipPackageUpdates`, porque o script de instalação reresolve o SwiftPM e desfaz a cópia local do fork).
- **Descoberta no teste:** figurinha e GIF **nunca abrem o visualizador** (usam o `GifMessageBubble`: toque curto não faz nada, toque longo abre o menu). Só foto e vídeo comuns abrem. A opção, portanto, só vale para esses.
- **Aprovado pela Isadora no `.dev` do iPhone (04/11/2026).** Depois dele, a figurinha também passou a abrir este visualizador (toque no `GifMessageBubble`, roadmap 145); falta ver na tela.
- **Ainda não visto na tela (antes da aprovação):** o simulador não tem foto comum de teste na sala "teste" (só figurinhas), e o seletor de fotos do simulador mostra capturas de conversas reais, por isso o executor não enviou nenhuma. Pendente de teste visual: X e compartilhar na área segura, toque na foto sem efeito, pinça e toque duplo, vídeo. Teste manual no `.dev` do iPhone ou, no simulador, com uma foto comum de teste enviada pelo iPhone para a sala "teste".
- **Para próximas rodadas de teste em simulador:** a fototeca do simulador tem conteúdo pessoal. Mandar fotos de teste pelo `.dev` do iPhone ou limpar a fototeca do simulador antes de usar o seletor.

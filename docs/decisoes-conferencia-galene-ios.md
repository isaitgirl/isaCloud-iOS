# Decisões — Criar conferência (Galene + meet-api), fase 1 no iOS

Data: 21/11/2026 · Branch: `feature/video-conferencia`

Equivalente ao Android (`decisoes-conferencia-galene.md`); o contrato da API e o mapa inicial estão em
`implementacao-video-conferencia-ios.md`. Este arquivo registra o que o iOS decidiu e onde se afastou do guia.

## O que a fase 1 faz

- Item **"Criar conferência"** no menu de anexos (`ChatInputBar`, `ChatView.createConferenceFromInputBar`).
- Cria a sala em `POST https://meet.isacloud.cc/meet-api/v1/rooms` (`IsaCloudConferenceApi`) e põe no
  compositor "Acesse a vídeo conferência pelo link: <roomURL>", **sem enviar** (se já houver texto, o link vai
  depois de uma quebra de linha). Toque duplo não cria duas salas.
- Tocar em `https://meet.isacloud.cc/join/<id>` no balão abre o `hostURL` guardado (quem criou a sala neste
  aparelho) ou a página pública (`ExternalLinkViewModifier`).
- Sem card na lista: o anfitrião entra tocando no próprio link do balão (ver "Card da lista retirado").

## Decisões

- **Sem toast "Entrar".** Pedido da Isadora: o atalho é só o card da lista (como no Android) e o link no chat.
- **`hostURL` é credencial e fica só no Keychain** (`IsaCloudConferenceStore`, serviço `IsaCloudMeet`,
  `AfterFirstUnlockThisDeviceOnly`, uma entrada por `roomID` com `hostURL`, `hostKey`, validade e `savedAt`).
  Nunca vai para o chat, log ou crash. Só abre se continuar https e no host `meet.isacloud.cc`.
- **Card da lista retirado (21/11/2026).** O card "Sua conferência está pronta" (`ChatListConferenceView`, com
  Entrar e x) saiu por ora, a pedido da Isadora: o anfitrião já entra tocando no mesmo link enviado ao convidado.
  Restou em `IsaCloudConferenceStore` a dispensa do card e a notificação de mudança, sem uso (ficam para uma
  eventual volta; o histórico do card está no commit `ffb9c36d2`). Os textos do card saíram do override.
- **Sem mexer no fork do ExyteChat.** O toque no balão chega ao `openURL` do app (`outerOpenURL` do `UIList`), que é
  o do `ExternalLinkViewModifier`. Testado no iPhone.
- **Link estrito:** `https`, host `meet.isacloud.cc`, caminho exatamente `/join/<id>` (`[A-Za-z0-9_-]+`), sem
  barra final, porta, usuário, query ou fragmento.

## Pendências / riscos

- O `hostURL` é por aparelho: em outro aparelho o link abre como convidado e ninguém entra (a sala exige quem
  criou). O `hostKey` está guardado, mas o app não oferece "Encerrar conferência" nem recuperar a sala.
- Link aberto fora do app (Universal Link) exige `apple-app-site-association` no `meet.isacloud.cc`.
- Fechar a aba do Safari de quem criou a sala derruba os convidados (`autokick`, é do servidor).
- `SAMKeychain.setAccessibilityType` é global: o app usa `AfterFirstUnlock` em outros lugares; uma corrida entre
  as duas gravações é possível, mas rara (o store serializa as próprias gravações).

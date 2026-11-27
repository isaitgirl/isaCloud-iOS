# Vídeo conferência no isaCloud iOS — guia de implementação

Data: 21/11/2026. Público: agente/dev que vai implementar a feature no
`isaCloud-iOS` (fork do Monal, `~/projects/isaCloud/isaCloud-iOS`, branch `isaCloud`).

O servidor e o app Android já estão prontos e em produção. Este documento descreve **o que o
iOS precisa fazer**, o contrato da API e onde mexer no código.

---

## 1. Visão geral

A conferência é hospedada no **Galene** (`https://meet.isacloud.cc`) e orquestrada por um
serviço nosso, o **meet-api**:

```
app iOS ──POST /meet-api/v1/rooms──► meet-api ──► API do Galene (token de operador)
   │                                   │
   │◄── roomURL (página) + hostURL ─────┘
   │
   └── abre hostURL no Safari/SFSafariViewController ──► Galene (vídeo)
```

- O app **não** cria token nem fala com a API administrativa do Galene: só chama o meet-api.
- O **convidado** não precisa de nada no app: o link compartilhado
  (`https://meet.isacloud.cc/join/<id>`) abre uma página web com nome da sala, quem criou, campo
  de apelido e o estado (“Aguardando quem criou a sala entrar…” / “Pode entrar!”).
- A sala só aceita entrada com **quem criou a sala presente**. Quando essa pessoa sai, todos são
  desconectados e o convidado volta para a página de espera. Isso é todo server-side; o app não
  precisa implementar nada.

O equivalente Android já feito (para consulta) está em
`docs/analise-conferencia-galene.md` e `docs/deploy-meet-api.md` deste repositório.

---

## 2. Contrato da API (produção)

Base: `https://meet.isacloud.cc`. Sempre HTTPS. Sem autenticação nesta fase (limite de 20 salas
por hora por IP). Timeout total sugerido: 15 s.

### Criar sala

```http
POST /meet-api/v1/rooms
Content-Type: application/json

{"hostName": "Isadora"}
```

`hostName` é o único campo obrigatório (`title` e `description` são opcionais; se `title` vier
vazio o servidor monta “Vídeo conferência de <hostName>”).

Resposta **201**:

```json
{
  "roomID": "qy3mqc6biep4o2ka",
  "roomURL": "https://meet.isacloud.cc/join/qy3mqc6biep4o2ka",
  "hostURL": "https://meet.isacloud.cc/u/qy3mqc6biep4o2ka/?token=…&pk=…",
  "hostKey": "…",
  "expiresAt": "2026-11-22T12:15:15Z"
}
```

- `roomURL` é o **link para compartilhar no chat**. Não contém token.
- `hostURL` é a **credencial de anfitriã** (token de operador + chave de presença). Vai só para o
  armazenamento local; **nunca** para a conversa, log ou analytics.
- `hostKey` serve para encerrar a sala (`DELETE`); pode ser guardado no Keychain se o app for
  oferecer “Encerrar conferência”. Nesta fase o Android não usa.
- `expiresAt` (RFC 3339) é a validade da sala (24 h). O token de anfitrião vale 12 h.

Erros: `400` entrada inválida, `429` limite por IP, `502` Galene indisponível. Corpo:
`{"error":"mensagem"}`.

### Entrar (só para o navegador do convidado)

A página `/join/<id>` faz isso sozinha; o app iOS **não precisa chamar**:

```http
POST /meet-api/v1/rooms/{id}/join   {"nickname":"Fulano"}  → 201 {joinURL, expiresAt}
```

Responde **409** enquanto quem criou a sala não estiver presente.

### Metadados / presença

```http
GET /meet-api/v1/rooms/{id}
→ {"roomID","title","description","hostName","closed":false,"hostOnline":true,"createdAt","expiresAt"}
```

A presença (`POST /meet-api/v1/rooms/{id}/presence`) é enviada pelo cliente web do Galene, não
pelo app. O iOS não precisa conhecer esse endpoint.

---

## 3. Fluxos no app

### 3.1 Anfitriã cria a conferência

1. Toque em **“Criar conferência”** no menu de anexos do compositor.
2. `POST /meet-api/v1/rooms` com `hostName` = nome de exibição da conta
   (`MLContact.ownDisplayName(forAccount:)`; fallback: parte local do JID).
3. Guardar `hostURL`, `hostKey` e `expiresAt` no **Keychain**, indexado por `roomID`.
4. Inserir no campo de texto (sem enviar): `Acesse a vídeo conferência pelo link: <roomURL>`.
   O botão de enviar muda sozinho (`ChatInputModel.canSend`).
5. Mostrar um aviso passageiro com a ação **“Entrar”**, que abre o `hostURL`. Se a pessoa ignorar
   o aviso, o link no chat e o atalho da lista continuam funcionando.

### 3.2 Reentrar como anfitriã

- **Atalho na lista de conversas** (recomendado): card no topo com “Sua conferência está pronta”,
  botão **Entrar** e um “x” para esconder. Aparece enquanto houver `hostURL` válido no Keychain.
  “x” esconde até uma nova conferência ser criada.
- **Link no chat**: ao tocar em `https://meet.isacloud.cc/join/<id>`, se houver `hostURL` guardado
  para aquele `roomID` e ainda válido, abrir o `hostURL`; senão abrir o link público.

### 3.3 Convidado

Nada a implementar: o link abre a página web no Safari/SFSafariViewController, que pede o apelido,
mostra o estado da sala e redireciona para o Galene. Só **não** bloqueie o link nem tente abrir uma
tela nativa de entrada nesta fase.

---

## 4. Regras de ouro

- **`hostURL` é credencial**: Keychain, nunca no chat, nunca em log (`print`/`OSLog`) nem em
  relatório de crash. Ao abrir, validar `scheme == https` e `host == meet.isacloud.cc`.
- **Só o aparelho que criou** tem o `hostURL`. Em outro aparelho o link abre como convidado — e
  como a sala exige a pessoa que criou, ninguém entra. Se o Keychain for perdido (reinstalação,
  troca de aparelho), é preciso criar uma conferência nova.
- **A sala encerra quando quem criou sai** (fechar a aba do Safari derruba os convidados).
- **Validade**: sala 24 h, token de anfitrião 12 h; a mesma sala aceita **até 30 pessoas**
  (incluindo a anfitriã).
- **O link compartilhado não tem token**; pode ser reenviado para várias pessoas.
- **Não reimplemente tokens, presença nem a página de entrada.** O servidor já faz.
- **Use Safari/SFSafariViewController** (WebRTC, câmera e microfone). WebView não serve.
- Cache do cliente Galene: o servidor manda `max-age=1800`; se a página parecer antiga, é só
  recarregar. Isso não é problema do app.

---

## 5. Textos (inglês + pt-BR)

Seguir o padrão do repositório: **chave = texto em inglês**, valor = tradução; adicionar em
`isaCloud/localization/Base.lproj/Localizable.strings` (inglês) e
`isaCloud/localization/pt-BR.lproj/Localizable.strings`.

| Inglês | pt-BR | Uso |
|---|---|---|
| Create conference | Criar conferência | item do menu de anexos |
| Access the video conference via the link: %@ | Acesse a vídeo conferência pelo link: %@ | texto inserido no compositor |
| Conference created | Conferência criada | aviso depois de criar |
| Join | Entrar | ação do aviso e botão do card |
| Could not create the conference. Please try again. | Não foi possível criar a conferência. Tente novamente. | erro |
| Your conference is ready | Sua conferência está pronta | card da lista |
| Tap Join to open the room | Toque em Entrar para abrir a sala | subtítulo do card |
| Hide shortcut | Ocultar atalho | “x” do card |

Termos neutros: usar **“quem criou a sala”**, não “anfitrião/anfitriã”. Os textos da página web já
estão nesse padrão.

---

## 6. Mapa de implementação no iOS

Levantamento feito no repositório (branch `isaCloud`, 21/11/2026). Linhas aproximadas.

### 6.1 Item no menu de anexos

- `Monal/Classes/ChatInputBar.swift` — `attachMenu` (linhas 104–158). Adicionar o item depois de
  “Location”:
  ```swift
  Button { onCreateConference() } label: {
      Label("Create conference", systemImage: "video.badge.plus")
  }
  ```
  Declarar `var onCreateConference: () -> Void` junto de `onShareLocation` (linha ~25).
- `Monal/Classes/ChatView.swift` — `makeInputBar()` (linhas 1056–1079): passar
  `onCreateConference: { showConference = true }`. Criar `@State` junto das sheets (linha ~234) e
  apresentar a sheet (linhas ~1767–1816) seguindo `LocationPickerView`.
- Se optar por uma tela SwiftUI própria para criar (título/apelido), registre o `case` em
  `SwiftuiHelpers.swift` (`makeView(name:)`, linhas 1123–1164) e chame via
  `[[SwiftuiInterface new] makeViewWithName:@"IsaCloudConference"]`.

### 6.2 Inserir o texto no compositor

- `Monal/Classes/ChatInputModel.swift` — `inputModel.setText("…")` (linha 206). O botão de enviar
  vira seta automaticamente (`canSend`, linhas ~100–117).
- No `ChatView`, a instância é `@StateObject private var inputModel = ChatInputModel()` (linha 224).
  **Não** envie sozinho: a usuária revisa e toca em enviar.

### 6.3 Cliente HTTP

- Criar `Monal/Classes/IsaCloudConference.swift` com `URLSession` + `Codable`, seguindo o padrão de
  `GiphySearch.swift`: timeout total de 15 s, sem cookies, `Accept: application/json`.
- Base URL: criar `+ (NSString*) isaCloudMeetBaseURL` em `HelperTools.h/.m` (padrão de
  `+isaCloudServerDomains`, linha 880) devolvendo `https://meet.isacloud.cc`.
- **Importante (projeto Xcode):** o app usa grupos clássicos no `project.pbxproj`. O arquivo novo
  precisa ser adicionado manualmente ao grupo `Monal/Classes` e à fase **Sources** do alvo `Monal`.
  Se precisar expor ao Objective-C, usar `Monal/Classes/Monal-Bridging-Header.h`.

### 6.4 Armazenamento do link de anfitrião

- Usar **SAMKeychain** (já é dependência; `import SAMKeychain`).
- Criar uma constante de serviço em `MLConstants.h` (padrão `kMonalKeychainName`, linhas ~52–60),
  por exemplo `kIsaCloudMeetKeychainName`.
- `account = roomID`; valor = JSON `{"hostURL": "...", "hostKey": "...", "expiresAt": 123}`.
  Ler/validar no momento de abrir (expiração em ms/segundos, consistente).
- Guardar também o `roomID` mais recente para o atalho da lista (UserDefaults via
  `@defaultsDB`/`HelperTools.defaultsDB()`, padrão em `SwiftHelpers.swift:436–480`).

### 6.5 Interceptar o link no chat

- `Monal/Classes/SwiftuiHelpers.swift` — `ExternalLinkViewModifier` (linhas 745–770), usado em
  `ChatView.swift:2175` (`.canContainExternalLinks()`). Antes de abrir o Safari, testar:
  ```swift
  url.scheme == "https" && url.host == "meet.isacloud.cc" && url.path.hasPrefix("/join/")
  ```
  Se o `roomID` (último componente do path, `[A-Za-z0-9_-]+`) tiver `hostURL` válido no Keychain,
  abrir o `hostURL`; senão seguir o fluxo normal (página pública).
- **Caveat**: os balões do chat usam o fork do ExyteChat, que instala o próprio `openURL`
  (`Sources/ExyteChat/Views/UIList.swift`; ver `docs/exytechat-fork.md`, item 17). Para o toque
  **dentro do balão** também respeitar a regra, é provável que seja preciso um ajuste pequeno no
  fork (`isaitgirl/ExyteChat`, branch `isaCloud`) ou um callback exposto pela biblioteca. O
  `ExternalLinkViewModifier` cobre o resto da UI.

### 6.6 Atalho na lista de conversas

- `Monal/Classes/ActiveChatsViewController.m` já tem o padrão de card no topo:
  `ChatListNewsView` (linhas 230–398) e `isaCloudUpdateNewsHeader` (linhas 891–936), que define
  `chatListTable.tableHeaderView`.
- Para não brigar com o card de novidades, envolver os dois em um `UIView` contentor e usar o
  contentor como `tableHeaderView`, ajustando a altura em `isaCloudUpdateNewsHeader`.
- O card mostra “Sua conferência está pronta” quando houver `hostURL` válido; **Entrar** abre o
  `hostURL`; **x** grava um “dispensado” em UserDefaults até a próxima conferência.

### 6.7 Localização

- `isaCloud/localization/Base.lproj/Localizable.strings` (inglês)
- `isaCloud/localization/pt-BR.lproj/Localizable.strings` (português)
- Não mexer nas traduções do Monal (submódulo `Monal/localization/external`); o build mescla por
  cima via `scripts/isacloud-merge-localizations.sh`.

---

## 7. Build e validação

Só em **macOS com Xcode 27.1** (este host é Linux). Passos do README:

```bash
cd Monal && pod install
open Monal.xcworkspace     # scheme "Monal"
```

- `.dev` no iPhone: `scripts/isacloud-dev-device.sh <TEAM_ID> [UDID]`
  (bundle `br.com.isacloud.messenger.dev`).
- Simulador: ver `docs/troubleshooting.md:104–120` (`xcodebuild ... -destination ...`).
- Testes: esquema `Monal Tests`; o modelo do compositor tem testes em
  `Monal/MonalXMPPUnitTests/ChatInputModelTests.swift` (vale acrescentar um teste do parser da
  resposta do meet-api).

### Checklist de aceitação

- [ ] Menu de anexos mostra “Criar conferência”; tocar cria a sala e insere o texto com o link.
- [ ] O link inserido é o `/join/<id>` (sem token).
- [ ] O aviso “Entrar” abre o `hostURL` e a pessoa entra como anfitriã (pré-entrada do Galene →
      câmera/microfone).
- [ ] O atalho da lista aparece com o `hostURL` válido; “Entrar” abre a sala; “x” esconde e
      continua escondido ao voltar ao app; nova conferência faz o atalho voltar.
- [ ] Tocar no link do chat, no aparelho que criou, abre como anfitriã.
- [ ] Em outro aparelho (ou sem `hostURL`), o link abre a página `/join/<id>`.
- [ ] Página mostra “Sala criada por: …” e “Aguardando quem criou a sala entrar…” até a anfitriã
      entrar; depois “Pode entrar!”.
- [ ] Quando a anfitriã sai, o convidado é desconectado e volta para a página de espera.
- [ ] Nenhum token aparece no chat, em logs ou em captura de tela do app.
- [ ] Textos em inglês e pt-BR.

---

## 8. Referência: o que foi feito no Android

- `conference/ConferenceApi` — POST + parse; timeouts 5/10/15 s; Tor quando ligado.
- `conference/ConferenceStore` — SharedPreferences por `roomID` (`hostUrl`, `expiresAt`,
  `savedAt`, `dismissed_room`).
- `conference/ConferenceLinks` — detecção estrita de `https://meet.isacloud.cc/join/<id>` e
  abertura em Custom Tabs (fallback `ACTION_VIEW`).
- `ConversationFragment` — item no clipe, `appendText`, Snackbar “Entrar”.
- `FixedURLSpan` — interceptação do link no balão e no cartão de prévia.
- `ConversationsOverviewFragment` + layout — card do atalho na lista.
- Strings `video_conference_*` / `attachment_choice_conference` em `values/` e `values-pt-rBR/`.

Documentação de servidor/operação: `docs/analise-conferencia-galene.md` e
`docs/deploy-meet-api.md` (neste repositório) e `galene-static/README.md` (repo do meet-api).

---

## 9. Entrega no repositório iOS

- Criar uma branch (`feature/video-conferencia` ou nome equivalente, a partir de `isaCloud`).
- Documentar as decisões em `docs/` (padrão `analise-*`/`decisoes-*` do repo).
- Atualizar `CHANGELOG.md` e `CHANGELOG-USERS.md` do iOS quando for commitar.
- Não abrir PR para o Monal upstream; seguir as convenções do fork isaCloud.

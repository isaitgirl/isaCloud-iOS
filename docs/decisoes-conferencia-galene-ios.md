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
  Nunca vai para o servidor, log ou crash. Só abre se continuar https e no host `meet.isacloud.cc`.
  **Exceção desde 24/11/2026:** vai na nota local das notas para mim mesmo (abaixo), que fica só no banco deste aparelho.
- **Nota local com o link de anfitrião (24/11/2026, pedido da Isadora).** Ao criar a sala, o app grava nas notas para
  mim mesmo da conta do chat "Este é o link para acessar sua nova conferência:" e o `hostURL`. Decisões:
  - criada junto com a sala, mesmo que o link do campo não seja enviado (uma por sala);
  - **só neste aparelho**: o `hostURL` é credencial e não pode ficar no arquivo do servidor (MAM) nem chegar a
    outros aparelhos. Por isso não vai por XMPP;
  - gravada como **recebida e não lida** (`inbound=1`, `unread=1`): o app só conta como não lida mensagem recebida,
    e uma nota enviada à própria conta voltaria como "de mim". Conta na lista, nos selos e no ícone, e sobe as
    notas para o topo;
  - notas arquivadas são desarquivadas; **silenciadas continuam sem contar** (escolha da Isadora);
  - sem banner nem som; o texto não vai para o log (só o id da linha);
  - tocar no `hostURL` da nota abre o link direto (não é `/join/<id>`, então não passa pelo desvio do Keychain).
  - **Risco aceito:** a nota pode ser copiada ou encaminhada como qualquer mensagem, e a chave vai junto.
  - **Aviso depois do envio:** quando a mensagem com o link de convidado da sala recém-criada é enviada, aparece
    por 5 s o aviso "Link de anfitrião enviado para você mesmo!" com "Ver" em rosa, que abre as notas para mim
    mesmo. Uma vez por sala (só a sala criada nesta conversa). Não aparece se a sala foi criada dentro das próprias
    notas.
- **Card da lista retirado (21/11/2026).** O card "Sua conferência está pronta" (`ChatListConferenceView`, com
  Entrar e x) saiu por ora, a pedido da Isadora: o anfitrião já entra tocando no mesmo link enviado ao convidado.
  Restou em `IsaCloudConferenceStore` a dispensa do card e a notificação de mudança, sem uso (ficam para uma
  eventual volta; o histórico do card está no commit `ffb9c36d2`). Os textos do card saíram do override.
- **Sem mexer no fork do ExyteChat.** O toque no balão chega ao `openURL` do app (`outerOpenURL` do `UIList`), que é
  o do `ExternalLinkViewModifier`. Testado no iPhone.
- **Link estrito:** `https`, host `meet.isacloud.cc`, caminho exatamente `/join/<id>` (`[A-Za-z0-9_-]+`), sem
  barra final, porta, usuário, query ou fragmento.
- **Opção "Abrir isaCloud Meet" (24/11/2026, pedido da Isadora).** Seletor No app / No navegador em Configurações ›
  Interface, padrão No navegador (chave `isaCloudMeetOpenExternally`). Vale para todo link do Meet; os outros links
  continuam no `useInlineSafari`. No app (SFSafariViewController) voltar às mensagens fecha a chamada e a aba não
  fecha sozinha; no navegador dá para alternar, e a aba fecha sozinha quando o `galene.js` tiver o `window.close()`.

## Análise: abrir no Safari e fechar a aba sozinha (24/11/2026)

Proposta vinda do Android: a conferência abre numa aba normal do navegador (lá, `ACTION_VIEW` em vez de Custom
Tab), a pessoa alterna para as mensagens durante a chamada, e o `galene.js` chama `window.close()` no fim
(anfitrião encerrou, convidado expulso). No Android funcionou no emulador. **No iOS, virou a opção "Abrir isaCloud Meet" (seção Decisões); o teste do microfone em segundo plano continua pendente.**

**Hoje no iOS.** O `ExternalLinkViewModifier` (`SwiftuiHelpers.swift`) segue a opção `useInlineSafari`:
- ligada (padrão fora da Europa, logo quase todos no Brasil): `SFSafariViewController` em tela cheia. É o
  equivalente ao Custom Tab: voltar às mensagens fecha o Safari e derruba a chamada; ele não atende
  `window.close()` nem avisa o app do fim da página;
- desligada: `UIApplication.shared.open`, o Safari de fora (o equivalente da opção 2 do Android).

**Como ficaria.**
1. Links de conferência (`/join/<id>` e `hostURL`) abrem **sempre** no Safari de fora, ignorando `useInlineSafari`.
   Poucas linhas no modificador. A pessoa volta pelo "◀ isaCloud" da barra de status ou pelo alternador de apps.
2. O mesmo `window.close()` do Android no `galene.js`, com a mensagem "Chamada encerrada — pode fechar esta aba"
   quando o fechamento for bloqueado. O WebKit permite fechar se a página foi aberta por script ou se o histórico
   da aba tem uma entrada só; com o `replaceState` do Galene deve valer, mas precisa confirmar no aparelho.
3. Diferente do Android: a aba fecha, mas o Safari continua na frente; o iOS **não volta sozinho** ao isaCloud.
   Voltar sozinho exigiria redirecionar para um link do app no fim, e o Safari costuma pedir confirmação quando
   isso acontece sem toque da pessoa.

**Ponto crítico (decide se vale a pena): Safari em segundo plano.**
- A câmera para quando o Safari sai da tela: os outros veem o vídeo congelado ou preto enquanto a pessoa escreve.
- Microfone e áudio dos outros: o comportamento mudou entre versões do iOS. Se o microfone cair, a pessoa fica
  muda enquanto escreve e o objetivo se perde. **Teste no iPhone** (o simulador não serve): entrar numa sala com
  outro aparelho, ir para o isaCloud, falar e ver se o outro lado escuta; repetir no iOS 18 (XR da Manuela).
- Se o microfone cair, alternar de verdade só com um cliente nativo do Galene (WebRTC + CallKit +
  Picture-in-Picture), trabalho bem maior.

**Outros cuidados.**
- No Safari de fora, o `hostURL` (credencial) fica no histórico e nas Abas do iCloud, que aparecem nos outros
  aparelhos da pessoa. Já acontece hoje com `useInlineSafari` desligada. Saída possível: o `galene.js` tira a chave
  da URL com `replaceState` logo depois de ler.
- Quando o `apple-app-site-association` existir, ele não pode cobrir o caminho da chamada; senão o `open` pode
  devolver o link ao próprio app em vez de abrir o Safari.
- Com outro navegador padrão (Chrome, Firefox), o link abre nele; no Brasil todos usam WebKit, mas a regra do
  `window.close()` pode variar um pouco.

**Custo.** No app, baixo (a troca no modificador). O `window.close()` no `galene.js` serve às duas plataformas.
Servidor sem mudança.

## Pendências / riscos

- O `hostURL` é por aparelho: em outro aparelho o link abre como convidado e ninguém entra (a sala exige quem
  criou). O `hostKey` está guardado, mas o app não oferece "Encerrar conferência" nem recuperar a sala.
- Link aberto fora do app (Universal Link) exige `apple-app-site-association` no `meet.isacloud.cc`.
- Fechar a aba do Safari de quem criou a sala derruba os convidados (`autokick`, é do servidor).
- `SAMKeychain.setAccessibilityType` é global: o app usa `AfterFirstUnlock` em outros lugares; uma corrida entre
  as duas gravações é possível, mas rara (o store serializa as próprias gravações).

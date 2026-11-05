# Análise pré-implementação: escolher a conta ao entrar num canal público

Status: **implementado em 05/11/2026** (branch `feature/canal-escolher-conta`). Mudou depois da análise: o diálogo se chama "Ingressar com…" e só oferece as contas que ainda não estão no canal (sem "Abrir com"); a ordem "mesmo servidor" usa os serviços de MUC da conta (`conferenceServers`), porque as contas `@isacloud.im` usam `conference.isacloud.cc`. Detalhes em `docs/decisoes.md`. Fontes: o código do isaCloud/Monal (esta árvore) e o clone do isaCloudMessenger (Android, fork do Conversations, `~/projects/java/isaCloudMessenger`). Nada foi testado nos servidores.

## 1. O problema

Na tela **Canais públicos** (menu "+" de Contatos), quem tem mais de uma conta toca num canal e o app entra nele com uma conta que a pessoa não escolheu. Não é aleatório: é sempre a **primeira conta ativa**.

## 2. O que o código faz hoje

Tudo fica em `Monal/Classes/PublicChannelsView.swift` (arquivo só do isaCloud):

```swift
private func connectedAccount() -> xmpp? {
    let connected = MLXMPPManager.sharedInstance().connectedXMPP as? [xmpp] ?? []
    return connected.first
}
```

- `connectedXMPP` (`MLXMPPManager.m:493`) é a lista de instâncias `xmpp` das contas **ativas**, não só das conectadas: entram na abertura do app na ordem de `enabledAccountList` (`ORDER BY account_id ASC`), e uma conta adicionada depois vai para o fim. Então `first` é a conta ativa **mais antiga**, conectada ou não.
- Essa mesma conta é usada para **tudo** na tela:
  - `load()`: a lista vem de `queryPublicChannels` (`MLMucProcessor.m:1202`), que consulta só os serviços de MUC **do servidor dessa conta**;
  - `joinedChannels(among:)`: o selo "Já está no canal" só olha a buddylist **dessa conta**;
  - `activate(_:)` → `account.joinMuc(...)` e `waitForJoin` → **entra com essa conta**;
  - `openChat(of:account:)` abre a conversa nessa conta;
  - `loadAvatar` e `loadMemberCount` também consultam por ela.

Consequências, além da pedida:

1. **A lista mostra só os canais do servidor da primeira conta.** Com uma conta em `isacloud.im` e outra em `autozona.cc`, os canais do `autozona.cc` nunca aparecem.
2. **O selo "Já está no canal" mente para as outras contas**: se a segunda conta já está no canal, a linha aparece sem selo e o toque faz a primeira conta entrar também.
3. **Se a primeira conta estiver desconectada** (sem rede no servidor dela, senha errada), a tela inteira falha ("Could not load…"), mesmo com outra conta conectada.

## 3. Como o Android (Conversations) faz

- **Lista** (`ChannelDiscoveryService.getLocalMucServices`, linha ~302): junta os serviços de MUC de **todas as contas ativas com conexão** e consulta todos; os canais de vários servidores aparecem numa lista só.
- **Toque** (`ChannelDiscoveryActivity.onChannelSearchResult`, linha ~250): `AccountPickerDialog.Enabled.pick(...)`:
  - 0 contas: não faz nada;
  - **1 conta: entra direto, sem diálogo**;
  - 2 ou mais: diálogo "Escolher conta" com uma lista de opção única (os JIDs), a primeira já marcada, e os botões Cancelar e OK.
- Depois entra com a conta escolhida (`findOrCreateConversation` + bookmark com autojoin) e abre a conversa. Não marca quais contas já estão no canal.

## 4. Padrões do Monal/isaCloud para escolher conta

- `AddContactMenu.swift` e `CreateGroupMenu.swift`: `Picker("Use account", …)` dentro de um `Form`, só aparece com mais de uma conta.
- `InvitationMenu` (`ContactsView.swift:372`): o mesmo `Picker`, filtrando as contas que podem criar convite.
- Diálogos de confirmação: `.confirmationDialog` (`ContactsView.swift:72`, `Stickers.swift:254`, `ChatView.swift:1837`).
- Estado da conta: `BlockedUsers.swift:48` usa `accountState >= .stateBound && connectionProperties.accountDiscoDone` para saber se a conta está pronta.
- Identificação da conta nas listas: `HelperTools.accountJidToShow` (só mostra a conta quando há mais de uma).

Para uma escolha **no momento do toque**, o `Picker` de formulário não serve (ele fica numa tela); o encaixe natural é o `.confirmationDialog`, que já é usado no app e vira action sheet no iPhone e popover no iPad.

## 5. Proposta

### 5.1 Diálogo de escolha (o pedido)

Ao tocar num canal:

- **Uma conta pronta:** comportamento de hoje (entra direto ou abre, se já estiver).
- **Duas ou mais:** `.confirmationDialog` com título **"Entrar no canal com qual conta?"** (mensagem: o nome do canal) e um botão por conta:
  - o texto do botão é o JID da conta (o mesmo que aparece no topo dos chats);
  - se a conta **já está** no canal, o botão diz **"Abrir com <conta>"** e só abre a conversa;
  - contas que não estão prontas (`accountState < .stateBound` ou sem `accountDiscoDone`) **não entram** no diálogo;
  - **Cancelar** fecha sem fazer nada.
- Se todas as contas prontas já estão no canal e só há uma, abre direto.

Mudanças no código (todas em `PublicChannelsView.swift`):

1. Trocar `connectedAccount()` por `readyAccounts() -> [xmpp]` (contas com `stateBound` e disco feito) e manter um `primaryAccount` (a primeira pronta, não a primeira ativa) para a consulta da lista, avatar e contagem de membros.
2. `joinedJids: Set<String>` vira `joinedAccounts: [String: Set<NSNumber>]` (canal → contas que já estão nele), preenchido com `isBuddyMuc` para **cada** conta pronta.
3. `activate(_:)`: com uma conta, segue como hoje; com mais, guarda o canal em `@State var channelToJoin: PublicChannel?` e mostra o diálogo.
4. `waitForJoin` e `openChat` já recebem a conta como parâmetro: só passam a receber a escolhida.
5. `joiningJids` passa a ser por canal **e** conta (`"\(accountID)|\(jid)"`), para a mesma sala em duas contas não se confundir (mesma lição da folha de compartilhar, build 44).
6. O selo "Já está no canal" aparece se **alguma** conta está no canal; com mais de uma conta, um texto pequeno embaixo pode dizer qual (opcional, ver §6).

Textos novos (base em inglês, tradução no override do isaCloud, `isaCloud/localization/pt-BR.lproj/Localizable.strings`):

| Base (en) | pt-BR |
|---|---|
| `Join the channel with which account?` | `Entrar no canal com qual conta?` |
| `Open with %@` | `Abrir com %@` |

("Cancel" já é traduzido pelo Weblate.)

### 5.2 Lista com os canais de todas as contas (recomendado junto ou logo depois)

Sem isto, o diálogo resolve "com qual conta entrar" mas a pessoa continua sem ver os canais do servidor da segunda conta. Como no Conversations:

1. `load()` chama `queryPublicChannels` em **cada** conta pronta e junta os resultados pelo JID do canal (dois servidores que anunciam o mesmo serviço de MUC não duplicam linhas).
2. A lista só falha se **todas** as consultas falharem; se uma falhar, mostra as outras.
3. O avatar e a contagem de membros continuam com uma conta só (qualquer conta consegue consultar uma sala remota).

`queryPublicChannels` já faz várias consultas em paralelo com timeout por conta (`MLMucProcessor.m:1219-1240`); a junção fica na tela, sem mexer no `MLMucProcessor`.

### 5.3 Alternativa descartada: seletor de conta no topo da lista

Um `Picker("Use account")` no topo (como no `InvitationMenu`) trocaria a lista inteira por conta. É o padrão do Monal, mas obriga a escolher **antes** de ver os canais, esconde os canais das outras contas e não é o que foi pedido. Fica registrado como plano B, caso o diálogo não agrade.

## 6. Pontos para decidir

1. **Escopo:** só o diálogo (5.1) ou diálogo + lista de todas as contas (5.2)? Recomendação: os dois juntos, porque o selo "Já está no canal" e o diálogo dependem de olhar todas as contas de qualquer jeito.
2. **Conta já no canal:** mostrar "Abrir com <conta>" no diálogo (proposto) ou esconder essa conta?
3. **Ordem dos botões:** ordem das contas (`account_id`, como hoje) ou a conta do mesmo servidor do canal primeiro? Recomendação: a do mesmo domínio primeiro, porque é a escolha mais provável.
4. **Mostrar na linha qual conta já está no canal** (por exemplo "Já está no canal · isadora@…")? Opcional; com duas ou três contas pode poluir.

## 7. Atrito de merge e esforço

- **Atrito com o Monal: nenhum.** `PublicChannelsView.swift` e `queryPublicChannels` são código só do isaCloud; nada de banco nem de arquivos do Monal.
- **Esforço:** diálogo (5.1) ~2 a 4 h; lista de todas as contas (5.2) mais ~3 a 4 h; testes nos simuladores iOS 18.6 e 27 com as três contas de teste (duas no `isacloud.im`, uma no `autozona.cc`) ~2 h.
- **Testes:** uma conta (sem diálogo); duas contas no mesmo servidor; contas em servidores diferentes (canais dos dois aparecem); conta já no canal ("Abrir com"); uma conta desconectada (some do diálogo e a lista ainda carrega); Cancelar; iPad (o diálogo vira popover preso à linha).

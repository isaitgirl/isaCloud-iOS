# Decisão — sincronizar conversas arquivadas entre Android e iOS

## Contexto

O Android passou a arquivar grupos e canais **localmente**, sem sair da sala
(`docs/deslizar-para-arquivar.md`). Conversas 1:1 continuam usando o fluxo original do
Conversations: `STATUS_ARCHIVED`, saem da lista e voltam quando chega uma mensagem nova.

O iOS é um fork do Monal. Hoje “arquivar” remove a conversa da tabela `activechats` e marca as
mensagens como lidas, mas:

- a próxima mensagem chama `addActiveBuddies` e a conversa volta para a lista;
- as notificações e o badge não consultam nenhum estado de arquivamento;
- portanto, o estado não é durável e não há o que sincronizar.

A mesma conta é usada no Android e no iOS. O objetivo é que arquivar ou desarquivar em um
aparelho apareça no outro, sem criar um serviço novo no servidor e sem sair de grupos/canais.

## Objetivo

1. Sincronizar o estado **arquivado/ativo** de contatos (conversas 1:1), grupos e canais entre
   Android e iOS usando a mesma conta XMPP.
2. Manter o comportamento atual do Android: grupo/canal arquivado continua conectado, com
   bookmark e `autoJoin` intactos, sem notificação e sem badge.
3. Manter o estado local funcionando offline.
4. Não criar conversas, não sair de salas e não alterar bookmarks por causa da sincronização.
5. Ser retrocompatível: um cliente antigo ignora o nó e continua funcionando localmente.

## Decisão

Usar **PEP** (XEP-0163 sobre XEP-0060) com:

- um nó por conta: `im.isacloud:conversation-state:0`;
- **um item por conversa**, com o JID bare como `item id`;
- um payload pequeno com `archived`, `updated`, `mode` e `device`;
- **tombstones**: desarquivar publica `archived='false'` em vez de retrair o item;
- resolução de conflito por **last-write-wins** usando `updated`;
- primeira sincronização por **união** entre o estado local e o remoto;
- aplicação remota **somente em conversas que já existem localmente**.

### Por que não as alternativas

| Alternativa | Motivo para não usar |
|---|---|
| XEP-0049 (Private XML Storage) | É um documento único por usuário: sobrescreve tudo, não avisa os outros recursos e mistura estados de vários aparelhos |
| Extensão dentro de `urn:xmpp:bookmarks:1` | O bookmark significa participação/`autoJoin`; outro cliente pode republicar o item e remover a extensão customizada |
| API HTTP própria no servidor | Exige autenticação, deploy e tratamento de falhas; os dois clientes já falam PEP |
| Tabela/coluna no banco do servidor | Os clientes continuariam precisando de um protocolo; não simplifica nada |
| Sincronizar tudo pelo MAM | MAM é histórico de mensagens, não estado de interface |

O PEP já é usado pelos dois clientes: o Android usa para bookmarks 2.0 e MDS
(`MessageDisplayedSynchronizationManager`), e o Monal registra MDS e bookmarks em
`MLPubSubProcessor`. O Prosody dos vhosts já tem `pep` ativo e `pep_max_items = 512`.

## Semântica de “arquivado”

“Arquivado” aqui significa **fora da lista de conversas recentes**, não “sair da sala”.
São estados diferentes:

| Situação | Contato (1:1) | Grupo/canal |
|---|---|---|
| Arquivar | `STATUS_ARCHIVED`, remove da lista | `archivedLocally = true`, continua `STATUS_AVAILABLE` |
| Continua conectado | não se aplica | sim, sala e bookmark intactos |
| Mensagem nova | desarquiva e volta para a lista | continua arquivado, sem notificação/badge |
| Abrir a conversa | desarquiva | **não** desarquiva |
| Desarquivar | automático ao abrir/receber | explícito no menu do bookmark |
| Sair do grupo/canal | não se aplica | fluxo separado; **não** publica estado |

O Android mantém essa diferença: 1:1 usa o status do Conversations; grupo/canal usa
`archivedLocally`. O iOS deve reproduzir a mesma diferença, com um único campo persistido e
regras por tipo (detalhado abaixo).

## Protocolo

### Nó e item

- Nó: `im.isacloud:conversation-state:0`
- Serviço: o próprio bare JID da conta (`account@domínio`), como no MDS
- `item id`: o JID bare da conversa (o mesmo endereço usado em `Conversation.getAddress()`)
- O atributo `mode` no payload evita aplicar um estado de 1:1 em um grupo/canal com o mesmo JID.

### Payload

```xml
<conversation-state xmlns='im.isacloud:conversation-state:0'
                    archived='true'
                    mode='multi'
                    updated='2026-11-01T18:00:00Z'
                    device='4f1c2a9e-...'/>
```

| Atributo | Obrigatório | Descrição |
|---|---|---|
| `archived` | sim | `true` para arquivado, `false` para ativo |
| `mode` | sim | `single` (1:1) ou `multi` (grupo/canal) |
| `updated` | sim | instante da última mudança, ISO 8601 em UTC |
| `device` | recomendado | UUID aleatório por instalação, só para diagnóstico/desempate; nunca usar identificador de hardware |

O item continua existindo com `archived='false'`. Isso permite comparar `updated` e resolver
conflito; retrair o item apagaria a informação de quando o desarquivamento aconteceu.

### Configuração do nó

Publicar com:

```
pubsub#persist_items           = true
pubsub#access_model            = whitelist
pubsub#max_items               = 512
pubsub#send_last_published_item = never
pubsub#notify_delete           = true
pubsub#notify_retract          = true
```

- `whitelist` sem afiliações deixa o nó restrito ao dono.
- `512` é o limite do `pep_max_items` do Prosody atual; é suficiente para uso pessoal.
- O Android já tem `NodeConfiguration.WHITELIST_MAX_ITEMS`, que publica `pubsub#max_items='max'`; o
  Prosody atual limita o nó a 512.
- O Monal publica com `pubsub#persist_items`, `pubsub#access_model` e `pubsub#max_items` e já
  trata `precondition-not-met` reconfigurando o nó (`MLPubSub.m`).

### Quando publicar

Publicar somente em ação do usuário:

- arquivar/desarquivar um grupo ou canal;
- arquivar/desarquivar uma conversa 1:1;
- desarquivar automaticamente uma conversa 1:1 quando uma mensagem nova chega ou quando ela é
  aberta (o Android já faz isso).

**Não** publicar:

- ao sair de um grupo/canal (isso é participação, não arquivamento);
- quando o bookmark é removido ou deixa de ter `autoJoin`;
- ao bloquear um contato;
- ao aplicar um estado vindo do PEP (evita eco e loop).

Falha de publicação não bloqueia a UI. A conversa fica com `pending = true` e a publicação é
repetida na próxima conexão.

### Quando receber

O cliente busca o nó no connect e também processa os eventos PEP em tempo real.

Regras de aplicação:

1. Validar o JID do item e o `mode`; se não bater com uma conversa local, ignorar.
2. Nunca criar contato, grupo, canal ou conversa por causa de um item.
3. Aplicar somente em conversa existente. Se ela ainda não estiver carregada, guardar o estado
   em um mapa `JID -> estado` e aplicar quando a conversa for criada (por exemplo, ao entrar por
   bookmark).
4. Aplicação remota **nunca** publica de volta.
5. Atualizar a UI e o badge depois de aplicar.

### Conflito e relógio

- Se a conversa tem `pending = true`, o estado local vence: publicar e ignorar o remoto.
- Senão, comparar `updated`: o mais recente vence.
- Em empate, manter o local (não publicar) para evitar oscilação.
- O `device` serve apenas para diagnóstico; não é usado para decidir o vencedor.

Limitação conhecida: relógios diferentes entre os aparelhos podem inverter o vencedor. Para uso
pessoal e ações explícitas, o risco é aceitável. Não vale introduzir relógio lógico nesta fase.
Se os dois aparelhos estiverem offline com mudanças pendentes, cada um publica a sua e o último
que publicar vence; o `updated` não resolve porque o pending tem prioridade sobre o remoto.

### Primeira sincronização e migração

Antes de ligar a sincronização, cada conta tem um marcador local “estado inicial sincronizado”
(preferência por conta no Android; `HelperTools defaultsDB` por conta no iOS).

Na primeira execução:

1. Buscar o nó.
2. Se o nó não existir ou estiver vazio: publicar como arquivadas todas as conversas arquivadas
   localmente.
3. Se o nó já tiver itens: aplicar o remoto e publicar as conversas arquivadas localmente que não
   têm item (união). Não desarquivar nada em massa.
4. Marcar a conta como inicializada.

No Android, a enumeração local inclui **1:1 com `STATUS_ARCHIVED`** e **grupo/canal com
`archivedLocally = true`**. Um grupo/canal com `STATUS_ARCHIVED` sem `archivedLocally` está
**fora da sala**, não arquivado localmente; não entra na enumeração.

Depois disso:

- item com `pending`: publicar o local;
- item remoto mais novo: aplicar;
- conversa local arquivada sem item remoto: tratar como ativa (o item só falta se o nó foi
  apagado ou se o item foi expulso pelo limite de 512).

### Itens órfãos e limite

- Ignorar itens de conversas que não existem localmente; não apagar o item por causa disso.
- Com 512 itens, o servidor pode expulsar os mais antigos. O efeito é uma conversa antiga voltar a
  ser considerada ativa em um aparelho novo. Documentar como limitação; não criar rotina de
  limpeza nesta fase.
- `retract`/`delete`/`purge` não são usados. Se chegarem, tratar `retract` como
  `archived='false'` e `delete`/`purge` como no-op para não desarquivar tudo por acidente.

## Android — o que muda

### Modelo e manager

- Adicionar `Namespace.CONVERSATION_STATE = "im.isacloud:conversation-state:0"`.
- Criar `im.conversations.android.xmpp.model.conversationstate.ConversationState` com
  `@XmlElement(namespace = Namespace.CONVERSATION_STATE)` e getters/setters para os atributos.
- Criar `ConversationStateManager extends AbstractManager`, no molde de
  `MessageDisplayedSynchronizationManager`:
  - `hasFeature()`: `PepManager.isAvailable() && hasPublishOptions() && hasConfigNodeMax()`;
  - `fetch()`: busca todos os itens e aplica; `item-not-found` significa nó vazio, não erro;
  - `handleItems(Items)`: processa eventos PEP;
  - `publish(Conversation, boolean archived)`: publica o item da conversa;
  - `flushPending()`: republica o que ficou pendente;
  - `applyRemote(...)`: aplica sem publicar.
- Registrar em `Managers.java`.
- Despachar em `PubSubManager.handleItems` quando `connection.fromAccount(message)` e o nó for
  `CONVERSATION_STATE`.

### Atributos da conversa

Em `Conversation.Attributes` (JSON, sem migração de banco):

- `archived_locally` — já existe;
- `archived_state_updated` — instante da última mudança (epoch millis);
- `archived_state_pending` — mudança local ainda não publicada.

Para 1:1, `archived_locally` continua falso; o estado real é `STATUS_ARCHIVED`. Os dois novos
atributos valem para os dois tipos.

### Pontos de publicação

Concentrar a publicação em um wrapper de ação do usuário (por exemplo
`archiveConversationByUser` / `unarchiveConversationByUser`), chamado pelo swipe, pelo menu e
pelo “limpar histórico”. Não colocar a publicação dentro de `archiveConversation` puro, para não
publicar quando o arquivamento vem de bookmark, bloqueio ou aplicação remota.

- `XmppConnectionService.archiveConversationLocally()`:
  - grupo/canal: marca `archivedLocally`, atualiza o banco e publica `true`;
  - 1:1: chama o arquivamento atual e publica `true`.
- `XmppConnectionService.unarchiveConversationLocally()`: limpa o flag e publica `false`.
- `restoreFromArchive()`: **apenas para `MODE_SINGLE`**, se a conversa estava `STATUS_ARCHIVED` e
  está sendo restaurada (mensagem nova ou abertura), publicar `false` depois de restaurar, exceto
  quando a restauração veio de uma aplicação remota (flag de supressão). Em `MODE_MULTI`,
  `STATUS_ARCHIVED` significa saída da sala, não estado local; não publicar.
- Menu “Archive chat” de 1:1: publicar. Para grupo/canal, o menu continua saindo da sala e **não**
  publica; o swipe é o caminho de arquivamento local.
- “Limpar histórico” com “encerrar conversa” em 1:1: publicar, pois é ação de UI que arquiva.
- Não publicar em `archiveConversation(conversation, false)` chamado por bookmark, bloqueio ou
  remoção de bookmark.

### Aplicação remota

- Grupo/canal:
  - `conversation.setArchivedLocally(true/false)`, atualizar banco e UI;
  - nunca chamar `archiveConversation` (isso daria `leave()` e mexeria no bookmark).
- 1:1 arquivado:
  - marcar `STATUS_ARCHIVED`, atualizar o banco, limpar a notificação e remover de `conversations`,
    de preferência em um método próprio que não repita efeitos colaterais desnecessários do
    `archiveConversation` (MAM/presença);
  - o efeito prático é o mesmo do arquivamento atual: some da lista e a próxima mensagem restaura.
- 1:1 desarquivado:
  - **verificar antes se a conversa existe no banco** (`databaseBackend.findConversation`); só
    então carregar/restaurar com `findOrCreateConversation` e supressão de publicação;
  - não usar `findOrCreateConversation` com um JID desconhecido, para não criar conversa.
- Em todos os casos, gravar `archived_state_updated` com o `updated` remoto e
  `archived_state_pending = false`.
- Conversa desconhecida: guardar no mapa do manager e aplicar quando ela for criada.

### Momento do fetch

Em `BindProcessor`, depois de `BookmarkManager.request()` e do fetch de MDS:

```java
final var stateManager = getManager(ConversationStateManager.class);
if (stateManager.hasFeature()) {
    stateManager.fetch();      // aplica o remoto e depois faz flush do pending
} else {
    Log.d(Config.LOGTAG, account.getJid() + ": server has no support for conversation state");
}
```

Adicionar uma constante em `Config` (por exemplo `SYNC_ARCHIVED_STATE = true`) como chave de
desligamento rápido, no molde de `MESSAGE_DISPLAYED_SYNCHRONIZATION`.

### UI

- Nenhuma tela nova. `ConversationsOverviewFragment.matches()` já esconde `archivedLocally`.
- 1:1 arquivado continua sumindo pelo `STATUS_ARCHIVED`.
- A linha “Arquivado” do bookmark continua sendo alimentada por `isArchivedLocally()`.
- O “Desarquivar” do menu do bookmark continua chamando `unarchiveConversationLocally()`.

### Convenções

- Comentar os pontos alterados com `// isaCloud: ...`, como no restante do fork.
- Não criar migração de banco: os atributos novos são JSON em `Conversation.ATTRIBUTES`.

## iOS — o que muda

O trabalho maior não é o PEP; é tornar o arquivamento **durável e silencioso** como no Android.
Hoje o Monal arquiva apagando a linha de `activechats` e marcando as mensagens como lidas; a
mensagem seguinte readiciona a conversa. A proposta é parar de apagar a linha: o estado passa a
ser um campo em `buddylist` e a lista filtra por ele.

### Diagnóstico do código atual

- `DataLayer.removeActiveBuddy:` (`DataLayer.m:2293`) marca tudo como lido e apaga
  `activechats`.
- `DataLayer.addActiveBuddies:` (`DataLayer.m:2310`) insere `activechats` de novo.
- A lista de conversas vem de `activeContactsWithPinned:` (`DataLayer.m:2258`).
- `MLMessageProcessor.m:823`, `MLMucProcessor.m:1803`, `MonalAppDelegate.m:815/847`,
  `ActiveChatsViewController.m:1467`, `chatViewController.m:1778` e `ChatView.swift:580/669`
  chamam `addActiveBuddies`.
- `MLNotificationManager.internalMessageHandlerWithMessage:` não verifica arquivamento.
- `DataLayer.countUnreadMessages`, `chatsWithUnreadMessages` e o badge não verificam arquivamento.
- A entrada em MUC é guiada por `muc_favorites`/bookmarks (`MLMucProcessor`), não por
  `activechats`; portanto arquivar **não** sai da sala. Isso já está alinhado com o Android.

### Banco e migração

Usar a escada própria `updateISACloudDB` (`DataLayerMigrations.m`), hoje na versão 4. Nova
migração **5**, idempotente, na tabela `buddylist`:

```
archived          BOOL DEFAULT FALSE
archived_updated  INTEGER DEFAULT 0      -- epoch millis
archived_pending  BOOL DEFAULT FALSE
```

Por que `buddylist` e não `activechats`:

- a linha existe para contato e para MUC independentemente de haver mensagens;
- as consultas que interessam já fazem join com `buddylist`
  (`activeContactsWithPinned`, `countUnreadMessages`, `chatsWithUnreadMessages`);
- `activechats` continua significando “existe conversa com mensagens”, sem carregar o estado de
  arquivamento;
- **não apagar `activechats`** preserva `pinned` e `lastMessageTime` ao arquivar. A conversa só
  deixa de aparecer porque a consulta da lista filtra `buddylist.archived = 0`.

A migração deve rodar também quando o banco é aberto pela extensão de notificação.

### Estado local

Adicionar em `DataLayer`:

- `-(BOOL)isArchivedBuddy:forAccount:`
- `-(void)archiveBuddy:forAccount:` — grava `archived=1`, `archived_updated=now`,
  `archived_pending=1`; **não** apaga `activechats` e **não** marca mensagens como lidas.
- `-(void)unarchiveBuddy:forAccount:` — grava `archived=0`, `archived_updated=now`,
  `archived_pending=1`; se a linha de `activechats` tiver sido removida por alguma versão
  anterior, recria.
- leitura/gravação dos campos `updated` e `pending` para o sincronizador.
- `addActiveBuddies:` passa a:
  - **1:1 arquivado:** limpar `archived`, `archived_updated=now`, `archived_pending=1` e garantir
    a linha em `activechats` (equivale ao restore do Android);
  - **grupo/canal arquivado:** não mexer no estado; a linha de `activechats` pode existir, mas a
    lista filtra `archived = 0`;
  - **não arquivado:** comportamento atual.

Essa centralização em `addActiveBuddies` cobre todos os caminhos que hoje fazem a conversa voltar:
mensagem nova, abertura, envio e encaminhamento. Para grupo/canal, o `isBuddyMuc` impede o
restore; para 1:1, o retorno é intencional.

O `removeActiveBuddy` atual deixa de ser usado para arquivar (ele marca como lido). Se não houver
outro uso, pode ser removido depois; o arquivamento passa a ser `archiveBuddy`.

Adicionar `isArchived` em `MLContact` (lido de `buddylist.archived` em
`contactDictionaryForUsername`) para a UI de detalhes.

### Lista, badge e notificações

- `activeContactsWithPinned:`: `AND b.archived = 0`.
- `countUnreadMessages`: `AND B.archived = 0`.
- `chatsWithUnreadMessages`: `AND b.archived = 0`.
- `contactDictionaryForUsername`: calcular `isActiveChat` com `archived = 0`, para o estado não
  divergir do que a lista mostra.
- contador de não lidas por conversa: ignorar arquivadas.
- `MLNotificationManager.handleNewMessage` / `internalMessageHandlerWithMessage`: retornar cedo
  se `isArchivedBuddy` for verdadeiro. Isso cobre mensagens normais e reações; a extensão de
  notificação usa o mesmo `MLNotificationManager` e o mesmo banco.
- Ao arquivar, remover notificações pendentes/entregues da conversa **sem marcar como lidas**.
  Reaproveitar o caminho de `handleDisplayedMessages` com as mensagens não lidas do contato, ou
  remover pelos identificadores já usados pelo notification manager.
- Disparar `updateUnread` depois de arquivar/desarquivar para o badge refletir na hora.
- Reações: além do check no `handleNewMessage`, garantir que o caminho
  `showNotificationForReactions` também respeite o estado arquivado.

### Sincronização PEP

Criar um componente novo, por exemplo `MLArchivedStateSync`, com uma instância por conta. O
`DataLayer` grava o estado, marca `archived_pending` e posta uma notificação
(`kMonalArchivedStateChanged`) **depois de fechar a transação de banco**; o componente observa,
publica e limpa o pending. A aplicação de um estado remoto grava com `archived_pending = false` e
não dispara esse aviso (ou o dispara com uma flag `remote = YES`) para não publicar de volta.
Não usar `archiveBuddy`/`unarchiveBuddy` no caminho remoto; usar um `applyArchivedState:` que só
grava e atualiza a UI.

1. **Registrar o nó** em `xmpp.m`, junto de MDS/bookmarks:

   ```objc
   [self.pubsub registerForNode:@"im.isacloud:conversation-state:0"
                   withHandler:$newHandler(MLPubSubProcessor, archivedStateHandler)];
   ```

2. **Buscar no connect**, logo depois do fetch de MDS (`xmpp.m`, por volta de `4883`):

   ```objc
   [self.pubsub fetchNode:@"im.isacloud:conversation-state:0"
                       from:self.connectionProperties.identity.jid
              withItemsList:nil
                  andHandler:$newHandler(MLPubSubProcessor, handleArchivedStateFetch)];
   ```

3. **Handler de evento** em `MLPubSubProcessor`:
   - `publish`: processar cada `<item id='jid'>` com filho
     `{im.isacloud:conversation-state:0}conversation-state`;
   - `retract`: tratar como `archived='false'`;
   - `delete`/`purge`: no-op (não desarquivar em massa).

4. **Aplicação**:
   - descartar evento cujo `jid` não seja o próprio bare JID (como o handler de MDS faz);
   - ignorar item sem `buddylist` correspondente (não criar contato/MUC);
   - validar `mode` contra `isBuddyMuc`;
   - se `archived_pending=1`, publicar o local e ignorar o remoto;
   - senão comparar `archived_updated` com `updated`; o mais novo vence;
   - aplicar com um caminho que **não** publique de volta e gravar `archived_pending = false`;
   - postar `kMonalArchivedStateChanged`; a lista deve observar e chamar `refreshDisplay` (o
     `refreshContact` atual só recarrega a linha existente, não remove nem insere), e a tela de
     detalhes deve reler o contato.

5. **Publicação**:
   - montar `<item id='jid'><conversation-state .../></item>`;
   - `[account.pubsub publishItem:item onNode:@"im.isacloud:conversation-state:0"
     withConfigOptions:@{...} andHandler:...]`;
   - em sucesso, limpar `archived_pending`; em falha, manter pending e tentar no próximo connect;
   - o Monal já reconfigura o nó em `precondition-not-met`.

6. **Bootstrap**: mesma regra do Android (união na primeira vez; depois, pending vence; item
   ausente = ativo). Guardar o marcador “inicializado” por conta em `HelperTools defaultsDB`.
   Limitação de migração: conversas arquivadas no iOS **antes** desta versão não têm o campo
   `archived` (a versão antiga apagava `activechats` e marcava como lido); elas não entram na
   primeira união e precisam ser arquivadas de novo uma vez.

7. **Flush**: no connect, buscar o nó, aplicar, e publicar os `archived_pending` que sobraram.

### UI no iOS

- Trocar o uso de `removeActiveBuddy` no arquivamento por `archiveBuddy` (sem marcar como lido e
  sem apagar a linha de `activechats`; a lista esconde pelo filtro e o `pinned` é preservado).
- Em `ContactDetails.swift`, mostrar “Arquivado” e uma ação **Desarquivar** quando
  `contact.isArchived`, para grupo/canal. É o equivalente ao menu do ícone “i” do Android. Para
  1:1, o desarquivamento continua acontecendo ao abrir/receber, como no Android; mostrar a ação
  também para 1:1 é opcional.
- Não criar tela de “Arquivados” nesta fase, para ficar alinhado ao Android.
- Abrir uma conversa 1:1 arquivada desarquiva (via `addActiveBuddies`); abrir um grupo/canal
  arquivado **não** desarquiva.
- Enviar mensagem para grupo/canal arquivado não desarquiva.
- O menu “Archive Conversation” continua usando o mesmo fluxo; só passa a gravar o estado e
  publicar.
- Textos novos (“Archived”, “Unarchive”) entram nos arquivos de localização do Monal em inglês e
  pt-BR; comentar as alterações com `//isaCloud:` como no restante do fork.

### Compatibilidade

- iOS antigo e Android antigo ignoram o nó; nada quebra.
- Se só o Android for atualizado, o estado fica no servidor e passa a valer quando o iOS novo
  entrar.
- O iOS novo sem o Android novo também funciona; o Android antigo continua local.
- Nenhuma mudança no servidor além de validar o disco (PEP, `publish-options`,
  `config-node-max`).

## Segurança e privacidade

- `access_model = whitelist` restringe o nó ao dono; outros usuários não leem nem publicam.
- O payload fica no servidor em claro. O admin do servidor consegue ver quais JIDs estão
  arquivados. É metadado de baixa sensibilidade (o servidor já vê o roster e o tráfego), mas deve
  ser documentado.
- Não incluir conteúdo de mensagem, motivo, nome de exibição ou qualquer dado além do JID, estado,
  instante e UUID de instalação.
- O `device` deve ser um UUID aleatório por instalação, não `ANDROID_ID`, IDFA ou identificador de
  hardware.
- Criptografar o payload entre os aparelhos é possível, mas exigiria gestão de chave; fica fora
  desta fase.

## Rollout

- Não entra na release 42, que é o swipe para arquivar. Proposta: release 43.
- Android: `Config.SYNC_ARCHIVED_STATE` como chave de desligamento; ligar por padrão somente
  depois dos testes com as duas contas.
- iOS: o gate natural é `supportsPubSub`/`accountDiscoDone`; se o servidor não anunciar PEP, o
  componente fica inativo e o comportamento local continua.
- Servidor: nenhuma mudança de código; validar `disco#info` do próprio JID para PEP,
  `pubsub#publish-options` e `pubsub#config-node-max`.
- Clientes antigos: sem efeito. Clientes novos: sincronizam entre si.

## Riscos e limitações

- **Mudança de semântica no iOS:** é a parte mais delicada. Arquivar deixa de marcar como lido e
  deixa de ser desfeito por mensagem em grupo/canal. Testar bem notificações, badge e contador
  por conversa.
- **Relógio entre aparelhos:** LWW por timestamp pode inverter o vencedor. Aceitável para uso
  pessoal; documentar.
- **Limite de 512 itens:** itens antigos podem ser expulsos; uma conversa antiga pode voltar a
  “ativa” em um aparelho novo. Para o volume esperado, não deve acontecer.
- **Itens órfãos:** conversas apagadas deixam itens; ignorar sem apagar.
- **Conversa aberta:** arquivar no outro aparelho pode remover a conversa da lista enquanto ela
  está aberta; a tela continua, mas ao voltar ela estará arquivada.
- **Menu “Archive chat” de grupo/canal:** continua saindo da sala e não é sincronizado por este
  nó. Só o swipe é arquivamento local. Se depois o menu também passar a arquivar localmente, ele
  deve publicar o estado.
- **Sem tela de arquivados:** no Android, a recuperação é bookmark/busca; no iOS, contatos e
  detalhes. Se o bookmark for removido, o grupo/canal só é alcançável por busca/contatos.
- **Sair e reentrar:** sair de um grupo/canal não publica estado; se ele estava arquivado, volta
  arquivado ao reentrar. O desarquivamento é explícito.
- **PEP do servidor:** se `publish-options` ou `config-node-max` não forem anunciados, a feature
  fica desligada. Validar antes de ligar por padrão.

## Ordem sugerida de implementação

1. **Validar o servidor:** com uma conta de teste, confirmar PEP e as features de configuração;
   criar o nó e conferir `whitelist`/`max_items` com um cliente XMPP.
2. **Android local:** modelo, manager, atributos, publicação e aplicação remota; testar só no
   Android, inspecionando o nó com outro cliente.
3. **iOS local:** migração 5, `archiveBuddy`/`unarchiveBuddy`, filtro da lista, badge e
   notificações; testar só no iOS, sem PEP.
4. **iOS PEP:** registro, fetch, handler, publicação e flush; testar Android ↔ iOS.
5. **Ligar por padrão** e publicar na release seguinte (proposta: 43).

## Testes

### Pré-requisitos

- Conta de teste em `docs/NOTAS-LOCAIS.md` usada nos dois aparelhos.
- Android e iOS com a mesma conta, ambos atualizados.
- `disco#info` do próprio JID mostrando PEP e as features de configuração.

### Matriz mínima

| # | Ação | Resultado esperado |
|---|---|---|
| 1 | Arquivar grupo no Android | iOS esconde o grupo, continua participando, sem notificação e sem badge |
| 2 | Desarquivar o mesmo grupo no iOS | Android volta a mostrar o grupo |
| 3 | Arquivar canal no Android | Mesmo comportamento do grupo; bookmark/`autoJoin` intactos |
| 4 | Arquivar 1:1 no Android | iOS esconde a conversa |
| 5 | Enviar mensagem nova para o 1:1 arquivado | Os dois desarquivam e mostram a mensagem |
| 6 | Abrir 1:1 arquivado no iOS | Desarquiva nos dois |
| 7 | Abrir grupo/canal arquivado | Continua arquivado nos dois |
| 8 | Arquivar offline no Android e desarquivar online no iOS | Ao reconectar, o mais recente vence; nenhum loop de publicação |
| 9 | Instalação limpa com nó vazio | Estado local sobe; nada é perdido |
| 10 | Instalação limpa com nó preenchido | Estado remoto é aplicado; conversas desconhecidas são ignoradas |
| 11 | Servidor sem PEP | Feature desligada; arquivamento local continua |
| 12 | Reiniciar os dois apps | Estado persiste; grupo/canal arquivado não notifica |
| 13 | Sair de um grupo/canal | Bookmark/`autoJoin` mudam como hoje; estado arquivado não é publicado |
| 14 | Duas contas no mesmo aparelho | Estados não se misturam (nó por conta) |
| 15 | Mais de 512 itens (teste de limite) | Documentar o comportamento; não travar |
| 16 | Fixar uma conversa, arquivar e desarquivar | Continua fixada (iOS não perde `pinned`) |

### Validação específica do iOS

- Arquivar não marca mais as mensagens como lidas; ao desarquivar, o contador aparece.
- Badge e “não lidas” ignoram grupo/canal arquivado, mas voltam ao desarquivar.
- Notificação de mensagem e de reação não aparece para grupo/canal arquivado.
- A extensão de notificação respeita o estado (mesmo banco).
- A lista de conversas não mostra a conversa arquivada, mas `ContactsView` e a busca continuam
  alcançando o grupo/canal.
- “Desarquivar” em `ContactDetails` funciona para grupo/canal; 1:1 volta ao abrir/receber.

## Fora de escopo

- Tela/pasta de arquivados em qualquer um dos clientes.
- Sincronizar silenciado, fixado, não lidas ou rascunhos.
- Sincronizar participação/`autoJoin` (já é feito pelos bookmarks).
- Criptografar o payload do PEP.
- Módulo customizado no Prosody ou API HTTP.
- Mudar o comportamento do menu “Archive chat” de grupo/canal.

## Decisões tomadas para o iOS (03/11/2026, Isadora)

Tomadas na avaliação do iOS, antes de qualquer implementação. **Nada foi implementado; a Isadora pediu para não começar o PR 1 ainda.**

1. **Menções (@) em grupo/canal arquivado:** só uma **menção** (@ para o meu nick/nome) notifica; mensagem comum fica muda. Uma menção **só notifica**: **não** traz o grupo de volta à lista.
2. **Badge e contador por conversa:** em grupo/canal arquivado contam **só as menções**.
3. **Mensagem nova em grupo/canal arquivado:** continua escondida e sem notificação, como no Android. Não desarquiva.
4. **Rótulo "Arquivado":** aparece nas **listas** (contatos, grupos e canais) **e** na tela de detalhes.
5. **"Abrir no ponto da última menção"** vale para **todos** os grupos e canais (não só arquivados), mas é uma **feature separada**, que será implementada **antes** deste trabalho (roadmap 135; a feature mais geral "abrir na primeira não lida", roadmap 136 e `docs/feature-abrir-na-primeira-nao-lida.md`, cobre a maior parte e pode absorvê-la). Quando o PR 1 vier, o ponto da última menção já existe; o PR 1 não implementa isso.
6. **Ordem de entrega:** o PR 1 (arquivamento local duradouro, sem PEP) **não começa ainda**; o PR 2 (PEP) espera o nó do Android validado.

### Efeito no desenho do iOS

- **Notificação** (`MLNotificationManager internalMessageHandlerWithMessage:`): em vez de "retornar cedo se arquivado", retornar cedo **exceto se a mensagem menciona o usuário**. Reaproveitar o `HelperTools text:mentionsAnyOfNames:` que o ramo "só menções" do mesmo método já usa (nick da sala, nome de exibição, parte local do JID e JID), valendo também para a extensão (mesmo código). Reação não notifica.
- **Badge e contador:** `countUnreadMessages`, `chatsWithUnreadMessages` e o contador por conversa, para grupo/canal arquivado, contam apenas mensagens que mencionam o usuário (em vez de excluir a conversa por inteiro, como o desenho do Android sugeria). Precisa de um jeito barato de saber "é menção" nas consultas (por exemplo, marcar a mensagem como menção quando chega, em coluna ou flag, na mesma escada do isaCloud) a definir no PR 1.
- **Rótulo nas listas:** `ContactsView` e as listas de grupos/canais mostram "Arquivado" (texto novo em inglês + pt-BR). A lista de conversas recentes continua escondendo os arquivados.
- **Menção não desarquiva:** a notificação aparece, mas a conversa continua fora da lista; tocar na notificação abre o chat sem desarquivar (consistente com "abrir grupo/canal arquivado não desarquiva").

## Decisões ainda em aberto

1. Release (proposta do doc: 43, é do Android; o iOS sai com o próximo build que a Isadora pedir).
2. Abrir 1:1 arquivado desarquiva (como no Android): confirmar para o iOS.
3. **Namespace do nó PEP:** o documento do Android usa `im.isacloud:conversation-state:0` (domínio `isacloud.im` invertido, sufixo `:0` de versão) e o lista como definitivo; **sugestão: manter** esse nome nos dois clientes, porque trocá-lo depois deixa os estados já publicados órfãos. Aguarda o ok da Isadora.

## Referências de código

### Android

- `src/main/java/eu/siacs/conversations/entities/Conversation.java` — `archivedLocally` e
  atributos.
- `src/main/java/eu/siacs/conversations/services/XmppConnectionService.java` —
  `archiveConversationLocally`, `unarchiveConversationLocally`, `archiveConversation`,
  `restoreFromArchive`.
- `src/main/java/eu/siacs/conversations/xmpp/manager/MessageDisplayedSynchronizationManager.java`
  — molde de manager PEP.
- `src/main/java/eu/siacs/conversations/xmpp/manager/PubSubManager.java` — dispatch de eventos.
- `src/main/java/eu/siacs/conversations/xmpp/Managers.java` — registro de managers.
- `src/main/java/im/conversations/android/xmpp/processor/BindProcessor.java` — fetch no connect.
- `src/main/java/eu/siacs/conversations/ui/ConversationsOverviewFragment.java` — filtro da lista.
- `docs/deslizar-para-arquivar.md` — decisão do arquivamento local.

### iOS

- `Monal/Classes/DataLayer.m` — `removeActiveBuddy`, `addActiveBuddies`,
  `activeContactsWithPinned`, `countUnreadMessages`, `chatsWithUnreadMessages`.
- `Monal/Classes/DataLayerMigrations.m` — escada `updateISACloudDB`.
- `Monal/Classes/MLMessageProcessor.m` — chamada de `addActiveBuddies` em mensagem nova.
- `Monal/Classes/MLNotificationManager.m` — decisão de notificar e badge.
- `Monal/Classes/MLPubSub.m` / `MLPubSubProcessor.m` — registro, fetch e publicação PEP.
- `Monal/Classes/xmpp.m` — registro dos nós e fetch no connect.
- `Monal/Classes/ContactDetails.swift` — ação de desarquivar.
- `Monal/NotificationService/NotificationService.m` — extensão que usa o mesmo
  `MLNotificationManager`.

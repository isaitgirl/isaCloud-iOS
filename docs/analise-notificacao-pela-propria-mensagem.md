# Análise: a extensão entregar a própria mensagem no lugar do placeholder

**Data:** 27/11/2026
**Estado:** análise, nada implementado
**Origem:** a medição de 27/11 (`docs/analise-alerta-decidido-pelo-servidor.md`) mostrou que a
notificação vazia ao lado de uma mensagem 1:1 é o placeholder do próprio push. Em 48 de 53 pushes
havia mensagem de verdade para mostrar.

## Atualização (27/11, 14:55): o caso da mensagem já lida

A Isadora pegou um exemplo ao vivo: uma mensagem 1:1 que ela já tinha lido no computador apareceu
como notificação vazia. Quando chegou outra notificação, a vazia sumiu, mas uma nova ficou no lugar
até ela abrir o app. No log:

- **14:51:55**, push de uma mensagem nova. A extensão conecta e, em cerca de 1 s, chegam os avisos
  de leitura do outro aparelho (carbons `displayed` próprios e MDS). O `MLNotificationManager` cancela
  as notificações locais ainda pendentes, então a mensagem nunca aparece. Aos 25 s (**14:52:20**), o
  handler recebe o placeholder: **a vazia fica sozinha**.
- **14:52:47**, novo push. A extensão apaga a vazia anterior, publica duas mensagens de verdade e,
  às **14:53:12**, entrega outro placeholder. É a vazia que ficou pendurada.

Contando nos logs do dia (49 execuções, 08:54 às 14:53):

| O que sobrou na tela ao fim dos 25 s | Execuções | A promoção resolve? |
|---|---|---|
| Pelo menos uma mensagem de verdade | 27 | Sim |
| Tudo lido em outro aparelho durante a execução | 18 (aproximado*) | **Não**: não há o que promover, sai o placeholder |
| Nada publicado | 4 | Não |

\* Conta as execuções em que o número de mensagens marcadas como lidas foi maior ou igual ao de
publicadas. Pode incluir leituras de mensagens antigas, então é uma estimativa por cima.

Ou seja, **mais de um terço das vazias é de mensagem lida em outro aparelho**, e a promoção sozinha
não resolve esse caso. Duas saídas que resolvem:

### Alternativa B: a extensão apaga o próprio placeholder antes de sair (só app, pequena)

Hoje o placeholder entregue só é apagado pela execução *seguinte* ou pelo app (o "isaCloud: removing
1 push placeholder" no começo da próxima execução prova que a extensão consegue apagá-lo). Depois de
alimentar o último handler, a extensão ainda roda cerca de 0,6 s (`usleep(500000)` mais o
`disconnectAll`) antes do `_exit`. A ideia é apagar ali os placeholders entregues, logo antes do
`killAppex`, com uma espera curta (por exemplo, 300 ms) e saindo de qualquer jeito no fim.

- Resolve **os dois casos** (vazia ao lado da mensagem e vazia sozinha), sem mexer em
  identificadores, na remoção por leitura nem no fpush.
- Efeito visível: o placeholder é passivo (sem banner, sem som, não acende a tela). Ele fica na
  Central de Notificações por menos de 1 s.
- Risco: era isso que o build antigo fazia com 1 s de atraso, e foi tirado porque mantinha a extensão
  viva com o SQLite aberto (`0xdead10cc`). A diferença é fazer **depois** do `disconnectAll` (estado
  já gravado) e com prazo, na mesma janela de ~0,6 s que já existe hoje. Precisa ser testado no
  `.dev`: a primeira pergunta é se o placeholder já aparece no `getDeliveredNotifications` tão cedo.
- Quando o push não for o último da execução (dois pushes em 51 s), o placeholder do primeiro só é
  apagado no fim, junto com o do segundo.

### Alternativa C: o servidor segurar o push quando outro aparelho está ativo

Na sequência das 14:51, a leitura no computador chegou cerca de 1 s depois de a mensagem chegar ao
iPhone. Se o `cloud_notify_quiet` segurasse por alguns segundos o alerta de uma conversa 1:1 quando a
pessoa tem outra sessão **ativa** (não hibernada e sem CSI `inactive`), e cancelasse o alerta ao ver o
`displayed` próprio ou o MDS daquela conversa, o push nem sairia. O custo é atrasar a notificação do
iPhone em alguns segundos justamente quando a pessoa está usando outro aparelho, o que faz sentido.
É mais trabalho (fila com temporizador no módulo) e só cobre esse caso.

### Implementada e testada no `.dev` (27/11/2026)

A alternativa B entrou em `PushSingleton killAppex` (`HelperTools removeIsaCloudPushPlaceholdersBeforeExitWithTimeout:0.3`).
Boot de 60 s sem crash nos dois simuladores (iOS 18.6 e 27). No `.dev`, que recebe push desde 27/11:
mensagem 1:1 recebida, lida em outro aparelho, e a notificação sumiu sem deixar vazia. Depois, o caso
de mensagem **não lida**: só a notificação da mensagem ficou, sem vazia ao lado. E reações às mensagens da conta
que está no `.dev` também não deixaram vazia (antes deixavam). Os dois casos passaram; a promoção da mensagem e
a alternativa C ficam guardadas para o caso de a vazia voltar.

### Recomendação revisada

1. **Alternativa B primeiro**: é pequena, só no app, e ataca as duas origens da vazia. Testar no
   `.dev` se o placeholder some sozinho em ~1 s e se não aparece nenhum `0xdead10cc` novo.
2. A **promoção** (abaixo) passa a ser refinamento: evita o placeholder piscar quando há mensagem para
   mostrar. Só vale a pena se a B funcionar mal ou se o piscar incomodar.
3. A **C** fica para depois, se ainda sobrar vazia com a B no ar.

## Como funciona hoje

Medido no log do iPhone de produção (build 135, 08:54 às 14:46 de 27/11, 46 execuções da extensão):

1. O push chega. A extensão guarda o `contentHandler` num `PushHandler` com um timer de **25 s**
   (`NotificationService.m:263`) e conecta as contas.
2. Cada mensagem nova passa pelo `MLNotificationManager`, que agenda uma **notificação local** com o
   identificador `message(thread(conta, jid), id)` e um gatilho de **2 s**
   (`publishNotificationContent:withID:`). Os 2 s servem para um marcador de leitura que chegue logo
   depois, no catch-up, cancelar a notificação antes de ela aparecer.
3. A extensão **não alimenta o handler quando termina o catch-up**: ela fica conectada até o timer
   vencer. Em 51 das 53 alimentações, quem disparou foi o `pushExpired`. A execução durou 25,7 a
   26,0 s com um push e cerca de 51 s com dois. O `nowIdle` só antecipa no modo de economia.
4. No `pushExpired`, o `PushHandler feed` entrega o **placeholder** ao `contentHandler`
   (`NotificationService.m:66`).

Na prática, a pessoa vê a mensagem de verdade **~2 s** depois do push e o placeholder aparece **~21 s
depois disso** (mediana entre a publicação e a alimentação: 20,9 s). Em 106 das 120 publicações, a
local já tinha aparecido quando o handler foi alimentado.

O placeholder some no push seguinte (que entrega outro), quando o app acorda ou quando o app abre.
Com o `apns-collapse-id` fixo do fpush (`isacloud-sync`), fica sempre um.

### Por que não dá só para alimentar o handler mais cedo

Depois que o último handler é alimentado, o iOS pode congelar ou encerrar a extensão a qualquer
momento. O comentário do `pushExpired` explica: por isso o Monal congela as filas de parse e publica
os erros de sincronização *antes* de alimentar o último handler. Alimentar cedo perderia as
mensagens que ainda chegassem no catch-up e a desconexão limpa (estado do smacks salvo no banco, a
origem dos C34 e C38). Então a troca tem que acontecer **no mesmo momento de hoje** (o
`pushExpired`), só trocando **o que** é entregue.

## A proposta: promover uma notificação da própria execução

No `PushHandler feed`, antes de cair no placeholder:

1. **Escolher uma notificação desta execução** que ainda não foi promovida: a mais recente de
   mensagem ou reação publicada pelo `MLNotificationManager` desde o primeiro push.
2. **Montar o conteúdo de novo** a partir do `MLMessage` guardado, com o mesmo construtor de hoje
   (`showModernNotificationForMessage` e o legado, separados em "montar" e "publicar"). Reaproveitar o
   `UNNotification` entregue não serve: os anexos são hardlinks `tmp.*` que o iOS move ao publicar e
   apaga ao remover a notificação. Montar de novo recria o hardlink a partir do cache.
3. **Conferir o estado da local**, com o `notificationStateForMessage` que já existe
   (`MLNotificationManager.m:236`):
   - **pendente** (os 14 casos em que ela ainda não tinha aparecido): remove a pendente e entrega o
     conteúdo ao handler **com som**, como seria a local;
   - **entregue** (os 106 casos): entrega o conteúdo ao handler **sem som e passivo**
     (`interruptionLevel = passive`), e só depois remove a local entregue. A pessoa não percebe a
     troca, porque é o mesmo texto e o mesmo agrupamento por conversa;
   - **já removida** (lida, apagada, arquivada, deslizada): não ressuscita. Passa para a próxima
     candidata ou, sem nenhuma, cai no placeholder.
4. Marcar no `userInfo` do conteúdo promovido o identificador que a local teria
   (`isaCloudNotificationId = message(...)`).

Com vários pushes na mesma execução (6 das 46 tiveram dois), cada handler promove uma notificação
diferente. Handlers que sobram ficam com o placeholder.

O que sobra de placeholder: os 5 pushes sem nada para mostrar (no máximo ~10%), e os casos em que a
pessoa já tirou a notificação da tela antes dos 25 s.

## O que precisa mudar junto

### 1. O `collapse-id` do fpush tem que sair (servidor)

Com `apns-collapse-id`, o identificador da notificação entregue pelo `contentHandler` é o próprio id
(`isacloud-sync`). Hoje isso é bom (só sobra um placeholder). Com a promoção, seria ruim: **o push
seguinte substituiria a mensagem promovida anterior**, que sumiria da Central de Notificações. O fpush
deixa de mandar o `collapse-id` (constante `ISACLOUD_ALERT_COLLAPSE_ID` no patch v3, vira um v4).

O alerta de reserva ("Pode haver mensagens novas", que aparece quando a extensão morre) continua com
a marca `isaCloudPushPlaceholder` e continua sendo limpo no push seguinte e na abertura do app. Ele
só deixa de ser "um no máximo".

**Ordem:** o app com a promoção e a troca no fpush vão juntos, no mesmo dia (ver os passos no fim).

### 2. Remoção da notificação promovida (app)

A promovida tem identificador do push, não `message(...)`. Hoje o app remove por identificador em:

| Onde | Situação | Com a promoção |
|---|---|---|
| `handleDisplayedMessages` | lida aqui ou em outro aparelho | precisa achar pelo `userInfo` |
| `handleDeletedMessage` | mensagem apagada (retract) | idem |
| `handleMessagesMoved` | canal leve com lacuna preenchida | idem |
| correção (LMC) | publica de novo com o mesmo id | criaria uma segunda notificação ao lado da promovida: remover a promovida antes |
| `removeDeliveredNotificationsForContact` | conversa arquivada | já funciona (procura pelo `threadIdentifier`) |

A solução é um helper só: remover pelo identificador, como hoje, **e** procurar nas entregues pelo
`isaCloudNotificationId`. A busca nas entregues é assíncrona (`getDeliveredNotifications`). No app,
tudo bem. Na extensão, o comentário do `handleDisplayedMessages` pede para não mexer em notificações
depois do congelamento das filas. Lá a busca vai só antes do congelamento, e o que escapar é limpo
quando o app acorda ou abre. Na medição, a extensão não removeu nenhuma notificação por leitura
(0 de 46 execuções), então isso quase não acontece lá.

### 3. Prazo curto no `feed` (lição do C38)

Montar o conteúdo e consultar o estado da local usa a central de notificações e o banco. O C38
mostrou o `serviceExtensionTimeWillExpire` travado na fila do `UNUserNotificationCenter` ocupada. A
promoção precisa de um prazo próprio (por exemplo, 1 s): se não terminar, entrega o placeholder como
hoje. No `serviceExtensionTimeWillExpire` e no `disconnectAndFeedAllWaitingHandlers`, que já
rodam com pouco tempo, fica o placeholder direto, sem promoção.

## Riscos

| Risco | Efeito | Como contornar |
|---|---|---|
| Promover uma mensagem lida entre a consulta e a entrega | Notificação de mensagem já lida, até o app limpar | Janela de milissegundos; a limpeza pelo `userInfo` no app resolve |
| Som duplicado | Toca de novo ao promover | Promovida de local já entregue vai sem som e passiva |
| Anexo (foto ou áudio) | Imagem ausente na promovida | Montar de novo do cache; sem o arquivo, promove sem anexo |
| Ordem na Central de Notificações | A promovida pode subir para o topo da conversa | Mesmo `threadIdentifier`; aceitável |
| App antigo com fpush novo | Placeholders acumulam | Publicar o app antes de trocar o fpush |
| Push filtering aprovado no futuro | A promoção continua útil: com a entitlement, o handler pode receber conteúdo vazio, mas a promoção também elimina a local duplicada | Manter atrás do `ISACLOUD_HAS_PUSH_FILTERING` e decidir depois |

## Como validar

Repetir a medição de 27/11 (log longo do iPhone, mesma janela de ~6 h) contando, por execução:
promovidas, placeholders entregues, e placeholders que ainda estavam na Central de Notificações
quando o app abriu. O esperado é cair de 48 de 53 pushes com vazia para algo perto dos 5 sem
conteúdo. Na prática: depois de algumas mensagens 1:1 com o app fechado, não deve haver nenhuma
notificação "isaCloud" vazia ao lado delas.

## Passos

1. App: separar a montagem do conteúdo da publicação no `MLNotificationManager` e guardar, na
   extensão, as mensagens publicadas na execução.
2. App: promoção no `PushHandler feed` com prazo; o helper de remoção pelo `userInfo` nos quatro
   pontos da tabela.
3. Build no TestFlight e, logo em seguida, o fpush v4 sem `collapse-id`. A janela entre os dois deve
   ser curta nos dois sentidos: app novo com fpush antigo faz o push seguinte apagar a mensagem
   promovida anterior; fpush novo com app antigo acumula placeholders até o app abrir.
4. Nova medição.

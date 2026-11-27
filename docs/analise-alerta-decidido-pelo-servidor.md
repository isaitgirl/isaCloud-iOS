# Análise: o servidor decidir quando o push vira alerta

**Data:** 27/11/2026
**Estado:** análise, nada implementado
**Objetivo:** menos notificações vazias (o placeholder "isaCloud" que só some ao abrir o app) e menos
"Pode haver mensagens novas"/"New Message?", sem a entitlement de push filtering (pedido LZ8H53L72D
ainda pendente).

## Resultado da medição (27/11/2026): a vazia não é problema do servidor

Janela de ~6 h (08:54 às 14:46) no iPhone de produção (build 135), mais 24 h de log do
`cloud_notify_quiet` no srv-01:

- **Servidor (todos os usuários, 24 h):** 281 alertas, sendo 275 de conversa 1:1 (`important`), só
  4 de menção em sala e 2 de chamada. A v3 já segura as salas: o que sobra como alerta é quase só 1:1.
- **iPhone:** 53 execuções da extensão. **Em 48 (91%) ela publicou pelo menos uma notificação de
  verdade.** Só 5 não tinham nada a mostrar.
- Em **toda** execução, a extensão entrega o placeholder ao `contentHandler` (`PushHandler feed`,
  `NotificationService.m:66`), e a notificação de verdade sai à parte, com identificador próprio,
  pelo `MLNotificationManager`. O push seguinte apaga o placeholder anterior, mas entrega um novo; com
  o `apns-collapse-id` do fpush, fica sempre um. Ele só some de vez quando o app abre ou acorda (9
  das 52 limpezas). Entre um push e outro, o placeholder ficou de 1 a 96 min (mediana de 2 min), e
  sempre havia um novo no lugar.

Ou seja: a notificação vazia ao lado de uma mensagem 1:1 é **o placeholder do próprio alerta certo**,
não um alerta a mais. O servidor decidir melhor mudaria no máximo as 5 execuções sem conteúdo. O que
resolve as outras 48 é a extensão **entregar a própria mensagem no `contentHandler`** em vez do
placeholder, e deixar de publicar essa mesma mensagem como notificação local separada (a opção A da
conversa de 27/11, a mesma coisa que o Fluux faz). As propostas abaixo continuam valendo para os
casos restantes, mas passam a ser secundárias.

## Por que o servidor

Sem o filtering, **todo push de alerta vira alguma notificação visível**: ou a mensagem de verdade,
ou o placeholder passivo, quando a extensão decide que não há nada para mostrar, ou o texto do fpush,
quando a extensão morre. A extensão não consegue desistir de um alerta. Então a única forma de não
ter a notificação vazia é **o alerta nem sair** quando o app não vai notificar. O push silencioso
(`background`) nunca aparece.

Bônus: cada alerta a menos é uma execução da extensão a menos, e portanto uma chance a menos de ela
morrer (check-in timeout, `0xdead10cc`, `_exit` com push pendente).

## O que já existe

| Peça | Onde | O que faz |
|---|---|---|
| `mod_cloud_notify_quiet` v3 (23/11) | `isacloud-custom-plugins/share/lua/5.4/` | Classifica cada push em `alert`, `background` ou `drop`: carbons próprios, leitura, retração, reação, correção e sinal de chamada viram silenciosos; sala (local ou remota) só alerta com menção, resposta ou conteúdo cifrado; no máximo 1 silencioso a cada 2 min por aparelho |
| fpush com `0001-silent-unimportant-pushes.v3.patch` | `fpush/` | Sem `last-message-body` → push `background`. Alerta com `apns-collapse-id` fixo (`isacloud-sync`), texto passivo "isaCloud / Pode haver mensagens novas" e a mesma marca do placeholder do app, para a limpeza do app apagar também |
| Placeholder passivo | `HelperTools.m` (`isaCloudPushPlaceholderContent`) | O que a extensão entrega quando não há nada a notificar |

Ou seja, o "servidor decide" já está meio caminho andado, e duas das ideias anteriores (o
`collapse-id` e o texto que não parece erro) já estão feitas. O `Dockerfile` do fpush aplica a v3
desde 23/11; vale conferir se a imagem que roda no servidor já foi refeita com ela. O que falta é o servidor conhecer **as
mesmas regras que o app usa para não notificar**.

## Onde o servidor e o app discordam

O app deixa de notificar em `MLNotificationManager.m` (`internalMessageHandlerWithMessage`). Cada
regra que o servidor não conhece é um alerta que vira notificação vazia:

| Regra do app | O servidor sabe? | Resultado hoje |
|---|---|---|
| Conversa **arquivada** (mudo total, inclusive menções) | Não: o nó PEP `im.isacloud:conversation-state:0` foi decidido, mas não implementado | Alerta → vazia |
| Contato **silenciado** (1:1) | Não: o mudo de 1:1 não sai do aparelho | Alerta → vazia |
| Sala com nível próprio (`always` / `on-mention` / `never`) | **Poderia:** o app já publica isso no bookmark (`urn:xmpp:notification-settings:0`, `MLPubSubProcessor.m:480`), e o quiet já lê os bookmarks para achar o apelido | O quiet usa a política geral (`mentions`) e ignora o nível da sala: sala em `never` com menção → vazia; sala em `always` sem menção → **o app não é acordado com alerta** (silencioso, com limite de 2 min) |
| Menção pelo **apelido, nome de exibição, parte local ou JID** | Só o apelido | Menção pelo nome de exibição ou pela parte local → o servidor manda silencioso e a notificação **pode atrasar ou se perder** |
| Mais de 5 apelidos no texto = menção em massa, ignorada | Não | Alerta → vazia |
| Mensagem cifrada em sala (OMEMO em grupo) | Não lê o conteúdo | Sempre alerta → vazia quando não era menção |
| Já notificada ou já lida (rajada, push guardado pela APNs por até 24 h) | Em parte (MDS fica no servidor) | Alerta tardio → vazia |

Repare que a discordância vai **para os dois lados**. Alerta a mais vira vazia (feio). Silencioso
quando o app ia notificar vira **notificação perdida ou atrasada** (pior). Qualquer regra nova no
servidor tem que respeitar o "na dúvida, alerta" que o quiet já segue.

## Propostas, em ordem

### 0. Medir antes de mexer

O `cloud_notify_quiet_log = true` está ligado, então o servidor registra uma linha por push com o
motivo. Do lado do app, o log longo já mostra o motivo de cada "not showing notification: ...".
Cruzando os dois numa janela de um dia (como a linha de base do build 126: 114 execuções da
extensão, só 2 viraram notificação), dá para saber **quais regras da tabela geram as vazias que
restaram depois da v3**, e começar pela maior.

### 1. Nível por sala do bookmark (só servidor, pequeno)

No quiet, para cada sala, ler `<notify xmlns='urn:xmpp:notification-settings:0'>` do bookmark (o
mesmo `get_items` que já busca o `<nick>`):

| Nível no bookmark | Ação |
|---|---|
| `never` | `background` (ou `drop`), mesmo com menção |
| `on-mention` | regra de menção atual |
| `always` | `alert` para toda mensagem com corpo |
| sem nível | política geral (hoje `mentions`) |

Cuidados:
- O cache de bookmark do quiet dura 10 min. Uma mudança no app levaria até 10 min para valer.
  Invalidar a entrada no evento de publicação do PEP (`item-published` no nó de bookmarks) resolve.
- O Android (Conversations) também escreve esse nó? Conferir. Se ele republicar o bookmark sem a
  extensão, o nível some.

### 2. Arquivado e mudo de 1:1 (depende do app)

O nó `im.isacloud:conversation-state:0` (ver `docs/decisoes-sincronizacao-arquivados.md`) resolve o
arquivado. O quiet leria o item do remetente e mandaria `background` em conversa arquivada. Isso
transforma o PR 2 dos arquivados também numa correção de notificação.

O mudo de 1:1 hoje está fora do escopo daquele documento ("Sincronizar silenciado" é não objetivo).
Incluir um campo `muted` no mesmo item é a extensão natural. **Decisão sua**, porque o Android
precisaria acompanhar.

### 3. Mesmos nomes de menção que o app (só servidor)

Além do apelido da sala, o quiet passa a aceitar como menção a **parte local** e o **JID** da conta
(o servidor já tem os dois) e o **nome de exibição** (o apelido do PEP XEP-0172, que o servidor
consegue ler). Isso fecha a direção perigosa: menção que o app notificaria e que o servidor mandava
como silenciosa.

A regra de "mais de 5 apelidos = em massa" também pode ir para o servidor, porque ele tem a lista de
ocupantes das salas locais. Nas salas remotas não tem, então lá continua como hoje.

### 4. Grupo com OMEMO (depende de decisão de privacidade)

O servidor não lê a mensagem cifrada, então hoje sempre alerta. Saídas:
- **a menção ir fora da criptografia** (referência XEP-0372 ou a XEP-0513, ver
  `docs/analise-mencoes-ios.md`). O servidor fica sabendo quem foi mencionado, não o texto. Isso exige
  que o Android e o iOS mandem a referência;
- **aceitar** o alerta em grupos cifrados (quantos são? a medição do passo 0 responde).

### 5. Push guardado pela APNs (ajuste fino)

O alerta tem validade de 24 h (`ISACLOUD_ALERT_TTL_SECS`) e, pelo `collapse-id`, só o último fica
guardado. Se o aparelho volta depois de a mensagem ter sido lida em outro lugar, a extensão não tem
nada novo e sobra a vazia. Encurtar a validade reduz isso, mas perde o aviso de quem ficou com o
celular desligado. Eu deixaria como está até a medição mostrar que isso pesa.

## O que não muda

- A vazia **não chega a zero** sem o filtering. Sempre haverá um alerta que o servidor achou que ia
  notificar e o app não (por exemplo, mensagem já lida em outro aparelho no meio do caminho). Com o
  `collapse-id`, fica no máximo uma de cada vez.
- O "New Message?" (a extensão morrendo) fica mais raro porque ela roda menos vezes, mas a causa
  continua sendo tratada no app (`docs/analises-crashes.md`, C29/C36/C38).

## Próximos passos sugeridos

1. Uma janela de medição de 24 h (log do quiet mais o log longo do app) para classificar as vazias
   que sobram.
2. Passo 1 (nível por sala) e passo 3 (nomes de menção) no quiet: só servidor, juntos numa v4.
3. Passo 2 junto do PR 2 dos arquivados.
4. Passo 4 junto da decisão das menções (XEP-0513).

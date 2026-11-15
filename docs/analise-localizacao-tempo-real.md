# Análise: localização em tempo real (iOS)

Data: 13/11/2026 (Prosody conferido no mesmo dia). Só análise: nada implementado.
Documento irmão no Android: `isaCloudMessenger/docs/analise-localizacao-tempo-real.md` (o contrato XMPP é o mesmo nos dois).

## Resumo

- **Hoje** o iOS só envia localização **estática**: o item "Localização" do clipe abre um mapa (`LocationPickerView.swift`) e envia um corpo `geo:lat,lon` (`ChatLocation.swift`, `ChatView.sendLocation`). Quem recebe vê o mapa (`kMessageTypeGeo`).
- **O caminho de menor risco** é: a mensagem inicial continua sendo um `geo:` normal (quem não tem o recurso vê um ponto fixo) e as **atualizações vão em mensagens sem corpo, do tipo `headline`**, com um elemento próprio do isaCloud. Mensagens sem corpo não aparecem nos outros clientes, não geram push e não precisam ser guardadas no arquivo do servidor.
- **Não dá para usar correção (XEP-0308)** para as atualizações: o Monal e o Conversations **recusam** correção de mensagem de localização (ver "Opções descartadas"). Cada atualização viraria uma nova mensagem de mapa na conversa de quem não tem isaCloud.
- **A parte difícil no iOS é o envio com o app em segundo plano**: precisa do modo de fundo `location` e, principalmente, de impedir que o Monal **desconecte as contas** quando o app vai para o fundo. Já existe precedente: as chamadas em andamento seguram a conexão do mesmo jeito.
- **Receber** é a parte simples: uma tabela pequena com a última posição por sessão, e a bolha e a tela cheia ao vivo **já existem no fork do ExyteChat**, só falta ligar.
- **Onde se vê:** dentro do isaCloud (bolha e tela cheia com MapKit). O Apple Maps só abre um ponto fixo. Outros clientes (Conversations, Monocles, Monal) veem só o ponto inicial.
- **Recomendação de escopo da primeira versão:** só conversas 1:1, durações fixas (15 min, 1 h, 8 h), atualizações sem criptografia OMEMO com aviso (o mesmo "enviar sem criptografia" que a localização estática já usa). Grupos e criptografia ficam para depois.

## O que existe hoje

| Peça | Onde | O que faz |
|---|---|---|
| Escolher o lugar | `Monal/Classes/LocationPickerView.swift` | Mapa SwiftUI, pino no centro, pede permissão "Durante o uso" |
| Montar o texto | `Monal/Classes/ChatLocation.swift` | `geo:lat,lon` |
| Enviar | `ChatView.sendLocation` | Envia como texto; pergunta antes de enviar sem criptografia (`askToSendWithoutEncryption`) |
| Classificar ao receber | `MLMessageProcessor.m` (corpo sem espaço que começa com `geo:`) | Vira `kMessageTypeGeo` |
| Mostrar | `ChatView` (`staticLocation`), `MLChatMapsCell`, `MLContactCell`, `MLNotificationManager` | Mapa na bolha, rótulo na lista e na notificação |
| Permissões | `Monal-Info.plist` | `NSLocationWhenInUseUsageDescription`; modos de fundo: `audio`, `fetch`, `processing`, `remote-notification`, `voip` (sem `location`) |
| Alvo mínimo | projeto | iOS 17.0 — permite `CLLocationUpdate.liveUpdates` e `CLBackgroundActivitySession` |

## O protocolo (comum ao iOS e ao Android)

Não existe XEP adotada para localização ao vivo dentro de conversa. O XEP-0080 (User Location) publica a posição por PEP para **todos os contatos**, não por conversa, e nenhum dos dois apps o implementa — por isso não serve. A proposta usa o formato de dados do XEP-0080 (`<geoloc>`) dentro de um elemento próprio do isaCloud.

Namespace: `urn:isacloud:live-location:0`.

**Início** (mensagem normal, com corpo; aparece como ponto fixo nos outros clientes):

```xml
<message to='contato@isacloud.im' type='chat' id='A1'>
  <body>geo:-23.5505,-46.6333;u=12</body>
  <live-location xmlns='urn:isacloud:live-location:0' state='start'
                 until='2026-11-13T19:00:00Z'/>
  <origin-id xmlns='urn:xmpp:sid:0' id='A1'/>
</message>
```

A sessão é identificada pelo `origin-id` (ou `id`) da mensagem inicial.

**Atualização** (sem corpo e do tipo `headline`; os outros clientes ignoram):

```xml
<message to='contato@isacloud.im' type='headline' id='A7'>
  <live-location xmlns='urn:isacloud:live-location:0' state='update' session='A1'>
    <geoloc xmlns='http://jabber.org/protocol/geoloc'>
      <lat>-23.5512</lat><lon>-46.6340</lon>
      <accuracy>9</accuracy>
      <timestamp>2026-11-13T18:12:30Z</timestamp>
    </geoloc>
  </live-location>
  <no-permanent-store xmlns='urn:xmpp:hints'/>
</message>
```

**Fim** (sem corpo, mas guardado no arquivo, para quem abrir depois saber que acabou):

```xml
<message to='contato@isacloud.im' type='chat' id='A9'>
  <live-location xmlns='urn:isacloud:live-location:0' state='stop' session='A1'/>
  <store xmlns='urn:xmpp:hints'/>
</message>
```

Regras de quem recebe:

1. Atualização ou fim só valem se vierem do **mesmo JID** (1:1) ou do **mesmo `occupant-id`** (grupo) que mandou o início.
2. Depois de `until`, a sessão é dada como encerrada mesmo sem o `stop` (o `stop` pode se perder).
3. Sessão desconhecida (atualização chegou antes do início, ou o início é de antes da instalação) é ignorada.
4. Guarda-se **só a última posição** da sessão, não o trajeto.
5. Atualização com `timestamp` mais velho que a última guardada é descartada (chegada fora de ordem).

Ritmo de envio recomendado: uma atualização quando a pessoa andar mais de ~25 m, no máximo uma a cada 10 s; e um "sinal de vida" a cada 2 min parada, para o cartão mostrar "atualizada há X". Em 1 h isso dá, no pior caso, algumas centenas de mensagens pequenas — sem push e sem arquivo.

Por que sem corpo resolve: os outros clientes não mostram mensagens sem corpo, e o servidor não guarda nem pusha (detalhes abaixo).

### Conferido no Prosody (13/11/2026)

Lido em `~/projects/lua/prosody-trunk` e no módulo próprio `mod_cloud_notify_quiet` (v2, o que está em produção):

| O quê | Onde | Resultado para a atualização (`headline`, sem corpo) |
|---|---|---|
| Arquivo 1:1 | `mod_mam`, `should_store` | `headline` nunca é guardado. As dicas do XEP-0334 também são respeitadas: `no-store`/`no-permanent-store` impedem e `store` força. Corpo, recibo (`urn:xmpp:receipts`) e marcador (`chat-markers`) fazem guardar — **a atualização não pode pedir recibo nem levar marcador**. |
| Arquivo de grupo | `muc/history.lib.lua`, `muc-message-is-historic` | Respeita `no-permanent-store`; sem corpo não guarda. |
| Push (cloud_notify) | `mod_cloud_notify`, `is_important` | Sem corpo e sem OMEMO = "não importante". **Mas o push ainda sai** (silencioso) quando a sessão está hibernada ou a pessoa está totalmente offline. |
| Push (isaCloud) | `mod_cloud_notify_quiet` | Uma `headline` cai no motivo `headline` → **drop**: nenhum push para o app iOS. Uma `chat` sem corpo cairia em `empty` → também drop. |
| Destinatário sem nenhuma sessão | `mod_message` | `headline` é **descartada** se ninguém estiver online. Uma `chat` sem corpo iria para `message/offline/handle`: dispararia push (no appserver que não passa pelo filtro) e, com o `mod_offline` ligado, **cada atualização ficaria guardada** e chegaria em rajada no próximo login. |
| Cópia para os outros aparelhos (carbons) | `mod_carbons`, `should_copy` | `headline` não é copiada; `chat` seria. Para a atualização, não copiar é o desejado. |

**Conclusão:** por isso a atualização vai como `type='headline'` e não `chat`. É o tipo que o servidor já trata como efêmero em todos os pontos: não guarda, não acumula offline, não copia e o filtro do isaCloud não pusha. As mensagens de início (`chat`, com corpo) e de fim (`chat`, com `<store/>`) seguem o caminho normal.

Duas ressalvas:

- **Grupos (fase 5):** em grupo a mensagem tem de ser `groupchat`. O `mod_cloud_notify_quiet` classifica `groupchat` sem menção como `muc-quiet` → push **silencioso** para cada atualização. Antes de liberar em grupo, acrescentar ao módulo um motivo `live-location` → `drop` (olhar o elemento `urn:isacloud:live-location:0`).
- O filtro só vale para o appserver do iOS (`push.isacloud.im`). Outros appservers (o do Android, se houver) recebem o push silencioso do `cloud_notify` quando a sessão está hibernada. Com `headline` isso só acontece com a sessão hibernada, nunca offline.

### Criptografia

O OMEMO que o Monal e o Conversations usam (0.3) só criptografa o **corpo**. Uma atualização sem corpo não pode ir criptografada sem passar a aparecer como mensagem nos outros clientes. Opções:

- **(recomendada para a primeira versão)** Atualizações em texto claro, só com TLS até o servidor próprio. Se a conversa estiver com OMEMO, perguntar antes de começar, como a localização estática já faz (`askToSendWithoutEncryption`). A mensagem de início pode continuar criptografada.
- **(depois)** Com OMEMO 2 e SCE (XEP-0420), qualquer elemento pode ir criptografado. Ver `docs/analise-omemo2.md`. Quando o OMEMO 2 existir nos dois apps, a atualização passa a ir dentro do envelope criptografado sem mudar o resto do contrato.

## Onde a pessoa vê o contato se movendo (iOS)

**Dentro do isaCloud, não no app Mapas.** O Apple Maps só recebe um ponto fixo de outro app (`MKMapItem.openMaps`, como o botão atual faz); não há como um app de terceiros mandar posições contínuas para ele. O mapa ao vivo é uma tela do próprio isaCloud desenhada com o MapKit — os mesmos mapas da Apple, mas dentro do app.

- **Na conversa:** a bolha da mensagem de início vira um mapa pequeno com o pino se movendo, selo "Ao vivo", "atualizada há 20 s" e o tempo restante.
- **Tocando na bolha:** tela cheia (`FullscreenLocationView` do ExyteChat) com o pino seguindo a pessoa, a barra de status ao vivo e, para quem está enviando, o botão **Parar de compartilhar**.
- **"Abrir no Mapas":** o botão que já existe continua lá e abre o Apple Maps **na última posição recebida** (útil para traçar rota até a pessoa). Ali o ponto não se move.

## Outros clientes (Conversations, Monocles, Monal, Gajim, Dino…)

**Só isaCloud ↔ isaCloud vê o contato se movendo.** O elemento `urn:isacloud:live-location:0` é do isaCloud; nenhum outro cliente o conhece, e não existe XEP adotada para localização ao vivo que eles implementem.

O que cada lado vê:

| Quem envia → quem recebe | O que aparece |
|---|---|
| isaCloud → isaCloud (iOS ou Android) | Bolha ao vivo, o pino anda, "até 19:00", "Parar" |
| isaCloud → Conversations, Monocles, Monal, Cheogram, Gajim, Dino | **Uma localização fixa**: o ponto de onde a pessoa estava ao começar. As atualizações (sem corpo) e o fim são ignorados em silêncio — nada de mensagens repetidas, nada de lixo na conversa |
| Outro cliente → isaCloud | Nada muda: esses clientes só mandam `geo:` fixo |

Limitações dessa degradação:

- Quem usa outro cliente **não fica sabendo** que era ao vivo, nem quando acabou. O corpo precisa ser só `geo:` (o Monal exige corpo sem espaços e o Conversations lê o corpo inteiro como URI) para virar mapa; um texto junto viraria só texto.
- Se for importante avisar, há uma opção barata: no fim, mandar uma mensagem de texto normal "📍 Localização em tempo real encerrada" **só quando o contato não anunciar suporte** (disco do XEP-0115 com o namespace `urn:isacloud:live-location:0`). Fica como decisão; não é necessário para a primeira versão.
- Mandar um `geo:` novo de tempos em tempos para esses clientes ("modo compatível") é possível, mas enche a conversa e notifica a cada envio. Não recomendado.

Para os apps isaCloud se reconhecerem, os dois anunciam o namespace no disco (XEP-0030/0115). Isso permite, no futuro, esconder a opção "em tempo real" ou avisar "este contato verá só o ponto inicial" quando o outro lado não for isaCloud.

## O que precisa no iOS

### 1. Envio com o app aberto e em segundo plano (a parte de maior risco)

**Permissão e modo de fundo**

- Acrescentar `location` em `UIBackgroundModes` (`Monal-Info.plist` e `Monal.Alpha-Info.plist`).
- Continuar só com "Durante o uso". No iOS 17+, uma `CLBackgroundActivitySession` criada com o app aberto mantém as atualizações chegando em segundo plano, com a pílula azul na barra de status. **Não precisa pedir "Sempre"**, o que evita o segundo pedido de permissão e a revisão mais rígida da Apple.
- Usar `CLLocationUpdate.liveUpdates()` (Swift concurrency), com filtro de distância feito no app.
- Revisar o texto de `NSLocationWhenInUseUsageDescription` para citar o compartilhamento ao vivo, com tradução pt-BR no override do isaCloud.
- A revisão da Apple (TestFlight externo e App Store) olha o modo de fundo `location`: a descrição precisa explicar o recurso. O TestFlight interno não passa por essa revisão.

**Manter a conexão XMPP viva**

Hoje o `MonalAppDelegate` desconecta todas as contas quando o app está no fundo e "ocioso" (`checkIfBackgroundTaskIsStillNeeded` e os blocos que chamam `disconnectAll`). Com o modo de fundo `location` o processo continua rodando, mas sem conexão as atualizações não saem.

- Já existe o precedente certo: `_voipProcessor.pendingCallsCount > 0` impede a desconexão durante uma chamada. Acrescentar uma condição igual — "há compartilhamento ao vivo ativo" — nos mesmos pontos (o teste de ociosidade e os três lugares que olham `pendingCallsCount` antes de desligar).
- A extensão de notificação já confere `MLProcessLock checkRemoteRunning:@"MainApp"` e deixa o app principal cuidar quando ele está rodando. Com o app vivo no fundo, isso é o comportamento desejado, mas **precisa ser testado**: é o mesmo terreno das notificações fantasma e do 0xdead10cc.
- Quando o compartilhamento acabar com o app no fundo, chamar o caminho normal de ociosidade para o app desconectar e congelar como hoje. Esquecer isso deixa o app acordado gastando bateria, e voltar ao congelamento sem soltar o banco é exatamente o 0xdead10cc (ver `docs/analises-crashes.md`).
- Se o iOS matar o app (memória, usuária fechou pelo seletor), o envio para. O cartão de quem recebe mostra "atualizada há X" e expira em `until`. Na volta, o app vê a sessão ainda dentro do prazo e pergunta se continua ou envia o `stop`.

**Peça nova: `LiveLocationSharing` (Swift, um objeto único)**

- Guarda as sessões de envio ativas (conta, contato, id da sessão, `until`).
- Dona da `CLBackgroundActivitySession` e do laço de `liveUpdates`.
- Aplica o ritmo (25 m / 10 s / 2 min) e manda as mensagens pelo `xmpp` da conta (`MLXMLNode` com o elemento, como as outras extensões).
- Persiste as sessões ativas (tabela ou chave no `defaultsDB` — se for chave, **com padrão registrado antes de qualquer tela ler**, para não repetir o crash C18).
- Expõe "há sessão ativa" para o `MonalAppDelegate`.

### 2. Recebimento

- **`MLMessageProcessor.m`:** antes do tratamento de corpo, olhar `{urn:isacloud:live-location:0}live-location`. Para `start`, a mensagem segue o caminho normal (vira `kMessageTypeGeo`) e se registra a sessão ligada ao `message_history_id`. Para `update` e `stop`, atualizar a sessão e avisar a interface com uma notificação interna própria. Nada vai para `message_history`.
- **Banco:** migração nova em `DataLayerMigrations` com uma tabela `live_location` (conta, contato, sessão, id da mensagem inicial, lat, lon, precisão, hora da posição, `until`, estado, `occupant_id` para grupos). Uma linha por sessão, atualizada no lugar.
- **Conferir a regra de remetente** (JID ou `occupant-id`) no processador, do mesmo jeito que a correção e a retratação já fazem.
- **Sem notificação** para atualizações; o início notifica como hoje ("📍 Localização", talvez "📍 Localização em tempo real").

### 3. Interface

**O fork do ExyteChat já traz quase toda a interface de localização ao vivo** (veio do upstream; nunca foi ligada no isaCloud):

| Peça do ExyteChat | O que faz |
|---|---|
| `Model/LiveLocation.swift` | Modelo (lat, lon, `lastUpdateAt`, `startedAt`, `expiresAt`) e `LiveLocationDuration` (15 min, 1 h, 8 h) |
| `Message.liveLocation` (`@Published`) | Mudar esse campo redesenha a bolha — é por aqui que as atualizações recebidas movem o pino |
| `MessageView.liveLocationView` | Bolha ao vivo |
| `Views/Location/LocationPickerView.swift` | Seletor com as durações |
| `Views/Location/FullscreenLocationView.swift` | Tela cheia ao vivo, barra de status, "Parar", "Abrir no Mapas" |
| `LiveLocationStatusText`, textos em `ChatLocalization` | "atualizada agora", "há N min" |
| `LiveLocationBroadcaster` + `onLiveLocationBroadcast` | Motor de envio — **não serve como está** (ver abaixo) |

O que não serve: o `LiveLocationBroadcaster` vive no `ChatViewModel` (morre ao sair da conversa) e só roda em segundo plano com permissão "Sempre". O envio fica com o `LiveLocationSharing` do app (seção 1); a interface do ExyteChat só **mostra** e dispara início/parada. Isso pede uma mudança pequena no fork (deixar o app fornecer o estado de envio em vez do broadcaster interno), pelo fluxo de PR do fork.

O isaCloud hoje usa o `LocationPickerView` próprio (`Monal/Classes`) no clipe. Duas opções: acrescentar a opção "em tempo real" ao picker próprio, ou trocar pelo do ExyteChat. A primeira mexe menos.

- **Clipe → Localização:** o mapa atual ganha duas opções: "Enviar esta localização" (como hoje) e "Compartilhar em tempo real" com escolha de duração (15 min, 1 h, 8 h).
- **Bolha ao vivo:** o mesmo mapa da `kMessageTypeGeo`, com selo "Ao vivo", "até 19:00" e "atualizada há 20 s"; o pino anda quando chega atualização. Encerrada, vira "Localização em tempo real encerrada" com a última posição.
- **Na conversa de quem envia:** faixa no topo "Compartilhando localização · Parar".
- **Mapa em tela cheia:** ao tocar, o mapa segue o pino.
- **Lista de conversas e notificação:** rótulo próprio.
- Todo texto novo com tradução pt-BR no override do isaCloud.

### 4. Testes

- Unitários: montagem e leitura das três mensagens; regras de remetente, de `until` e de ordem; ritmo de envio (com relógio e posições falsas).
- Simulador: o Xcode simula rotas (Features → Location → City Run) — dá para ver o envio e a recepção entre dois simuladores com contas diferentes. **Pelos créditos, a validação real fica no iPhone (.dev)**, como combinado.
- iPhone real, obrigatório: app no fundo por 30 min compartilhando; tela bloqueada; app morto pelo sistema; extensão de notificação recebendo push enquanto o app está vivo no fundo; consumo de bateria.

## Opções descartadas

| Opção | Por que não |
|---|---|
| **Corrigir a mensagem `geo:` a cada atualização (XEP-0308)** | O Monal só aceita correção de mensagem do tipo texto (`checkLMCEligible` exige `kMessageTypeText`) e o Conversations recusa correção de `geo:` (`acceptMessageCorrection` exclui `isGeoUri`). Nos clientes sem isaCloud, cada atualização viraria uma nova mensagem de mapa. Além disso, toda correção com corpo gera push e fica no arquivo. |
| **XEP-0080 por PEP** | Publica para todos os contatos com assinatura de presença, não para uma conversa. Restringir por lista de permitidos é complexo e frágil, e não funciona em grupo. |
| **Mensagens `geo:` novas a cada atualização** | Enche a conversa de todo mundo e gera push a cada passo. |
| **Servidor de localização próprio (HTTP/WebSocket)** | Infraestrutura nova, autenticação nova, fora do XMPP. Muito mais risco e trabalho. |

## Fases sugeridas

1. **Contrato** fechado nos dois apps (este documento e o do Android; pode virar um `contrato-localizacao-tempo-real.md` como o do reply).
2. **Recebimento** no iOS e no Android (risco baixo; dá para testar mandando as stanzas à mão pelo console do Gajim/Prosody).
3. **Envio com o app aberto** (sem segundo plano): mostra o fluxo inteiro sem mexer no ciclo de vida do app.
4. **Envio em segundo plano** (modo `location` + segurar a conexão): a etapa de maior risco, isolada num build próprio para medir crash e bateria.
5. **Grupos** (`occupant-id`) e, quando houver OMEMO 2, criptografia das atualizações.

## Riscos e pontos a conferir

| Risco | Tamanho | Mitigação |
|---|---|---|
| Conexão segurada no fundo reabre o terreno do 0xdead10cc e das notificações fantasma | Alto | Etapa isolada; usar o mesmo caminho das chamadas; testar o fim da sessão no fundo |
| Bateria (GPS + socket aberto) | Médio | Filtro de distância, precisão "melhor para navegação" só quando em movimento, duração máxima de 8 h |
| Revisão da Apple pelo modo de fundo `location` | Médio | Texto de permissão claro; recurso visível e iniciado pela pessoa |
| Atualizações sem OMEMO | Médio (privacidade) | Aviso antes de começar; servidor próprio com TLS; OMEMO 2 depois |
| Push silencioso por atualização em grupo | Baixo (só na fase de grupos) | Motivo `live-location` → `drop` no `mod_cloud_notify_quiet` antes de liberar grupos |
| Monal upstream mudar o processador de mensagens | Baixo | Mudança pequena e marcada com `isaCloud:` |

## Esforço estimado (ordem de grandeza)

| Parte | Esforço |
|---|---|
| Recebimento + tabela + ligar a bolha e a tela cheia do ExyteChat | pequeno-médio (1–2 dias) |
| Envio com o app aberto | pequeno-médio (1–2 dias) |
| Envio em segundo plano (conexão, ciclo de vida, testes no iPhone) | médio-grande (3–5 dias, a maior parte teste) |
| Grupos | pequeno (1 dia) |

# Avaliação: criar canal público e ferramentas de moderação (31/10/2026)

Pedido da Isadora: avaliar complexidade e risco de **criar canal** (mostrando opções como o Conversations; o canal já nasce público, não "só para membros"), além da criação de grupo que já existe, e de **moderação (XEP-0425)**, **identificação de ocupantes (XEP-0421)** e **MAM (XEP-0313)**, seguindo o que o Conversations oferece hoje para canais e moderação. **Nada disto foi implementado**: é só o levantamento, para decidirmos depois.

Referências lidas: Monal/isaCloud (`MLMucProcessor.m`, `MLMessageProcessor.m`, `xmpp.m`, `MLIQProcessor.m`, `CreateGroupMenu.swift`, `ChatView.swift`, `MemberList.swift`, `ChannelMemberList.swift`, `PublicChannelsView.swift`) e Conversations 2.21.0 (`CreatePublicChannelDialog`, `MultiUserChatManager`, `ModerationManager`, `MucOptions`, menus de usuário e de detalhes da sala).

## O que o app já tem

| Item | Estado hoje |
|---|---|
| **XEP-0421 (occupant-id)** | Pronto. Lê o id da presença e da mensagem, guarda o id próprio da sala (`getOwnOccupantIdForMuc`) e decide a direção da mensagem por ele (`MLMessageProcessor.m:341-406`). Sem o id, edição, retração e reação ficam bloqueadas. |
| **XEP-0425 (moderar)** | Pronto no básico. `moderateMessage:` envia o IQ `urn:xmpp:message-moderate:1` (`xmpp.m`), a retração moderada recebida apaga a mensagem (`MLMessageProcessor.m`, ~linha 520) e o menu "Moderar" aparece para moderador quando a sala anuncia o recurso. A tela pede o motivo e tem "Bloquear este usuário" (banimento por JID). |
| **XEP-0313 (MAM) em sala** | Pronto. Catchup com `urn:xmpp:mam:2`, paginação e a janela de 7 dias dos canais públicos (`MLMucProcessor.m`). |
| **Permissões** | `MemberList` e `ChannelMemberList` trocam dono, admin, membro e banido; hats (XEP-0317) aparecem. |
| **Criar grupo** | `CreateGroupMenu.swift` e `MLMucProcessor createGroup:` (sala privada, só membros, OMEMO). |
| **Descobrir canais** | `PublicChannelsView` lista as salas públicas dos serviços MUC do servidor (`disco#items`). |

## O que o Conversations oferece para canais

- **Criar canal** (`CreatePublicChannelDialog`): conta, nome e endereço. O endereço é sugerido a partir do nome, sem `" & ' / : < > @`. Não há mais opções na criação.
- **Configuração do canal** (`defaultChannelConfiguration`): persistente, não só para membros, pública, `whois = moderators`, assunto só para admin, MAM ligado. Manda as chaves de Prosody (`muc#roomconfig_enablearchiving`) e de ejabberd (`mam`, `muc#roomconfig_mam`) juntas.
- **Moderação** (`ModerationManager`): apaga a mensagem; apaga também os stanza-ids antigos se ela foi editada; apaga o arquivo local associado. Há um aviso explicando a moderação, que pode ser dispensado por 5 minutos.
- **Selo de conformidade** (`MucOptions.isCompliant`): canal público precisa de occupant-id, MAM e moderação (`urn:xmpp:message-moderate:1`, o mesmo namespace do Monal).
- **Menu no usuário**: dar ou tirar membro, admin e dono; remover da sala.

## Avaliação por frente

### 1. Criar canal público: complexidade média (2 a 3 dias), risco médio

- **Tela nova**: `CreateChannelMenu.swift` com conta, nome e endereço sugerido, mais uma entrada no popover "+". Já existe o serviço MUC de cada servidor nosso (`_ownMucComponents`).
- **Configuração da sala**: hoje o status 201 sempre aplica a configuração de grupo (`MLMucProcessor.m`, `configureMuc:` com `_mandatoryGroupConfigOptions`, `membersonly=1`). É preciso guardar o tipo que está sendo criado e aplicar a configuração de canal (`membersonly=0`, `publicroom=1`, `whois=moderators`, `changesubject=0`, persistente, MAM ligado). A mecânica de "campo opcional" que o Monal já tem serve para as diferenças entre Prosody e ejabberd.
- **Risco principal: endereço que já existe.** O endereço legível pode colidir com um canal alheio. Hoje a sala entraria na lista antes de sabermos se foi criada ou só acessada (o 201 é ignorado com erro no log, mas o `initMuc` já aconteceu). Solução: consultar `disco#info` do endereço antes (`item-not-found` = livre) e bloquear a criação se já existir.
- **Decisões de produto** (respostas da Isadora em 31/10/2026):
  - **Listar na descoberta de canais: sim, com interruptor** (`muc#roomconfig_publicroom`). Ligado, o canal aparece em "Canais públicos" para todo o servidor; desligado, só entra quem souber o endereço.
  - **Notificação do criador: em aberto.** O app põe todo canal novo em "só menção" na primeira entrada (`MLMucProcessor.m`); no canal que a própria pessoa criou isso provavelmente não é o desejado (a proposta era deixar em "tudo" só para quem criou).
- **Merge com o Monal**: baixo, se a tela ficar em arquivo Swift novo e a mudança no `MLMucProcessor.m` (ponto quente de merge) for pequena e aditiva.

### 2. XEP-0421: pouco trabalho (meio dia), risco baixo

- Falta só o pré-requisito: antes de criar o canal, checar se a sala anuncia `urn:xmpp:occupant-id:0` e avisar se não anunciar. Sem isso o dono não conseguiria editar nem retratar as próprias mensagens.
- Com `whois=moderators`, o moderador vê o JID real de quem escreve, e é isso que o "Bloquear" usa; os demais só veem o occupant-id.

### 3. XEP-0425: complexidade baixa a média (1 a 2 dias), risco baixo

O básico já funciona. Buracos em relação ao Conversations:

- **Apagar também os stanza-ids antigos de mensagem editada**: se a mensagem foi corrigida, a versão original pode continuar no MAM. Conferir se o Monal guarda esses ids; se não guardar, é migração de banco (escada `+migrateISACloudDB:`, nunca na do Monal) e precisa ser validada com banco real.
- **Apagar o arquivo local** quando a mensagem moderada tinha mídia (conferir se já acontece).
- **Remover da sala (kick)**: o Monal só muda afiliação. Falta mudar o papel (XEP-0045 §8.2, IQ `muc#admin` com `role=none`), que é por apelido, não por JID.
- **Fora do pacote**: a tela de pedidos de voz (ícone do balão com interrogação), adiada a pedido da Isadora.
- **Servidores**: o app só mostra "Moderar" se a sala anuncia `message-moderate:1`, então degrada bem. **Não confirmado** se o Prosody 13.0.7 e o ejabberd 26.09 anunciam o recurso: conferir o `disco#info` de uma sala em cada servidor.

### 4. XEP-0313: quase nenhum código, risco baixo

- Já funciona. Falta garantir que o canal novo nasça com o arquivo ligado (`enablearchiving`, `mam`, `muc#roomconfig_mam`) e avisar se o servidor não oferecer. O `//TODO: mark mam as mandatory` do `MLMucProcessor.m` pode virar obrigatório para canal.
- Canal recém-criado não tem histórico para o catchup baixar.

## Riscos gerais

- **Banco real**: qualquer coluna nova (stanza-ids antigos) precisa ser validada com o banco exportado do TestFlight ou o do `.dev`, não com linha fabricada.
- **Dois servidores**: Prosody e ejabberd diferem no formulário de configuração da sala; testar nos dois e nos simuladores iOS 18.6 e 27.
- **Canal criado em produção** cria sala de verdade: para testar, usar um canal de teste e destruí-lo depois (o app já destrói sala).
- **Merge com o Monal**: o `configureMuc:` e o `MLMucProcessor.m` são as partes de maior atrito.

## Recomendação: duas entregas

1. **Criar canal**: com checagem de endereço livre, aviso de occupant-id e MAM, interruptor "listar na busca" e a configuração do Conversations.
2. **Moderação**: kick, stanza-ids antigos e arquivo local. Pequena e independente.

Cada entrega nasce em branch próprio a partir da `isaCloud`, com a implementação delegada ao `executor` depois da aprovação do plano.

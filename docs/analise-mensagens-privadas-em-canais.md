# Análise pré-implementação: mensagens privadas em canais (MUC-PM)

Status: **análise, sem código** (03/11/2026). Fontes: o código do isaCloud/Monal (esta árvore) e o clone local do Conversations (`~/projects/java/Conversations`, versão 2.21.0-2, commit `a4c980825`). Nada aqui foi testado nos servidores; os pontos marcados com **[confirmar]** dependem de ler o disco#info/formulário da sala em cada servidor.

## 1. O que é

Uma mensagem privada em canal (PM, XEP-0045 §7.5) é uma mensagem `type="chat"` enviada ao **JID completo do ocupante** (`sala@servico/nick`), com `<x xmlns="http://jabber.org/protocol/muc#user"/>` marcando que é uma PM de sala. Só o destinatário a recebe; ela não entra no histórico público da sala (o arquivo MAM da sala não guarda PMs). Quem responde usa o `from` recebido (`sala/nick-do-remetente`).

Vale só para salas em que **não conhecemos o JID real** do outro (canais públicos/anônimos). Em grupo privado (só membros, `whois=anyone`) o JID real é conhecido e a conversa 1:1 normal (com OMEMO) é melhor, ver §4.3.

## 2. O que o isaCloud/Monal faz hoje: **rejeita PMs de propósito**

`Monal/Classes/MLMessageProcessor.m:238-262`: o comentário diz *"ignore muc PMs (after discussion with holger we don't want to support that)"*. Toda mensagem que **não** é `groupchat`, tem `muc#user x`, não é convite e tem `<body>`:
- é descartada (`DDLogWarn "Ignoring muc pm marked as such..."`);
- se tem `id` e o contato é uma sala, responde ao remetente com um erro `cancel / feature-not-implemented` e o texto *"The receiver does not seem to support MUC-PMs"* (então quem usa Conversations vê a PM falhar para nós).

Outros pontos do código que hoje assumem "sem PM":
- `MLMessageProcessor.m:265-278`: **carbons** de PM sem a marca são ignorados quando o outro lado é uma sala (`Ignoring carbon copied muc pm...`).
- `MLMessageProcessor.m:280-290`: mensagens `groupchat` **ou** com `muc#user x` de sala desconhecida são ignoradas (isso continuaria valendo para PMs).
- `xmpp.m:4071` e `:4166/:4216`: o envio decide o tipo só por `isMuc` (`groupchat` para sala, `chat` para o resto); não existe "enviar para sala/nick".
- Modelo e banco: o contato é identificado por JID **bare** (`buddylist(account_id, buddy_name)`, `MLContact createContactFromJid:`); `message_history` tem `buddy_name` (a sala), `actual_from` (nick de quem falou) e `participant_jid`. **Não há campo para "destinatário privado"**, e `MLMessage.messageType` descreve o conteúdo (texto, imagem, link…), não o canal.
- Não lemos `muc#roomconfig_allowpm` em lugar nenhum (só configuramos outros campos de sala em `MLMucProcessor.m:75-86`); a tela de participantes (`ChannelMemberList.swift`) mostra nick, papel e chapéus, sem ação por participante.
- O `docs/plano-nick-por-sala.md` já mexe na identidade na sala (nick por sala, 303); PMs dependem de o nick ser estável (§6).

## 3. Como o Conversations faz

Resumo: **a PM é uma mensagem comum da conversa da sala, com tipo próprio, aparecendo no meio da linha do tempo com uma marcação.**

| Aspecto | Conversations (arquivo) |
|---|---|
| Tipo | `Message.TYPE_PRIVATE` (4) e `TYPE_PRIVATE_FILE` (5); `isPrivateMessage()` (`entities/Message.java:70,981`) |
| Entrada na UI | menu de contexto do participante: "Enviar mensagem privada" (`MucDetailsContextMenuHelper.java:52-56,124,181`); em **grupo privado/não anônimo** o mesmo gesto abre uma conversa 1:1 normal, e o item PM só aparece em canal (`!isGroupChat`) |
| Habilitação | `mucOptions.allowPm()` lê o formulário da sala `muc#roomconfig_allowpm` (`anyone` / `participants` / `moderators` / nenhum) e compara com o papel de quem envia; sem o campo, assume permitido (`MucOptions.java:298-323`). Só para quem tem papel ≥ visitante. O dono pode mudar o campo (`MucConfiguration.java:58-65`) |
| Destino | `Conversation.nextCounterpart` = JID completo `sala/nick` (`Conversation.java:707`); `ConversationFragment.privateMessageWith` define, limpa o campo de texto e troca a dica (`ConversationFragment.java:2665,1126-1132`: "Enviar mensagem privada para *nick*" e **"enviar mensagem sem criptografia"**) |
| Envio | `MessageGenerator.preparePacket` (`:41-45`): `to` = JID completo, `type=chat`, `muc#user x`, pede recibo `urn:xmpp:receipts`; mensagem de sala comum vai para o bare JID com `groupchat` |
| Recebimento | `MessageParser` (`:536-545`): se há `muc#user x` e não é `groupchat`, marca `TYPE_PRIVATE`; guarda `trueCounterpart` (JID real, se a sala revelar) e `occupantId` (XEP-0421) |
| Dedupe | PM sempre passa pela checagem de duplicata (`:626-627`) |
| Recibos | envia recibo de entrega para PM (`:586-592,701-704`, com um TODO se faz sentido para todas) e trata a leitura de PM à parte (`DisplayedManager.java:133` exclui PM; `MessageDisplayedSynchronizationManager.java:125` usa o ocupante como item) |
| Âncora de MAM | PM **não** serve de âncora de catch-up da sala (`Conversation.java:906`: "pode vir do arquivo do usuário") |
| Criptografia | A dica do campo de texto diz "enviar mensagem sem criptografia" (`ConversationFragment.java:1126-1132`), mas o código do OMEMO **prevê PM**: `AxolotlService.java:1632` monta o cabeçalho com o JID real do ocupante (`trueCounterpart`) quando a sala o revela. Em canal anônimo (sem JID real) a PM sai em texto claro. **[confirmar]** na prática com uma sala não anônima |
| Resposta/reação/edição | resposta a PM vira PM para o mesmo ocupante (`XmppConnectionService.java:962`); reação em PM é enviada como chat privado (`ReactionManager.java:150-191`); correção de mensagem funciona |
| Arquivos | `TYPE_PRIVATE_FILE`; upload não usa o bare da sala (`HttpUploadConnection.java:214`) |
| Notificação | PM sempre notifica, como se fosse menção (`NotificationService.java:1798`) |
| Exibição | prefixo no balão: "Mensagem privada" / "Mensagem privada para *nick*" (`MessageAdapter.java:522-568`, `:708-735`) |

Gajim/Dino/Movim seguem o outro modelo (cada PM abre uma **conversa separada** com o ocupante); não olhamos o código deles aqui.

## 4. Opções de desenho para o isaCloud

### 4.1 Opção A (recomendada): PM dentro da linha do tempo da sala, como no Conversations
- Usa a conversa da sala e `message_history` com `buddy_name = sala`; não cria contato novo. Mantém a regra "um contato = um JID bare".
- Um campo novo em `message_history` indica a PM e para quem/de quem foi (ver §5).
- A UI mostra a PM no fluxo com marcação (pílula "Privada" + nome do outro), e o campo de texto troca de modo ("Para *nick* · privada", com um X para voltar à sala).
- Prós: pouco atrito com o Monal (nada muda no modelo de contatos), reaproveita histórico, notificações e envio de arquivo. Contras: a PM se mistura ao fluxo público (risco de enviar pelo modo errado: a dica visível e o X no campo mitigam, como no Conversations).

### 4.2 Opção B: conversa separada por ocupante
- Cria um "contato" `sala/nick` (JID completo). Conflita com o modelo atual (JID bare como chave de `buddylist`, `activechats`, `MLContact`), com nick que muda e com ocupante que sai. **Atrito alto no merge com o Monal.** Não recomendada.

### 4.3 Regra de produto (vale para as duas): onde oferecer
- **Canal público/anônimo** (sem JID real): oferecer "Mensagem privada" no participante, se `allowpm` permitir.
- **Grupo privado** (membros-only, JID real conhecido): **não oferecer PM**; o gesto abre/usa a conversa 1:1 com o JID real (com OMEMO). Já existe a lista de membros com `ContactDetails`. É exatamente o que o Conversations faz e evita mandar sem criptografia dentro de um grupo "seguro".

## 5. O que precisa mudar (Opção A) e onde

1. **Recebimento** (`MLMessageProcessor.m:238-262`): trocar "descarta + erro `feature-not-implemented`" por "aceita como PM" quando a sala é conhecida; manter descarte de sala desconhecida (linhas 280-290) e o erro só para quando a opção estiver desligada. Marcar a mensagem como PM e guardar o nick do outro.
2. **Carbons** (`:265-278`): decidir o que fazer com a cópia `sent` de uma PM enviada de outro aparelho (hoje é descartada). O XEP-0045 recomenda a marca `muc#user x`; **[confirmar]** se Prosody e ejabberd copiam PMs marcadas e se queremos mostrá-las.
3. **MAM**: PMs não estão no arquivo da sala; chegam no arquivo da própria conta (**[confirmar]** com `with` e como o servidor as guarda). O catch-up do Monal precisa não usar PM como âncora da sala (mesma ressalva do Conversations) e dedupe por `stanza-id`/id.
4. **Banco** (`DataLayerMigrations.m`, escada própria `+migrateISACloudDB:`, flag `isacloud_dbversion`, passo idempotente): coluna nova em `message_history` (por exemplo `muc_pm_nick TEXT NULL`, "o outro lado da PM"); `NULL` = mensagem normal. **Validar a migração com o banco real** antes (regra do projeto). Nenhum passo na escada 7.0xx do Monal.
5. **Modelo** (`MLMessage.h/.m`, `DataLayer.m` insert/leitura, mapeamento para `ChatViewMessage` no `ChatView.swift`): propagar o campo; notificações e `lastMessage` da lista de conversas mostram a PM como "Mensagem privada de *nick*".
6. **Envio** (`xmpp.m:4071,4125-4220`): novo caminho "PM": `to = sala/nick`, `type=chat`, `muc#user x`, `request` de recibo, **sem OMEMO** na primeira versão (canal anônimo não tem JID real) e sem `groupchat`; tratar erro do servidor (`item-not-found` quando o ocupante saiu, `not-acceptable`/`forbidden` quando `allowpm` não deixa) mostrando o "!" existente.
7. **Permissão** (`MLMucProcessor.m`, formulário da sala): ler `muc#roomconfig_allowpm` do disco#info da sala (Conversations lê do `roomInfoForm`) e guardar por sala; habilitar o item só quando o nosso papel permitir. **[confirmar]** o nome do campo em Prosody 13.0.7 (`isacloud.im`) e ejabberd 26.09 (`autozona.cc`): o Conversations espera `muc#roomconfig_allowpm`; se o ejabberd usar outro nome, tratar os dois.
8. **UI** (`ChatView.swift`, `ChannelMemberList.swift`, `ChatInputBar.swift`): ação "Mensagem privada" no participante (só canal, só se permitido); modo de envio privado no `ChatInputBar` com dica e X; balão com pílula "Privada · *nick*" (cor/ícone distintos), citação/resposta herdando o destino privado; textos novos em inglês + pt-BR no override do isaCloud (regra de traduções).
9. **Fork do ExyteChat**: só se o balão exigir algo que o `ChatView` não permita por dados (provável que não; a marcação cabe no texto/cabeçalho do balão do app).
10. **Notificações e extensão** (`NotificationService`): PM chega como `chat` com `from=sala/nick`; conferir que o `MLMessageProcessor` usado na extensão (mesmo código) aceita e que o alerta usa o nick, não o JID da sala. Push filtering ainda não está ativo.
11. **Conversas ativas/contador**: a PM atualiza a linha da sala (não cria linha nova); badge conta como menção.

## 6. Riscos e armadilhas

- **Atrito com o Monal:** hoje o upstream **decidiu não suportar** MUC-PM. Esta feature reverte uma decisão deliberada do upstream em `MLMessageProcessor.m`; manter a mudança pequena, comentada com `//isaCloud:` e registrada em `docs/decisoes.md`. O PR é do app para a `isaCloud` (nunca para o Monal/upstream).
- **Segurança/privacidade:** em canal anônimo não há JID real, então a PM só pode sair **sem criptografia de ponta a ponta** (o operador do serviço/sala pode ver); a UI precisa dizer isso. Em grupo privado nem oferecer PM (§4.3), usando a conversa 1:1 com OMEMO. O mesmo vale para anexos.
- **Identidade instável:** o PM depende do nick atual; troca de nick (303, `docs/plano-nick-por-sala.md`) ou saída do ocupante quebra o destino. Conversations não resolve isso; usa `occupant-id` (XEP-0421) quando a sala fornece. O Monal já guarda `occupant_id` (`muc_participants`, migração 867). Resposta a PM de quem trocou de nick: tratar erro, sem reencaminhar para a sala.
- **Mistura com a sala:** risco de a pessoa achar que mandou em privado e ter mandado público (ou ao contrário). Mitigar com modo explícito e visual forte.
- **Spam:** `allowpm` e `muc_limits` do servidor são o controle; o app deve respeitar o formulário e permitir bloquear um ocupante (já existe? **[confirmar]**).
- **Carbons e múltiplos aparelhos:** sem tratar o `sent` carbon, a PM enviada do iPhone não aparece no iPad; com tratar, conferir a duplicação.
- **Teste:** precisa de dois ocupantes de verdade (as 3 contas de teste servem: duas em `isacloud.im`, uma em `autozona.cc`), em canal público, e em **ambos** os servidores (Prosody 13.0.7 e ejabberd 26.09); iOS 18.6 e 27.

## 7. Plano em fases (sugestão)

0. **Verificação nos servidores** (sem código): `disco#info` da sala nos dois servidores, formulário `muc#roomconfig_allowpm`, comportamento de carbons e MAM de PM; um dump de uma PM real recebida do Conversations.
1. **Receber PMs** (passos 1, 4, 5 e a marcação no balão): a PM do outro aparece marcada e a resposta ainda vai por um botão simples. Remove o erro "não suporta MUC-PM" que o outro lado vê hoje.
2. **Enviar PM** (6, 7, 8): item no participante, modo do campo de texto, erros.
3. **Acabamento:** carbons/MAM (2, 3), notificação (10, 11), arquivos, reações e respostas.
Cada fase vira um PR do app para a `isaCloud`, com o doc `docs/decisoes.md` atualizado e o roadmap.

## 8. Perguntas para a Isadora

1. Confirma a **Opção A** (PM na linha do tempo da sala, como no Conversations)?
2. Só **canais** ou também grupos privados? (Sugestão: só canais; em grupo, abrir a conversa 1:1 com OMEMO.)
3. Começar pela **fase 1 (receber)**, que já resolve o erro que quem usa outro cliente recebe de nós?
4. Aceitamos divergir do Monal nesse ponto (upstream decidiu não suportar)? Algum aviso/convite ao Jejê antes?

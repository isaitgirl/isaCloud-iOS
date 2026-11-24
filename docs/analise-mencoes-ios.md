# Análise: menções explícitas (XEP-0513) no isaCloud iOS

Relatório pedido em `docs/xep-0513-mencoes-analise.md`, só a parte do iOS. Nenhum código foi alterado.
Caminhos relativos a `Monal/Classes/`, salvo indicação. Linhas conferidas em 23/11/2026 (build 129).

---

## 1. Mapa do código

| Ponto | Arquivo:linha | Classe/método | O que faz hoje |
|---|---|---|---|
| 1. Decisão de notificar | `MLNotificationManager.m:323-367` | `internalMessageHandlerWithMessage:andAccount:showAlert:andSound:andLMCReplaced:` | Arquivada → silêncio; mutada → silêncio; sala "só menções" → procura os nomes no texto; senão, notifica tudo |
| 1. Casamento do nome | `HelperTools.m:937-965` | `+text:mentionsAnyOfNames:` | Palavra inteira (alfanumérico + `_`), sem caixa e sem acento |
| 1. Contador global (ícone do app) | `DataLayer.m:2611-2640` | `countUnreadMessages` | SQL com `LIKE '%nick%'`: **substring**, sem limite de palavra (diverge do item acima) |
| 1. Cor do contador na lista | `MLContactCell.m:331-357` + `DataLayer.m:2903-2921` | `shouldShowGrayBadgeForContact:` / `hasUnreadMentionInMuc:forAccount:withNames:` | Relê as últimas 500 não lidas e aplica `text:mentionsAnyOfNames:` |
| 1. "@" e negrito na lista | `MLContactCell.m:141-152` | `applyUnreadHighlightForContact:` | Depende do resultado da cor acima |
| 1. NSE | `NotificationService/NotificationService.m:300-309` | — | Sobe `MLNotificationManager` + `MLXMPPManager` inteiros: **mesmo código** do app, sem caminho próprio |
| 2. Parsing da mensagem | `MLMessageProcessor.m:395-416` (inbound), `:745-797` (LMC + gravação) | `processMessage:…` | Calcula `inbound` por occupant-id → JID → nick; grava com `addMessageToChatBuddy:` (`:779`) |
| 2. Correção recebida | `MLMessageProcessor.m:751-767` | idem | `updateMessageHistory:withText:` troca só o texto |
| 2. Reply recebido | `MLMessageProcessor.m:803-813` | idem | Guarda só o id citado (`setQuotedMessageIdForHistoryId:`); o **intervalo do fallback não é guardado**; o body fica com as linhas `> …` |
| 2. Modelo / banco | `DataLayer.m:110` (esquema), `MLMessage.m:93` | `message_history`, `MLMessage` | Já tem `occupant_id`; nada sobre menções |
| 3. Occupant-id de terceiros | `MLMucProcessor.m:470-471`, `DataLayer.m:1276` | presença → `muc_participants.occupant_id` | Lido só se a sala anuncia a feature |
| 3. Meu occupant-id | `MLMucProcessor.m:1178-1192`, `DataLayer.m:1600-1609` | self-presence 110 → `buddylist.muc_occupant_id` | Já existe (com a proteção do C37) |
| 3. Sala anuncia occupant-id? | `MLMucProcessor.m:36, 142, 159` | `_roomFeatures` | Cache de disco da sala, persistido no estado da conta (não no banco) |
| 4. Autocomplete de `@` | `ChatInputModel.swift:344-383`, `ChatInputBar.swift:85-93`, `ChatView.swift:1325-1335` | `MentionAutocomplete` | Insere **`nick, `** (sem `@`), só texto; candidatos são só os nicks online |
| 4. Montagem da stanza | `xmpp.m:4261-4375` | `sendMessage:toContact:isEncrypted:isUpload:andMessageId:withLMCId:` | Lê do banco, pelo `messageId`, os extras (sticker, reply, enquete) e os anexa |
| 4. Correção enviada | `ChatView.swift:1813-1822` | `.edit` | Chama `sendMessage` com **`UUID()` novo** e `withLMCId:`; esse id novo não está no banco |
| 4. Code points | `MLMessageProcessor.m:525` | — | Já existe o padrão `lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding / 4` |
| 5. Features / caps | `HelperTools.m:3557-3575`, `xmpp.m:279-291, 416-424` | `+getOwnFeatureSet` | Lista fixa; o hash é recalculado a partir dela no init da conta. Basta acrescentar a string |
| 6. Ajuste por sala | `ContactDetails.swift:452-488`, `MLContact.m:696-705`, `DataLayer.m:3128-3162` | `toggleMentionOnly:` | Ciclo Todas → Só menções → Silenciada (`buddylist.mentionOnly`, `muted`) |
| 6. Sincronização por sala | `MLPubSubProcessor.m:264, 310-330, 411-524` | bookmarks `urn:xmpp:notification-settings:0` | `always` / `on-mention` / `never`, compatível com outros clientes |
| 6. Canal público começa "só menções" | `MLMucProcessor.m:1931-1935` | — | No primeiro join |
| 6. Ajustes globais | `GeneralSettings.swift` (ex.: `showNotificationsForReactions`) | — | Não há nada sobre menções |
| 6. Traduções | `isaCloud/localization/pt-BR.lproj/Localizable.strings` | — | Override do isaCloud (Weblate é a base) |

## 2. Comportamento atual, com precisão

1. **Só importa em sala "só menções".** Em sala com "todas as mensagens" a menção não é olhada: tudo notifica (`MLNotificationManager.m:344`). Os três modos da tabela, portanto, só mudam algo nessas salas. Grupos privados começam em "todas"; canais públicos começam em "só menções".
2. **Nomes testados:** nick na sala, nome de exibição da conta, parte local do JID e o JID inteiro (`:355-360`). Então quem se chama "perdido" é notificado por "perdido" também quando o nick na sala é outro.
3. **Casamento:** palavra inteira, sem caixa, sem acento (`HelperTools.m:937`). A posição na frase não conta; não há `@` obrigatório. Os testes estão em `MonalXMPPUnitTests/HelperToolsTest.swift:50-58`.
4. **Nick antigo:** não é considerado (só o nick atual, `ownNickNameforMuc`).
5. **Citações:** **não são ignoradas**. O body guardado inclui as linhas `> …` do reply, então citar alguém notifica essa pessoa.
6. **Mensagem minha:** não notifica, mas por outro caminho: `showAlert` é NO para saída, e `inbound` usa o occupant-id (`MLMessageProcessor.m:401-413`).
7. **Menção em massa:** se mais de 5 nicks de participantes aparecerem como palavras soltas, a mensagem é silenciada (`:346-353`).
8. **Três critérios diferentes:** notificação (palavra inteira), cor do contador (palavra inteira, recalculada sobre até 500 mensagens a cada desenho de célula) e contador do ícone (`LIKE`, substring). Hoje "precisa" conta no ícone para a "isa", mas não notifica.

## 3. Lacunas

| Desejado | Situação |
|---|---|
| Ler `<mention/>` | Não lido em lugar nenhum |
| Persistir "é menção a mim" | Não existe; a decisão é refeita a partir do texto em três lugares |
| `<noping/>`, `<active/>` | Não existem |
| Ignorar citação | Não ignora |
| Modos `all` / `called` / `explicit` | Só existe o equivalente a `all` (e com mais nomes que o nick) |
| Enviar `<mention/>` | O autocomplete só insere texto e não sabe o occupant-id do escolhido |
| Remover menção se o `@nick` for apagado | Não há estado de menção no campo de texto |
| Menções na correção | A correção usa um id novo que não está no banco, então o padrão "extras guardados pelo messageId" não funciona nela |
| Anunciar `urn:xmpp:mentions:0` | Uma linha em `getOwnFeatureSet` |

## 4. Plano de implementação

Ordem pensada para que cada passo seja um build testável no .dev.

1. **Função pura de decisão (P).** `MentionRules.swift` (Swift, sem UI, como `MucHatRules.swift`): recebe body, lista de `<mention/>` já parseados, meu occupant-id, meu JID, meu nick, modo, e devolve `notify` / `silent`. Inclui o corte das citações (linhas `>` e o intervalo do fallback, quando vier) e as regras do `called` (`@nick` em qualquer lugar; `nick:` / `nick,` no início). Testes Swift Testing cobrindo os 13 casos. *Arquivos:* novo `MentionRules.swift`, novo `MentionRulesTests.swift`.
2. **Parse e persistência no recebimento (M).** Migração: `message_history.mentions_me` (0/1/NULL) e `message_history.has_explicit_mentions`. Em `MLMessageProcessor.m`, logo depois de `addMessageToChatBuddy:` (`:779`), ler `{urn:xmpp:mentions:0}mention` (ignorar os que têm `mentions=`, sem erro), chamar a função do passo 1 com o modo da sala e gravar. Na correção (`:766`), recalcular. Como o NSE roda o mesmo `MLMessageProcessor`, o MAM e a extensão saem iguais ao ao vivo (casos 11 e 12). *Arquivos:* `DataLayerMigrations.m`, `DataLayer.m/.h`, `MLMessageProcessor.m`, `MLMessage.m/.h` (propriedade `mentionsMe`). Lembrar a regra do C18: coluna nova com padrão.
3. **Usar a flag nos três lugares (M).** `MLNotificationManager.m:344-361` passa a ler `message.mentionsMe`; `hasUnreadMentionInMuc:` vira `EXISTS(... mentions_me=1)`; `countUnreadMessages` troca os `LIKE` por `M.mentions_me = 1`. Mensagens antigas (NULL) caem no critério de texto atual, para não mudar o histórico. Ganho extra: acaba a releitura de 500 mensagens por célula. *Arquivos:* `MLNotificationManager.m`, `DataLayer.m`, `MLContactCell.m`.
4. **Configuração dos modos (M).** Chave global `mentionNotificationMode` (padrão `called`) em `defaultsDB` com migração (regra do C18). Picker em `GeneralSettings.swift` com os textos da tabela; sobrescrita por sala em `buddylist.mention_mode` (NULL = segue o global) e um item em `ContactDetails.swift` visível só quando a sala está em "só menções". Traduções pt-BR no override. *Arquivos:* `GeneralSettings.swift`, `ContactDetails.swift`, `DataLayerMigrations.m`, `HelperTools.m` (padrão), `Localizable.strings` do isaCloud.
5. **Anunciar a feature (P).** `@"urn:xmpp:mentions:0"` em `getOwnFeatureSet`. Só depois do passo 2 estar no ar, para não anunciar sem saber ler.
6. **Estado de menção no campo de texto (M).** `ChatInputModel` guarda `[(nick, occupantId?, jid?)]` escolhidos no autocomplete e no toque no avatar. `mentionNicks()` (`ChatView.swift:1325`) passa a devolver também `occupant_id` e `participant_jid` de `getMembersAndParticipantsOfMuc`. Ao enviar, cada menção só vale se o nick ainda estiver no texto como palavra; as posições `begin`/`end` são recalculadas no texto final e convertidas para code points (utilitário em Swift com `unicodeScalars`, testado com "👋 @perdido", caso 13).
7. **Anexar `<mention/>` na stanza (M).** Duas opções:
   - (a) guardar as menções por `messageId` no banco, como reply e enquete, e ler em `xmpp.m` antes de `setStoreHint`;
   - (b) passar as menções como parâmetro novo de `sendMessage:` (sobrecarga), e também guardá-las.
   **Recomendo (b) + guardar**: a correção (`ChatView.swift:1822`) usa um id novo que nunca vai para o banco, então só o parâmetro cobre o caso; guardar cobre os reenvios. Escolha do atributo: `occupantid` se `_roomFeatures` da sala tem `urn:xmpp:occupant-id:0`; senão `jid` se conhecido; senão nada. Em sala OMEMO (grupo privado), o `<mention/>` fica fora do payload, como reply e enquete já fazem, e leva só ids e posições. *Arquivos:* `xmpp.m/.h`, `ChatView.swift`, `ChatInputModel.swift`, `DataLayer.m`.
8. **Correção recalcula (P).** No `.edit`, carregar no modelo de entrada as menções da mensagem original (pelo passo 7) e reaplicar o passo 6 no texto editado.
9. **Teste cruzado (M).** Com o Android (quando tiver a parte dele) e com algum cliente que já envie XEP-0513, se houver. Atualizar `CHANGELOG.md` e `CHANGELOG-USERS.md` (ex.: "🔔 Chega de alarme falso: o app só te chama quando alguém te chamar de verdade.").

Tamanho total: médio-grande, dá para fatiar em três PRs: (1-3) recebimento, (4-5) ajustes e feature, (6-8) envio.

## 5. Casos de teste: esperado × atual

Considerando sala em "só menções" e nick `perdido` (em sala "todas as mensagens" todos notificam hoje e continuarão notificando).

| # | Esperado | Hoje | Diferença |
|---|---|---|---|
| 1 "tô perdido aqui" | só `all` | notifica | sim (no padrão `called`) |
| 2 "@perdido vem cá" | `all`, `called` | notifica | só em `explicit` |
| 3 "perdido: vem cá" | `all`, `called` | notifica | só em `explicit` |
| 4 "vem cá perdido" | só `all` | notifica | sim |
| 5 nick no texto + `<mention/>` para outro | nunca | notifica | sim |
| 6 `<mention>` meu, sem nick no texto | sempre | **não** notifica | sim |
| 7 `<mention>` meu com `<noping/>` | nunca | notifica se o nick estiver no texto | sim |
| 8 reply citando meu nick | não notifica | notifica (linha `>` está no body) | sim |
| 9 mensagem minha | não | não | igual |
| 10 `mentions='…#channel'` | ignorado | ignorado (não lido) | igual, mas precisa continuar assim depois |
| 11 MAM com `<mention/>` | igual ao vivo | igual ao vivo (texto) | igual depois do passo 2 |
| 12 NSE × primeiro plano | igual | igual (mesmo código) | igual, se a flag for gravada no `MLMessageProcessor` |
| 13 "👋 @perdido" | `begin=2 end=10` | nada é enviado | novo |

Detalhe do caso 13: em UTF-16 o `@` está na posição 3, em code points na 2.

## 6. Riscos e dúvidas em aberto

**Riscos**

- **Merge com o upstream:** `MLNotificationManager.m:344-361`, `countUnreadMessages` e `sendMessage:` já têm muito código isaCloud. A lógica nova deve ficar em arquivo próprio (`MentionRules.swift`) e entrar nesses pontos com poucas linhas marcadas `//isaCloud`.
- **Desempenho na NSE:** o parse de alguns atributos é barato. O ganho é maior do que o custo: os passos 2 e 3 tiram a releitura de 500 mensagens por célula e o `LIKE` em toda a tabela.
- **Occupant-id ausente:** a self-presence sem occupant-id (C37) já é tratada; se mesmo assim faltar o meu, cair na comparação por JID e depois pelo nick. Se uma mensagem tem `<mention/>` mas eu não sei meu occupant-id, ela não é menção a mim: aceitar esse falso negativo e registrar em log.
- **Comparações por string de nick** que poderiam passar ao occupant-id: o heurístico de "mais de 5 nicks" (`:346-353`) e `mentionNicks()`. O `inbound` já usa occupant-id.
- **Modo `explicit` hoje** quase não notificaria: pouca gente envia XEP-0513 ainda (o Android também ainda não envia).

**Decisões para a Isadora**

1. **Nomes testados na detecção pelo texto:** hoje são nick, nome de exibição, parte local do JID e JID. A spec e o pedido falam só do nick. Manter os quatro em `all` e só o nick em `called`?
2. **Autocomplete:** hoje insere `nick, `. Passar a inserir `@nick ` (casa com o exemplo da spec e com o modo `called` para quem não lê XEP-0513) ou manter o estilo do Conversations?
3. **Menção em massa:** manter o corte de "mais de 5 nicks" também para `<mention/>` explícitos (ex.: mais de 5 elementos silencia)?
4. **Sobrescrita por sala:** fica só local, ou entra no bookmark? `notification-settings:0` só conhece `always`/`on-mention`/`never`; um valor novo quebraria a compatibilidade com outros clientes. Sugestão: só local.
5. **Grupos em "todas as mensagens":** continuam notificando tudo (os modos só valem em "só menções")? É o que o Monal e o Conversations fazem hoje.
6. **`<active/>`:** sem o conceito de "ativo" no iOS (o app em segundo plano é sempre "inativo"), tratar como `<noping/>` quando em segundo plano, ou ignorar o modificador?
7. **Mensagens antigas (NULL):** manter o critério de texto atual ou aplicar o modo novo a elas também?

O relatório do Android (`analise-mencoes-android.md`) fica para a sessão do repositório do Android.

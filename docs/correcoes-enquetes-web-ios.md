# Correções de enquetes a replicar no isaCloud Web e no isaCloud iOS

> O Android levou quatro correções de estabilidade nas enquetes (`urn:fluux:poll:0`) depois do
> problema de duplicação observado nas releases 74–78. Este documento lista a regra de cada uma,
> o estado atual no **Web** (`~/projects/js/isaCloud-Web`, fork do Converse.js) e no **iOS**
> (`~/projects/isaCloud/isaCloud-iOS`, fork do Monal), e onde mexer em cada um.
>
> Contexto do Android: `docs/analise-enquete-fluux.md`, `docs/decisoes-enquetes-fluux.md` §13/§14,
> `docs/regressoes.md` (entradas de enquete) e a branch `fix/enquetes-duplicacao-mam`.
> Protocolo: `~/projects/js/fluux-messenger/docs/XEP-POLL_PROTOCOL.md`.

## 1. O problema que originou as correções

Servidores como `conexaociencia.cc` entregam mensagens de MAM **sem `<stanza-id>` e sem
`<origin-id>`** — só o `id` de cliente. Somado a isso:

1. o app crashava ao abrir a conversa (bug de R8/Gson, só no Android), o catch-up do MAM
   reprocessava mensagens e as notificações repetiam;
2. mensagens próprias de MUC eram gravadas de novo porque a deduplicação dependia de stanza-id ou
   do `counterpart` (que muda entre a cópia local, `sala`, e a do MAM, `sala/nick`);
3. o estado "encerrada" era gravado **depois** do envio; crash/kill no meio deixava a enquete
   aberta e o menu "Encerrar" disponível de novo;
4. cada `<poll-closed>` que chegava virava **um cartão completo**, então vários fechamentos
   apareciam como várias enquetes;
5. enquetes antigas já gravadas com cartão de fechamento duplicado continuavam na tela.

Resultado: o criador encerrou a mesma enquete 4 vezes, cada fechamento virou outro cartão e quem
estava no Gajim viu o resultado repetido em texto.

## 2. As seis correções (regra, independente de cliente)

| # | Correção | Regra |
|---|---|---|
| 1 | **Dedupe de replay de MAM** | Quando o servidor não manda `stanza-id`/`origin-id`, reconhecer a mensagem própria pelo `id` de cliente igual ao id local que já temos (no Android, `remoteMsgId == uuid`). Nunca comparar `counterpart` por JID nu: em sala isso fundiria ocupantes diferentes. |
| 2 | **Encerrar antes de enviar** | Gravar "encerrada" (e o tally congelado) **antes** de mandar o `<poll-closed>`; só desfazer se o envio falhar. Um crash no meio do envio não pode reabrir a enquete. |
| 3 | **Um único estado por enquete** | Um `<poll-closed>` válido não vira uma segunda mensagem/cartão: aplicar na original e **consumir** a mensagem de fechamento. Fechamentos repetidos são ignorados. A exceção é quem entrou depois e não tem a original — aí o fechamento é a única evidência e deve ser mostrado. |
| 4 | **Tally congelado na original** | A original guarda o tally recebido no fechamento (`pollClosed`/`poll_closed`) além do instante (`closed_at`). Sem isso, ao apagar o cartão redundante o resultado dependeria das reações (que podem ter sido podadas). |
| 5 | **Original chegando depois** | Se a janela de MAM traz o fechamento antes da enquete, guardar a informação e aplicá-la quando a original chegar (adotar o tally e remover o fechamento redundante). Validar criador/título/emojis na hora de adotar. |
| 6 | **Limpeza dos dados antigos** | Uma migração local única copia o tally do fechamento para a original e apaga as mensagens de fechamento que ficaram redundantes (só quando a original existe, tem `closed_at` e o título confere). JSON corrompido e fechamento sem original não são tocados. |

Regras que **não** mudam: voto continua sendo reação XEP-0444 no stanza-id; `voters` do
`<poll-closed>` são nicks e não são reconciliados com as reações; validação do criador
(occupant-id quando existir, senão nick) + título + emojis; o body de fallback continua indo para
clientes legados.

## 3. Estado no isaCloud iOS

Já implementado (base do `docs/implementacao-enquetes-ios.md`, migração 9 do banco isaCloud):

- `Polls.swift`: definição/fechamento em JSON, tally, `toggledReactions`, `canVote`, validação
  (`closed(_:matches:)`), fallback bodies;
- `PollViews.swift` + `ChatView.swift`: cartão e voto;
- `MLMessageProcessor.processPollClosedNode`: verifica criador/título/emojis, ignora fechamento de
  quem não é o criador e mantém o **primeiro** fechamento quando a original já está encerrada;
- `MLXMPPManager.closePollAndAddToHistory:voters:isEncrypted:`: envia o fechamento e marca a
  original.

### O que falta (na ordem de importância)

1. **Ordem do envio** (`MLXMPPManager.m`, `closePollAndAddToHistory:` ~linha 944): hoje ele
   envia (`sendMessageAndAddToHistory`) e só depois grava `pollClosedAt` + tally. Inverter:
   persistir `pollClosedJSON` + `pollClosedAt` na original e **em todas as cópias** da mesma
   enquete antes de enviar; se o envio falhar, reverter. *(correções 2 e 4)*
2. **Tally na original** (`DataLayer`): a original hoje recebe só `pollClosedAt`
   (`setPollClosedAt`). Precisa também de `setPollClosedJSON:<closedJSON>` para o cartão mostrar o
   resultado congelado e para a limpeza não perder informação. *(correção 4)*
3. **Consumir o fechamento** (`MLMessageProcessor.processPollClosedNode`): a mensagem de
   fechamento é sempre persistida (`setPollClosedJSON … forHistoryId:historyId`) e o app renderiza
   um cartão inteiro para ela. Quando a original existe e o fechamento valida, aplicar na original
   e **não** manter/desenhar a mensagem (ou mostrar apenas uma linha compacta). Fechamento de quem
   entrou depois continua como cartão. *(correção 3)*
4. **Original tardia**: se `historyIdOfPollMessageId` não achar a original, hoje só loga
   "not in our database (yet)". Guardar o fechamento pendente (em memória e, se possível, numa
   coluna/tabela) e aplicá-lo quando a original for criada — com a mesma validação.
   *(correção 5)*
5. **Dedupe sem stanza-id** (`MLMessageProcessor.m`, criação da mensagem ~linha 794):
   `checkForDuplicates: origin-id || stanzaid` desliga a deduplicação exatamente no servidor que
   mais precisa (MAM sem os dois). Habilitar também quando o `messageId` (id de cliente) já existe
   no banco para aquele chat, ou sempre para itens de MAM (`usingHistoryId`/`historyBaseID`).
   *(correção 1)*
6. **Limpeza única** (`DataLayerMigrations.m`, próxima versão isaCloud = **10**): copiar o tally
   do fechamento para a original e apagar as linhas `isacloud_poll_closed` sem `isacloud_poll`
   cuja original tem `isacloud_poll_closed_at` e o mesmo título. Idempotente, como os outros
   passos do arquivo. *(correção 6)*

### Feito no iOS em 22/11/2026 (branch `fix/enquetes-encerrar-antes-de-enviar`)

Correções 2, 3, 4 e 5 implementadas e testadas no simulador e no `.dev`. Diferenças em relação ao plano acima:

- **2 e 4:** a original (e as cópias da mesma enquete) recebe `isacloud_poll_closed` e `isacloud_poll_closed_at` antes do envio, e a marca é desfeita se o envio falhar. `pollClosedJSONForOutboundMessageId:` ignora linhas com `isacloud_poll`, para que um reenvio da original não leve o `<poll-closed>` junto. O cartão da original mostra "Enquete encerrada · N votos" com o voto próprio marcado.
- **3:** o fechamento recebido, válido e com a original no banco, é aplicado e a linha dele é apagada antes de virar mensagem ou notificação. O **nosso** fechamento não pode ser apagado (o `xmpp.m` lê o JSON dele pelo messageid para enviar e reenviar), então fica no banco e o `ChatView` não o desenha (`PollCardRules.hidesClosing`). Esse filtro também esconde os fechamentos duplicados antigos, por isso a **correção 6 (migração) não foi necessária** no iOS.
- **5:** sem tabela de pendentes. A linha do fechamento que chegou antes já é a "pendência": ao gravar a enquete, o app procura fechamentos dela no chat, valida e adota o mais antigo válido. A regra do criador virou `PollRules.sameCreator`, usada pelos dois caminhos.
- **1 (pendente):** no iOS, itens de MAM sempre têm stanzaid (o Monal usa o `result@id`) e as mensagens próprias saem com origin-id, então trocar a condição de `checkForDuplicates` não resolve. O caso que sobra é a mensagem de **outra pessoa** que chega ao vivo sem stanza-id e volta pelo MAM. A correção seria um fallback em `hasMessageForStanzaId` (mesmo messageid + mesmo remetente + stanzaid vazio). Falta confirmar que acontece numa sala do conexaociencia.cc.

## 4. Estado no isaCloud Web

Já implementado no plugin `src/plugins/isacloud-polls/` (fases 1–3 do Android):

- `parsers.js` (`parsePollElement`, `parsePollClosedElement`), `tally.js`, `poll-card.js`,
  `poll-modal.js`, `send.js`, `i18n.js`;
- `close.js`: `isValidClose` (criador/título/emojis), `computeClosedTally` com `voters` em nicks,
  `closePoll` e `onAfterMessageCreated`;
- votos como reações, com os emojis de opção em `hidden_reaction_emojis` para não duplicar o chip;
- **original tardia já resolvida em memória**: `pending_closes` guarda o fechamento e aplica quando
  a enquete chega (correção 5 parcial).

### O que falta

1. **Ordem do envio** (`src/plugins/isacloud-polls/close.js`, `closePoll`): hoje
   `await chatbox.sendMessage(...)` e só depois `markClosed(message)`. Inverter — marcar a original
   (e todas as cópias no `chatbox.messages`) com `isacloud_poll_closed` + `isacloud_poll_closed_at`
   antes do envio, revertendo se o envio lançar. *(correções 2 e 4)*
2. **Tally na original**: `markClosed` grava somente `isacloud_poll_closed_at`; incluir o
   `isacloud_poll_closed` (tally congelado) para o cartão da original mostrar o resultado e
   sobreviver à remoção do fechamento. *(correção 4)*
3. **Consumir o fechamento**: `onAfterMessageCreated` aplica na original, mas a mensagem de
   fechamento continua na coleção e o `wrapMessageRender` desenha `converse-isacloud-poll` para
   `isacloud_poll_closed` — ou seja, um cartão inteiro por fechamento. Quando a original existe e o
   fechamento valida, remover a mensagem (`message.destroy()`/`collection.remove`) depois de
   aplicar, e ignorar fechamentos repetidos. *(correção 3)*
4. **Dedupe sem stanza-id** (`src/headless/plugins/chat/parsers.js` ~linha 161): o id do modelo é
   `origin_id || stanza_id <from> || u.getUniqueId()`. Sem os dois primeiros, cada replay de MAM
   ganha um id novo e duplica — inclusive mensagens próprias de enquete. Incluir um fallback pelo
   `id` de cliente do stanza (quando já existe mensagem com aquele id no chatbox) ou pelo
   `isacloud_poll_client_id` do plugin. *(correção 1)*
5. **Limpeza dos dados antigos**: se a instalação persiste mensagens (IndexedDB/localStorage),
   rodar uma vez a mesma regra da migração 61 (copiar tally e remover fechamentos redundantes).
   Se a coleção é só em memória e recarregada do MAM, a correção 3 já resolve o que aparece.
   *(correção 6)*
6. **Opcional**: guardar `pending_closes` em armazenamento local para não perder o fechamento
   quando a aba recarrega antes da original chegar.

## 5. Checklist de teste cruzado

Montar uma sala em um servidor **sem stanza-id no MAM** (ex.: `conexaociencia.cc`) e outra no
`isacloud.im` (Prosody, com stanza-id), com Android + Web + iOS + um cliente legado (Gajim):

- [ ] Criar no Android → ler/votar no Web e no iOS; criar no Web → votar no Android; criar no iOS
      → votar no Web.
- [ ] Encerrar no Android: Web e iOS mostram **uma** enquete, encerrada, com o tally congelado; sem
      cartão extra de "resultado".
- [ ] Encerrar no Web e no iOS: Android idem.
- [ ] Fechamento repetido (outro cliente manda dois `<poll-closed>`): nenhum cliente cria segundo
      cartão.
- [ ] Matar o app/aba **durante** o envio do fechamento: ao reabrir, a enquete continua encerrada
      e o botão "Encerrar" não volta.
- [ ] Sala sem `stanza-id`: recarregar/reconectar (catch-up de MAM) não duplica cards nem notifica
      de novo.
- [ ] Quem entra depois recebe só o `<poll-closed>`: aparece o cartão de resultado (sem original).
- [ ] Quem carrega o fechamento antes da original e depois rola o histórico: a original entra
      encerrada, com o resultado, e o fechamento redundante some.
- [ ] Fechamento de quem não é o criador: ignorado, original segue aberta e votável.
- [ ] `hide-results` e `deadline` continuam iguais nos três clientes.
- [ ] Grupo com OMEMO: o `<poll-closed>` continua no stanza externo e a original fica encerrada.

## 6. Ordem sugerida

1. iOS: correções 2 e 4 (ordem do envio + tally na original) — são as que evitam o "Encerrar"
   repetido;
2. iOS: correção 3 (consumir o fechamento) e depois 5 e 1;
3. Web: correções 2, 4 e 3 (mesma ordem, arquivos em `isacloud-polls/`);
4. Web: 1 e, se houver persistência, 6;
5. iOS: 6 (migração 10) por último, quando houver dados antigos para limpar.

Observações: nada disso muda o protocolo no fio — Gajim e outros clientes legados continuam vendo
o texto de fallback de cada mensagem que for realmente enviada. A limpeza é só local. E como no
Android, o cartão da original encerrada deve mostrar "Encerrada · N votos" (resultado congelado),
enquanto a mensagem de fechamento de quem entrou depois mostra "Resultado final · N votos".

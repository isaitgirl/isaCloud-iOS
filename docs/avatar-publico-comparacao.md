# Avatar público: como Conversations, Converse.js e Monal publicam e leem

Investigação de 26/10/2026, a partir dos fontes do Conversations (2.21.0-2), do Converse.js (v14.0.0 + commits; o servidor do isaCloud serve a v13.0.1) e do Prosody 13.0.6. Pergunta de partida: por que a foto marcada como "visível para todos" não aparece no Converse.js?

## Resumo

- **A publicação do Monal está certa.** Os nós `urn:xmpp:avatar:data` e `urn:xmpp:avatar:metadata` ficam em `open`, com `info` (`id`, `type`, `bytes`) válido, igual ao que o Conversations publica. Prova: o `mod_http_pep_avatar` do servidor entrega a imagem a um visitante qualquer (`GET https://isacloud.im/pep_avatar/<usuario>` responde 200 `image/jpeg` para contas com a foto pública).
- **O Converse.js não lê XEP-0084 (PEP).** Ele só lê `vcard-temp` (XEP-0054) e o hash da presença (XEP-0153). No servidor, o `mod_vcard_legacy` converte o PEP em `vcard-temp` na hora da pergunta, usando o modelo de acesso do nó contra quem pergunta.
- **O Converse.js busca o `vCard` de um JID uma única vez e guarda para sempre** (no navegador). Se a primeira busca aconteceu quando o nó ainda era `presence` (ou não tinha foto), o servidor devolve um `vCard` vazio, o Converse grava `vcard_updated` e nunca mais pergunta, nem quando o hash da presença muda. É a causa mais provável da foto "invisível".

## Servidor (Prosody 13.0.6)

- `mod_vcard_legacy`, `iq-get/bare/vcard-temp:vCard`: lê `urn:xmpp:avatar:metadata` e, com o `id` do `info`, o item de `urn:xmpp:avatar:data`, os dois com `stanza.attr.from` como ator. Monta `PHOTO/TYPE` (só se o `info` tiver `type`) e `PHOTO/BINVAL`. Se o ator não pode ler o nó, **não dá erro**: responde um `vCard` vazio e com sucesso.
- O modelo `open` dá a qualquer um a afiliação `member` (`util/pubsub.lua`, `get_default_affiliation`); `presence` só a quem tem inscrição de presença com a conta (`mod_pep.lua`, `subscription_presence`).
- Salas (`muc.lib.lua`): um `get` de `vcard-temp` para um ocupante é reescrito para o JID bare dele, com o ator sendo o apelido na sala de quem perguntou (`sala@.../apelido`). Com `open` isso funciona; com `presence`, não.
- `inject_xep153` (`pre-presence/full|bare|host`): o servidor põe `<x xmlns="vcard-temp:x:update"><photo>hash</photo></x>` em toda presença que sai da conta. O hash vem do último item de `urn:xmpp:avatar:metadata` (ator `true`, sem checar acesso: o hash aparece mesmo com a foto privada).
- O módulo avisa `urn:xmpp:pep-vcard-conversion:0` no disco da conta (o Conversations usa isso para saber se deve reenviar a presença às salas).

## Publicar

| | Conversations | Monal (isaCloud) |
|---|---|---|
| Ordem | `data` e depois `metadata` | igual |
| Modelo de acesso | `NodeConfiguration.OPEN` ou `PRESENCE`, nas duas publicações | `open` ou `presence` (`avatarAccessModel`), nas duas publicações; também reconfigura os nós sozinho (`applyAvatarVisibility`) |
| `info` | `id`, `type`, `bytes`, `width`, `height`, `url` (envio HTTP, propósito "profile") | `id`, `type` (`image/jpeg`), `bytes` |
| Presença depois | reenvia a presença às salas, só se o servidor tem a conversão PEP→vCard | `sendPresence` e `sendPresenceToJoinedMucs`, sempre |
| Ler a visibilidade | `getPepAccessModel`, lendo a configuração do nó `data` | lê a configuração do nó `metadata` |

Nada disso explica a falha. Diferenças sem efeito sobre o Converse.js: `width`/`height` e a versão com `url` (o Converse.js não os usa).

## Ler

| | Conversations | Converse.js | Monal (isaCloud) |
|---|---|---|---|
| Contato (com presença) | PEP: `fetchAndStore` (metadata e depois data), com cache por hash | `vcard-temp` + hash da presença (XEP-0153) | PEP (`MLPubSubProcessor`, `avatarHandler`) |
| Quem não é contato, em sala | hash da presença da sala (`handleVCardUpdate`) e `vcard-temp` do ocupante (`retrievePhotoCacheException`); confere o SHA-1 com o hash da presença; guarda falhas (`IllegalStateException`, erro do IQ) numa cache | hash da presença da sala (`image_hash` do ocupante) e `vcard-temp` do JID real, ou do ocupante se a sala for anônima; **busca uma vez só** | **não lê** (item "Avatares de quem não é contato" no roadmap) |
| Avatar da sala | hash em `muc#roominfo_avatarhash` e `vcard-temp` da sala | `vcard-temp` da sala (única que se atualiza, de 7 em 7 dias) | `vcard-temp` da sala (`MLMucProcessor`) |
| Exige `type` | não | **sim**: `avatar.js` só desenha se houver `image_type` e imagem | não se aplica |

O ponto do Converse.js está em `src/headless/plugins/vcard/api.js` (`get`): se o modelo já tem `vcard_updated` ou `vcard_error`, só continua quando existe uma sala com esse JID (`chatboxes.get(jid)`) e `force` é verdadeiro; para uma pessoa devolve `null`. O `onOccupantAvatarChanged` e o `handleVCardUpdatePresence` chamam `api.vcard.update(..., true)`, mas esse `true` não adianta para quem não é sala. O mesmo código está no bundle do servidor (v13.0.1).

## Como confirmar (confirmado em 26/10/2026)

Resultado: numa janela anônima do Converse.js, com cache vazio, a foto pública de uma conta apareceu direito nos canais onde ela fala. A publicação do app está certa; a falha era a cache do `vCard` de quem já tinha olhado antes.

1. Abrir o Converse.js do servidor numa janela anônima (cache vazio) com uma conta que não seja contato da dona da foto e entrar numa sala em que ela fala (ou abrir a lista de ocupantes). Se a foto aparecer, a causa é a cache do `vCard`.
2. No navegador onde a foto não aparecia: limpar os dados do site, ou apagar a chave `<jid>-converse.vcards` (localStorage/IndexedDB), e recarregar.
3. Conferir direto o que o servidor responde: `GET https://isacloud.im/pep_avatar/<usuario>` (200 com `image/jpeg` quer dizer `open` nos dois nós).

## O que fazer

- **Nada no app para o Converse.js**: a publicação já está correta; o que falta é a cache do navegador de quem já tinha buscado o `vCard` vazio. Quem vê a conta pela primeira vez depois da foto pública já a recebe.
- **No servidor (opcional)**: não há como forçar o Converse.js a perguntar de novo. Uma saída seria um módulo que, junto da mudança de hash, avisasse o cliente, mas o Converse.js ignora. Melhor deixar como limitação conhecida e avisar nos textos do app que quem já viu a conta antes pode precisar limpar o cache do Converse.js.
- **No Monal**: o item de ler a foto de quem não é contato pode seguir o desenho do Conversations: hash da presença da sala (`x/photo`), `vcard-temp` do ocupante (JID real quando a sala mostra, senão `sala/apelido`), conferência do SHA-1 e guardar a falha por um tempo.

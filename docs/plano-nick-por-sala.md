# Plano: apelido (nick) por grupo e canal

Status: **implementado em 26/10/2026 nos 3 passos abaixo (passos 1 a 3 testados nos simuladores; falta iPhone, grupo privado e a rotina de 4 a 5).** O resultado e as lições estão em `docs/decisoes.md` ("Apelido por grupo e canal"). O texto abaixo é o plano original. Meta: a pessoa escolhe um nick diferente em cada grupo ou canal, sem mexer no nome de exibição da conta (o `nick` do PEP, `rosterName`). Contexto da tentativa anterior, revertida: `docs/decisoes.md` ("Nick por sala: tentado e revertido").

## 1. O que já existe (e o que isso muda na conta)

- **O nick por sala já é guardado por sala.** `buddylist.muc_nick` (lido primeiro) e `muc_favorites.nick` (reserva); `DataLayer ownNickNameforMuc:` lê, `updateOwnNickName:` grava a primeira tabela e `addMucFavorite:` a segunda. O nome da conta só entra como valor inicial, em `MLMucProcessor calculateNickForMuc:`, quando a sala ainda não tem nick. **Não precisa de coluna nem migração**: "nick personalizado" é só um nick diferente do da conta. "Voltar ao padrão" = gravar o nome atual da conta.
- Mudar o nome de exibição da conta **não toca nas salas** hoje, e deve continuar assim (foi o erro da tentativa anterior: propagar para todas).
- O **bookmark** (XEP-0402, `urn:xmpp:bookmarks:1`) já carrega um `<nick/>` por sala. É o lugar certo e é o que o Conversations usa.

## 2. Por que o bookmark é obrigatório (e não opcional)

`MLPubSubProcessor bookmarks2Handler` (tipo `publish`), para uma sala já conhecida, **compara o nick do bookmark com o local e, se diferir, grava o do bookmark no banco e reenvia presença** (≈ linhas 290 a 305). Esse handler roda também na atualização forçada de bookmarks depois do catch-up de uma reconexão sem retomada (`handleCatchupDone`).
Conclusão: se trocarmos o nick só localmente, **a próxima reconexão desfaz a troca** com o valor antigo do servidor. Logo, a troca só está "pronta" quando o bookmark no servidor tiver o nick novo. Esta é a parte de maior risco (lições 2, 3 e 5 da tentativa anterior).

Armadilhas do código atual, lidas em `handleBookmarks2FetchResult`:
1. Para sala já bookmarkada com `autojoin=true`, o item buscado é **republicado como veio**; o nick local só é escrito quando `autojoin` é falso ou quando a sala não está no bookmark. Ou seja, nenhuma atualização genérica atual leva o nick novo para o servidor.
2. Toda atualização genérica (`updateBookmarks`: primeira entrada numa sala, saída, mutar, fixar) busca **todos** os itens e republica **todos**. Se ela buscar antes da nossa publicação e republicar depois, **sobrescreve o nick novo com o antigo** (corrida de ida e volta de rede). Foi o que fez "todos os aparelhos voltarem".
3. A publicação do bookmark gera uma notificação PEP de volta para **a própria conta, em todos os aparelhos**. Ela só é inofensiva se o banco local já tiver o nick novo quando a notificação chegar (senão o handler "corrige" para o antigo).
4. Sobre outro aparelho: o ramo que reage a nick diferente usa `sendJoinPresenceFor:`, que põe a sala no estado "entrando" (`_joining`, com timer de ociosidade de 30 s). Numa sala em que já estamos, isso mistura "troca de nick" com "entrada": a resposta do servidor à troca (duas presenças, ver 3) seria lida como entrada concluída (refaz catch-up MAM, listas de membros, possivelmente `updateBookmarks`) e o timer sobra no banco, que é a origem do aborto "Spurious idle timer firing!" já visto no `.dev`.

## 3. Protocolo (XEP-0045, seção 7.6)

- Troca: presença **sem** `<x xmlns="…muc">` (o `joinRoom:withNick:` do app põe `<history>`, não serve) para `sala@serviço/novo-nick`. Incluir o hash de avatar como `sendPresenceToJoinedMucs` faz (`XMPPPresence initWithHash:`), senão a foto some para os outros.
- Sucesso: o serviço manda **duas** presenças: (1) `unavailable` de `sala/nick-antigo` com `status 303` + `110` e `<item nick='novo'>`; (2) `available` de `sala/nick-novo` com `110`.
- Erros: **409** `conflict` (nick em uso), **406** `not-acceptable` (nick reservado/registrado, ou a sala bloqueia troca), **400** `jid-malformed` (nick inválido), `resource-constraint`/rate limit (mod_muc_limits). O erro volta com `from` = `sala/nick-novo`.
- `210` pode vir com um nick **diferente** do pedido (o serviço normaliza): vale o que o servidor devolveu, não o digitado.
- Hoje o código **não trata 303** (cai em "não tratado" em `handleStatusCodes`). A presença `unavailable`+110 de quem não está "entrando" é ignorada ("non-joining muc presence"), o que é o comportamento certo; o problema só aparece se a sala estiver marcada como "entrando" (item 4 acima).
- Outros pontos do código que leem o nick atual como identidade: ping da sala (`ping.toResource`), comparação de status 301/307/322/332, `MLMessageProcessor` (mensagem própria) e `xmpp.m` (`actualFrom` ao enviar). Enquanto o banco tiver o nick antigo e o servidor o novo, o **ping dá `item-not-found`** (o código já prevê isso: "occupant just changed their name… do nothing").

## 4. Desenho proposto

### 4.1 Núcleo: `changeNick` no `MLMucProcessor` (idempotente, sem estado de "entrando")
- `-(void) changeNickOfMuc:(NSString*) room to:(NSString*) nick` chamado **só pela fila de recepção da conta** (lição 4: da UI travou o app). A UI usa o mesmo padrão dos outros ajustes de sala (`promisifyMucAction` + `addUIHandler:forMuc:`), com o trabalho despachado para a fila certa.
- Estado novo `_nickChanging[room] = {pedido, timer}`; **um por sala**, ignorar pedido novo enquanto houver um. Timer de 15 s com a mesma classe de timer de ociosidade, **cancelado em todos os caminhos** (sucesso, erro, timeout, saída da sala) para não repetir o aborto de timer sobrando.
- Se a sala **não está entrada** (`!isJoined`): não há presença a mandar; gravar o nick no banco e publicar o bookmark (4.2); a próxima entrada usa o nick novo.
- Se **está entrada**: mandar a presença de troca; **gravar no banco só quando chegar a presença nova (`available`, 110, `from` = nick pedido ou o devolvido pelo 210)**; erro 409/406/400/timeout: limpar o estado, não gravar nada, chamar o handler de UI com mensagem traduzida.
- Tratar o 303 explicitamente (ignorar o `unavailable` do nick antigo como "não é saída"), sem tocar em `_joining`/`_joined`.
- Depois do sucesso: `updateOwnNickName` + `addMucFavorite` (as **duas** tabelas), `kMonalContactRefresh` (o `MLContact` guarda `accountNickInGroup` em cache), e só então o bookmark.

### 4.2 Bookmark: publicar **só aquele item**, em ordem
1. Buscar **só o item da sala** (`fetchNode … withItemsList:@[room]`), nunca a lista inteira.
2. Trocar o `<nick/>` (criar o item completo como o ramo `toAdd` faz se não existir) e publicar **só esse item**, com as mesmas `publish-options` do código atual.
3. **Ordem fixa:** banco local atualizado → publicação (assim o eco PEP não "corrige" para trás).
4. **Proteção contra a corrida (item 2 da seção 2):** conjunto `_nickBookmarkPending` com as salas cuja publicação ainda não foi confirmada; em `handleBookmarks2FetchResult`, para sala nesse conjunto, escrever o **nick local** no item em vez de republicar o do servidor; remover do conjunto em `bookmarks2Published` (sucesso). Alternativa mais simples e mais lenta: enfileirar as atualizações genéricas enquanto houver publicação de nick pendente.
5. Uma publicação por troca; nada de `updateBookmarks` extra (lição 6: "uma só atualização depois da última resposta").

### 4.3 Outros aparelhos: adotar, sem "entrar"
- Trocar o ramo "that changed nickname" de `bookmarks2Handler` (sala já conhecida) para chamar `adoptNick`: gravar nas duas tabelas e mandar a **mesma presença de troca** do 4.1, sem tocar em `_joining`. É idempotente: se o servidor já moveu a sessão (mesmo ocupante), a presença é só uma presença normal; se o aparelho está como ocupante separado (lição 1 da tentativa anterior, comportamento observado no Prosody), a presença o move.
- Aparelho offline ou reinstalado: ao reconectar, a atualização forçada de bookmarks (`handleCatchupDone`) já aplica o nick do servidor, e `handleSessionInit` entra nas salas pelo `muc_favorites`. Como o bookmark já terá o nick novo, converge sozinho.
- Aparelho com a conta desativada e reativada (lição 5): entra pelos bookmarks do servidor; só funciona se o bookmark estiver certo, daí a ordem do 4.2.

### 4.4 Tela
- `ContactDetails.swift`, seção da sala (grupo e canal, só se a sala está entrada ou tem bookmark): linha "Seu apelido neste grupo/canal" (`TextField` com o nick atual), botão "Salvar" e botão "Usar o nome da conta". Estado de carregamento e mensagem de erro com o padrão dos outros ajustes da sala.
- **Validação local antes de enviar:** sem espaços nas pontas, não vazio, até ~100 caracteres (o servidor aceita até 1023 bytes na parte de recurso, mas nicks enormes quebram o layout), sem `/` e `@` no início ou meio, sem quebras de linha; mostrar o texto do servidor para 409 ("já está em uso neste grupo") e 406 ("este apelido é reservado ou a sala não permite trocar").
- Nada muda na tela de edição de conta nem no `rosterName`.
- Traduções pt-BR novas em `isaCloud/localization` (regra do `docs/traducoes.md`); texto novo que o simulador mostrar em inglês será avisado.

### 4.5 Efeitos colaterais a conferir (não são código novo, mas mudam de comportamento)
- **Mensagens antigas minhas** sem occupant-id no servidor: `MLMessageProcessor` calcula "mensagem própria" pelo nick atual quando não há occupant-id nem JID real; depois da troca, **mensagens recebidas via MAM com o nick antigo seriam tratadas como de outra pessoa** (notificação de mensagem própria). Com occupant-id (Prosody atual) não há problema. Conferir quais dos serviços usados (`conference.isacloud.cc`, `canais.xmpp.social.br`, `canais.voz.social.br`) anunciam `urn:xmpp:occupant-id:0`.
- **Menções:** "só menções" (`MLNotificationManager`) e a contagem de não lidas com menção (`DataLayer`, `LIKE '%'||muc_nick||'%'`) passam a usar o nick novo; menções feitas ao nick antigo deixam de contar.
- **Reações** guardam o nick da época (`muc_nick` na tabela `reactions`); as antigas continuam com o nick antigo.
- **Participantes e hats** são por nick; a presença `unavailable` do nick antigo remove o registro antigo e a nova cria o novo (já funciona hoje).
- **Conversations e outros clientes** leem o `<nick/>` do bookmark; devem seguir a troca.

## 5. Arquivos a mexer (e atrito com o merge do Monal)

| Arquivo | Mudança | Atrito |
|---|---|---|
| `MLMucProcessor.m/.h` | `changeNick`, `adoptNick`, estado e timer, tratamento do 303/409/406, erros de UI | médio (arquivo grande do Monal; manter tudo em blocos "isaCloud:") |
| `MLPubSubProcessor.m` | trocar o ramo de nick do `bookmarks2Handler`; nick local nos itens pendentes em `handleBookmarks2FetchResult`; publicação de item único | **médio a alto** (é o trecho que mais muda no Monal) |
| `ContactDetails.swift` | linha e validação | baixo (já tem blocos "isaCloud:") |
| `Localizable.strings` (pt-BR) | textos novos | baixo |
| `DataLayer.m` | **nenhum**, salvo um helper se quisermos gravar as duas tabelas numa transação | baixo |

## 6. Plano de entrega em passos, cada um testável sozinho

1. **Adotar (receber).** Trocar o ramo do `bookmarks2Handler` por `adoptNick` (item 4.3). Teste: mudar o `<nick/>` do bookmark à mão (outro cliente ou `ArtifactData`/ferramenta XMPP) e ver o app seguir sem estado "entrando" e sem timer sobrando. Risco baixo e útil por si só.
2. **Trocar (enviar), com bookmark ligado.** `changeNick` + 303 + erros (4.1) e o bookmark de item único (4.2). Teste com **um** aparelho e **uma conta de teste**.
3. **Tela** (4.4) e traduções.
4. **Dois aparelhos** (iPhone + simulador) e **Conversations**: convergência, reativar conta, reinstalar, offline durante a troca.
5. Documentação (`docs/decisoes.md`, roadmap, changelog) e build.

Pausas obrigatórias: depois do 1 e do 2, **parar e conferir** antes de continuar.

## 7. Matriz de testes

Um aparelho: grupo privado; canal público; troca simples; nick em uso por outra conta (409); nick reservado (406, se algum serviço aplicar); nick vazio/espaços/emoji/muito longo; trocar duas vezes seguidas; trocar com a sala fora de linha; matar o app no meio; sair e entrar na sala; "Usar o nome da conta".
Dois aparelhos: A troca com B conectado; A troca com B offline; B reinstalado; B com a conta desativada e reativada; trocas quase simultâneas (aceitar "última publicação vence", sem laço de volta).
Efeitos: mensagem minha no histórico depois da troca (ida e MAM); menção ao nick novo e ao antigo em "só menções"; reação minha antes/depois; lista de participantes; foto na sala depois da troca (hash na presença).
Plataformas: simuladores iOS 18.6 e iOS 27 e iPhone; Prosody (`conference.isacloud.cc`) e os dois serviços de canais públicos.
Segurança dos dados: **antes de testar, exportar os bookmarks da conta** (item `urn:xmpp:bookmarks:1`) e testar com uma **conta de teste**, não com a conta principal, porque um erro afeta os bookmarks de todos os aparelhos e clientes dela.

## 8. Esforço e risco

| Parte | Esforço | Risco |
|---|---|---|
| Adotar nick por bookmark (passo 1) | 2 a 3 h | baixo |
| `changeNick` + 303/erros/timer (passo 2, protocolo) | 4 a 6 h | médio (máquina de estados; timer) |
| Bookmark de item único + proteção contra corrida | 4 a 6 h | **alto** (causa da tentativa anterior) |
| Tela, validação, traduções | 3 a 4 h | baixo |
| Testes de unidade (validação do nick, montagem do item do bookmark) | 2 a 3 h | baixo |
| Testes manuais em 2 aparelhos e 3 serviços, correções | 6 a 10 h | médio |
| **Total** | **~3 a 4 dias úteis focados** (o roadmap dizia "meio dia a um dia", que só cobria o protocolo) | |

## 9. Alternativas e por que não

- **Só local (sem bookmark):** desfeito na próxima reconexão (seção 2).
- **Sair e entrar com o nick novo:** apaga bookmark, fixação e silenciar da sala (`deleteMuc`) e mexe no histórico; pior que trocar o nick.
- **Nick só na entrada ("Entrar como…") e sem troca depois:** bem mais simples e de baixo risco (escrever o nick no primeiro bookmark já existe no ramo `toAdd`), serve de **versão 1 mínima** se quisermos entregar rápido; não resolve quem já está nas salas.
- **Trocar tudo ao mudar o nome da conta:** foi o que falhou; fora de escopo.

## 10. Perguntas abertas (decidir antes de começar)

1. Valor padrão para salas novas: continua o nome da conta (hoje) ou perguntar na entrada?
2. Mostrar "Voltar ao nome da conta" também na tela de edição de conta (ex.: "usar em todas as salas")? Recomendo **não** (foi o que deu errado).
3. Aceitar a janela curta em que o mesmo usuário aparece com dois nicks (aparelho A novo, aparelho B antigo) até B receber o bookmark?
4. Os serviços de canais do isaCloud aplicam reserva de nick (406) ou limite de taxa? Verificar na configuração do Prosody antes dos testes.

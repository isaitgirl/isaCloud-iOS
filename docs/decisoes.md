# Decisões de projeto

Registro do **porquê** das escolhas feitas no fork: decisões de produto, de código e do fork do ExyteChat, e o que foi descartado e por quê. Para quem abrir uma sessão nova (ou outra pessoa) não precisar redescobrir.

- O que está feito, em andamento ou pendente, com datas e resultados de teste, fica no `ROADMAP.md` (toda decisão daqui tem uma linha lá). O histórico de cada build fica no `CHANGELOG.md`.
- Dados sensíveis ficam em `isaCloud/local/NOTAS-LOCAIS.md`, nunca aqui.

## Fork do ExyteChat (25/10/2026)
- **Decisão:** o chat usa o fork `isaitgirl/ExyteChat`, **branch `isaCloud`** (cadeia: `exyte/Chat` → `monal-im/ExyteChat` → nosso; nunca a `main`). Rotina de atualização, revisão em uso e o que o fork muda: `docs/exytechat-fork.md`.
- **Por quê:** o balão é desenhado pela biblioteca (`Text` de `AttributedString`), sem ponto de extensão. Os primeiros ajustes pediam mudar o balão por dentro: ícones de status maiores (de 10 para 16 pt, na base do balão) e citação com uma barra vertical contínua em vez de um `│` por linha.
- **Alternativas descartadas:** (a) trocar `│` por caractere de bloco (testado: barras grossas e ainda segmentadas); (b) balão próprio via `messageBuilder` para toda mensagem com citação (1 a 2 dias e risco de regressão: reproduzir avatar, nome, hora, status, reações, links, menu e swipe); (c) esperar a XEP-0461 do Monal (sem previsão).
- **Regras:** mudanças pequenas, comentadas com "isaCloud:" e em commits separados, para o rebase ser fácil; se o upstream trouxer o recurso, descartar o nosso commit. Toda mudança entra por PR de uma branch nova para `isaCloud`, no fork e no app (o PR do app só depois do PR do fork). Depois de cada commit no fork, atualizar a revisão fixada no `Package.resolved` do app.

## Modal de quem reagiu (25 e 26/10/2026, do Jejê)
- **Decisão:** tocar nas reações de um balão abre uma modal com a lista de quem reagiu e com qual emoji, com filtro por emoji, e o balão agrupa as reações por emoji, com contagem. A lista que aparecia no topo ao segurar a mensagem foi removida.
- **Por quê:** o balão mostrava um círculo por reação (duas pessoas com ❤️ davam dois corações) e a lista do toque longo tinha layout ruim e só aparecia segurando a mensagem. É desenhado pelo ExyteChat, então é a mudança nº 4 do fork, com um PR par no app.
- **Reagir pela própria modal (26/10/2026):** a modal tem uma linha por pessoa (um fulano com dois emojis não aparece duas vezes), em ordem alfabética, e a linha "Você" é sempre a primeira, mesmo sem reações. Nela, tocar num emoji remove a reação e o "+" abre o teclado de emojis do sistema para adicionar. Descartamos a faixa de emojis no topo e o flutuante de emojis. O teclado vem de um campo de texto invisível que pede o teclado de emojis (o iOS não tem API para abri-lo direto); se o teclado de emojis estiver desativado nos ajustes, cai no teclado normal. Não testado no iOS 18 nem em iPhone real.
- **Prints:** só em simuladores sem o defeito de emoji dos runtimes iOS 26.1 e 26.3.1 (ver `docs/troubleshooting.md`).

## Menu da mensagem mais rápido (26/10/2026)
- **Decisão:** toque longo de 0,3 s (mudança nº 3 do fork, em `UIList.swift`) e animação do menu de 0,15 s (`.messageMenuAnimationDuration(0.15)` em `ChatView.swift`, parâmetro que a biblioteca já tem). Os GIFs usam os mesmos 0,3 s em `GifMessageBubble`.
- **Por quê:** o padrão (0,5 s, sentido como ~0,6 s na lista, mais ~0,5 s de etapas e animação do menu) era "nitidamente" mais lento que o WhatsApp. Experimentos de 0,3, 0,2 e 0,15 s no iPhone; 0,15 s foi aprovado ("bem melhor").
- **Se abrir sem querer ao rolar:** subir os valores (em `UIList.swift` e em `GifMessageBubble`).

## Visibilidade da foto da conta (25 e 26/10/2026)
- **O que é:** chave "Foto Visível para Todos" em Editar Conta. Desligada (padrão) = só contatos (PEP `pubsub#access_model` = `presence`); ligada = qualquer pessoa (`open`), como no Conversations. Vale só para os nós de avatar (`urn:xmpp:avatar:data` e `urn:xmpp:avatar:metadata`); o nome de exibição (`http://jabber.org/protocol/nick`) continua em `presence`, por decisão da Isadora.
- **Sem aviso ao ligar**, por decisão da Isadora (a primeira ideia era um alerta de privacidade).
- **A chave mostra o servidor:** ao abrir Editar Conta o app lê o `pubsub#access_model` do nó de metadados (`fetchAvatarVisibilityWithCompletion:`, `xmpp.m`); o valor guardado no aparelho (`avatarPublic.<conta>`) é só uma cópia, usada ao publicar uma foto nova.
- **Mudar só a visibilidade não reenvia a foto (revisto em 26/10/2026).** O app reconfigura os dois nós (`applyAvatarVisibility`, dois pedidos pequenos) e, só se os nós não existirem no servidor, publica a foto que tem localmente. Antes (build 15) a foto era republicada ao salvar a visibilidade; foi trocado porque (1) publicar com um modelo de acesso diferente do nó faz o servidor responder "precondition not met" e o app enviava a imagem uma segunda vez, e (2) cada upload leva ~15 s num servidor que limita o cliente a poucos kB/s (era 3 kB/s, ~17 s para 52 KB; passou para 6 kB/s). Ao trocar a foto e a visibilidade juntas, a visibilidade é aplicada primeiro e a foto depois.
- **Avatar nas presenças:** o servidor (`mod_vcard_legacy`) injeta o hash (XEP-0153) em toda presença que sai da conta e responde o `vcard-temp` dos ocupantes, então o app não manda `<photo>` nem responde vCard. Falta só **mandar uma presença nova** depois de publicar ou apagar o avatar, porque as salas só veem o hash em presença nova (`avatarMetadataPublished` e `avatarDeleted`, `MLPubSubProcessor.m`, chamam `sendPresence` e `sendPresenceToJoinedMucs`).
- **Por aparelho:** com a mesma conta em dois aparelhos, quem publicar um avatar por último aplica a escolha do seu aparelho. Limitação aceita por ora.
- **Por que importa:** só quem escolhe ser público pode ter o avatar visto por quem não é contato (grupos e canais); ver "Avatares de quem não é contato" em "Por avaliar" no roadmap.

## Apelido por grupo e canal (26/10/2026)
Plano e raciocínio completos: `docs/plano-nick-por-sala.md`.
- **Decisão:** cada sala tem o seu apelido, sem mexer no nome de exibição da conta. Ele fica em `buddylist.muc_nick` e `muc_favorites.nick` (nada de coluna nova) e no `<nick/>` do bookmark da sala. Salas novas continuam entrando com o nome da conta. Tela: Detalhes do grupo/canal → "Nome de Exibição" (`MucNickEditView`, `ContactDetails.swift`), com o atalho "Usar o Nome da Conta" (pequeno e em preto, para o "Salvar" ser o destaque). **Descartado: "usar em todas as salas"**, por ser o que quebrou na primeira tentativa. Aceito: por instantes dois aparelhos podem aparecer na sala com apelidos diferentes, até o outro receber o bookmark.
- **O que a primeira tentativa errou e como a segunda evita:** (1) o erro de um pedido de troca em sala já entrada caía no ramo "erro permanente" de `processPresence`, que **apaga a sala dos favoritos e dos bookmarks**; agora `handleNickChangePresence` intercepta antes (troca pendente só na memória, prazo de 20 s, sem timer no banco); (2) trocar o apelido só no aparelho é desfeito na reconexão seguinte, porque o `bookmarks2Handler` copia o apelido do bookmark; por isso a troca confirmada pelo servidor publica **só o item daquela sala** (ordem: banco, depois bookmark) e as atualizações gerais de bookmarks levam o apelido local enquanto a publicação está pendente (`_nickBookmarkPending`); (3) outros aparelhos seguem o bookmark com `adoptNick:` (presença de troca, que grava no banco só depois da confirmação), em vez do fluxo de "entrada" (`sendJoinPresenceFor:`) do Monal, que deixava a sala como "entrando".
- **Servidor (Prosody):** a troca é por sessão (cada aparelho é uma sessão); `muc_limits` está desligado em todos os serviços; `enforce_registered_nickname` não está definido (o 406 só ocorre se alguém reservar um apelido e a opção ligar); o 409 vem quando outro JID usa o apelido.
- **Lição de processo:** ao limpar logs temporários com expressão regular, conferir o diff; uma linha `if` sobrando fez toda presença própria virar "confirmação" e republicar o bookmark com o apelido antigo.

## Balão dos GIFs é do app (23 a 26/10/2026)
- O ExyteChat mostra GIF como imagem parada; o app desenha o GIF animado em `GifMessageBubble` (`GifPickerView.swift`), via `messageBuilder`. Efeito colateral: o balão padrão (avatar, horário, status, reações, menu) some. Reproduzimos essas partes no `GifMessageBubble`; **se o balão padrão ganhar algo novo, conferir os GIFs.**

## Ícones de status das mensagens
- Convenções (relógio, círculo vazado cinza, rosa, cheio, exclamação) e cores: tabela no `CHANGELOG.md` (build 13). O estado "servidor recebeu" é desenhado no app (`IsaCloudStatusIcons`, `GifPickerView.swift`) porque a imagem do ExyteChat para esse estado é vazia.

## iOS 27 e iOS 18 (24 a 26/10/2026)
- Builds e testes sempre do iOS 18 ao 27, no simulador de cada versão (um app compilado para o iOS 27 não abre no 18: falta `libswiftCompatibilitySpan`).
- iOS 27: o app usa o ciclo de vida por cenas (`SceneDelegate` repassa os eventos); o vigia de travamento do KSCrash fica desligado; o aviso de "primeiro plano" na abertura não espera filas (`nowForegroundedAtLaunch`). Detalhes e como investigar: `docs/troubleshooting.md`.
- Seletor de fotos do chat: o do sistema (`PHPicker`), porque o do ExyteMediaPicker não rola no iOS 27.
- Seletores das telas de ajustes: margem direita de 26 pt em `MLSwitchCell.xib` (no iOS 27 o conteúdo da célula passa da borda visível; 26 pt ficou bom nos dois sistemas). É uma mudança de uma linha num xib do Monal: pode conflitar em merge.

## Pedidos de contato: onde aparecem (26/10/2026)
- **Decisão:** os pedidos ficam **no topo da lista da tela de Contatos**, entre os filtros e os contatos, e o ícone de Contatos mostra um selo **preto com o número em branco** ("9+" a partir de dez; o vermelho não contrastava com os bonequinhos rosa). O box de pedidos **saiu da tela "Adicionar contato"**. Aceitar ou recusar **não sai da tela** (no Monal, aceitar abria a conversa), para responder vários pedidos seguidos; abrir a conversa ficou no menu "…". O "+" da tela de Contatos **não tem bolinha**, por decisão da Isadora.
- **Alternativas descartadas:** o box entre a busca e os filtros (faixa fixa no topo, com altura variável e espaço permanente) e uma bolinha sem número.

## Várias contas: como aparecem (26/10/2026)
- **Decisão:** a lista de contas mostra o **avatar no lugar do check** (conta desativada: avatar esmaecido com marca de pausa, para não perder a informação que o check dava); o botão do avatar na tela principal mostra **até dois avatares sobrepostos** (a primeira conta da lista na frente) e um selo preto "+N" para as demais. Só contas ativadas, na ordem da lista de Configurações.
- **De qual conta é cada conversa:** o JID da conta aparece **logo abaixo do nome** (conversas e Contatos), em cinza e menor, sempre que há 2 ou mais contas ativadas, mesmo que o contato não se repita; a última mensagem fica um pouco mais abaixo. Escolhido pela simplicidade, depois de comparar com selo de mini-avatar no avatar, filtro pelo botão do perfil, cor por conta (Cheogram) e JID só nos casos repetidos. A linha é criada em código em `MLContactCell` (sem mexer no xib do Monal) e a altura da linha passa de 60 para 74 pt com várias contas. O selo e o filtro ficam como ideias para depois.
- **Descartado:** um ícone genérico de "várias contas" (perde o avatar) e a foto de uma conta só com uma bolinha de contagem.

## Avisos de erro: o que vira banner (26/10/2026)
- **Decisão:** só impede o uso → banner (e, se grave, notificação). Falha de fundo que não impede nada (sala de outro servidor que não responde, entrada temporariamente impossível) vira erro "quiet": só log, sem banner e sem notificação (`HelperTools postQuietError:`, `MLMucProcessor handleBackgroundError:`). Avisos não graves repetidos da mesma conta: no máximo um a cada 10 minutos (`showConnectionStatus:`, `MonalAppDelegate.m`). Se uma tela espera pela sala (UI handler), ela continua recebendo o erro.
- **Por quê:** o banner amarelo/vermelho de dez segundos aparecia mesmo para falhas inofensivas e repetidas a cada ping; o timeout de entrada era grave e gerava até notificação com som fora do app.
- **Fica para depois (nice to have):** a lista "Avisos do Sistema (n)" em Configurações (ver o roadmap, linha 54).

## Código do Monal que não alteramos sem validar (26/10/2026)
- **Exceção feita:** `showWarningsIfNeeded` (`ActiveChatsViewController.m`) pula a conta em vez de lançar exceção quando o objeto `xmpp*` ainda não existe, porque o app caía na abertura no iOS 27 (a tela inicial é montada durante a espera pela extensão de notificações, antes de `didFinishLaunching` criar as contas). Os avisos são checados de novo no fim do catchup. Mudança de poucas linhas, com comentário "isaCloud:".
- `handleJoinTimeout` (asserção "Spurious idle timer firing!"), `DumpMemoryGraph` (`MLDelayedDealloc.m`, só em Debug) e a asserção ao remover conta (`MLMessage handleGlobalRefresh:`) são arquivos do Monal: só mexemos com validação da Isadora, por causa do merge. O TestFlight (Release) não tem o despejo de memória. Detalhes e correções possíveis: linha "Corrigir no Monal" em "Por avaliar" no roadmap.

## Descartado
- **Código de afiliado** (Tela "Tenho um código", `mod_invites` do Prosody): removido do roadmap por decisão da Isadora em 26/10/2026.
- **Aviso de privacidade ao ligar a foto pública** e **"usar o apelido em todas as salas"**: ver as seções acima.

## Convenções gerais
- Código em inglês, seguindo o Monal; textos para a pessoa em pt-BR pelo mecanismo de tradução (`isaCloud/localization`, regra em `docs/traducoes.md`). Mudanças que compliquem o merge com o Monal precisam ser validadas antes.
- Commits: só quando a Isadora pedir, com mensagem bem descritiva.

# Changelog do isaCloud para iOS

Mudanças do fork isaCloud sobre o Monal. A lista do que está feito e do que falta está em [ROADMAP.md](ROADMAP.md).

## Próximo build (ainda não enviado)

### Mudado
- **Logo novo no splash e nas telas de conta.** O splash (`Launch Screen.storyboard`) usa o logo "gordinho" do ícone (`docs/logo-isacloud-im-liquidglass-1024.png`, fundo transparente) num asset próprio, `SplashLogo`, em @1x/@2x/@3x de 140 pt com perfil sRGB: o PNG de 1024 px só em @3x não aparecia no splash do iPhone XR. "Adicionar uma conta" (`WelcomeLogIn`, antes "Boas vindas") e "Registrar" (`RegisterAccount`, que ganhou o logo ao lado do texto) usam o mesmo logo, com o texto alinhado ao topo e frases mais curtas; o título de "Registrar" ficou pequeno na barra, para a tela começar no topo como a de adicionar conta. O `AppLogo` antigo continua no topo das Configurações. Testado no `.dev` em 12/11/2026. Branch `feature/splash-logo-gordinho`.

## 0.0.1 (build 107) — 12/11/2026

Enviado ao TestFlight às 12:14. PR 69 do app (ExyteChat sem mudança, `3eb0aa1`).

### Mudado
- **Contatos abrem sem animação.** O botão de contatos da tela inicial apresenta a lista com `animated:NO` (`-[ActiveChatsViewController showContacts]`), sem a folha crescendo a partir do botão; fechar continua animado. Testado no `.dev` em 12/11/2026. Branch `feature/contatos-sem-animacao`.

## 0.0.1 (build 106) — 12/11/2026

Enviado ao TestFlight às 11:51. PR 68 do app (ExyteChat sem mudança, `3eb0aa1`).

### Corrigido
- **Pedidos de contato repetidos entre duas contas.** O pedido de volta (quem aceita manda `subscribed` + `subscribe`) virava pedido novo com notificação para quem tinha adicionado primeiro: em `xmpp.m`, o primeiro `if` do ramo `subscribe` também pegava `subscription=to`, e o aceite automático do Monal nunca rodava. Agora, com `to` ou `ask=subscribe`, o pedido é aceito sozinho (só `subscribed`, sem notificação). Descartar a notificação de pedido não conta mais como Recusar (antes chamava `removeContact:` e apagava o contato do roster), e Recusar (`-[MLXMPPManager rejectContactRequest:]`) só manda `unsubscribed` quando já adicionamos a pessoa. Novo selo "Aguardando aceite" na lista de contatos para quem ainda não aceitou o nosso pedido. Visto entre `poli2` (`.dev`) e `isadora@im` (produção) em 11 e 12/11/2026.

## 0.0.1 (build 105) — 11/11/2026

Enviado ao TestFlight às 20:14. PRs 66 e 67 do app (ExyteChat sem mudança, `3eb0aa1`).

### Adicionado
- **Novidades do isaCloud no topo da lista de conversas** (roadmap 170, como no Android). Depois de uma atualização, um item no `tableHeaderView` da lista mostra o que mudou nos builds desde a última abertura (instalação nova: só o build atual), com o balão 3D, selo "Novo", data, prévia e botão de arquivar com alerta de confirmação; some com filtro, conta oculta ou busca. Arquivar vale até o próximo build. A tela (SwiftUI) marca como lido, tem "Mostrar na lista de conversas" quando arquivado e link para o `CHANGELOG-USERS.md`; Configurações → Sobre → Novidades do isaCloud mostra todos os builds. O texto vem de `Monal/isaCloud-changelog.json`, gerado do `CHANGELOG-USERS.md` por `scripts/isacloud-generate-changelog-json.py` no `archive-testflight.sh` e no `isacloud-dev-device.sh` ("Próximo build" vira o `CURRENT_PROJECT_VERSION`). Estado em `UserDefaults.standard` (`IsaCloudChangelog.swift`). PR 67; análise em `docs/analise-novidades-na-lista.md`.
- **Convites de grupos e canais como solicitações pendentes** (roadmap 168, como no Android). O convite não faz mais o app entrar sozinho na sala: vira uma pendência com "Ingressar", "Recusar" e "Recusar e Bloquear", numa seção de Contatos depois dos pedidos de contato, e entra no selo do botão de contatos. Tabela própria `isacloud_pending_invites` no passo 8 da escada do isaCloud (escada do Monal intacta). Regras do recebimento (`-[MLMucProcessor isaCloudHandleInviteToRoom:...]`, roda também na NSE): ignora convites com mais de 30 dias, de bloqueados, da própria conta e de salas que estão nos favoritos; convite de quem não é contato só aparece com a opção nova **"Mostrar convites de desconhecidos"** (Privacidade, desligada por padrão); convite mediado com JID de ocupante conta como desconhecido; até 50 pendências por conta. Nome e tipo da sala vêm de um `disco#info` ao mostrar a linha. Recusar um convite mediado manda `<decline>` para a sala. PR 66. Análise em `docs/analise-solicitacoes-pendentes.md`.

### Corrigido
- **C22: convidar alguém para um canal (ou adicionar membro a um grupo) derrubava o app no iOS 27.** `promisifyMucAction` (código do Monal) rodava numa fila de fundo um bloco isolado à thread principal; agora roda na fila principal. Detalhes em `docs/analises-crashes.md`.

## 0.0.1 (build 104) — 11/11/2026

Enviado ao TestFlight às 15:20. PR 65 do app (ExyteChat sem mudança, `3eb0aa1`).

### Adicionado
- **Sair do grupo/canal mantendo na lista.** Sair nos detalhes pergunta, como no Android: "Remover da lista", "Manter na lista" ou "Cancelar". "Manter na lista" sai da sala (`leave:withBookmarksUpdate:NO keepBuddylistEntry:YES`), mantém a linha na buddylist e republica o bookmark com `autojoin="false"` (`-[MLMucProcessor leaveKeepingBookmark:]`, `keepBookmarkFetched`/`keepBookmarkPublished` em `MLPubSubProcessor`; `_keepBookmarkPending` impede que um `updateBookmarks` simultâneo retraia o item). Uma sala mantida na lista mostra "Ingressar" e "Remover da lista" nos detalhes; remover retrai o bookmark explicitamente (`removeKeptMuc:`), já que o `updateBookmarks` nunca retrai itens com `autojoin=false`. Um bookmark com `autojoin=false` desconhecido (outro aparelho, reinstalação) entra na lista sem join (disco com `withJoin:NO`). Branch `feature/sair-mantendo-na-lista`.
- **Estado de participação na lista de contatos.** Selos à direita, com os textos e as cores do Android: canal "Participante" (rosa) ou "Ingressar" (cinza), grupo de que a pessoa saiu "Não participando" (cinza); "Arquivado" passa a cinza. O endereço do canal fica em uma linha, cortado no meio.

### Corrigido
- **Contatos:** grupos e canais aparecem mesmo sem participar (o filtro de assinatura escondia salas fora de `muc_favorites`).
- **Contatos:** a ordem do mesmo contato ou sala em várias contas é estável; a conta desempata (antes alternava a cada atualização, porque a lista vem de um `Set`).

## 0.0.1 (build 103) — 11/11/2026

Enviado ao TestFlight às 10:20. PR 64 do app (ExyteChat sem mudança, `3eb0aa1`).

### Mudado
- **GIF enviado na maior versão de até 2 MB.** Antes ia sempre a maior (GIPHY `original`, até ~10 MB; KLIPY `hd`, até ~20 MB). Agora vale a primeira versão de até 2 MB pelo tamanho que a API informa (GIPHY: `original`, `downsized_large`, `downsized_medium`, `downsized`, `fixed_width`; KLIPY: `hd`, `md`, `sm`, `xs`); se nenhuma couber, vai a menor. Continua `.gif`. As listas de "em alta" salvas antes são ignoradas (arquivo `<provedor>-v2.json`).

## 0.0.1 (build 102) — 11/11/2026

Enviado ao TestFlight às 09:24. Hotfix do build 101 (ExyteChat sem mudança, `3eb0aa1`).

(O KLIPY e o cache da busca de GIF, PR 62, já estavam neste build; só a seção do changelog ficou para trás.)

### Adicionado
- **KLIPY como segundo provedor de GIF.** O GIPHY continua o padrão; o KLIPY aparece como opção quando o build tem a chave. Troca pelo menu da própria busca de GIFs ou em Anexos → GIFs (preferência `gifProvider`: `giphy` ou `klipy`, migrada em `MLXMPPManager` com padrão `giphy`). A chave vem de `isaCloud/local/klipy-api-key.txt` pelos scripts `archive-testflight.sh` e `isacloud-dev-device.sh`, que passam `KLIPY_API_KEY` ao build (`KlipyAPIKey` no `Monal-Info.plist`). Sem chave, a opção não aparece. Anúncios do KLIPY desligados no Partner Panel. Análise em `docs/analise-gif-klipy.md`. Branch `feature/gif-klipy`.
- **Cache da busca de GIF.** As duas chaves têm limite de 100 chamadas por hora. Cache HTTP próprio (`GifNetwork`, 100 MB em `Caches/gif-http-cache`) que segue os cabeçalhos dos servidores (API do KLIPY 6 h, prévias 1 a 7 dias), e o "em alta" de cada provedor salvo em `Caches/gif-trending` (página de 50, 6 h no KLIPY e 1 h no GIPHY, embaralhado a cada abertura). Logs com o prefixo `GIF cache:` para avaliar no `.dev`. A rolagem para em 3 páginas (`GifSearch.maxPages`). Validado no `.dev` em 10/11/2026: o KLIPY fez 6 chamadas em cerca de 16 aberturas e o GIPHY 1 em 6.

### Corrigido
- **App morto em segundo plano ao perder o sinal (C21, `0xdead10cc`).** Sem rede, a escrita do último ack ficava esperando para sempre o `nw_connection_send`; `-[MLStream close]` não cancelava a conexão e `cleanupSendQueue` esperava a escrita sem prazo, então o `disconnectAll` da tarefa de segundo plano nunca terminava e o app era suspenso com a trava de processo (crashes de 08/11, iPhone12,8, e 10/11, iPhone13,3, no elevador). Agora `-[MLOutputStream close]` cancela a conexão à força quando há escrita pendente, e a espera da escrita tem prazo de 15 s (depois disso cancela a conexão e segue). Branch `fix/c21-escrita-sem-prazo`. Detalhes em `docs/analises-crashes.md` (C21).

### Técnico
- **Registro do C20 liga mais cedo.** Passa a ligar no `kMonalWillBeFreezed` (`+[HelperTools isaCloudArmDbAccessRecording]`) em vez de só depois do `flushLogs` da suspensão, e desliga ao descongelar (`isaCloudDisarmDbAccessRecording`), inclusive quando o app volta sem ter sido suspenso. Segunda ocorrência do C20 (10/11 22:48) em `docs/analises-crashes.md`.
- **dSYM guardado a cada build** (`scripts/archive-testflight.sh`) em `~/Library/Developer/Xcode/Archives/isacloud-dsyms/build-N/`, para symbolicar os endereços das linhas `isaCloud C20:`.

## 0.0.1 (build 101) — 10/11/2026

Enviado ao TestFlight às 09:29. Hotfix do build 100 (ExyteChat sem mudança, `3eb0aa1`).

### Corrigido
- **App morto em segundo plano pelo próprio registro do C20 (`0xdead10cc`).** O registro de acesso ao banco com o app congelado montava a pilha com `callStackSymbols`, que symbolica (lento) e rodava dentro de transações do banco; o iOS suspendia o app com a trava na mão (crash de 10/11 08:56, iPhone14,7). Agora grava só os endereços de retorno e os endereços de carga do `monalxmpp` e do app, para symbolicar depois com `atos`. As duas fontes vistas no crash deixam de tocar no banco com o app congelado: `+[MLFiletransfer storeState]` (download em segundo plano terminando) grava o estado ao descongelar, e `updateAccountAvatar` da lista de conversas se atualiza ao descongelar. Branch `fix/c20-registro-sem-simbolos`. Detalhes em `docs/analises-crashes.md` (C20).

## 0.0.1 (build 100) — 09/11/2026

Enviado ao TestFlight às 17:15. PRs 56, 57, 58, 59 e 60 do app (ExyteChat sem mudança, `3eb0aa1`).

### Adicionado
- **Arquivamento duradouro de conversas, como no Android** (PR 1 do roadmap 134). Arquivar (swipe "Arquivar" ou o menu do Mac) passa a gravar `buddylist.archived` (migração 7 da escada do isaCloud, com `archived_updated` e `archived_pending` para a futura sincronização pelo PEP) em vez de apagar `activechats`. Por isso não marca mais as mensagens como lidas e a conversa fixada continua fixada. A lista de conversas, o badge, o contador por conversa e as não lidas ignoram as arquivadas. Grupo/canal arquivado fica totalmente mudo (nem a @ notifica, nem reações), continua na sala e não volta com mensagem nova nem ao entrar na sala; só volta pelo "Desarquivar" nos detalhes. Conversa 1:1 arquivada volta ao receber, abrir ou enviar (`addActiveBuddies`). Rótulo "Arquivado" com ícone na lista de Contatos, abaixo da conta; nos detalhes, a linha "Arquivado", o botão "Desarquivar" e as notificações mostradas como desativadas enquanto arquivado (o ajuste próprio volta ao desarquivar). Arquivar também apaga as notificações entregues da conversa. Conversas arquivadas antes desta versão voltam do jeito antigo e precisam ser arquivadas de novo uma vez. Testado pela Isadora no `.dev`. Decisões em `docs/decisoes-sincronizacao-arquivados.md`.
- **Olho para esconder as conversas de uma conta.** Na tela de contas (Configurações), cada conta ativa ganha um olho cinza antes da bolinha de status; tocar alterna entre visível (`eye`) e oculta (`eye.slash`). A lista de conversas, com ou sem os chips, mostra só as conversas das contas visíveis: a regra entra em `contactPassesChatListFilter` (vale também para mensagem nova) e, com conta oculta, a lista vazia diz "Nenhuma conversa nas contas visíveis". O estado fica só em memória de propósito (`+[ActiveChatsViewController setChatListAccount:hidden:]`): ao reabrir o app, todas voltam visíveis. Contador de não lidas, notificações e busca não mudam. A bolinha verde e o alerta laranja de reconexão ficaram menores (20 pt e símbolo 15), sem esticar. Branch `feature/olho-visibilidade-contas`; testado pela Isadora no `.dev`.
- **Busca por nomes mostra a conta de cada resultado.** Com mais de uma conta ativa, os resultados da aba "Nomes" da busca da tela inicial ganham a linha da conta (ícone + JID), como a aba "Mensagens" e a lista de Contatos; antes, o mesmo canal em duas contas aparecia duas vezes igual.
- **Merge do Monal/develop (24 commits, `8e30e1696`)**, branch `merge/monal-develop-2026-11`. Entram: correção de crash no catchup do MAM; bookmarks2 com o nome da sala (`name`); regra nova de identidade OMEMO (chave diferente para um aparelho já conhecido é recusada e o chat mostra um aviso, traduzido sem a palavra "ataque"); leitura de arquivos escolhidos no app Arquivos (acesso security-scoped); backscroll do MAM na versão do Monal (`markReachedMamArchiveTop` no `MLIQProcessor`); template do banco em 7.013 (igual ao piso da escada do isaCloud); flags novas de Swift. A compressão de mídia do Monal ficou de fora (fica a nossa). Nada do isaCloud foi desfeito. Testado pela Isadora no `.dev` (reconexões e modo avião).

### Corrigido
- **Crash ao voltar a conexão (C16, quarta ocorrência).** Ao desligar o modo avião com o app aberto, o evento de abertura da conexão que acabara de ser fechada podia rodar o bloco de login da conexão nova, ainda abrindo, e a asserção `Stream must be open` em `-[MLStream tlsVersion]` derrubava o app. O bloco do `NSStreamEventOpenCompleted` em `xmpp.m` agora só segue se o evento for do stream atual e ele estiver aberto; os outros são ignorados e o bloco espera o evento verdadeiro. Branch `fix/c16-open-completed-conexao-antiga`. Detalhes em `docs/analises-crashes.md` (C16).
- **Checagem de FTS5 com alarme falso em build para qualquer simulador.** `scripts/isacloud-check-fts5.sh` exigia exatamente uma ocorrência de `ENABLE_FTS5`, mas um binário com duas arquiteturas (x86_64 e arm64) tem duas; agora aceita uma ou mais.

### Técnico
- **Registro C20 de acesso ao banco depois do congelamento, e limpeza automática pausada com o app suspenso.** `MLSQLite` (`prepareQuery`, ponto comum de todo SQL, BEGIN incluído) grava em `isacloud-db-after-freeze.log` (grupo de apps), sem passar pelo log suspenso, até 30 linhas por suspensão e 64 KB: data, processo, fila, 80 caracteres do SQL (sem argumentos) e 12 frames. `signalResumption` e a inicialização despejam as linhas no log normal como `isaCloud C20:`. A flag `isaCloudSuspendedFast` não usa trava. A thread `im.monal.timeouts` não apaga mensagens por intervalo enquanto o app está congelado. Ver `docs/analises-crashes.md` (C20).

## 0.0.1 (build 99) — 09/11/2026

Enviado ao TestFlight às 12:51. PRs 53, 54 e 55 do app e PR 22 do fork do ExyteChat (`3eb0aa1`).

### Adicionado
- **Tamanho do arquivo nas fotos, vídeos e áudios da conversa.** Pílula no canto inferior esquerdo de fotos e vídeos (também no álbum), escondida durante o upload, e "0:42 · 120 KB" no balão de áudio, também depois de baixados ou enviados (`Attachment.size` e `Recording.size` no fork; `MLFiletransferInfo.size` no app). GIFs e figurinhas ficam sem (no GIF a pílula tapava a legenda). Análise em `docs/analise-tamanho-de-midias.md`; roadmap 162.
- **Fileira de reações do menu com os 6 últimos emojis usados (LRU).** Começa por ❤️ 👍 👎 😂 😨 🥲; adicionar uma reação move o emoji para o início (remover não muda a lista); o botão de outro emoji continua no fim; reações já postas que saíram da lista vão para o fim da fileira. Lista local ao aparelho, nas preferências (`RecentReactions.swift`, sem `@defaultsDB`); roadmap 163.
- **Compressão de vídeos da galeria (480p).** Vídeo escolhido na galeria acima de 512 KB vai em MP4 H.264 + AAC 480p (`AVAssetExportPreset640x480`), sem a localização (filtro de compartilhamento). Opção "Compressão de vídeos" em Anexos (Original ou 480p, padrão 480p). Sem duração máxima fixa: vale o limite de upload da conta (XEP-0363 `max-file-size`, lido do formulário do disco no Prosody e no ejabberd e guardado no estado da conexão). Vídeo da galeria que não cabe pela estimativa (480 kB/s em 480p) não é anexado, com alerta "Este vídeo passa do limite de X MiB do servidor". Antes de subir qualquer arquivo, o tamanho real é comparado com o limite (cobre o modo Original e um 480p maior que a estimativa). Recusa do servidor por tamanho (`not-acceptable`/"too large") mostra o limite em vez de "tente de novo". Vídeo gravado pela câmera também é convertido, e a gravação para sozinha no tempo que cabe no limite (`videoMaximumDuration`). Vídeo compartilhado de outro app é conferido pelo tamanho do arquivo antes de subir. A conversão só roda com o app aberto. Análise em `docs/analise-comprimir-videos.md`; roadmap 161. Em Anexos, os seletores de fotos e vídeo ficam na linha de baixo do título, e o padrão de fotos numa instalação nova passa a ser "Sempre". Testado no `.dev` (galeria, câmera curta, compartilhar); a parada automática da câmera ficou para depois.

## 0.0.1 (build 98) — 07/11/2026

Enviado ao TestFlight às 08:25. Branch `fix/primeiro-plano-apos-segundo-plano`.

### Técnico
- **Documentação de build e branches** (`docs/build-e-branches.md`): como criar branches de feature e de correção, inclusive em worktree separada (o que copiar do checkout principal: `Monal/Pods`, `rust/LibMonalRustSwiftBridge`, `rust/target`, chave do Giphy), e os problemas de build conhecidos (Rust, `Package.resolved`, SQLite/FTS5, `pod install`, assinatura).

### Correções
- **Contas não ficam mais congeladas ao abrir o app depois de uma noite em segundo plano (C19).** O primeiro primeiro plano de um processo que já vivia em segundo plano era tratado como abertura a frio (`SceneDelegate.sceneWillEnterForeground`): só as flags mudavam, sem descongelar nem reconectar, e as contas ficaram ~96 s paradas até a Isadora encerrar o app (07/11/2026, produção, build 96). Agora o atalho de abertura a frio só vale se o processo nunca foi congelado (`MonalAppDelegate.isaCloudWasFrozen`, `SwiftuiHelpers.swift`); depois disso a abertura segue o caminho normal de volta ao primeiro plano. Análise em `docs/analises-crashes.md`.

## 0.0.1 (build 97) — 06/11/2026

Enviado ao TestFlight às 14:20. Merge do PR 50 (`feature/encaminhar-busca-sem-x`).

### Melhorias
- **Caixa de escrever com UITextView: 6 linhas e rolagem até o cursor** (`ChatTextInput.swift` novo, `ChatInputBar.swift`, `ChatView.swift`): o campo cresce até 6 linhas e depois rola, mantendo o cursor visível enquanto a pessoa digita. Antes, com `TextField(axis: .vertical)` e `lineLimit(1...8)`, o cursor e a linha digitada podiam sumir da área visível. Placeholder próprio (`UILabel`) e `accessibilityValue` igual ao placeholder quando vazio e ao texto quando não. Texto de fora (limpar, enviar, editar, menção) não mexe no cursor quando veio da digitação; ditado e acentos não são interrompidos. Testes de UI (`ChatInputBaselineTests`) não rodados nos simuladores.

### Correções
- **Encaminhar: ao marcar um contato com a busca aberta, a busca sai do foco e o botão Encaminhar aparece sem precisar tocar no X; o texto da busca continua filtrando** (`MessageForwardPicker.swift`, `isSearching` no `.searchable`). Testado no isaCloud.dev (iPhone).
- **OMEMO: contato que ainda não aceitou não mostra mais o alerta "No OMEMO keys found"** (`ChatView.swift`): sem alerta e sem busca de chaves para contato pendente (a busca reenviaria a solicitação). Uma linha discreta acima da caixa diz que a criptografia começa quando o contato aceitar ou as chaves chegarem. Ao enviar para contato pendente (texto, foto, arquivo, figurinha, áudio, localização ou encaminhamento), um alerta pergunta "Enviar sem criptografia só desta vez" ou "Cancelar"; cancelar mantém o texto e os anexos na caixa. O aviso roda antes de gravar a mensagem no histórico. Motivo: sem chaves, o envio criptografado saía com o corpo "[This message is OMEMO encrypted]" e sem conteúdo. Decisão em `docs/decisoes.md`.

## 0.0.1 (build 96) — 06/11/2026

Enviado ao TestFlight às 12:48. PRs 46 (`feature/citacao-com-miniatura`) e 47 (`fix/c17-wakeup-deadlock`); fork ExyteChat PR 21 (`7d3292b`).

### Novidades
- **Citação de foto, GIF e figurinha com miniatura** (roadmap 157, PR 46): ao responder a uma dessas mídias, a citação mostra uma miniatura (200 × 80 pt, gerada em 240 px, com cache) abaixo do autor e do rótulo, se a mídia já estiver no aparelho. Entre clientes isaCloud a resposta leva `<isacloud-quote xmlns='urn:isacloud:quote:0' id='…'/>` com o ID da citada (`stanza-id` em grupo, ID do stanza em 1:1); o corpo não muda, então os outros clientes continuam vendo o rótulo. ID guardado em `isacloud_quote_id` (migração 6 de `+migrateISACloudDB:`, idempotente). A mensagem pendente recalcula a miniatura quando o envio termina. Depende do PR 21 do fork ExyteChat (`Message.quotePreview`, `MessageTextView.quoteView`). Guia para o Android em `docs/citacao-com-miniatura-android.md`; decisão em `docs/decisoes.md`.

### Correções
- **O app não é mais morto em segundo plano ao receber um push enquanto o timer de um wakeup anterior termina (C17, PR 47).** O timer, rodando no fallback de fundo de `runOnMainQueue:withTimeout:`, segurava `@synchronized(self)` enquanto esperava a principal no `scheduleBackgroundTask`, e a principal esperava o mesmo lock num push novo (`0x8BADF00D`, build 95). Agora o lock só decide o estado; sincronizar erros, desconectar e congelar ficam fora dele, com uma reconferência no lock logo antes de desligar (para não congelar contas que um push novo ou a volta para a frente acabaram de reconectar), e o `scheduleBackgroundTask` é assíncrono nesse ponto (`MonalAppDelegate.m`). Análise e revisão em `docs/analises-crashes.md`.

## 0.0.1 (build 95) — 05/11/2026

Enviado ao TestFlight às 13:35. PR 45 (`fix/c16-bloco-tls-stream-em-erro`).

### Técnico
- **"Limpar outros aparelhos OMEMO…" na Depuração** (Extra Settings, roadmap 105): um botão por conta conectada, com a contagem de aparelhos próprios, tira da lista OMEMO todos os aparelhos da conta menos o atual e publica a lista nova; os que estão em uso voltam sozinhos ao conectar. Mesma ideia do "Clear devices" do Conversations (`wipeOtherPepDevices`). Métodos novos `isaCloudClearOtherOwnDevices` e `isaCloudOwnDeviceCount` em `MLOMEMO.m`, sem mudar métodos do Monal; textos no `Localizable.strings` do isaCloud. Testado no simulador iOS 27 (poli2: 17 → 1; o aparelho do iOS 18.6 voltou sozinho em ~40 s). Decisão em `docs/decisoes.md`.

### Melhorias
- **Conexão mais rápida na abertura e na volta da rede (roadmap 156):** a conta que ainda está logando só é reconectada quando a rede muda de verdade, pela assinatura do caminho em `isaCloudPathSignature()` (status, Wi-Fi/celular/cabo, rede cara ou limitada, IPv4/IPv6). Antes, os avisos de rede repetidos do iOS e o primeiro aviso depois da abertura derrubavam logins que estavam andando, e a abertura a frio no iPhone chegou a ~22 s (`isacloud.im`) e ~31 s (`autozona.cc`). A pausa de 5 s (`ISACLOUD_NETWORK_RECONNECT_COOLDOWN`) saiu, porque passou a segurar só mudanças reais: a troca de celular para Wi-Fi ficava presa até o prazo de 12 s do login. Medido no `.dev`: abertura a frio de 0,7 s e 3,2 s, e contas prontas em 0,55 a 2,3 s quando a rede volta. Só `MLXMPPManager.m`, dentro da trava `ISACLOUD_RECONNECT_UNBOUND_ON_NETWORK_CHANGE`. Decisão em `docs/decisoes.md`.

### Correções
- **O app não cai mais quando a conexão cai entre a abertura do socket e o login (C16, terceira ocorrência).** O crash `Stream must be open` em `-[MLStream tlsVersion]` voltou no build 92 (05/11/2026 10:38, iPhone14,7, iOS 27.2) por outro caminho. O `NSStreamEventOpenCompleted` deixa o bloco do login com TLS (`_blockToCallOnTCPOpen`) esperando na fila de recebimento e, quando ele roda, o stream já está em erro. A guarda de 04/11, no começo de `handleFeaturesBeforeAuth`, não chega até ali. Agora o próprio bloco e o ramo do desafio SASL2 (`processInput`), que também lê o channel binding, ignoram o stream nunca aberto ou já fechado/em erro, com um aviso no log, e a reconexão segue. "Abrindo" continua passando, para não voltar a espera de 12 s na abertura a frio. Channel binding e proteção contra MITM sem mudança (`xmpp.m`). Registrado no C16 em `docs/analises-crashes.md`.

## 0.0.1 (build 94) — 05/11/2026

Enviado ao TestFlight às 10:56. PR 44 (`feature/linha-lido-ate-aqui`).

### Novidades
- **Linha "Lido até este ponto"** (roadmap 153, PR 44): quando um grupo ou canal abre na primeira não lida, uma linha cinza clara com "Lido até este ponto" aparece logo acima dela e fica enquanto o chat estiver aberto. Não aparece com mais de 200 não lidas (o chat abre em outro ponto; uma segunda consulta sem limite confirma a primeira não lida verdadeira, ~0,3 ms). O segundo scroll do salto deixa 220 pt de folga acima da mensagem, para a linha caber na tela mesmo quando a não lida é uma foto; os scrolls e os tempos do salto continuam os mesmos. Só `ChatView.swift` e o `Localizable.strings` do isaCloud, sem mudar o fork do ExyteChat nem o banco. Documentação em `docs/feature-marcacao-leitura.md`; decisão em `docs/decisoes.md`.

## 0.0.1 (build 93) — 05/11/2026

Enviado ao TestFlight às 10:09. PRs 42 (`feature/canal-escolher-conta`) e 43 (`feature/compartilhar-pela-sugestao`).

### Melhorias
- **Canais públicos com várias contas** (roadmap 151, PR 42): a lista junta os canais dos servidores de todas as contas conectadas (antes só os da conta mais antiga); com mais de uma conta, tocar num canal abre uma folha com o nome do canal e o menu suspenso "Ingressar com…" (só as contas que ainda não estão no canal, as do servidor do canal primeiro); a linha mostra, uma por linha, quais contas já estão no canal. Só `PublicChannelsView.swift`. Análise em `docs/analise-ingressar-canal-escolhendo-conta.md`.
- **Compartilhar tocando no contato sugerido pelo iOS** (roadmap 152, PR 43): quando o compartilhamento vem de um contato da fileira de sugestões da folha do iOS, a extensão abre a lista já filtrada por aquele endereço, uma linha por conta em que ele existe, com a conta da sugestão marcada; "Mostrar todos" (ou a busca) volta para a lista inteira, rolada até a linha marcada. Se o contato não está na lista ou não dá para escrever nele, abre a lista inteira sem nada marcado. Só `SharePickerView.swift` e `ShareSheet.strings` (decisão em `docs/decisoes.md`, análise em `docs/analise-compartilhar-pela-sugestao.md`).

## 0.0.1 (build 92) — 04/11/2026

Enviado ao TestFlight às 20:41. PR 41 (`feature/conexao-rapida`).

### Melhorias
- **Spinner só quando o app não consegue conectar:** o indicador da lista de conversas aparece só quando alguma conta fica mais de 5 s sem conectar com o app em primeiro plano. Catchup, processamento de mensagens e transferências de arquivo não acendem mais o spinner (têm indicadores próprios). O rótulo de acessibilidade passa a ser "Conectando...". Trava `ISACLOUD_SYNC_INDICATOR_ONLY_WHEN_CONNECTING` em `MonalAppDelegate.m` e `ActiveChatsViewController.m` (decisão em `docs/decisoes.md`).
- **Rodapé da tela de abertura com o nome isaCloud:** "Copyright © 2026 isaCloud. Todos os direitos reservados." no `Launch Screen.storyboard`, em português fixo (a tela de abertura não passa pelo Localizable; decisão em `docs/decisoes.md`).

### Técnico
- **Tempo de conexão por conta:** cada tentativa de conexão grava uma linha em `connects-*.jsonl` (DNS, socket, TLS, login, bind, catchup e ocioso, em ms). Só medição, sem mudança de comportamento; a gravação usa fila serial, para duas contas terminando juntas não corromperem uma linha (`MLConnectTiming`, `docs/decisoes.md`).

### Correções
- **Login antecipado na abertura a frio:** a guarda do C16 em `handleFeaturesBeforeAuth` descartava também o stream em "abrindo", e toda abertura com recursos guardados esperava os 12 s do prazo de login. Agora só descarta o stream não aberto, fechado ou em erro (`docs/analises-crashes.md`, C16).
- **Reconexão quando a rede volta:** as contas ainda não vinculadas reconectam na hora (`reconnect:0`) quando a rede volta ou muda, em vez de receber um ping que o `xmpp.m` ignora antes do bind. Antes, a tentativa começada sem rede só destravava no prazo de login de 12 s (~15 s depois de sair do modo avião). Contas já conectadas continuam com o ping. Depois de uma reconexão pela rede, os avisos seguintes de mudança de rede respeitam uma pausa de 5 s por conta (`ISACLOUD_NETWORK_RECONNECT_COOLDOWN`), senão uma conta lenta como a do `autozona.cc` era derrubada a cada aviso e não terminava o login. Trava `ISACLOUD_RECONNECT_UNBOUND_ON_NETWORK_CHANGE` em `MLXMPPManager.m` (decisão em `docs/decisoes.md`).

## 0.0.1 (build 91) — 04/11/2026

### Alterado
- **Busca de GIF:** mais GIFs carregam ao rolar a lista, e os "em alta" (trending) mudam a cada vez que a busca é aberta (`GiphySearch.swift`, `GifPickerView.swift`; testes em `GiphySearchTests.swift`). Mesclado da branch `feature/gif-paginacao-variedade` (commits `3a692d86f` e `f9baf20d5`).

### Documentação
- Roadmap: abrir na primeira não lida (136) e preview de link de altura fixa (137) aprovados pela Isadora; dados do salvamento de estado (131) colhidos e analisados em `docs/analise-salvamento-do-estado.md`.
- Figurinhas: a conformidade com a XEP-0449 (`<file-sharing/>` junto com `<sticker/>`) está registrada como pendente em `docs/decisoes.md` e `docs/analise-figurinhas.md`, sem implementação.

## 0.0.1 (build 90) — 04/11/2026

### Adicionado
- **Compressão de fotos no envio.** Em Anexos, "Compressão de fotos" tem três modos: Nunca (envia a original, intacta), Apenas grandes (padrão; reduz fotos acima de 2 MB ou com orientação gravada nos metadados) e Sempre. A foto reduzida tem no máximo 1920 px no lado mais longo, sai em JPEG no nível do slider de qualidade, e GIF nunca é reduzido. A redução vale também para o envio pela folha de compartilhar (feito na outbox do app principal) e para o encaminhar (uma redução por encaminhamento, para todos os destinos). Enquanto prepara, a barra mostra "Preparando foto…" ou "Preparando foto N de M…". Análise em `docs/analise-comprimir-imagens.md`. Testes unitários em `HelperToolsTest.swift` (`ImageCompressionTests`).
- Log de cada foto: antes e depois (tamanho e pixels), o modo e a orientação aplicada, e a limpeza das cópias temporárias da outbox depois do envio.

### Alterado
- **Orientação normalizada na redução.** Toda foto reduzida sai com a orientação real aplicada aos pixels e sem a tag EXIF de rotação (antes, o iOS gravava a foto deitada com a tag, e alguns apps mostravam de lado). No modo Nunca, a original vai intacta.
- Preferência antiga "Enviar imagens originais" migrada para o novo seletor (ligada vira Nunca; desligada vira Apenas grandes).

### Corrigido
- Nada nesta versão além da compressão acima.

### Pendente
- Cor P3: a redução converte para RGB genérico, e fotos em Display P3 podem perder cor (roadmap 148).
- Android: a leitura da rotação (`FileBackend.getRotation`) ignora os valores 2, 4, 5 e 7 da tag EXIF. Fica com outro agente.

## 0.0.1 (build 89) — 04/11/2026 (enviado ao TestFlight às 10:43)

### Adicionado
- **Tocar numa figurinha na conversa abre o visualizador de mídia.** `GifMessageBubble` ganhou `onSelect` (só a figurinha o usa; o GIF continua reiniciando) e o `messageBuilder` passa `params.showAttachmentClosure`.

### Alterado
- **Visualizador de imagens mostra só a foto tocada**, sem contador nem miniaturas, com X e compartilhar fixos em círculos translúcidos e o toque na foto sem efeito. Opção nova do fork (`fullscreenSingleAttachment`, desligada por padrão; mudança nº 21 do fork, PR 20, `e168ed8`). Análise em `docs/feature-visualizador-mostra-foto-unica.md`. Figurinha e GIF não abriam esse visualizador (agora só a figurinha abre).
- **Folha de figurinhas:** "Cancelar" à esquerda e "Criar" (ícone de carinha e texto, na cor primária) à direita, no lugar do "+". O recorte livre foi feito e descartado no mesmo dia (04/11/2026): o recorte volta a ser sempre quadrado e o seletor Quadrado/Retângulo saiu (strings "Square", "Rectangle" e "Shape" removidas; entrou "Create").

### Corrigido
- **Quando o envio de um arquivo falha, o app avisa.** Se o upload de uma figurinha, foto, vídeo, áudio ou documento falhava (conexão caindo, como numa garagem ou elevador), nada aparecia: o erro só ia para o log, e como o balão só nasce depois do upload, a mensagem sumia sem "!" nem "Reenviar". Agora a cápsula acima da caixa de texto mostra, por 4 s, "Não foi possível enviar 😞 Tente de novo!", em vermelho (`uploadAndSendFile` no `ChatView.swift`, `showNotice(isError:)`). O "Enviando…" também passou a ser um contador: com dois uploads ao mesmo tempo, o primeiro a terminar não apaga mais o aviso do outro (`ChatInputModel.beginUpload/endUpload`). Alternativa mais completa, deixada para depois: criar o balão antes do upload, com spinner e "Reenviar" se falhar. Falta provocar a falha real num aparelho.
- **O app não cai mais quando a conexão de uma conta cai bem na hora do login.** O iOS derruba as conexões quando congela o app em segundo plano. Ao descongelar, a fila ainda processava os recursos de login (SASL2) de uma conexão já em erro, e a escolha do channel binding consultava o TLS desse stream, disparando a asserção `Stream must be open` em `-[MLStream tlsVersion]` (relatório de usuário, build 88, 03/11/2026 22:30). Agora `handleFeaturesBeforeAuth:withForceSasl2:` ignora os recursos quando o stream não está mais aberto, e a reconexão normal segue. A lógica de channel binding e de proteção contra MITM não mudou (`xmpp.m`). Registrado como C16 em `docs/analises-crashes.md`.

## 0.0.1 (build 88) — 03/11/2026 (enviado ao TestFlight às 16:57)

### Adicionado
- **Figurinhas.** Novo item "Figurinhas" no clipe abre uma folha com "Favoritas" e "Todas" e um botão para criar. Para criar: o seletor de fotos abre direto; escolher uma foto, recortar em quadrado ou retângulo, remover o fundo (Vision, no aparelho) e escrever textos com contorno, inclusive fora da foto, sobre a margem transparente. A figurinha é salva num PNG 512×512 numa biblioteca local; o toque longo favorita ou exclui. Tocar na figurinha envia na hora: ela vai como uma imagem pelo upload, com o marcador XEP-0449 (`<sticker xmlns='urn:xmpp:stickers:0'/>`). No isaCloud ela aparece sem balão, com 128 pt e o nome de quem mandou acima nos grupos; os outros apps (Conversations, Monal) veem uma imagem comum. O toque longo numa figurinha recebida oferece "Salvar figurinha", que confirma com um aviso passageiro "Figurinha salva" acima da caixa de texto, no lugar do "Enviando…" (sem janela para fechar). Migração 5 da escada do isaCloud (`message_history.isacloud_sticker`). Testado nos simuladores iOS 18.6 e 27 (inclusive a figurinha chegando pelo histórico no outro simulador); a remoção de fundo não funciona no simulador, mas funcionou no iPhone. Guia para o Android em `docs/ferramenta-de-figurinhas.md`. Análise em `docs/analise-figurinhas.md`.

### Alterado
- **O menu da mensagem abre em 0,4 s no total, contando do toque até o menu aberto.** Antes eram cerca de 250 ms. O toque longo continua em 0,15 s e a animação do menu passou de 0,1 s para 0,25 s (`.messageMenuAnimationDuration` no `ChatView.swift`, sem mudar o fork). GIFs e figurinhas usavam 0,1 s de toque longo e agora usam os mesmos 0,15 s das outras mensagens.

### Corrigido
- **Compartilhar com o isaCloud não apaga mais as chaves OMEMO nem o estado das contas.** A extensão de compartilhar não tinha o grupo de keychain do app (`keychain-access-groups`). Por isso lia um "device id" diferente do do app, e a cada vez que um dos dois abria depois do outro, a verificação do Monal ("Device id has changed") apagava todas as chaves OMEMO (`signalIdentity`, sessões, pre-keys) e invalidava o estado das contas. Isso explica: identidade OMEMO nova a cada abertura ("Novo dispositivo OMEMO detectado" para os contatos), reconexão completa e upload lento depois de compartilhar, e o crash na abertura de 03/11/2026 16:38 (SIGSEGV gerando chaves novas em `createLocalIdentiyKeyPairIfNeeded`). Afetava também a produção. Agora a extensão usa o mesmo grupo do app e da extensão de notificação (`Monal/shareSheet.entitlements` e `isaCloud/dev-entitlements/shareSheet.entitlements`).
- **"Reenviar" reenvia direto, sem perguntar.** Antes abria a pergunta "Tentar enviar mensagem novamente?" numa folha de ações que, no iOS 26 ou mais novo, aparecia cortada numa linha na barra de navegação, sem dar para ler nem tocar (`ChatView.swift`, caso `.resend`). Testado no simulador do iOS 27.
- **"Enviando…" também ao compartilhar de outro app.** A foto compartilhada pela folha do iOS sobe logo depois de a conversa abrir, e o aviso de upload chegava antes de a conversa escutar. Agora a conversa pergunta ao abrir se há algo dela na fila de compartilhamento (`DataLayer hasShareSheetUploadForJid:onAccount:`, só leitura) e mostra "Enviando…" até o envio terminar. Falta ver no iPhone (no simulador o upload é rápido demais para ver).
- **O app não congela mais ao enviar uma mensagem criptografada (OMEMO) enquanto chegam chaves OMEMO.** Visto ao compartilhar uma foto para um contato pela folha de compartilhar: o app abria a conversa e a tela ficava congelada para sempre. Era um deadlock do Monal. O envio criptografava na thread principal, pegava a trava do Signal e esperava o banco para gravar a sessão. Ao mesmo tempo, a thread de recebimento segurava o banco processando um pacote de chaves OMEMO e esperava a trava do Signal. Agora o envio abre a transação do banco antes de criptografar, na mesma ordem do recebimento (`xmpp.m sendMessage:`). Diagnosticado pelo log do `.dev` (03/11/2026, 16:14); o envio criptografado foi testado no simulador do iOS 27, mas o deadlock em si, que depende de tempo, não dá para provocar sob demanda.
- **Compartilhar com o isaCloud: marcar o destinatário na busca fecha a busca.** Antes, o botão de fechar a busca ficava por cima de "Enviar", e era preciso tocar nele antes de enviar. Agora, ao marcar alguém durante a busca, ela fecha, a lista volta inteira e rola até quem foi marcado, e "Enviar" já pode ser tocado (`SharePickerView.swift`). Testado no simulador do iOS 27 (Fotos → Compartilhar → isaCloud).
- **A notificação de reação está em português:** "Reagiu com ❤️ a «…»." (antes vinha em inglês, "Reacted with … to «…»").
- **Foto, GIF ou figurinha não fica mais com "!" quando duas contas do mesmo aparelho estão na mesma sala.** As duas contas recebem a mensagem e baixam o mesmo arquivo. O cache dá ao arquivo um nome tirado da URL, então a segunda cópia falhava com "já existe um item com o mesmo nome". O app marcava a mensagem com "Erro de download", e como o erro é gravado pelo id da mensagem e pela sala, também a mensagem enviada pela outra conta ficava com "!". Agora um arquivo que já está no cache vale como baixado (`MLFiletransfer.m`, download sem criptografia). As mensagens antigas que já tinham o erro continuam com ele. Testado nos simuladores iOS 18.6 e 27 com as contas poli e cookie no canal de teste.

## 0.0.1 (build 87) — 03/11/2026 (enviado ao TestFlight às 14:45)

A abertura na primeira não lida, o salto e o card de link ficam **em avaliação por alguns dias a partir de 03/11/2026**.

### Adicionado
- **Grupos e canais abrem na primeira mensagem não lida.** Ao abrir um grupo ou canal com mensagens não lidas, a conversa abre na primeira delas, com um pouco do que veio antes; sem não lidas, abre no fim como sempre. Com mais de 200 mensagens entre a primeira não lida e a mais nova, abre na 200ª mais recente (o resto se alcança rolando para cima). Se a conversa foi aberta por um resultado de busca, a busca vence. O que foi lido em outro aparelho (MDS) não conta como não lido. Chats 1:1 não mudam (`DataLayer firstUnreadHistoryIdForBuddy:`, `ChatView.swift`). O salto não pula mais por causa de links: a lista fica escondida até assentar (`listHidden`, API nova do fork do ExyteChat) e uma cápsula "Carregando…" aparece só se o salto precisar buscar mensagens no banco ou passar de 1,2 s (vale também para o salto da busca). O salto leva ~0,9 s (antes ~1,7 s com 1 não lida, e ~3,4 s com link perto do alvo): os tempos fixos de rolagem caíram de 0,4/1,2/1,5 s para 0,1/0,5/0,7 s e o app deixou de esperar a busca de previews, porque o card de link tem altura fixa (o `LinkPreviewPrefetcher` do fork continua no código, sem uso, a remover se o resultado for aprovado). Testado nos simuladores iOS 18.6 e 27 e no iPhone.
- **Card de preview de link com altura fixa (120 pt).** Com os previews ligados, o card de cada URL nasce com a altura final e nunca muda de tamanho: carregando, com preview ou sem preview. Quando a página não responde, não tem dados ou passa de 5 s, o card mostra "Pré-visualização indisponível" na mesma altura (a falha é lembrada por 5 minutos para não buscar de novo a cada rolagem). Assim a linha não cresce quando o preview chega e o salto não é mais empurrado. O card com preview ocupa a largura do balão. Decisão e análise do cache em disco descartado em `docs/feature-abrir-na-primeira-nao-lida.md`. Mudança no fork do ExyteChat (`LinkPresentation+View.swift`, `+Cache.swift`). Testado no iOS 18.6 e 27 e no iPhone.

### Corrigido
- **O campo de texto da mensagem não corta mais linhas e rola até o cursor quando o texto fica longo.** Sem limite próprio, o layout espremia o campo e uma linha ficava cortada no topo ou na base da caixa, e o campo não rolava para o cursor nessa situação (visto no iPhone com iOS 27.2). Agora o campo tem no máximo 8 linhas inteiras e rola por dentro (`.lineLimit(1...8)` em `ChatInputBar.swift`). Testado nos simuladores iOS 18.6 e 27 (digitando no fim, com Enter e movendo o cursor) e no iPhone.

## 0.0.1 (build 86) — 02/11/2026 (enviado ao TestFlight às 18:31)

### Adicionado
- **"Câmera" no clipe da caixa de mensagem.** Abre a câmera do iOS para tirar uma foto ou gravar um vídeo, que entra na barra de anexos como as mídias da biblioteca e é enviado quando a pessoa toca em enviar. Não salva na biblioteca de Fotos e usa a qualidade de vídeo padrão do sistema. O item só aparece em aparelhos com câmera; com a permissão negada, o app mostra o alerta com o atalho para Ajustes. Textos novos em pt-BR: "Câmera", "Falta permissão da câmera", "O isaCloud não tem permissão para usar a câmera", "Ajustes" (`CameraPicker` em `SwiftuiHelpers.swift`, `ChatInputBar.swift`, `ChatView.swift`). Análise em `docs/feature-enviar-midia-da-camera.md`.

## 0.0.1 (build 85) — 02/11/2026 (enviado ao TestFlight às 18:17)

### Corrigido
- **Mensagem de grupo entregue não fica mais com "!" e "Reenviar" por um erro tardio do servidor.** Quando o iOS suspendia o app e o servidor descartava a sessão antiga, ele devolvia um erro `recipient-unavailable` com o id de uma mensagem que a sala já tinha aceitado e redistribuído, e o app a marcava como falha (caso de 02/11/2026 16:43, grupo com OMEMO). Agora o erro é ignorado quando a sala já refletiu a mensagem (o `stanzaid` está gravado), e um erro que chega antes do eco é desfeito quando o eco chega. A marcação de "mensagem presa" da abertura do app também deixa em paz mensagens que já têm `stanzaid`.
- **Menos chance de o iOS encerrar o app (`0xdead10cc`) ao suspendê-lo.** A thread de timeouts abria uma transação de escrita no banco para cada conta a cada segundo, mesmo sem nada a fazer e mesmo com o app congelando; se o iOS suspendesse o app nesse instante, o banco ficava travado. Agora ela só abre a transação quando há iq handlers ou idle timers pendentes, e pula contas congeladas (`xmpp.m` `updateIqHandlerTimeouts`, `DataLayer hasIdleTimersForAccount:`).
- **O app não segura mais o banco esperando a rede ao desconectar.** Ao ir para segundo plano, o desconectar enviava o último aviso ao servidor e fechava a conexão dentro de uma transação de escrita, esperando sem prazo; com a rede presa, o iOS suspendia o app com o banco travado (`0xdead10cc` de 28/10 e 01/11). Agora a parte de rede fica fora da transação e espera no máximo 2 s (`xmpp.m`).
- **Medida dos salvamentos lentos do estado da conta:** o log registra os que passam de 50 ms, com o tempo, o tamanho e o que pesa, para decidir a próxima correção do `0xdead10cc` mais comum.

## 0.0.1 (build 84) — 02/11/2026 (enviado ao TestFlight às 17:19)

### Corrigido
- **Notificação "New Message?" por extensão travada na inicialização.** Em 02/11/2026 15:53 (build 81) o iOS matou a extensão de notificação com "extension check-in timeout" depois de 5 s e mostrou o texto cru do push. Ela travou no flush do logger de rede (`MLUDPLogger flushWithTimeout:`, arquivo do Monal), que esperava um sinal sem prazo: se o envio terminava antes de a espera começar, o sinal se perdia e a espera não acabava. Agora o sinal fica guardado numa flag e a espera tem prazo (o timeout pedido + 50 ms). O mesmo flush roda no app ao suspender e acordar. **Causa provável, não provada por pilha**; validar contando "New Message?" depois do próximo build.

## 0.0.1 (build 83) — 02/11/2026 (enviado ao TestFlight às 16:51)

### Adicionado
- **"Compartilhar…" no menu de toque longo das mídias.** Mensagens com arquivo já baixado (foto, GIF, vídeo, áudio, documento) ganham a opção no menu, que abre a folha de compartilhar do iOS ("Salvar Imagem", "Salvar Vídeo", "Salvar em Arquivos", AirDrop…). Foto, GIF e vídeo usam o compartilhamento do ExyteChat (cópia com a extensão certa, PR 14 do fork); áudio e documentos são copiados para uma pasta temporária com o nome original, que é removida quando a folha fecha. Mídia ainda não baixada e mensagens de texto não mostram a opção (`ChatView.swift`).
- **Cor do balão e do texto das minhas mensagens** (Configurações Gerais → Interface do Usuário → Aparência). Dois seletores de cor livres (sem opacidade), "Restaurar cores padrão", a mesma prévia do tamanho do texto e um aviso quando o contraste entre balão e texto fica abaixo de 4,5:1 (só com cor personalizada). O botão de enviar, o microfone, os ícones de entrega e a pílula de reação acompanham a cor escolhida; o rótulo "Encaminhado" e os links nos meus balões usam a cor do texto. Vazio = rosa e branco do isaCloud. Duas preferências novas, `ownBubbleColorHex` e `ownBubbleTextColorHex` (`GeneralSettings.swift`, `ChatView.swift`, `ChatInputBar.swift`, `IsaCloudBubbleColors` em `GifPickerView.swift`, `IsaCloudColorMath.swift`). **Depende do PR 18 do fork do ExyteChat** (pílula de reação e seta de responder). Testado nos simuladores iOS 18.6 e 27; falta o `.dev`.

### Corrigido
- **O app podia ser encerrado pelo iOS (`0xdead10cc`) por um log de erro preso na suspensão do registro.** Um log síncrono (erro) feito dentro de uma transação de escrita no banco podia travar para sempre se a fila de log fosse suspensa logo depois da checagem (caso do build 81, 13:48:11); o banco ficava travado e o iOS matava o app. Agora o log síncrono entra na fila e espera no máximo 250 ms (`HelperTools.m`, `swizzled_queueLogMessage`).
- **O visualizador de imagens não abre mais sozinho depois de fechar o menu de uma mensagem com mídia** (defeito do build 82, de quando o menu passou a abrir em 250 ms). O toque curto da foto, do GIF ou do vídeo disparava quando o dedo levantava do toque longo e a apresentação ficava na fila atrás do menu; o fork do ExyteChat agora ignora o toque na mensagem enquanto o menu está aberto (PR 16 do fork, `ChatViewModel`).
- **O toque longo só abre o menu em cima do balão, não na linha inteira.** Antes, segurar o dedo no espaço vazio ao lado do balão (ou na hora e no avatar) também abria o menu da mensagem. Agora o fork do ExyteChat compara o toque com a área medida do balão (citação + balão; a hora, o avatar e o status ficam de fora; no GIF, a imagem e as reações) e o reconhecedor não começa fora dela (PR 17 do fork, `UIList`, `MessageBubbleFrame`; `GifMessageBubble` mede o próprio balão). Se a área ainda não foi medida, o menu abre como antes.
- **Link tocado com o menu aberto não abre mais.** Num toque longo sobre um link, ao escolher a reação o link era aberto (Safari embutido). O fork passa a ignorar o `openURL` enquanto o menu da mensagem está aberto; o toque curto no link continua abrindo (PR 17 do fork).
- **O app não cai mais ao compartilhar um link (ou arquivo) de outro app para o isaCloud.** Crash do build 81 (iOS 27.2, 15:21, compartilhando um link do iTunes): `Messages can not have duplicate ids` em `ChatView.mapMessages` (ExyteChat). A mensagem enviada pela folha de compartilhar chega ao chat aberto pelo aviso `kMonalShareOutboxUpdate`, que a colocava na lista com `messages.append`; se uma atualização do chat já tivesse lido a mesma mensagem do banco, a lista ficava com o mesmo id duas vezes e o ExyteChat aborta o app. A mensagem **já tinha sido enviada** (chegou ao destinatário); só a tela caía. Agora o aviso usa `enqueueNewMessages`, que ignora o que já está na lista ou na fila (`ChatView.swift`).

## 0.0.1 (build 82) — 02/11/2026 (enviado ao TestFlight às 14:18)

### Alterado
- **O menu da mensagem (toque longo) abre em ~250 ms, em vez de ~0,6 s.** O toque longo do SwiftUI dentro da lista ignorava a duração pedida e só disparava depois de ~600 ms; agora o gatilho é um reconhecedor do UIKit de 0,15 s no fork do ExyteChat (PR 15 do fork), com a vibração preparada no toque, e a animação do menu é de 0,1 s. Vale também para o balão de GIF.

### Corrigido
- **A folha de compartilhar do visualizador de imagens agora oferece "Salvar Imagem" (e "Salvar Vídeo").** O app guarda os anexos baixados com o mime type em hexadecimal no lugar da extensão (`….696d6167652f706e67`), então o iOS mostrava um arquivo genérico e só deixava salvar em Arquivos. O fork do ExyteChat passa a compartilhar uma cópia temporária com a extensão certa (PR 14 do fork); no iOS 18.6 a folha mostra "Imagem PNG", com miniatura, e a imagem entrou na biblioteca de Fotos no formato original. A permissão de adicionar fotos já existia. **Falta testar no iPhone, em vídeo e no iOS 27.**

## 0.0.1 (build 81) — 02/11/2026 (enviado ao TestFlight às 11:41)

### Corrigido
- **O app podia ser encerrado pelo iOS (`0xdead10cc`) no fim de uma acordada em segundo plano com muitas presenças de canal.** Quando o iOS avisa que o tempo da tarefa de segundo plano acabou, o app espera a thread principal para desconectar as contas e se congelar. Num canal movimentado (centenas de presenças de participantes a cada acordada) a thread principal ficava ocupada por mais de 5 s, o congelamento não chegava a rodar e o iOS suspendia o app no meio de uma gravação no banco. Agora o app espera a thread principal no máximo 1 s e, se ela não responder, faz o congelamento na própria thread da tarefa (`MonalAppDelegate.m`: tarefas de atualização e de processamento em segundo plano e o timer de wakeup). Quando isso acontece o log mostra "Main queue did not run our block within 1.0 seconds". **Ainda não testado no aparelho.**
- **A extensão de notificação sai sem passar pelo `exit()`.** Nos 5 relatórios de `0xdead10cc` da extensão (31/10 e 01/11) o processo estava preso dentro do `exit()` (fase de `atexit` e destrutores) quando o iOS o suspendeu com os arquivos do banco e de lock abertos. Agora ela faz o flush dos logs, libera o lock do processo e sai com `_exit(0)`, que encerra na hora e solta todos os locks. **Ainda não testado no aparelho** (o simulador não roda a nossa extensão).
- **O aviso "isaCloud" vazio também é removido quando o app acorda em segundo plano**, e não só quando o app é aberto. Ele continua aparecendo quando chega um push que o app decide não notificar (até a Apple liberar o push filtering), mas some na próxima acordada.

## 0.0.1 (build 80) — 31/10/2026 (enviado ao TestFlight às 13:10)

### Corrigido
- **Mensagens de quem não é contato (em grupos) não são mais recusadas como "você não confiou no dispositivo"** quando é a primeira mensagem de um aparelho que o app ainda não conhecia. O app já confiava sozinho nesses aparelhos, mas a mensagem chegava antes da busca da lista de aparelhos. Mensagens que já falharam continuam com o erro. Quando o motivo é "aparelho ainda desconhecido", o texto diz isso.
- **Interruptor de criptografia na tela do contato espera o servidor** em vez de mostrar erro no primeiro toque, e liga sozinho quando a lista de aparelhos chega. Se o servidor da pessoa não deixa quem não é contato ler a lista, aparece um aviso explicando.

## 0.0.1 (build 79) — 31/10/2026 (enviado ao TestFlight às 12:28)

### Alterado
- **A linha da conta no topo da conversa individual foi desligada por enquanto**: nome, conta e "visto por último" eram três linhas e não ficaram bem. Continua na lista de conversas e no topo de grupos e canais. O código está comentado em `ChatView.swift` (marcado com TODO) para voltar depois.

- **"Visto pela última vez" virou um ícone de olhinho.** No topo da conversa individual, o rótulo "Visto pela última vez:" foi trocado por um olho preenchido dentro de um círculo vazado, do mesmo tamanho e cinza do ícone da pessoinha da conta, e o texto fica só "19 horas atrás". Também resolve o texto cortado ("Visto pela última vez: 2 hor…") no iOS 27. "Visto agora" e "Online" continuam como eram.

### Alterado
- **Proteção contra build sem a busca de mensagens (FTS5).** O Xcode às vezes compila a SQLite sem o módulo de busca, sem avisar (aconteceu nos builds 32 e 77). Agora o build **falha com uma mensagem clara** se isso acontecer (fase "[isaCloud] Check FTS5"), o novo `scripts/archive-testflight.sh` arquiva numa pasta limpa e confere o arquivo antes de enviar, e o app registra no log, a cada abertura, se a SQLite dele não tem FTS5. Nada muda para quem usa o app.

## 0.0.1 (build 78) — 31/10/2026

### Corrigido
- **O app fechava ao abrir uma conversa individual com "visto por último"** (build 77, regressão minha no cabeçalho com a conta da conversa). O Swift lia a data da última interação com o tipo errado e a leitura falhava assim que o contato tinha uma data; sem data tudo funcionava, por isso passou nos testes. Agora a leitura usa tipo explícito. Quem abriu o build 77 e caiu na abertura volta ao normal no 78.

## 0.0.1 (build 77) — 31/10/2026 (enviado ao TestFlight às 11:16)

### Alterado
- **A hora e o cadeado ficam sempre embaixo do texto**, numa linha própria, como já era nas imagens, GIFs e vídeos. Antes eles dividiam a linha com a última palavra quando cabiam, e com fonte maior ou com emoji no fim da mensagem (por exemplo "…pode ignorar 🙂") a hora caía por cima do texto. A hora continua crescendo junto com o tamanho de texto escolhido em Aparência, na mesma proporção do texto. Mudança no fork do ExyteChat (opção `timeAlwaysBelowText`, ligada pelo app).

- **"Enviando…" ao mandar mídia ou GIF virou uma cápsula flutuante**, na cor do fundo da conversa (branca no modo claro, preta no escuro) com uma sombra leve, logo acima da caixa de texto, e o texto dela acompanha o tamanho de fonte escolhido para a conversa (Aparência). Antes era uma cápsula cinza dentro da barra, que empurrava a conversa para cima enquanto o arquivo subia.

- **Com mais de uma conta, a conversa mostra a que conta ela pertence também no topo do chat.** Na lista de conversas o endereço da conta ganhou o mesmo ícone de pessoinha da lista de contatos, no mesmo cinza do endereço. Dentro da conversa, o endereço da conta (com o ícone) aparece embaixo do nome, e o número de participantes de grupo ou canal saiu da linha própria e foi para o lado do nome, entre parênteses, cinza e menor. Nome comprido nunca quebra: termina em "…" e o número continua visível. Só a conversa individual com "visto por último" tem três linhas e usa fontes um pouco menores para caber na barra do iOS 18.

### Corrigido
- **A hora e o cadeado não caem mais em cima do texto** da mensagem (aparecia em frases cuja última linha termina numa palavra curta, como "revolução sozinhos."; valia para qualquer tamanho de fonte da conversa). O SwiftUI evita deixar uma palavra sozinha na última linha e a conta da hora não sabia disso; agora a conta usa a mesma regra. Mudança no fork do ExyteChat (PR 13). Com a hora sempre embaixo (item acima), essa conta deixou de decidir a posição da hora.

## 0.0.1 (build 76) — 30/10/2026 (enviado ao TestFlight às 21:14)

### Alterado
- **Menos avisos**: sem a notificação "Problemas de conexão" fora do app; sem popup de erro quando o envio de um arquivo falha (fica só no log, por enquanto).
- **Sem popup nem banner para erro técnico**: avisos de servidor sem MAM, Stream Management ou push; falha ao buscar mensagens antigas; e o banner de erro não grave (só log). Também só no log: nove erros de sincronização em segundo plano (buscar mensagens novas, carbons, push, bookmarks). Login, banimento e falhas de ações suas continuam avisando.
- **Tela de contas**: conta habilitada e ainda não conectada mostra um símbolo laranja de "reconectando" no lugar do ponto.

### Corrigido
- **Canais sumindo da lista** depois de erro de servidor remoto (por exemplo `recipient-unavailable` ao entrar numa sala de outro domínio): o canal não é mais removido dos favoritos e dos bookmarks, nem gera banner ou notificação.

## 0.0.1 (build 75) — 30/10/2026 (enviado ao TestFlight às 20:27)

### Corrigido
- **App de produção travava ao abrir depois de uma rajada de imagens** (deadlock no download automático: a fila de recebimento e a thread de download esperavam uma à outra, e a tela ficava no spinner até o iOS matar o app). O estado dos downloads agora é gravado fora do bloqueio, de forma assíncrona. Quem desligou "Download automático de arquivos e mídias" para escapar do travamento pode ligar de novo.
- **A conversa piscava em canais com reações** (a lista refazia a atualização inteira 3 a 4 vezes por segundo porque as reações ganhavam um identificador novo a cada leitura). Agora o identificador é estável.

### Nota
- Medido no `.dev` do iPhone: rajada de 15 fotos sem esperas de banco e sem reconexões; 27 reações em 2 s sem nenhuma atualização desnecessária da lista.

## 0.0.1 (build 74) — 30/10/2026

### Corrigido
- **Pílulas de reação em imagem, vídeo e GIF** agora aparecem nas mídias que eu mando (antes a pílula branca sumia no fundo branco). Sem balão, as reações ficam em cinza e a minha em rosa claro; no texto nada mudou. Enviado ao TestFlight em 30/10/2026.

## 0.0.1 (build 73) — 30/10/2026

### Corrigido
- **GIF ainda aparecia cortado** (o do cinema, do Giphy, sem o teto e sem as laterais): a view do GIF mantinha o tamanho do arquivo dentro do balão menor e só o meio aparecia. Agora ela assume o tamanho do balão e o GIF mostra inteiro. Vale também para as miniaturas do seletor. Conferido com GIFs reais nos simuladores iOS 18.6 e 27.
- O 72 já tinha o balão na proporção certa, mas com o GIF ainda cortado; o 73 resolve. Enviado ao TestFlight em 30/10/2026 e instalado nos simuladores (iOS 18.6 e 27) e no `.dev` do iPhone.

## 0.0.1 (build 72) — 30/10/2026

### Corrigido
- **Mensagem de uma linha cortada com "…"** (TestFlight 71: "Que ele ia usar sem o cor…"). A conta que decide se a hora cabe ao lado do texto não contava o cadeado das mensagens criptografadas e o texto era limitado a uma linha; agora o cadeado entra na conta e o que não couber quebra em duas linhas. Correção na biblioteca de chat (ExyteChat, PR 11 do fork).
- **GIF cortado:** o GIF aparece inteiro, na proporção do arquivo, dentro de uma caixa de 220×280 (balão e miniaturas do seletor).
- **Reações nos GIFs voltaram**, iguais às das imagens (cápsulas centralizadas sob o GIF, a minha em rosa, até 5 e "+N").

### Adicionado
- **Tamanho do texto nas conversas** (PR 11 do Jejê): Configurações → Interface do Usuário → Aparência, com Pequeno, Padrão, Grande, Maior e Gigante e uma prévia. "Padrão" acompanha o tamanho do sistema; a barra de digitação não muda.

### Nota
- Build 72 enviado ao TestFlight em 30/10/2026 (16:52) e instalado nos simuladores (iOS 18.6 e 27) e no `.dev` do iPhone.

## 0.0.1 (build 71) — 30/10/2026

### Corrigido
- **Reversão do fechamento de banco na extensão de notificação.** O build 66 passou a fechar as conexões do SQLite ao entregar a notificação para resolver o `0xdead10cc`; o efeito colateral foi pior: um único log de 30/10 tem **29 exceções `SQLite3Exception: 7: out of memory`** na appex. O padrão é sempre o mesmo — fecha, algo escreve 300–800 ms depois (janela de encerramento de 1,5 s), a reconexão precisa alocar memória com a extensão em ~35 MB de 59 MB disponíveis e o SQLite devolve `NOMEM`, que vira `SIGABRT`. A extensão voltou ao comportamento anterior: o lock fica até o processo sair (`killAppex`).
- A API `closeDatabasesForCurrentThread`/`closeAllDatabases` foi **removida** do `MLSQLite` para não ser reaproveitada sem contexto.

### Documentação
- `docs/plano-estabilidade-appex.md`: o diagnóstico com a evidência, a decisão da reversão e o **plano de controle** (reproduzir com `simctl push`, medir a memória por etapa, uma mudança por build, `.dev` como campo de provas antes do TestFlight).

### Mantido do que já estava pronto
- Logs, métricas e relatórios de crash em `Library` (legíveis pelo `devicectl`), teto de 2 MB na cópia do log no crash (profile de cobertura inteiro), remoção do atraso de 1 s na limpeza do placeholder, correção do `disconnectAll` × conta congelada e vigia do KSCrash desligado em produção.

## 0.0.1 (build 70) — 30/10/2026

### Corrigido
- **Extensão morrendo com `SQLite3Exception: 7: out of memory`** (5 relatórios de 30/10, build 68, todos da appex): a extensão inicializa a pilha inteira do XMPP (`MLXMPPManager`) num processo com orçamento de memória minúsculo e, no momento do crash, **copiava o log para o relatório** — 45 MB num dos casos (e 6 GB num anterior). Agora a cópia leva **só os últimos 2 MB** do log (o profile de cobertura continua indo inteiro, senão corromperia).
- **`0xdead10cc` na extensão**: ela agendava a remoção da notificação-placeholder com **1 s de atraso** e ficava viva esse tempo com o arquivo do SQLite aberto. Esse agendamento saiu da extensão; o placeholder continua sendo removido quando o app abre e no começo do próximo push. O banco também é fechado antes de o processo sair (`killAppex`).

### Nota de engenharia
- Uma tentativa de fechar **todas** as conexões do banco na extensão (`closeAllDatabases`, inclusive de outras threads) foi **descartada**: `prepareQuery` usa `_database` sem checar `NULL`, então fechar a conexão de outra thread poderia virar uso de ponteiro nulo. Ficou o fechamento por thread, que é seguro.

## 0.0.1 (build 69) — 30/10/2026

### Adicionado
- **Relatórios de crash dentro de `Library/CrashReports`** (com migração dos que estão na raiz do grupo, feita na primeira abertura): a raiz do grupo não é legível pelo `xcrun devicectl device copy from`, então os arquivos de crash (relatório + log copiado + profile) só saíam pelo e-mail do app, que às vezes não entrega 24 MB. Agora dá para puxar direto do aparelho, como já acontece com as métricas e os logs.

## 0.0.1 (build 68) — 30/10/2026

### Corrigido
- **Crash `SIGABRT` ao ir para o fundo**: o `MLAssert` "receive queue suspended while trying to disconnect!" matava o app quando o caminho de encerramento (`MLXMPPManager disconnectAll`) encontrava a conta **congelada** pelo app em segundo plano (relatório de 30/10, build 67, durante uma atualização de apps). Agora o `disconnectAll` pula contas congeladas e, se um disconnect chegar com a fila congelada por outro caminho, ele registra e retorna em vez de derrubar o app.
- **Extensão de notificação ainda morta com `0xdead10cc`**: no 66/67 ela fechava só as conexões da thread atual — e abre o banco em outra thread. Agora `MLSQLite closeAllDatabases` fecha **todas** as conexões vivas do processo (instâncias fracas registradas) antes de a extensão ser suspensa.

### Adicionado
- **Logs dentro de `Library/logs`** (com migração dos antigos, que ficavam na raiz do grupo e não podiam ser lidos pelo `devicectl`): agora o log da extensão também é acessível para diagnóstico.
- **Flags nas esperas pelo banco**: `db_lock_max_background` e `db_lock_max_suspect` (acima de 3 s). As esperas enormes (759 s, 33 s) eram **tempo com o app suspenso**, não contenção real — o relógio continua correndo enquanto o processo está congelado.
- **Abertura em segundo plano identificada**: o registro de abertura ganhou o campo `background` (uma abertura por notificação/tarefa mostra a primeira tela muito depois e inflava o `launch_ms` — foi o caso dos 24.984 ms de uma amostra do 67).
- `HelperTools.appState`: estado do app que também funciona na extensão (`UIApplication.sharedApplication` não existe lá).

## 0.0.1 (build 67) — 29/10/2026

### Corrigido
- **O checkpoint da extensão não bloqueia mais o app**: o 66 fechava o banco da extensão com `wal_checkpoint(TRUNCATE)`, que exige que ninguém esteja escrevendo — com o app ativo ele ficava no `busy_timeout` por até 1 s e as mensagens do app esperavam o lock (esperas de 1,1 a 2,8 s medidas no XMPP, sempre com `db_lock_holders` vazio: o lock estava em outro processo, a extensão). Agora é `PASSIVE`, que nunca espera.
- **Fechamento sem deixar conexão órfã**: `sqlite3_close_v2` (adia o fechamento até o último statement ser finalizado) e o ponteiro só é zerado quando o fechamento realmente acontece — antes, um `sqlite3_close` que voltasse "busy" deixava a conexão viva segurando o lock, que é justamente o que mantém o `0xdead10cc`.
- **Log para cruzar os dois processos**: a extensão registra quando abre e quando fecha o banco, com horário.

## 0.0.1 (build 66) — 29/10/2026

### Corrigido
- **Extensão de notificação morta pelo sistema (`0xdead10cc`)**: os diagnósticos do MetricKit do iPhone da Isadora mostraram seis mortes do `notificationService` (builds 54, 57 e 63) com `Namespace RUNNINGBOARD, Code 0xdead10cc` — a extensão ficava **suspensa com o arquivo do SQLite aberto**, segurando o lock de arquivo. Agora ela fecha as conexões do banco assim que entrega o conteúdo da notificação (`MLSQLite.closeDatabasesForCurrentThread`, com `wal_checkpoint(TRUNCATE)` antes do `sqlite3_close`) e também quando o tempo expira. O banco é reaberto sozinho na próxima notificação.

## 0.0.1 (build 65) — 29/10/2026

### Adicionado
- **Origem da pior espera pelo banco**: além de `db_lock_waits`/`db_lock_max_ms`, a amostra passa a trazer `db_lock_waiter` (a pilha de quem esperou) e `db_lock_holders` (a pilha de quem estava segurando o lock de escrita naquele instante), limitadas a 1200 caracteres. Foi o que faltava para responder "quem prendeu o lock por 10 s" — as amostras do oficial mostravam `db_lock_max_ms` de até 10.625 ms sem dizer a origem.

## 0.0.1 (build 64) — 29/10/2026

### Adicionado
- **Medição do tempo de abertura em cada launch**: uma linha por abertura em `metrics/launches-AAAA-MM-DD.jsonl` (e no export de métricas), com `launch_ms` (de `main()` até a tela de conversas aparecer), `app_delegate_ms` (trabalho na thread principal no `didFinishLaunching`), `list_build_ms` (montagem da lista), `list_ready_ms`/`first_frame_ms` e `main_ms`.
- **Etapas do `didFinishLaunching`** (`stage_<nome>_ms`): `xmpp_manager`, `metrics_start`, `observers`, `notifications`, `appearance`, `audio_session`, `background_task` e `connect`. No `.dev` (Debug) as duas que pesam são o singleton do `MLXMPPManager` e a `configureDefaultAudioSession`.
- O harness (`tools/metrics-harness`) envia as aberturas para a medida `<measurement>_launch` e o dashboard ganhou o painel **"Abertura a frio (ms)"**.

## 0.0.1 (build 63) — 29/10/2026

### Corrigido
- **Fim dos "crashes" em iPhone 11 e XR** (relatórios do Will, build 54, iOS 26.7.2): os dois incidentes eram o **vigia de travamento do KSCrash** matando o app, não um bug de lógica. O limiar dele é fixo em **250 ms**; na abertura a frio num telefone mais antigo a lista de conversas passava disso decodificando avatares (`imageWithContentsOfFile:` na thread principal) e montando o texto da prévia. Um dos relatórios ainda mostra o próprio KSCrash quebrando ao escrever o relatório.
  - O vigia **não é mais ligado em produção** (só em build de desenvolvimento); travamentos reais continuam aparecendo como `0x8BADF00D` do sistema.
  - A **decodificação dos avatares saiu da thread principal**: `getIconForContact:withCompletion:` devolve na hora o ícone de reserva (ou o que estiver em cache) e decodifica o avatar de verdade em background, entregando-o na main quando fica pronto. A célula usa o ícone devolvido na hora e troca quando o real chega.

## 0.0.1 (build 62) — 29/10/2026

### Mudado
- **Ícone com o "im" mais equilibrado** (arte final ajustada pela Isadora): o balão ganhou mais respiro e as letras ficaram um pouco menores em relação a ele. Fontes em `isaCloud/branding/` (`logo-isacloud-im-ios-icon.svg` e `…-1024.png`, RGB sem alfa). Vale para todos os iOS — no 26+ o sistema aplica o Liquid Glass por cima.
- **Roadmap em dia**: todos os itens concluídos estão riscados e o resumo antes da tabela mostra 92 features, 88 concluídas.

## 0.0.1 (build 61) — 29/10/2026

### Mudado
- **Ícone novo, o desenhado para o Liquid Glass**: o balão virou um tubo arredondado com brilho, as letras ganharam volume e os pontos, formato de pílula. Vale para todos os iOS — no 26+ o sistema aplica o vidro por cima, nas versões anteriores ele aparece nítido. Fontes em `isaCloud/branding/` (`logo-isacloud-im-ios-icon.svg` e `…-1024.png`). O porquê de não existirem dois ícones por versão está em `docs/decisoes.md`.

## 0.0.1 (build 60) — 29/10/2026

### Mudado
- **A busca da tela inicial ignora os filtros dos chips**: buscar é para achar qualquer coisa, inclusive o que o filtro está escondendo. Enquanto a busca está aberta, os resultados vêm só de nomes e do texto das mensagens (FTS), como antes; ao cancelar/fechar a busca, a lista de conversas volta a aparecer filtrada pelos chips. (A versão do 59 aplicava os chips também na busca; foi revertida a pedido da Isadora.)

## 0.0.1 (build 59) — 29/10/2026

### Adicionado
- **Filtros na lista de conversas**: chips abaixo da busca, com multi-seleção e estado guardado entre aberturas — **Não lidas, Contatos, Grupos e Canais**. Contatos/Grupos/Canais são mutuamente exclusivos por conversa, então formam um conjunto ("nenhum marcado = todos"); "Não lidas" é independente e conta também a bolinha cinza de canal silenciado. A lista segue os filtros **ao vivo** (uma conversa que fica não lida entra; uma que é lida sai) e a **busca** (nomes e FTS de mensagens) usa o mesmo filtro. Estado vazio com o filtro ativo: "Nenhuma conversa com esses filtros".

### Corrigido
- **Estado vazio da lista podia derrubar o app**: `imageForEmptyDataSet:` montava um dicionário de views que podia conter `nil`.
- **Conversa fora do filtro entrava na lista** quando chegava mensagem: `insertOrMoveContact:` não olhava os chips.

### Visual
- Chips em cinza (preenchido = marcado, contorno = desmarcado), fonte 7 com kerning −0,2, pílulas de altura 24 e centralizadas (scroll horizontal se não couber). O visual é aplicado pela `UIButtonConfiguration` — o `backgroundColor` era coberto pelo `tintColor` do botão do sistema.

## 0.0.1 (build 58) — 29/10/2026

### Corrigido
- **O spinner eterno era uma mensagem retratada, não uma mensagem presa.** Com o banco da Isadora (banco real, 133 mil mensagens) a mensagem das 13:24 apareceu como `sent=0`, `received=NULL` **e `retracted=1`**: ela foi apagada antes de ser enviada, e o status só olhava `sent/received/displayed` — caía no caso "enviando" e girava para sempre. Agora mensagem retratada não mostra indicador de envio (não faz sentido "enviando" para o que foi apagado).
- **A reconciliação do 57 não achava nada por dois motivos**, também descobertos no banco real: `received` é **NULL** nas mensagens que nunca receberam recibo (o filtro `received=0` descartava todas — 157 de 157) e mensagens retratadas não são falha de entrega. O filtro passou a usar `ifnull(received,0)=0`, a ignorar retratadas e a olhar só os últimos 7 dias (para não ressuscitar o histórico antigo importado como "falha").

## 0.0.1 (build 57) — 29/10/2026

### Corrigido
- **A reconciliação do 56 não achava a mensagem presa** (e podia derrubar o app): o `SELECT` era feito fora de uma transação, e o `MLSQLite` **lança exceção** nesse caso. Agora a leitura vai dentro de `idReadTransaction:`; o filtro também deixou de olhar só os últimos 2000 ids (uma mensagem antiga e ainda presa ficava de fora) — lê todas as não confirmadas e marca só as encontradas. Testado no simulador com uma mensagem de id antigo (marcada) e uma recente (intacta).

## 0.0.1 (build 56) — 29/10/2026

### Corrigido
- **Mensagem que ficava "enviando" para sempre depois de um crash.** Se o app morresse no meio do envio, a mensagem ficava no banco com `sent = 0` e ninguém voltava a tentar: o indicador de envio não saía mais. Agora, na abertura, mensagens de saída com mais de um minuto que continuam sem confirmação são marcadas como **falha de entrega** — o balão mostra o aviso e o botão **tentar de novo** (que reenvia com o mesmo id). Nada é reenviado sozinho, então não há risco de duplicar.

## 0.0.1 (build 55) — 29/10/2026

### Corrigido
- **Crash ao abrir uma conversa com mensagem de arquivo sem mimetype** (relatório do build 53, iPhone 12 Pro, iOS 27.0.1): a lista chama `replyQuoteText` para montar a citação, e o wrapper de KVO **lança exceção** quando o campo é nulo (`fileInfo.mimeType` de um anexo ainda não baixado) — o app abortava em `ObservableKVOWrapperCastingError`. A leitura passou a pedir o valor como opcional (com padrão seguro), então anexo sem tipo não derruba mais a tela.

### Adicionado
- **Instrumentação das esperas pelo banco.** O `MLSQLite` agora conta quantas vezes uma transação teve que esperar o lock e qual foi a maior espera; isso entra nas amostras de métricas como `db_lock_waits` e `db_lock_max_ms`, e o dashboard ganhou o painel **"Esperas pelo banco (lock)"**. É medição para decidir com dados se vale mexer na contenção (e não uma mudança no comportamento do banco).

## 0.0.1 (build 54) — 29/10/2026

### Adicionado
- **Métricas do aparelho, por build.** O app passa a coletar o que é preciso para avaliar consumo de recursos nos aparelhos:
  - **MetricKit** (fonte oficial da Apple): tempo de CPU, memória, bateria, lançamentos, hangs e diagnósticos, gravados em JSON com o build carimbado quando chegam (~1×/dia);
  - **amostras próprias** a cada abertura, ao ir para segundo plano e a cada 5 minutos com o app ativo: memória, CPU, térmica, modo de baixa energia, bateria, contas ociosas, tamanho do banco e do WAL;
  - **Depuração → "Métricas do aparelho" → "Exportar métricas"** gera um JSON único e abre o compartilhamento (mesmo caminho dos logs).
- **Harness `tools/metrics-harness/`** (Python 3, só biblioteca padrão): envia esse JSON para o **InfluxDB 2.x** (credenciais em `.credentials`, fora do Git), com `--dry-run` e controle do que já foi enviado; inclui um script para apagar a measurement quando o schema muda e um **dashboard do Grafana 12.0.1** com séries contínuas e os builds marcados como annotations.

## 0.0.1 (build 53) — 29/10/2026

### Corrigido
- **O app ainda abortava na abertura depois de importar um banco** (relatórios do build 51 num iPhone 11, iOS 26.7.2). O log do próprio app mostrou o motivo: **"database is locked"** — a limpeza de avatares abria uma transação de leitura enquanto a migration tinha uma de escrita aberta, o `MLSQLite` lançava exceção numa thread de segundo plano sem tratador e o processo abortava. Agora são duas proteções: (1) as duas limpezas de abertura chamam `[DataLayer sharedInstance]` antes de tocar no banco (ele espera a migration terminar, se ainda estiver rodando) e (2) `cleanupHashes` roda dentro de `@try/@catch` — perder uma limpeza de avatares é inofensivo, derrubar o app não é.

## 0.0.1 (build 52) — 29/10/2026

### Mudado
- **A conversa com bolinha vermelha na lista fica mais fácil de achar:** o preview da última mensagem aparece em **cinza quase preto (#373736)** em vez do cinza claro, e um **`@` rosa** aparece logo antes do sininho que indica o tipo de notificação do canal (só quando há sininho: canal em "só menção" ou silenciado). O nome do canal, a linha da conta e as conversas com bolinha cinza continuam exatamente como eram — a regra do vermelho/cinza não mudou.
- O negrito chegou a ser usado nesse preview e foi **descartado**: no iPhone a fonte ficava visualmente maior que o nome da conversa.

## 0.0.1 (build 51) — 29/10/2026

### Corrigido
- **O app fechava sozinho (SIGABRT) na abertura depois de importar um banco de outro cliente.** Na inicialização, o app disparava duas limpezas em segundo plano (cache de transferências e de imagens) **antes** de abrir o banco — e abrir o banco é o que roda as migrations. Com um banco importado (que precisa migrar de uma versão antiga), a migration recria tabelas enquanto essas limpezas consultavam o banco, o `MLSQLite` lançava exceção numa thread sem tratador e o app abortava. No simulador a migration é rápida e a corrida não aparecia; num iPhone 11 (iOS 26.7) ela apareceu em **quatro** aberturas seguidas. Agora as duas limpezas só começam **depois** de o banco estar aberto e migrado.

## 0.0.1 (build 50) — 28/10/2026

### Adicionado
- **Importar um banco de dados pelo app (Configurações → App → "Importar do Monal"; a mesma coisa fica em Depuração → "Import Database…" para nós)**, para trocar de cliente sem perder o histórico. O iOS não deixa nenhuma ferramenta de fora escrever na raiz do container compartilhado (onde fica o `sworim.sqlite`) — o serviço de arquivos só aceita `Library`, `Documents` e `tmp` —, então o próprio app copia o arquivo escolhido para `import-sworim.sqlite` e, na abertura seguinte, troca o banco atual por ele antes de qualquer código abrir o banco. A escada de migrations roda normalmente depois. Depois de importar, os **avatares** são baixados de novo (as imagens não vêm no banco, só o hash — e com o hash guardado o app nunca baixaria outra vez); o Depuração também ganhou **Reset Avatar Cache**, para o mesmo efeito sem reimportar. Aceita o banco **cru ou comprimido (`.gz`)** — as versões novas do Monal exportam comprimido —, e a linha do menu tem tradução pt-BR. **É uma ferramenta de depuração**, com aviso de que o banco atual será substituído; senhas e a chave OMEMO continuam no keychain de cada app, então o Assistente de Migração pede as senhas.

## 0.0.1 (build 47) — 28/10/2026

### Corrigido
- **O app congelava e podia ser encerrado pelo sistema por causa do log (`0x8BADF00D`).** Quatro relatórios de crash (builds 40 e 42) mostram a thread principal **parada** em `[DDLog flushLog]`, com o app quase sem CPU, até o iOS matar: *scene-update watchdog* (30 s) e, no último, *"Failed to terminate gracefully after 5.0s"*. O `flushLog` é um `dispatch_sync` **sem timeout** para a fila de log, que fica suspensa com o app em segundo plano; com a rede instável (mais linhas de log) ficou fácil de travar. Agora as **23 chamadas diretas** de flush do app e da extensão de notificação (14 em `MonalAppDelegate.m`, 9 em `NotificationService.m`) passam pelo `HelperTools flushLogsWithTimeout:`, que espera a fila **com timeout** e segue em frente se estourar. A única perda possível são as últimas linhas de log.
- **Compartilhar um arquivo dava "your account got disconnected while requesting upload slot".** O app abria e subia a foto **antes de a conta conectar**; o pedido do espaço de upload ia por um stream ainda desconectado. Agora, na fila do compartilhar, o app espera a conta ficar ligada e o servidor de upload ser anunciado (até ~30 s) antes de subir arquivo ou imagem.
- **O compartilhar deixava marcar vários destinos**, embora mandasse para um só: a linha usava `Button`, e o iOS mantinha a linha destacada. Agora é um toque simples, com um destino por vez.

### Adicionado
- **Responder com áudio mantendo a citação.** Puxar o balão para responder preenche o campo com a citação, e o microfone desaparecia. Agora o microfone fica ao lado do botão de enviar, e a resposta com áudio vai em duas mensagens: a citação num balão com um 🎤 e o áudio em seguida. Gravação com menos de 0,35 s é descartada (não vira áudio vazio).

## 0.0.1 (build 43) — 28/10/2026

### Alterado
- **A janela de compartilhar do iOS ficou igual à tela de "Encaminhar" do app.** Antes ela era a do Monal — `SLComposeServiceViewController`, uma API depreciada —, com duas linhas de configuração ("Conta" e "Destinatário") abrindo uma tabela de texto sem avatar; no simulador ela aparecia com o campo vazio, um pedaço de imagem sobrando e só a linha "Conta". Agora é uma lista SwiftUI com avatar, nome, endereço e a conta de cada destino, busca, seleção com um toque e o rosa do isaCloud, no desenho do sistema (saiu a compatibilidade forçada do iOS 26 que a extensão pedia).
- **Grupos e canais entram na lista do compartilhar** (antes só contatos individuais), com os que a pessoa não pode escrever cinza e desabilitados, com "Você não pode escrever aqui", como no Encaminhar.
- **Campo de mensagem opcional** abaixo da lista: o texto vai como mensagem e o anexo em seguida, como já era.

### Continua igual
- A extração do que foi compartilhado (fotos, vídeos, arquivos, mapas, contatos, texto), a fila `sharesheet_outbox` e a abertura do app para enviar: só a tela mudou.
- Cancelar fecha sem enviar e não abre o app.

### Testado
- No simulador iOS 27: a lista com as três contas e os canais, o canal sem voz não seleciona, cancelar não envia, e o envio de foto + mensagem chegou (o texto e um `aesgcm://` no banco, fila vazia no fim).
- O build também compila no iOS 18.6 (Xcode 26.2). Falta a mesma passada de UI no 18.6 e no iPhone.

## 0.0.1 (build 42) — 28/10/2026

### Corrigido
- **Em canal ou grupo em "só menção", o app notificava por qualquer pedaço de texto parecido com o seu nome.** Quem tem um apelido curto (como "isa") recebia notificação de "isafashiondev", "precisa", "analisar", "avisar", "pesquisa" ou "Elisa", porque a regra procurava o apelido, o nome de exibição, a parte local do endereço e o endereço dentro de qualquer palavra. Agora o nome só conta como menção quando aparece como **palavra inteira**, sem diferenciar maiúscula nem acento: "oi isa", "isa, vem aqui", "@isa" e "isa." contam; "isafashiondev", "precisa" e "Elisa" não. Vale para a notificação (inclusive a da extensão de notificação) e para a bolinha vermelha ou cinza da lista de Conversas. Limite conhecido: `.`, `-` e `@` colados ao nome contam como fim de palavra ("isa-dev" ainda casa com "isa"). Era o comportamento do Monal original; o código ficou numa função só, `HelperTools text:mentionsAnyOfNames:`.

## 0.0.1 (build 41) — 28/10/2026

### Corrigido
- **Ao enviar uma mensagem de texto, a conversa não dá mais um "sobe e desce" rápido** (visto no modo avião, em que a gravação é quase instantânea). A mensagem que aparece na hora (provisória) era trocada na lista pela mensagem gravada, que tem outro id, e a lista fazia isso como apagar uma linha e inserir outra, em duas etapas: três movimentos seguidos. Agora a própria mensagem provisória passa a apontar para a gravada, a lista não vê troca nenhuma e o status (o spinner que vira tique) continua sendo acompanhado. Medido gravando a tela do simulador do iOS 27: 3 surtos de movimento antes, 1 depois (a entrada da mensagem).

## 0.0.1 (build 40) — 28/10/2026

### Adicionado
- **A mensagem de texto aparece na hora ao enviar, com um spinner no lugar do tique** (PR do Jejê, com uma correção). Antes, a gravação da mensagem no banco rodava na thread principal e esperava o bloqueio de escrita do banco, que outra parte do app segura de vez em quando (medido: 7 segundos parada); a conversa ficava parada e a mensagem só entrava depois, às vezes já com reação de alguém. Agora a mensagem entra na hora, é gravada e enviada em segundo plano, na ordem, e é trocada pela real quando termina (a hora continua sendo a da gravação). Se a gravação falhar, a mensagem sai e o texto volta ao campo. **Enquanto a mensagem está a caminho ela não responde a toque** (sem menu, reações nem ações). Só vale para texto escrito na barra; foto, GIF, arquivo, localização e áudio seguem como antes. O spinner vem do fork do ExyteChat (PR 9 de lá).

### Alterado
- **Menos notificações fantasma, até a Apple liberar o push filtering.** Sem essa permissão, todo push de alerta virava uma notificação visível ("New Message / New Message?", com som) mesmo quando o app decidia não notificar. Agora a extensão de notificação entrega no lugar um **aviso passivo** (sem som, sem banner, sem texto, com o nome do app como título) e o remove quando consegue: ao fim da extensão, no próximo push e ao abrir o app. Funciona junto com o patch do servidor (push em segundo plano para o que não é importante e um collapse id nos alertas), que já está no ar. Quando a Apple liberar a permissão, basta mudar `ISACLOUD_HAS_PUSH_FILTERING` para `1`. **Ainda não testado no aparelho com o servidor**: ver se o iOS respeita o aviso passivo e se ele some sozinho. Como reverter: `docs/fpush/README.md`. (Estava no build 39, enviado só ao TestFlight; o 40 o inclui.)

## 0.0.1 (build 39) — 28/10/2026

### Alterado
- **Menos notificações fantasma, até a Apple liberar o push filtering.** Sem essa permissão, todo push de alerta virava uma notificação visível ("New Message / New Message?", com som) mesmo quando o app decidia não notificar. Agora a extensão de notificação entrega no lugar um **aviso passivo** (sem som, sem banner, sem texto, com o nome do app como título) e o remove quando consegue: ao fim da extensão, no próximo push e ao abrir o app. Funciona junto com o patch do servidor (push em segundo plano para o que não é importante e um collapse id nos alertas), que já está no ar. Quando a Apple liberar a permissão, basta mudar `ISACLOUD_HAS_PUSH_FILTERING` para `1`. **Ainda não testado no aparelho com o servidor**: ver se o iOS respeita o aviso passivo e se ele some sozinho. Como reverter: `docs/fpush/README.md`.

## 0.0.1 (build 38) — 28/10/2026

### Corrigido
- **Convite por link ou QR (`xmpp:…?roster;preauth=…;ibr=y`): quem convidou agora entra na lista de contatos de quem cria a conta.** Num app sem contas, o link abre o registro com o servidor e o convite; depois do registro o app adiciona quem convidou (com o token do convite) e abre a conversa com essa pessoa. Antes ele dependia de uma tela "Adicionar contato" que, depois do registro, não aparecia (visto no Monal.alpha). Testado de ponta a ponta com o `isacloud.im` num simulador sem contas. Num app que já tem conta, o link de contato continua abrindo a tela "Adicionar contato" (ou a conversa, se a pessoa já está na lista).

### Alterado
- **A tela "Convidar para o isaCloud" mostra só o link da página de convite** (QR e compartilhar), como antes do build 37: as duas abas "Pelo site" e "No aplicativo" saíram, porque a página de convite do servidor passou a oferecer os dois caminhos (registrar pelo aplicativo ou pelo site).

## 0.0.1 (build 37) — 28/10/2026

### Adicionado
- **Convite com duas abas.** A tela "Convidar para o isaCloud" tem agora **Pelo site** (o QR e o link de compartilhar do site, como era) e **No aplicativo** (o QR e o link `xmpp:` que abre a criação de conta direto no isaCloud e, depois, adiciona quem convidou). A aba do aplicativo avisa que quem recebe precisa ter o isaCloud instalado. As abas só aparecem quando o servidor devolve os dois links; sem mudança no servidor.

### Alterado
- **A bolinha de não lidas da lista de Conversas é vermelha ou cinza.** Vermelha: conversa 1:1 não silenciada; grupo ou canal com todas as notificações ativas; grupo ou canal em "só menção" com menção a você nas não lidas. Cinza: conversa 1:1 silenciada; grupo ou canal silenciado; "só menção" sem menção. Silenciado sempre vence, mesmo com menção. A menção segue a regra das notificações (seu apelido na sala, nome de exibição, parte local do endereço ou o endereço completo) e é procurada nas 500 mensagens não lidas mais novas.

### Corrigido
- **O app podia ser fechado pelo iOS ao tocar num resultado da busca em mensagens** (visto num iPhone XR com iOS 18, no build 33). O pulo até a mensagem carrega até 3.000 mensagens, e a lista refazia a detecção de links de cada uma na thread principal, a cada comparação. Agora a detecção usa um cache, calculado em segundo plano antes de inserir as mensagens, e o resultado na tela é o mesmo.

## 0.0.1 (build 36) — 28/10/2026

### Adicionado
- **Encaminhar mídia.** A ação **Encaminhar…** do toque longo agora também aparece em foto, vídeo, áudio, GIF e arquivo (que não tenham sido retirados nem falhado). Vale a mesma folha de destinos do texto (até 5, sem o autor original, inclui as próprias notas). Se a mídia ainda não foi baixada, o app baixa sozinho (aparece "Encaminhando…"). Para cada destino o arquivo é **enviado de novo**, no servidor da conta do destino e com a criptografia do destino (o endereço com a chave nunca é copiado); só depois do envio do arquivo saem, uma logo após a outra, a linha "➦ 📷 Encaminhado" (o emoji muda: 📷 foto, 🎥 vídeo, 🎤 áudio, 🎞️ GIF, 📎 arquivo) e a mídia. Um destino que falha é pulado e aparece num aviso; os outros seguem. O rótulo sozinho também aparece em negrito e branco, como o do texto.

### Alterado
- **A hora das fotos e dos vídeos fica embaixo do balão, fora da imagem**, do lado da mensagem e com o cadeado se for criptografada, como já era nos GIFs (mudança no fork do ExyteChat, PR 8). Mensagem com legenda e a prévia de uma resposta ficam como eram.

### Corrigido
- **Encaminhar para uma conversa que não estava na lista** (inclusive as próprias notas de outra conta e uma conversa arquivada) agora coloca a conversa de volta na lista, no lugar da hora do envio. Valia também para o encaminhar de texto.
- **O app podia fechar ao abrir uma conversa no momento em que chegava uma mensagem nova** (visto uma vez no iOS 18.6): a mesma mensagem entrava duas vezes na lista e o ExyteChat aborta com ids repetidos. Agora uma mensagem já mostrada não entra de novo.

## 0.0.1 (build 35) — 28/10/2026

### Corrigido
- **O título das telas "Adicionar contato ou canal" e "Convidar para o isaCloud" sumia ao entrar, sair e entrar de novo (iOS 27).** O título agora também é colocado na barra de navegação à mão, e as duas telas usam `navigationTitle` no lugar da API antiga `navigationBarTitle(_:displayMode:)`. Testado nos simuladores do iOS 18.6 e do iOS 27.

## 0.0.1 (build 34) — 28/10/2026

### Adicionado
- **Encaminhar mensagem de texto.** No menu da mensagem (toque longo) há a ação **Encaminhar…**, que abre uma folha com contatos, grupos, canais e as suas próprias notas, com busca por nome ou endereço e a conta indicada quando há mais de uma. Dá para escolher até 5 destinos por vez; canais e grupos onde você não pode escrever aparecem apagados, com o aviso "Você não pode escrever aqui". A mensagem sai como sua, com a criptografia do destino, sem o autor original, e começa com a linha "➦ Encaminhado" (em negrito e branco no seu balão; a lista de Conversas mostra o rótulo e o texto numa linha). Em outros aplicativos a linha aparece como texto comum. Mídia (foto, vídeo, áudio, arquivo) ainda não pode ser encaminhada.

## 0.0.1 (build 33) — 28/10/2026

### Adicionado
- **Busca nas mensagens.** Na barra de busca da tela Conversas, duas abas fixas: **Nomes** (contatos, grupos e canais, como antes) e **Mensagens**. A busca em mensagens acha as palavras (a partir de 2 letras) pelo começo, sem diferenciar acento nem maiúscula, e mostra, da mais nova para a mais antiga, o nome da conversa, quem escreveu, a data (a hora, se for de hoje), um trecho com as palavras em negrito e, com mais de uma conta, a conta. Tocar num resultado abre a conversa já rolada até a mensagem, no meio da tela (se ela estiver a mais de 3.000 mensagens do fim, a conversa abre nas mais novas). Mensagens de arquivo (a URL leva a chave do OMEMO), apagadas e retiradas não entram, nem as de contas desligadas. Na primeira abertura depois da atualização o app cria o índice de busca (uns 3 segundos com 133 mil mensagens no iPhone); depois ele é mantido a cada mensagem.

### Corrigido
- **Tocar num resultado da busca (inclusive na aba Nomes) não abria a conversa no iOS 27.** A busca ainda estava fechando quando o app tentava abrir a conversa. Agora a conversa abre quando a busca termina de fechar.

## 0.0.1 (build 32) — 27/10/2026

### Alterado
- **Mudanças de banco do isaCloud numa escada própria de migrations.** Os três passos que o isaCloud acrescentou à escada do Monal com os números 7.014 a 7.016 (dias de histórico dos canais, "hats" e avatares de quem não é contato) passam a ter versão própria (`isacloud_dbversion`) e rodam depois das migrations do Monal. Assim as próximas migrations do Monal, que vão usar esses números, não são puladas nos nossos bancos. Na primeira abertura, o banco que já estava em 7.014 a 7.016 tem a versão do Monal devolvida a 7.013 (as mensagens e as tabelas continuam como estão). Testado em cópias dos bancos do simulador, do TestFlight e do Monal Beta (133 mil mensagens, versão 6.407).
- **A SQLite do app agora tem o módulo de busca de texto (FTS5).** O pacote `sqlite3-package` do Monal repassa uma lista fixa de opções e deixava o FTS5 desligado; o app passa a usar o fork `isaitgirl/sqlite3-package` (branch `isaCloud`) com `ENABLE_FTS5` ligado. É a base para a futura busca em mensagens; por enquanto nada aparece na tela.

### Corrigido
- **O spinner da lista de conversas podia ficar preso.** Quando as transferências de arquivo terminavam depois de as contas já estarem ociosas, o spinner não era atualizado e só sumia na próxima mudança de estado de uma conta ou ao voltar para o app. Agora ele também é atualizado quando as transferências terminam.

## 0.0.1 (build 31) — 27/10/2026

### Alterado
- **Menu "+" de Contatos num painel mais largo.** Os itens ("Adicionar contato ou canal", "Convidar para o isaCloud", "Adicionar via QRCode", "Criar grupo" e "Listar canais") aparecem num painel próprio, de 310 pt, com cada texto em uma linha, em vez do menu do sistema, que quebrava os textos mais longos em duas linhas. Fonte um ponto menor que a do texto normal.
- **Convite e leitura de QR code saíram da tela de adicionar e foram para o menu "+".** "Convidar para o isaCloud" (ícone de compartilhar, rosa) abre uma tela que cria o convite e mostra o QR code, a validade e o botão "Compartilhar link do convite"; com mais de uma conta cujo servidor aceita convites, há um seletor de conta. "Adicionar via QRCode" (câmera, rosa) abre o leitor. A tela de adicionar contato ou canal ficou só com o campo, sem os dois ícones do topo, e voltou a se chamar "Adicionar contato ou canal".
- **Texto de ajuda da tela de adicionar:** "Informe o endereço do contato ou do canal que você quer adicionar, no formato nome@dominio.tld." O item do menu agora diz "Adicionar contato ou canal".

### Corrigido
- **O spinner não estica mais a bolha de vidro dos botões do topo (iOS 26 em diante).** Na lista de conversas, o spinner de sincronização dividia a bolha com o botão de contatos; na janela de mensagem, o do carregamento do histórico e do envio de arquivo dividia a bolha do telefone e do cadeado. Em ambos a bolha esticava e encolhia quando o spinner entrava e saía; agora o spinner fica solto, sem bolha.

## 0.0.1 (build 30) — 27/10/2026

### Adicionado
- **Responder a foto, vídeo, áudio, arquivo e localização** (PR do Jerônimo, solução temporária). O gesto de puxar o balão e o "Responder" do menu passam a valer para mensagens sem texto, e a resposta cita um rótulo curto com emoji: `> 📷 Foto`, `> 🎥 Vídeo`, `> 🎤 Mensagem de áudio`, `> 📎 Arquivo: nome.pdf`, `> 🎞️ GIF` e `> 📍 Localização` (em grupos e canais o autor vem antes). Não mostra a miniatura nem leva à mensagem original: isso depende do XEP-0461 e do XEP-0428, que o Monal ainda não implementou (issue `monal-im/Monal#1671`).

### Corrigido
- **Lista de mensagens voltou a rolar quando o dedo começa em cima de um balão (iOS 27).** O gesto de responder disputava o toque com a rolagem. No iOS 18 em diante ele passou a ser um gesto do UIKit que só começa quando o dedo vai para a direita (PR do Jerônimo, no fork do ExyteChat e no app).
- **Menu da mensagem cortado com o teclado aberto.** Ao fazer o toque longo numa mensagem com o teclado levantado (depois de responder, por exemplo), o menu era montado no espaço acima do teclado e virava uma rolagem, com as ações cortadas; com foto ou link era pior. Agora ele usa a altura da janela e aparece inteiro.

## 0.0.1 (build 29) — 27/10/2026

### Corrigido
- **Avatar de canal de outro servidor não aparecia.** O avatar de uma sala só era buscado quando o hash chegava numa presença da própria sala; alguns servidores (visto com `isadora@xmpp.social.br` e o canal `prosody@conference.prosody.im`) não repassam essa presença. Agora o hash também é lido das informações da sala (`muc#roominfo_avatarhash`, como o Conversations faz) e, se a sala não disser nada mas aceitar `vcard-temp`, o app pede o avatar uma vez por execução. A leitura roda ao entrar na sala: um canal já adicionado sem avatar só o ganha depois de sair e entrar de novo (confirmado no TestFlight, build 29).

## 0.0.1 (build 28) — 27/10/2026

### Corrigido
- **Remover uma conta derrubava o app.** Ao remover uma conta, o Monal apagava as mensagens dela e em seguida mandava um aviso geral de atualização; cada mensagem ainda na memória tentava se recarregar do banco, e a asserção "Querying for one single history ID must always yield exactly one result" abortava o app (a conta já estava removida). Agora a mensagem que já não existe é simplesmente ignorada. Visto no isaCloud e no Monal alpha (3 quedas ao remover 3 contas).

## 0.0.1 (build 27) — 27/10/2026

### Adicionado
- **Responder puxando o balão para a direita** (PR do Jerônimo). O balão acompanha o dedo, uma seta de resposta aparece atrás, há uma vibração ao passar do ponto e o balão volta com um bounce; a citação entra no campo de texto, como no "Responder" do menu.
- **Reações no rodapé do balão** (PR do Jerônimo, com o ponto de corte e a preferência feitos em 27/10/2026). As reações aparecem em cápsulas no rodapé do balão, com o número junto do emoji. Quem preferir as bolinhas sobre o canto do balão liga "Reações acima das mensagens" em Configurações → Interface do Usuário → Aparência (desligada por padrão). A modal de quem reagiu usa componentes nativos e os emojis de cada pessoa quebram a linha, nos dois modos.

### Alterado
- **Menu principal (botão do avatar) mais atual.** As seções viram cartões arredondados, como nas telas de Configurações Gerais, e os títulos ("Aplicativo", "Suporte", "Sobre") passam a ficar centralizados na faixa, em caixa mista e semibold, em vez de colados embaixo, em caixa alta e pequenos. Saíram "Avalie o isaCloud" (levava à página do Monal na App Store) e "Enviar um bug" (abria as issues do repositório do Monal); voltam quando o isaCloud tiver página na App Store e um canal próprio de bugs.
- **Citações aninhadas, como no Conversations.** Uma resposta a uma resposta aparece com uma barra dentro da outra (`>>` é uma citação dentro de uma citação, até 7 níveis). Ao responder, a citação da mensagem desce um nível e as linhas que já estão fundas demais ficam de fora, para a resposta não crescer a cada ida e volta.
- **Lista de conversas mais espaçada** (PR do Jerônimo): linhas de 72 pt (86 pt com mais de uma conta), em vez de 60 e 74.

### Corrigido
- **Gesto de responder puxando o balão mais fluido.** O balão deixou de reconstruir a mensagem inteira a cada quadro do arrasto (o estado do arrasto passou para uma view própria), a vibração é preparada antes de ser usada e a citação e o teclado só entram depois da volta do balão (antes disputavam a thread principal com a animação).
- **Banner amarelo "Temporary failure to enter Group/Channel" voltava para o canal `discuss@conference.conversejs.org`.** O silenciamento do build 20 cobria a falha ao entrar pela presença e o timeout de entrada, mas não a falha temporária da consulta de informações da sala (`disco#info`, também `remote-server-timeout`), que seguia mostrando banner a cada tentativa. Agora esse caminho também só vai para o log (a tela que espera a sala continua recebendo o erro).

## 0.0.1 (build 26) — 26/10/2026

### Adicionado
- **Avatares de quem não é contato em grupos e canais.** Quem marcou "Foto Visível para Todos" agora aparece com a foto nas mensagens e na lista de participantes de grupos e canais, mesmo sem ser seu contato; quem não marcou continua com as iniciais. O app só busca a foto quando o hash da presença muda, guarda cada imagem uma vez e, quando a foto não está disponível, tenta de novo depois de 1 h, 6 h e 24 h.

## 0.0.1 (build 25) — 26/10/2026

### Alterado
- **Menu "+" de Contatos mais curto.** "Adicionar novo contato" virou "Adicionar contato", "Criar grupo de contatos" virou "Criar grupo" e "Canais públicos" virou "Listar canais" (a tela que abre continua com o título "Canais públicos").
- **Grupos privados sem o endereço na lista de Contatos.** O endereço de um grupo privado é um texto aleatório e não diz nada a quem usa; agora só aparece nos detalhes do grupo. Contatos e canais seguem iguais.

## 0.0.1 (build 24) — 26/10/2026

### Corrigido
- **Popup "Desativar criptografia?" cortado no iOS 27.** Agora é um diálogo preso ao cadeado, inteiro e legível.

### Alterado
- **Cadeado nos grupos e canais.** No grupo, o cadeado rosa só mostra o estado (a criptografia se muda nos detalhes do grupo); no canal, duas setas (ida e volta) com um cadeadinho rosa indicam a criptografia em trânsito. Nenhum dos dois tem ação, e tocar neles não faz mais o chat subir até o início.

## 0.0.1 (build 23) — 26/10/2026

### Adicionado
- **Várias contas: de qual conta é cada conversa.** Com duas ou mais contas ativadas, a lista de conversas mostra o JID da conta logo abaixo do nome do contato, grupo ou canal, e a lista de Contatos mostra a conta de cada um. Com uma conta só, nada muda.

## 0.0.1 (build 22) — 26/10/2026

### Adicionado
- **Várias contas: avatares na lista e no botão.** Em Configurações, cada conta mostra o avatar dela no lugar do check; a conta desativada aparece esmaecida, com uma marca de pausa. No botão do avatar da tela principal, com mais de uma conta ativada aparecem **dois avatares sobrepostos** (a primeira conta da lista na frente) e, com mais de duas, um selo "+N". Antes o botão mostrava só a foto da conta que o app abriu primeiro. O botão também atualiza assim que uma conta é adicionada, mesmo que ela ainda não tenha avatar.

## 0.0.1 (build 21) — 26/10/2026

### Adicionado
- **Pedidos de contato bem à vista.** O ícone de Contatos na tela principal ficou um pouco maior e ganhou um selo preto com o número de pedidos em branco ("9+" a partir de dez). Na tela de Contatos, os pedidos aparecem **no topo da lista**, com avatar, nome e os botões **Aceitar** e **Recusar**; o menu "…" tem "Abrir Conversa" e "Recusar e Bloquear". Aceitar ou recusar não sai da tela. Antes era preciso tocar no "+" e em "Adicionar contato" para ver o pedido. O "+" da tela de Contatos não tem mais bolinha. No iOS 26 em diante, o avatar da conta no canto de cima à esquerda não tem mais a bolha de vidro em volta: o avatar redondo (44 pt) ocupa todo o espaço do botão. O box de pedidos também saiu da tela "Adicionar contato".

## 0.0.1 (build 20) — 26/10/2026

### Adicionado
- **Reagir pela modal de reações** (do Jejê). A modal de quem reagiu agora tem **uma linha por pessoa**, em ordem alfabética, com os emojis dela à direita (faixa que rola quando não cabem). A linha **"Você" é sempre a primeira**, mesmo sem reações: tocar num emoji seu remove a reação, e o **"+"** abre o teclado de emojis do sistema para adicionar outra. A modal acompanha as mudanças enquanto está aberta. No balão das mensagens de outras pessoas, o selo de contagem não fica mais coberto pelo balão vizinho. Mudança nº 4 do fork do ExyteChat (revisão `3b4801b`). Não testado no iOS 18 nem em iPhone real pelo autor.

### Alterado
- **Menos banners de aviso.** Falhas de fundo que não impedem o uso (por exemplo "Falha temporária ao entrar no Grupo/Canal: ... remote-server-timeout", quando o servidor de outro domínio não responde) não mostram mais o banner amarelo; o timeout de entrada em sala deixou de ser um erro grave (sem banner vermelho e sem notificação com som). O mesmo aviso não grave da mesma conta aparece no máximo uma vez a cada 10 minutos. Os erros continuam no log. Quando você mesmo adiciona um canal, o erro continua aparecendo na tela de adicionar.

## 0.0.1 (build 19) — 26/10/2026

### Corrigido
- **Crash ao abrir o app logo depois de uma notificação (iOS 27).** O app caía na abertura, em `ActiveChatsViewController showWarningsIfNeeded` ("Connected xmpp* object for accountID is nil!"), e depois pedia para enviar o relatório. Causa: ao abrir o app com a extensão de notificações ainda rodando, `willFinishLaunching` espera a extensão num run loop aninhado; nesse tempo o UIKit monta a tela inicial, que pergunta pelas contas antes de `didFinishLaunching` criá-las. Agora a tela só adia os avisos (servidor sem MAM ou sem Stream Management) até as contas existirem. Visto 4 vezes em 26/10/2026 em dois iPhones com iOS 27.0.1 (builds 9 e 18).

### Corrigido
- **Foto de perfil: mudar só a visibilidade não reenvia mais a foto.** Antes, ligar ou desligar "Foto Visível para Todos" reenviava a foto inteira, e o servidor ainda recusava a primeira tentativa ("precondition not met"), então a foto subia duas vezes (~40 s em um servidor que limita o cliente a 3 kB/s). Agora o app só troca o modelo de acesso dos nós (uns 0,1 s) e só publica a foto se ela ainda não existir no servidor. Ao trocar a foto e a visibilidade juntas, a visibilidade vai primeiro.

## 0.0.1 (build 18) — 26/10/2026

### Adicionado
- **Quem reagiu.** Tocar nas reações de uma mensagem (ou de um GIF) abre uma lista com quem reagiu e com qual emoji, com filtro por emoji ("Tudo" e um chip por emoji), e o nome "Você" para a sua reação. O balão agora mostra **um círculo por emoji**, com um selo de contagem no canto de cima quando mais de uma pessoa reagiu (antes eram um círculo por reação). A lista que aparecia acima do menu do toque longo saiu. Feito pelo Jerônimo, no fork do ExyteChat (revisão `60e5f56`, mudança nº 4 em `docs/exytechat-fork.md`) e no app, com 8 testes novos do agrupamento.

## 0.0.1 (build 17) — 26/10/2026

### Alterado
- **Menu da mensagem (reações, responder, copiar...) abre bem mais rápido.** O toque longo passou de 0,5 s para 0,3 s e a animação do menu de 0,3 s para 0,15 s (antes o menu ficava completo uns 0,5 s depois do toque longo disparar; agora uns 0,25 s). Vale também para os GIFs. A mudança do toque longo está no fork do ExyteChat (`isaitgirl/ExyteChat`, branch `isaCloud`, revisão `9f4e34e`; ver `docs/exytechat-fork.md`). Se o menu abrir sem querer ao rolar a conversa, o valor está em `UIList.swift` (fork) e em `GifMessageBubble`.

## 0.0.1 (build 16) — 26/10/2026

### Adicionado
- **Apelido por grupo e canal.** Nos detalhes do grupo ou canal, "Nome de Exibição" troca o seu apelido só naquela sala; o nome de exibição da conta não muda e as salas novas continuam entrando com ele. Mostra erro traduzido quando o apelido já está em uso. O apelido vai para o bookmark da sala e os outros aparelhos da conta seguem a troca. "Usar o Nome da Conta" volta ao padrão. Testado nos simuladores iOS 18.6 e iOS 27 com dois aparelhos; conferido também no iPhone, no canal e em grupo privado.

### Alterado
- Na tela do apelido, o título e a linha dos detalhes usam "Nome de Exibição" (igual à tela de conta) e o atalho "Usar o Nome da Conta" ficou pequeno e em preto, para o "Salvar" ser o botão de destaque.
- Removido o código temporário de medição do atraso de envio que estava nos builds 13 a 15 (gravava um arquivo de log no aparelho). O atraso de ~1 s segue sem causa achada; ver `docs/decisoes.md`.

### Corrigido
- Troca de apelido de uma sala já entrada não trata mais o erro do servidor como "falha ao entrar", que apagava a sala dos favoritos e dos bookmarks.

## 0.0.1 (build 15) — 26/10/2026

### Corrigido
- **Foto Visível para Todos**: a chave agora mostra o que está no servidor (antes valia o que estava gravado em cada aparelho, e simuladores e iPhone discordavam). Ao salvar uma mudança de visibilidade, a foto é publicada de novo com a visibilidade escolhida, o que também cria os nós de avatar se não existirem.
- **Foto nos canais**: depois de trocar ou apagar a foto, o app reenvia a presença (inclusive para as salas), para os outros clientes verem o avatar nos canais. Conferido com um usuário que não tem a conta no roster.

## 0.0.1 (build 14) — 25/10/2026

### Adicionado
- **Foto Visível para Todos**: nova chave em Editar Conta para escolher quem vê a foto da conta. Desligada (padrão), só contatos veem; ligada, qualquer pessoa vê, como no Conversations. Mudar só a chave reconfigura os nós de avatar no servidor, sem republicar a imagem. O nome de exibição continua visível só para contatos. Conferido nos simuladores (linha, tradução e gravação da escolha); a mudança no servidor ainda precisa ser conferida com uma conta que não seja contato.

### Corrigido
- GIFs enviados e recebidos agora têm o mesmo que as outras mensagens: foto de quem enviou ao lado (também em conversas 1:1), horário com cadeado abaixo, ícone de status nos seus GIFs, reações exibidas no GIF e menu de toque longo para reagir, responder e excluir. O balão dos GIFs é próprio do app e tinha ficado sem essas partes.

### Alterado
- Chaves (seletores) das telas de ajustes com mais folga na margem direita, alinhadas com as setas e o separador; no iOS 27 elas encostavam e saíam da borda da tela (`MLSwitchCell.xib`, margem de 8 para 26 pt).

## 0.0.1 (build 13) — 25/10/2026

### Alterado
- Citações nas respostas agora têm **uma barra vertical contínua** à esquerda do trecho citado, em vez de um `|` por linha. Vale para linhas que quebram sozinhas e para citações de várias linhas, nos balões cinza e rosa. É feito num fork próprio do ExyteChat (ver `docs/exytechat-fork.md`).
- Ícones de status das mensagens enviadas maiores: de 10 para 16 pt, ainda alinhados pela base do balão. Convenções na seção abaixo.

### Corrigido
- Mensagem que o servidor recebeu, mas ainda sem confirmação de entrega, ficava sem nenhum ícone (a imagem do estado "enviada" do ExyteChat é vazia). Agora mostra um círculo vazado cinza com um check cinza dentro, desenhado no app.

### Convenções dos ícones de status

Aparecem ao lado das mensagens que você enviou, na base do balão. Todos são redondos e do mesmo tamanho; cinza significa "ainda não chegou ao aparelho de quem recebe", rosa significa "chegou".

| Ícone | Estado | Significado |
|---|---|---|
| Relógio cinza | Enviando | A mensagem está no app, mas o servidor ainda não confirmou o recebimento. |
| Círculo vazado cinza com check cinza | Servidor recebeu | O servidor confirmou (XEP-0198). É o estado final em canais e em contatos cujo cliente não envia confirmação de entrega. |
| Círculo vazado rosa com check rosa | Entregue | O aparelho de quem recebe confirmou a chegada (recibo de entrega, XEP-0184). |
| Círculo rosa cheio com check branco | Lida | Quem recebeu marcou como lida (marcador de leitura, XEP-0333). Em grupos privados vale quando um participante marca. |
| Exclamação vermelha | Erro | O servidor ou o destinatário devolveu erro e a mensagem nunca foi confirmada como entregue. |

Outros indicadores: o cadeado antes do horário mostra que a mensagem foi criptografada com OMEMO (sem cadeado, foi em texto aberto); a cápsula "Enviando..." acima do campo de texto é só para envio de arquivo, foto ou GIF.

## 0.0.1 (build 12) — 25/10/2026

### Corrigido
- GIF recebido em grupo ou canal aparecia solto: sem a bolinha com a foto ou inicial de quem enviou e sem o nick. Agora vem num balão cinza com o nick no topo, e a foto (ou inicial colorida) ao lado, como as outras mensagens de outras pessoas; seus próprios GIFs e os de conversa 1:1 continuam sem balão, como as outras imagens.

## 0.0.1 (build 11) — 25/10/2026

### Corrigido
- Chat deixado aberto não mostrava as mensagens que chegaram enquanto o app estava em segundo plano (o iOS grava as mensagens de uma notificação num processo à parte, e a tela só relia o banco ao ser reaberta). Ao voltar ao primeiro plano, a conversa aberta passa a buscar no banco as mensagens que faltam. Conferido nos simuladores iOS 18.6 e iOS 27.

## 0.0.1 (build 10) — 25/10/2026

### Alterado
- Anexar fotos e vídeos usa o seletor do sistema (`PHPicker`), com várias seleções, álbuns e busca. O seletor da biblioteca ExyteMediaPicker deixa de ser usado no chat.
- Textos dos pedidos de permissão (fotos, câmera, localização e microfone) traduzidos para o português (`InfoPlist.strings` do isaCloud, criado no passo de mesclagem das traduções).

### Corrigido
- Seletor de fotos do chat não rolava no iOS 27: o gesto de seleção por arrasto da biblioteca roubava a rolagem da grade "Fotos". O seletor do sistema não tem o problema (conferido no iOS 18.6 e no iOS 27).
- Adicionar contato ficava em "Adicionando..." para sempre quando o cliente da pessoa não respondia à consulta de tipo de JID (o servidor entrega a consulta ao cliente de quem está online). Passou a valer "conta" depois de 10 segundos sem resposta e o fluxo segue.

## 0.0.1 (build 9) — 25/10/2026

### Corrigido
- Crash ao abrir um canal cujo histórico tem arquivo recebido sem o registro de informações do arquivo no banco (visto no build 8, iOS 18.7, ao abrir um canal de pets). O registro agora é criado vazio na hora, em vez de derrubar o app. A causa de o registro faltar não foi determinada.

## 0.0.1 (build 8) — 25/10/2026

Reúne também o que entrou nos builds 6 e 7. O build 7 pode travar ou cair ao abrir no iOS 27 com muita coisa para sincronizar; use o 8.

### Adicionado
- Número de membros (grupos) e de participantes (canais) ao lado de "Membros do Grupo" e "Participantes do Canal" nos detalhes, e em fonte pequena abaixo do nome no topo do chat.
- Na lista de membros do grupo, a sua própria conta aparece primeiro (sem link de perfil, seletor de afiliação nem remoção).
- Aviso no seletor de histórico do canal: a mudança vale na próxima vez que o app se reconectar ao canal.

### Alterado
- Avatar da conta na tela inicial maior (40 pt) no iOS 26 ou mais novo.
- Barra superior do chat no iOS 26 ou mais novo: o indicador de carregamento só ocupa espaço enquanto carrega (a bolha de vidro deixou de ficar larga), cadeado e telefone voltam ao rosa do isaCloud, e o cadeado aberto de canais públicos fica cinza (vermelho só onde o botão funciona).
- Citações em respostas: cada linha da mensagem original vira uma linha de citação, e linhas longas quebram com a barra `│` em cada linha visual.
- Textos dos detalhes de grupo, canal e contato em Title Case, com traduções em português: "Fixar Conversa", "Mídia Compartilhada", "Arquivos Compartilhados", "2 Dias", "Histórico ao Conectar", "Notificar Apenas Quando Mencionado" e outros.
- Notificações: canais em "só menções" deixam de notificar toda mensagem (um nome vazio casava com qualquer texto).

### Corrigido
- iOS 27: o app abre (ciclo de vida por cenas), conecta a conta e atualiza as conversas; a tela inicial recupera o layout (busca abaixo do título, sem bolha vazia).
- Lista de canais públicos que ficava carregando para sempre (a conta não conectava; também ganhou limite de 20 s e mensagem de erro).
- Crash ao abrir no iOS 27 causado pelo vigia de travamento do coletor de crashes; o vigia fica desligado no iOS 27 ou mais novo.
- Travamento ao abrir o app enquanto as contas sincronizam: o aviso de "primeiro plano" no início não espera mais as filas.
- Crash ao sincronizar quando o botão de carregamento da barra saía da tela.
- Chat aberto recebendo, no mesmo momento, mensagens de um dia novo e de um dia já exibido (causava erro de atualização da lista); a mistura agora entra em duas etapas. Ainda não reproduzido em teste, então é uma correção por hipótese.

### Conhecido
- Barra de citação por linha (e não uma única barra vertical): ver o roadmap, em "Por avaliar".
- Notificações "New Message / New Message?" no app de produção: dependem da entitlement de push filtering, pedida à Apple (ver "Pendências" no `CLAUDE.md`).

## 0.0.1 (build 5) — 24/10/2026

### Adicionado
- Busca de nomes na tela inicial: contatos, grupos e canais pelo nome, com resultado que abre a conversa.
- Avatar redondo da conta no botão de perfil, atualizado quando a foto muda (aqui ou em outro app com a mesma conta).
- Colar imagem da área de transferência pelo clipe, com aviso quando não há imagem.
- Cápsula "Enviando..." e spinner no topo ao enviar arquivo.
- Autocompletar de menções (`@`) em grupos e canais, com os participantes online.
- Citação em texto ao responder ("Responder" no menu de mensagens).
- Botão "Clear share sheet queue" na tela de debug.
- Lista de domínios do isaCloud compartilhada entre criação de conta e convites.

### Alterado
- Sincronização inicial de canais públicos: 2 dias por padrão, com a opção "2 days" no seletor.
- Compartilhar pelo iOS: folha de compartilhar em rosa, com textos do isaCloud; esquema de abertura separado por build.
- Executável do app renomeado para `isaCloud`; bundle e módulo Swift mantidos.
- Títulos das telas Conversas e Contatos inline; barra de busca de Contatos sempre visível.
- Endereços de crash e contato (`sysadmin@isacloud.cc`); links de Sobre, FAQ e Privacidade apontam para `isacloud.com.br`.
- Identificação do cliente para o servidor e rótulo das notificações passam a dizer "isaCloud".
- Convites: sem landing do servidor, um domínio do isaCloud monta a página `/register?t=`; os outros recebem o link `xmpp:`.

### Corrigido
- Foto recebida aparece na conversa aberta sem precisar sair e entrar.
- Crash ao trocar o avatar pelo iPhone (atualização do botão de perfil fora da thread principal).
- Mensagens em alguns menus (Copiar, Editar, Retrair, Moderar, Excluir localmente, Reenviar) passam a ter tradução.

### Conhecido
- Travamento na sincronização inicial de canais grandes: ver a seção "Pendências técnicas" do roadmap.

## Builds anteriores (TestFlight)
- Build 6 e 7: ver o início da seção do build 8.
- Build 1 a 4: primeiros envios ao App Store Connect, com as funções de caixa de mensagem, GIF, hats, busca de canais e compartilhamento em desenvolvimento.

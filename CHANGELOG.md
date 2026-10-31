# Changelog do isaCloud para iOS

Mudanças do fork isaCloud sobre o Monal. A lista do que está feito e do que falta está em [ROADMAP.md](ROADMAP.md).

## Não publicado

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

# Abrir grupos e canais na primeira mensagem não lida

Status: **implementado e no build 87 (03/11/2026); em avaliação por alguns dias a partir de 03/11/2026.** Roadmap 136 e 137. Relacionada ao 135 (última menção) e ao 134 (arquivados).

## Objetivo

Ao abrir um **grupo ou canal**, a conversa abre na **primeira mensagem ainda não lida**, com um pouco do que veio antes visível. Se não há não lidas, abre no fim, como hoje. 1:1 não muda.

## Como o app funciona hoje (por que não basta o que existe)

- Ao abrir o chat, `ChatView.swift` (`onAppear`) chama `loadHistory()` (as mensagens mais novas, em blocos de 50 a 75) e, logo em seguida, `ChatViewHelpers.refreshCounter`, que marca **todas** as não lidas como lidas de uma vez (`DataLayer markMessagesAsReadForBuddy:...tillStanzaId:nil`) e publica o MDS. Por isso `buddylist.latest_read_message_history_id` sempre acaba na mensagem mais nova e **não diz onde a pessoa parou**.
- Já existe o mecanismo de salto da busca: `jumpToSearchedMessage()` / `scrollToSearchedMessage()` (`ChatView.swift`, ~740-790), com `DataLayer messagesForContact:...aroundMsgHistoryID:beforeMsgHistoryID:limit:` (carrega do alvo até o que já está na tela, mostrando ~20 mensagens antes do alvo) e `ScrollToParams(messageID:position:offset:)` do ExyteChat, em dois passos (0,4 s e 1,2 s) porque o primeiro erra pela altura estimada das linhas. Limite atual de salto: `maxMessagesToJumpOver = 3000` (acima disso não salta).

## Decisões da Isadora (03/11/2026)

1. **Critério: primeira não lida** (não a posição exata de saída). Sem não lidas, abre no fim. A posição exata em que a pessoa saiu (rolar de volta ao ponto visível ao sair) fica **fora**: exigiria o ExyteChat informar a mensagem visível e é menos esperada. Obs.: na conversa ela respondeu "isso mesmo" à primeira não lida, "quero isso" à posição exata e, por fim, "pode" à primeira não lida em vez da posição exata; vale a última resposta.
2. **Piscada:** implementar o mais simples (abrir no fim e saltar depois, como a busca, com o atraso de ~0,4 s) e **a Isadora avalia a sensação**. Plano B, se incomodar: esconder a lista até o salto.
3. **Limite de 200 mensagens** entre a primeira não lida e o fim. Com mais de 200, abre na 200ª mensagem mais recente (o resto vem pela rolagem normal para cima, o histórico continua carregando em blocos). Avaliação: 200 é razoável (o bloco normal é 50 a 75, a busca já aceita até 3000, e os links das mensagens carregadas são detectados em segundo plano antes de inserir), então não deve pesar nem na memória nem na rolagem.
4. **Altura estimada:** aceito o salto em dois passos, a posição pode ficar um pouco fora, como na busca.
5. **Busca vence:** se o chat abre por um resultado de busca (`jumpToHistoryId`), o salto da busca tem prioridade e a primeira não lida não roda.

## Desenho

1. **`DataLayer`** (arquivo do Monal, método novo e aditivo, `//isaCloud:`): `firstUnreadHistoryId(forBuddy:account:)`: `SELECT MIN(message_history_id) FROM message_history WHERE account_id=? AND buddy_name=? AND unread=1 AND inbound=1`; e a regra do limite (devolver o id da 200ª mais recente se o intervalo até o fim passar de 200).
2. **`ChatView.swift` `onAppear`:** só se `contact.isMuc` e sem `jumpToHistoryId`: ler o id **de forma síncrona, antes** do `refreshCounter` (que marca como lido em outra fila; se a ordem falhar a feature nunca dispara); depois de `loadHistory()`, chamar o mesmo caminho do salto da busca com esse id (ajustando `maxMessagesToJumpOver` para o limite de 200 neste caso).
3. **Nada de texto novo** nesta versão. Um divisor "Mensagens não lidas" seria extra e mexeria no fork do ExyteChat (`UIList`): fora do escopo.
4. **Não muda** o marcador de lido nem o MDS.

## Riscos e armadilhas

- **Ordem:** capturar o id antes de marcar como lido (acima).
- **Piscada:** abre no fim e depois salta; ver decisão 2.
- **Canal com milhares de não lidas:** coberto pelo limite de 200.
- **Mensagens que chegam do MAM depois da abertura** (catch-up de canal): podem criar não lidas depois do cálculo; a primeira não lida é fixada ao abrir.
- **Leitura em outro aparelho:** o MDS já limpa o `unread` das mensagens lidas no Android, então o iOS não volta para trás delas (comportamento desejado).
- **Arquivados:** um grupo arquivado conta só menções no badge (decisão do 134), mas o `unread` continua valendo para esta feature.
- **Atrito com o Monal:** baixo (um método aditivo no `DataLayer` e poucas linhas no `ChatView.swift`).
- **Teste:** iOS 18.6 e 27 (o 27 já deu problema de rolagem), grupo com poucas, nenhuma e mais de 200 não lidas; abrir por resultado de busca; validar a consulta com o banco real (regra do projeto).

## Relação com as outras frentes

- **MDS** (XEP-0490, Message Displayed Synchronization): o recurso do XMPP que avisa os outros aparelhos da mesma conta qual foi a última mensagem lida de cada conversa (o Monal publica no nó `urn:xmpp:mds:displayed:0`, `xmpp.m` ~6215-6271). É por ele que ler no Android marca como lido no iOS.
- **Roadmap 135 (última menção):** esta feature cobre a maior parte dele. Sugestão: o 135 vira só um destaque/atalho da menção dentro das não lidas (ou é encerrado). Decisão pendente da Isadora.
- **Roadmap 134 (arquivados):** dependia do 135; passa a depender desta (136), que deve vir antes.

## Implementação e testes (03/11/2026)

- `DataLayer.h/.m`: `firstUnreadHistoryIdForBuddy:forAccount:maxMessages:`. `ChatView.swift`: `maxUnreadMessagesToOpenAt = 200` e, no começo do `.onAppear` (antes do `refreshCounter`), grupo/canal sem `jumpToHistoryId` recebe a primeira não lida e reaproveita `jumpToSearchedMessage()`.
- **Simulador XR iOS 18.6** (banco de teste com 30 mensagens marcadas como não lidas no grupo "Fórum IA"): abre na primeira não lida (mensagem "Atualização: Instalei o opencode pra testar", com 20 mensagens de contexto antes) e o botão de descer aparece; depois de abrir, nenhuma mensagem fica não lida. Print: `docs/screenshots/2026-11-03-1012-iphone-xr-ios18-abrir-na-primeira-nao-lida.png`.
- **Limite de 200** (Guia XMPP, 400 não lidas): abre com 220 mensagens carregadas (200 + 20 de contexto), no meio do histórico, com o botão de descer.
- **iOS 27:** abriu na primeira não lida na segunda abertura (mesma mensagem).
- **Observação:** na **primeira abertura logo depois de instalar e iniciar o app** (nos dois simuladores) a conversa abriu no fim, sem saltar; nas aberturas seguintes (inclusive depois de reiniciar o app no XR) saltou certo. Não reproduzido de forma consistente; pode ser a abertura enquanto o app ainda sincroniza. Observar no iPhone.
- O `.onAppear` também roda ao voltar de outra tela dentro do app (por exemplo detalhes): só salta se houver não lida pendente, o que é raro porque o chat aberto marca tudo como lido.
- **Ainda não feito:** validar a consulta com o banco real exportado (regra do projeto); a posição do salto usa `.middle` (a primeira não lida aparece no meio da tela, com o contexto acima).

## Estabilização do salto (03/11/2026, a pedido da Isadora: "o salto é estranho, ainda mais com URLs")

- **Causa:** linha com URL começa como placeholder baixo do `LPLinkView` e cresce quando o preview chega (`LinkPreviewView` no fork, cache só em memória); como a lista é invertida, o crescimento das linhas mais novas que o alvo empurra o alvo para fora do lugar. A primeira abertura depois de abrir o app (cache vazio) era a pior.
- **Solução (itens 1 e 2 do plano):** (1) antes de rolar, o app busca os previews das linhas ao redor do alvo (alvo ±12, só 1 por mensagem, como o fork mostra) com prazo de 2 s (`LinkPreviewPrefetcher.prefetch`, API nova do fork); (2) a lista fica transparente até o salto assentar (`listHidden(_:)`, API nova do fork, só na lista; a barra de digitação e o cabeçalho ficam), e uma cápsula discreta "Carregando…", no estilo do "Enviando…", aparece só se passar de 0,5 s. Rede de segurança: tudo termina em 4,5 s. Vale também para o salto da busca.
- **Fork:** branch `feature/prefetch-link-previews` (2 commits, `81638b2`), sem PR ainda; o app está apontando para esse SHA no `Package.resolved` (arquivo ignorado pelo git) até o PR do fork ser mesclado.
- **Testado:** XR iOS 18.6 (cápsula "Carregando…" com lista escondida, depois abre fora do fim com o botão de descer e sem deslocamento em 8 s) e iOS 27 (card de preview já carregado ao abrir, sem deslocamento). Print: `docs/screenshots/2026-11-03-1118-iphone-xr-ios18-salto-com-previews-carregando.png`. Falta o iPhone.
- **Ficaram para depois (não feitos):** guardar os previews em disco; ancorar a posição no fork (correção de deslocamento) se ainda sobrar pulo.

## Cache em disco dos previews × altura fixa do card (03/11/2026, a pedido da Isadora)

Depois do teste no iPhone, o salto ainda incomodava. A Isadora perguntou se dava para ter um cache em disco, limitado e com validade, para os previews de link. Análise e escolha:

### Versão com cache em disco (avaliada, não escolhida)
- **Onde:** dentro de `LinkMetadataCache` (fork do ExyteChat, hoje só `NSCache` em memória), numa pasta `linkpreviews/` em Caches (o iOS pode limpar, fora do backup, sem migração).
- **Formato:** um arquivo por link (nome = hash da URL). `LPLinkMetadata` não grava direto: o título e a URL sobrevivem, mas imagem e ícone (`NSItemProvider`) se perdem. Guardar título, URL e imagem/ícone reduzidos em JPEG e remontar o `LPLinkMetadata` na leitura.
- **Fluxo:** `get` olha a memória e depois o disco; `insert` grava na memória e em segundo plano no disco; o `prefetch` usa o mesmo cache.
- **Limites:** validade de 7 dias contados do último uso, teto de 50 MB (apaga os menos usados), limpeza ao abrir o app e ao passar do teto, arquivo corrompido vira "não tinha".
- **Custo:** 100 a 150 linhas num arquivo novo do fork, mais uma linha em cada ponta do `LinkMetadataCache`.
- **Por que não:** só ajuda link **já visto antes**; o primeiro encontro com o link continua precisando da rede (cobertura do prefetch + "Carregando…"). Guarda no disco conteúdo de páginas que a pessoa nunca abriu. Tem risco de o `LPLinkView` ainda redimensionar quando a imagem decodifica depois do primeiro layout (plano B: gravar a altura final de cada preview). Mais código para manter no fork (atrito com o ExyteChat).
- **Outros elementos:** miniaturas de foto/vídeo e avatares já são arquivos locais com tamanho fixo no quadro; só o preview de link depende de rede, então não precisam de cache novo.

### Escolha: altura fixa do card (com texto "Pré-visualização indisponível")
- **Ideia (da Isadora):** com os previews ligados nas configurações, o card de cada URL já nasce com a altura final X; quando o preview chega, só o conteúdo muda dentro do espaço reservado. A linha não cresce, então a lista não é empurrada. Vale para qualquer link, inclusive os nunca vistos, que o cache não resolveria.
- **Estados do card (mesma altura X):** carregando (pill com a URL no topo, como hoje); com preview (`LPLinkView`); sem preview (ícone discreto + "Pré-visualização indisponível", centralizado, em cinza, em vez de encolher o balão). O estado "sem preview" vale quando a busca termina sem metadados ou estoura o prazo. A falha é lembrada por alguns minutos para não refazer a busca a cada rolagem; ao reabrir a conversa tenta de novo.
- **Texto:** inglês "Preview not available", pt-BR "Pré-visualização indisponível" (confirmado pela Isadora). O fork não tem tradução própria: lê a string do `Localizable.strings` do app (base + override do isaCloud).
- **Por que é melhor que o cache:** menos código, sem gravar páginas no disco, sem validade nem limite, e resolve a causa do pulo (a linha mudar de tamanho) em vez de reduzir a frequência. O cache continua possível depois, só para não "piscar" o conteúdo e funcionar sem rede.
- **Custo aceito:** cada link ocupa um card inteiro mesmo antes do preview chegar. O valor de X controla isso; escolhido testando alturas nos simuladores.
- **O prefetch + lista escondida + "Carregando…"** ficam por enquanto; podem sair depois se a altura fixa bastar.

### Implementação e testes da altura fixa (03/11/2026)
- **Valor:** X = 120 pt. Testados 90 (título em duas linhas com o domínio fica apertado), 120 (legível, imagem sem esticar, pouco vazio) e 160 (muito espaço vazio). Capturas: `docs/screenshots/2026-11-03-1328-iphone-xr-ios18-preview-altura-90.png`, `...-1329-...-altura-120.png`, `...-1328-...-altura-160.png`.
- **Visto no XR iOS 18.6:** carregando, com preview e "Pré-visualização indisponível" (URL inexistente), a mesma altura de card; a linha tem a mesma altura antes e depois do preview chegar; a falha lembrada não refaz a busca ao voltar à linha. iOS 27: cards de carregamento a 120 pt.
- **Não testado:** estado indisponível no iOS 27 e no iPhone; timeout real de 5 s; expiração dos 5 min.
- **Consequência visual:** balão só com URL fica com a largura cheia do card; balão de texto curto sem link continua estreito.
- **Dado de teste:** o banco do XR tem uma mensagem de teste (grupo Pernalonga, `message_history_id` 2519, URL `.invalid`), a remover com o app fechado quando não for mais útil.

### Medição da abertura e tempos do salto (03/11/2026)
- **Medição** (marcas temporárias `//TEMP-MEDIÇÃO`, `JUMPTIMING`, a remover antes do commit; `grep -rn "TEMP-MEDIÇÃO" Monal/Classes`): com 1 a 3 não lidas e sem link, os dados chegam à lista em ~0,2 s; a lista ficava escondida ~1,7 s por esperas fixas (scrolls em 0,4 s e 1,2 s, fim em 1,5 s) e a dica "Carregando…" aparecia em 0,5 s.
- **Ajuste:** scrolls em 0,1 s e 0,5 s, fim em 0,7 s (`jumpFirstScrollDelay` etc. em `ChatView.swift`); dica só em 1,2 s, ou 0,5 s quando há busca no banco. Resultado: ~0,85-0,95 s nos dois iOS.
- **Prefetch:** media 2,7 s (iOS 18.6) e 4,6 s (iOS 27) contra o prazo de 2 s (cancelar o `TaskGroup` não interrompe o `LPMetadataProvider`); corrigido no fork com porta de uso único, 2,1-2,2 s. Como o card tem altura fixa, o app **deixou de chamar o prefetch** (removidos `prefetchPreviewsAndScroll` e `previewURLs`): Pernalonga 3,22 s → 0,87 s (XR), canal teste 3,56 s → 0,77 s (iOS 27). Os alvos não se mexeram quando os previews chegaram (capturas 8 s depois) e os cards trocaram de pill para preview no mesmo espaço.
- **Falta:** grupo sem links, e a avaliação da Isadora no iPhone (piscada dentro do card). Se incomodar, voltar com prefetch de prazo curto (0,5 s); se estiver bom, remover `LinkPreviewPrefetcher` do fork.


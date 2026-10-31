# Estado atual e handoff (31/10/2026, build 80)

Página de passagem: o que está no ar, o que foi tentado, o que **não** repetir e por onde continuar.
Detalhes de cada frente ficam nos documentos citados; aqui está o mapa.

## Onde estamos

| | |
|---|---|
| Commit | o do **build 78** (mensagem "Build 78 ..."), tag `build-80`; `git log --oneline -3` |
| TestFlight | **80** (31/10/2026; o 79 foi o anterior, tag `build-79`) |
| `.dev` no iPhone | **80** (igual ao TestFlight, sem a sonda) |
| Simuladores | iPhone XR (iOS 18.6) e isaCloud iOS27 com o build 80 e as 3 contas de teste |
| ExyteChat | `349d33b` na `isaCloud` (a hora sobre o texto, PR 13, e a hora sempre embaixo; **está no build 77**) |
| Instrumentação temporária | **fora do código**; patches da sonda em `isaCloud/local/` (`chatjump-app.patch`, `chatjump-exytechat.patch`, ver `docs/investigacao-atraso-na-conversa.md` §8) |

Comando para conferir: `git log --oneline -3 && git status --porcelain`.

## O que entrou no build 80 (sobre o 79)

- **OMEMO com quem não é contato** (PR 23): 1ª mensagem de aparelho desconhecido aceita sob ToFU; interruptor de criptografia 1:1 espera o servidor e avisa quando o servidor não deixa não-contatos lerem a lista de aparelhos. **Falta testar em uso real** (grupo com não-contato, no iPhone ou TestFlight): conferir no log `Accepting prekey message from unknown device`. Detalhes em `decisoes.md`.

## O que entrou no build 79 (sobre o 78)

- **FTS5 à prova de falha** (PR 21): fase de build "[isaCloud] Check FTS5" (o build falha sem FTS5), `scripts/archive-testflight.sh [--upload]` (archive em pasta limpa e conferência; **use-o para os próximos builds**) e `MLMessageSearch isAvailable` com log. Detalhes em `decisoes.md` e `troubleshooting.md`.
- **"Visto por último" como ícone** (PR 22): olho cheio num círculo vazado + o tempo; a **linha da conta no topo da conversa individual está comentada** por enquanto (TODO em `ChatView.swift`, `showsAccountLine`); segue na lista e em grupos e canais.

## O que entrou no build 78 (sobre o 77)

Só a correção do **crash do build 77** (PR 20): abrir conversa individual com "visto por último" derrubava o app (`contact.lastInteractionTime != nil` sem tipo explícito: o `ObservableKVOWrapper` inferia `Any.Type` e o cast da `NSDate` lançava exceção). Achado pelo relatório de queda do iPhone e pelo rawlog de produção. **Lição:** membro do `ObservableKVOWrapper` sempre com tipo explícito (`let d: Date? = contact.x`) e testar o cabeçalho com um contato que tenha `buddylist.lastInteraction` preenchido.

## O que entrou no build 77 (sobre o 76)

Tema: **acabamento do chat** (PRs 16, 17, 18 e 19 do app, PR 13 e commit `349d33b` do fork). Detalhes em `decisoes.md`.
- **Hora e cadeado** não caem mais em cima do texto e ficam sempre embaixo dele, numa linha própria (fork: `.pushOut` no cálculo e `timeAlwaysBelowText`).
- **"Enviando…"** é uma cápsula flutuante, na cor do fundo da conversa e no tamanho de fonte do chat; não empurra mais o chat.
- **Conta da conversa** (só com mais de uma conta ativa): ícone de pessoinha na lista, e no topo do chat o endereço da conta embaixo do nome com o número de participantes ao lado do nome, entre parênteses. Conversa individual com "visto por último" usa fontes menores para caber no iOS 18.
- **Avaliação** (sem código) de criar canal público e moderação: `docs/avaliacao-canais-e-moderacao.md`. Decisões em aberto: notificação do canal criado pela própria pessoa ("tudo" ou "só menção") e o texto do aviso quando a sala não tem occupant-id/MAM.
- Pendências que seguem: balão de envio com tentar de novo (roadmap 111), teste em execução do canal que não some (108), crash raro no `ObservableKVOWrapper.addObserverForMember` ao abrir um chat com muitos links (visto uma vez no simulador iOS 18.6 em 31/10, não reproduziu na segunda tentativa).

## O que entrou no build 76 (sobre o 75)

Tema: **menos avisos técnicos ao usuário** (PR 15 do app; princípio: o WhatsApp não avisa de problema de conexão). Detalhes e o custo conhecido em `decisoes.md` ("Menos avisos ao usuário").
- Sem a notificação "Problemas de conexão" (e sem o toggle nas configurações).
- Canal **não some** dos favoritos e dos bookmarks por erro de servidor remoto (`recipient-unavailable`...): só `forbidden`, `registration-required` e `not-authorized` removem. **Não testado em execução** (precisa de login completo com um favorito de domínio inexistente).
- Tela de contas: símbolo laranja de "reconectando" no lugar do ponto.
- Sem popup quando o envio de arquivo falha (só log; a falha fica silenciosa até o balão de envio, roadmap 111).
- Só log, sem popup nem banner: servidor sem MAM/smacks/push, falha ao buscar mensagens antigas, banner de erro não grave, nove erros graves de sincronização.

## O que entrou no build 75 (sobre o 74)

- **Deadlock no download de imagens** (produção travada por mais de 2 min depois de uma rajada de fotos): `MLFiletransfer` grava o estado fora do lock, de forma assíncrona (PR 13 do app).
- **Conversa piscando em canais com reações**: id estável nas reações (PR 14 do app).
- Quem desligou o "Download automático de arquivos e mídias" na produção para abrir o app pode religar depois de instalar o 75.

## O que entrou no build 74 (sobre o 73)

- **Pílulas de reação em mídia/GIF** (cinza; a minha em rosa claro): PR 12 do app e do fork, ver `decisoes.md`.

## O que entrou no build 73 (sobre o 72)

- **GIF sem corte**: `sizeThatFits` no `AnimatedGifRepresentable` (a view assumia o tamanho do arquivo e o balão mostrava só o meio).

## O que entrou no build 72

- **Texto cortado com "…"** (causa: cadeado fora da conta da hora + `.lineLimit(1)`), corrigido no fork.
- **GIF com reações** como as das imagens (o corte do GIF **só foi resolvido depois do 72**, com `sizeThatFits`, ver `decisoes.md`)
- (antes da correção) **GIF inteiro e com reações** como as das imagens (`GifLayout`, `GifReactionsFooter`); o Release **passou no type-checker** depois do merge do PR 11, então a divisão do `body` do `ChatView` **não** é mais pré-requisito.
- **PR 11 do Jejê** (tamanho do texto nas conversas) mesclado.

Detalhes e o porquê em [`decisoes.md`](decisoes.md) ("Texto cortado com …" e GIF).

## O que entrou nos builds 65–71

- **Extensão de notificação**: reversão do fechamento do banco (o fechamento do 66 causava `SQLite3Exception: 7: out of memory`), remoção da API `closeDatabasesForCurrentThread`/`closeAllDatabases`, remoção do atraso de 1 s do placeholder.
- **Diagnóstico legível**: logs, métricas e relatórios de crash em `Library/...` (a raiz do grupo não é legível pelo `devicectl`), com migração dos antigos; cópia do log no relatório com teto de 2 MB.
- **Banco**: atribuição das esperas mais longas (`waiter`/`holders`), flags `db_lock_max_background`/`db_lock_max_suspect`, e `disconnectAll` que não derruba mais o app com conta congelada.
- **Métricas de abertura** por launch (`launches-*.jsonl`), enviadas ao harness/Grafana.

Documentos: [`plano-estabilidade-appex.md`](plano-estabilidade-appex.md), [`investigacao-atraso-na-conversa.md`](investigacao-atraso-na-conversa.md), [`decisoes.md`](decisoes.md).

## O que está em aberto (em ordem de prioridade)

### 1. Conversa "pulando"/piscando e demora no envio — **piscar resolvido no 75**

- **Resolvido:** o piscar era a lista refazendo o diff a cada reavaliação porque as reações tinham `id` novo a cada leitura; ver `docs/investigacao-atraso-na-conversa.md` §8 e `docs/decisoes.md`.
- **Resolvido:** o travamento da produção com rajada de imagens (deadlock no `MLFiletransfer`).
- **Em aberto (próximos passos, nesta ordem):**
  1. **Rajada de envios** em grupo OMEMO com muitos dispositivos: limite `c2s` de 6 kb/s no servidor + 54 chaves por mensagem causam reconexão em loop e spinner de ~90 s (roadmap 105). Decidir: subir o limite/`burst` no Prosody, limpar dispositivos OMEMO antigos das contas de teste, e/ou o app não reconectar por ping atrasado durante um envio.
  2. **Escrita no banco na thread principal** ao abrir um chat (`addActiveBuddies:`) e o `0xdead10cc` da produção às 19:46 (roadmap 106). Medir antes de mexer (arquivos do Monal).
  3. **Camada 2 do deadlock** só se a rajada voltar a pesar: `checkMimeTypeAndSizeForHistoryID:` fora da transação do parser (`MLMessageProcessor.m`).
  4. Confirmar com a Isadora, em canal movimentado, que o piscar não voltou (a medição foi no Guia XMPP, com chat quase parado).

### 1b. Próximos passos da frente "menos avisos" (build 76)

1. **Balão de envio de mídia** com spinner, erro e "tentar de novo" (roadmap 111): hoje só há o "Enviando..." acima do campo de texto e a falha de upload é silenciosa. O `ChatViewMessage` já tem `isPending` e o estado `.error` com reenvio de texto.
2. **Testar o item dos canais** com login completo (sem retomada de sessão) e um favorito de domínio inexistente; ver se o canal fica e não há banner.
3. **Erros que eram o único retorno de uma ação** e agora ficam sem aviso (apelido inválido, falha ao bloquear contato, publicar avatar/apelido): decidir se voltam como estado na tela.
4. Falhas de ação grave (criar/configurar/destruir grupo, moderar mensagem) ainda viram banner e notificação; avaliar junto com o item 1.

### 2. GIF: tamanho e reações — **resolvido no build 72** (histórico abaixo)

O que foi tentado e **por que não entrou**:

- Correção do corte (tamanho proporcional em vez de 220×220 + `.scaleAspectFill`) e reações no padrão das imagens — funcionou no `.dev`, mas **o build de Release passou a estourar o type-checker do Swift** (`unable to type-check this expression in reasonable time`) no `body` do `ChatView`.
- O problema **não era o GIF**: com o GIF revertido o erro continuou, e cada corte (extrair o builder, extrair o bloco de moderação) só empurrava o erro para o trecho seguinte. É o tamanho do `body` do `ChatView` (herdado do Monal, com toolbar + alerts + sheets numa expressão só) no limite do compilador.

**Próximo passo (superado: o Release passou depois do merge do PR 11, sem dividir)**: dividir o `body` do `ChatView` em pedaços com nome (conteúdo, apresentações/sheets, toolbar) **antes** de recolocar o GIF. Com o 71 commitado, dá para fazer isso com calma e validar cada corte com um `archive` de Release.

Decisões de desenho que continuam valendo (registradas em [`decisoes.md`](decisoes.md)):

- **Texto**: reações dentro do balão, em pills — rosa quando é reação minha em mensagem de outra pessoa, branca na minha própria mensagem.
- **Imagem e GIF**: sem balão; imagem, reações centralizadas **na largura da prévia** e sem pill (por enquanto), e hora/status abaixo à direita.

### 3. PR 11 do Jejê — **mesclado em 30/10/2026** (histórico abaixo)

Era: em revisão, **não mesclar** sem antes considerar: depende de PR par no fork (`setMessageTimeFont`), o `Package.resolved` só pode apontar para a revisão mesclada, e ele mexe no `ChatView.swift` — o mesmo arquivo que precisa ser dividido no item 2. Fazer o item 2 primeiro reduz o conflito.

## Armadilhas que custaram tempo hoje (não repetir)

1. **Instrumento que pode matar o processo** precisa de teste de controle no cenário real antes de ir para o aparelho: o primeiro vigia de main thread contava o tempo em background e abortava o app ao voltar do fundo; o defeito de base era um `dispatch_source_t` em variável local, liberado pelo ARC, que **nunca disparava** (e "zero stalls" foi lido como ausência de travamento quando era ausência de medição).
2. **Verificar que o app instalado é o build novo**: `devicectl device process launch` só traz o app para frente; é preciso matar o processo antes (`device process signal --pid … --signal SIGKILL`). Sem isso, muda-se o código e a tela continua a antiga.
3. **Nunca esconder a saída do build** com `tail -1`: foi assim que um build de aparelho falhou e o script instalou o app antigo.
4. **Não editar estrutura de arquivo por script** sem conferir o diff: já custou um `+ (void) initialize` do `MLSQLite` apagado e um `@implementation` faltando.
5. **Dados injetados no banco** precisam dos campos obrigatórios (mensagens de canal exigem `occupant_id`), senão o app quebra por causa do teste.
6. **A tela do iPhone pode ser capturada** sem a Isadora: `xcrun devicectl device capture screenshot --device <udid> --destination <arquivo>`.
7. `xcrun devicectl device info processes` lista os processos; o `.dev` e o de produção rodam ao mesmo tempo — conferir **qual** está na frente antes de concluir qualquer coisa sobre a tela.

## Branches pendentes de apagar (pedir confirmação)

`fix/deadlock-filetransfer`, `fix/reacoes-id-estavel` e `fix/avisos-de-conexao` (mesclados nos PRs 13, 14 e 15; remoto e local), `pr10-rebase`, `rebase/pr10-59` e o local `diag/chat-jump` (só tem a sonda; os patches estão em `isaCloud/local/`).

## Se precisar reativar o diagnóstico na próxima sessão

O que existia (e pode ser reescrito, agora com teste de controle antes de ir ao aparelho):

- `sends-*.jsonl` em `Library/metrics`: envio (`append`, `banco_envio`, `confirmacao`), `render` (contagem + último id), `ui_rows` (linhas + `offset`), `main_hang`.
- `main-waits-*.jsonl`: esperas da main thread pelo banco.
- `kvo-*.jsonl`: membros observados que mudam.
- tela do iPhone por `devicectl device capture screenshot`.

Tudo isso deve ficar em `#if DEBUG` (o `.dev` é Debug; o TestFlight é Release) — e **nunca** ir para produção.

## Comandos úteis

```bash
# .dev no iPhone (Debug, com App Group do .dev)
scripts/isacloud-dev-device.sh K8Y6S5RF2S 00008101-000C1DD01198001E

# arquivo de produção (Release/AppStore)
cd Monal && xcodebuild archive -workspace Monal.xcworkspace -scheme Monal \
  -sdk iphoneos -configuration AppStore \
  -archivePath "$(pwd)/../build/isaCloud-AppStore.xcarchive" \
  -derivedDataPath /tmp/ddarch -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=K8Y6S5RF2S ISACLOUD_BUNDLE_ID=br.com.isacloud.messenger \
  ISACLOUD_ENTITLEMENTS_DIR= \
  GIPHY_API_KEY="$(tr -d '[:space:]' < ../isaCloud/local/giphy-api-key.txt)"

# capturar a tela do iPhone / puxar métricas e logs
xcrun devicectl device capture screenshot --device <udid> --destination /tmp/tela.jpg
xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer \
  --domain-identifier group.br.com.isacloud.messenger.dev --source "Library/metrics" \
  --destination /tmp/metrics
```

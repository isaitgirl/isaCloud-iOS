# Estado atual e handoff (30/10/2026, fim do dia)

Página de passagem: o que está no ar, o que foi tentado, o que **não** repetir e por onde continuar.
Detalhes de cada frente ficam nos documentos citados; aqui está o mapa.

## Onde estamos

| | |
|---|---|
| Commit | o do **build 73** (mensagem "Build 73 ..."), tag `build-73`; `git log --oneline -3` |
| TestFlight | **73** (30/10/2026; o 72 foi o anterior, tag `build-72`; a tag `build-73` fica no commit do 73) |
| `.dev` no iPhone | **73 + pílulas de reação em mídia** (PR 12 mesclado; ainda não está no TestFlight, ver CHANGELOG "Não publicado") |
| Simuladores | iPhone XR (iOS 18.6) e isaCloud iOS27 com o build 73 e as 3 contas de teste |
| ExyteChat | `9131c62` (fork PR 12: pílulas de reação em mídia sem balão) |
| Instrumentação temporária | **removida** do código |

Comando para conferir: `git log --oneline -3 && git status --porcelain`.

## Depois do build 73 (ainda não publicado)

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

### 1. Conversa "pulando" e mensagens demorando a aparecer (canais movimentados)

**O que já foi medido e está provado**

- O envio é rápido: `append` 18–48 ms, banco+envio 17–64 ms, confirmação 33–69 ms, com a mensagem pendente presente na lista.
- A **tabela acompanha o modelo**: `ui_rows` = `mensagens` em todos os pontos medidos (63→63 … 68→68). A hipótese da fila de atualização do ExyteChat está **derrubada**.
- Em canal movimentado o corpo do chat é reavaliado ~3×/s, e as notificações de **participantes** são ~7× as de mensagens (520 × 70 num teste).
- O travamento real (`0x8BADF00D`, main presa > 5 s) existe, mas ainda não tem pilha simbolizada.

**Próximo passo (o dado que falta)**

Medir a **posição da rolagem** (`contentOffset`) no momento do pulo. O instrumento já foi escrito uma vez (sonda de `ui_rows` com `offset`, em `#if DEBUG`) e validado no simulador; precisa ser reaplicado e rodado no `.dev` com o pulo acontecendo. Se o `offset` oscilar, o caminho é o `UIList` (`updateTableNoAnimation` → `reloadData`, e `performInsertPreservingOffset`); se ficar estável, o pulo é outra coisa (animação de inserção/altura de célula).

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

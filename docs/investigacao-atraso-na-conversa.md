# Investigação: atraso e "pulos" na conversa

**Aberto em 30/10/2026.** Pergunta: por que, em canais movimentados, as mensagens (enviadas **e** recebidas)
demoram 10–15 s para aparecer, a tela "pula" e a mensagem enviada aparece já como entregue, sem spinner.

Este documento registra o que foi **medido**, o que é **inferência**, o que já foi **derrubado** e como cada
hipótese pode ser confirmada ou refutada. Ele precede qualquer correção.

## Resumo

| Camada | Medida no aparelho | Situação |
|---|---|---|
| Envio (append → confirmação) | 26–57 ms, pendente presente | **rápido** |
| Banco (esperas da main thread) | zero acima de 500 ms; uma de 437 ms | **não é o gargalo** |
| Corpo do chat reavaliado (canal) | 3–4/s antes, 1,1–1,3/s depois da correção do contador | **churn alto** |
| Lista (aparecer na tela) | ~15 s de atraso | **é aqui** |
| Travamento | `0x8BADF00D` (watchdog do iOS, main presa > 5 s) | **hang de main thread** |

## 1. Como a lista se atualiza (leitura do código)

- `ChatView.init` recalcula as seções: `ChatView.swift:642` → `mapMessages`.
- `UIList.updateUIView` (`Views/UIList.swift:82`) compara `latestUpdateSections != sections` e só segue se mudou.
- Cada atualização vira um **job** numa fila serial (`Views/UIList+Queue.swift`): `createJob` enfileira,
  `processNextIfNeeded` processa **um por vez**.
- Aplicação na tabela por três caminhos:
  - `updateTableNoAnimation` (`UIList.swift:286`): **`reloadData()` + `layoutIfNeeded()`**;
  - `updateTableWithAnimation`: diff em background + `performBatchUpdates`;
  - `performInsertPreservingOffset`: diff + inserções preservando a posição.
- O scroll animado custa **0,25 s** e o job **espera** a animação terminar.

**Fato relevante:** a fila **não coalesce**. Se as atualizações chegam mais rápido do que os jobs terminam, ela
cresce sem limite.

## 2. O que já foi medido

- `sends-*.jsonl` (aparelho): `append` 26–48 ms, `banco_envio` 46–56 ms, `confirmacao` 45–57 ms, `pendente_na_lista: true`.
- `main-waits-*.jsonl`: uma espera de **437 ms** pelo lock de escrita (main). Os `main_stall` **não valem como
  evidência**: descobrimos em 30/10 que o vigia nunca rodou (ver §5) — o "zero stalls" era ausência de medição, não
  ausência de travamento.
- `render`: 3–4/s no canal (78 notificações de participantes contra 6 de mensagens); caiu para 1,1–1,3/s
  depois de tirar o contador de participantes do corpo do chat.
- Diagnóstico do iOS: `0x8BADF00D`, "Failed to terminate gracefully after 5.0s", foreground, 14% CPU.
- `kvo-*.jsonl`: poucas mudanças (`MLMessage.hasBeenSent`, 1–2 por 5 s) — o churn **não** vem do KVO de mensagens.

## 3. Hipóteses

### H1 — fila de atualizações da lista (principal)

`sections` muda a cada mensagem nova/status; cada mudança enfileira um job que faz `reloadData` (ou batch updates
+ animação). Com churn de 3–4/s e jobs de ~250 ms, a fila cresce e a lista fica 10–15 s atrás; ao parar a
atividade, aparece tudo de uma vez. A mensagem pendente (vida de 50–70 ms) é adotada pela salva antes de o job
que a mostraria rodar — daí "aparecer já entregue".

**Como confirmar:** medir a profundidade da fila e a duração de cada job, e comparar o **número de linhas na
tabela** com o **número de mensagens no modelo** ao longo do tempo.

### H2 — parser/rede atrasando a chegada

A mensagem recebida pode chegar tarde ao app (parser preso no lock de escrita), e não só tarde à tela.

**Como confirmar:** marcar o instante em que o stanza entra no parser e o instante em que a linha é construída.

### H3 — envio/entrega lenta na rede

"Enviar" pode estar rápido no app e lento na entrega (servidor/fila XMPP), o que explicaria o "15 s para ir".

**Como confirmar:** comparar `salvo no banco` × `recibo (hasBeenSent)` com carimbo de tempo.

## 4. O que já foi derrubado

- **Lock do banco** como causa do envio: `main-waits` praticamente vazio e envio em 26–57 ms.
- **Main thread travada durante o envio**: sem evidência válida — o vigia de main thread estava **desligado na
  prática** (o `dispatch_source` local era liberado pelo ARC e nunca disparava). O travamento `0x8BADF00D` é real,
  mas não temos medição própria dele ainda.
- **Churn de participantes como causa única do pulo**: a correção reduziu (3,2 → 1,1/s), mas não eliminou.
- **Captura do hang pelo nosso abort**: ele esperava 5 s, empatava com o iOS e perdia a corrida (corrigido para 2,5 s).

## 5. Instrumentação desta rodada (só `.dev`, sem tocar em produção)

1. **Sonda da tabela** (`ui_rows`): a cada 100 ms lê `numberOfRows` da `UITableView` do chat (identificada por estar
   rotacionada em 180°, `transform.a == transform.d == -1`) e grava quando muda. Comparada a `render.mensagens`, diz
   se a **tabela** está atrás do **modelo** — ou se o dado nem chegou ao modelo.
2. **`render` com id e pendência**: cada reavaliação do corpo registra `mensagens`, o **id da última mensagem** e se
   ela ainda é pendente — liga o modelo a um instante e a uma mensagem.
3. **`kvo` (`kvo-*.jsonl`)**: mudanças de propriedades observadas (ex.: `MLMessage.hasBeenSent`), que marcam o recibo.
4. **Vigia de main thread consertado**: o `dispatch_source` agora é retido; se a main ficar 2,5 s parada, o app
   aborta de propósito e o KSCrash grava a pilha de todas as threads (antes disso, ele simplesmente não rodava).

**Defeitos encontrados no caminho (os dois no vigia):**

1. O `dispatch_source_t` vivia numa variável local, liberada pelo ARC — o vigia **nunca disparava**. Toda conclusão
   baseada em "não houve stall" foi invalidada; o timer passou a ser retido.
2. Ao voltar do background, o **primeiro tick** comparava com o batimento velho (de antes da suspensão) e via ~27 s
   de "travamento", abortando o app. Ele agora reinicia o batimento em `UIApplicationDidBecomeActiveNotification`,
   ignora o tempo em background (`appState != 0`) e exige 2 s de app ativo antes de considerar um travamento (3,5 s).

**Lição de método:** instrumento que pode matar o processo precisa de **teste de controle no cenário real**
(background → foreground) antes de ir para o aparelho de alguém.

## 6. Revisão crítica desta análise

- H1 depende de `sections` realmente mudar a cada render. A igualdade compara id/status/posições (`MessageRow.swift:79`),
  então **pode não haver job** quando nada muda — se a sonda mostrar tabela e modelo sempre juntos, H1 cai.
- `reloadData` numa conversa de 50–55 mensagens é barato; H1 só explica 15 s se os jobs forem **muitos** (fila
  crescendo), não se cada um for caro.
- A mensagem recebida da amiga nunca foi medida de ponta a ponta; a simetria com o envio é **inferência**.
- "Aparecer" e "ir" podem ser fenômenos distintos (tela vs. rede) — a instrumentação desta rodada separa os dois.
- O vigia de main thread (e, depois, a sonda da tabela) **nunca disparava** por um erro meu de retenção do
  `dispatch_source` — o mesmo tipo de erro que já quase me fez "consertar" o que não estava quebrado. Antes de
  confiar num instrumento, é preciso ver **um evento dele** no arquivo.
- O simulador **não reproduziu** o atraso (mesmo com 600 mensagens e envios em sequência), o que sugere que o
  ingrediente que falta é atividade real de canal — e é uma pista de que o problema pode estar no caminho do
  **recebimento**, não só na renderização.

## 7. Estado em 30/10/2026 (build 71 no TestFlight e no `.dev`)

**Provado com medição**
- O envio é rápido (26–57 ms, mensagem pendente presente) e o banco não trava a main.
- A **tabela acompanha o modelo**: `ui_rows` e `mensagens` sempre no mesmo valor (63→63 … 68→68). A hipótese da fila de atualizações (H1) está **derrubada**.
- Em canal movimentado, o corpo do chat é reavaliado ~3×/s e as notificações de **participantes** são 7× as de mensagens (520 × 70).

**Em aberto**
- A **posição da rolagem** (`contentOffset`) ainda não foi medida com o pulo acontecendo — é o próximo dado. A sonda do `.dev` já registra `offset` junto com `linhas`.
- Não se sabe ainda por que a volta ao primeiro plano e a atividade de outras pessoas mexem na rolagem.

**Como seguir**
1. reproduzir o pulo no `.dev` (canal com outras pessoas interagindo) e puxar `Library/metrics`;
2. comparar `offset` antes/depois do pulo: se oscila, o caminho é o `reloadData`/`performInsertPreservingOffset` do `UIList`;
3. só então corrigir, com antes e depois medidos.

**Instrumentação** (toda em `#if DEBUG`, fora do build de produção): `sends-*.jsonl` (envio, render, `ui_rows` com `offset`, `main_hang`), `kvo-*.jsonl`, `main-waits-*.jsonl`.

## 8. Resultado (30/10/2026, à noite, build 75)

**O "pular" era, na verdade, piscar, e a causa foi achada e corrigida.** A sonda de rolagem (só DEBUG, fora do Git) mostrou que a posição (`contentOffset`) **não oscila**; o que muda sozinho é a altura total (`contentSize`) e uma linha de 32 pt que liga e desliga logo depois de cada reavaliação do corpo do chat. Um log temporário no `UIList.updateUIView` do ExyteChat (qual campo das linhas mudou, qual caminho rodou) mostrou: 38 de 49 atualizações eram só "reações mudaram" em 4 mensagens de texto, sem mensagem nova, 44 pelo caminho animado. Causa: `ChatViewMessage.reactions` criava `Reaction` com `id` (UUID) novo a cada leitura. Corrigido com id estável; 27 reações em 2 s geraram 0 atualizações espúrias. Detalhes em `docs/decisoes.md` ("Lista que piscava").

- **H1 (fila de atualizações)** continua derrubada como causa da demora, mas a lista **refazia o diff a cada reavaliação** em chats com reações (o churn de 3 a 4 renders por segundo se transformava em 3 a 4 `performBatchUpdates` por segundo).
- **A demora de 10 a 15 s no envio** (H3) tem agora uma pista forte, separada da tela: reconexão em loop por limite de envio do servidor (`c2s` 6 kb/s) com mensagens OMEMO de ~15 KB (grupo com 54 chaves). Registrado em `docs/decisoes.md` e no roadmap (linha 105). Não foi corrigido nem medido em um canal comum.
- **Travamento (`0x8BADF00D`)** que estava "sem pilha simbolizada" ganhou causa em produção: deadlock no `MLFiletransfer` (linha 103 do roadmap).
- **Lição de método:** a primeira sonda interceptava métodos da `UITableView` e derrubou o app (`Invalid number of sections`); sondas passivas (observar valores) bastam. E antes de interpretar "msgs 0 -> 50" como recriação do chat, cruzar com o log do app (era só a Isadora abrindo chats).
- **Como reativar a sonda:** `git apply isaCloud/local/chatjump-app.patch` (app, só DEBUG) e aplicar `isaCloud/local/chatjump-exytechat.patch` nos checkouts do SwiftPM (`build/dev-device/SourcePackages/checkouts/ExyteChat`; precisa de `chmod u+w` no `UIList.swift`). Nunca commitar.

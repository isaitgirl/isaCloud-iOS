# isaCloud para iOS

Fork do Monal (cliente XMPP para iOS) com a marca e os ajustes do isaCloud. Branch de trabalho: `isaCloud`.

**Dipi** é o nome que a Isadora deu ao agente que trabalha neste repositório (28/10/2026). Ela chama o agente assim; o agente responde por esse nome.

## Instruções

- Pode ser simpático, sem ser engraçadinho demais o tempo todo!
- Responda às gentilezas e elogios com simpatia e humildade :)
- Qualquer alteração que possa causa complexidade no merge com o Monal deve ser validada.
- Os builds e testes devem sempre levar em consideração do iOS 18 ao 27.
- Não perguntar a todo instante sobre commitar o projeto, aguardar instrução do usuário.
- **"Fazer novo build e push"** quer dizer, nesta ordem: subir o número do build e enviar ao TestFlight (`docs/publicacao-testflight.md`); atualizar o iPhone com a mesma versão; atualizar o `CHANGELOG.md`; atualizar o `ROADMAP.md` se for feature; atualizar `docs/decisoes.md` (e `docs/exytechat-fork.md`) quando for relevante para merges futuros com o Monal e o ExyteChat, citando o Conversations quando a ideia veio de lá; commit com mensagem bonita e descrita; push. Se houver mudança no fork do ExyteChat, o PR do fork é mesclado antes e o `Package.resolved` aponta para o SHA mesclado.
- **"Fazer novo build"** (sem "e push") é o mesmo sem o commit e o push: atualiza docs, TestFlight e iPhone e deixa as mudanças sem commit.
- As traduções devem seguir os padrões do Monal, considerando o merge com weblate, mas as traduções do isaCloud devem prevalecer sobre elas.
- Estamos escrevendo o software em pt-br, mas você deve seguir as convenções de código do Monal, usando o idioma padrão dele e usando nosso mecanismo de tradução pro pt-br.
- Se identificar textos em inglês não traduzidos nos simuladores, você deve avisar o usuário e confirmar qual será a tradução.
- **Ao final de uma tarefa que atualiza os simuladores, atualizar também o `isaCloud.dev` no iPhone** (`scripts/isacloud-dev-device.sh`), sem esperar pedido, e avisar quando ele tiver código que ainda não está no TestFlight.
- **Build não é a cada correção.** A produção tem as contas oficiais da Isadora: **acumular correções** e só subir o número/TestFlight quando ela pedir (ou quando ela realmente precisar usar o isaCloud de produção). Enquanto isso, implementar, testar nos simuladores e **adiantar no `isaCloud.dev`** (sem bump) — o `.dev` pode ficar com código que ainda não está no TestFlight.
- **Ao atualizar o `ROADMAP.md`**: riscar (`~~...~~`) **todo** item concluído — inclusive os que só tinham "feito" na coluna de esforço — e refazer o resumo que fica antes da tabela ("**Total de features no roadmap:** N" e "**Features concluídas:** N"). As contagens saem das próprias linhas da tabela (total de linhas numeradas; concluídas = as riscadas), não de memória.
- **Antes de mexer em rotina de banco (queries, migrações, reconciliação), validar com banco real**: pedir o banco oficial exportado (TestFlight) ou usar o do `.dev`, e rodar a query nele. Teste com linha fabricada no simulador já escondeu dois bugs (o `received=NULL` e o `retracted=1` do spinner, 29/10/2026).
- **Branches**: `isaCloud` é a de trabalho e a única que vai para o TestFlight. `develop` fica no repositório só como **ponto de atualização** para buscar commits do Monal (alpha/upstream) sob demanda — não é para desenvolvimento. `pr10-rebase` é local e fica guardada até a decisão sobre o PR 10 (controles na parte de baixo da tela) ser tomada com o Jejê.
- **Mudanças de banco do isaCloud** entram na escada própria (`+migrateISACloudDB:` em `DataLayerMigrations.m`, flag `isacloud_dbversion`), nunca como 7.0xx na escada do Monal, e cada passo deve poder rodar de novo sem estragar nada. Detalhes em `docs/decisoes.md`.
- Busque implementar seguindo as convenções atuais do Monal, é importante respeitarmos esse legado para mantermos a menor fricção possível nos merges futuros.

## Capturas de tela

- Salve toda captura de tela do simulador que mostre o app em `docs/screenshots/`, inclusive as tiradas só para conferir uma mudança.
- Nome do arquivo: `AAAA-MM-DD-HHMM-<aparelho>-<ios>-<tela-ou-assunto>.png`, em minúsculas e com hífens. Exemplo: `2026-10-23-1359-iphone-xr-ios18-boas-vindas.png`.
- Não apague nem sobrescreva capturas antigas; elas registram como o app estava em cada momento.
- As capturas feitas pela Isadora no app Simulator (⌘S) também caem nessa pasta, com o nome padrão do Simulator.

## Notas locais (fora do Git)

- Dados sensíveis ou pessoais (UDID de aparelhos, números de pedidos da Apple, contas de teste, caminhos de segredos) ficam em `isaCloud/local/NOTAS-LOCAIS.md`, que está no `.gitignore`. Modelo em `docs/NOTAS-LOCAIS.exemplo.md`.
- Os `.md` que vão para o Git (como este) não podem conter esses dados: aponte para as notas locais. Nunca cole valores de segredos em nenhum `.md`.

## Contas e servidores de teste

- Os testes nos simuladores e no iPhone da Isadora usam basicamente três contas de teste (endereços em `isaCloud/local/NOTAS-LOCAIS.md`, que não vai para o Git). Duas ficam no servidor `isacloud.im` e uma no `autozona.cc`.
- **`isacloud.im`: Prosody 13.0.7.** **`autozona.cc`: ejabberd 26.09.** Vale lembrar disso ao investigar diferenças de comportamento entre servidores (avatares, MUC, push, MAM, upload de arquivos).

## ExyteChat (fork)

- O chat usa um fork nosso do ExyteChat (`isaitgirl/ExyteChat`, branch `isaCloud`, clone em `~/projects/swift/ExyteChat`). Mudanças na biblioteca ficam lá, pequenas, comentadas e em commits separados. Depois de cada commit no fork: push na branch `isaCloud` e atualizar a revisão em `Monal/Monal.xcworkspace/xcshareddata/swiftpm/Package.resolved` (senão o TestFlight compila a versão antiga). Rotina de atualização, a revisão atual e o que o fork muda: `docs/exytechat-fork.md`. Depois que um PR é mesclado, apagar o branch dele (no GitHub e local) e deixar os clones na `isaCloud`, **sempre pedindo confirmação antes de apagar**.
- Toda mudança nasce em um branch novo criado a partir de `isaCloud` e volta por PR do branch novo para `isaCloud` (nunca para `develop`), no app e na biblioteca. Todo PR tem a `isaitgirl` como revisora e responsável e traz prints de antes e depois das mudanças visíveis, feitos só com dados de teste. Detalhes em `docs/exytechat-fork.md`.

## Decisões e pendências

- **Nunca apagar nada em `tools/metrics-harness/`** — `.credentials` e `.sent-state.json` são dados de quem usa o harness, não arquivos temporários (já apaguei o `.credentials` da Isadora duas vezes, 29/10/2026). Para testar, usar `--credentials /tmp/<arquivo>` ou `INFLUX_CREDENTIALS`, nunca o arquivo real.
- **Métricas do aparelho:** o app coleta amostras (memória, CPU, bateria/térmica, banco) e os payloads do MetricKit em `<grupo>/metrics`, exportáveis pelo Depuração ("Métricas do aparelho" → "Exportar métricas"). O harness que envia para o InfluxDB/Grafana fica em `tools/metrics-harness/` (credenciais em `.credentials`, fora do Git); detalhes em `docs/decisoes.md` e no README do harness.
- **Decisões** (o porquê das escolhas de projeto, de código e do fork, e o que foi descartado): `docs/decisoes.md`. **Funcionalidades e pendências** (feito, em andamento, a fazer, bugs conhecidos): `ROADMAP.md`. Ao tomar uma decisão nova, registre no `docs/decisoes.md` **e** numa linha do roadmap; resultados de teste e pendências ficam só no roadmap. O código temporário de medição, quando existir, não deve ser commitado.

## Troubleshooting

- Comandos e procedimentos para investigar crashes e travamentos (TestFlight e isaCloud.dev, iPhone e simulador): `docs/troubleshooting.md`. Quando aprender um comando útil novo, acrescente lá.

## Simulador controlado por fora (agente)

- Como tocar, digitar e capturar o simulador sem XCUITest — DeviceHub (não o Simulator do Xcode 26.2), as permissões, keycodes em vez de texto unicode e a calibração framebuffer→tela: `docs/DeviceHubControl.md`.

## Pendências

- **Reativar o push filtering.** A entitlement `com.apple.developer.usernotifications.filtering` foi removida em 23/10/2026 de `Monal/Monal.ios.entitlements` e `Monal/NotificationService/NotificationService.ios.entitlements`, porque a Apple só a libera mediante pedido (texto de referência em `push_filtering_entitlement.md`). Sem ela, todo push vira notificação visível. Pedido enviado à Apple em 24/10/2026 (número do pedido em `isaCloud/local/NOTAS-LOCAIS.md`); a resposta chega por e-mail. Enquanto isso, o app de produção mostra a notificação genérica "New Message / New Message?" (texto do payload do `fpush`) quando decide não notificar. Depois de aprovada para a conta do isaCloud, ativar a capacidade nos App IDs do app e da extensão (`br.com.isacloud.messenger` e `.notificationService`), recolocar `<key>com.apple.developer.usernotifications.filtering</key><true/>` nos dois arquivos. **Junto, reverter o patch provisório dos avisos fantasma** (28/10/2026, `docs/fpush/README.md`): mudar `ISACLOUD_HAS_PUSH_FILTERING` para `1` em `Monal/Classes/HelperTools.m` e, no servidor, desfazer o patch do fpush (`0001-...v2.patch`) e o `cloud_notify_quiet`.

## Planejamento e delegação (Claude Code)

- A sessão principal roda em Sonnet 5.5 com esforço alto (`.claude/settings.json`) e cuida da avaliação, do planejamento e da revisão. A execução fica com o subagente `executor` (Haiku 5.5, `.claude/agents/executor.md`).
- Para qualquer tarefa que altere código, primeiro investigue e monte o plano. Depois que a Isadora aprovar, delegue a implementação ao `executor` em vez de editar os arquivos na conversa principal. Mudanças triviais (uma linha, um texto, um ajuste de doc) podem ser feitas direto.
- Sempre que delegar, escreva para o subagente instruções completas e autossuficientes, porque ele começa sem o contexto desta conversa: objetivo; arquivos e símbolos exatos (caminho, classe, método); passos numerados na ordem; trechos de código ou assinaturas esperadas quando ajudarem; o que não deve ser tocado; como validar (comando de build, teste, simulador e versões de iOS); e o formato do relatório esperado.
- Tarefas independentes podem ir para mais de um `executor` em paralelo; tarefas que mexem nos mesmos arquivos vão para um só.
- Ao receber o relatório, revise o diff antes de dar a tarefa por concluída. Se o `executor` apontar divergência entre o plano e o código, replaneje aqui em vez de mandar ele improvisar.
- Commits, push, PRs e a rotina de "fazer novo build" continuam com a sessão principal, seguindo as regras acima.

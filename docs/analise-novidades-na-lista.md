# Análise: "Novidades do isaCloud" no topo da lista de conversas

Análise de 11/11/2026. Nada implementado ainda. A referência é o isaCloud Messenger (Android), releases 2.21.0-64 a 66.

## Como o Android fez

### Fonte dos textos
- O texto vem do `docs/CHANGELOG-users.md` (o mesmo que vai para as redes e para o Guia XMPP).
- `scripts/generate-changelog-json.py` converte o Markdown em `res/raw/changelog_users.json` e valida o resultado: release sem seção ou seção sem itens dá erro, e a ordem é conferida (mais nova primeiro). Usa `## <versão> — <data>`, `**Seção**` e itens `- ...`, e tira o `**`/`` ` `` dos itens.
- O JSON vai **embutido no APK**. Não há rede: o app só conhece as novidades da versão que está instalada.

### Estado (`ChangelogStore`, SharedPreferences `changelog`)
| Chave | Para quê |
|---|---|
| `last_run_version` | versão da última abertura |
| `batch_from` / `batch_to` | o "lote" de versões a mostrar: `(from, to]` |
| `first_run` | instalação nova (ou primeira vez com a feature) |
| `read_version` | até que versão o lote já foi lido (selo "Novo") |
| `archived_version` | até que versão o item foi arquivado |

`recordLaunch()` roda uma vez por processo, em `Conversations.onCreate()`:
- **sem versão anterior** (instalação nova ou primeira versão com a feature): o lote é só a release atual, não o histórico inteiro;
- **atualização**: o lote vai da versão anterior (exclusive) até a atual, então quem pulou versões vê todas as que pulou;
- **mesma versão**: mantém o lote;
- **downgrade**: lote vazio.

`getBatch()` monta o lote e calcula `unread` (lido < atual) e `visible` (tem release e não foi arquivado nesta versão). Arquivar vale **só até a próxima atualização**: a versão nova traz o item de volta.

### Na lista
- Um `ChangelogAdapter` separado, juntado à lista com `ConcatAdapter(changelogAdapter, conversationsAdapter)`. Tem 0 ou 1 linha.
- A linha imita uma conversa: ícone do app, título "Novidades do isaCloud", selo rosa "Novo" enquanto não lida, data da release mais nova à direita e a prévia "Veja o que mudou na versão 2.21.0-66" (ou "nas versões 64, 65, 66", da mais antiga para a mais nova, só com o número quando a base é a mesma).
- Um **botão de arquivar na própria linha** (não é deslizar). Arquivar mostra um Snackbar "Novidades arquivadas. Reabra em Configurações → Sobre." com **Desfazer**.
- Só aparece na visão "Todas" (nenhum filtro ativo). Entra na conta do estado vazio (a lista com só o item de novidades não mostra a dica de lista vazia) e na posição de rolagem salva.

### Tela de novidades (`ChangelogActivity`)
- Lista as releases do lote: "Versão X • data", seções com título na cor primária e itens com "•".
- Abrir a tela **marca como lido** (o selo some).
- Se o item estiver arquivado, mostra o botão "Mostrar na lista de conversas" (desarquiva).
- Link "Ver changelog completo" para o `CHANGELOG-users.md` no Codeberg.
- Também se chega a ela por Configurações → Sobre (botão "changelog").

## Como fazer no iOS

### 1. Fonte: `CHANGELOG-USERS.md` → JSON no bundle
O nosso `CHANGELOG-USERS.md` já tem o formato certo: `## Build 104 · 11/11/2026`, `### Novidades`, itens `- 🚪 ...`. A versão no iOS é o **número do build** (`CFBundleVersion`, inteiro e sempre crescente), então a comparação é `Int` contra `Int`, sem o parser de `major.minor.patch-release` do Android.

**Armadilha principal: "Próximo build".** Na nossa rotina de "novo build", o `CHANGELOG-USERS.md` ganha o número do build **depois** do archive (passo 3, o archive é o passo 1). Se o JSON for gerado do arquivo como está, o build 105 sairia com uma seção chamada "Próximo build" e sem o 105. Opções:
- **(recomendada)** o gerador trata `## Próximo build` como o `CURRENT_PROJECT_VERSION` do projeto, com a data do dia. O build sai certo mesmo com o Markdown ainda sem fechar, e a rotina não muda;
- ou mudar a rotina para fechar o `CHANGELOG-USERS.md` antes do archive.

Onde gerar:
- **(recomendada)** um script `scripts/isacloud-generate-changelog-json.py` (pode partir do script do Android) chamado pelo `archive-testflight.sh` e pelo `isacloud-dev-device.sh`, gravando `Monal/isaCloud-changelog.json` (commitado, no target do app como recurso). Assim dá para ver no diff o que vai no build;
- uma Run Script phase no Xcode também funciona, mas mexe no `project.pbxproj` e roda em todo build (inclusive nos do simulador), e erro de script quebra o build.

O JSON não precisa ir para as extensões (notificação e compartilhar), só para o app.

### 2. Estado: `ChangelogStore` em Swift
Mesma lógica do Android, com `Int` no lugar das strings de versão. Chamar `recordLaunch()` em `MonalAppDelegate` no `didFinishLaunching` (depois de uma atualização o processo é sempre novo, então isso basta).

Guardar em `UserDefaults.standard` (só o app lê; não precisa do app group). Se for para o `HelperTools.defaultsDB` com o property wrapper `@defaultsDB`, **toda chave precisa de padrão registrado antes da leitura**, senão crasha (C18). Com `UserDefaults.standard.integer(forKey:)` / `string(forKey:)` direto, ausência é 0/nil e não há esse risco.

Ponto de partida das instalações atuais: ninguém tem `last_run_build`, então quem atualizar para o primeiro build com a feature cai em "primeira vez" e vê só esse build. Se quiser que o primeiro lote mostre mais (por exemplo, os builds desde o último que a Manuela e a turma usaram), dá para tratar "sem versão anterior **e** banco já existente" como atualização a partir de um build fixo (ex.: 100). O Android não fez isso.

### 3. Na lista (`ActiveChatsViewController.m`)
A lista é uma `UITableView` com duas seções (`pinnedChats`, `unpinnedChats`) e o enum é usado em ~12 lugares que assumem "se não é fixada, é não fixada" (`cellForRow`, `didSelect`, `commitEditingStyle`, `accessoryButtonTapped`, busca de `indexPath` em `refreshDisplay`/`insertOrMoveContact`...). Há dois caminhos:

**A. `tableHeaderView` (recomendado)** — o equivalente mais próximo do `ConcatAdapter`: uma view à parte, em cima da lista, sem tocar no data source.
- Uma `UIView` (ou `UIHostingController` com SwiftUI) com o mesmo visual da `MLContactCell`: ícone do app arredondado, "Novidades do isaCloud" em negrito, selo "Novo" rosa, data à direita, prévia em cinza claro, separador embaixo. Altura igual à das linhas (72 pt, ou 86 pt com mais de uma conta, como em `heightForRowAtIndexPath`).
- **Botão de arquivar na linha**, como no Android (não precisa de deslizar, que exigiria ser uma linha da tabela).
- Toque: `showDetailViewController` com a tela de novidades (no iPad abre na coluna da direita, como uma conversa).
- Cuidado conhecido: `tableHeaderView` com Auto Layout não se dimensiona sozinho; é preciso calcular o frame (`systemLayoutSizeFitting`) e reatribuir o header quando a altura muda (mais de uma conta, Dynamic Type).
- Contras: não participa do destaque de "conversa aberta" do iPad e não tem o deslizar para arquivar. O Android também não tem.

**B. Terceira seção na tabela** — ficaria idêntico a uma conversa (deslizar "Arquivar", destaque no iPad), mas exige uma seção nova antes de `pinnedChats` e guardas em todos os pontos que hoje deduzem a seção. É código do Monal que muda bastante a cada merge; mais risco de conflito e de crash por índice errado. Não recomendo para o primeiro passo.

Nos dois casos:
- **Filtros**: só mostrar quando nenhum chip de filtro estiver ativo e nenhuma conta estiver oculta (o mesmo critério que hoje deixa a lista "incompleta"), como o Android faz com `activeFilters.isEmpty()`.
- **Busca**: esconder enquanto a busca estiver ativa.
- **Estado vazio**: `emptyDataSetShouldDisplay` hoje volta YES quando as duas seções estão vazias. Com o item de novidades visível, tem que voltar NO, senão a ilustração de lista vazia fica por cima do item (conta nova, primeiro uso).
- **Arquivar com desfazer**: o iOS não tem Snackbar. Opções: um aviso curto no rodapé com "Desfazer" (feito à mão, ~3 s) ou um `UIAlertController` de confirmação ("Arquivar novidades? Você pode reabrir em Configurações → Sobre → Novidades do isaCloud."). O alerta é mais simples e combina com o iOS; o aviso com desfazer fica mais perto do Android.
- Reavaliar o item em `viewWillAppear` e quando os filtros mudarem (o Android chama `refreshChangelog()` no `onResume` e em `refresh()`).

### 4. Tela de novidades (SwiftUI)
Uma view nova no `SwiftuiInterface` (`makeViewWithName:@"IsaCloudChangelog"`), com `List`/`ScrollView`:
- por release: "Build 104 · 11/11/2026"; seções com título em rosa; itens com o emoji que já vem no texto (sem "•");
- ao aparecer, `markRead(build atual)`;
- se arquivado, botão "Mostrar na lista de conversas";
- link "Ver todas as novidades" para o `CHANGELOG-USERS.md` no GitHub (o repositório é público? conferir antes; se não for, mostrar todas as releases do JSON na própria tela em vez do link).

E uma linha "Novidades do isaCloud" em Configurações → seção Sobre (`MLSettingsTableViewController`, enum `SettingsAboutRows`), que abre a mesma tela mostrando **todas** as releases do JSON, não só o lote.

### 5. Textos novos (com pt-BR no override do isaCloud)
| Chave (en) | pt-BR |
|---|---|
| isaCloud news | Novidades do isaCloud |
| See what changed in build %@ | Veja o que mudou no build %@ |
| See what changed in builds %@ | Veja o que mudou nos builds %@ |
| New | Novo |
| Archive news | Arquivar novidades |
| News archived. Reopen it in Settings → About. | Novidades arquivadas. Reabra em Configurações → Sobre. |
| Show in chats list | Mostrar na lista de conversas |
| See all news | Ver todas as novidades |
| No news for now. | Nenhuma novidade por enquanto. |

Prévia com vários builds: "Veja o que mudou nos builds 103, 104, 105", da mais antiga para a mais nova, como no Android. Se o salto for grande (ex.: mais de 4 builds), "nos builds 101 a 105" cabe melhor numa linha.

## Ordem sugerida
1. Gerador do JSON + `ChangelogStore` + testes do lote (nova instalação, atualização com salto, mesma versão, downgrade, arquivado/lido).
2. Tela de novidades em SwiftUI e a linha em Configurações → Sobre (já dá valor sozinha e não toca na lista).
3. Item no topo da lista (`tableHeaderView`), filtros, estado vazio e arquivar.
4. Incluir o gerador no `archive-testflight.sh` e no `isacloud-dev-device.sh`; anotar na rotina de "novo build".
5. Changelog, roadmap e `docs/decisoes.md` (ideia vinda do Android do isaCloud).

## Decisões (11/11/2026)
- **Item na lista: opção A**, `tableHeaderView` com o botão de arquivar na linha (o mais simples).
- **Arquivar: alerta de confirmação** ("Arquivar novidades? Você pode reabrir em Configurações → Sobre → Novidades do isaCloud."), sem desfazer.
- **Primeiro lote: só o build atual**, como no Android.
- **Changelog completo: link** para o `CHANGELOG-USERS.md` no GitHub (o repositório é público): `https://github.com/isaitgirl/isaCloud-iOS/blob/isaCloud/CHANGELOG-USERS.md`. Configurações → Sobre abre a mesma tela com todas as releases do JSON.
- **JSON:** `scripts/isacloud-generate-changelog-json.py` grava `Monal/isaCloud-changelog.json` (commitado, recurso só do app); `## Próximo build` vira o `CURRENT_PROJECT_VERSION` com a data do dia. Chamado pelo `archive-testflight.sh` e pelo `isacloud-dev-device.sh`.
- Implementação na branch `feature/novidades-na-lista`, testada no `.dev` (aprovada em 11/11/2026).
- **Ajustes do teste no `.dev`:** o ícone do item é o balão 3D sem o fundo do ícone do app (asset `IsaCloudNewsIcon`, original em `isaCloud/branding/logo-isacloud-im-balao-3d-1024.png`); a tela abre com `UIKitWorkaround` como uma conversa (com `AddTopLevelNavigation` ficavam duas setas de voltar no iPhone); "Mostrar na lista de conversas" fica no topo da tela e só aparece com as novidades arquivadas.
- **Para testar de novo:** o estado fica no `UserDefaults.standard`; trocar o `.plist` no aparelho não adianta (o `cfprefsd` guarda a cópia em memória). Para uma abertura só, `xcrun devicectl device process launch -d <udid> br.com.isacloud.messenger.dev -- -isaCloudChangelog.archivedBuild 0 -isaCloudChangelog.readBuild 0`.

# Branches, worktrees e build: o passo a passo e os problemas conhecidos

Este documento junta o que dá errado com mais frequência na hora de compilar o isaCloud (Rust, `Package.resolved`, SQLite/FTS5, Pods, assinatura) e como criar uma branch de feature ou de correção, inclusive em uma **worktree separada** (uma pasta própria por branch, para duas frentes não pisarem uma na outra).

Complementa `docs/publicacao-testflight.md` (enviar ao TestFlight) e `docs/troubleshooting.md` (crashes e logs). Dados sensíveis (Team ID, UDIDs) ficam em `isaCloud/local/NOTAS-LOCAIS.md`, fora do Git.

## 1. Regras das branches

- `isaCloud` é a branch principal e a única que vai para o TestFlight. A `develop` só serve para buscar commits do Monal; nunca se desenvolve nela.
- Toda mudança nasce em uma branch nova **criada a partir de `isaCloud`** e volta por PR para a `isaCloud` (nunca para `develop`, `main` ou `master`).
- Nomes: `feature/<assunto>` para funcionalidade, `fix/<assunto>` para correção (ex.: `fix/primeiro-plano-apos-segundo-plano`). Em minúsculas, com hífens. O disco do Mac não diferencia maiúsculas: `isaCloud` e `isacloud/...` colidem, então não use esse prefixo.
- Todo PR tem a `isaitgirl` como revisora e responsável e traz prints de antes e depois das mudanças visíveis (só com dados de teste). No app o merge é com **merge commit**; no fork do ExyteChat é com `--rebase`.
- Só mesclar com a autorização da Isadora. Depois do merge, apagar a branch (no GitHub e local) **só depois de perguntar**.
- Mudança que depende do fork do ExyteChat: o PR do fork é mesclado **antes**; só então o PR do app. Detalhes em `docs/exytechat-fork.md`.

## 2. Criar uma branch no checkout principal

Quando só uma frente mexe no repositório:

```bash
cd ~/projects/swift/isaCloud-iOS
git fetch origin
git switch isaCloud && git merge --ff-only origin/isaCloud
git switch -c fix/nome-da-correcao
```

Se já houver alterações sem commit de outra frente no checkout, **não troque de branch ali**: use uma worktree (próxima seção). Trocar de branch com trabalho pendente, ou duas sessões no mesmo checkout, já fez uma sessão desfazer as edições da outra (02/11/2026).

## 3. Criar uma branch em uma worktree separada

Uma worktree é outra pasta com outra branch do mesmo repositório. Convenção: `~/projects/swift/isaCloud-iOS-<assunto>`.

```bash
cd ~/projects/swift/isaCloud-iOS
git fetch origin
git worktree add -b fix/nome-da-correcao ../isaCloud-iOS-nome-da-correcao origin/isaCloud
cd ../isaCloud-iOS-nome-da-correcao
git submodule update --init --recursive
```

A worktree nasce só com o que está no Git. O build precisa de arquivos que o Git ignora; sem eles ele falha (veja a seção 5). **Copie do checkout principal** (cópias com `cp -Rc` são clones do APFS: rápidas e sem gastar disco até mudarem):

```bash
SRC=~/projects/swift/isaCloud-iOS
DST=~/projects/swift/isaCloud-iOS-nome-da-correcao
cp -Rc $SRC/Monal/Pods                    $DST/Monal/Pods
cp -Rc $SRC/rust/LibMonalRustSwiftBridge  $DST/rust/LibMonalRustSwiftBridge
cp -Rc $SRC/rust/target                   $DST/rust/target
mkdir -p $DST/isaCloud/local && cp $SRC/isaCloud/local/giphy-api-key.txt $DST/isaCloud/local/
```

| Item copiado | Para que serve | Sem ele |
|---|---|---|
| `Monal/Pods` | dependências do CocoaPods (gitignored) | falha de módulo/header de pod |
| `rust/LibMonalRustSwiftBridge` | pacote Swift gerado pelo Rust (gitignored) | `Missing package product 'LibMonalRustSwiftBridge'` |
| `rust/target` | bibliotecas Rust já compiladas (~3,6 GB, em clone) | o build tenta recompilar o Rust |
| `isaCloud/local/giphy-api-key.txt` | chave da busca de GIF | o app compila, mas a busca de GIF aparece como "não configurada" |

Copie **só** a chave do Giphy de `isaCloud/local`; o resto (notas, patches, `.credentials`) é pessoal e não precisa ir junto.

### Compilar e instalar na worktree

Os scripts usam o repositório onde estão (`REPO_ROOT`), então rode-os **de dentro da worktree**:

```bash
cd ~/projects/swift/isaCloud-iOS-nome-da-correcao
scripts/isacloud-dev-device.sh <TEAM_ID> <UDID_DO_IPHONE>
```

- O `.dev` (`br.com.isacloud.messenger.dev`) é compilado em `build/dev-device` **da worktree**. A primeira vez é um build do zero (vários minutos). As seguintes aproveitam o cache.
- O `.dev` instalado é sempre um só no iPhone: instalar de uma worktree substitui o que veio de outra. O app e os dados (`.dev` usa a pasta privada do app) continuam; só o código muda.
- O archive do TestFlight (`scripts/archive-testflight.sh --upload`) usa a pasta **`/tmp/ddarch`**, que é a mesma para todas as worktrees: arquive uma de cada vez. Normalmente o archive sai do checkout principal, com a `isaCloud` já atualizada depois do merge.
- Simuladores: `docs/troubleshooting.md` (seção de builds) traz os comandos. Use uma pasta `-derivedDataPath` nova por worktree.

### Remover a worktree

Só depois de mesclar (e com a confirmação da Isadora para apagar a branch):

```bash
cd ~/projects/swift/isaCloud-iOS
git worktree remove --force ../isaCloud-iOS-nome-da-correcao   # --force: a pasta tem submódulos e arquivos copiados
git branch -d fix/nome-da-correcao
git push origin --delete fix/nome-da-correcao
```

## 4. Do commit ao merge (resumo)

1. Commitar na branch de trabalho (mensagem descritiva em português) e dar push: `git push -u origin fix/nome-da-correcao`.
2. `gh pr create --base isaCloud --head fix/nome-da-correcao --assignee isaitgirl` (revisora também).
3. Mesclar com merge commit **quando a Isadora autorizar**: `gh pr merge <n> --merge`.
4. No checkout principal: `git switch isaCloud && git pull --ff-only`.
5. Se for sair em build: subir o número, TestFlight e o resto da rotina de `CLAUDE.md` ("fazer novo build e push") e a tag `build-N`.

## 5. Problemas de build e como resolver

### `Missing package product 'LibMonalRustSwiftBridge'` (Rust)
- **Causa:** `rust/LibMonalRustSwiftBridge` é gerado pelo `rust/build-rust.sh` e fica no `.gitignore`. Um clone novo ou uma worktree nova não o tem. (Visto em 07/11/2026 na primeira worktree.)
- **Resolver (rápido):** copiar do checkout principal, como na seção 3 (`LibMonalRustSwiftBridge` e `rust/target`).
- **Resolver (do zero):** `rust/build-rust.sh`. Precisa do `rustup`, da toolchain `nightly` com `rust-src` e do `swift-bridge-cli` (`cargo install swift-bridge-cli`). Compila várias plataformas, inclusive o Mac Catalyst, e demora; só vale a pena se o código Rust (`rust/*`) mudou ou se não houver outra cópia. No dia a dia, copie.
- **Quando regerar:** só ao mudar o código Rust. Mudança em Swift/Objective-C não pede.

### `Package.resolved` (pacotes Swift)
- O arquivo é `Monal/Monal.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Está no `.gitignore`, mas **é versionado**: alterações aparecem no `git status`; se o `git add` recusar, use `git add -f`.
- Ele fixa a revisão (SHA) de cada pacote, em especial do fork `isaitgirl/ExyteChat` e do `isaitgirl/sqlite3-package`. **Sem atualizar a revisão, o TestFlight compila a versão antiga da biblioteca.**
- Depois de mesclar um PR do fork do ExyteChat: atualizar a revisão para o SHA **mesclado** (com `--rebase` o SHA muda em relação ao da branch do PR), commitar o `Package.resolved` e conferir `docs/exytechat-fork.md`.
- **Armadilha do requisito do pacote:** para testar uma branch do fork, às vezes se troca o `branch` do ExyteChat no `Monal/Monal.xcodeproj/project.pbxproj` para a branch da feature. Isso é provisório e **não pode ir no merge**: antes de mesclar, o requisito volta para `isaCloud` e o `Package.resolved` aponta para a `isaCloud` do fork (com o SHA mesclado). Foi o caso do PR 46.
- O Xcode pode reescrever o `Package.resolved` ao resolver pacotes. Olhe o `git diff` do arquivo antes de commitar e não leve mudanças que você não pediu.
- Erro de resolução ou "package not found": confira rede e o `~/.gitconfig` (ele reescreve `https://github.com/` para SSH; na sessão do Claude use `GIT_CONFIG_GLOBAL=/dev/null`).

### SQLite sem FTS5 ("no such module: fts5")
- **Causa:** o Xcode reaproveita a SQLite já compilada quando muda um trait de pacote (`ENABLE_FTS5` do fork `sqlite3-package`) e entrega o app sem o módulo de busca, sem avisar. Aconteceu no `.dev` e em archives (builds 27/10 e 77).
- **Defesas que já existem:** a fase de build **"[isaCloud] Check FTS5"** (falha o build se o `monalxmpp` não tem a string `ENABLE_FTS5`), o `scripts/archive-testflight.sh` (pasta nova e conferência antes do envio) e a autoverificação no app (`MLMessageSearch isAvailable`).
- **Resolver:** para o `.dev`: `rm -rf build/dev-device` e rodar o script de novo. Para o TestFlight: arquivar com `-derivedDataPath /tmp/ddarch` novo (o script já faz). Conferir:

```bash
strings -a build/isaCloud-AppStore.xcarchive/Products/Applications/*.app/Frameworks/monalxmpp.framework/monalxmpp | grep -c '^ENABLE_FTS5$'
```
  O resultado precisa ser `1`.
- **Se o `sqlite3-package` mudar** (merge com o Monal ou do fork): conferir que o `Package.swift` do fork continua com `ENABLE_FTS5` nos traits e que o `Package.resolved` aponta para o SHA certo. Detalhes e decisões: `docs/decisoes.md` (busca de mensagens / FTS5) e `docs/troubleshooting.md`.
- **Pastas de compilação velhas** (`/tmp/dd18`, `/tmp/dd27`) ficam com a SQLite sem FTS5 e os testes de busca falham: use uma pasta nova.

### `pod install` reordena o `project.pbxproj`
- Rodar `pod install` em `Monal/` reescreve a ordem das linhas do `project.pbxproj`. **Não commite essa reordenação**: ela estraga o diff e o merge com o Monal. Se rodou sem querer: `git checkout -- Monal/Monal.xcodeproj/project.pbxproj` (e refaça só a sua mudança real, se houver).
- Arquivo novo de código entra no `project.pbxproj` com um PBXBuildFile, um PBXFileReference, a entrada no grupo e a entrada em Sources do alvo, no estilo dos vizinhos (IDs `A1C0FFEE…` do isaCloud). Confira com `plutil -lint Monal/Monal.xcodeproj/project.pbxproj`.

### Assinatura, iPhone e instalação
- O `.dev` assina com o time pago (automático) e usa `isaCloud/dev-entitlements/` (sem push, sem notificações de comunicação, sem aumento de memória). O Team ID está em `isaCloud/local/NOTAS-LOCAIS.md`.
- O iPhone às vezes aparece como **"unavailable"**: destravar o aparelho, mantê-lo conectado e repetir (`xcrun devicectl list devices`).
- `error: the following command failed with exit code 0 but produced no further output` no fim do log do script é inofensivo. O que vale é o `EXIT=0` e a linha `Launched application with br.com.isacloud.messenger.dev`.
- Simulador **com** assinatura: sem entitlements o app aborta ao abrir (`Container URL should never be nil!`). Para rodar no simulador, use assinatura ad-hoc (`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=`) e um DerivedData limpo ao trocar de destino (senão: erro de PCH desatualizado).
- Archive/TestFlight: `exportArchive Failed to Use Accounts` se resolve saindo e entrando de novo na conta em Xcode → Settings → Accounts (ver `docs/publicacao-testflight.md`, "Problemas já vistos").

### Outros avisos conhecidos
- Build que "funciona no checkout principal e falha na worktree": quase sempre é um arquivo ignorado pelo Git que não foi copiado (seção 3). Compare `git status --ignored` nas duas pastas.
- Antes de reinstalar um app nos simuladores (`simctl uninstall`/`install`), faça o backup do banco (`sworim.sqlite`, `-wal`, `-shm` juntos); regras no `CLAUDE.md`.
- O `.dev` compilado em outra worktree **não** tem o código da outra branch: ao testar duas correções juntas, junte as branches primeiro.

## 6. Lista de conferência antes de começar um build

- [ ] Estou na branch certa, partindo de `isaCloud` atualizada (`git log --oneline -3`)?
- [ ] Na worktree: `Monal/Pods`, `rust/LibMonalRustSwiftBridge`, `rust/target` e a chave do Giphy estão lá?
- [ ] `Package.resolved` sem mudanças que eu não queria (`git diff` do arquivo)?
- [ ] `project.pbxproj` sem reordenação do `pod install` e sem o requisito provisório do fork?
- [ ] Para TestFlight: número do build igual nos 25 lugares e FTS5 `= 1` (o script confere).

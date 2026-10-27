# Troubleshooting do isaCloud (TestFlight e isaCloud.dev)

Procedimentos e comandos que já funcionaram para investigar problemas. Rode a partir da raiz do repositório, salvo quando indicado.

## Identificadores

| O quê | Valor |
|---|---|
| App de distribuição (TestFlight) | `br.com.isacloud.messenger` |
| App de desenvolvimento (iPhone) | `br.com.isacloud.messenger.dev` |
| App Group (produção / dev) | `group.br.com.isacloud.messenger` / `group.br.com.isacloud.messenger.dev` |
| Equipe | `K8Y6S5RF2S` |
| Seu iPhone | `<UDID_DO_IPHONE>` (em `isaCloud/local/NOTAS-LOCAIS.md`; `xcrun devicectl list devices` mostra) |
| Simulador iPhone XR (iOS 18.6) | `7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D` |
| Simulador iOS 27 ("isaCloud iOS27") | `346E97D1-7A60-4671-A481-FB22437B8380` |

Os dois apps (TestFlight e `.dev`) convivem no iPhone. No `.ips` de um crash, o campo `bundleID` diz de qual dos dois veio.

## 1. Pegar relatórios de crash do iPhone

Funciona para o app do TestFlight e para o `.dev`. O iPhone precisa estar conectado ao Mac e desbloqueado.

```bash
xcrun devicectl device copy from --device <UDID_DO_IPHONE> --domain-type systemCrashLogs --source / --destination /tmp/crashes
```

Os arquivos `isaCloud-AAAA-MM-DD-HHMMSS.ips` ficam em `/tmp/crashes`. Os mais novos aparecem no topo de `ls -t /tmp/crashes`. Crashes antigos podem ter ido para a subpasta `Retired`.

Sem o Mac por perto: no iPhone, Ajustes → Privacidade e Segurança → Análises e Melhorias → Dados de Análise → arquivo `isaCloud-...ips` → compartilhar.

Pelo App Store Connect: TestFlight → Crashes, ou Xcode → Window → Organizer → Crashes (só de testadores que aceitaram compartilhar análises, com atraso de horas).

O app também tem um coletor de crash próprio (KSCrash). Na abertura seguinte ao crash ele oferece enviar o relatório por e-mail para `sysadmin@isacloud.cc`.

### Ler o `.ips`

O `.ips` tem duas partes em JSON: a primeira linha (cabeçalho) e o resto (o relatório). Para ver o tipo do crash e a pilha da thread que caiu:

```bash
python3 - /tmp/crashes/isaCloud-AAAA-MM-DD-HHMMSS.ips <<'EOF'
import json, sys
t = open(sys.argv[1]).read().split('\n', 1)
h = json.loads(t[0]); d = json.loads(t[1])
print(h.get('bundleID'), 'build', h.get('build_version'), d.get('captureTime'))
print(d.get('exception'), str(d.get('termination'))[:400])
for th in d['threads']:
    if th.get('triggered'):
        for fr in th['frames'][:25]:
            im = d['usedImages'][fr['imageIndex']]
            print(im.get('name'), fr.get('symbol'), fr.get('sourceFile'), fr.get('sourceLine'))
EOF
```

Para ver a thread principal e as outras (útil em travamento, onde a thread que "caiu" é a do vigia): troque o `if th.get('triggered')` por `if th is d['threads'][0]` ou imprima todas.

Dicas para interpretar:

- **`0x8BADF00D` (watchdog)**: a thread principal ficou bloqueada tempo demais. Veja a pilha da `com.apple.main-thread`: em `-[xmpp unfreeze]` ou em `sqlite3...BusyHandler` significa espera por fila ou por banco.
- **Crash em `com.kscrash.hang.watchdog.thread`** (`populateReportForCurrentHang`, `getClassRO`): era o vigia de travamento do KSCrash quebrando ao gravar o relatório no iOS 27. Está desligado no iOS 27 ou mais novo (`HelperTools.m`).
- **`NSInternalInconsistencyException ... attempt to insert row N into section S`** com `UIList.swift` na pilha: atualização de tabela do ExyteChat (chat aberto recebendo mensagens). A mensagem completa da exceção está no log do sistema, não no `.ips`.
- Para ver a mensagem de uma exceção do simulador, busque no log: `xcrun simctl spawn <UDID> log show --last 3m --style compact --debug --predicate 'eventMessage CONTAINS "Terminating app"'`.

## 2. Instalar e abrir o isaCloud.dev no iPhone

```bash
scripts/isacloud-dev-device.sh K8Y6S5RF2S <UDID_DO_IPHONE>
```

Compila em Debug, instala e abre. O certificado da conta gratuita expira em 7 dias. O `.dev` não tem push.

Abrir, fechar e listar processos no iPhone:

```bash
xcrun devicectl device process launch --device <UDID_DO_IPHONE> --terminate-existing br.com.isacloud.messenger.dev
xcrun devicectl device info processes --device <UDID_DO_IPHONE> | grep isaCloud
xcrun devicectl device process terminate --device <UDID_DO_IPHONE> --pid <PID>
```

Se o app estiver rodando e a tela congelada sem crash, o `grep` mostra se o processo continua vivo.

## 3. Ver arquivos do app no iPhone

```bash
# listar
xcrun devicectl device info files --device <UDID_DO_IPHONE> --domain-type appDataContainer --domain-identifier br.com.isacloud.messenger.dev
xcrun devicectl device info files --device <UDID_DO_IPHONE> --domain-type appGroupDataContainer --domain-identifier group.br.com.isacloud.messenger.dev
# copiar um arquivo
xcrun devicectl device copy from --device <UDID_DO_IPHONE> --domain-type appGroupDataContainer --domain-identifier group.br.com.isacloud.messenger.dev --source <arquivo> --destination <pasta-local>
```

Para o app do TestFlight, troque o identificador do domínio pelos de produção (`br.com.isacloud.messenger` e `group.br.com.isacloud.messenger`). Isso só funciona com apps instalados por build de desenvolvimento; o de TestFlight pode recusar.

## 4. Perfil de CPU de um travamento (Time Profiler)

Só mostra o que está consumindo CPU; thread bloqueada esperando fila ou banco não aparece. Para o travamento da abertura:

```bash
xcrun xctrace record --template "Time Profiler" --device <UDID_DO_IPHONE> --time-limit 20s --output /tmp/travou.trace --launch -- br.com.isacloud.messenger.dev
```

Anexar a um processo já em execução (`--attach`) não funcionou neste aparelho; use `--launch`.

## 5. Simulador

```bash
# compilar para o simulador (precisa do workspace, não do .xcodeproj)
xcodebuild -workspace Monal/Monal.xcworkspace -scheme Monal -configuration Debug -destination "platform=iOS Simulator,id=7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D" -derivedDataPath /tmp/dd18 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build

# instalar e abrir
xcrun simctl install 7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D /tmp/dd18/Build/Products/Debug-iphonesimulator/isaCloud.app
xcrun simctl launch 7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D br.com.isacloud.messenger
```

No simulador o app instalado é o de produção (`br.com.isacloud.messenger`).

Testes unitários (um conjunto):

```bash
xcodebuild -workspace Monal/Monal.xcworkspace -scheme "Monal Tests" -destination "platform=iOS Simulator,id=7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D" -derivedDataPath /tmp/dd18 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= -only-testing:MonalXMPPUnitTests/QuoteFormattingTests test
```

Capturas de tela: ver as regras de nome e pasta em `CLAUDE.md` (`docs/screenshots/`).

Crashes do simulador ficam em `~/Library/Logs/DiagnosticReports/isaCloud-*.ips` (o mesmo leitor da seção 1 serve).

### Emojis aparecem como `[?]` no simulador

Sintoma: reações, o seletor de reações e qualquer emoji aparecem como uma caixinha com `?`, até no Safari do simulador. No iPhone de verdade aparecem normalmente.

Causa: defeito da Apple nos runtimes de simulador **iOS 26.1 e 26.3.1** (build `23D8133`): a fonte de emoji existe, mas não é usada. Não é do app nem do ExyteChat. Relatos e confirmações: issue 56183 do React Native (`facebook/react-native`). Confirmado aqui em 25 e 26/10/2026: os runtimes iOS 26.4 e 27.1 mostram os emojis, o 26.3.1 não.

Solução: usar um runtime que não tenha o defeito (iOS 26.4 ou mais novo, ou o 27.x).

```bash
# ver o que o Xcode oferece e baixar (cerca de 8 GB)
xcodebuild -downloadPlatform iOS -buildVersion 26.4

# criar um iPhone nesse runtime e ligar
xcrun simctl create "iPhone 17 Pro (26.4)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-4
```

Teste rápido de emoji, sem abrir o app: servir uma página HTML com emojis no Mac e abrir no Safari do simulador (`xcrun simctl openurl <udid> http://127.0.0.1:<porta>/emoji.html`; URLs `data:` não abrem).

Prints de reações devem ser feitos num runtime sem o defeito. Depois de confirmar, apague o runtime com defeito e os aparelhos dele (cada runtime ocupa cerca de 8 GB):

```bash
xcrun simctl delete <udid-do-aparelho>
xcrun simctl runtime delete <id-do-runtime>   # o id aparece em: xcrun simctl runtime list
```

## 6. Logs do app

Os logs do app (DDLog) **não** aparecem no `log stream` do sistema. O que aparece:

- mensagens de `NSLog`;
- logs do sistema, como UIKit, CoreLocation e CFNetwork.

No simulador, dá para capturar mensagens por texto:

```bash
xcrun simctl spawn 7AA8D91B-C04C-460E-A4CB-F400FA1F5D5D log stream --level debug --style compact --predicate 'eventMessage CONTAINS "TEXTO"'
```

Para investigar o que o app está fazendo, o caminho que funcionou foi acrescentar `NSLog(@"DIAG ...")` temporário no código, reproduzir e filtrar pelo texto. Lembre de remover depois.

O app tem um logger de arquivo e um logger por UDP (`udpLoggerEnabled`), que no iPhone real são os padrões. No simulador o padrão é o log do Xcode. Para ver o que cada um faz, veja `HelperTools.m` (`initSystem`, `configureLogging`, `configureXcodeLogging`).

### Extensão de notificações morta com `0xdead10cc`

No iPhone os relatórios aparecem como `NotificationService-AAAA-MM-DD-HHMMSS.ips` (veja a seção 1 para puxá-los; os mais antigos vão para `Retired/`). No cabeçalho, `bundleID` diz de qual app é (`br.com.isacloud.messenger.notificationService` é o nosso; `monal.alpha...` e `G7YU7X7KRJ.SworIM...` são do Monal). O sinal é `termination: {namespace: RUNNINGBOARD, code: 3735883980}`, que é `0xdead10cc`: o processo foi suspenso segurando um arquivo ou um banco no contêiner compartilhado. Para ver quem segurava, olhe as threads com `monalxmpp`: `-[PushSingleton pushExpired]` em `usleep` (segurando o `MLProcessLock`) ou `-[MLSQLite voidWriteTransaction:]` (transação aberta). Se o Monal alpha e o beta caem junto, não é nosso. Ver a pendência no `ROADMAP.md`.

### Spinner preso depois de o app dormir

Se o spinner gira sem conectar, **reabra o app (feche e abra) e depois exporte o log**: o arquivo do log fica em disco (rolagem de 48 h, até 4 arquivos) e guarda também a execução anterior. Em Configurações → Depuração → Arquivos de log, toque no mais recente e compartilhe. Anote a hora aproximada do travamento. Procure no arquivo por `Unfreezing account`, `existing account, calling unfreeze`, `connected(?) existing account, just pinging`, `ping attempted before logged in and bound`, `ping already sent` e `Login took too long`.

## 7. Reiniciar o estado do app para testar

- **Fila do compartilhamento travada** (a share sheet "compartilha o item anterior"): na tela de Debug dos ajustes, o botão "Limpar a fila de compartilhamento" (o `.dev` e o de produção têm filas separadas). O texto exato do caminho pode variar; o botão está em `DebugView.swift`.
- **Contas travadas na sincronização inicial**: a opção de resetar o estado de todas as contas, também nos ajustes de Debug ("Reset the state of all accounts" em inglês). Não precisa deslogar.

## 8. Quando o app congela ou cai na abertura

Roteiro que resolveu casos desta sessão:

1. Puxar o `.ips` (seção 1) e ver o tipo do crash.
2. Se for `0x8BADF00D`, olhar a pilha da thread principal: o que ela está esperando.
3. Se o crash tem menos de 1 segundo de vida (`procLaunch` e `captureTime` no `.ips`), suspeitar do vigia de travamento ou de algo na inicialização.
4. Se só o `.dev` cai, comparar com o app do TestFlight no mesmo aparelho.
5. Confirmar a versão: `build_version` e `bundleID` no cabeçalho do `.ips`.

## 9. Crashes conhecidos do Monal no isaCloud.dev (Debug)

- **`Spurious idle timer firing!` em `-[MLMucProcessor handleJoinTimeout]`** (`SIGABRT` na fila `im.monal.timeouts`, alguns segundos depois de abrir). Os timers de inatividade das entradas em sala ficam no banco e sobrevivem a uma queda ou a um encerramento forçado do app; na abertura seguinte o timer vence sem o estado "entrando" na memória e a asserção derruba o app, às vezes em ciclo. Saída sem mexer no código: apagar o `.dev` e instalar de novo (`xcrun devicectl device uninstall app --device <UDID_DO_IPHONE> br.com.isacloud.messenger.dev`, depois `scripts/isacloud-dev-device.sh`) e adicionar a conta de novo. O banner vermelho "Could not join group/channel: timeout" aparece um instante antes. Evite `devicectl ... process terminate` com o app entrando em salas. Correção possível (ainda não feita, é código do Monal): ignorar o timer em vez de abortar.
- **Travamento de 7 a 9 s na abertura** (relatório `UIKit-runloop-isaCloud-*.ips`): a thread principal fica presa numa chamada de log (`DDLog queueLogMessage`, por exemplo `didFailToRegisterForRemoteNotificationsWithError`, que o `.dev` sempre gera por não ter push) porque a fila de log está ocupada com `DumpMemoryGraph` (`MLDelayedDealloc.m`, só em build Debug). O app do TestFlight (Release) não tem isso. Para ler a pilha, simbolize com `atos` usando os UUIDs do relatório e os dSYM em `build/dev-device/Build/Products/Debug-iphoneos/` (`monalxmpp.framework.dSYM` e `isaCloud.app.dSYM`); o endereço de carga vem da seção "Binary Images" do relatório.
- **Remover conta** (corrigido em 27/10/2026, `handleGlobalRefresh:` ignora a mensagem que já não existe): a pilha era `removeAccountForAccountID:` > `handleGlobalRefresh:` > `messageDataForHistoryID:` > `MLAssert`, vista no isaCloud e no Monal alpha. Para reproduzir no simulador sem remover conta: abra um chat, mande o app para o início, apague a mensagem aberta (`delete from message_history where message_history_id=...` no `sworim.sqlite` do App Group, com cópia de segurança antes) e volte ao app. Depois de restaurar uma cópia do banco, o servidor pode mostrar o aviso amarelo "Server acknowledged more stanzas than sent by client": são os contadores de confirmação (XEP-0198) antigos da cópia, e o app se corrige sozinho.
- **Crash ao desativar a conta** (`SIGABRT` em `-[xmpp disconnectWithStreamError:andExplicitLogout:]`, com `-[MLMessage handleGlobalRefresh:]` e `-[DataLayer messageDataForHistoryID:]` na pilha): o refresh global da desconexão manda uma mensagem se recarregar do banco e a asserção dispara. Evite o interruptor "Ativado" para reiniciar; use Ajustes > Debug > "Reset the state of all accounts".
- **Relatórios direto do iPhone** (sem e-mail): `xcrun devicectl device copy from --device <UDID_DO_IPHONE> --domain-type systemCrashLogs --source / --destination <pasta>`; veja `UIKit-runloop-isaCloud-*.ips` (travamentos) e `isaCloud-*.ips` (quedas). Os `UIKit-runloop` não são JSON: leia o texto, procurando `DispatchQueue "com.apple.main-thread"`.
- **Ver o que o servidor manda ao app** (Prosody, sem habilitar debug): `prosodyctl shell` e `watch:stanzas("poli@dominio")` (use `help watch` para as opções da sua versão). Mostra só o que chega à sessão; para o que o app envia, assista a sessão do próprio aparelho.

# Análises de crashes e travamentos do isaCloud para iOS

Registro único dos crashes, travamentos e mortes pelo sistema que já analisamos: o que se viu, a causa, a correção e o build em que entrou. **A partir de 04/11/2026 todo crash novo é registrado aqui**, com o modelo do fim do arquivo. Detalhes longos continuam em `docs/decisoes.md` (cada entrada aponta a seção), e a receita de investigação fica em `docs/troubleshooting.md`.

## Como colher os dados

- **Relatórios do sistema (`.ips`) do iPhone:**
  ```bash
  xcrun devicectl device info files --device <UDID> --domain-type systemCrashLogs
  ```
  Depois copie o arquivo com `xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs --source <arquivo>.ips --destination <pasta>`. O UDID fica em `isaCloud/local/NOTAS-LOCAIS.md`. Para classificar vários de uma vez: `scripts/classificar-crashes.py --dir <pasta>` (ou `--pull <UDID>`).
- **Log do app (`.rawlog`):** fica em `Library/logs` do grupo do app (`group.br.com.isacloud.messenger` ou `.dev`). Copie com `--domain-type appGroupDataContainer`.
  - **Armadilha:** o arquivo que ainda está sendo gravado sai **cortado na dezena de MB abaixo do tamanho**. Para pegar o fim, espere o arquivo passar da próxima dezena ou a rotação.
  - Arquivo fechado sai inteiro. O nome do arquivo está em UTC; as linhas, em hora local.
- **KSCrash:** os relatórios do app ficam em `<grupo>/Library/CrashReports`.
- **MetricKit:** os diagnósticos ficam em `<grupo>/Library/metrics/metrickit-diagnostic-*.json` e são exportáveis pelo Depuração.
- **Banco:** o `devicectl` não lê `sworim.sqlite`, porque fica fora de `Library`. Para isso, peça a exportação do Depuração ou use o simulador.
- **O que olhar primeiro:**
  - **Tipo:** `exception.type`/`signal` e `termination` (`0xdead10cc` = suspenso com arquivo bloqueado; `0x8BADF00D` = vigia, thread principal presa).
  - **Pilha:** a thread `faultingThread`.
  - **Banco travado:** no log, "Retrying write transaction start" lista `currentTransactions` (quem segura, `currentlyAt`) e `newWriteTransactionVia` (quem espera).

## Resumo

| # | Data | Build | Tipo | O quê | Situação |
|---|---|---|---|---|---|
| C01 | 29/10 | 54 | KSCrash "App hung" | vigia do KSCrash (250 ms) disparando por avatares e prévias na thread principal | corrigido |
| C02 | 29/10 | 54–63 | `0xdead10cc` (extensão de notificação) | extensão suspensa com o banco aberto | corrigido (66/67) |
| C03 | 30/10 | 74 | `0x8BADF00D` + `0xdead10cc` | deadlock no download de imagens (`MLFiletransfer`) | corrigido (75) |
| C04 | 25–30/10 | 13, 52 | `0xdead10cc` | log síncrono dentro da transação quando a fila de log é suspensa | corrigido (83) |
| C05 | 28/10–02/11 | 36–81 | `0xdead10cc` (app) | quatro mecanismos de transação longa na suspensão | em parte corrigido (83–85), em medição |
| C06 | 28/10–30/10 | 53–75 | `0x8BADF00D` | thread principal esperando sem prazo (`disconnectAll`, `unfreeze`, busy do SQLite) | sem ocorrência depois do 75 |
| C07 | 29/10 | 68 | SIGABRT (extensão) | `beginWriteTransaction` depois de fechar o banco | revertido |
| C08 | 28/10 e 01/11 | 53, 77 | crash Swift | `ObservableKVOWrapper` lido sem tipo explícito | corrigido (78) |
| C09 | 02/11 | 81 | `fatalError` | mensagens com id duplicado na lista (compartilhar um link) | corrigido (83) |
| C10 | 02/11 | 83 | extensão morta (check-in timeout) | "New Message?": extensão travada no flush do logger de rede | corrigido (84), a confirmar |
| C11 | 03/11 16:14 | 87 `.dev` | congelamento → `0x8BADF00D` ao fechar | deadlock: envio OMEMO × recebimento de chaves OMEMO | corrigido (88) |
| C12 | 03/11 16:38 | 87 `.dev` | SIGSEGV na abertura | extensão de compartilhar sem o grupo de keychain → chaves OMEMO apagadas e geradas de novo | corrigido (88) |
| C13 | 03/11 | simulador | crash Swift/ObjC | `MLContactCell` com `message` em BLOB (dado de teste mal inserido) | não é do app |
| C14 | 24 e 25/10 | 5, 8 | SIGABRT (`MLAssert`) | `MLFiletransferInfo createFiletransferInfoForMessage:` sem a linha de `filetransfer_info` ao abrir um chat | corrigido (linha criada na hora) |
| C15 | 30/10 | 67 | SIGABRT (`MLAssert`) | asserção em `disconnectWithStreamError:` durante `disconnectAll`, correndo com o congelamento | corrigido (virou aviso no log) |
| C16 | 03/11 22:30 | 88 (TestFlight, iPhone14,7, iOS 27.2) | SIGABRT (`MLAssert`) | `MLStream tlsVersion` com o stream já em erro: login processado depois de a conexão cair | corrigido (build 89; voltou no iPhone da Isadora em 04/11 10:53, no build 88); a guarda ficou rígida demais e travava o login da abertura a frio (regressão de 04/11, ver a entrada) e a correção vai no próximo build; **voltou no build 92 (05/11 10:38, iPhone14,7) por outro caminho: o bloco do TLS (`_blockToCallOnTCPOpen`) roda no `OpenCompleted` com o stream já em erro — corrigido no build 95 (guarda no bloco e no desafio SASL2, PR 45)**; **voltou em 09/11 15:35 no `.dev` (modo avião: evento de abertura da conexão antiga rodando o bloco da nova, ainda abrindo) — correção na branch `fix/c16-open-completed-conexao-antiga`** |
| C17 | 05/11 22:20 | 95 (produção, iPhone13,3, iOS 27.2) | `0x8BADF00D` (watchdog de cena, em segundo plano) | deadlock: o timer de wakeup roda o bloco na thread de fundo e espera a principal enquanto a principal espera o lock `@synchronized(self)` do `MonalAppDelegate` | corrigido no build 96 (PR 47; teste no `.dev` limitado porque o `.dev` não recebe push) |
| C18 | 06/11 15:21 | 97 (`.dev`, iPhone13,3, iOS 27.2) | SIGABRT (`DefaultsDBCastingError`) | ao abrir Anexos, o `defaultsDB` não achou a chave `videoCompressionMode` (nenhuma migração a gravava) e lançou exceção | corrigido na branch de vídeo (migração na `MLXMPPManager`; validar reinstalando o `.dev`) |
| C19 | 07/11 07:37 | 96 (produção, iPhone13,3, iOS 27) | travamento sem crash (contas congeladas por ~96 s após abrir o app) | o primeiro primeiro plano de um processo que já vivia em segundo plano (com as contas congeladas) foi tratado como abertura a frio: só flags, sem descongelar nem reconectar | corrigido no build 98 (07/11/2026); confirmar em produção depois de uma noite em segundo plano |
| C20 | 09/11 15:04 e 10/11 08:56 | 98 (iPhone 11, iOS 26.7) e 100 (iPhone14,7, iOS 27.2.1) | `0xdead10cc` do app | no 98, app morto 5 s depois de congelar, sem thread no banco; no 100, o próprio registro do C20 symbolicava a pilha dentro de transações com o app congelado (gravação do estado dos downloads e avatar das contas) | registro sem symbolicar e as duas fontes adiadas até descongelar no build 101 (branch `fix/c20-registro-sem-simbolos`) |
| C21 | 08/11 20:06 e 10/11 20:28 | 98 (iPhone12,8, iOS 26.3) e 101 (iPhone13,3, iOS 27.2) | `0xdead10cc` do app, thread principal presa em `disconnectAll` | sem sinal (elevador/garagem), a escrita do último ack esperava sem prazo o `nw_connection_send`; `close` não cancelava a conexão e `cleanupSendQueue` esperava a escrita para sempre; o app não congelava e era suspenso com o `MLProcessLock` | `close` cancela a conexão à força com escrita pendente e a escrita tem prazo de 15 s, no build 102 (branch `fix/c21-escrita-sem-prazo`) |

## Entradas

### C01 · "App hung" do KSCrash nos iPhones mais antigos (29/10/2026, build 54)
- **Sintoma:** o app "fechava" no iPhone 11 (iOS 26.7.2) e no XR. O KSCrash dizia `App hung for 2.25 seconds. Terminated by watchdog.`
- **Causa:** o vigia do KSCrash tem limiar fixo de 250 ms e estava ligado em produção para iOS ≤ 26. Na abertura, a lista decodificava avatares e montava prévias na thread principal.
- **Correção:** vigia só em `DEBUG`, e avatar decodificado em segundo plano com ícone de reserva na hora. Ver `docs/decisoes.md` › "Crashes do iPhone 11 e do XR".

### C02 · Extensão de notificação morta com `0xdead10cc` (29/10/2026, builds 54–63)
- **Sintoma:** seis mortes da `notificationService` num dia (MetricKit), com `RUNNINGBOARD 0xdead10cc`.
- **Causa:** a extensão ficava suspensa entre notificações com a conexão do banco aberta.
- **Correção:** `+[MLSQLite closeDatabasesForCurrentThread]` depois de entregar o conteúdo e em `serviceExtensionTimeWillExpire` (66), e depois sem o `TRUNCATE` que piorava a disputa (67). Ver `docs/decisoes.md` › "Extensão de notificação morta com 0xdead10cc".

### C03 · Deadlock no download de imagens (30/10/2026, build 74)
- **Sintoma:** a produção congelou mais de 2 min depois de uma rajada de imagens. Vieram `0x8BADF00D` e, em segundo plano, `0xdead10cc` às 19:46:44.
- **Causa:** inversão de travas no `MLFiletransfer`. A fila de recebimento segurava a transação e esperava `_stateSyncObject`; a thread do `NSURLSession` segurava `_stateSyncObject` e esperava o banco.
- **Correção:** `+storeState` grava um snapshot fora do lock, de forma assíncrona (75). Ver `docs/decisoes.md` › "Deadlock no download de imagens".

### C04 · `0xdead10cc` por log síncrono (25–30/10/2026, builds 13 e 52)
- **Causa:** a thread do parser, dentro da transação, fez `dispatch_sync` na fila de log, que tinha sido suspensa ao ir para segundo plano. O banco ficou trancado.
- **Correção:** log assíncrono dentro da transação (PR 27, build 83). O de 25/10 (build 13) ficou sem causa provada. Ver `docs/decisoes.md` › "0xdead10cc por log síncrono".

### C05 · `0xdead10cc` do app: os quatro mecanismos (28/10–02/11/2026, builds 36–81)
- **Fonte:** mais de 50 `.ips` do iPhone. São 14 `0xdead10cc` do app: 5 de persistState, 1 de parse, 2 de disconnect, 2 de log, 2 de filetransfer e 2 sem banco.
- **Mecanismos:**
  1. **CPU dentro da transação** (`realPersistState` serializando o estado inteiro, ou o parse do stanza). Ainda **não corrigido**; a medida do `persistState` acima de 50 ms está no log desde o build 85 (roadmap 131).
  2. **`disconnect` com rede dentro da transação.** Corrigido no 85: a rede ficou fora da transação, com espera de no máximo 2 s.
  3. **Log síncrono.** Ver C04.
  4. **Deadlock do `MLFiletransfer`.** Ver C03.
- **Bilhete de loteria removido:** a thread `im.monal.timeouts` abria uma transação por conta a cada segundo. Desde o 85 só abre quando há algo a fazer e pula contas congeladas.
- **Sem causa visível:** um caso (01/11 05:59). Candidato: o `flock` do `MLProcessLock`.
- **Próximo passo:** contar os `0xdead10cc` por dia depois do 85 (`scripts/classificar-crashes.py --pull`) e ler as linhas "slow realPersistState" antes de pensar em gravar o estado em lote. Ver `docs/decisoes.md` › "Análise dos 0xdead10cc" e "Desconectar com a rede fora da transação".

### C06 · `0x8BADF00D` com a thread principal esperando sem prazo (builds 53–75)
- **Pilhas:** `disconnectAll` em barreira, `unfreeze` com `NSCondition` e `sqliteDefaultBusyCallback`.
- **Situação:** o desenho continua igual, mas não houve mais ocorrência depois do 75. Volta a ser suspeito se aparecer de novo.

### C07 · SIGABRT da extensão (29/10/2026, build 68)
- **Sintoma:** 17 vezes, com `beginWriteTransaction` depois de fechar o banco.
- **Correção:** a mudança do 68 foi revertida.

### C08 · `ObservableKVOWrapper` (builds 53 e 77)
- **Sintoma:** no 77, `contact.lastInteractionTime != nil` derrubava o app ao abrir um chat com "visto por último". O subscript genérico faz `as? T` e lança exceção quando o tipo inferido não confere.
- **Regra:** ler membros do wrapper sempre com tipo explícito (`let d: Date? = contact.x`).
- **Teste:** usar um contato com `lastInteraction` preenchido. Ver `docs/decisoes.md`.

### C09 · `fatalError("Messages can not have duplicate ids")` (02/11/2026, build 81)
- **Sintoma:** ao compartilhar um link, a mensagem da fila de compartilhamento entrava na lista duas vezes (com `append` e de novo pelo refresh).
- **Correção:** o aviso da fila usa `enqueueNewMessages`, que ignora duplicatas (83). Ver `docs/decisoes.md` › "Crash ao compartilhar um link".

### C10 · "New Message?": extensão morta por check-in timeout (02/11/2026)
- **Sintoma:** o launchd matou a extensão de notificação com `EXTENSION_CHECK_IN_TIMEOUT` (5 s) antes do `-init`, e o iOS entregou o texto cru do push. Não gera `.ips`; só aparece no `log collect` do aparelho.
- **Suspeita:** `+[MLUDPLogger flushWithTimeout:]`, uma espera sem predicado que pode perder o sinal.
- **Correção:** flag e `waitUntilDate:` em laço (PR 32, build 84). Validar pela contagem de "New Message?". Ver `docs/decisoes.md` › "Notificação New Message?" e `docs/troubleshooting.md`.

### C11 · Deadlock do envio criptografado (03/11/2026 16:14, `.dev` do build 87)
- **Sintoma:** ao compartilhar uma foto para um contato, a conversa abriu e congelou para sempre. Fechar à força gerou `0x8BADF00D` ("Failed to terminate gracefully", 16:17:22).
- **Causa:** inversão de travas.
  - **Thread principal:** `sendAllOutboxes` → `xmpp sendMessage:` → `MLOMEMO encryptMessage:` pegava a trava do Signal e esperava o banco para gravar a sessão.
  - **Fila de recebimento:** estava na transação, processando um bundle OMEMO (`processPreKeyBundle`), e esperava a trava do Signal.
- **Correção:** criptografar dentro de `createTransaction`, com o banco antes da trava do Signal (`xmpp.m`, build 88). Ver `docs/decisoes.md` › "Deadlock entre o envio criptografado…".

### C12 · SIGSEGV na abertura gerando chave OMEMO (03/11/2026 16:38, `.dev` do build 87)
- **Pilha:** thread principal, `didFinishLaunching` → `connectIfNecessary` → `MLOMEMO activate` → `createLocalIdentiyKeyPairIfNeeded` → `curve25519` (SIGSEGV).
- **Causa:** a extensão de compartilhar não tinha `keychain-access-groups`. Por isso lia outro `deviceUUID` do keychain, e a migração ("Device id has changed") apagava `signalIdentity`, sessões e pre-keys e invalidava o estado das contas a cada alternância entre app e extensão. A cada abertura o app gerava identidades OMEMO novas e numa delas caiu. Afetava também a produção.
- **Correção:** a extensão ganhou o grupo de keychain do app em `Monal/shareSheet.entitlements` e `isaCloud/dev-entitlements/shareSheet.entitlements` (build 88). No `.dev`, o mesmo `device id` aparece nos dois processos.
- **Efeito que fica:** os contatos viram dispositivos OMEMO novos. Ver `docs/decisoes.md` › "Extensão de compartilhar sem o grupo de keychain…".

### C13 · `MLContactCell displayLastMessage` com `hasPrefix` em `NSData` (03/11/2026, simulador)
- **Causa:** um teste inseriu no banco do simulador uma mensagem com `message` em BLOB, e a lista de conversas caiu ao montar a prévia.
- **Situação:** o app real sempre grava texto. Fica registrado como cuidado ao fabricar linhas de teste: `message` deve ser `TEXT`.

### C14 · `MLFiletransferInfo` sem linha de `filetransfer_info` (24 e 25/10/2026, builds 5 e 8)
- **Fonte:** Xcode Organizer, dois relatórios (iPhone13,3 com iOS 26.6.2 e iPhone11,8 com iOS 18.7.10). A asserção era em `createFiletransferInfoForMessage:`, vinda de `ChatViewMessage.init` ao abrir um chat com mensagem de arquivo sem a linha correspondente (visto no histórico de canal no iOS 18).
- **Correção:** a linha é criada vazia na hora e preenchida depois (`MLFiletransferInfo.m`, `//isaCloud:`).

### C15 · Asserção no `disconnect` durante o congelamento (30/10/2026, build 67)
- **Fonte:** Xcode Organizer (iPhone13,3, iOS 27.0.1). A pilha era `MLXMPPManager disconnectAll` → `xmpp disconnectWithStreamError:andExplicitLogout:`, no caminho de desligamento correndo com o congelamento do app.
- **Correção:** a asserção virou aviso no log (`xmpp.m`, comentário `//isaCloud: this used to be an MLAssert…`).

### C16 · `MLStream tlsVersion` com o stream em erro (03/11/2026 22:30:56, build 88, iPhone14,7, iOS 27.2)
- **Fonte:** relatório de um usuário. Veio em duas formas, que são o mesmo crash: Xcode Organizer (`.xccrashpoint`, `SIGABRT`, thread 21) e o `CrashReport-1.mcrash` do próprio app (KSCrash com o log anexado, conta 3). Motivo: `MLAssert triggered at Classes/MLStream.m:849 in -[MLStream tlsVersion] with reason 'Stream must be open to call this method!'`, `streamStatus = 7` (`NSStreamStatusError`).
- **Sequência no log anexado (conta 3):**
  - **22:30:56,208:** a conexão da conta 3 cai ("Software caused connection abort"; é o iOS derrubando as conexões ao congelar o app). O `MLStream` reporta o erro.
  - **22:30:56,355:** a fila de parse é descongelada ("Parse queue is UNfrozen now!") e processa os recursos de login (SASL2) que estavam na fila.
  - **Ali mesmo:** `handleFeaturesBeforeAuth` → `channelBindingToUse` → `supportedChannelBindingTypes` → `isTLS13` → `tlsVersion`, com o stream já em erro. A asserção derruba o app.
- **Causa:** corrida entre a queda da conexão e o processamento de um stanza que já estava na fila. Código do Monal (a `develop` tem o mesmo).
- **Correção (04/11/2026, branch `fix/login-com-stream-em-erro`, vai no próximo build):** em `xmpp.m`, ao processar os recursos antes da autenticação, parar se o stream de saída não estiver aberto (`streamStatus` fora de `Open…<Closed`). É só um aviso no log e o retorno, deixando a reconexão normal seguir.
  - **O que não fazer:** devolver uma lista vazia de channel binding ou zero no `tlsVersion`. Isso pode cair no ramo que **desativa a conta por suspeita de MITM** (canais anunciados sem par).
- **Validar:** a asserção não aparece mais. Para provocar: congelar o app logo depois de conectar, ou cortar a rede durante o login.
- **Segunda ocorrência (04/11/2026 10:53:38, build 88, iPhone13,3 = iPhone da Isadora, iOS 27.2):** `.ips` `isaCloud-2026-11-04-105338.ips` (SIGABRT, fila `receiveQueue[47:...]`, conta `isadora@xmpp.social.br`), pilha idêntica: `handleFeaturesBeforeAuth` → `channelBindingToUse` → `supportedChannelBindingTypes` → `isTLS13` → `tlsVersion` → `MLAssert`. O app de produção ainda era o build 88 (o 89, com a correção, subiu às 10:43 e ainda não estava instalado). O log do aparelho (`.rawlog`) saiu truncado em 10:53:17 (cópia de arquivo em escrita), então não mostra a queda de rede dos últimos 20 s; o mesmo padrão do log do usuário. As pastas de `~/Downloads/crashes-report/` de 04/11 trazem o mesmo evento por duas vias: o `CrashReport-1.mcrash-8 copy` (KSCrash, 932 KB, 10:53:37.087, `streamStatus = 7` = erro, thread 16; **sem log anexado**, `logfileCopyResult: -1`) e a entrada de 10:53:37 no `.xccrashpoint`. O `CrashReport-1.mcrash-8` de 5 MB é o de 03/11 22:30 (usuário, iPhone14,7), com o log. O relatório foi enviado pelo build **89**, que já estava instalado no aparelho quando o app reabriu. **Confirma que o crash é real e frequente o bastante para aparecer em dois aparelhos em ~12 h; o build 89 é o que o corrige. Validar no 89: nenhuma nova asserção `Stream must be open`.**
- **Regressão (04/11/2026, medição de conexão):** a guarda de 04/11 também descartava o stream em "abrindo" (`NSStreamStatusOpening`). Na TLS direta com recursos guardados, o login antecipado chega com o TLS ainda abrindo, então toda abertura a frio esperava os 12 s do prazo de login (`Login took too long`) e só reconectava depois. Log do iPhone: 18:42:21 → 18:42:34 e 18:43:31 → 18:43:43, nas três contas. **Correção:** a guarda passou a descartar só o stream não aberto (`NSStreamStatusNotOpen`) e o fechado ou em erro (`>= NSStreamStatusClosed`). O status "abrindo" é seguro porque o trabalho que depende do TLS fica em `_blockToCallOnTCPOpen`, que só roda com o TLS pronto. O crash continua coberto pelo caso de erro (status 7). **Validar:** abrir a frio com recursos guardados e ver a conta ociosa sem `login_timeout` em `connects-*.jsonl`.
- **Terceira ocorrência (05/11/2026 10:38:42, build 92, iPhone14,7, iOS 27.2, aparelho do Roney):** `CrashReport-1.mcrash-8 copy 2` (KSCrash, 990 KB, thread 14, `streamStatus = 7`; **sem log anexado**, `logfileCopyResult: -1`). Mesma asserção, mas a pilha mostra outro caminho: `-[xmpp stream:handleEvent:]_block_invoke` → `handleFeaturesBeforeAuth:withForceSasl2:]_block_invoke_2` (o `_blockToCallOnTCPOpen`) → `channelBindingToUse` → `supportedChannelBindingTypes` → `isTLS13` → `tlsVersion`. **Causa:** a guarda do começo de `handleFeaturesBeforeAuth` passa com o stream em "abrindo" (o relaxamento de 04/11, que entrou no build 92) e guarda o bloco do TLS; o `NSStreamEventOpenCompleted` agenda o bloco com `dispatchOnReceiveQueue`, e quando a fila o roda o stream já caiu para erro. A guarda não protege esse ponto. O código de `xmpp.m` é o mesmo do build 92 até o 94, então **o crash continua aberto em produção**. **Correção proposta:** no bloco do `OpenCompleted` (e/ou no começo do próprio `_blockToCallOnTCPOpen`), conferir o `streamStatus` do `oStream` e, se estiver fechado ou em erro, só registrar um aviso e descartar o bloco (`_blockToCallOnTCPOpen = nil`), deixando a reconexão seguir; continua valendo não devolver channel binding vazio (risco de desativar a conta por MITM).
  - **Correção aplicada (05/11/2026, branch `fix/c16-bloco-tls-stream-em-erro`, PR 45, build 95):** guarda no começo de `_blockToCallOnTCPOpen` e no ramo `{urn:xmpp:sasl:2}challenge` de `processInput`, com a mesma condição da guarda de `handleFeaturesBeforeAuth` (`NSStreamStatusNotOpen` ou `>= NSStreamStatusClosed`): só aviso no log e `return`. "Abrindo" passa de propósito, porque a chamada direta do bloco pode acontecer com o handshake da TLS direta ainda em curso e barrar esse caso traria de volta a espera de 12 s. Fica uma janela pequena entre conferir o status e ler o TLS (o status muda em outra thread); fechá-la exigiria mexer nas asserções do `MLStream`, o que complica o merge com o Monal. **Validado** só no login normal a frio (simuladores do iOS 18.6 e 27, três contas, sem `Login took too long`); a corrida em si não foi reproduzida. **Validar em produção:** nenhuma nova asserção `Stream must be open`.
- **Quarta ocorrência (09/11/2026 15:35:33, `.dev` build 99 com o merge do Monal/develop, iPhone13,3, iOS 27.2):** a Isadora ligou e desligou o modo avião com o app aberto. `.ips` `isaCloud-2026-11-09-153535.ips` (SIGABRT, fila `receiveQueue[1:...]`, conta `poli@isacloud.im`) e o log exportado do `.dev` mostram a mesma pilha do build 92 (`stream:handleEvent:` → bloco do `OpenCompleted` → `_blockToCallOnTCPOpen` → `channelBindingToUse` → `tlsVersion`), mas com `streamStatus = 1` (**abrindo**), que a guarda deixa passar. No log, a conta reconecta às 15:35:33.680 (streams novos, TLS direta, auth em pipeline com features em cache, "Waiting until TLS stream is connected...") e a asserção vem 1 ms depois. **Causa:** o `NSStreamEventOpenCompleted` vai para a fila de recepção e um reconnect pode rodar antes dele; quando o bloco roda, o evento é da conexão que acabou de ser fechada, enquanto `self.oStream` e `_blockToCallOnTCPOpen` já são os novos, ainda abrindo. Não veio do merge: `xmpp.m` e `MLStream.m` estão iguais aos da `isaCloud`, então o build 99 de produção tem o mesmo risco.
  - **Correção (09/11/2026, branch `fix/c16-open-completed-conexao-antiga`):** no bloco do `OpenCompleted`, só seguir (estado `kStateConnected` e `_blockToCallOnTCPOpen`) se o evento for do `self.oStream` atual e ele estiver `NSStreamStatusOpen`. O `MLStream` marca `open` antes de gerar o evento, então o evento verdadeiro da conexão atual sempre vê "aberto"; os outros só registram `Ignoring stale open completed event` e mantêm o bloco para o evento verdadeiro (stream fechado ou com erro é limpo pelo reconnect, que também descarta o bloco). A guarda de "abrindo" nos outros pontos continua igual, para não trazer de volta a espera de 12 s. **Validar no `.dev`:** alternar o modo avião com o app aberto, várias vezes, sem crash e com as contas voltando; no log, a frase `Ignoring stale open completed event` quando a corrida acontecer.
  - **Validado no `.dev` (09/11/2026 15:53–15:55):** a Isadora alternou o modo avião com o app aberto. A corrida aconteceu uma vez (15:54:54.707, `Ignoring stale open completed event`, stream atual em status 1) e foi contida: sem crash, e as três contas retomaram a sessão (SM resumed) em 1 a 2 s. Os `Login took too long` do log são do período sem rede, como esperado.

### C17 · deadlock no wakeup por push, em segundo plano (05/11/2026 22:20:12, build 95, iPhone13,3, iOS 27.2)
- **Sintoma:** o app foi morto pelo sistema à noite, em segundo plano, sem aviso. O relatório só foi enviado na manhã seguinte, quando a pessoa abriu o app (`Trying to send crash reports` às 06:47–06:48 de 06/11). Por isso a pessoa percebeu o crash de manhã.
- **Fonte:** `isaCloud-2026-11-05-222013.ips` (`bug_type` 309, `termination`: `FRONTBOARD`, código `0x8BADF00D`, "scene-update watchdog transgression", `ProcessState: Running`, `ProcessVisibility: Background`). Logs dos aparelhos (`Library/logs`) de 05:31 a 09:52 de 06/11 não têm `App launching`: o app não foi reiniciado depois do crash.
- **Causa (pelo `.ips`):** a thread principal está em `-[MonalAppDelegate incomingWakeupWithCompletionHandler:]`, presa em `objc_sync_enter` (espera o lock `@synchronized(self)`). Ela veio de um push (PushKit → `application:didReceiveRemoteNotification:`). Outra thread (`com.apple.root.default-qos`) está no timer de segurança do wakeup: `runOnMainQueue:withTimeout:` esgotou o prazo (a principal não rodou o bloco), então o bloco rodou nessa thread, **dentro de `@synchronized(self)`**, e chegou a `HelperTools scheduleBackgroundTask:` → `dispatchAsync:reentrantOnQueue:` (`dispatch_sync` para a principal). Cada uma espera a outra: a principal quer o lock, a de fundo quer a principal. O sistema matou o app depois de ~20 s.
- **Onde:** `Monal/Classes/MonalAppDelegate.m` (bloco do timer de wakeup, `Handling wakeup completion`, com o `@synchronized(self)` e o `scheduleBackgroundTask:!wasIdle`) e o fallback de `runOnMainQueue:withTimeout:` (que roda o bloco na thread de fundo quando a principal não responde). O fallback é de isaCloud (build 81). Não tem relação com as mudanças de rede e de login do build 95 (`xmpp.m`, `MLXMPPManager.m`).
- **Correção (build 96, PR 47):** o corpo do timer de wakeup só lê e grava estado dentro de `@synchronized(self)` (com a reconferência descrita abaixo); `scheduleBackgroundTask`, `updateSyncErrorsWithDeleteOnly`, `disconnectAll` e o `kMonalWillBeFreezed` rodam depois, fora do lock. O `completionHandler` também sai do lock. O fallback de `runOnMainQueue` e os outros blocos com lock listados abaixo não mudaram.
- **Revisão da correção (06/11/2026, segunda opinião):** a separação do lock não muda nada quando o bloco roda na principal (caminho normal, tudo serializado por ela). Só o fallback de fundo muda: antes travava (C17), agora não trava, mas abria uma corrida. Com o lock solto, um push novo (o próprio cenário do C17: a principal estava em `incomingWakeupWithCompletionHandler:` esperando a extensão) ou a volta para a frente podiam reconectar e registrar outro timer, e a thread de fundo em seguida rodava `disconnectAll` + `kMonalWillBeFreezed`. O `prepareForFreeze` congela as contas, solta o `MLProcessLock` (a extensão pode rodar junto) e marca `_wasFrozen`, e o `signalSuspension` pausa o logger, deixando o push novo sem conexão até o timer dele. Por isso, **logo antes de desligar, o bloco reconfere dentro do lock** que `_shutdownPending` continua `YES` (a volta para a frente põe `NO`), que o app continua em segundo plano e que não entrou outro wakeup (só a própria entrada em `_wakeupCompletions`); se algo mudou, desiste e só chama o `completionHandler`. O `scheduleBackgroundTask` passou a ser assíncrono nesse ponto. Manter o `disconnectAll` dentro do lock foi descartado: ele espera cada conta desconectar e as filas das contas podem esperar a principal (o mesmo tipo de deadlock por outro caminho). Sobra uma janela de milissegundos entre a reconferência e o congelamento, aceita. Não afeta o C16, a reconexão pela rede (`xmpp.m`, `MLXMPPManager.m`) nem os fallbacks do C06/C11. Dois timers desligando juntos já era possível antes e o `disconnectAll` pula contas congeladas.
- **Correção proposta original (base da correção acima):** (1) não chamar `scheduleBackgroundTask:` (nem nada que faça `dispatch_sync` para a principal) dentro de `@synchronized(self)`: calcular as condições dentro do lock e fazer a parte de UIKit/agendamento depois, fora dele; (2) o fallback de `runOnMainQueue` não deve rodar o bloco na thread de fundo quando ele precisa da principal, ou deve pular essas partes; (3) avaliar trocar o `@synchronized(self)` do wakeup por um objeto de lock próprio, para a principal nunca disputar o lock com o timer.
- **Validar:** provocar um push de wakeup com o app em segundo plano e a principal ocupada (por exemplo, com o app congelando logo antes), e conferir que não aparece `0x8BADF00D` nem a pilha acima. No `.dev`, ver `Main queue did not run our block` e `Handling wakeup completion` no log, sem travar.
- **Relação com outros crashes:** é a mesma classe do C06 (thread principal presa sem prazo) e do C11 (deadlock com `dispatch_sync`), mas o caminho é outro.

### C18 · `DefaultsDBCastingError` ao abrir Anexos (06/11/2026 15:21:44, build 97 do `.dev`, iPhone13,3, iOS 27.2)
- **Sintoma:** ao tocar em Configurações → Anexos, o app fechou sozinho.
- **Fonte:** `isaCloud-2026-11-06-152144.ips` (SIGABRT, `bundleID` `br.com.isacloud.messenger.dev`). Pilha: `HelperTools throwExceptionWithName:` ← `defaultsDB.wrappedValue.getter` ← `GeneralSettingsDefaultsDB.videoCompressionMode.getter` ← `Binding(keyPath:)` ← `AttachmentSettings.body`.
- **Causa:** a configuração de vídeo nova lê `videoCompressionMode` pelo `@defaultsDB`. O wrapper não tem valor padrão: se a chave não existe, lança exceção (`SwiftHelpers.swift`). A chave só era gravada por migração, e a migração não existia. Quem nunca tocou no seletor (e instalações novas) abre Anexos e cai. Código do isaCloud, não do Monal.
- **Correção:** em `MLXMPPManager.m`, junto da migração de `imageCompressionMode`, grava `"480"` se a chave não existir. Leitura de `MLFiletransfer.m` já tinha `?: @"480"`, então o envio não dependia da chave.
- **Validar:** reinstalar o `.dev` e abrir Anexos, com e sem a chave (conferir com um `.dev` novo). Em `Monal/Classes/GeneralSettings.swift`, qualquer nova chave de `@defaultsDB` precisa de migração ou padrão antes da tela que a lê.

### C19 · contas congeladas ao abrir o app depois de uma noite em segundo plano (07/11/2026 07:37:20, build 96, iPhone13,3)
- **Sintoma:** a Isadora abriu o app pela manhã e as contas ficaram mais de 1 minuto sem conectar; precisou encerrar e abrir de novo. Não gerou crash report.
- **Fonte:** quatro `.rawlog` de produção (23:16 a 07:39 de 06 e 07/11, exportados para o iCloud Drive). Nenhum `App launching` nesse intervalo: o processo viveu a noite toda, acordado a cada ~7 min por tarefas de segundo plano (BGAppRefresh).
- **Causa (provada pelo log):** às 07:35:41 rodou uma tarefa de segundo plano, que reconectou as contas e as congelou às 07:36:07 (`BGREFRESHING EXPIRED` → `Parse queue is frozen now!`). Às 07:37:20 a cena foi para o primeiro plano pela primeira vez na vida do processo. `SceneDelegate.sceneWillEnterForeground` (`SwiftuiHelpers.swift`) trata o **primeiro** primeiro plano como abertura a frio: chama só `nowForegroundedAtLaunch` (atualiza flags) e retorna, sem `applicationWillEnterForeground` (que descongela e reconecta). O log mostra `App now foregrounded (launch), only updating flags...`, depois `Not pinging ... parse queue frozen!`, e nenhum `Entering FG`, `calling unfreeze` nem `connecting account` até a pessoa encerrar o app (07:38:56). Na abertura a frio seguinte, as contas conectaram em poucos segundos. O atalho é de 24/10/2026 (builds 6 a 9), feito para a abertura a frio do iOS 27.
- **Por que só apareceu agora:** antes, o app costumava morrer à noite (por exemplo pelo C17, `0x8BADF00D` em segundo plano), e a abertura da manhã era sempre a frio. Com o processo sobrevivendo, o primeiro primeiro plano passou a ser uma volta de verdade.
- **Correção (build 98, branch `fix/primeiro-plano-apos-segundo-plano`):** o atalho só vale se o processo nunca foi congelado. `MonalAppDelegate` expõe `isaCloudWasFrozen` (o `_wasFrozen` que `prepareForFreeze:` já põe em `YES`); se já foi congelado, o primeiro primeiro plano segue o caminho normal `applicationWillEnterForeground`, o mesmo das voltas seguintes. Não mexe em C16, C17 nem na reconexão pela rede.
- **Limite conhecido:** um processo acordado em segundo plano que ainda não congelou quando a tela aparece continua no atalho (contas conectadas, só as flags mudam); não foi visto nos logs.
- **Validar:** no `.dev`, deixar o app em segundo plano até rodar uma tarefa de segundo plano (algumas dezenas de minutos ou uma noite) e abrir: o log deve mostrar `Entering FG` e `calling unfreeze` e as contas conectarem em poucos segundos. Cuidado: sem esse tempo o teste não passa pelo caminho novo.

### C20 · `0xdead10cc` do app logo depois de congelar, sem thread no banco (09/11/2026 15:04:55, build 98, iPhone 11)
- **Sintoma:** `RUNNINGBOARD 0xdead10cc` com Modo de Pouca Energia ligado. No crash, nenhuma thread está no SQLite nem pegando trava: a principal espera eventos e a `im.monal.timeouts` dorme (`MLXMPPManager.m`, `sleepForTimeInterval`). É o terceiro caso "sem banco" (os outros: 01/11 05:59 e 04/11, build 88).
- **Fonte:** `.xccrashpoint` com 5 relatórios do mesmo aparelho e quatro `.rawlog` de produção (09/11, 13:40 a 16:33).
- **Linha do tempo:** 15:04:50.416 o app vai para segundo plano e desconecta; 15:04:50.498 avisa o congelamento e solta o `MLProcessLock`; 15:04:50.507 suspende a fila de log (daí em diante o app não registra mais nada); 15:04:51.5 a extensão de notificação sobe, vê `Remote MainApp running: NO` às 15:04:51.8 e faz o catch-up de 10 salas, gravando o estado ~30 vezes por segundo e fazendo checkpoint do WAL; 15:04:55.563 o app é morto no meio dessas gravações.
- **Descartado:** o `MLProcessLock` (a extensão o achou livre às 15:04:51.8); transação em andamento (nenhuma thread no SQLite); a limpeza automática de mensagens (desligada no aparelho); a thread de timeouts (com a conta desconectada, `updateIqHandlerTimeouts` sai antes de tocar no banco). A extensão não registrou espera por banco ocupado.
- **Causa:** suspeita, não provada. Algum trabalho atrasado do app tocou no banco nos 5 s entre o congelamento e a suspensão, ao mesmo tempo em que a extensão gravava sem parar. Esse trecho é cego: o log do app já estava suspenso.
- **Correção (aberta, branch `fix/c20-banco-depois-de-congelar`):** registro de qualquer acesso ao banco depois de `signalSuspension`, gravado num arquivo pequeno do grupo de apps (sem passar pelo log suspenso) e despejado no log normal na volta (`signalResumption`) ou na próxima abertura, com a pilha de chamadas. A limpeza automática também deixa de rodar com o app suspenso.
- **Regressão no build 100 (10/11/2026 08:56:49, iPhone14,7, iOS 27.2.1, app aberto desde 07:46 e ~10 min em segundo plano):** `0xdead10cc` com duas threads dentro de `isaCloudRecordDbAccessAfterFreeze:` montando a pilha com `[NSThread callStackSymbols]` (→ `backtrace_symbols` → `dladdr`, que varre as tabelas de símbolos e é lento):
  - thread de fundo **dentro de uma transação de escrita**: `+[MLFiletransfer storeState]` → `-[DataLayer setFiletransferState:]`, disparada por `URLSession:downloadTask:didFinishDownloadingToURL:` (download em segundo plano terminando com o app congelado);
  - thread principal dentro de uma transação de leitura: `-[ActiveChatsViewController updateAccountAvatar]` → `-[DataLayer accountList]`, disparada por `refreshContact:`/`handleRefreshDisplayNotification:`.
  O registro esticou as transações até o iOS suspender o app com a trava. Ao mesmo tempo, mostrou quem toca no banco com o app congelado.
- **Correção do build 101 (branch `fix/c20-registro-sem-simbolos`):** o registro grava só os endereços de retorno (`callStackReturnAddresses`, sem symbolicar) e os endereços de carga do `monalxmpp` e do app (`base monalxmpp=0x... app=0x...`), para symbolicar depois com `atos -l <base> -o <dSYM>`; o formatador de data é criado uma vez. `MLFiletransfer storeState` não grava com o app congelado e grava o estado ao descongelar (`kMonalUnfrozen`). `updateAccountAvatar` não lê o banco com o app congelado e se atualiza ao descongelar.
- **Segunda ocorrência no build 101 (10/11/2026 22:48:07, iPhone13,3):** BGPROCESSING expirou às 22:48:04.120; o `disconnectAll` levou 2,1 s (gravações do estado da conta 9 de 260 a 345 ms, 176 KB); a thread principal estava em `signalSuspension` → `flushLogsWithTimeout` quando o app morreu, 2,9 s depois da expiração. Nenhuma thread no banco e nenhuma linha `isaCloud C20:`, mas o registro só ligava depois do `flushLogs`. Desde o build 102 ele liga no `kMonalWillBeFreezed` (`isaCloudArmDbAccessRecording`) e desliga ao descongelar.
- **O registro funcionou:** às 21:06 e 21:09 de 10/11 gravou leituras curtas na thread principal com o app congelado (última mensagem da lista de conversas e reações), sem relação com os crashes. Os endereços não foram symbolicados porque o dSYM do 101 não foi guardado; desde o 102 o dSYM de cada build fica em `~/Library/Developer/Xcode/Archives/isacloud-dsyms/build-N/`.
- **Lição:** nada caro (symbolicar, formatar, alocar muito) dentro do caminho do SQL; instrumentação em ponto quente precisa ser tão barata quanto o próprio acesso.
- **Validar:** nos próximos logs de produção, procurar `isaCloud C20:` (a partir do build 101, com endereços). Uma pilha ali aponta quem toca no banco depois do congelamento; se o crash voltar sem nenhuma linha dessas, o banco fica descartado e o próximo suspeito é outro arquivo travado.

### C21 · desconexão presa numa escrita sem rede (08/11/2026 20:06 build 98, iPhone12,8; 10/11/2026 20:28:53 build 101, iPhone13,3)
- **Sintoma:** `RUNNINGBOARD 0xdead10cc` em segundo plano. No caso de 10/11 a Isadora estava no elevador/garagem, sem sinal. O log para 15 s antes da morte.
- **Pilhas (iguais nos dois aparelhos):** thread principal no expirador da tarefa de segundo plano → `-[MLXMPPManager disconnectAll]` (espera síncrona); `-[xmpp closeSocket]` → `-[xmpp cleanupSendQueue]` (`addOperations:waitUntilFinished:YES`, sem prazo); na `sendQueue`, `-[xmpp sendSMAck:]` (via `isaCloudRunOnSendQueue:withTimeout:`) → `-[MLOutputStream write:maxLength:]` parado em `[condition wait]`.
- **Causa (provada pelas pilhas):** sem rede, o `nw_connection_send` do último ack não completa. `-[MLStream close]` só enfileira a mensagem final e cancela a conexão no completion dela, que fica atrás da escrita travada. O prazo de 2 s do build 85 (`isaCloudRunOnSendQueue:withTimeout:`) contava com o `close` destravar a escrita, mas o `cleanupSendQueue` logo depois espera a mesma operação sem prazo. O app nunca chega ao `prepareForFreeze`, não solta o `MLProcessLock` e é suspenso com ele.
- **Correção (build 102, branch `fix/c21-escrita-sem-prazo`):** `-[MLOutputStream close]` chama `nw_connection_force_cancel` quando há escrita pendente (os sends pendentes completam com erro e a escrita retorna). Rede de segurança: a espera da escrita tem prazo de 15 s; passado o prazo, cancela a conexão à força e espera o completion, que então vem rápido.
- **Validar:** no `.dev` com uma conta conectada, ligar o modo avião e mandar o app para segundo plano logo em seguida; o log deve mostrar `Posting kMonalWillBeFreezed` e `Unlocking process` em poucos segundos, sem travar no `disconnectAll`. Em produção: nenhum `0xdead10cc` com `disconnectAll` na pilha principal.

## Modelo para um crash novo

```markdown
### CNN · <título curto> (<data e hora>, build <N>, <aparelho/iOS>)
- **Sintoma:** o que a pessoa viu e o que o relatório diz (tipo, `termination`, thread).
- **Fonte:** `.ips` <nome>, log <arquivo e intervalo>, MetricKit, KSCrash.
- **Causa:** provada ou suspeita (dizer qual), com a pilha que importa.
- **Correção:** o que mudou, arquivos, PR e build; ou "aberto".
- **Validar:** como saber que não voltou.
```

Acrescente também uma linha na tabela do resumo e, se houve decisão de projeto, a seção correspondente em `docs/decisoes.md`.

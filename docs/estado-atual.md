# Estado atual e handoff (26/11/2026, build 135)

Página de passagem: o que está no ar, o que foi tentado, o que **não** repetir e por onde continuar.
Detalhes de cada frente ficam nos documentos citados; aqui está o mapa.

## Onde estamos

| | |
|---|---|
| Commit | o do **build 135** (tag `build-135`: canal leve com lacuna por sala, PR 98); antes, o do **build 134** (tag `build-134`: sessão retomada com a descoberta pela metade, PR 97); antes, o do **build 133** (tag `build-133`: C39, arquivo retratado durante o HEAD, PR 96); antes, o do **build 132** (tag `build-132`: bolinha de atualização no título, PR 95, e correções do canal leve, PR 94); antes, o do **build 131** (tag `build-131`: canal leve, fase A, PR 92, e a opção "Abrir isaCloud Meet", PR 93); antes, o do **build 130** (tag `build-130`: nota com o link de anfitrião ao criar conferência e aviso com "Ver", PR 91); antes, o do **build 129** (tag `build-129`: brilho da original no pulo e citação sem vínculo com balão, PR 90, e PR 25 do fork do ExyteChat); antes, o do **build 128** (tag `build-128`: reply XEP-0461, fases 1 e 2, PR 89, e toque na citação no fork do ExyteChat, PR 24); antes, o do **build 127** (tag `build-127`: C38, extensão de notificação no fim do prazo e com o app principal rodando); antes, o do **build 126** (tag `build-126`: enquetes com um cartão só e placar congelado, PR 87, e C37, reação em canal sem occupant-id próprio, PR 88); antes, o do **build 125** (tag `build-125`: C35 e C36, gravação adiada e escrita presa no desligamento); antes, o do **build 124** (tag `build-124`: ligações com o Web e com o app fechado); antes, o do **build 123** (tag `build-123`: enquetes do Fluux, criar conferência pelo Galene, figurinhas só no atalho da caixa de texto); antes, o do **build 122** (tag `build-122`: folga no desligamento da extensão de notificação, C34, PR 85); antes, o 121 (`38b814af7`, tag `build-121`: correção do C33 e do log longo, PR 84); antes, o 120 (`f884e6c04`, tag `build-120`: espelhar selfies, PR 83); `git log --oneline -3` |
| TestFlight | **135** (26/11/2026, 16:27): a busca dos canais leves ao abrir não deixa mais canais para trás quando uma sala não responde (PR 98). Antes: **134** (25/11/2026, 16:27): foto sem envio numa sessão retomada cuja descoberta não terminou. Antes: **133** (25/11/2026, 13:32): C39, sem SIGABRT quando o arquivo é retratado ou muda de tipo durante o HEAD de tipo e tamanho (PR 96). Antes: **132** (25/11/2026, 12:42), bolinha de atualização e correções do canal leve |
| `.dev` no iPhone | **135** com o código do build mais o push do `.dev` (27/11/2026 15:15, ainda sem commit). **Recebe push** desde 27/11: módulo `isaCloudDeviOS-sandbox` no fpush, primeiro push às 15:18; a extensão de notificação roda no `.dev` |
| Simuladores | iPhone XR (iOS 18.6) e isaCloud iOS27 com o código do build 121 (o 122 só mexe na extensão, que não roda no simulador) (20/11/2026, ad-hoc, por cima do banco; backup em `~/Library/Application Support/isacloud-sim-backups/<udid>-20261120-0833-c33/`) e as 3 contas de teste; a extensão não roda no simulador com `simctl push` |
| ExyteChat | `3c09327` na `isaCloud` (toque na citação `onQuoteTap`, PR 24, mudança nº 25); antes `80602dd` (visualizador sem `TabView` paginado com um anexo só, PR 23, mudança nº 24; antes `3eb0aa1`: tamanho do arquivo nas mídias e nos áudios, PR 22; antes `7d3292b`: miniatura opcional dentro da citação, `Message.quotePreview`, PR 21; antes `e168ed8`: visualizador de mídia só com o anexo tocado, opção `fullscreenSingleAttachment`, PR 20; antes `f49d4f6`: card de link com altura fixa, PR 19). Detalhes em `docs/exytechat-fork.md`. |
| Instrumentação temporária | **fora do código**; patches da sonda em `isaCloud/local/` (`chatjump-app.patch`, `chatjump-exytechat.patch`, ver `docs/investigacao-atraso-na-conversa.md` §8) |

Comando para conferir: `git log --oneline -3 && git status --porcelain`.

## Validações e pendências (revisão de 16/11/2026)

- **OK pela Isadora:** build 104 (reingressar em sala mantida, "Remover da lista", selos), build 105 (novidades com selo "Novo" na atualização 104 → 105) e build 106 (sem pedido de contato repetido entre `.dev` e produção).
- **Arquivado:** o limite de reparo de sessão OMEMO do build 110 (substituído pela correção do build 112).
- **Ainda em avaliação:** build 112 (aceitar mensagem de aparelho OMEMO conhecido removido da lista; testar com dois aparelhos).
- **Primeira mensagem não lida (build 87):** só no roadmap, sem previsão de nova avaliação.
- **Figurinhas e XEP-0449 (roadmap 155):** análise iOS e Android pronta em `docs/analise-xep0449-conformidade.md`; aguarda 3 decisões, sem código.

## O que entrou no build 135 (sobre o 134)

- **Canal leve, lacuna por sala (PR 98):** ao abrir o app depois de muito tempo no fundo, sem encerrar, a busca saía incompleta. A causa era uma sala fora do ar (ou uma consulta perdida num congelamento), que segurava a lacuna da conta inteira. Agora cada sala tem a sua própria lacuna, e uma sala com falha não segura as outras. Testado no `.dev` em 26/11: 26 salas em ~10 s, com a `conversejs.org` fora do ar. **Falta:** ver no TestFlight (conta xmpp.social.br) a próxima abertura depois de horas no fundo. Detalhes em `docs/analise-canal-leve.md`.

## O que entrou no build 134 (sobre o 133)

- **Sessão retomada com a descoberta pela metade:** depois do restart do Prosody (13.0.8), a conta `im.isacloud.cc` ficou sem `uploadServer` e as fotos falhavam com `service-unavailable` até desativar e reativar a conta. Agora o app principal abre sessão nova em vez de retomar uma sessão cujo disco não terminou (`isaCloudDropResumeIfDiscoIncomplete`). Testado: boot de 60 s nos dois simuladores e `.dev` no iPhone. O caso real só aparece no próximo restart do servidor; procurar no log "whose disco never finished".

## O que entrou no build 133 (sobre o 132)

- **C39 (PR 96):** SIGABRT quando o arquivo era retratado ou mudava de tipo durante o HEAD que busca tipo e tamanho. O assert virou aviso (`isaCloud C39`) e o retorno do HEAD relê a mensagem do banco. Testado: boot de 60 s nos dois simuladores e `.dev` no iPhone. A corrida é difícil de reproduzir; para forçar, mandar um arquivo e retratar logo em seguida.

## O que entrou no build 132 (sobre o 131)

- **Bolinha de atualização (PR 95):** bolinha rosa pulsante depois de "Conversas" enquanto alguma conta conecta ou faz o catchup, incluindo a busca dos canais leves. Testada nos simuladores; **falta** ver no iPhone ao abrir o app.
- **Canal leve, correções da primeira noite (PR 94 e servidor):**
  - **Servidor:** o `<markable/>` não acorda mais o aparelho, e o reload do `mod_csi_battery_saver` rearma o filtro nas sessões inativas. O arquivo já está no ar desde 25/11 11:49. **O rearme ainda não foi commitado** no `isacloud-custom-plugins`; o marcador está no `c981670`.
  - **App:** um despertar com a lacuna aberta não dispara mais uma segunda busca.
  - **Teste no `.dev`:** nenhum vazamento, nenhuma retomada recusada, uma busca só ao abrir.
  - **Falta:** a noite do 132 no TestFlight. Ao entrar numa sessão nova, a presença 110 limpa a lista de ocupantes; acompanhar.

## O que entrou no build 131 (sobre o 130)

- **Canal leve (fase A):** extensão `urn:xmpp:isacloud:muc-light:0`.
  - Com o app inativo, o servidor deixa de entregar as mensagens comuns dos canais leves.
  - Ao abrir, o app busca o intervalo no MAM de cada canal leve e reinsere as menções recebidas ao vivo depois das buscadas.
  - Interruptor "Canal leve" nos detalhes da sala; canal é leve por padrão.
  - Testado no `.dev`. **Falta a noite no TestFlight**, com a conta xmpp.social.br de volta no app.
  - Métrica `muc_light_deferred` em `https://isacloud.im/metrics`; no log, as linhas `isaCloud muc-light:`. Análise em `docs/analise-canal-leve.md`.
- **CSI ativo na abertura a frio:** antes, o app ficava inativo para o servidor durante todo o primeiro uso.
- **"Abrir isaCloud Meet":** No app ou No navegador (padrão). **Falta** confirmar no iPhone se o microfone continua com o Safari em segundo plano e o `window.close()` no `galene.js`.

## O que entrou no build 130 (sobre o 129)

- **Nota da conferência:** ao criar a sala, o app grava nas notas para mim mesmo, só no aparelho, a mensagem com o `hostURL` como recebida e não lida (`isaCloudAddLocalUnreadNote:toSelfChat:forAccount:`): conta nos selos, sobe ao topo, desarquiva; silenciada não conta; sem banner; nunca vai pelo XMPP nem para o log (`MLNotificationManager` confere `showAlert` antes de registrar o texto).
- **Aviso com "Ver":** depois de enviar o link ao convidado, aviso de 5 s acima da caixa de texto com "Ver" em rosa que abre as notas (`showNotice` com `actionTitle`/`action`); maior que os outros avisos, quebra linha e cresce para cima.

## O que entrou no build 129 (sobre o 128)

- **Brilho da original:** depois do toque na citação (ou de abrir pela busca), a linha da mensagem ganha uma faixa rosa por ~1 s que some aos poucos (`JumpHighlightBand` no `messageBuilder`), como no Android e no Web; não brilha na abertura pela primeira não lida.
- **Citação sem vínculo:** sem id da original (outro app sem XEP-0461, resposta antiga, citação à mão), a citação mostra ⓘ e o toque abre um balão (popover) preso a ela; a cápsula no topo ficava discreta demais. Fork: `isLinked` e `unlinkedHint` no `onQuoteTap` (PR 25, `99f3398`).

## O que entrou no build 128 (sobre o 127)

- **Reply XEP-0461, fase 1 (protocolo):** toda resposta com ID leva `<reply>` e, quando o corpo começa com a citação, `<fallback>` com o fim em pontos de código; `isacloud-quote` continua só para foto, GIF e figurinha; leitura com `<reply>` primeiro; disco anuncia `urn:xmpp:reply:0`; sem migration (coluna `isacloud_quote_id`). Conferido no Gajim e no log (as posições batem com o texto).
- **Reply XEP-0461, fase 2 (toque):** tocar na citação leva à original pelo pulo da busca, mas com a lista visível (esconder deixava a tela branca ~1 s); original ausente ou retratada mostra "Mensagem original indisponível".
- **Para o Android e o Web:** guia em `docs/guia-implementacao-replies-xep0461-android-web.md`. O Web (Converse 14) já tem XEP-0461, mas não manda o reply com OMEMO legado e não lê nem manda `isacloud-quote`.
- **Próximo:** fase 3 (notificação sem o trecho citado, em build separado; cartão para `<reply>` sem fallback) e, depois dos três apps, os fios (`docs/analise-fios-xep0201.md`).

## O que entrou no build 127 (sobre o 126)

- **C38** (`0xdead10cc` da extensão de notificação e "New Message?", 23/11/2026 07:47 e 08:08, build 126). Às 07:47 a conta do xmpp.social.br segurou a escrita no banco esperando a confirmação de uma escrita na rede, e no fim do prazo o `serviceExtensionTimeWillExpire` travou atrás da fila do UserNotifications (remoção de aviso de sync error). Às 08:08, com o app principal rodando, um segundo push chegou 5 ms antes do `_exit` e morreu sem resposta. Correções em `MLStream.m` (5 s na extensão), `HelperTools.m` (sem `updateSyncErrors` na extensão) e `NotificationService.m` (prazo de 1 s e `isaCloudScheduleKillAfterMainAppHandoff`). Implementado por executores e conferido; decisões em `docs/decisoes.md`, análise em `docs/analises-crashes.md` (C38).
- **No servidor (fora do app, 23/11):** `mod_cloud_notify_quiet` v3 no ar desde 12:29 UTC (sala de outro servidor só alerta com menção pelo apelido dos marcadores, intervalo mínimo de 2 min entre silenciosos, menção por palavra inteira com bordas estritas) e fpush com o aviso de reserva passivo, sem som, com `isaCloudPushPlaceholder` (imagem `isacloud/fpush:42359ca-isacloud3`, conferido no log às 13:04 UTC). Nenhum dos dois repositórios foi commitado.
- **A validar:** os itens do build 127 em "Testes pendentes" do roadmap; linha de base para comparar o efeito do v3: 114 execuções da extensão e 67 acordadas silenciosas em ~20 h (22–23/11).

## O que entrou no build 125 (sobre o 124)

- **C35** (`0xdead10cc`, build 122): o timer de 1 s das gravações adiadas (`isaCloudFlushPendingPersist`) passava pela checagem antes de pegar a trava de escrita e gravava com o app já desligando. Agora confere de novo dentro da transação. Não pôr essa guarda no `realPersistState` em geral: as gravações do desligamento precisam rodar.
- **C36** (`0xdead10cc`, build 124): no despertar por push, a escrita do último ack não completou (com Wi-Fi bom, pelo log do sistema) e segurou o desligamento, o congelamento e o `locks/MainApp` até a suspensão. Agora o `close` solta a escrita pendente (`IsaCloudWriteCondition` em `MLStream.m`), a espera depois do `force_cancel` tem 2 s de prazo e `WAKEUP_TIMEOUT` caiu de 20 s para 15 s.
- **A validar:** nenhum `0xdead10cc` novo desses tipos; no log, "isaCloud C35: … skipped after getting the write lock" e "isaCloud C36: stream closed while a write waited…". Detalhes em `docs/analises-crashes.md`.
- **Log do sistema do iPhone:** precisa do cabo USB (pela rede dá "Device not configured"); o `runningboardd` diz qual arquivo estava travado no `0xdead10cc`.

## O que entrou no build 124 (sobre o 123)

- **Ligação do isaCloud Web caía depois de atendida:** `<parameter value='111/111'/>` do `red` sem `name` derrubava a conversão Jingle → SDP (`rust/sdp-to-jingle`, `name` agora opcional). A Web vai parar de mandar sem `name`.
- **Ligação com o app fechado nunca tocava (bug herdado do Monal):** a extensão de notificação morria (`killAppex`) antes de chamar `reportNewIncomingVoIPPushPayload`; novo `disconnectAndFeedAllWaitingHandlersWithoutKilling` (`NotificationService.m`).
- **Armadilha de teste:** com um simulador ligado na mesma conta, ele recusa a chamada com `reject` `<busy/>` e a chamada cai em todos os aparelhos. **Desligar os simuladores ao testar ligações.**
- **Rust:** o xcframework (`rust/LibMonalRustSwiftBridge`, ignorado pelo Git) foi regerado só para iOS; copiar para outras worktrees. Ver `docs/decisoes.md`.
- **A validar:** ligação com o app fechado no TestFlight (a linha `Dispatching voip call to mainapp` da extensão).

## O que entrou no build 123 (sobre o 122)

- **Enquetes Fluux** (PR 86, roadmap 181): item "Enquete" no clipe (só em grupo ou canal com `occupant-id`), voto com um toque e "Encerrar enquete" no menu da mensagem (só o criador). Compatível com o Android e o Fluux (`urn:fluux:poll:0`). Migração 9 do banco (`isacloud_poll`, `isacloud_poll_closed`, `isacloud_poll_closed_at`). Docs: `docs/implementacao-enquetes-ios.md`, `docs/decisoes-enquetes-fluux.md`. **Falta:** teste cruzado com o Fluux e a fase 4 (roadmap 184).
- **Criar conferência pelo Galene** (fase 1, roadmap 182; mesclada direto na `isaCloud`, sem PR): item "Criar conferência" no clipe cria a sala em `meet.isacloud.cc` e põe o link no compositor; tocar no link abre o `hostURL` guardado no Keychain (anfitrião) ou a página pública. **Sem card na lista** (foi feito e retirado no mesmo dia; o histórico está no commit `ffb9c36d2`). Decisões em `docs/decisoes-conferencia-galene-ios.md`. **Falta:** encerrar/recuperar sala e Universal Link (roadmap 183).
- **Figurinhas só no atalho da caixa de texto:** o item "Figurinhas" saiu do menu do clipe.
- **Repositório limpo (21/11/2026):** só a `isaCloud`, a `develop` e a `medicao/c05-estado-da-conta` (worktree `isaCloud-iOS-medicao`, com alterações do C05 ainda sem commit). Branches `feature/video-conferencia` e `feature/enquetes-fluux` apagadas (a do remoto também).
- **A validar:** os testes do build 123 estão listados em "Testes pendentes" do roadmap. Os simuladores seguem no código do build 121 (outro agente os usava).

## O que entrou no build 122 (sobre o 121)

- **C34** (PR 85): a extensão de notificação foi morta com `0xdead10cc` em 20/11 21:18:29. Depois de entregar a notificação ela tem ~5 s, e gastava 1,5 s esperando um push atrasado; o `disconnectAll` da segunda conta não coube. A espera agora é de 0,5 s, e a linha `isaCloud C34: disconnectAll took N ms` mede o desligamento. **Validar:** nenhum `.ips` de `NotificationService` com `disconnectAll` na pilha.
- **No servidor (fora do app, 20/11):** `smacks_max_queue_size = 5000` e compactação de presença de sala no `mod_csi_battery_saver`. Na primeira noite houve 0 retomadas recusadas e as presenças caíram ~13 vezes (`docs/analise-trafego-canais.md`).
- **Primeira noite do 121:** sem `0xdead10cc` do app; a proteção do C33 pulou uma gravação com o app congelado às 07:18:39.

## O que entrou no build 121 (sobre o 120)

- **C33** (PR 84): crash `0xdead10cc` de 20/11 04:55 no build 120, com uma thread em `realPersistState` gravando o estado da conta com o app já congelado. O timer de 1 s do limitador de gravações (`isaCloudFlushPendingPersist`) não abre mais transação com `isaCloudShuttingDown`, `isaCloudSuspendedFast` ou `parseQueueFrozen`; o pendente fica marcado e a queda da conexão já grava tudo. Log: `isaCloud C33: deferred state save ... skipped`. **Só se prova em produção** (madrugadas com canais estrangeiros ativos). Análise em `docs/analises-crashes.md` (C33).
- **Log longo gravando de novo:** nos builds 118–120 os arquivos ficavam com 0 bytes (`unrecognized selector` em `shouldLockLogFile:`); agora com `MLLongLogFileManager`. No `.dev`: 1,1 MB em 3 min. **Falta ver a extensão (`appex`) gravando no TestFlight.** Com crash de madrugada, exportar o log longo de manhã cobre a noite toda (os 4 rawlogs cobrem menos de 2 h).

## O que entrou no build 120 (sobre o 119)

- **Espelhar selfies** (PR 83, roadmap 180): o iOS entrega a selfie sem o espelho do ajuste "Espelhar câmera frontal" (log do `.dev`: `EXIF orientation 6`) e não há API para ler o ajuste. Opção `mirrorFrontCameraPhotos` (Ajustes → Anexos, padrão ligado) espelha nos pixels a foto da frontal (`picker.cameraDevice == .front`) antes do envio; vale para o `CameraPicker` e para o caminho antigo do `chatViewController`. Vídeo não muda. Testado no `.dev`. Decisão em `docs/decisoes.md`.

## O que entrou no build 117 (sobre o 116)

- **Relatório de crash por XMPP** (PR 80, roadmap 177): aviso próprio ("Enviar" rosa, "Agora não" cinza); o relatório sobe cifrado (XEP-0363) com o nome `ios-b<build>-<AAAAMMDD>-<HHMMSS>Z.mcrash.gz` (UTC) e o link vai por OMEMO para `reports@isacloud.im`, com a lista de aparelhos buscada antes de cada envio. Sem conta, sem chave confiável, falha no upload ou 60 s sem resposta: Compartilhar. Fila `crash-outbox/` (5 relatórios, 7 dias). Depois do envio: convite ao Guia XMPP com o botão "Abrir o Guia XMPP" (`reports: ` na caixa, sem criar rascunho). Testado no `.dev`: relatório recebido com nome legível. `scripts/crash-report-renomear.py` e `--extrair` para analisar.
- **Em aberto:** reenvio silencioso da fila x aviso de novo (análise, 2.2 x 8.2); "enviado" não espera recibo do servidor; resposta automática no `mod_firewall` (2.3). No simulador o KSCrash só é instalado com o Registrador UDP ligado: o teste de ponta a ponta é no `.dev`.
- `docs/analises-crashes.md`: registro do C31.

## O que entrou no build 116 (sobre o 115)

- **Figurinha a partir de GIF** (PR 78, roadmap 175): interruptor "Figurinha" na tela de GIFs; ligado, o toque baixa a menor versão animada, guarda na biblioteca e envia como figurinha (`isSticker`, `image/gif`). A biblioteca guarda PNG e GIF (formato pelos bytes). Análise em `docs/feature-enviar-gif-figurinha.md`; guia do Android em `docs/figurinha-de-gif-android.md`.
- **Vídeo sem tela cinza no iOS 27** (PR 79 + PR 23 do fork, `80602dd`, roadmap 176): o visualizador do chat é o do fork do ExyteChat (`FullscreenMediaPages`/`VideoView`), não o `MediaViewer.swift`; um `AVPlayerViewController` dentro do `TabView(.page)` fica cinza no iOS 27 até um toque. Com um anexo só, o fork mostra o anexo sem o `TabView`. Decisão em `docs/decisoes.md`; mudança nº 24 em `docs/exytechat-fork.md`.
- `CHANGELOG-USERS.md`: o título da seção em andamento tem de ser `## Próximo build` (o gerador do `.dev` e do archive não aceita outro).

## O que entrou no build 110 (sobre o 109)

- Reparo de sessão OMEMO com limite: no máximo uma tentativa a cada 5 minutos por (jid, rid) em `MLOMEMO.m`. O reparo antecipado (antes do fim do catch-up) ficou de fora por falta de critério seguro. Análise em `docs/analise-omemo-invalid-message.md`; decisão em `docs/decisoes.md`. Validar com dois aparelhos.

## O que entrou no build 108 (sobre o 107)

- **Bolinhas de "digitando" na conversa 1:1** (PR 71, roadmap 172): balão com três bolinhas no canto inferior esquerdo enquanto o contato digita; a lista acompanha se a mensagem mais nova estava à vista. Aprovado no `.dev`.
- **Logo gordinho no splash e nas telas de conta** (PR 70, roadmap 173): `SplashLogo` em @1x/@2x/@3x sRGB; "Adicionar uma conta" e "Registrar" com o logo e textos mais curtos. Aprovado no `.dev`.
- **Atalho de figurinhas dentro da caixa de texto** (PR 72, roadmap 174): ícone rosa próprio (`StickerIcon`) à direita com o campo vazio, no lugar do X; o mesmo ícone no item do clipe. Aprovado no `.dev`, claro e escuro.

## O que entrou no build 107 (sobre o 106)

- **Lista de contatos abre sem animação** (PR 69, roadmap 171): `showContacts` apresenta com `animated:NO`; fechar continua animado. Aprovado no `.dev`.

## O que entrou no build 106 (sobre o 105)

- **Pedidos de contato repetidos** (PR 68): o pedido de volta de quem aceitou (`subscribe` com `subscription=to` ou `ask=subscribe`) é aceito sozinho em `xmpp.m`, sem notificação; descartar a notificação não recusa mais (antes apagava o contato do roster); Recusar usa `-[MLXMPPManager rejectContactRequest:]`. Selo "Aguardando aceite" em Contatos. Testado no `.dev`. **A validar em produção:** adicionar alguém entre `.dev` e produção e ver que não aparece pedido de volta. Lembrar que o servidor guarda pré-aprovação (`approved='true'`) e reentrega pedidos pendentes a cada login; limpar o roster no servidor antes de repetir o teste.

## O que entrou no build 105 (sobre o 104)

- **Convites de grupos e canais como solicitações pendentes** (PR 66, roadmap 168): o convite vira pendência em Contatos (Ingressar, Recusar, Recusar e Bloquear) e entra no selo do botão de contatos; opção "Mostrar convites de desconhecidos" em Privacidade, desligada por padrão. Testado no `.dev`. Junto, o **C22** (convidar para canal derrubava o app no iOS 27).
- **Novidades do isaCloud no topo da lista** (PR 67, roadmap 170): item no `tableHeaderView` com o que mudou desde a última abertura, tela em SwiftUI e linha em Configurações → Sobre. O JSON vem do `CHANGELOG-USERS.md` no archive. Aprovado no `.dev`. **A validar:** a primeira atualização real (104 → 105) mostra o item com o build 105 e o selo "Novo"; numa atualização com builds pulados, a prévia lista todos. Ver `docs/analise-novidades-na-lista.md`.

## O que entrou no build 104 (sobre o 103)

- **Sair do grupo/canal mantendo na lista** (PR 65): "Remover da lista" / "Manter na lista" / "Cancelar". Manter guarda o bookmark com `autojoin=false` e a linha na lista; um bookmark assim vindo de outro aparelho entra na lista sem join. Testado no `.dev`: sair de um canal arquivado mantendo na lista e ele continuar em Contatos/Canais. **A validar:** reingressar, "Remover da lista" de sala mantida, e o layout final dos selos no aparelho.
- **Contatos:** grupos e canais sempre visíveis, selos "Participante" / "Ingressar" / "Não participando" / "Arquivado" (cinza) à direita, endereço em uma linha, ordem estável entre contas.
- **Diferença conhecida com o Android:** o "Manter na lista" de lá ainda não grava `autojoin=false`, então uma saída mantendo na lista feita no Android não aparece no iOS.

## O que entrou no build 103 (sobre o 102)

- **GIF enviado na maior versão de até 2 MB** (roadmap 167, PR 64): antes ia sempre a maior (GIPHY `original` até ~10 MB, KLIPY `hd` até ~20 MB). A regra e as medidas estão em `docs/analise-gif-klipy.md`. As listas de "em alta" salvas passaram a `<provedor>-v2.json`. Testado no `.dev`; os testes de unidade novos não rodaram.
- **Docs novos, sem código:** resposta de verdade (XEP-0461) em `docs/analise-reply-xep0461.md`, `docs/contrato-reply-xep0461.md` (a regra do fio para iOS e Android) e `docs/decisoes-reply-real-android.md`; relatório de crash pelo XMPP para `reports@isacloud.im` em `docs/analise-relatorio-de-crash.md` (decidido, não implementado).

## O que entrou no build 102 (sobre o 101)

- **KLIPY e cache da busca de GIF** (PR 62, roadmap 166) já estavam neste build; ver `docs/analise-gif-klipy.md` e o guia do Android em `docs/analise-giphy-provider-android.md`.

- **C21:** sem sinal (elevador/garagem), a escrita do último ack esperava sem prazo e travava o `disconnectAll` da tarefa de segundo plano; o app era suspenso com a trava de processo (`0xdead10cc`). `-[MLOutputStream close]` cancela a conexão à força com escrita pendente, e a escrita tem prazo de 15 s. **A validar:** no `.dev`, modo avião e segundo plano logo depois; em produção, nenhum `0xdead10cc` com `disconnectAll` na pilha.
- **Registro do C20 mais cedo:** liga no `kMonalWillBeFreezed` e desliga em todo `signalResumption` (notificação `kIsaCloudFreezeEndedWithoutSuspension` quando não houve suspensão).
- **dSYMs guardados** por `scripts/archive-testflight.sh` em `~/Library/Developer/Xcode/Archives/isacloud-dsyms/build-N/`.
- **Pendente do C05 (mecanismo 1):** o estado da conta é serializado inteiro a cada stanza (176 KB, 260–345 ms numa conta no crash de 10/11 22:48). Decisão de 05/11 era só voltar a isso se os crashes voltassem; voltaram. Próximo passo: medir pelas linhas `slow realPersistState`.

## O que entrou no build 101 (sobre o 100)

- **Hotfix do C20:** o registro do build 100 symbolicava a pilha dentro de transações do banco e matou o app em segundo plano (`0xdead10cc`, 10/11 08:56, iPhone14,7). Agora grava só endereços de retorno e as bases do `monalxmpp` e do app (symbolicar com `atos -l`). `MLFiletransfer storeState` e `updateAccountAvatar` não tocam no banco com o app congelado e se refazem no `kMonalUnfrozen`. **A validar em produção:** sem novos `0xdead10cc` em segundo plano; linhas `isaCloud C20:` nos logs mostram outras fontes.

## O que entrou no build 100 (sobre o 99)

- **Arquivamento duradouro, como no Android** (PR 56, PR 1 do roadmap 134): `buddylist.archived` (migração 7 da escada do isaCloud); grupo/canal arquivado fica mudo e só volta pelo "Desarquivar"; arquivar não marca como lido nem desafixa. Junto, a **busca por nomes com a conta** de cada resultado. Falta o PR 2 (sincronização pelo PEP com o Android). `docs/decisoes-sincronizacao-arquivados.md`.
- **C16, quarta ocorrência** (PR 57): `NSStreamEventOpenCompleted` de uma conexão antiga não roda mais o login da nova (crash ao sair do modo avião).
- **Merge do Monal/develop, 24 commits** (PR 58): crash no catchup do MAM, regra nova de chave OMEMO (com aviso traduzido), arquivos do app Arquivos, backscroll do Monal, banco modelo 7.013. A migração do Snikket que veio junto fica desligada (`SNIKKET_MIGRATION` não definido; ver `docs/decisoes.md`).
- **Olho para esconder as conversas de uma conta** (PR 59, roadmap 165): só em memória; bolinha verde e alerta laranja menores.
- **C20, diagnóstico** (PR 60): todo acesso ao banco com o app congelado vira linha em `isacloud-db-after-freeze.log` e sai no log normal como `isaCloud C20:` ao voltar. **A validar em produção:** procurar `isaCloud C20:` nos próximos logs do iPhone; a limpeza automática não roda mais com o app congelado.

## O que entrou no build 99 (sobre o 98)

- **Compressão de vídeos da galeria e da câmera (480p) e limite do servidor** (PR 54, roadmap 161): MP4 H.264 + AAC 480p sem GPS; opção Original em Anexos. Limite de upload lido do servidor (`max-file-size` no formulário do disco; `isacloud.im` 200 MiB, `autozona.cc` 150 MiB) e guardado no estado da conexão. Aviso antes de anexar, tamanho real conferido antes de subir qualquer arquivo e recusa do servidor com a mensagem do limite. Sem duração fixa (a regra de 300 s saiu em 09/11/2026). A câmera para a gravação no tempo que cabe no limite. Compartilhar de outro app confere só o tamanho, sem converter. Anexos: seletores na linha de baixo do título; fotos "Sempre" por padrão em instalação nova. C18 corrigido. Testado no `.dev`. **Pendentes, não bloqueiam:** parada automática da câmera (~6 min 25 s no `isacloud.im`) e vídeo da galeria > 5 min dentro do limite (sem amostra). Atenção no merge com o Monal: `xmpp.m`, `MLIQProcessor.m`, `MLXMPPManager.m`, `MonalAppDelegate.m`, `SwiftuiHelpers.swift` (trechos `//isaCloud:`). Detalhes: `docs/analise-comprimir-videos.md`, `docs/decisoes.md`.
- **Tamanho do arquivo nas fotos, vídeos e áudios** (PR 55 + PR 22 do fork, roadmap 162): pílula no canto inferior esquerdo e "0:42 · 120 KB" no áudio; GIFs e figurinhas sem. `docs/analise-tamanho-de-midias.md`.
- **Reações do menu com os 6 últimos emojis usados** (PR 53, roadmap 163): `RecentReactions.swift`.
- **Observação:** `scripts/isacloud-dev-device.sh` sai com código 0 mesmo quando a compilação falha (não instala nada nesse caso); conferir no log se aparece "Installing".

## Em andamento (05/11/2026)

- Nada em aberto deste lote. Conferidos pela Isadora no iPhone em 05/11/2026: a linha "Lido até este ponto" (roadmap 153), compartilhar pelo contato sugerido (152), entrar num canal público escolhendo a conta (151), "Compartilhar…" de áudio e documento (120) e o aviso de falha de upload (141).

## O que entrou no build 98 (sobre o 97)

- **C19, contas congeladas ao abrir o app depois de uma noite** (produção, 07/11 07:37, build 96): o primeiro primeiro plano de um processo que já vivia em segundo plano e já tinha sido congelado era tratado como abertura a frio (só flags). Agora `SceneDelegate.sceneWillEnterForeground` só usa o atalho se `isaCloudWasFrozen` é falso; senão segue `applicationWillEnterForeground` (descongela e reconecta). **Validar em produção** (o `.dev` fica com as contas desligadas): deixar o app em segundo plano uma noite e abrir; o log deve mostrar `Entering FG` e `existing account, calling unfreeze` e as contas conectarem em poucos segundos. Análise em `docs/analises-crashes.md` (C19), decisão em `docs/decisoes.md`, como reconhecer no log em `docs/troubleshooting.md`.
- **Novo doc `docs/build-e-branches.md`:** branches, worktrees e problemas de build (Rust, `Package.resolved`, FTS5, Pods, assinatura). Ao criar uma worktree: copiar `Monal/Pods`, `rust/LibMonalRustSwiftBridge`, `rust/target` e a chave do Giphy do checkout principal.

## O que entrou no build 97 (sobre o 96)

- **Caixa de escrever com `UITextView`** (roadmap 160, `ChatTextInput.swift`): cresce até 6 linhas e depois rola, mantendo o cursor visível. Resolve o bug que estava em aberto no 96 (cursor uma linha acima e linha escondida). Testes de UI escritos (`ChatInputBaselineTests`), **não rodados** nos simuladores; falta confirmar no iPhone.
- **Encaminhar com a busca aberta** (PR 50, mesclado na `isaCloud`): marcar um contato tira o foco da busca e mantém o filtro, para o botão Encaminhar aparecer sem tocar no X. Testado no `.dev` pela Isadora.
- **OMEMO: contato pendente** (roadmap 159, commit `89dee4999`): sem alerta de chaves e com aviso antes do envio sem criptografia. Testado no `.dev`.
- Os textos novos têm tradução pt-BR no override do isaCloud.

## O que entrou no build 96 (sobre o 95)

- **C17** (watchdog `0x8BADF00D` em segundo plano no build 95, 05/11 22:20): o timer do wakeup não segura mais `@synchronized(self)` enquanto espera a principal, e reconfere o estado no lock antes de desligar e congelar (`MonalAppDelegate.m`, PR 47). **Validar em produção:** nenhum `0x8BADF00D` com `incomingWakeupWithCompletionHandler:` na pilha; no log, `Main queue did not run our block` seguido de `Handling wakeup completion` sem travar, e às vezes `state changed while preparing the shutdown`. O `.dev` não recebe push, então esse caminho só é exercitado no TestFlight.
- **Citação com miniatura** de foto, GIF e figurinha (roadmap 157, PR 46 + PR 21 do fork). Falta o Android (roadmap 158, `docs/citacao-com-miniatura-android.md`).
- **Em aberto:** o bug da caixa de escrever (cursor uma linha acima e a linha escondida pelo teclado, `ChatInputBar.swift`, `TextField(axis: .vertical).lineLimit(1...8)`): diagnosticado, plano de trocar por um `UITextView` aguardando a Isadora escolher o limite de linhas (6 ou manter 8).

## O que entrou no build 95 (sobre o 94)

- **C16, terceira ocorrência** (crash do build 92 no iPhone de um amigo, 05/11 10:38): o bloco do login com TLS (`_blockToCallOnTCPOpen`) e o desafio SASL2 ignoram o stream nunca aberto ou já fechado/em erro (`xmpp.m`, PR 45). A corrida não foi reproduzida. **Validar em produção:** nenhuma nova asserção `Stream must be open`. Detalhes em `docs/analises-crashes.md`.
- **Reconexão pela rede só em mudança real** (roadmap 156, `isaCloudPathSignature` em `MLXMPPManager.m`), e a pausa de 5 s saiu. Medido no `.dev`: abertura a frio de 0,7 s e 3,2 s (antes até 22 s e 31 s), e contas prontas em 0,55 a 2,3 s quando a rede volta. **A observar:** se a rede alternar de verdade várias vezes seguidas, cada troca reconecta (no teste não houve cascata). O log agora tem `nw_path update: … changed=… first=…` a cada aviso de rede.
- **"Limpar outros aparelhos OMEMO…"** na Depuração (roadmap 105).

## O que entrou no build 94 (sobre o 93)

- **Linha "Lido até este ponto"** (roadmap 153, PR 44): ao abrir um grupo ou canal na primeira não lida, uma linha cinza clara fica acima dela. O id fica num objeto (`ReadMarker`), porque o ExyteChat guarda o `messageBuilder` do primeiro desenho; com `@State` a linha não aparecia. O segundo scroll do salto deixa 220 pt de folga para a linha caber acima de uma foto (`.top` foi tentado e erra o alvo). **Para testar no simulador:** o app sincroniza a leitura com o servidor ao conectar e desfaz um `UPDATE ... SET unread=1` feito com o app fechado; fazer o `UPDATE` com o app já conectado e então abrir a sala. Doc: `docs/feature-marcacao-leitura.md`.

## O que entrou no build 93 (sobre o 92)

- **Canais públicos com várias contas** (roadmap 151, PR 42): a lista junta os canais de todas as contas prontas; com 2+ contas, a folha "Ingressar com…" oferece só as contas que ainda não estão no canal. Análise: `docs/analise-ingressar-canal-escolhendo-conta.md`.
- **Compartilhar pelo contato sugerido do iOS** (roadmap 152, PR 43): a extensão abre a lista filtrada pelo endereço sugerido, uma linha por conta, com a da sugestão marcada; "Mostrar todos" ou a busca voltam para a lista inteira. O simulador não mostra a fileira de sugestões: o teste foi com um contato injetado (código temporário, não commitado). Análise: `docs/analise-compartilhar-pela-sugestao.md`.

## O que entrou no build 92 (sobre o 91)

- **Medição do tempo de conexão por conta** (roadmap 149, `MLConnectTiming`): cada tentativa grava DNS, TCP, TLS, login, bind, catchup e ocioso em `<grupo>/Library/metrics/connects-AAAA-MM-DD.jsonl` (fila serial). Puxar do iPhone: `docs/troubleshooting.md`. Referência de 04/11: `isacloud.im` 0,3–2,6 s, `autozona.cc` 2,2–4,6 s (ejabberd mais lento no TLS e no login).
- **Abertura a frio sem os 12 s de espera** (C16 em `docs/analises-crashes.md`): a guarda do build 89 descartava também o stream "abrindo" e todo login antecipado esperava o prazo de login. Confirmado no iPhone (folha de compartilhar a frio também envia na primeira tentativa).
- **Reconexão na hora quando a rede volta** (`ISACLOUD_RECONNECT_UNBOUND_ON_NETWORK_CHANGE` + pausa `ISACLOUD_NETWORK_RECONNECT_COOLDOWN` de 5 s, `MLXMPPManager.m`): modo avião de ~15 s para 1,4–3,9 s, testado no iPhone às 20:34. A primeira versão sem pausa derrubava o login do `autozona.cc` a cada aviso de rede (um por segundo); a pausa resolveu.
- **Spinner só quando não conecta** (roadmap 150, `ISACLOUD_SYNC_INDICATOR_ONLY_WHEN_CONNECTING`): acende depois de 5 s com alguma conta sem bind, com o app em primeiro plano; rótulo "Conectando...". Testado sem rede no iPhone.
- **Rodapé da tela de abertura** "Copyright © 2026 isaCloud. Todos os direitos reservados.", preso à área segura.
- **A observar:** o caminho do primeiro plano depois de muito tempo dormindo ("Spinner que gira sem conectar", roadmap) ainda não tem a conferência de ~25 s (em 07/11/2026 apareceu a causa de um caso: C19, corrigido no build 98); se o spinner ficar aceso, colher o log e o `connects`. Aviso inofensivo `Could not invalidate already invalid timer` no `reinitLoginTimer`/`reconnect` (não investigado).

## O que entrou no build 89 (sobre o 88)

- **Visualizador de imagens só com o anexo tocado** (roadmap 146, PR 20 do fork, `docs/feature-visualizador-mostra-foto-unica.md`): sem contador nem miniaturas; X e compartilhar fixos nos cantos. Figurinha agora abre esse visualizador (roadmap 145); GIF continua reiniciando no toque. Aprovado pela Isadora no iPhone.
- **Aviso quando o envio de um arquivo falha** (roadmap 141): cápsula vermelha "Não foi possível enviar 😞 Tente de novo!" (antes o erro só ia para o log e a figurinha sumia sem "!"). "Enviando…" por contador. Visto no simulador com falha forçada; **falta uma falha real de upload no aparelho**. Opção B (balão durante o upload, roadmap 142) fica para depois.
- **Folha de figurinhas:** "Cancelar" à esquerda, "Criar" (carinha + texto) à direita; recorte continua sempre quadrado (o recorte livre foi feito e descartado no mesmo dia, roadmap 143).
- **Login não cai mais com a conexão falhando** (C16 em `docs/analises-crashes.md`): `handleFeaturesBeforeAuth:` ignora os recursos quando o stream não está aberto. O caminho da queda de rede não foi provocado; **só fica provado se o crash não voltar**.
- **Atualização de 04/11/2026 (tarde):** primeira não lida, salto e card de link **aprovados** pela Isadora. O C16 apareceu de novo no iPhone dela às 10:53 (build 88, `.ips` em `docs/analises-crashes.md`): o fix está no 89, ainda por instalar do TestFlight. Dados do roadmap 131 colhidos (um salvamento de estado por stanza, até 17/s; extremos = app congelado; sem `0xdead10cc` desde 02/11): análise em `docs/analise-salvamento-do-estado.md` (debounce descartado; próximo passo, se ela quiser: medir por parte do estado, etapa 1).
- **A observar:** `Device id` igual no app e na extensão (sem identidades OMEMO novas); primeira não lida e card de link seguem em avaliação.
- **Dica de teste:** a fototeca do simulador tem conversas reais; para testar editor de figurinha ou envio de foto use o `.dev` do iPhone ou limpe a fototeca antes.

## O que entrou no build 88 (sobre o 87)

- **Figurinhas** (roadmap 138): criar a partir de foto (recorte quadrado ou 4:3, remover fundo com o Vision, textos com contorno inclusive fora da foto), biblioteca local com favoritas, envio ao tocar, sem balão com 128 pt, "Salvar figurinha" com aviso passageiro; PNG 512 + marcador XEP-0449; migração 5 da escada do isaCloud. **Guia para o Android: `docs/ferramenta-de-figurinhas.md`.**
- **Extensão de compartilhar com o grupo de keychain do app** (roadmap 140): sem ele, cada compartilhamento trocava o "device id" e a migração **apagava as chaves OMEMO e o estado das contas** (também na produção); foi a causa do crash na abertura de 16:38 e das identidades OMEMO novas do dia. Conferido no `.dev`.
- **Deadlock do envio OMEMO** (roadmap 139): o envio criptografado agora abre a transação do banco antes da trava do Signal.
- **Download duplicado entre contas do mesmo aparelho** não marca mais "!"; **menu da mensagem em 0,4 s** no total; **"Reenviar" direto**; **"Enviando…" no compartilhar**; **busca do compartilhar fecha ao marcar**; notificação de reação em pt-BR.
- **A observar:** os contatos viram dispositivos OMEMO novos de hoje (as identidades apagadas); a primeira não lida e a altura fixa do card de link seguem em avaliação.

## O que entrou no build 87 (sobre o 86) — em avaliação por alguns dias a partir de 03/11/2026

- **Grupos e canais abrem na primeira não lida** (roadmap 136, `docs/feature-abrir-na-primeira-nao-lida.md`): limite de 200, a busca vence, MDS respeitado; salto de ~0,9 s (antes ~1,7 s; 3,4 s com link), dica "Carregando…" só depois de 1,2 s ou com busca no banco.
- **Card de link com altura fixa de 120 pt** (roadmap 137, PR 19 do fork) e "Pré-visualização indisponível" quando falha; o app **não chama mais** o prefetch de previews (fica no fork).
- **Campo de texto** com no máximo 8 linhas inteiras (`.lineLimit(1...8)`).
- **Se incomodar:** ancorar a posição do alvo no fork, ou religar o prefetch com prazo de 0,5 s; se aprovar, remover `LinkPreviewPrefetcher` do fork.
- Cache em disco dos previews: avaliado e descartado (`docs/feature-abrir-na-primeira-nao-lida.md`). Marcas `//TEMP-MEDIÇÃO` de tempo foram removidas antes do commit.

## O que entrou no build 85 (sobre o 84)

- **Estabilidade do `0xdead10cc`** (roadmap 128, 130, 131; PRs 33 e 35): a thread de timeouts só abre transação quando há iq handlers/idle timers e pula contas congeladas; o disconnect faz a parte de rede fora da transação, com prazo de 2 s por espera; o log passa a registrar salvamentos de estado acima de 50 ms (`isaCloud: slow realPersistState`, `slow persistState serialization`). Script novo `scripts/classificar-crashes.py` (receita em `docs/troubleshooting.md`).
- **Mensagem de grupo entregue não vira "!"/"Reenviar" por erro tardio** (roadmap 129, PR 34, outra sessão). O caso de reconexão não foi reproduzido de ponta a ponta; **validar no iPhone**.
- **Para validar com dados do 85:** `0xdead10cc` por dia (rodar o script no iPhone), "New Message?" e `EXTENSION_CHECK_IN_TIMEOUT` (fix do 84), linhas "slow ..." e "did not finish within ... while disconnecting" nos logs de produção.

## O que entrou no build 86 (sobre o 85)

- **Botão "Câmera" no clipe** (PR 36, roadmap 132): foto ou vídeo direto da câmera como anexo, sem salvar na galeria. Testado no iPhone pela Isadora; o simulador não tem câmera e o item não aparece lá. Análise em `docs/feature-enviar-midia-da-camera.md`. Textos novos em pt-BR: "Camera", "Camera permissions missing", "Monal is not allowed to access the camera", "Settings" (esta última vale para todo "Settings" do app).

## O que entrou no build 82 (sobre o 81)

- **Menu da mensagem em ~250 ms** (PR 25 do app, PR 15 do fork): o toque longo do SwiftUI ignorava a duração e disparava em ~600 ms; agora é um `UILongPressGestureRecognizer` de 0,15 s na tabela do ExyteChat + animação de 0,1 s + vibração preparada no toque. **Confirmado pela Isadora no iPhone, GIF incluído.** Detalhes em `decisoes.md` ("Menu da mensagem em 250 ms") e `exytechat-fork.md` (mudança nº 3).
- **"Salvar Imagem" e "Salvar Vídeo" na folha de compartilhar do chat** (PR 14 do fork): a extensão do arquivo compartilhado era o mime type em hexadecimal. Testado no simulador iOS 18.6; **falta** vídeo, iOS 27 e conferir no iPhone; o `MediaViewer.swift` (Mídia Compartilhada) não foi verificado.

## O que entrou no build 84 (sobre o 83)

- **Extensão de notificação não trava mais na inicialização** (PR 32 do app; roadmap 127): o `MLUDPLogger flushWithTimeout:` esperava sem prazo e a extensão foi morta pelo iOS por "extension check-in timeout" (o "New Message?" das 15:54, build 81). Agora o sinal fica numa flag e a espera tem prazo. **Causa provável, sem pilha; validar no TestFlight** contando "New Message?" e mortes por check-in timeout (receita em `docs/troubleshooting.md`, "Notificação fantasma"). As notificações **vazias** continuam: são o placeholder esperado sem push filtering.
- **Ainda sem causa:** as vazias de 12:13 e 12:48 de 02/11 (saíram da janela de log do iPhone). Para o próximo caso: anotar o minuto e rodar `sudo log collect --device-udid <UDID> --last 12h` logo depois.

## O que entrou no build 83 (sobre o 82)

- **Visualizador de imagens não abre mais depois do menu** (defeito do build 82; PR 16 do fork e 26 do app; roadmap 123). Confirmado pela Isadora no iPhone; falta conferir vídeo e replay do GIF.
- **Toque longo só no balão e link ignorado com o menu aberto** (PR 17 do fork, 28 do app; roadmap 124 e 125). Confirmado pela Isadora no iPhone; falta conferir o avatar e a hora sozinha no iOS 27.
- **`0xdead10cc` do build 81, log síncrono com limite de espera** (PR 27 do app; roadmap 106). **Ainda não validado no aparelho:** contar os `0xdead10cc` por dia e procurar "Main queue did not run our block".
- **Cor do balão e do texto das minhas mensagens** (PR 29 do app, PR 18 do fork; roadmap 119). **Falta** testar no iPhone com cor personalizada: seta de responder, enviar, editar e gravar.
- **"Compartilhar…" no menu das mídias** (PR 31; roadmap 120). Testado em foto, GIF e vídeo nos simuladores; **falta** áudio, documento e o iPhone.
- **Crash ao compartilhar um link para o isaCloud** (build 81, iOS 27.2): corrigido (PR 30; roadmap 126). Testado no XR; no iOS 27 o share sheet do Safari do simulador não abriu.
- **Depois do envio:** notificação "New Message?" das 15:54 = extensão morta por check-in timeout na inicialização; corrigido no código (`MLUDPLogger flushWithTimeout` com flag e prazo, roadmap 127, **para o build 84**, validar no aparelho). O crash do e-mail (`CrashReport-1.mcrash-7`) é o mesmo "duplicate ids" das 15:21, já corrigido no 83.
- **Próximas frentes:** validar o `0xdead10cc` com o build 83 e a camada 2 (presenças de canal em lote, roadmap 106).

## O que entrou no build 81 (sobre o 80)

Tema: **`0xdead10cc` em segundo plano** (PR 24; causa, correção, limites e **pontos sensíveis de merge com o Monal** em `decisoes.md`, seção "Expiração das tarefas de segundo plano..."; roadmap 106).
- **Camada 1:** o `expirationHandler` do BGRefresh/BGProcessing e o timer de wakeup esperam a thread principal no máximo 1 s (`MonalAppDelegate runOnMainQueue:withTimeout:`) e, se ela não responder, congelam as contas na própria thread. Achado no log do iPhone: uma acordada de ~30 s com centenas de presenças de canais MUC (um canal movimentado respondeu por mais da metade) deixava a thread principal saturada e o congelamento nunca rodava.
- **Extensão de notificação** sai com flush manual, `[MLProcessLock unlock]` e `_exit(0)` (5 mortes `0xdead10cc` dela em 31/10 e 01/11 estavam presas dentro do `exit()`).
- **Aviso "isaCloud" vazio** também removido nas acordadas em segundo plano.
- **Falta validar no aparelho (nada disso foi testado em execução):** contar `0xdead10cc` por dia nos crash logs do iPhone (base: 1 a 3 por dia desde 28/10; no app e, separado, na `NotificationService`) e procurar no log "Main queue did not run our block" seguido de "Posting kMonalWillBeFreezed" em 1 a 2 s. Comandos: `docs/troubleshooting.md` e a memória `ler-log-de-producao-do-iphone`.
- **`0xdead10cc` do logger (caso do build 81, 13:48:11): corrigido em código, falta commit/PR e ver no aparelho.** Branch `fix/log-sincrono-na-suspensao` (`HelperTools.m`, log síncrono com espera de no máximo 250 ms; roadmap 106 e `decisoes.md`, "Log síncrono com limite de espera"). Está no `.dev` do iPhone; **não** está no TestFlight. Falta medir os `0xdead10cc` por dia depois do build 83.
- **Próximos passos:** (1) camada 2: gravar as presenças de canal em lote (um `persistState` e uma atualização de tela por lote; arquivos `xmpp.m`/`MLMucProcessor.m` do Monal, validar antes); (2) o aviso cru **"New Message?"** (texto original do push quando a extensão não entrega o conteúdo): falta o horário de um caso para achar o push no log do iPhone; a nossa limpeza nunca o remove; (3) propor `_exit` e o fallback de expiração ao Monal.

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

8. **Backup de simulador sempre em pasta nova** (04/11/2026): um executor escolheu a pasta com `ls -d ... | tail -1` e sobrescreveu dois backups antigos (`7AA8D91B-...-72b-1705` e `346E97D1-...-diag-1924`, que agora têm o banco de 04/11). Criar `<udid>-<data>-<HHMM>-<assunto>/` com `mkdir` sem `-p` e conferir com `ls -la`.
9. **Avisos de rede chegam em rajada** (04/11/2026): ao sair do modo avião o iOS manda ~1 "still reachable" por segundo por uns 10 s. Qualquer reação a esse aviso precisa de pausa, senão um login lento nunca termina.
10. **Módulo do servidor: conferir o arquivo antes do reload** (25/11/2026): o servidor rodou código velho duas vezes (faltou o reload; depois faltou o arquivo). Conferir `wc -l` e `sha256sum` do arquivo em `/var/lib/prosody/custom_plugins/...` contra o do repo antes de `prosodyctl reload`/`module:reload`, e procurar no log a linha nova (`filter re-armed on N inactive session(s) at load`).

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
scripts/isacloud-dev-device.sh <TEAM_ID> <UDID_DO_IPHONE>

# arquivo de produção (Release/AppStore)
cd Monal && xcodebuild archive -workspace Monal.xcworkspace -scheme Monal \
  -sdk iphoneos -configuration AppStore \
  -archivePath "$(pwd)/../build/isaCloud-AppStore.xcarchive" \
  -derivedDataPath /tmp/ddarch -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> ISACLOUD_BUNDLE_ID=br.com.isacloud.messenger \
  ISACLOUD_ENTITLEMENTS_DIR= \
  GIPHY_API_KEY="$(tr -d '[:space:]' < ../isaCloud/local/giphy-api-key.txt)"

# capturar a tela do iPhone / puxar métricas e logs
xcrun devicectl device capture screenshot --device <udid> --destination /tmp/tela.jpg
xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer \
  --domain-identifier group.br.com.isacloud.messenger.dev --source "Library/metrics" \
  --destination /tmp/metrics
```

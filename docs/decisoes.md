# Decisões de projeto e pendências em aberto

Registro do **porquê** das escolhas feitas no fork, para quem abrir uma sessão nova (ou outra pessoa) não precisar redescobrir. O que está pronto e a data ficam no `CHANGELOG.md` e no `ROADMAP.md`; aqui ficam as razões e o que ainda falta conferir. Dados sensíveis ficam em `isaCloud/local/NOTAS-LOCAIS.md`, nunca aqui.

## Decisões

### Fork do ExyteChat (25/10/2026)
- **Decisão:** o chat usa o fork `isaitgirl/ExyteChat`, branch `isaCloud` (cadeia: `exyte/Chat` → `monal-im/ExyteChat` → nosso). Rotina de atualização e o que o fork muda: `docs/exytechat-fork.md`.
- **Por quê:** o balão é desenhado pela biblioteca (`Text` de `AttributedString`), sem ponto de extensão. Dois ajustes pediam mudar o balão por dentro: ícones de status maiores (de 10 para 16 pt, na base do balão) e citação com uma barra vertical contínua em vez de um `│` por linha.
- **Alternativas descartadas:** (a) trocar `│` por caractere de bloco (testado: barras grossas e ainda segmentadas); (b) balão próprio via `messageBuilder` para toda mensagem com citação (1 a 2 dias e risco de regressão: reproduzir avatar, nome, hora, status, reações, links, menu e swipe); (c) esperar a XEP-0461 do Monal (sem previsão).
- **Regras:** mudanças pequenas, comentadas com "isaCloud:" e em commits separados, para o rebase ser fácil. Se o upstream trouxer o recurso, descartar o nosso commit.

### Visibilidade da foto da conta (25/10/2026)
- **O que é:** chave "Foto Visível para Todos" em Editar Conta. Desligada (padrão) = só contatos (PEP `pubsub#access_model` = `presence`); ligada = qualquer pessoa (`open`), como no Conversations.
- **Onde vale:** só nos nós de avatar (`urn:xmpp:avatar:data` e `urn:xmpp:avatar:metadata`). O nick (nome de exibição, `http://jabber.org/protocol/nick`) continua em `presence`, por decisão da Isadora.
- **Sem aviso ao ligar**, por decisão da Isadora (a primeira ideia era um alerta de privacidade).
- **Como funciona no código:** `xmpp.m` (`avatarAccessModel`, `applyAvatarVisibility`, `publishAvatar:`), `MLPubSubProcessor.m` (`avatarDataPublished`) e `XMPPEdit.m` (linha com `SettingsAvatarPublicRow`, tag 4). Mudar só a chave reconfigura os dois nós com `configureNode:` sem republicar a imagem; se também houve troca de foto, publica com o modelo novo.
- **Onde fica a escolha:** nos ajustes do app (`avatarPublic.<accountID>`, grupo compartilhado), **por aparelho**. Com a mesma conta em dois aparelhos, quem publicar um avatar por último aplica a escolha do seu aparelho. Limitação aceita por ora.
- **Por que importa:** só quem escolhe ser público pode ter o avatar visto por quem não é contato (grupos e canais). Ver "Avatares de quem não é contato" no roadmap.
- **Falta conferir:** a mudança no servidor (ver pendências).

### Avatar nas presenças e visibilidade da foto (26/10/2026)
- **Avatar:** o servidor (`mod_vcard_legacy`) injeta o hash (XEP-0153) em toda presença que sai da conta e responde o `vcard-temp` dos ocupantes, então o app não manda `<photo>` nem responde vCard (conferido: o app não envia `x:update`). Faltava só **mandar uma presença nova** depois de publicar ou apagar o avatar, porque as salas só veem o hash em presença nova. `avatarMetadataPublished` e `avatarDeleted` (`MLPubSubProcessor.m`) agora chamam `sendPresence` e `sendPresenceToJoinedMucs` (`MLMucProcessor.m`). Conferido pela Isadora: o avatar apareceu para um usuário que não tinha a conta no roster.
- **Visibilidade vem do servidor:** ao abrir Editar Conta o app lê o `pubsub#access_model` do nó `urn:xmpp:avatar:metadata` (`fetchAvatarVisibilityWithCompletion:`, `xmpp.m`) e a chave mostra isso, em vez do valor guardado no aparelho (que vira só uma cópia). Ao salvar uma mudança de visibilidade o app republica a foto que já tem localmente (`hasIconForContact`), o que também cria os nós se não existirem e reenvia a presença; sem foto local, só reconfigura os nós.
- **Nick por sala: tentado e revertido (26/10/2026).** Tentamos trocar o nick em todas as salas ao mudar o nome de exibição. Funcionou no servidor (presença para `sala/novo-nick`, 303, hash da foto certo), mas deu regressão em cadeia e foi desfeito. Lições para quando voltar: (1) no Prosody o ocupante é por JID completo: cada aparelho tem o seu nick na mesma sala e só se alinham pelo bookmark; (2) o bookmark do Monal é buscado, alterado e publicado de volta (`handleBookmarks2FetchResult`), e uma atualização por sala faz buscas seguidas que republicam o nick antigo por cima do novo, e todos os aparelhos voltam; (3) esse código só grava o nick do banco no bookmark quando `autojoin` é falso; (4) o `MLMucProcessor` só deve ser chamado pela fila de recepção da conta (chamar da UI travou o app); (5) uma só atualização de bookmarks depois da última resposta, tratamento do 303 e dos erros 409/406, testar com **um** aparelho conectado primeiro. Ver o item 9 do roadmap.
- **Travamento do .dev no iPhone (Debug):** o relatório mostrou a thread principal presa na fila de log, ocupada com `DumpMemoryGraph` (`MLDelayedDealloc.m`, só em build Debug), e depois a asserção "Spurious idle timer firing!" em `handleJoinTimeout`. Não foi alterado: o TestFlight (Release) não tem o despejo. Se voltar a atrapalhar os testes no iPhone, validar com a Isadora antes de mexer nesses arquivos do Monal.

### Balão dos GIFs é do app (23 a 26/10/2026)
- O ExyteChat mostra GIF como imagem parada; o app desenha o GIF animado em `GifMessageBubble` (`GifPickerView.swift`), via `messageBuilder`. Efeito colateral: o balão padrão (avatar, horário, status, reações, menu) some. Reproduzimos essas partes no `GifMessageBubble`; **se o balão padrão ganhar algo novo, lembrar de conferir os GIFs**.

### Ícones de status das mensagens
- Convenções (relógio, círculo vazado cinza, rosa, cheio, exclamação) e cores: tabela no `CHANGELOG.md` (build 13). O estado "servidor recebeu" é desenhado no app (`IsaCloudStatusIcons`, `GifPickerView.swift`) porque a imagem do ExyteChat para esse estado é vazia.

### iOS 27 e iOS 18 (24 e 25/10/2026)
- Builds e testes sempre do iOS 18 ao 27, no simulador de cada versão (um app compilado para o iOS 27 não abre no 18: falta `libswiftCompatibilitySpan`).
- iOS 27: o app usa o ciclo de vida por cenas (`SceneDelegate` repassa os eventos); o vigia de travamento do KSCrash fica desligado; o aviso de "primeiro plano" na abertura não espera filas (`nowForegroundedAtLaunch`). Detalhes e como investigar: `docs/troubleshooting.md`.
- Seletor de fotos do chat: o do sistema (`PHPicker`), porque o do ExyteMediaPicker não rola no iOS 27.
- Seletores (chaves) das telas de ajustes: margem direita de 26 pt em `MLSwitchCell.xib` (no iOS 27 o conteúdo da célula passa da borda visível; 26 pt ficou bom nos dois sistemas). É uma mudança de uma linha num xib do Monal: pode conflitar em merge.

### Convenções gerais
- Código em inglês, seguindo o Monal; textos para a pessoa em pt-BR pelo mecanismo de tradução (`isaCloud/localization`, regra em `docs/traducoes.md`). Mudanças que compliquem o merge com o Monal precisam ser validadas antes.
- Commits: só quando a Isadora pedir, com mensagem bem descritiva.

## Pendências e por quê

| Pendência | Por quê / o que falta |
|---|---|
| **Atraso de ~1 s ao enviar texto** | Intermitente. O caminho de envio medido leva 35 a 100 ms na thread principal; suspeita: fila de atualização do ExyteChat ou resolução de chaves OMEMO em grupos privados. Há código **temporário** de medição (marcado `TEMPORARY`, em `ChatView.swift`, `xmpp.m`, `HelperTools.h/.m`, `MLXMPPManager.m`, `SwiftuiHelpers.swift`) que grava `Documents/send-timing.log` no aparelho. Quando a Isadora relatar uma ocorrência: puxar o arquivo (`docs/troubleshooting.md`, seção 3), analisar e **depois remover o código temporário**. Ele está nos builds 13, 14 e 15 e **não entra em commit**: ao commitar, tirar as marcas `TEMPORARY` (ChatView, SwiftuiHelpers, MLXMPPManager, HelperTools.h/.m, xmpp.m) numa cópia, conferir que compila e depois devolver o código ao disco (feito no commit do build 15). |
| **Visibilidade da foto: conferir no servidor** | Testado só até a gravação da escolha e a linha na tela. Falta: com uma conta que não seja contato, ver o avatar com a chave ligada e sumir com ela desligada (e conferir o `access_model` dos nós). |
| **GIF recebido: avatar ao lado** | Conferi horário, status, reação e menu num GIF enviado (simulador iOS 18). O avatar de GIF recebido segue o mesmo código de antes, mas não foi revisto depois da mudança; olhar numa conversa 1:1 e num grupo. |
| **Margem direita dos campos de texto** | "Nome de Exibição", "Mensagem de Status" e o ID XMPP encostam na borda direita da tela de edição de conta (visto no iOS 27). Só os seletores foram ajustados. |
| **Liberar o build 15 aos testadores internos** | O archive do build 15 está pronto, mas o envio ao App Store Connect falhou por falta de acesso da conta K8Y6S5RF2S no Xcode (Settings → Accounts). Depois de entrar, rodar só o passo 3 de `docs/publicacao-testflight.md`; depois liberar o grupo interno. |
| **Push filtering** | Entitlement removida (a Apple só libera mediante pedido); pedido enviado em 24/10/2026 (número em `isaCloud/local/NOTAS-LOCAIS.md`). Sem ela, todo push vira notificação visível ("New Message / New Message?"). Quando aprovada: ativar a capacidade nos App IDs e recolocar a chave nos dois `.entitlements` (ver `CLAUDE.md`). Se a Apple negar, ver o item de notificações fantasmas no roadmap. |
| **Avatares de quem não é contato em grupos e canais** | Depende de buscar o avatar público (PEP) sob demanda; só funciona para quem escolheu ser público (ver acima). Esforço médio, no roadmap ("Por avaliar"). |
| **Apelido por grupo e canal; menção XEP-0372; XEP-0461 (responder deslizando)** | No roadmap, com o plano de cada um. |

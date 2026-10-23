# Roadmap do isaCloud para iOS

Funcionalidades a implementar no fork. A primeira linha é a próxima a ser feita; as demais seguem a ordem de esforço (do menor para o maior). A referência de paridade é o Conversations (Android).

A avaliação original foi feita sobre o Monal 6.x (19/10/2026) e revisada em 23/10/2026 sobre a `develop` (Monal 7), base atual do fork: nenhum destes itens existe na `develop`. As reações (XEP-0444), que eram o item mais trabalhoso, saíram da lista porque já existem na `develop`.

| # | Funcionalidade | Esforço | Observações |
|---|---|---|---|
| 1 | **Busca de canais (próximo)** | médio, cerca de 17 a 27 h de trabalho focado (3 a 4 dias úteis) | Tela com os canais públicos do servidor do usuário, via `disco#items` no serviço de MUC. Paginada por RSM (XEP-0059): 50 por vez, com botão "Carregar mais". Ordenada alfabeticamente no app, que percorre todas as páginas no início e guarda só JID e nome (o nome já vem no `disco#items`). Cada linha mostra a contagem de membros (`disco#info`, consulta leve) e o avatar do canal (`vcard-temp`, sob demanda, com cache no `MLImageManager`; enquanto não chega, aparecem as iniciais coloridas). Botão "Entrar" reaproveita o fluxo de adicionar canal (entra nos bookmarks e nas conversas). Só salas públicas aparecem (no isaCloud, `muc_room_default_public = false`). |
| 2 | GIF pelo teclado | baixo | Aceitar GIF colado no campo de mensagem preservando a animação; o envio de GIF por HTTP Upload já existe. Rever na tela de chat nova (`ChatView.swift`, ExyteChat). |
| 3 | XEP-0317 (Hats) | baixo a médio | Ler e exibir os hats dos participantes das salas (o isaCloud usa "Verificado 🛡️" e "Deusa do Olimpo"). Só leitura, como no Conversations. |
| 4 | Responder deslizando para a direita (XEP-0461) | médio | O gesto e o botão "Responder" já existem na `ChatView.swift` da `develop`, mas comentados pelo time do Monal; a biblioteca de chat já mostra a citação (`replyMode: .quote`). Falta o protocolo: enviar `<reply>` (com `stanza-id` em grupos e o ID da mensagem em 1:1) e a citação de fallback (XEP-0428), receber e retirar o fallback, guardar a ligação no banco (migração) e exibir no balão e nas notificações. **OMEMO:** a citação vai cifrada, mas a referência `<reply>` vai fora da parte cifrada, como no Conversations. **Conflito com o Monal:** como o gesto está pronto e comentado, eles provavelmente estão trabalhando nisso; antes de começar, verificar no repositório/issues ou na sala `monal@chat.yax.im` para não conflitar nas próximas atualizações. |
| 5 | XEP-0393 (Message Styling) | médio | Negrito, itálico, código e citação nas mensagens: interpretação e renderização no cliente. |
| 6 | @ com autocompletar em grupos | médio | Sugerir participantes da sala ao digitar `@` e marcar a menção; definir o formato no XML (provável XEP-0372). |
| 7 | Código de afiliado | médio, com servidor | Tela "Tenho um código" com escolha de servidor, aceitando um token curto e reutilizável; depende de o `mod_invites` do Prosody gerar esse tipo de token. |

## Por avaliar

Funcionalidades que ainda não entraram na fila: decidir se valem a pena antes de priorizar.

| Funcionalidade | Esforço | Observações |
|---|---|---|
| XEP-0455 (Service Outage Status) | baixo | Ler o aviso de manutenção anunciado pelo servidor e exibir ao usuário. |
| Avatares de quem não é contato em grupos e canais | médio a médio-alto | Grupos: buscar sob demanda o avatar público (PEP) pelo JID real. Canais: ler o hash de avatar da presença (XEP-0398) e buscar pela sala; o código do Monal para isso está comentado (possível trabalho em andamento). |
| OMEMO: buscar a lista de aparelhos antes de marcar todos como removidos | baixo a médio | Ao receber de outra pessoa um aviso de lista vazia (`retract`/`purge`/`delete` ou `publish` sem aparelhos), o app hoje marca todos os aparelhos dela como removidos (`devicelistHandler` em `MLOMEMO.m`); com quem não é contato, ele não recebe a lista corrigida depois e fica "sem dispositivos com criptografia" até alguém redefinir a sessão. Buscar a lista de novo e só marcar se continuar vazia. Código central do OMEMO: testar com cuidado. Visto em 23/10/2026 com `isadora@im.isacloud.cc` no grupo Avatares. |
| Ajustes visuais do chat | baixo | Botão do microfone ainda azul (deveria ser rosa) e "Type a message…" sem tradução. |

## Feito

- **Histórico ao conectar em canais públicos** (23/10/2026): ao entrar, o catchup MAM dos canais baixa só os últimos 7 dias (padrão), podendo ser trocado nos detalhes do canal para 1 mês ou "Tudo" (sem limite, sob responsabilidade de quem escolhe). Grupos privados não mudam. Migração de banco 7.014 (`buddylist.mam_catchup_days`).
- **"Redefinir sessão OMEMO" sempre visível** (23/10/2026) nos detalhes de contatos e membros de grupos privados, sem precisar da interface avançada; tradução pt-BR da opção de interface avançada e da confirmação.
- **Avatares com iniciais coloridas** (23/10/2026): quem não tem avatar aparece com 1 ou 2 letras ("Isadora Ribeiro" → IR) sobre a cor do XEP-0392; nos canais, a cor vem de `sala/apelido` (antes eram letras sobre fundo branco).
- **XEP-0202 (Entity Time)** (23/10/2026): o app responde à consulta de hora local (`urn:xmpp:time`) de contatos com assinatura de presença, da própria conta e do servidor, e anuncia o recurso no disco; nos detalhes do contato, mostra "Horário local" abaixo de "Visto por último" quando um aparelho do contato responde. Teste em `MonalXMPPUnitTests/HelperToolsTest.swift`; exibição conferida no iPhone com o Conversations.
- Identidade própria (Bundle ID `br.com.isacloud.messenger`, App Group, keychain), marca, cores, ícone e traduções próprias.
- Primeira abertura direto em Boas-vindas; registro com os servidores do isaCloud e mensagens de erro amigáveis.
- Push apontando para `push.isacloud.im` (fpush, ver `docs/fpush/`) e STUN de reserva `stun.isacloud.im`.

## Testes pendentes

- **Limite de 7 dias no histórico de canais públicos** (anotado em 23/10/2026). A janela já está implementada (padrão 7 dias, 1 mês ou "Tudo" nos detalhes do canal), mas falta medir o efeito num canal com arquivo MAM grande:
  - **Prosody** (`prosody@conference.prosody.im`): não serve. O arquivo começa em 17/10 (48 mensagens no total), então a janela de 7 dias não corta nada.
  - **Conversations** (`conversations@conference.siacs.eu`): anuncia MAM. A primeira página da janela voltou com `complete='false'` e não consegui terminar a paginação. Falta: (1) contar as mensagens da janela até `complete='true'`; (2) repetir com "Tudo" e comparar o total.
  - Pré-requisito: entrar de novo no canal, gravar um stanza ID inexistente em `buddylist.lastMucStanzaId` e forçar sessão nova (Ajustes → Debug → Extra Settings → "Reset the state of all accounts").
  - Antes do teste, vale o log contar as páginas de MAM, para saber quando a paginação termina.

## Pendências fora do código

Ver a seção "Pendências" do `CLAUDE.md` (por exemplo, reativar o push filtering quando a Apple liberar).

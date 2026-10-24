# Roadmap do isaCloud para iOS

Funcionalidades a implementar no fork. A primeira linha é a próxima a ser feita; as demais seguem a ordem de esforço (do menor para o maior). A referência de paridade é o Conversations (Android).

A avaliação original foi feita sobre o Monal 6.x (19/10/2026) e revisada em 23/10/2026 sobre a `develop` (Monal 7), base atual do fork: nenhum destes itens existe na `develop`. As reações (XEP-0444), que eram o item mais trabalhoso, saíram da lista porque já existem na `develop`.

| # | Funcionalidade | Esforço | Observações |
|---|---|---|---|
| 1 | ~~Busca de canais~~ **feito em 23/10/2026** | médio, cerca de 17 a 27 h de trabalho focado (3 a 4 dias úteis) | Tela com os canais públicos do servidor do usuário, via `disco#items` no serviço de MUC. Paginada por RSM (XEP-0059): 50 por vez, com botão "Carregar mais". Ordenada alfabeticamente no app, que percorre todas as páginas no início e guarda só JID e nome (o nome já vem no `disco#items`). Cada linha mostra a contagem de membros (`disco#info`, consulta leve) e o avatar do canal (`vcard-temp`, sob demanda, com cache no `MLImageManager`; enquanto não chega, aparecem as iniciais coloridas). Botão "Entrar" reaproveita o fluxo de adicionar canal (entra nos bookmarks e nas conversas). Só salas públicas aparecem (no isaCloud, `muc_room_default_public = false`). |
| 2 | ~~GIF pelo teclado~~ **feito em 23/10/2026** | baixo | Busca de GIF no clipe de anexos (Giphy, com GIFs em alta quando a busca está vazia), prévias animadas e envio do GIF original animado; no chat, o GIF toca duas vezes e para, e toca de novo ao ser tocado. A chave fica em `isaCloud/local/giphy-api-key.txt` (fora do Git) e entra no build pelo script. |
| 3 | ~~XEP-0317 (Hats)~~ **feito em 23/10/2026** | baixo a médio | Hats lidos da presença da sala e salvos no banco (migração 7.015, tabela `muc_hats`). Em Participantes do Canal, pílulas abaixo do nick, com cor fixa por título. Nas mensagens do canal, 🛡️ ao lado do nick de quem tem o hat "Verificado" (reconhecido pelo início do título, porque o servidor envia "Verificado 🛡️"), sem entrar na menção. Vale para qualquer canal. |
| 5 | XEP-0393 (Message Styling) | médio | Negrito, itálico, código e citação nas mensagens: interpretação e renderização no cliente. |
| 6 | ~~@ com autocompletar em grupos~~ **feito em 24/10/2026, opção A (só texto), testado no simulador** | médio | Sugerir participantes da sala ao digitar `@` e marcar a menção; definir o formato no XML (provável XEP-0372). |
| 7 | Código de afiliado | médio, com servidor | Tela "Tenho um código" com escolha de servidor, aceitando um token curto e reutilizável; depende de o `mod_invites` do Prosody gerar esse tipo de token. |
| 8 | Barra de pesquisa na tela inicial (**parte de nomes feita em 24/10/2026**: contatos, grupos e canais; busca em mensagens pendente; acentos como nice to have) | médio, uns 1,5 a 2 dias | Entre o título Conversas e a lista, uma barra que busca primeiro pelo nome de contatos, grupos e canais (conversas recentes e bookmarks), sem diferenciar acento nem maiúscula. Abaixo dela, antes dos resultados, uma linha com lupa: "buscar <termo> nas conversas". Essa busca leva ao histórico local (mensagens com o termo), com índice FTS5 e `remove_diacritics` por migração, porque a busca por `LIKE` não trata acento e fica lenta. Só o histórico local entra; mensagens que existem só no servidor (MAM) não aparecem. Parte de nomes: uns meio dia; parte do histórico: 1 a 2 dias. |

## Aguardando o Monal

Itens que dependem de a `develop` do Monal implementar antes de o isaCloud seguir. Ficam fora da fila até a implementação chegar.

- **Responder deslizando para a direita (XEP-0461)**: o gesto e o botão "Responder" já existem na `ChatView.swift` da `develop`, mas comentados pelo time do Monal. Quando sair, o isaCloud precisa do protocolo: `<reply>` (com `stanza-id` em grupos e o ID da mensagem em 1:1), fallback de citação (XEP-0428), banco e exibição no balão e nas notificações. Até lá, vale a citação em texto que já está em uso, que vai no corpo da mensagem.

## Por avaliar

Funcionalidades que ainda não entraram na fila: decidir se valem a pena antes de priorizar.

| Funcionalidade | Esforço | Observações |
|---|---|---|
| XEP-0455 (Service Outage Status) | baixo | Ler o aviso de manutenção anunciado pelo servidor e exibir ao usuário. |
| Avatares de quem não é contato em grupos e canais | médio a médio-alto | Grupos: buscar sob demanda o avatar público (PEP) pelo JID real. Canais: ler o hash de avatar da presença (XEP-0398) e buscar pela sala; o código do Monal para isso está comentado (possível trabalho em andamento). |
| OMEMO: buscar a lista de aparelhos antes de marcar todos como removidos | baixo a médio | Ao receber de outra pessoa um aviso de lista vazia (`retract`/`purge`/`delete` ou `publish` sem aparelhos), o app hoje marca todos os aparelhos dela como removidos (`devicelistHandler` em `MLOMEMO.m`); com quem não é contato, ele não recebe a lista corrigida depois e fica "sem dispositivos com criptografia" até alguém redefinir a sessão. Buscar a lista de novo e só marcar se continuar vazia. Código central do OMEMO: testar com cuidado. Visto em 23/10/2026 com `isadora@im.isacloud.cc` no grupo Avatares. |
| Fonte do nome nas conversas de grupos e canais | baixo, mas depende de decisão | O ExyteChat fixa a fonte do nome (`.caption.weight(.bold)`) e não tem opção para mudar. Aumentar exige: mudar a biblioteca (fork próprio ou cópia no repositório, com custo de manutenção) ou desenhar o balão de texto no app (trabalho maior, com risco de regressão). Decisão pendente. |

## Feito

- **Caixa de mensagem própria** (23/10/2026): substitui a do ExyteChat, com texto, respostas, edição de mensagem, rascunho restaurado ao voltar ao chat, anexos de galeria e de arquivo (com prévia e remoção), gravação de áudio (tocar para gravar, segurar para enviar, pausar, apagar e enviar) e localização. Testes de interface e unitários em `ChatInputBaselineTests`, `ChatInputModelTests` e `ChatInputRecordingTests`.
- **Reações nos GIFs** (23/10/2026, testado e OK): as reações aparecem sobre a borda de cima do GIF, do mesmo lado que nas demais mensagens, em círculos, com a cor do meu balão para as que eu enviei e a cor dos balões das outras pessoas para as demais. Mesmo emoji de várias pessoas vira um círculo com a contagem.
- **Menção sem o emoji de verificado** (23/10/2026, testado e OK): ao tocar na bolinha com a inicial, o nome inserido é só o nick.
- **Splash com o logo e "isaCloud" em rosa** (23/10/2026, testado e OK).
- **Balões das minhas mensagens em rosa isaCloud** (23/10/2026): texto branco e horário com transparência, por contraste; as reações que eu envio usam a mesma cor.
- **Seletor de contatos** (23/10/2026): Todos / Contatos / Grupos / Canais num controle só e um único botão "+" com as opções de adicionar contato, criar grupo e canais públicos.
- **Tela Minha conta** (23/10/2026): ícone de perfil com o logo do isaCloud, título "isaCloud", seção de contas sem cabeçalho cinza, cabeçalho "Usuário" fino e remoção de "Adicionar conta (avançado)".
- **Logo na lista de conversas e na tela de abertura** (23/10/2026): logo do isaCloud no botão de perfil, e na tela de abertura o logo com "isaCloud" em rosa abaixo, centralizados.
- **Criação de grupos no serviço de MUC do domínio** (23/10/2026): cada domínio usa o componente certo (`conference.isacloud.cc`, `canais.xmpp.social.br`, `canais.voz.social.br`); o primeiro componente anunciado serve para os demais servidores. Persistência de grupo confirmada por `muc_persistent`, com aviso se o servidor não confirmar.
- **Cores dos hats fixas** (24/10/2026): "Verificado", "Deusa do Olimpo" e "CEO" têm cores próprias e diferentes; os demais títulos usam cor pelo próprio título. Conferido no iPhone.
- **Tradução do campo de mensagem** (24/10/2026): "Escreva uma mensagem...". Regra de traduções em `docs/traducoes.md`.
- **Traduções pt-BR** (23/10/2026) dos textos novos: caixa de mensagem, GIF, localização, contatos, hats, "Endereço do contato ou canal" e "Nenhum pedido de contato pendente".

- **Localização na caixa de mensagem** (23/10/2026): item "Localização" no clipe, com mapa para escolher o lugar (o centro do mapa é o lugar enviado); envia `geo:` como o restante do Monal, e o chat já mostra o mapa. Teste de interface em `ChatInputBaselineTests`. Localização ao vivo não entra.
- **Histórico ao conectar em canais públicos** (23/10/2026): ao entrar, o catchup MAM dos canais baixa só os últimos 7 dias (padrão), podendo ser trocado nos detalhes do canal para 1 mês ou "Tudo" (sem limite, sob responsabilidade de quem escolhe). Grupos privados não mudam. Migração de banco 7.014 (`buddylist.mam_catchup_days`).
- **"Redefinir sessão OMEMO" sempre visível** (23/10/2026) nos detalhes de contatos e membros de grupos privados, sem precisar da interface avançada; tradução pt-BR da opção de interface avançada e da confirmação.
- **Avatares com iniciais coloridas** (23/10/2026): quem não tem avatar aparece com 1 ou 2 letras ("Isadora Ribeiro" → IR) sobre a cor do XEP-0392; nos canais, a cor vem de `sala/apelido` (antes eram letras sobre fundo branco).
- **XEP-0202 (Entity Time)** (23/10/2026): o app responde à consulta de hora local (`urn:xmpp:time`) de contatos com assinatura de presença, da própria conta e do servidor, e anuncia o recurso no disco; nos detalhes do contato, mostra "Horário local" abaixo de "Visto por último" quando um aparelho do contato responde. Teste em `MonalXMPPUnitTests/HelperToolsTest.swift`; exibição conferida no iPhone com o Conversations.
- **Guia XMPP sempre em Conversas** (24/10/2026, testado e OK): ao entrar na sala, o canal vai para as conversas recentes, mesmo depois de arquivado. Regra em `MLMucProcessor.m` (`kIsaCloudGuideRoom`).
- **Traduções do menu de long press** (24/10/2026, testado e OK): Copiar, Responder, Editar, Excluir para todos (antes Retrair), Excluir localmente, Moderar e Reenviar.
- **Responder com citação em texto** (24/10/2026, testado no simulador): "Responder" põe `> autor: trecho` na caixa (só o trecho em 1:1). Em grupos e canais o autor aparece; a citação vira um bloco com `│`, na cor do texto. A citação vai no corpo da mensagem, cifrada junto com o OMEMO.
- **Build 2 enviado ao App Store Connect** (24/10/2026): em processamento para o TestFlight. Rotina em `docs/publicacao-testflight.md`.
- **Busca de nomes na tela inicial** (24/10/2026, testado no simulador): barra "Buscar" entre o título e a lista, que procura contatos, grupos e canais pelo nome; tocar num resultado abre a conversa. Acentos não são tratados (nice to have).
- **Avatar da conta no botão de perfil** (24/10/2026): o botão mostra o avatar redondo da conta e é atualizado quando a foto muda aqui ou em outro app com a mesma conta (teste no iPhone: sem crash).
- **Compartilhar pelo iOS** (24/10/2026): a fila de envio mostra o spinner e a cápsula "Enviando..." na conversa de destino, e a mensagem aparece assim que é enviada. Botão "Clear share sheet queue" na tela de debug. Esquema de abertura por build: `isacloudOpen` no isaCloud e `isacloudOpenDev` no isaCloud.dev, para o compartilhamento de um não abrir o outro. Folha de compartilhar em rosa, com textos do isaCloud.
- **Colar imagem da área de transferência** (24/10/2026): item "Colar da área de transferência" no clipe, com o aviso "Nenhuma imagem na área de transferência" quando não há imagem.
- **Cápsula "Enviando..." e spinner ao enviar arquivo** (24/10/2026): acima da caixa de mensagem e no topo da conversa.
- **Foto recebida aparece ao vivo** (24/10/2026): a conversa aberta atualiza a mensagem quando o tipo e o tamanho do arquivo são conhecidos, sem precisar sair e entrar.
- **Sincronização de canais de 2 dias por padrão** (24/10/2026): nova opção "2 days" no seletor (junto de 7 dias, 1 mês e Tudo); canais novos começam em 2 dias.
- **Lista de domínios do isaCloud** em um só lugar (`HelperTools isaCloudServerDomains`), usada na criação de contas e nos convites.
- **Convites sem página do servidor**: quando o servidor não manda o `landing-url`, um domínio do isaCloud monta `https://<domínio>/register?t=<token>`, e os outros servidores recebem o link `xmpp:`.
- **Executável renomeado para isaCloud** (24/10/2026): o app é `isaCloud.app`, com o mesmo bundle `br.com.isacloud.messenger`. O módulo Swift continua `Monal`, para não mexer nos imports.
- **Identidade do cliente para o servidor** (24/10/2026): versão e nome de software/capacidades passam a dizer "isaCloud"; rótulo "Monal IM" das notificações virou "isaCloud".
- **Endereços do app** (24/10/2026): relatórios de crash e contato em `sysadmin@isacloud.cc`; links Sobre, FAQ e Privacidade em `isacloud.com.br`.
- **Títulos inline** nas telas Conversas e Contatos (24/10/2026), com a barra de busca de Contatos sempre visível.
- Identidade própria (Bundle ID `br.com.isacloud.messenger`, App Group, keychain), marca, cores, ícone e traduções próprias.
- Primeira abertura direto em Boas-vindas; registro com os servidores do isaCloud e mensagens de erro amigáveis.
- Push apontando para `push.isacloud.im` (fpush, ver `docs/fpush/`) e STUN de reserva `stun.isacloud.im`.

## Testes pendentes

- ✅ **Limite de 7 dias no histórico de canais públicos** (testado e OK em 24/10/2026; a seção abaixo ficou como registro do método). A janela já está implementada (padrão 7 dias, 1 mês ou "Tudo" nos detalhes do canal), mas falta medir o efeito num canal com arquivo MAM grande:
  - **Prosody** (`prosody@conference.prosody.im`): não serve. O arquivo começa em 17/10 (48 mensagens no total), então a janela de 7 dias não corta nada.
  - **Conversations** (`conversations@conference.siacs.eu`): anuncia MAM. A primeira página da janela voltou com `complete='false'` e não consegui terminar a paginação. Falta: (1) contar as mensagens da janela até `complete='true'`; (2) repetir com "Tudo" e comparar o total.
  - Pré-requisito: entrar de novo no canal, gravar um stanza ID inexistente em `buddylist.lastMucStanzaId` e forçar sessão nova (Ajustes → Debug → Extra Settings → "Reset the state of all accounts").
  - Antes do teste, vale o log contar as páginas de MAM, para saber quando a paginação termina.

- **Aviso de grupo não permanente** (23/10/2026, ainda pendente): quando o servidor não confirma `muc_persistent` após criar um grupo, o app mostra o aviso. Falta testar esse caminho: no isaCloud a persistência foi confirmada (grupos teste4 e teste5). Para testar, precisa de um servidor que não confirme a persistência.

- **Testes de interface da caixa de mensagem** (24/10/2026): a classe `ChatInputBaselineTests` falha ao abrir a conversa "Notas para si mesmo" pela lista de contatos (a linha não é encontrada pelo teste). O app funciona no iPhone; a falha é da navegação do teste, ainda não investigada. Precisa ser resolvida para o teste servir de regressão de novo.

## Pendências técnicas

- **Travamento na sincronização inicial de canais** (observado no isaCloud.dev em 24/10/2026, relatórios de 17:41 e 17:46): ao voltar ao primeiro plano, `unfreezeParseQueue` (em `xmpp.m`) espera de forma síncrona a fila de recepção, que está ocupada com o catch-up. A thread principal fica presa e o iOS encerra o app pelo watchdog. Correção planejada: não esperar a fila (aguardando decisão).
- **isaCloud.dev com App Group** (24/10/2026): o grupo `group.br.com.isacloud.messenger.dev` foi criado no portal e vinculado aos três identificadores `.dev`. Validar a extensão de compartilhamento no `.dev`.
- **Textos com "Monal" ainda visíveis**: por exemplo "Rate Monal", "Welcome to Monal !", "Account already configured in Monal!", textos de Configurações e alertas de anexo da tela de chat antiga. Plano: trocar nas chaves de código e colocar as traduções no override do isaCloud.
- **Links do Monal no app**: alerta de DNSSEC (mantido por decisão), identificação de capacidades (`XMPPPresence.m`, nó `https://monal-im.org/`), convites (`invite.monal-im.org`, só usado quando o servidor não manda landing) e servidores de push/TURN da lista do Monal.
- **Página de convite do servidor**: para o convite abrir numa página web, cada domínio precisa servir `/register?t=` (ex.: `mod_invites_page` no Prosody).

## Pendências fora do código

Ver a seção "Pendências" do `CLAUDE.md` (por exemplo, reativar o push filtering quando a Apple liberar).

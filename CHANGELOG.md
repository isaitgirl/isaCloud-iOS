# Changelog do isaCloud para iOS

Mudanças do fork isaCloud sobre o Monal. A lista do que está feito e do que falta está em [ROADMAP.md](ROADMAP.md).

## 0.0.1 (build 50) — 28/10/2026

### Adicionado
- **Importar um banco de dados pelo app (Configurações → App → "Importar do Monal"; a mesma coisa fica em Depuração → "Import Database…" para nós)**, para trocar de cliente sem perder o histórico. O iOS não deixa nenhuma ferramenta de fora escrever na raiz do container compartilhado (onde fica o `sworim.sqlite`) — o serviço de arquivos só aceita `Library`, `Documents` e `tmp` —, então o próprio app copia o arquivo escolhido para `import-sworim.sqlite` e, na abertura seguinte, troca o banco atual por ele antes de qualquer código abrir o banco. A escada de migrations roda normalmente depois. Depois de importar, os **avatares** são baixados de novo (as imagens não vêm no banco, só o hash — e com o hash guardado o app nunca baixaria outra vez); o Depuração também ganhou **Reset Avatar Cache**, para o mesmo efeito sem reimportar. Aceita o banco **cru ou comprimido (`.gz`)** — as versões novas do Monal exportam comprimido —, e a linha do menu tem tradução pt-BR. **É uma ferramenta de depuração**, com aviso de que o banco atual será substituído; senhas e a chave OMEMO continuam no keychain de cada app, então o Assistente de Migração pede as senhas.

## 0.0.1 (build 47) — 28/10/2026

### Corrigido
- **O app congelava e podia ser encerrado pelo sistema por causa do log (`0x8BADF00D`).** Quatro relatórios de crash (builds 40 e 42) mostram a thread principal **parada** em `[DDLog flushLog]`, com o app quase sem CPU, até o iOS matar: *scene-update watchdog* (30 s) e, no último, *"Failed to terminate gracefully after 5.0s"*. O `flushLog` é um `dispatch_sync` **sem timeout** para a fila de log, que fica suspensa com o app em segundo plano; com a rede instável (mais linhas de log) ficou fácil de travar. Agora as **23 chamadas diretas** de flush do app e da extensão de notificação (14 em `MonalAppDelegate.m`, 9 em `NotificationService.m`) passam pelo `HelperTools flushLogsWithTimeout:`, que espera a fila **com timeout** e segue em frente se estourar. A única perda possível são as últimas linhas de log.
- **Compartilhar um arquivo dava "your account got disconnected while requesting upload slot".** O app abria e subia a foto **antes de a conta conectar**; o pedido do espaço de upload ia por um stream ainda desconectado. Agora, na fila do compartilhar, o app espera a conta ficar ligada e o servidor de upload ser anunciado (até ~30 s) antes de subir arquivo ou imagem.
- **O compartilhar deixava marcar vários destinos**, embora mandasse para um só: a linha usava `Button`, e o iOS mantinha a linha destacada. Agora é um toque simples, com um destino por vez.

### Adicionado
- **Responder com áudio mantendo a citação.** Puxar o balão para responder preenche o campo com a citação, e o microfone desaparecia. Agora o microfone fica ao lado do botão de enviar, e a resposta com áudio vai em duas mensagens: a citação num balão com um 🎤 e o áudio em seguida. Gravação com menos de 0,35 s é descartada (não vira áudio vazio).

## 0.0.1 (build 43) — 28/10/2026

### Alterado
- **A janela de compartilhar do iOS ficou igual à tela de "Encaminhar" do app.** Antes ela era a do Monal — `SLComposeServiceViewController`, uma API depreciada —, com duas linhas de configuração ("Conta" e "Destinatário") abrindo uma tabela de texto sem avatar; no simulador ela aparecia com o campo vazio, um pedaço de imagem sobrando e só a linha "Conta". Agora é uma lista SwiftUI com avatar, nome, endereço e a conta de cada destino, busca, seleção com um toque e o rosa do isaCloud, no desenho do sistema (saiu a compatibilidade forçada do iOS 26 que a extensão pedia).
- **Grupos e canais entram na lista do compartilhar** (antes só contatos individuais), com os que a pessoa não pode escrever cinza e desabilitados, com "Você não pode escrever aqui", como no Encaminhar.
- **Campo de mensagem opcional** abaixo da lista: o texto vai como mensagem e o anexo em seguida, como já era.

### Continua igual
- A extração do que foi compartilhado (fotos, vídeos, arquivos, mapas, contatos, texto), a fila `sharesheet_outbox` e a abertura do app para enviar: só a tela mudou.
- Cancelar fecha sem enviar e não abre o app.

### Testado
- No simulador iOS 27: a lista com as três contas e os canais, o canal sem voz não seleciona, cancelar não envia, e o envio de foto + mensagem chegou (o texto e um `aesgcm://` no banco, fila vazia no fim).
- O build também compila no iOS 18.6 (Xcode 26.2). Falta a mesma passada de UI no 18.6 e no iPhone.

## 0.0.1 (build 42) — 28/10/2026

### Corrigido
- **Em canal ou grupo em "só menção", o app notificava por qualquer pedaço de texto parecido com o seu nome.** Quem tem um apelido curto (como "isa") recebia notificação de "isafashiondev", "precisa", "analisar", "avisar", "pesquisa" ou "Elisa", porque a regra procurava o apelido, o nome de exibição, a parte local do endereço e o endereço dentro de qualquer palavra. Agora o nome só conta como menção quando aparece como **palavra inteira**, sem diferenciar maiúscula nem acento: "oi isa", "isa, vem aqui", "@isa" e "isa." contam; "isafashiondev", "precisa" e "Elisa" não. Vale para a notificação (inclusive a da extensão de notificação) e para a bolinha vermelha ou cinza da lista de Conversas. Limite conhecido: `.`, `-` e `@` colados ao nome contam como fim de palavra ("isa-dev" ainda casa com "isa"). Era o comportamento do Monal original; o código ficou numa função só, `HelperTools text:mentionsAnyOfNames:`.

## 0.0.1 (build 41) — 28/10/2026

### Corrigido
- **Ao enviar uma mensagem de texto, a conversa não dá mais um "sobe e desce" rápido** (visto no modo avião, em que a gravação é quase instantânea). A mensagem que aparece na hora (provisória) era trocada na lista pela mensagem gravada, que tem outro id, e a lista fazia isso como apagar uma linha e inserir outra, em duas etapas: três movimentos seguidos. Agora a própria mensagem provisória passa a apontar para a gravada, a lista não vê troca nenhuma e o status (o spinner que vira tique) continua sendo acompanhado. Medido gravando a tela do simulador do iOS 27: 3 surtos de movimento antes, 1 depois (a entrada da mensagem).

## 0.0.1 (build 40) — 28/10/2026

### Adicionado
- **A mensagem de texto aparece na hora ao enviar, com um spinner no lugar do tique** (PR do Jejê, com uma correção). Antes, a gravação da mensagem no banco rodava na thread principal e esperava o bloqueio de escrita do banco, que outra parte do app segura de vez em quando (medido: 7 segundos parada); a conversa ficava parada e a mensagem só entrava depois, às vezes já com reação de alguém. Agora a mensagem entra na hora, é gravada e enviada em segundo plano, na ordem, e é trocada pela real quando termina (a hora continua sendo a da gravação). Se a gravação falhar, a mensagem sai e o texto volta ao campo. **Enquanto a mensagem está a caminho ela não responde a toque** (sem menu, reações nem ações). Só vale para texto escrito na barra; foto, GIF, arquivo, localização e áudio seguem como antes. O spinner vem do fork do ExyteChat (PR 9 de lá).

### Alterado
- **Menos notificações fantasma, até a Apple liberar o push filtering.** Sem essa permissão, todo push de alerta virava uma notificação visível ("New Message / New Message?", com som) mesmo quando o app decidia não notificar. Agora a extensão de notificação entrega no lugar um **aviso passivo** (sem som, sem banner, sem texto, com o nome do app como título) e o remove quando consegue: ao fim da extensão, no próximo push e ao abrir o app. Funciona junto com o patch do servidor (push em segundo plano para o que não é importante e um collapse id nos alertas), que já está no ar. Quando a Apple liberar a permissão, basta mudar `ISACLOUD_HAS_PUSH_FILTERING` para `1`. **Ainda não testado no aparelho com o servidor**: ver se o iOS respeita o aviso passivo e se ele some sozinho. Como reverter: `docs/fpush/README.md`. (Estava no build 39, enviado só ao TestFlight; o 40 o inclui.)

## 0.0.1 (build 39) — 28/10/2026

### Alterado
- **Menos notificações fantasma, até a Apple liberar o push filtering.** Sem essa permissão, todo push de alerta virava uma notificação visível ("New Message / New Message?", com som) mesmo quando o app decidia não notificar. Agora a extensão de notificação entrega no lugar um **aviso passivo** (sem som, sem banner, sem texto, com o nome do app como título) e o remove quando consegue: ao fim da extensão, no próximo push e ao abrir o app. Funciona junto com o patch do servidor (push em segundo plano para o que não é importante e um collapse id nos alertas), que já está no ar. Quando a Apple liberar a permissão, basta mudar `ISACLOUD_HAS_PUSH_FILTERING` para `1`. **Ainda não testado no aparelho com o servidor**: ver se o iOS respeita o aviso passivo e se ele some sozinho. Como reverter: `docs/fpush/README.md`.

## 0.0.1 (build 38) — 28/10/2026

### Corrigido
- **Convite por link ou QR (`xmpp:…?roster;preauth=…;ibr=y`): quem convidou agora entra na lista de contatos de quem cria a conta.** Num app sem contas, o link abre o registro com o servidor e o convite; depois do registro o app adiciona quem convidou (com o token do convite) e abre a conversa com essa pessoa. Antes ele dependia de uma tela "Adicionar contato" que, depois do registro, não aparecia (visto no Monal.alpha). Testado de ponta a ponta com o `isacloud.im` num simulador sem contas. Num app que já tem conta, o link de contato continua abrindo a tela "Adicionar contato" (ou a conversa, se a pessoa já está na lista).

### Alterado
- **A tela "Convidar para o isaCloud" mostra só o link da página de convite** (QR e compartilhar), como antes do build 37: as duas abas "Pelo site" e "No aplicativo" saíram, porque a página de convite do servidor passou a oferecer os dois caminhos (registrar pelo aplicativo ou pelo site).

## 0.0.1 (build 37) — 28/10/2026

### Adicionado
- **Convite com duas abas.** A tela "Convidar para o isaCloud" tem agora **Pelo site** (o QR e o link de compartilhar do site, como era) e **No aplicativo** (o QR e o link `xmpp:` que abre a criação de conta direto no isaCloud e, depois, adiciona quem convidou). A aba do aplicativo avisa que quem recebe precisa ter o isaCloud instalado. As abas só aparecem quando o servidor devolve os dois links; sem mudança no servidor.

### Alterado
- **A bolinha de não lidas da lista de Conversas é vermelha ou cinza.** Vermelha: conversa 1:1 não silenciada; grupo ou canal com todas as notificações ativas; grupo ou canal em "só menção" com menção a você nas não lidas. Cinza: conversa 1:1 silenciada; grupo ou canal silenciado; "só menção" sem menção. Silenciado sempre vence, mesmo com menção. A menção segue a regra das notificações (seu apelido na sala, nome de exibição, parte local do endereço ou o endereço completo) e é procurada nas 500 mensagens não lidas mais novas.

### Corrigido
- **O app podia ser fechado pelo iOS ao tocar num resultado da busca em mensagens** (visto num iPhone XR com iOS 18, no build 33). O pulo até a mensagem carrega até 3.000 mensagens, e a lista refazia a detecção de links de cada uma na thread principal, a cada comparação. Agora a detecção usa um cache, calculado em segundo plano antes de inserir as mensagens, e o resultado na tela é o mesmo.

## 0.0.1 (build 36) — 28/10/2026

### Adicionado
- **Encaminhar mídia.** A ação **Encaminhar…** do toque longo agora também aparece em foto, vídeo, áudio, GIF e arquivo (que não tenham sido retirados nem falhado). Vale a mesma folha de destinos do texto (até 5, sem o autor original, inclui as próprias notas). Se a mídia ainda não foi baixada, o app baixa sozinho (aparece "Encaminhando…"). Para cada destino o arquivo é **enviado de novo**, no servidor da conta do destino e com a criptografia do destino (o endereço com a chave nunca é copiado); só depois do envio do arquivo saem, uma logo após a outra, a linha "➦ 📷 Encaminhado" (o emoji muda: 📷 foto, 🎥 vídeo, 🎤 áudio, 🎞️ GIF, 📎 arquivo) e a mídia. Um destino que falha é pulado e aparece num aviso; os outros seguem. O rótulo sozinho também aparece em negrito e branco, como o do texto.

### Alterado
- **A hora das fotos e dos vídeos fica embaixo do balão, fora da imagem**, do lado da mensagem e com o cadeado se for criptografada, como já era nos GIFs (mudança no fork do ExyteChat, PR 8). Mensagem com legenda e a prévia de uma resposta ficam como eram.

### Corrigido
- **Encaminhar para uma conversa que não estava na lista** (inclusive as próprias notas de outra conta e uma conversa arquivada) agora coloca a conversa de volta na lista, no lugar da hora do envio. Valia também para o encaminhar de texto.
- **O app podia fechar ao abrir uma conversa no momento em que chegava uma mensagem nova** (visto uma vez no iOS 18.6): a mesma mensagem entrava duas vezes na lista e o ExyteChat aborta com ids repetidos. Agora uma mensagem já mostrada não entra de novo.

## 0.0.1 (build 35) — 28/10/2026

### Corrigido
- **O título das telas "Adicionar contato ou canal" e "Convidar para o isaCloud" sumia ao entrar, sair e entrar de novo (iOS 27).** O título agora também é colocado na barra de navegação à mão, e as duas telas usam `navigationTitle` no lugar da API antiga `navigationBarTitle(_:displayMode:)`. Testado nos simuladores do iOS 18.6 e do iOS 27.

## 0.0.1 (build 34) — 28/10/2026

### Adicionado
- **Encaminhar mensagem de texto.** No menu da mensagem (toque longo) há a ação **Encaminhar…**, que abre uma folha com contatos, grupos, canais e as suas próprias notas, com busca por nome ou endereço e a conta indicada quando há mais de uma. Dá para escolher até 5 destinos por vez; canais e grupos onde você não pode escrever aparecem apagados, com o aviso "Você não pode escrever aqui". A mensagem sai como sua, com a criptografia do destino, sem o autor original, e começa com a linha "➦ Encaminhado" (em negrito e branco no seu balão; a lista de Conversas mostra o rótulo e o texto numa linha). Em outros aplicativos a linha aparece como texto comum. Mídia (foto, vídeo, áudio, arquivo) ainda não pode ser encaminhada.

## 0.0.1 (build 33) — 28/10/2026

### Adicionado
- **Busca nas mensagens.** Na barra de busca da tela Conversas, duas abas fixas: **Nomes** (contatos, grupos e canais, como antes) e **Mensagens**. A busca em mensagens acha as palavras (a partir de 2 letras) pelo começo, sem diferenciar acento nem maiúscula, e mostra, da mais nova para a mais antiga, o nome da conversa, quem escreveu, a data (a hora, se for de hoje), um trecho com as palavras em negrito e, com mais de uma conta, a conta. Tocar num resultado abre a conversa já rolada até a mensagem, no meio da tela (se ela estiver a mais de 3.000 mensagens do fim, a conversa abre nas mais novas). Mensagens de arquivo (a URL leva a chave do OMEMO), apagadas e retiradas não entram, nem as de contas desligadas. Na primeira abertura depois da atualização o app cria o índice de busca (uns 3 segundos com 133 mil mensagens no iPhone); depois ele é mantido a cada mensagem.

### Corrigido
- **Tocar num resultado da busca (inclusive na aba Nomes) não abria a conversa no iOS 27.** A busca ainda estava fechando quando o app tentava abrir a conversa. Agora a conversa abre quando a busca termina de fechar.

## 0.0.1 (build 32) — 27/10/2026

### Alterado
- **Mudanças de banco do isaCloud numa escada própria de migrations.** Os três passos que o isaCloud acrescentou à escada do Monal com os números 7.014 a 7.016 (dias de histórico dos canais, "hats" e avatares de quem não é contato) passam a ter versão própria (`isacloud_dbversion`) e rodam depois das migrations do Monal. Assim as próximas migrations do Monal, que vão usar esses números, não são puladas nos nossos bancos. Na primeira abertura, o banco que já estava em 7.014 a 7.016 tem a versão do Monal devolvida a 7.013 (as mensagens e as tabelas continuam como estão). Testado em cópias dos bancos do simulador, do TestFlight e do Monal Beta (133 mil mensagens, versão 6.407).
- **A SQLite do app agora tem o módulo de busca de texto (FTS5).** O pacote `sqlite3-package` do Monal repassa uma lista fixa de opções e deixava o FTS5 desligado; o app passa a usar o fork `isaitgirl/sqlite3-package` (branch `isaCloud`) com `ENABLE_FTS5` ligado. É a base para a futura busca em mensagens; por enquanto nada aparece na tela.

### Corrigido
- **O spinner da lista de conversas podia ficar preso.** Quando as transferências de arquivo terminavam depois de as contas já estarem ociosas, o spinner não era atualizado e só sumia na próxima mudança de estado de uma conta ou ao voltar para o app. Agora ele também é atualizado quando as transferências terminam.

## 0.0.1 (build 31) — 27/10/2026

### Alterado
- **Menu "+" de Contatos num painel mais largo.** Os itens ("Adicionar contato ou canal", "Convidar para o isaCloud", "Adicionar via QRCode", "Criar grupo" e "Listar canais") aparecem num painel próprio, de 310 pt, com cada texto em uma linha, em vez do menu do sistema, que quebrava os textos mais longos em duas linhas. Fonte um ponto menor que a do texto normal.
- **Convite e leitura de QR code saíram da tela de adicionar e foram para o menu "+".** "Convidar para o isaCloud" (ícone de compartilhar, rosa) abre uma tela que cria o convite e mostra o QR code, a validade e o botão "Compartilhar link do convite"; com mais de uma conta cujo servidor aceita convites, há um seletor de conta. "Adicionar via QRCode" (câmera, rosa) abre o leitor. A tela de adicionar contato ou canal ficou só com o campo, sem os dois ícones do topo, e voltou a se chamar "Adicionar contato ou canal".
- **Texto de ajuda da tela de adicionar:** "Informe o endereço do contato ou do canal que você quer adicionar, no formato nome@dominio.tld." O item do menu agora diz "Adicionar contato ou canal".

### Corrigido
- **O spinner não estica mais a bolha de vidro dos botões do topo (iOS 26 em diante).** Na lista de conversas, o spinner de sincronização dividia a bolha com o botão de contatos; na janela de mensagem, o do carregamento do histórico e do envio de arquivo dividia a bolha do telefone e do cadeado. Em ambos a bolha esticava e encolhia quando o spinner entrava e saía; agora o spinner fica solto, sem bolha.

## 0.0.1 (build 30) — 27/10/2026

### Adicionado
- **Responder a foto, vídeo, áudio, arquivo e localização** (PR do Jerônimo, solução temporária). O gesto de puxar o balão e o "Responder" do menu passam a valer para mensagens sem texto, e a resposta cita um rótulo curto com emoji: `> 📷 Foto`, `> 🎥 Vídeo`, `> 🎤 Mensagem de áudio`, `> 📎 Arquivo: nome.pdf`, `> 🎞️ GIF` e `> 📍 Localização` (em grupos e canais o autor vem antes). Não mostra a miniatura nem leva à mensagem original: isso depende do XEP-0461 e do XEP-0428, que o Monal ainda não implementou (issue `monal-im/Monal#1671`).

### Corrigido
- **Lista de mensagens voltou a rolar quando o dedo começa em cima de um balão (iOS 27).** O gesto de responder disputava o toque com a rolagem. No iOS 18 em diante ele passou a ser um gesto do UIKit que só começa quando o dedo vai para a direita (PR do Jerônimo, no fork do ExyteChat e no app).
- **Menu da mensagem cortado com o teclado aberto.** Ao fazer o toque longo numa mensagem com o teclado levantado (depois de responder, por exemplo), o menu era montado no espaço acima do teclado e virava uma rolagem, com as ações cortadas; com foto ou link era pior. Agora ele usa a altura da janela e aparece inteiro.

## 0.0.1 (build 29) — 27/10/2026

### Corrigido
- **Avatar de canal de outro servidor não aparecia.** O avatar de uma sala só era buscado quando o hash chegava numa presença da própria sala; alguns servidores (visto com `isadora@xmpp.social.br` e o canal `prosody@conference.prosody.im`) não repassam essa presença. Agora o hash também é lido das informações da sala (`muc#roominfo_avatarhash`, como o Conversations faz) e, se a sala não disser nada mas aceitar `vcard-temp`, o app pede o avatar uma vez por execução. A leitura roda ao entrar na sala: um canal já adicionado sem avatar só o ganha depois de sair e entrar de novo (confirmado no TestFlight, build 29).

## 0.0.1 (build 28) — 27/10/2026

### Corrigido
- **Remover uma conta derrubava o app.** Ao remover uma conta, o Monal apagava as mensagens dela e em seguida mandava um aviso geral de atualização; cada mensagem ainda na memória tentava se recarregar do banco, e a asserção "Querying for one single history ID must always yield exactly one result" abortava o app (a conta já estava removida). Agora a mensagem que já não existe é simplesmente ignorada. Visto no isaCloud e no Monal alpha (3 quedas ao remover 3 contas).

## 0.0.1 (build 27) — 27/10/2026

### Adicionado
- **Responder puxando o balão para a direita** (PR do Jerônimo). O balão acompanha o dedo, uma seta de resposta aparece atrás, há uma vibração ao passar do ponto e o balão volta com um bounce; a citação entra no campo de texto, como no "Responder" do menu.
- **Reações no rodapé do balão** (PR do Jerônimo, com o ponto de corte e a preferência feitos em 27/10/2026). As reações aparecem em cápsulas no rodapé do balão, com o número junto do emoji. Quem preferir as bolinhas sobre o canto do balão liga "Reações acima das mensagens" em Configurações → Interface do Usuário → Aparência (desligada por padrão). A modal de quem reagiu usa componentes nativos e os emojis de cada pessoa quebram a linha, nos dois modos.

### Alterado
- **Menu principal (botão do avatar) mais atual.** As seções viram cartões arredondados, como nas telas de Configurações Gerais, e os títulos ("Aplicativo", "Suporte", "Sobre") passam a ficar centralizados na faixa, em caixa mista e semibold, em vez de colados embaixo, em caixa alta e pequenos. Saíram "Avalie o isaCloud" (levava à página do Monal na App Store) e "Enviar um bug" (abria as issues do repositório do Monal); voltam quando o isaCloud tiver página na App Store e um canal próprio de bugs.
- **Citações aninhadas, como no Conversations.** Uma resposta a uma resposta aparece com uma barra dentro da outra (`>>` é uma citação dentro de uma citação, até 7 níveis). Ao responder, a citação da mensagem desce um nível e as linhas que já estão fundas demais ficam de fora, para a resposta não crescer a cada ida e volta.
- **Lista de conversas mais espaçada** (PR do Jerônimo): linhas de 72 pt (86 pt com mais de uma conta), em vez de 60 e 74.

### Corrigido
- **Gesto de responder puxando o balão mais fluido.** O balão deixou de reconstruir a mensagem inteira a cada quadro do arrasto (o estado do arrasto passou para uma view própria), a vibração é preparada antes de ser usada e a citação e o teclado só entram depois da volta do balão (antes disputavam a thread principal com a animação).
- **Banner amarelo "Temporary failure to enter Group/Channel" voltava para o canal `discuss@conference.conversejs.org`.** O silenciamento do build 20 cobria a falha ao entrar pela presença e o timeout de entrada, mas não a falha temporária da consulta de informações da sala (`disco#info`, também `remote-server-timeout`), que seguia mostrando banner a cada tentativa. Agora esse caminho também só vai para o log (a tela que espera a sala continua recebendo o erro).

## 0.0.1 (build 26) — 26/10/2026

### Adicionado
- **Avatares de quem não é contato em grupos e canais.** Quem marcou "Foto Visível para Todos" agora aparece com a foto nas mensagens e na lista de participantes de grupos e canais, mesmo sem ser seu contato; quem não marcou continua com as iniciais. O app só busca a foto quando o hash da presença muda, guarda cada imagem uma vez e, quando a foto não está disponível, tenta de novo depois de 1 h, 6 h e 24 h.

## 0.0.1 (build 25) — 26/10/2026

### Alterado
- **Menu "+" de Contatos mais curto.** "Adicionar novo contato" virou "Adicionar contato", "Criar grupo de contatos" virou "Criar grupo" e "Canais públicos" virou "Listar canais" (a tela que abre continua com o título "Canais públicos").
- **Grupos privados sem o endereço na lista de Contatos.** O endereço de um grupo privado é um texto aleatório e não diz nada a quem usa; agora só aparece nos detalhes do grupo. Contatos e canais seguem iguais.

## 0.0.1 (build 24) — 26/10/2026

### Corrigido
- **Popup "Desativar criptografia?" cortado no iOS 27.** Agora é um diálogo preso ao cadeado, inteiro e legível.

### Alterado
- **Cadeado nos grupos e canais.** No grupo, o cadeado rosa só mostra o estado (a criptografia se muda nos detalhes do grupo); no canal, duas setas (ida e volta) com um cadeadinho rosa indicam a criptografia em trânsito. Nenhum dos dois tem ação, e tocar neles não faz mais o chat subir até o início.

## 0.0.1 (build 23) — 26/10/2026

### Adicionado
- **Várias contas: de qual conta é cada conversa.** Com duas ou mais contas ativadas, a lista de conversas mostra o JID da conta logo abaixo do nome do contato, grupo ou canal, e a lista de Contatos mostra a conta de cada um. Com uma conta só, nada muda.

## 0.0.1 (build 22) — 26/10/2026

### Adicionado
- **Várias contas: avatares na lista e no botão.** Em Configurações, cada conta mostra o avatar dela no lugar do check; a conta desativada aparece esmaecida, com uma marca de pausa. No botão do avatar da tela principal, com mais de uma conta ativada aparecem **dois avatares sobrepostos** (a primeira conta da lista na frente) e, com mais de duas, um selo "+N". Antes o botão mostrava só a foto da conta que o app abriu primeiro. O botão também atualiza assim que uma conta é adicionada, mesmo que ela ainda não tenha avatar.

## 0.0.1 (build 21) — 26/10/2026

### Adicionado
- **Pedidos de contato bem à vista.** O ícone de Contatos na tela principal ficou um pouco maior e ganhou um selo preto com o número de pedidos em branco ("9+" a partir de dez). Na tela de Contatos, os pedidos aparecem **no topo da lista**, com avatar, nome e os botões **Aceitar** e **Recusar**; o menu "…" tem "Abrir Conversa" e "Recusar e Bloquear". Aceitar ou recusar não sai da tela. Antes era preciso tocar no "+" e em "Adicionar contato" para ver o pedido. O "+" da tela de Contatos não tem mais bolinha. No iOS 26 em diante, o avatar da conta no canto de cima à esquerda não tem mais a bolha de vidro em volta: o avatar redondo (44 pt) ocupa todo o espaço do botão. O box de pedidos também saiu da tela "Adicionar contato".

## 0.0.1 (build 20) — 26/10/2026

### Adicionado
- **Reagir pela modal de reações** (do Jejê). A modal de quem reagiu agora tem **uma linha por pessoa**, em ordem alfabética, com os emojis dela à direita (faixa que rola quando não cabem). A linha **"Você" é sempre a primeira**, mesmo sem reações: tocar num emoji seu remove a reação, e o **"+"** abre o teclado de emojis do sistema para adicionar outra. A modal acompanha as mudanças enquanto está aberta. No balão das mensagens de outras pessoas, o selo de contagem não fica mais coberto pelo balão vizinho. Mudança nº 4 do fork do ExyteChat (revisão `3b4801b`). Não testado no iOS 18 nem em iPhone real pelo autor.

### Alterado
- **Menos banners de aviso.** Falhas de fundo que não impedem o uso (por exemplo "Falha temporária ao entrar no Grupo/Canal: ... remote-server-timeout", quando o servidor de outro domínio não responde) não mostram mais o banner amarelo; o timeout de entrada em sala deixou de ser um erro grave (sem banner vermelho e sem notificação com som). O mesmo aviso não grave da mesma conta aparece no máximo uma vez a cada 10 minutos. Os erros continuam no log. Quando você mesmo adiciona um canal, o erro continua aparecendo na tela de adicionar.

## 0.0.1 (build 19) — 26/10/2026

### Corrigido
- **Crash ao abrir o app logo depois de uma notificação (iOS 27).** O app caía na abertura, em `ActiveChatsViewController showWarningsIfNeeded` ("Connected xmpp* object for accountID is nil!"), e depois pedia para enviar o relatório. Causa: ao abrir o app com a extensão de notificações ainda rodando, `willFinishLaunching` espera a extensão num run loop aninhado; nesse tempo o UIKit monta a tela inicial, que pergunta pelas contas antes de `didFinishLaunching` criá-las. Agora a tela só adia os avisos (servidor sem MAM ou sem Stream Management) até as contas existirem. Visto 4 vezes em 26/10/2026 em dois iPhones com iOS 27.0.1 (builds 9 e 18).

### Corrigido
- **Foto de perfil: mudar só a visibilidade não reenvia mais a foto.** Antes, ligar ou desligar "Foto Visível para Todos" reenviava a foto inteira, e o servidor ainda recusava a primeira tentativa ("precondition not met"), então a foto subia duas vezes (~40 s em um servidor que limita o cliente a 3 kB/s). Agora o app só troca o modelo de acesso dos nós (uns 0,1 s) e só publica a foto se ela ainda não existir no servidor. Ao trocar a foto e a visibilidade juntas, a visibilidade vai primeiro.

## 0.0.1 (build 18) — 26/10/2026

### Adicionado
- **Quem reagiu.** Tocar nas reações de uma mensagem (ou de um GIF) abre uma lista com quem reagiu e com qual emoji, com filtro por emoji ("Tudo" e um chip por emoji), e o nome "Você" para a sua reação. O balão agora mostra **um círculo por emoji**, com um selo de contagem no canto de cima quando mais de uma pessoa reagiu (antes eram um círculo por reação). A lista que aparecia acima do menu do toque longo saiu. Feito pelo Jerônimo, no fork do ExyteChat (revisão `60e5f56`, mudança nº 4 em `docs/exytechat-fork.md`) e no app, com 8 testes novos do agrupamento.

## 0.0.1 (build 17) — 26/10/2026

### Alterado
- **Menu da mensagem (reações, responder, copiar...) abre bem mais rápido.** O toque longo passou de 0,5 s para 0,3 s e a animação do menu de 0,3 s para 0,15 s (antes o menu ficava completo uns 0,5 s depois do toque longo disparar; agora uns 0,25 s). Vale também para os GIFs. A mudança do toque longo está no fork do ExyteChat (`isaitgirl/ExyteChat`, branch `isaCloud`, revisão `9f4e34e`; ver `docs/exytechat-fork.md`). Se o menu abrir sem querer ao rolar a conversa, o valor está em `UIList.swift` (fork) e em `GifMessageBubble`.

## 0.0.1 (build 16) — 26/10/2026

### Adicionado
- **Apelido por grupo e canal.** Nos detalhes do grupo ou canal, "Nome de Exibição" troca o seu apelido só naquela sala; o nome de exibição da conta não muda e as salas novas continuam entrando com ele. Mostra erro traduzido quando o apelido já está em uso. O apelido vai para o bookmark da sala e os outros aparelhos da conta seguem a troca. "Usar o Nome da Conta" volta ao padrão. Testado nos simuladores iOS 18.6 e iOS 27 com dois aparelhos; conferido também no iPhone, no canal e em grupo privado.

### Alterado
- Na tela do apelido, o título e a linha dos detalhes usam "Nome de Exibição" (igual à tela de conta) e o atalho "Usar o Nome da Conta" ficou pequeno e em preto, para o "Salvar" ser o botão de destaque.
- Removido o código temporário de medição do atraso de envio que estava nos builds 13 a 15 (gravava um arquivo de log no aparelho). O atraso de ~1 s segue sem causa achada; ver `docs/decisoes.md`.

### Corrigido
- Troca de apelido de uma sala já entrada não trata mais o erro do servidor como "falha ao entrar", que apagava a sala dos favoritos e dos bookmarks.

## 0.0.1 (build 15) — 26/10/2026

### Corrigido
- **Foto Visível para Todos**: a chave agora mostra o que está no servidor (antes valia o que estava gravado em cada aparelho, e simuladores e iPhone discordavam). Ao salvar uma mudança de visibilidade, a foto é publicada de novo com a visibilidade escolhida, o que também cria os nós de avatar se não existirem.
- **Foto nos canais**: depois de trocar ou apagar a foto, o app reenvia a presença (inclusive para as salas), para os outros clientes verem o avatar nos canais. Conferido com um usuário que não tem a conta no roster.

## 0.0.1 (build 14) — 25/10/2026

### Adicionado
- **Foto Visível para Todos**: nova chave em Editar Conta para escolher quem vê a foto da conta. Desligada (padrão), só contatos veem; ligada, qualquer pessoa vê, como no Conversations. Mudar só a chave reconfigura os nós de avatar no servidor, sem republicar a imagem. O nome de exibição continua visível só para contatos. Conferido nos simuladores (linha, tradução e gravação da escolha); a mudança no servidor ainda precisa ser conferida com uma conta que não seja contato.

### Corrigido
- GIFs enviados e recebidos agora têm o mesmo que as outras mensagens: foto de quem enviou ao lado (também em conversas 1:1), horário com cadeado abaixo, ícone de status nos seus GIFs, reações exibidas no GIF e menu de toque longo para reagir, responder e excluir. O balão dos GIFs é próprio do app e tinha ficado sem essas partes.

### Alterado
- Chaves (seletores) das telas de ajustes com mais folga na margem direita, alinhadas com as setas e o separador; no iOS 27 elas encostavam e saíam da borda da tela (`MLSwitchCell.xib`, margem de 8 para 26 pt).

## 0.0.1 (build 13) — 25/10/2026

### Alterado
- Citações nas respostas agora têm **uma barra vertical contínua** à esquerda do trecho citado, em vez de um `|` por linha. Vale para linhas que quebram sozinhas e para citações de várias linhas, nos balões cinza e rosa. É feito num fork próprio do ExyteChat (ver `docs/exytechat-fork.md`).
- Ícones de status das mensagens enviadas maiores: de 10 para 16 pt, ainda alinhados pela base do balão. Convenções na seção abaixo.

### Corrigido
- Mensagem que o servidor recebeu, mas ainda sem confirmação de entrega, ficava sem nenhum ícone (a imagem do estado "enviada" do ExyteChat é vazia). Agora mostra um círculo vazado cinza com um check cinza dentro, desenhado no app.

### Convenções dos ícones de status

Aparecem ao lado das mensagens que você enviou, na base do balão. Todos são redondos e do mesmo tamanho; cinza significa "ainda não chegou ao aparelho de quem recebe", rosa significa "chegou".

| Ícone | Estado | Significado |
|---|---|---|
| Relógio cinza | Enviando | A mensagem está no app, mas o servidor ainda não confirmou o recebimento. |
| Círculo vazado cinza com check cinza | Servidor recebeu | O servidor confirmou (XEP-0198). É o estado final em canais e em contatos cujo cliente não envia confirmação de entrega. |
| Círculo vazado rosa com check rosa | Entregue | O aparelho de quem recebe confirmou a chegada (recibo de entrega, XEP-0184). |
| Círculo rosa cheio com check branco | Lida | Quem recebeu marcou como lida (marcador de leitura, XEP-0333). Em grupos privados vale quando um participante marca. |
| Exclamação vermelha | Erro | O servidor ou o destinatário devolveu erro e a mensagem nunca foi confirmada como entregue. |

Outros indicadores: o cadeado antes do horário mostra que a mensagem foi criptografada com OMEMO (sem cadeado, foi em texto aberto); a cápsula "Enviando..." acima do campo de texto é só para envio de arquivo, foto ou GIF.

## 0.0.1 (build 12) — 25/10/2026

### Corrigido
- GIF recebido em grupo ou canal aparecia solto: sem a bolinha com a foto ou inicial de quem enviou e sem o nick. Agora vem num balão cinza com o nick no topo, e a foto (ou inicial colorida) ao lado, como as outras mensagens de outras pessoas; seus próprios GIFs e os de conversa 1:1 continuam sem balão, como as outras imagens.

## 0.0.1 (build 11) — 25/10/2026

### Corrigido
- Chat deixado aberto não mostrava as mensagens que chegaram enquanto o app estava em segundo plano (o iOS grava as mensagens de uma notificação num processo à parte, e a tela só relia o banco ao ser reaberta). Ao voltar ao primeiro plano, a conversa aberta passa a buscar no banco as mensagens que faltam. Conferido nos simuladores iOS 18.6 e iOS 27.

## 0.0.1 (build 10) — 25/10/2026

### Alterado
- Anexar fotos e vídeos usa o seletor do sistema (`PHPicker`), com várias seleções, álbuns e busca. O seletor da biblioteca ExyteMediaPicker deixa de ser usado no chat.
- Textos dos pedidos de permissão (fotos, câmera, localização e microfone) traduzidos para o português (`InfoPlist.strings` do isaCloud, criado no passo de mesclagem das traduções).

### Corrigido
- Seletor de fotos do chat não rolava no iOS 27: o gesto de seleção por arrasto da biblioteca roubava a rolagem da grade "Fotos". O seletor do sistema não tem o problema (conferido no iOS 18.6 e no iOS 27).
- Adicionar contato ficava em "Adicionando..." para sempre quando o cliente da pessoa não respondia à consulta de tipo de JID (o servidor entrega a consulta ao cliente de quem está online). Passou a valer "conta" depois de 10 segundos sem resposta e o fluxo segue.

## 0.0.1 (build 9) — 25/10/2026

### Corrigido
- Crash ao abrir um canal cujo histórico tem arquivo recebido sem o registro de informações do arquivo no banco (visto no build 8, iOS 18.7, ao abrir um canal de pets). O registro agora é criado vazio na hora, em vez de derrubar o app. A causa de o registro faltar não foi determinada.

## 0.0.1 (build 8) — 25/10/2026

Reúne também o que entrou nos builds 6 e 7. O build 7 pode travar ou cair ao abrir no iOS 27 com muita coisa para sincronizar; use o 8.

### Adicionado
- Número de membros (grupos) e de participantes (canais) ao lado de "Membros do Grupo" e "Participantes do Canal" nos detalhes, e em fonte pequena abaixo do nome no topo do chat.
- Na lista de membros do grupo, a sua própria conta aparece primeiro (sem link de perfil, seletor de afiliação nem remoção).
- Aviso no seletor de histórico do canal: a mudança vale na próxima vez que o app se reconectar ao canal.

### Alterado
- Avatar da conta na tela inicial maior (40 pt) no iOS 26 ou mais novo.
- Barra superior do chat no iOS 26 ou mais novo: o indicador de carregamento só ocupa espaço enquanto carrega (a bolha de vidro deixou de ficar larga), cadeado e telefone voltam ao rosa do isaCloud, e o cadeado aberto de canais públicos fica cinza (vermelho só onde o botão funciona).
- Citações em respostas: cada linha da mensagem original vira uma linha de citação, e linhas longas quebram com a barra `│` em cada linha visual.
- Textos dos detalhes de grupo, canal e contato em Title Case, com traduções em português: "Fixar Conversa", "Mídia Compartilhada", "Arquivos Compartilhados", "2 Dias", "Histórico ao Conectar", "Notificar Apenas Quando Mencionado" e outros.
- Notificações: canais em "só menções" deixam de notificar toda mensagem (um nome vazio casava com qualquer texto).

### Corrigido
- iOS 27: o app abre (ciclo de vida por cenas), conecta a conta e atualiza as conversas; a tela inicial recupera o layout (busca abaixo do título, sem bolha vazia).
- Lista de canais públicos que ficava carregando para sempre (a conta não conectava; também ganhou limite de 20 s e mensagem de erro).
- Crash ao abrir no iOS 27 causado pelo vigia de travamento do coletor de crashes; o vigia fica desligado no iOS 27 ou mais novo.
- Travamento ao abrir o app enquanto as contas sincronizam: o aviso de "primeiro plano" no início não espera mais as filas.
- Crash ao sincronizar quando o botão de carregamento da barra saía da tela.
- Chat aberto recebendo, no mesmo momento, mensagens de um dia novo e de um dia já exibido (causava erro de atualização da lista); a mistura agora entra em duas etapas. Ainda não reproduzido em teste, então é uma correção por hipótese.

### Conhecido
- Barra de citação por linha (e não uma única barra vertical): ver o roadmap, em "Por avaliar".
- Notificações "New Message / New Message?" no app de produção: dependem da entitlement de push filtering, pedida à Apple (ver "Pendências" no `CLAUDE.md`).

## 0.0.1 (build 5) — 24/10/2026

### Adicionado
- Busca de nomes na tela inicial: contatos, grupos e canais pelo nome, com resultado que abre a conversa.
- Avatar redondo da conta no botão de perfil, atualizado quando a foto muda (aqui ou em outro app com a mesma conta).
- Colar imagem da área de transferência pelo clipe, com aviso quando não há imagem.
- Cápsula "Enviando..." e spinner no topo ao enviar arquivo.
- Autocompletar de menções (`@`) em grupos e canais, com os participantes online.
- Citação em texto ao responder ("Responder" no menu de mensagens).
- Botão "Clear share sheet queue" na tela de debug.
- Lista de domínios do isaCloud compartilhada entre criação de conta e convites.

### Alterado
- Sincronização inicial de canais públicos: 2 dias por padrão, com a opção "2 days" no seletor.
- Compartilhar pelo iOS: folha de compartilhar em rosa, com textos do isaCloud; esquema de abertura separado por build.
- Executável do app renomeado para `isaCloud`; bundle e módulo Swift mantidos.
- Títulos das telas Conversas e Contatos inline; barra de busca de Contatos sempre visível.
- Endereços de crash e contato (`sysadmin@isacloud.cc`); links de Sobre, FAQ e Privacidade apontam para `isacloud.com.br`.
- Identificação do cliente para o servidor e rótulo das notificações passam a dizer "isaCloud".
- Convites: sem landing do servidor, um domínio do isaCloud monta a página `/register?t=`; os outros recebem o link `xmpp:`.

### Corrigido
- Foto recebida aparece na conversa aberta sem precisar sair e entrar.
- Crash ao trocar o avatar pelo iPhone (atualização do botão de perfil fora da thread principal).
- Mensagens em alguns menus (Copiar, Editar, Retrair, Moderar, Excluir localmente, Reenviar) passam a ter tradução.

### Conhecido
- Travamento na sincronização inicial de canais grandes: ver a seção "Pendências técnicas" do roadmap.

## Builds anteriores (TestFlight)
- Build 6 e 7: ver o início da seção do build 8.
- Build 1 a 4: primeiros envios ao App Store Connect, com as funções de caixa de mensagem, GIF, hats, busca de canais e compartilhamento em desenvolvimento.

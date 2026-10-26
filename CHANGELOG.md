# Changelog do isaCloud para iOS

Mudanças do fork isaCloud sobre o Monal. A lista do que está feito e do que falta está em [ROADMAP.md](ROADMAP.md).

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

# Voltar ao ponto em que você parou de ler (análise)

Status: **análise, sem implementação** (06/11/2026). Pergunta da Isadora: ao sair de um grupo ou canal depois de rolar um pouco para baixo a partir da linha "Lido até este ponto" (roadmap 153, build 94), ao voltar o chat já considera tudo lido. É possível guardar onde a pessoa parou de rolar e abrir ali na próxima visita?

Relacionado: `docs/feature-marcacao-leitura.md` (a linha), `docs/feature-abrir-na-primeira-nao-lida.md` (abertura na primeira não lida).

## Como a leitura funciona hoje

- Ao abrir o chat, `ChatViewHelpers.refreshCounter` (`ChatView.swift`, chamado em `onAppear` e nos outros pontos de atualização) marca **todas** as não lidas como lidas: `markMessagesAsReadForBuddy:... tillStanzaId:nil` (`ChatViewHelpers.m`, `DataLayer.m` ~2207).
- O estado de leitura é **um único ponteiro por conversa**, `buddylist.latest_read_message_history_id`. Uma mensagem é não lida se tem id maior que esse ponteiro e `unread=1` e `inbound=1` (`DataLayer.m` ~2364 e ~2463).
- Esse estado alimenta o contador, a bolinha da lista, o filtro "Não lidas", as notificações, o MDS (`MonalAppDelegate.m` ~905) e o marcador XEP-0333 (`XMPPMessage.m`).
- **Rolar não marca nada.** A leitura acontece só ao abrir (e em outros pontos de atualização). Por isso, ao voltar, tudo já está lido e o chat abre no fim, ou na primeira não lida, que já não existe mais.

Em resumo: o app sabe "até onde chegou o que existe", não "até onde você olhou".

## O que seria preciso para guardar a posição

1. **Um segundo ponteiro, só de posição.** Algo como `isacloud_reading_anchor`: o id da mensagem no topo da tela, por conta e conversa. Pode ficar no banco local, com migração na escada própria (`+migrateISACloudDB:`, `DataLayer.m`, flag `isacloud_dbversion`, passos que podem rodar de novo), ou em `UserDefaults`. Fica **separado** de `latest_read_message_history_id`, então contador, notificações e MDS não mudam.
2. **Saber qual mensagem está no topo.** O fork do ExyteChat informa hoje só se a lista está no fim ou no início (`UIList.swift` ~856: `isScrolledToBottom`, `isScrolledToTop`). Seria preciso expor a primeira linha visível (id da mensagem). É uma mudança pequena no fork, com PR próprio, em `isaCloud`, conforme `docs/exytechat-fork.md`.
3. **Gravar no momento certo.** Quando a rolagem para (com um atraso curto, para não gravar a cada movimento), ao sair do chat (`onDisappear`) e quando o app vai para segundo plano (`scenePhase`), porque o app pode ser encerrado sem passar por `onDisappear`.
4. **Abrir ali.** Se houver âncora e ela não for a última mensagem, usar o salto que já existe para a busca (`jumpToSearchedMessage`, que carrega do alvo até o que já está na tela). Não precisa ser feito de novo.

## Casos que precisam de regra

- **Âncora apagada ou retratada:** usar a mensagem mais próxima mais antiga; se não houver, o comportamento atual.
- **Âncora mais antiga que `maxMessagesToJumpOver` (3000):** o salto recusa; cair no comportamento atual.
- **Mensagens chegaram enquanto você estava fora:** a âncora continua no mesmo lugar, e as novas ficam abaixo dela.
- **Vários aparelhos:** a âncora fica só neste aparelho. Sincronizar pelo MDS seria outra decisão, com mais risco, e não é necessário para o caso descrito.
- **Conta removida ou conversa apagada:** a âncora deixa de ser usada e pode ser apagada junto com a conversa.

## Duas formas de fazer

- **A. Âncora separada (recomendada).** Guarda a posição sem mudar o que conta como lido. Muda só a abertura do chat. Risco baixo, e reversível: basta parar de gravar e de usar a âncora.
- **B. Leitura pela rolagem.** Marcar como lido só até a mensagem visível, em vez de tudo ao abrir. Mudaria contador, bolinha, filtro "Não lidas", notificações, MDS e XEP-0333. É o comportamento mais correto para o produto, mas é uma mudança grande, com risco alto e atrito com o Monal. Não recomendada agora.

## Decisão em aberto

Com a opção A, a linha "Lido até este ponto" passaria a marcar a âncora. A primeira não lida deixaria de ter linha própria. Ou seja, a linha mostraria onde a pessoa parou de ler, e não necessariamente a primeira mensagem não lida. Pergunta para a Isadora: manter as duas (a âncora e a primeira não lida) ou só a âncora?

## Próximo passo, se aprovado

1. Decidir a pergunta acima e a opção A ou B.
2. Se A: PR no fork do ExyteChat para expor a primeira linha visível; depois a âncora no app (banco com migração própria ou `UserDefaults`), a gravação nos três momentos e a abertura pelo salto da busca.
3. Testar com banco real (CLAUDE.md: validar rotina de banco com o banco oficial ou o do `.dev`, não só com linha fabricada), nos simuladores do iOS 18.6 e 27, e no `.dev`.

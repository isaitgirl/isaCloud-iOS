# Fork do ExyteChat

O chat do app (balões, lista de mensagens) é a biblioteca ExyteChat. O Monal usa o fork dele, `monal-im/ExyteChat`; o isaCloud usa um fork desse fork, para poder mudar o que a biblioteca desenha sem contornos no app.

```
exyte/Chat  →  monal-im/ExyteChat (main)  →  isaitgirl/ExyteChat (branch isaCloud)
```

- Repositório: `https://github.com/isaitgirl/ExyteChat`, branch **`isaCloud`** (é a única branch que o projeto usa; nunca a `main`, que acompanha o `monal-im/ExyteChat`).
- Revisão em uso: **`ad2740f`** (27/10/2026, componentes nativos na modal, emojis que quebram linha, reações no rodapé do balão como opção e a opção desligada por padrão; o PR do fork foi mesclado com rebase, por isso o SHA é o do `isaCloud` do fork, e não o dos commits do PR). Ela fica fixada em `Monal/Monal.xcworkspace/xcshareddata/swiftpm/Package.resolved`; o `project.pbxproj` só diz `branch = isaCloud`. **Depois de cada commit novo no fork é preciso atualizar essa revisão** (e fazer o push antes), senão o TestFlight compila a versão antiga.
- Clone de trabalho: `~/projects/swift/ExyteChat`, com os remotos `origin` (nosso fork) e `upstream` (`monal-im/ExyteChat`).
- O projeto referencia o pacote em `Monal/Monal.xcodeproj/project.pbxproj` (`repositoryURL` e `branch`) e `Monal.xcworkspace`/`Package.resolved` fixa a revisão.

O motivo da decisão (e as alternativas descartadas) está em `docs/decisoes.md`.

## O que o fork muda (só isto)

Cada mudança é pequena, comentada com "isaCloud:" no código e vive num commit próprio, para o rebase ser fácil.

1. **Ícones de status maiores** (`MessageView.swift`): `statusViewWidth` de 10 para 16 pt, mantendo o ícone alinhado pela base do balão. Esse valor também entra nas contas de largura do balão.
2. **Citação com uma barra só** (`Extensions/AttributedString+Quote.swift`, `MessageTextView.swift`, `MessageView.swift`): o app marca o texto citado com o atributo `quote` (`texto.quote = true`) e o balão desenha cada citação como um bloco com uma barra vertical contínua à esquerda. Mensagens com citação sempre põem a hora embaixo do texto.
3. **Menu da mensagem abre mais cedo** (`Views/UIList.swift`): o toque longo passa de 0,5 s (padrão do SwiftUI, sentido como ~0,6 s na lista) para `minimumDuration: 0.3`. A animação do menu não precisa de mudança na biblioteca: o app chama `.messageMenuAnimationDuration(0.15)` (padrão da biblioteca: 0,3 s) em `ChatView.swift`. Os GIFs, que o app desenha por conta própria, usam os mesmos 0,3 s em `GifMessageBubble`.
4. **Modal de quem reagiu** (`Model/ReactionGroup.swift`, `Views/MessageView/ReactionDetailsSheet.swift`, `MessageReactionView.swift`, `ChatViewModel.swift`, `ChatView.swift`, `ChatBuilderParameters.swift`, `ChatMessageView.swift`, `ChatLocalization.swift`): as reações do balão são agrupadas por emoji (um círculo por emoji, com selo de contagem quando mais de uma pessoa reagiu) e tocar nelas abre uma modal com uma linha por pessoa (emojis dela à direita, em faixa rolável; ordem alfabética), com filtro por emoji. A linha "Você" é sempre a primeira: cada emoji dela é um botão que remove a reação e um "+" abre o teclado de emojis do sistema para adicionar (`Views/MessageView/EmojiKeyboardField.swift`, um campo de texto invisível que pede o teclado de emojis; `Model/ReactionPeople.swift` agrupa por pessoa). Por padrão (opção desligada) cada reação é uma bolinha sobre o canto do balão e, nos balões de outras pessoas, o selo de contagem fica por cima do balão vizinho. Balões próprios do app (como o dos GIFs) abrem a mesma modal por `MessageBuilderParameters.showReactionDetailsClosure`. No app, `shouldShowOverviewFor` devolve `false`, porque a modal substitui a lista que aparecia no topo do toque longo. Testes em `Tests/ExyteChatTests/ReactionGroupTests.swift`. **Componentes nativos e rodapé (26/10/2026):** com a opção `ChatView.reactionsBelowBubble(true)` (o app liga pela preferência "Reações abaixo do balão", em Configurações → Interface do Usuário → Aparência; desligada por padrão) as reações do balão saem de cima dele e ficam no rodapé, centralizadas, em cápsulas nativas (`Button` com `.bordered` e `.capsule`, emoji e número juntos; no balão rosa as cápsulas são brancas e sólidas; passando de 5 emojis, o "+N" é mais uma cápsula). Na modal, os chips, o "+" e os emojis da linha "Você" são `Toggle` em estilo botão e `Button` bordered, e a lista é uma `List`, e os emojis de cada pessoa quebram a linha em quantas linhas precisar, alinhados à direita (`FlowLayout`, um `Layout` próprio: o SwiftUI não tem um HStack que quebra linha). O código dos balões redondos antigos (`reactionsView`, `overflowBubbleView`, `ReactionBubble`) continua, é o modo padrão.

## Fluxo de branches e PRs

- Toda mudança, no app e na biblioteca, nasce em um branch novo criado **a partir de `isaCloud`** (por exemplo `feature/reaction-details-sheet`) e volta por **PR do branch novo para `isaCloud`** do mesmo repositório. Nunca para `develop` (app) nem para `monal-im`.
- Todo PR tem a `isaitgirl` como revisora e responsável e traz **prints de antes e depois** das mudanças visíveis, feitos só com dados de teste (contas e conversas de teste, nunca conversas reais, porque as imagens ficam públicas). As capturas seguem a convenção de `CLAUDE.md` e entram no branch do PR (a pasta `docs/screenshots/` está no `.gitignore`, então use `git add -f`).
- Mudança que depende da biblioteca tem um PR par em cada repositório. O PR do app só pode ser mesclado depois do PR do ExyteChat, porque o app usa o branch `isaCloud` da biblioteca.
- Quem não tem permissão de escrita no `isaitgirl/ExyteChat` trabalha num fork próprio e abre o PR do fork para o `isaCloud` dela.
- Prints de reações e outros emojis: só em simulador sem o defeito de emoji (ver `docs/troubleshooting.md`, iOS 26.4 ou mais novo, ou 27.x).

## Como acompanhar o Monal e o ExyteChat

```bash
cd ~/projects/swift/ExyteChat
git fetch upstream
git checkout isaCloud
git rebase upstream/main      # ou: git merge upstream/main
# resolver conflitos (as nossas mudanças estão em poucos trechos de MessageView.swift e MessageTextView.swift)
git push --force-with-lease origin isaCloud     # só se usou rebase
```

Depois, no projeto isaCloud: atualizar a revisão fixada (Xcode → File → Packages → Update to Latest, ou apagar a entrada em `Package.resolved` e resolver), compilar nos simuladores iOS 18 e iOS 27 e conferir um chat com citação, GIF, foto e mensagens com os quatro ícones de status.

Se o Monal fixar o `monal-im/ExyteChat` numa versão nova, vale conferir em `Package.resolved` se a `develop` do Monal exige uma revisão mais nova que a do nosso fork antes de fazer o merge com o Monal.

## Se um dia o Monal ou o ExyteChat trouxerem o mesmo recurso

Ícones e citação com barra são candidatos a contribuição. Se o upstream implementar, basta descartar o nosso commit correspondente no rebase e adaptar o app.

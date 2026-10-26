# Fork do ExyteChat

O chat do app (balões, lista de mensagens) é a biblioteca ExyteChat. O Monal usa o fork dele, `monal-im/ExyteChat`; o isaCloud usa um fork desse fork, para poder mudar o que a biblioteca desenha sem contornos no app.

```
exyte/Chat  →  monal-im/ExyteChat (main)  →  isaitgirl/ExyteChat (branch isaCloud)
```

- Repositório: `https://github.com/isaitgirl/ExyteChat`, branch **`isaCloud`** (é o que o projeto usa).
- Clone de trabalho: `~/projects/swift/ExyteChat`, com os remotos `origin` (nosso fork) e `upstream` (`monal-im/ExyteChat`).
- O projeto referencia o pacote em `Monal/Monal.xcodeproj/project.pbxproj` (`repositoryURL` e `branch`) e `Monal.xcworkspace`/`Package.resolved` fixa a revisão.

O motivo da decisão (e as alternativas descartadas) está em `docs/decisoes.md`.

## O que o fork muda (só isto)

Cada mudança é pequena, comentada com "isaCloud:" no código e vive num commit próprio, para o rebase ser fácil.

1. **Ícones de status maiores** (`MessageView.swift`): `statusViewWidth` de 10 para 16 pt, mantendo o ícone alinhado pela base do balão. Esse valor também entra nas contas de largura do balão.
2. **Citação com uma barra só** (`Extensions/AttributedString+Quote.swift`, `MessageTextView.swift`, `MessageView.swift`): o app marca o texto citado com o atributo `quote` (`texto.quote = true`) e o balão desenha cada citação como um bloco com uma barra vertical contínua à esquerda. Mensagens com citação sempre põem a hora embaixo do texto.
3. **Modal de quem reagiu** (`Model/ReactionGroup.swift`, `Views/MessageView/ReactionDetailsSheet.swift`, `MessageReactionView.swift`, `ChatViewModel.swift`, `ChatView.swift`, `ChatBuilderParameters.swift`, `ChatMessageView.swift`, `ChatLocalization.swift`): as reações do balão são agrupadas por emoji (um círculo por emoji, com selo de contagem quando mais de uma pessoa reagiu) e tocar nelas abre uma modal com a lista de quem reagiu, com filtro por emoji. Balões próprios do app (como o dos GIFs) abrem a mesma modal por `MessageBuilderParameters.showReactionDetailsClosure`. No app, `shouldShowOverviewFor` devolve `false`, porque a modal substitui a lista que aparecia no topo do toque longo. Testes em `Tests/ExyteChatTests/ReactionGroupTests.swift`.

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

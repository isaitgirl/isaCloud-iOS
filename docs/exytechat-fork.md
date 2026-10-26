# Fork do ExyteChat

O chat do app (balões, lista de mensagens) é a biblioteca ExyteChat. O Monal usa o fork dele, `monal-im/ExyteChat`; o isaCloud usa um fork desse fork, para poder mudar o que a biblioteca desenha sem contornos no app.

```
exyte/Chat  →  monal-im/ExyteChat (main)  →  isaitgirl/ExyteChat (branch isaCloud)
```

- Repositório: `https://github.com/isaitgirl/ExyteChat`, branch **`isaCloud`** (é a única branch que o projeto usa; nunca a `main`, que acompanha o `monal-im/ExyteChat`).
- Revisão em uso: **`9f4e34e`** (26/10/2026). Ela fica fixada em `Monal/Monal.xcworkspace/xcshareddata/swiftpm/Package.resolved`; o `project.pbxproj` só diz `branch = isaCloud`. **Depois de cada commit novo no fork é preciso atualizar essa revisão** (e fazer o push antes), senão o TestFlight compila a versão antiga.
- Clone de trabalho: `~/projects/swift/ExyteChat`, com os remotos `origin` (nosso fork) e `upstream` (`monal-im/ExyteChat`).
- O projeto referencia o pacote em `Monal/Monal.xcodeproj/project.pbxproj` (`repositoryURL` e `branch`) e `Monal.xcworkspace`/`Package.resolved` fixa a revisão.

O motivo da decisão (e as alternativas descartadas) está em `docs/decisoes.md`.

## O que o fork muda (só isto)

Cada mudança é pequena, comentada com "isaCloud:" no código e vive num commit próprio, para o rebase ser fácil.

1. **Ícones de status maiores** (`MessageView.swift`): `statusViewWidth` de 10 para 16 pt, mantendo o ícone alinhado pela base do balão. Esse valor também entra nas contas de largura do balão.
2. **Citação com uma barra só** (`Extensions/AttributedString+Quote.swift`, `MessageTextView.swift`, `MessageView.swift`): o app marca o texto citado com o atributo `quote` (`texto.quote = true`) e o balão desenha cada citação como um bloco com uma barra vertical contínua à esquerda. Mensagens com citação sempre põem a hora embaixo do texto.

3. **Menu da mensagem abre mais cedo** (`Views/UIList.swift`): o toque longo passa de 0,5 s (padrão do SwiftUI, sentido como ~0,6 s na lista) para `minimumDuration: 0.3`. A animação do menu não precisa de mudança na biblioteca: o app chama `.messageMenuAnimationDuration(0.15)` (padrão da biblioteca: 0,3 s) em `ChatView.swift`. Os GIFs, que o app desenha por conta própria, usam os mesmos 0,3 s em `GifMessageBubble`.

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

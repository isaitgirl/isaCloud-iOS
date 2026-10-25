# Fork do ExyteChat

O chat do app (balões, lista de mensagens) é a biblioteca ExyteChat. O Monal usa o fork dele, `monal-im/ExyteChat`; o isaCloud usa um fork desse fork, para poder mudar o que a biblioteca desenha sem contornos no app.

```
exyte/Chat  →  monal-im/ExyteChat (main)  →  isaitgirl/ExyteChat (branch isaCloud)
```

- Repositório: `https://github.com/isaitgirl/ExyteChat`, branch **`isaCloud`** (é o que o projeto usa).
- Clone de trabalho: `~/projects/swift/ExyteChat`, com os remotos `origin` (nosso fork) e `upstream` (`monal-im/ExyteChat`).
- O projeto referencia o pacote em `Monal/Monal.xcodeproj/project.pbxproj` (`repositoryURL` e `branch`) e `Monal.xcworkspace`/`Package.resolved` fixa a revisão.

## O que o fork muda (só isto)

Cada mudança é pequena, comentada com "isaCloud:" no código e vive num commit próprio, para o rebase ser fácil.

1. **Ícones de status maiores** (`MessageView.swift`): `statusViewWidth` de 10 para 16 pt, mantendo o ícone alinhado pela base do balão. Esse valor também entra nas contas de largura do balão.
2. **Citação com uma barra só** (`Extensions/AttributedString+Quote.swift`, `MessageTextView.swift`, `MessageView.swift`): o app marca o texto citado com o atributo `quote` (`texto.quote = true`) e o balão desenha cada citação como um bloco com uma barra vertical contínua à esquerda. Mensagens com citação sempre põem a hora embaixo do texto.

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

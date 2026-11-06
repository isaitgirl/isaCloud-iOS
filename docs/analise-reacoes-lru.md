# Fileira de reações no menu da mensagem: LRU de 6 emojis (análise)

Status: **decidido (06/11/2026), opção A, ainda não implementado.** Pedido da Isadora: trocar a fileira padrão de reações do menu de contexto das mensagens em conversas por uma lista LRU (usados recentemente primeiro) de **6 emojis**, seguida de um botão para escolher outro emoji.

## Resumo

- A fileira é desenhada pela biblioteca ExyteChat (nosso fork), em `Sources/ExyteChat/Views/MessageView/MessageMenu/MessageMenu+ReactionSelectionView.swift`. A lista vem de `reactions(for:)`, que o app preenche pelo parâmetro `availableReactionsFor` do `onMessageReaction` em `Monal/Classes/ChatView.swift` (por volta da linha 1458).
- **O botão "escolher outro emoji" já existe:** é o `face.smiling` no fim da fileira, que abre o teclado de emojis do sistema. Ele aparece com `allowEmojiSearch`, que já é verdadeiro por padrão. Não precisa de código novo; só não desligar.
- **Opção escolhida (A): só no app.** Uma lista LRU de 6 emojis guardada em preferências, passada por `availableReactionsFor`. Nada muda no fork do ExyteChat.

## Opções avaliadas

| Opção | O que muda | Conflito com o Monal | Conflito com o fork | Risco |
|---|---|---|---|---|
| **A. Só no app (escolhida)** | Arquivo novo com a LRU (`@defaultsDB`, como `chatViewDefaultsDB` em `ChatView.swift`); `availableReactionsFor` devolve a LRU; `didReactTo` atualiza a LRU | Baixo: uma closure a mais em `ChatView.swift` e o arquivo novo no `project.pbxproj` | Nenhum | Baixo |
| B. Mudar `defaultEmojis()` no fork | Lista fixa na biblioteca; a LRU precisaria de um callback novo | Nenhum | Médio: PR par, nova revisão no `Package.resolved` | Médio |
| C. Refazer a fileira ou o `ViewState` | Código novo na biblioteca | Alto | Alto | Alto |

## Decisões

1. **Emojis da fileira padrão, nesta ordem:** ❤️ 👍 👎 😂 😨 🥲.
   - "Assustado" = 😨 (rosto assustado). Alternativa descartada: 😱.
   - "Lágrima no sorriso" = 🥲 (sorriso com lágrima).
2. **Atualização da LRU:** só quando o usuário **adiciona** uma reação, inclusive pelo botão de outro emoji (que entra no início e empurra o sexto item para fora). Tirar uma reação não muda a LRU.
3. **Reações próprias fora da LRU:** a biblioteca só mostra a lista que recebe. Se o usuário já reagiu com um emoji que saiu da LRU, sem essa regra ele não o veria na fileira e não conseguiria removê-lo. Decisão: as reações próprias do usuário naquela mensagem que não estão na LRU são **acrescentadas ao fim da fileira**, destacadas, para poder tirá-las. Só nesse caso a fileira passa de 6 itens (mais o botão de outro emoji).
4. **Escopo:** global (não por conversa) e **local ao aparelho**, guardado em preferências (não sincroniza entre dispositivos).

## Pontos de atenção

- **Variação de emoji:** ❤️ é U+2764 seguido de U+FE0F. Se o Conversations (ou outro cliente) enviar só U+2764, a reação aparece como outra e não fica destacada na fileira. Testar com uma reação vinda do Android antes de dar por fechado.
- **Largura:** 7 itens (6 + botão) no iPhone SE (largura menor) podem rolar em vez de caber. Conferir no iPhone XR e no iPhone SE, em iOS 18 e 27.
- **Merge com o Monal:** a mudança fica em `ChatView.swift` (arquivo já alterado no isaCloud) e num arquivo novo. Validar o diff antes de um merge com o Monal.
- **Registro:** quando a implementação sair, registrar a decisão em `docs/decisoes.md` e numa linha do `ROADMAP.md`.

## Próximo passo

Implementar a opção A (delegar ao `executor`, com o plano acima), testar nos simuladores iOS 18 e 27 e no `isaCloud.dev`, sem subir o número do build.

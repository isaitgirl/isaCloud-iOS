# Análise: compartilhar pelo contato sugerido do iOS

Status: **implementado em 05/11/2026** (branch `feature/compartilhar-pela-sugestao`, roadmap 152). A decisão final ficou com a opção "lista filtrada", proposta durante a conversa com a Isadora, em vez da "tela curta". Detalhes em `docs/decisoes.md`, seção "Compartilhar pelo contato sugerido do iOS".

## 1. O problema

Quando alguém compartilha de outro app tocando num contato da fileira de sugestões da folha do iOS, em vez de tocar no ícone do isaCloud, a extensão abre a mesma tela de sempre: busca, lista inteira, campo de mensagem e "Enviar". O contato até vem marcado, mas muitas vezes fica fora da tela, e parece que é preciso escolher de novo.

## 2. O que o código já fazia

- **Doação das conversas:** a cada mensagem que chega ou sai, o app doa ao sistema um `INSendMessageIntent` por conversa (`MLNotificationManager.m`, `makeIntentForMessage:`, `donateInteractionForIncomingDBId:` e `donateInteractionForOutgoingDBId:`). O `conversationIdentifier` leva o `MLContact` serializado, com o `accountID` dentro, e o `serviceName` leva o `accountID`.
- **Leitura na extensão:** o `ShareViewController.m` (`viewDidLoad`) lê o `extensionContext.intent`, desserializa o contato e o passa como `initialRecipient` ao `SharePickerView`, que marca a linha `accountID|jid` correspondente.
- **A sugestão já traz a conta.** Cada sugestão é uma conversa, ou seja, conta + contato. Se o mesmo contato estiver em duas contas, o iOS pode mostrar duas sugestões iguais na aparência, mas cada uma leva para a conta certa.

## 3. Opções avaliadas

| Opção | O que faz | Risco | Resultado |
|---|---|---|---|
| A. Tela curta | Uma tela só com o contato (foto, nome, conta), mensagem e "Trocar" | baixo, mas é mais uma tela | substituída pela lista filtrada |
| A'. Lista filtrada | A lista atual só com o endereço sugerido, uma linha por conta, com a da sugestão marcada e "Mostrar todos" | muito baixo; reaproveita linhas e envio | **escolhida** |
| B. Contato no topo | A lista inteira com o contato marcado no topo | quase zero, mas não pula a escolha | descartada |
| C. Enviar direto | Envia sem mostrar nada | sem mensagem, sem como desfazer um toque errado | descartada |

## 4. Como ficou

- O filtro (`focusJid`) só vale quando o contato sugerido está entre os destinos e dá para escrever nele. Se não estiver ou não der, abre a lista inteira, sem nada marcado.
- A busca e o "Mostrar todos" tiram o filtro. O "Mostrar todos" rola até a linha marcada.
- Arquivos: `Monal/shareSheet-iOS/SharePickerView.swift` e `ShareSheet.strings` (Base e pt-BR, com "Show all" = "Mostrar todos"). Nenhum arquivo do Monal muda.

## 5. Testes

- **Simuladores iOS 18.6 e 27 (05/11/2026):** o simulador não mostra a fileira de sugestões, então o caminho foi testado com a sala "teste" injetada no `ShareViewController.m`. Era um código temporário, que não foi commitado. Resultado: a sala apareceu nas duas contas, com a da sugestão marcada; "Mostrar todos" funcionou e a lista rolou até a linha; a busca procurou na lista inteira; sem sugestão, a tela ficou igual à de antes.
- **A conferir no iPhone:** a sugestão de verdade, inclusive quando o mesmo contato está em duas contas (se o iOS junta ou separa as sugestões).

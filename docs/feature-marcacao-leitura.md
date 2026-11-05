# Linha "Lido até este ponto" (marcação de leitura)

Status: **feita e no build 94 (05/11/2026)**, PR 44 (`feature/linha-lido-ate-aqui`). Roadmap 153. Complementa a abertura na primeira não lida (roadmap 136, `docs/feature-abrir-na-primeira-nao-lida.md`).

## O que faz

Quando um **grupo ou canal** abre na primeira mensagem não lida, aparece logo acima dela uma linha cinza clara (traço, texto, traço) com **"Lido até este ponto"**. A linha:

- fica enquanto o chat estiver aberto, sem acompanhar as mensagens novas que chegam;
- some quando o chat abre de novo, já com tudo lido (a abertura recalcula tudo);
- não aparece em conversas individuais (1:1), que não abrem na primeira não lida;
- não aparece quando o chat abre por um resultado de busca (a busca vence, como no salto);
- não aparece sem não lidas (o chat abre no fim, como antes);
- não aparece com **mais de 200 não lidas**, porque aí o chat abre na 200ª mensagem mais nova e a linha estaria no lugar errado.

## Como funciona (`Monal/Classes/ChatView.swift`)

1. **Onde a linha vai.** No `onAppear`, logo depois de `firstUnreadHistoryId(... maxMessages: 200)` decidir onde o chat abre, uma segunda chamada da mesma função, com `maxMessages: UInt.max`, devolve a primeira não lida verdadeira. Só se as duas forem iguais o id vai para `readMarker.historyId`. Isso roda antes do `refreshCounter`, que marca tudo como lido.
2. **Desenho.** O `messageBuilder` envolve a linha de cada mensagem num `VStack(alignment: .leading, spacing: 0)` e põe `ReadMarkerLine()` antes da bolha quando o `historyId` da mensagem é o guardado. A linha faz parte da linha da mensagem: não é uma mensagem falsa na lista (o ExyteChat derruba o app com dois ids iguais) e não muda o fork.
3. **Posição no salto.** Os dois scrolls do salto continuam com os mesmos tempos (0,1 s e 0,5 s) e a mesma posição (`.middle`). Quando há a linha, o segundo scroll ganha `readMarkerExtraOffset` (220 pt) a mais de deslocamento. A lista é invertida, então isso mostra mais do que vem antes e a linha cabe na tela mesmo quando a não lida é uma foto alta.
4. **Texto.** `NSLocalizedString("Read up to here", ...)`, com `"Read up to here" = "Lido até este ponto";` em `isaCloud/localization/pt-BR.lproj/Localizable.strings`.

## Armadilhas encontradas

- **`@State` não funciona aqui.** A lista do ExyteChat (`UIList`) guarda o `messageBuilder` da primeira vez que a tela é montada (no `makeCoordinator`), quando o marcador ainda está vazio. Com `@State var readMarkerHistoryId`, a linha nunca aparecia, embora o log confirmasse o id. A solução é guardar o id num objeto (`final class ReadMarker`) dentro de `@State`: a closure antiga e a nova veem o mesmo objeto.
- **Pedir a posição "no alto da tela" erra.** Com `.top` (o fork converte para a lista invertida), o scroll calcula a posição pelas alturas estimadas das fotos que ainda não apareceram, e o chat parou mensagens depois da linha. Usar `.top` só no segundo scroll também não deu certo. O deslocamento extra sobre o `.middle` foi o que funcionou, sem scroll a mais nem espera.
- **A posição varia um pouco** de uma abertura para outra, porque depende das alturas estimadas. No teste com 14 fotos não lidas, a linha e a foto apareceram inteiras em duas aberturas seguidas.

## Custo

A segunda consulta (`MIN(message_history_id)` das não lidas e um `COUNT`) foi medida no simulador com um log temporário (não commitado): 0,24 a 0,30 ms. A consulta que já existia levou de 1,1 a 5,2 ms.

## Descartado

- **O indicador próprio do ExyteChat** (`showLastReadIndicator`, `LastReadIndicatorView`, texto fixo "New messages" em vermelho). Ele usa o status `.readBy` das mensagens e insere uma linha a mais na tabela, com contas de índice em vários pontos do `UIList`. Exigiria mudar o fork (texto, cor, critério) e mapear o status das mensagens recebidas.
- **Mudar o `DataLayer`** para devolver também se o limite cortou: a segunda chamada resolve sem mexer no código compartilhado.
- **Esconder a linha no menu da mensagem:** o ExyteChat redesenha a linha inteira no destaque do toque longo, então a marcação aparece junto. É só visual, e a Isadora aceitou (05/11/2026).

## Testes

- Simulador iOS 18.6 (iPhone XR), sala "teste" da conta do `autozona.cc` com 14 não lidas (fotos): linha acima da primeira não lida, com a foto inteira na tela.
- Compilado no simulador do iOS 27 e no `.dev` do iPhone.
- **Falta:** um canal só de texto e um com mais de 200 não lidas (a linha não deve aparecer) no iPhone.

# Análise: OMEMO "Invalid Message" com sessão fora de sincronia (15/11/2026)

Não é crash. Registrado aqui porque um testador viu mensagens criptografadas falharem por cerca de 8 minutos. Build de referência: 109. Mudança feita no branch `fix/omemo-reparo-antecipado` (build 110).

## Sintoma

Mensagens OMEMO de um contato chegavam com erro de decifragem (`org.whispersystems.SignalProtocol Code=7 Invalid Message`, `isPreKey=NO`). Depois de um tempo tudo voltava ao normal sem ação do testador.

## Linha do tempo (logs do testador)

- 13:54:50: primeiro erro `Invalid Message` de uma mensagem do contato.
- Entre o primeiro erro e o fim do catch-up, o app marcou a sessão com aquele aparelho do contato como quebrada e colocou o reparo em `queuedSessionRepairs`. Como o catch-up ainda não tinha terminado, o reparo só ficou na fila.
- 14:02:45: o catch-up terminou e `repairQueuedSessions` rodou: buscou o bundle do aparelho e enviou um KeyTransportElement para reconstruir a sessão. Espera de cerca de 8 minutos.
- Depois do KeyTransport o contato respondeu (14:36) e as mensagens voltaram a decifrar.
- Em paralelo apareceram 24 erros `Duplicate Message` (Code=3), reentregas do histórico depois de reconexão sem retomada de stream management, e 11 avisos de que o app não confiou em um dos aparelhos próprios.

## Causa

O contato tem 8 aparelhos, muitos antigos. A mensagem chegou cifrada com um estado de sessão que não bate com o que temos para aquele aparelho dele. As sessões saíram de sincronia do lado do contato. Isso é do protocolo e do aparelho do contato: o app não tem como consertar o estado que o outro lado usa. O que o app pode fazer é reconstruir o *nosso* lado e pedir ao contato uma nova troca de chaves.

Não é bug do app: o Signal recusou a mensagem corretamente, porque a chave não bate.

## O que o app fez e por que demorou

O app já reconstrói a sessão quando a decifragem falha (`-[MLOMEMO rebuildSessionWithJid:forRid:]`, `Monal/Classes/MLOMEMO.m`). Enquanto `catchupDone` for NO, ele só enfileira o reparo, porque durante o catch-up chegam mensagens antigas e reentregas, e tentar reparar com elas geraria reparos desnecessários. A fila só roda no fim do catch-up inteiro, que nesse caso demorou 8 minutos.

## O que foi mudado (build 110)

- **Limite de reparo por (jid, rid):** no máximo 1 tentativa a cada 5 minutos, com um dicionário em memória protegido por `@synchronized(self)`. Serve para nunca gerar KeyTransportElements em laço quando o contato insiste em cifrar com um estado que não temos.
- **Reparo antecipado: não entrou.** Para disparar o reparo antes do fim do catch-up seria preciso saber se a mensagem com erro é nova ou reentregue do histórico. O código não tem um marco por jid para isso: `catchupDone` é da conta inteira, e as mensagens do histórico chegam pelo mesmo caminho. Sem esse critério seguro, o disparo antecipado ficaria arriscado (mais reparos, e possivelmente reparos desnecessários com mensagens antigas), então ficou de fora. Ver `docs/decisoes.md`.
- **Duplicatas (Code=3): nada mudou.** O código já retorna antes de `rebuildSessionWithJid` quando o erro é `Code=3` (`MLOMEMO.m`, bloco `Deduplicated normal message via omemo`). Não enfileira reparo nem loga como falha.
- **Não mexido:** o aviso de aparelho próprio não confiável, que ficou para investigar depois.

## Ressalvas

- O desencontro de sessão é do contato. O limite não conserta isso; só evita que o app piore a situação.
- A primeira mensagem com erro continua chegando com erro. Só as seguintes podem se beneficiar de um reparo.
- Como o disparo antecipado ficou de fora, o limite de 5 minutos hoje só age sobre reparos disparados depois do catch-up. O caso de 8 minutos do testador continua igual até existir um marco seguro por jid.
- Risco de reparos em excesso: por isso o limite.
- Só dá para provar o efeito com uma troca real entre dois aparelhos. O simulador prova apenas que compila.

## Como validar

1. Dois aparelhos com a mesma conta OMEMO, e um contato que aceite mensagens cifradas.
2. Provocar uma sessão quebrada (por exemplo, reinstalar um dos aparelhos sem apagar a conta no outro).
3. Ler o log do aparelho: depois de um erro `Invalid Message`, deve aparecer `Trying to repair session with deviceid ...` logo em seguida, fora do catch-up.
4. Gerar novos erros dentro de 5 minutos para o mesmo aparelho: deve aparecer `Not repairing session ... again` e nenhum novo KeyTransportElement.
5. Depois de 5 minutos, um novo erro deve disparar um novo reparo.

## Como desfazer

Remover o bloco `isaCloud: rate limit` em `rebuildSessionWithJid:forRid:` e a propriedade `sessionRepairAttempts`. O comportamento volta ao do Monal.

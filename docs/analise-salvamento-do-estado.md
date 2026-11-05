# Análise: salvamentos lentos do estado da conta (04/11/2026, roadmap 131)

Resultado da coleta pedida no roadmap 131 e o plano para o que fazer (ou não) com ele. Nada foi implementado.

## Dados (iPhone da Isadora, produção, 04/11/2026 07:38 a 10:47, builds 87 e 88, duas contas)

Fonte: três `.rawlog` do grupo do app, filtrando `isaCloud: slow persistState serialization` e `isaCloud: slow realPersistState` (limite de 50 ms). O arquivo em escrita sai truncado pelo `devicectl` (ver `docs/troubleshooting.md`).

- **5.213 salvamentos acima de 50 ms** em ~3 h, somando ~600 s de serialização (~5,5% do tempo).
- **Conta `im.isacloud.cc` (conta 9):** ~170 KB (169 a 179 KB), mediana 87 ms, p90 103 ms, p99 139 ms. **Conta `xmpp.social.br` (conta 47):** ~100 KB, mediana 54 ms, p99 137 ms. A serialização (`NSKeyedArchiver`, `HelperTools serializeObject:`) é quase todo o tempo do `realPersistState` (596 s de 618 s).
- **Um salvamento por stanza:** cada stanza é tratada na própria transação (`Starting transaction for: <presence/>` ... `Ended transaction`), e a transação termina com um `realPersistState`. Picos de **17 por segundo** e **340 por minuto**, nas rajadas de presença de salas grandes (ex.: `conversations@conference.siacs.eu`, com 170 a 230 stanzas na fila de parse).
- **Extremos:** 32 salvamentos acima de 200 ms. Os maiores (143 s, 26 s, 24 s, 17 s, 14 s, 9,5 s) **não são CPU**: o app foi congelado no meio do salvamento (buracos de até 143 s no log e `Write transaction blocking took 142.97 s`). É o cenário do `0xdead10cc`.
- **Sem `0xdead10cc` desde 02/11 13:48 (build 81)**: as correções dos builds 82 a 85 seguram (ver `docs/analises-crashes.md` e `scripts/classificar-crashes.py`).
- **Contexto dos lentos:** nenhum durante catchup nem com consulta MAM; 89% com stanzas sem confirmação (`unAckedStanzas > 0`). O estado tem `mdsData` (157 itens na conta 9, 70 na 47), `mucState` (10) e `pubsubData` (2), tamanho estável ao longo das 3 h.

## O que o código faz hoje (`xmpp.m`)

- `-persistState` já **junta** todos os salvamentos de uma mesma transação num só: abre uma transação de escrita e registra um gatilho de fim de transação (`addEndTransactionTrigger`) que chama `-realPersistState` uma vez.
- `-realPersistState` monta o dicionário inteiro (contadores do Stream Management, `unAckedStanzas`, `iqHandlers`, `serverFeatures`, `mdsData`, `mucState`, `pubsubData`, `omemo.state`...) e `DataLayer persistState:forAccount:` o serializa e grava (`UPDATE account SET state=?`) dentro da transação do stanza.
- Então o custo não vem de salvar várias vezes dentro de uma transação, e sim de **haver uma transação por stanza** e de **cada serialização custar ~87 ms para 170 KB** (lento: ~2 MB/s).

## Conclusões

1. **Não implementar "salvar só no fim da rajada" (debounce por tempo).** O estado guarda os contadores do Stream Management (`lastHandledInboundStanza`), o estado do OMEMO e os handlers de IQ, que precisam sair junto com o commit das mudanças do stanza. Adiar o salvamento deixaria o contador inconsistente com o banco se o app caísse no meio (mensagem aceita pelo servidor e perdida, ou reenvio e duplicatas). O ganho não compensa o risco.
2. **O ganho possível é pequeno.** A serialização é ~5,5% do tempo e a maior parte do tempo com o banco aberto é o processamento do próprio stanza. Sem `0xdead10cc` desde 02/11, não há urgência.

## Plano (por etapas, parando quando não compensar)

1. **Medir (barato, não muda comportamento):** código temporário `//TEMP-MEDIÇÃO` (não commitar), no `.dev`: tempo de serialização por parte do estado (`mdsData`, `mucState`, `pubsubData`, `omemo.state`, `serverFeatures` etc.) e arquivar versus gravar no SQLite.
2. **Se uma parte "fria" domina:** guardar o arquivamento dessa parte em cache e refazê-lo só quando ela mudar, sem mudar **quando** se salva. Mexe em `xmpp.m` e no formato do estado (sobe `STATE_VERSION`, hoje 7020, o que invalida o estado e força uma reconexão completa uma vez); **validar o atrito com o Monal antes** e registrar em `docs/decisoes.md`.
3. **Só se os dados pedirem:** processar vários stanzas por transação (o "lote"), com teto de tempo e de quantidade, para o contador e o estado continuarem saindo juntos no commit. É a mudança mais invasiva na fila de recebimento do Monal e a que pior se funde; fica por último.

Antes de qualquer rotina de banco, validar com banco real (regra do `CLAUDE.md`).

## Como repetir a coleta

```bash
xcrun devicectl device copy from --device <UDID> --domain-type appGroupDataContainer --domain-identifier group.br.com.isacloud.messenger --source Library/logs --destination <pasta>
python3 scripts/classificar-crashes.py --pull <UDID> --dir <pasta> --since AAAA-MM-DD
```

As linhas `slow` aparecem com `"message":"isaCloud: slow ..."`; o formato do `.rawlog` e a armadilha do arquivo truncado estão em `docs/troubleshooting.md`.

## Decisão (05/11/2026)

A Isadora decidiu manter como está. As etapas 2 e 3 do plano só voltam se os `0xdead10cc` voltarem.

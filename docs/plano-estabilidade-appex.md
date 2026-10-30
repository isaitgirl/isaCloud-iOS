# Estabilidade da extensão de notificação (plano de controle)

**Criado em 30/10/2026**, depois de uma sequência de builds em que a extensão de notificação
(`NotificationService.appex`) derrubou o app várias vezes enquanto a correção era tentada por
hipótese. Este documento existe para **parar de iterar no telefone da Isadora** e passar a
trabalhar com reprodução, medição e uma mudança por vez.

## Por que este caso pede controle

A appex roda **a cada push**, sem interface, com orçamento de memória pequeno e ciclo de vida
controlado pelo iOS. Um erro nela não aparece como tela quebrada: aparece como **notificação que
não chega**, **app que "fecha sozinho"** ou **relatório de crash** que ninguém lê na hora. Com mais
gente usando o app de produção, cada build enviado ao TestFlight é um teste em campo.

## Linha do tempo do problema

| Data | Build | Sintoma | Ação |
|---|---|---|---|
| 29/10 | 54, 57, 63 | `RUNNINGBOARD 0xdead10cc`: appex suspensa segurando lock de arquivo do SQLite | diagnóstico |
| 30/10 (manhã) | 66, 67 | a appex passou a **fechar o banco** ao entregar a notificação | tentativa de correção |
| 30/10 | 68 | **5 relatórios** de `SQLite3Exception: 7: out of memory` na appex | investigação |
| 30/10 | 70 | idem, **29 exceções em um único log** | reversão |

## Evidência (log da appex, 30/10, build 68/70)

Um único arquivo `UnifiedReport-log-*.rawlog` contém **29 ocorrências** do mesmo padrão:

```
…closed database connection …/sworim.sqlite          ← fechamento feito pelo app
Last push expired shutting down in 1500ms
activity: memory used 35.7MiB / available 59.4MiB
SQLite Exception: 7 out of memory for query 'BEGIN IMMEDIATE TRANSACTION;'
Database opened … / isaCloud: appex opened the database   ← reabre e falha
```

Interpretação: a conexão era fechada, algo escrevia no banco 300–800 ms depois (durante a janela
de encerramento de 1,5 s), a reconexão precisava alocar memória **no momento em que a extensão já
está no limite** (≈35 MB usados, ≈59 MB disponíveis) e o SQLite devolvia `SQLITE_NOMEM` (código 7),
que vira `SIGABRT`.

**Conclusão:** o fechamento do banco introduzido no 66 **foi a causa direta** desses crashes. Antes
dele o sintoma era o `0xdead10cc` (mais brando: o iOS mata a appex, sem crash report em cascata e
sem risco de perder o trabalho de entrega).

## Decisão do build 71

- **Reverter todo o fechamento de banco na extensão** (comportamento de volta ao pré-66): o lock
  fica aberto até o processo sair, e é o `exit(0)` do `killAppex` que o libera.
- Remover também a API `closeDatabasesForCurrentThread`/`closeAllDatabases` do `MLSQLite`, para
  ninguém reaproveitá-la sem o contexto deste documento.
- **Manter** o que é comprovadamente seguro e independente: logs/métricas/crash reports em
  `Library` (legíveis pelo `devicectl`), teto de 2 MB na cópia do log no crash (com o profile de
  cobertura indo inteiro), remoção do atraso de 1 s na limpeza do placeholder, correção do
  `disconnectAll` × appex congelada e o desligamento do vigia do KSCrash em produção.

## Plano para daqui em diante

### Fase 1 — reproduzir localmente (sem o telefone da Isadora)

- `xcrun simctl push <udid> br.com.isacloud.messenger payload.json` entrega um push falso e
  **executa a appex de verdade** no simulador.
- Com o log em `Library/logs` e as métricas em `Library/metrics`, medir por etapa: abertura do
  banco, conexão das contas, entrega do handler, janela de 1,5 s, saída.
- Critério de sucesso da fase: reproduzir o `0xdead10cc` **no simulador**.

### Fase 2 — medir a memória da appex

- Instrumentar o pico (`os_proc_available_memory`) por etapa.
- Testar, no harness e não no telefone: cache do SQLite menor na appex, evitar a inicialização
  completa do `MLXMPPManager` quando o push não precisa dela, e o efeito de cada uma.
- Critério: nenhuma alocação falhando durante o ciclo completo, com margem registrada.

### Fase 3 — só então voltar a mexer em fechar o banco

Se ainda for necessário para o `0xdead10cc`, com o harness cobrindo o caso e uma medição antes e
depois — nunca por hipótese.

## Regras que valem a partir daqui

1. **Nenhuma mudança de ciclo de vida da appex sobe sem reprodução no simulador.** Se não der para
   reproduzir, a mudança não vai para o TestFlight.
2. **Uma mudança por build**, com hipótese escrita antes e resultado medido depois.
3. **O `.dev` é o campo de provas**; o TestFlight recebe o que passou pelo harness.
4. Toda mudança em `MLSQLite`/appex entra com: o que foi medido, o que se espera, como reverter.
5. Quando o resultado não confirmar a hipótese, **reverter primeiro** e só depois investigar de
   novo — o telefone da Isadora não é lugar de dúvida.

## O que ainda está aberto

- `0xdead10cc` na appex (voltou a ser o único sintoma dela).
- Origem real das esperas longas pelo banco (flags `db_lock_max_background`/`db_lock_max_suspect`
  já separam suspensão de contenção).
- Crash do `MLAssert` de `disconnect`/congelamento: corrigido no 68, precisa de confirmação em uso.

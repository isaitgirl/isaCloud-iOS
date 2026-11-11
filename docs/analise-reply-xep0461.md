# Análise: resposta de verdade (XEP-0461, Message Replies)

Escrita em 10/11/2026. Só análise, sem código.

## 1. Onde estamos

**No Monal:** nada iniciado. A `develop` de 10/11/2026 (`ac4a74a3e`) não tem `urn:xmpp:reply:0` em lugar nenhum, e o gesto de deslizar continua comentado na `ChatView.swift` deles. A issue `monal-im/Monal#1671` está aberta, com o rótulo "Chat-UI Rewrite". O comentário de 16/08/2026 diz que ela sai no **Monal 7.0**, junto com a nova interface de chat, sem data. O Monal usa `urn:xmpp:fallback:0` (XEP-0428) só para reações (`MLMessageProcessor.m`, envio em `xmpp.m`).

**No isaCloud iOS:**
- O gesto de deslizar e o "Responder" do menu existem desde o build 30 (`onSwipeToReply`). O ExyteChat está em `replyMode: .quote`.
- A citação vai como **texto no corpo** (`> autor` e `> texto`), formatada por `QuoteFormatting.swift`. Quem recebe vê a citação desenhada a partir desse texto.
- Desde o build 96, quando a mensagem citada é foto, GIF ou figurinha, a resposta leva também `<isacloud-quote xmlns='urn:isacloud:quote:0' id='…'/>`:
  - o `id` é o `stanza-id` em grupo e canal e o `id` da mensagem em 1:1 (`QuoteFormatting.quotedMessageId`);
  - fica na coluna `isacloud_quote_id` de `message_history`;
  - é lido em `MLMessageProcessor.m` e enviado em `xmpp.m`;
  - serve para mostrar a miniatura (`historyIdOfQuotedMessageId` no `DataLayer.m`).

**No isaCloud Android (`isaCloudMessenger`, 08/11/2026):** lê e manda o mesmo `isacloud-quote` (`IsacloudQuote.java`, `Namespace.ISACLOUD_QUOTE`). Não tem `urn:xmpp:reply:0`.

**Ou seja:** o nosso elemento já é uma "XEP-0461 particular", só para mídia e só entre os nossos apps. A XEP-0461 é a versão padrão disso, para qualquer mensagem e qualquer cliente.

## 2. O que a XEP-0461 pede

```xml
<message to='sala@conference.isacloud.im' id='abc' type='groupchat'>
  <body>&gt; Ana
&gt; Vamos fazer um bolo?
Boa ideia!</body>
  <reply xmlns='urn:xmpp:reply:0' to='sala@conference.isacloud.im/Ana' id='STANZA-ID-DA-ORIGINAL'/>
  <fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
    <body start='0' end='31'/>
  </fallback>
</message>
```

- **`<reply>`:**
  - `id` aponta a mensagem respondida. Em grupo e canal é o `stanza-id` dado pela sala (XEP-0359); em 1:1 é o `id` da mensagem. É **a mesma regra** que o `isacloud-quote` já segue.
  - `to` diz quem escreveu a original: o JID da pessoa em 1:1 e `sala/apelido` em grupo.
- **`<fallback>` (XEP-0428):** marca o trecho do corpo que é só a citação. Clientes sem suporte mostram o corpo inteiro, como hoje. Clientes com suporte escondem o trecho e desenham a citação a partir da mensagem original.
- **Atenção às posições `start` e `end`:** a contagem é em caracteres Unicode, não em bytes nem em UTF-16 (conferir a regra exata na XEP-0426 antes de implementar). Emoji no texto é o caso que quebra se contar errado. Precisa de teste de unidade.
- **Com OMEMO:** o Monal criptografa só o `<body>`. O `<reply>` e o `<fallback>` vão **em aberto**, como o `isacloud-quote` já vai. Isso expõe só o ID da original, nunca o conteúdo. As posições do `fallback` valem para o corpo já descriptografado.

## 3. O que melhora para quem usa

1. **Resposta a qualquer mensagem** (texto, áudio, arquivo, localização), não só a foto, GIF e figurinha.
2. **Tocar na citação leva à mensagem original.** O pulo até a mensagem já existe na busca (build 33).
3. **A citação aparece desenhada acima do balão,** com autor e trecho ou miniatura, em vez das linhas `>` no texto. O ExyteChat já sabe fazer isso: `Message.replyMessage` desenha um balão de resposta acima da mensagem (`MessageView.swift`).
4. **Resposta com áudio passa a fazer sentido.** Hoje o áudio não leva citação, porque o corpo dele é a URL (ver `docs/decisoes.md`). Com o `<reply>`, o áudio aponta a original sem mexer no corpo.
5. **Notificações mais limpas:** o texto da notificação sai sem a parte citada.
6. **Conversa com outros clientes:** pelo que sei, Dino, Cheogram, Gajim e Movim usam a XEP-0461 (não conferi versão por versão). Os nossos apps passariam a mostrar as respostas deles direito, e eles as nossas.
7. **Possível bônus no servidor:** `docs/decisoes.md` cita a XEP-0461 entre as formas de detectar menção no módulo de push do Prosody. Uma resposta a uma mensagem minha poderia contar como menção nos canais em "só menção". **Conferir no `mod_cloud_notify_quiet`.**

## 4. Proposta em fases

### Fase 1: protocolo (cerca de 1,5 a 2 dias)
O app passa a falar a XEP-0461, sem mudar a aparência ainda.
- **Enviar** `<reply>` e `<fallback>` em **toda** resposta. O ID sai da mesma regra de hoje (`quotedMessageId`), mas para qualquer tipo de mensagem. O `to` sai do autor da original.
- **Continuar enviando o `isacloud-quote`** nas respostas a mídia enquanto o Android não ler a XEP-0461 (seção 5).
- **Receber:** ler `{urn:xmpp:reply:0}reply@id`, com o `isacloud-quote` como alternativa, e guardar o ID. **Reaproveitar a coluna `isacloud_quote_id`**, que já guarda exatamente isso, para não criar uma migração nova; só muda o significado para "ID da mensagem respondida". Guardar também as posições do fallback, ou recalcular na exibição.
- **Testes de unidade:** posições com emoji e acentos, 1:1 contra grupo, resposta sem ID conhecido (a própria mensagem ainda não confirmada pela sala, que é o mesmo limite de hoje).

### Fase 2: exibição (cerca de 2 a 3 dias, com o fork do ExyteChat)
- Quando a resposta tem ID **e a original existe no aparelho:**
  - montar o `replyMessage` do ExyteChat (autor, trecho ou miniatura) e esconder o trecho do fallback no corpo;
  - se a original foi apagada, mostrar "mensagem apagada".
- Quando a original **não existe no aparelho** (histórico antigo, entrou depois na sala): mostrar o fallback como hoje.
- **Tocar no balão de resposta** pula até a original, reaproveitando o pulo da busca. O toque precisa de um ajuste no fork do ExyteChat.
- **Mudar para `replyMode: .answer` ou só preencher o `replyMessage`:** decidir com protótipo. O `.answer` muda onde a resposta aparece na lista, o que provavelmente não queremos.
- **A miniatura de foto, GIF e figurinha (build 96)** passa a usar esse mesmo caminho.

### Fase 3: arremates (cerca de 0,5 a 1 dia)
- Notificação sem o trecho citado (a extensão de notificação também precisa ler o fallback).
- Áudio respondendo a uma mensagem: o cabeçalho de resposta acima do balão do áudio.
- Conferir e, se for o caso, ajustar a detecção de menção por resposta no módulo do Prosody.

**Total no iOS: cerca de 4 a 6 dias.** O Android tem um trabalho parecido (o Conversations já tem o modelo de `fallback`), mas eu não estimei.

## 5. Transição com o Android

1. **iOS e Android passam a ler `<reply>`**, e continuam lendo `isacloud-quote`.
2. **Os dois passam a enviar `<reply>` e `<fallback>`** em toda resposta, e continuam enviando `isacloud-quote` nas respostas a mídia.
3. **Depois de alguns builds com os dois apps atualizados**, param de enviar `isacloud-quote`. **A leitura fica para sempre**, para as mensagens antigas continuarem com miniatura. Isso já está no guia `docs/citacao-com-miniatura-android.md`.

A ordem importa: se um app parar de mandar `isacloud-quote` antes de o outro ler `<reply>`, a miniatura some entre eles.

## 6. Riscos

- **Conflito com o Monal 7.0.** Quando o Monal implementar a XEP-0461 na nova interface, o merge vai bater em `MLMessageProcessor.m`, `xmpp.m`, `DataLayer.m` e `ChatView.swift`. Como mitigação:
  - manter o código em blocos `isaCloud:` bem marcados e pequenos;
  - seguir **o formato padrão** à risca, para que os dados no fio sejam iguais aos do Monal;
  - na hora do merge, ficar com a implementação deles e migrar a nossa coluna para a deles.
- **Posições do fallback erradas** cortam texto da resposta ou deixam pedaço da citação. Os testes de unidade da fase 1 cobrem isso.
- **Citação de mensagem fora do histórico local:** cai no fallback, que é o comportamento de hoje. Não piora nada.
- **ID da própria mensagem em grupo antes do eco da sala:** sem `stanza-id`, a resposta vai só com o fallback. É o mesmo limite do `isacloud-quote`.

## 7. Compatibilidade com a análise do Android (10/11/2026)

Comparação com `docs/decisoes-reply-real-android.md`. **No protocolo, as duas análises batem.** As diferenças estão na exibição e em pontos que o Android levantou e o iOS não tinha:

| Tema | iOS (este doc) | Android | Combinado |
|---|---|---|---|
| Elementos | `<reply>` + `<fallback>`, mais `isacloud-quote` na transição | o mesmo | igual |
| `isacloud-quote` | só para foto, GIF e figurinha | o mesmo | igual |
| ID em 1:1 | `messageid` do Monal, que já é o `origin-id` (o Monal manda os dois iguais; ver `MLMessageProcessor.m`) | `origin-id`, senão o `id` do stanza | compatível |
| ID em grupo e canal | só `stanza-id`; sem ele, só citação em texto | o mesmo | igual |
| `to` | do autor da original | o mesmo; na **própria** mensagem, o JID da própria conta | **adotar a regra do Android** |
| Banco | reaproveitar `isacloud_quote_id` | colunas novas `replyToId` e `replyToTo`, mantendo `isacloudQuoteId` | decisão local, sem efeito no fio |
| Leitura | `<reply>`, senão `isacloud-quote` | o mesmo | igual |
| Quando mandar | se o texto ainda contém a citação | só se o corpo **começar** com a citação; se a pessoa apagar a citação, nada de `<reply>` | **adotar a regra do Android** |
| Exibição | balão de resposta do ExyteChat acima do texto, escondendo o fallback | manter o bloco citado atual e torná-lo clicável; cartão separado só quando chega `<reply>` sem fallback | **adotar a regra do Android** (abaixo) |
| Resposta com áudio | o iOS já manda a citação em texto e o áudio logo depois | "responder com mídia" fica para depois | o `<reply>` vai **na mensagem de texto** com a citação, nunca no áudio |
| Rótulo do menu | "Responder" | pergunta se fica "Quote" ou vira "Reply" | **"Responder" nos dois** |

**Pontos que o Android levantou e entram também no iOS:**
- **Anunciar `urn:xmpp:reply:0` nas capacidades (disco).** A XEP pede isso. No iOS é uma linha na lista de `HelperTools.m`, perto de `urn:xmpp:fallback:0`.
- **Conferir se o MAM do isacloud.im guarda `<reply>`, `<fallback>` e `isacloud-quote`.** Sem isso, o clique só funciona em tempo real.
- **Retração ou exclusão da original:** mostrar "mensagem original indisponível", sem quebrar o clique.
- **Mensagem antiga com só `isacloud-quote`:** ao responder a ela, derivar o `to` da original local.

**Exibição: por que seguir o Android.** Manter o bloco citado que já temos e só torná-lo clicável é mais barato e menos arriscado do que trocar pelo balão de resposta do ExyteChat:
- mantém a miniatura do build 96 do jeito que está;
- deixa os dois apps com a mesma cara, como combinamos para o Android;
- evita citação em dobro.

O balão separado fica só para quando chega `<reply>` **sem** fallback, de um cliente externo. Isso reduz a fase 2 do iOS: o grosso passa a ser o toque no bloco e o pulo até a original.

**Ponto crítico a combinar entre os dois apps: como contar as posições do fallback.** As posições `start` e `end` precisam ser contadas do mesmo jeito nos dois apps:
- em Java, `String.length()` conta unidades UTF-16;
- em Swift, `String.count` conta caracteres visíveis;
- a XEP-0426 manda contar **pontos de código Unicode** (confirmar na XEP antes de implementar).

Os próprios rótulos mostram o problema: `🎞️ GIF` começa com 2 pontos de código, que são 3 unidades UTF-16 e 1 caractere visível. Se cada app contar de um jeito, um corta texto da resposta do outro. **Combinar:** os dois contam pontos de código, com o mesmo teste de unidade nos dois (uma citação com `🎞️` e acento).

**Respostas para as decisões pendentes do Android, do ponto de vista do iOS:**
1. Mandar `<reply>` e `isacloud-quote` juntos na transição: **sim, os dois.**
2. Bloco clicável em vez de cartão: **bloco clicável.**
3. Ícone de play na miniatura de vídeo: decisão de interface; se entrar, entra nos dois apps.
4. Duração no áudio: dá para fazer no iOS também, se o arquivo estiver no aparelho.
5. "Responder com mídia": **depois.** O iOS já tem o caminho "citação em texto e depois o áudio".
6. Rótulo: **"Responder".**
7. Carregar histórico ao tocar quando a original não estiver na tela: **sim, uma página**, como o pulo da busca.

**Estimativas:** com a exibição do Android, o iOS fica em cerca de **3 a 5 dias**. A análise do Android estima **7 a 10 dias** para o MVP de lá, porque ela inclui vídeo e áudio no cartão e uma matriz de testes maior.

## 8. Recomendação

Dá para fazer sem esperar o Monal, e boa parte da base já existe: a regra do ID, a coluna, o gesto, a miniatura, o pulo até a mensagem e o balão de resposta do ExyteChat.

Sugestão: **fazer a fase 1 primeiro e combinar com o Android**, porque ela é invisível, barata e destrava a interoperabilidade. Depois decidir a fase 2 com um protótipo no `.dev`. O maior custo é o risco de merge com o Monal 7.0, que é mitigável se seguirmos o padrão à risca.

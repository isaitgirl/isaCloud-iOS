# Contrato: resposta de verdade (XEP-0461) no iOS e no Android

Escrito em 10/11/2026. **É a regra que os dois apps seguem no fio.** Cada app implementa do seu jeito, mas o que vai e vem no stanza é igual. Se algo aqui mudar, muda nos dois apps.

Base:
- `docs/analise-reply-xep0461.md` (iOS) e `docs/decisoes-reply-real-android.md` (Android);
- XEP-0461 v0.2.1 (25/02/2026), XEP-0428 v0.2.1 e XEP-0426 v0.3.0, conferidas em 10/11/2026.

As três XEPs ainda são **Experimental**: o formato pode mudar, e por isso o `isacloud-quote` e a citação em texto continuam valendo.

## 1. O stanza de uma resposta

```xml
<message type='groupchat' to='sala@conference.isacloud.im' id='ID-DA-RESPOSTA'>
  <body>&gt; Ana: 📷 Foto
Que lindo!</body>
  <reply xmlns='urn:xmpp:reply:0' to='sala@conference.isacloud.im/Ana' id='STANZA-ID-DA-ORIGINAL'/>
  <fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
    <body start='0' end='14'/>
  </fallback>
  <isacloud-quote xmlns='urn:isacloud:quote:0' id='STANZA-ID-DA-ORIGINAL'/>
</message>
```

- **`<reply>`:** em **toda** resposta que tenha ID conhecido (seção 2), qualquer que seja o tipo da original.
- **`<fallback>`:** só quando o corpo **começa** com o bloco citado (seção 3).
- **`<isacloud-quote>`:** só quando a original é **foto, GIF ou figurinha**, com o **mesmo** `id` do `<reply>`. Fica durante a transição (seção 6).
- **Com OMEMO:** os três elementos vão **fora** da criptografia, como o `isacloud-quote` e a marca de figurinha já vão. Só o `<body>` é criptografado.
- **Capacidades:** os dois apps anunciam `urn:xmpp:reply:0` no disco e nas capacidades (XEP-0115). A XEP exige isso de quem implementa.

## 2. O `id` e o `to`

| Conversa | `id` do `<reply>` | `to` do `<reply>` |
|---|---|---|
| 1:1 | o `origin-id` da original; se não houver, o `id` do stanza dela | JID do autor da original (o JID sem recurso é aceito em 1:1) |
| 1:1, original é minha | o mesmo (o meu `origin-id`) | o JID da minha conta |
| Grupo e canal | **só** o `stanza-id` dado pela sala (XEP-0359, com `by` igual ao JID da sala) | `sala@conferencia/apelido` do autor |
| Grupo e canal **sem** `stanza-id` (por exemplo, a minha mensagem antes do eco da sala) | **não manda `<reply>`** (a XEP proíbe usar o `id` do stanza em grupo) | — |

- **iOS:** o Monal grava como `messageid` o `origin-id` quando ele existe, e manda os dois iguais. A regra atual de `QuoteFormatting.quotedMessageId` já segue a tabela; só precisa deixar de valer apenas para mídia.
- **O `to`:** é um "SHOULD" na XEP. Quem recebe **resolve a original pelo `id`**, nunca pelo `to`. Em grupo, o formato `sala/apelido` é inferência nossa, porque a XEP só diz "JID completo do autor".

## 3. O fallback (a parte citada do corpo)

- O corpo da resposta continua com a citação em texto, como hoje, cada app no seu formato (`> autor: texto`, rótulos como `> 📷 Foto`).
- **`start` = 0 e `end` = o fim do bloco citado, incluindo a quebra de linha que o separa da resposta.** É o que o exemplo da XEP faz: o `end` aponta o primeiro caractere da resposta.
- **Só manda o `<fallback>` se o corpo começar com o bloco citado.** Se a pessoa apagou a citação do campo, não vai nem `<reply>` nem `<fallback>`.
- **A contagem é em pontos de código Unicode** (XEP-0426):
  - não em UTF-16, não em caracteres visíveis, não em bytes;
  - feita sobre o corpo **já decodificado do XML** (`&gt;` conta 1), sem normalizar o texto;
  - o `end` é **exclusivo**.

| Plataforma | Como contar |
|---|---|
| Swift | `body.unicodeScalars.count`; para o fim do bloco, `bloco.unicodeScalars.count`. **Não usar** `String.count` (conta caracteres visíveis) nem `NSRange` (conta UTF-16). |
| Java | `body.codePointCount(0, body.length())`; para converter, `body.offsetByCodePoints(0, n)`. **Não usar** `String.length()` (conta UTF-16). |

- **Quem recebe:** se o app **mostra a original** de alguma forma (bloco clicável ou cartão), não precisa mostrar o trecho do fallback duplicado. Se não consegue resolver a original, mostra o corpo inteiro, como hoje.
- **Posições inválidas** (fora do corpo, ou `start` maior que `end`): ignorar o fallback e mostrar o corpo inteiro.

### 3.1. Casos de teste iguais nos dois apps

| Corpo | Bloco citado | `end` esperado |
|---|---|---|
| `> Ana: oi\nTudo bem?` | `> Ana: oi\n` | **10** |
| `> 📷 Foto\nLindo!` | `> 📷 Foto\n` | **9** (o 📷 conta 1; em UTF-16 seriam 10) |
| `> Ana: 🎞️ GIF\nKkk` | `> Ana: 🎞️ GIF\n` | **14** (o `🎞️` são 2 pontos de código; em UTF-16 seriam 15, e em caracteres visíveis 13) |
| `> João: ação\nOk` | `> João: ação\n` | **13** (acentos já compostos; não normalizar) |

Os dois apps devem passar nos mesmos casos: calcular o `end` ao enviar e cortar certo ao receber.

## 4. Leitura

1. Se houver `<reply>`, guardar o `id` (e o `to`, se o app quiser).
2. Se houver só `<isacloud-quote>`, guardar o `id` dele como referência, sem `to`.
3. Se houver os dois, valem os dois com o mesmo `id`, e o `<reply>` tem precedência.
4. **Resolver a original** pelo `id`, procurando no ID da mensagem, no `origin-id` e no `stanza-id` dessa conversa.
5. **Original não encontrada, apagada ou retratada:** mostrar a citação em texto e, no toque, um aviso curto ("Mensagem original indisponível").
6. Ler `<reply>` também em mensagens vindas do histórico do servidor (MAM) e de cópias de outros aparelhos (carbons), depois de desembrulhar.

## 5. Interface (mesma cara nos dois apps)

- **Menu e gesto:** "Responder" ("Reply" em inglês).
- **Exibição:** o bloco citado que já existe continua igual, com a miniatura de foto, GIF e figurinha, e fica **clicável**. O toque leva à original e carrega uma página de histórico se ela não estiver na tela.
- **Cartão separado** acima do texto só quando chega `<reply>` **sem** fallback, de um cliente externo.
- **Responder com áudio:** o `<reply>` vai na mensagem de **texto** que leva a citação, nunca na mensagem do áudio. É o que o iOS já faz: a citação em texto e logo depois o áudio. "Responder com mídia" de verdade fica para depois.
- **Editar** a resposta não muda a referência.

## 6. Transição (a ordem importa)

1. **Os dois apps aprendem a ler `<reply>`**, e continuam lendo `isacloud-quote`.
2. **Os dois passam a mandar** `<reply>` + `<fallback>`, mais `isacloud-quote` nas respostas a foto, GIF e figurinha.
3. **Depois de alguns builds com os dois apps atualizados**, param de mandar `isacloud-quote`. A **leitura** fica para sempre, por causa do histórico.

Os passos 1 e 2 podem sair juntos em cada app, desde que nenhum app pule o passo 1.

## 7. Antes de começar

- **Conferir se o MAM do isacloud.im guarda `<reply>`, `<fallback>` e `isacloud-quote`.** Mandar uma resposta, limpar o histórico local ou entrar por outro aparelho, e ver se os elementos voltam.
- **Ordem sugerida:** a parte de protocolo nos dois apps (seções 1 a 4, sem mudar a tela), validada entre iOS e Android; depois o bloco clicável (seção 5).

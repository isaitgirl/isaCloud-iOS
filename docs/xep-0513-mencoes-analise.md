# Análise: menções explícitas (XEP-0513) e modos de notificação nos apps isaCloud

## Contexto

O isaCloud é um serviço XMPP brasileiro (Prosody 13). Os apps cliente são forks:

- **isaCloud Android**: fork do Conversations (Java)
- **isaCloud iOS**: fork do Monal Alpha (Objective-C/Swift)

Hoje os dois detectam menção em MUC procurando o nick do usuário no texto da mensagem. Isso gera reclamação de usuários com nick que é palavra comum (caso real: o nick `perdido` é notificado a cada "tô perdido aqui").

Queremos:

1. Suportar a **XEP-0513 (Explicit Mentions)**, só as **menções individuais**.
2. Dar ao usuário **três modos de notificação** de menção.

**Sua tarefa neste documento é a ANÁLISE do código, não a implementação.** Entregue um relatório (formato no fim) que permita implementar depois com segurança. Não altere código nesta etapa.

---

## Resumo da XEP-0513 (só o que importa aqui)

Spec: https://xmpp.org/extensions/xep-0513.html (versão 0.1.0, Experimental, de 2026-04-01). Leia a spec se precisar de detalhe; o resumo abaixo é o recorte que vamos implementar.

- Namespace: `urn:xmpp:mentions:0`. Anunciar no disco (caps/XEP-0115) **somente** essa feature.
- As menções individuais são o mínimo obrigatório. Os tipos de grupo (`#channel`, `#space`, `#server`, `#associations`, hats) são OPTIONAL e **ficam fora do escopo**. Não anunciar as features deles.
- A menção individual é um `<mention/>` filho de `<message/>`, **sem** o atributo `mentions`:
  - em MUC com suporte a XEP-0421 (occupant-id): atributo `occupantid`
  - em MUC sem XEP-0421, ou fora de MUC: atributo `jid`
  - `begin` / `end` (opcionais): dica do trecho do body que contém a menção, em code points Unicode, `begin` inclusivo e `end` exclusivo
- Modificadores (filhos do `<mention/>`, mesmo namespace), opcionais, mas baratos:
  - `<noping/>`: cita a pessoa sem notificar
  - `<active/>`: só notifica se o usuário estiver ativo
- Quem recebe tem a palavra final sobre notificar ou não. A spec diz que as implementações SHOULD permitir desligar as menções implícitas (por nick no texto).
- Um `<mention/>` com tipo/URI desconhecido é válido pelo schema: **ignorar sem erro**, nunca quebrar o parser.

Exemplo de envio em MUC com occupant-id:

```xml
<message type='groupchat' to='sala@chat.isacloud.im' id='...'>
  <body>@perdido olha isso</body>
  <mention xmlns='urn:xmpp:mentions:0' occupantid='dd72603deec90a38ba552f7c68cbcc61bca202cd' begin='0' end='8'/>
</message>
```

---

## Comportamento desejado

### Envio

- Quando o usuário escolhe um ocupante no autocomplete de `@` (já existe ou está sendo feito nos dois apps), inserir `@nick` no body **e** anexar um `<mention/>`:
  - `occupantid` do ocupante, se a sala anuncia `urn:xmpp:occupant-id:0`
  - senão, o `jid` real se conhecido (sala não anônima); senão, só o body (sem `<mention/>`)
  - `begin`/`end` apontando para o `@nick` inserido. Atenção: **code points**, não UTF-16 (Java `String` e `NSString` são UTF-16; emojis quebram a conta).
- Se o usuário editar o texto e apagar o `@nick`, remover o `<mention/>` correspondente.
- Correções (XEP-0308) devem recalcular as menções da mensagem corrigida.

### Recebimento: decidir se a mensagem é uma menção a mim

Regra principal, igual nos três modos:

- **A mensagem tem ao menos um `<mention xmlns='urn:xmpp:mentions:0'>`:** confiar só nos elementos explícitos. É menção se existir um `<mention/>` sem atributo `mentions` cujo `occupantid` é o meu occupant-id nessa sala (ou cujo `jid` é o meu bare JID) e que não tenha `<noping/>`. O nick no texto é **ignorado** nesse caso.
- **A mensagem não tem nenhum `<mention/>`:** aplicar a detecção implícita conforme o modo escolhido (tabela abaixo).

Sempre:

- Ignorar mensagens enviadas por mim mesma (comparar occupant-id; fallback: nick atual).
- Na detecção implícita, ignorar o trecho citado: o intervalo do `<fallback for='urn:xmpp:reply:0'>` (XEP-0461/XEP-0428) e linhas começando com `>`.
- Casamento do nick: palavra inteira com limite de palavra Unicode e sem diferenciar maiúsculas/minúsculas (verificar o comportamento atual e documentar).

### Modos (configuração global + sobrescrita por sala)

| Chave interna | Nome na UI | Texto de ajuda na UI | Implícita: notifica com |
|---|---|---|---|
| `all` | Qualquer menção ao meu nick | Avisa sempre que seu nick aparecer na mensagem. | nick em qualquer lugar do texto (palavra inteira) |
| `called` (**padrão**) | Quando me chamarem (recomendado) | Avisa com @nick, nick: no início, ou menção pelo app. | `@nick` em qualquer lugar, ou `nick:` / `nick,` no começo da mensagem |
| `explicit` | Só menções pelo app | Avisa apenas quando a pessoa te marcar usando a função de menção. | nunca (só `<mention/>`) |

Na interface, não usar os termos "explícita" e "implícita".

---

## O que analisar no código

Para cada app, localize e documente (arquivo, classe/método, linhas) os pontos abaixo. Os nomes entre parênteses são **pistas** de onde procurar, não garantias. Confirme no código.

### 1. Detecção de menção atual
- Onde o app decide hoje que uma mensagem de MUC é uma menção ("highlight") e dispara notificação, badge ou destaque visual.
  - Android: `NotificationService` (algo como `wasHighlightedOrPrivate` / padrão regex do nick)
  - iOS: `MLNotificationManager`, `MLMessageProcessor`, `DataLayer`
- Qual regex/lógica é usada: limite de palavra? case-insensitive? considera nick antigo após troca de nick? ignora citações?
- Esse mesmo critério é usado em outros lugares (contador de não lidas, destaque na lista de conversas, push/NSE no iOS)? Liste todos.

### 2. Parsing de mensagens recebidas
- Onde o `<message type='groupchat'>` é parseado e onde dá para extrair os `<mention/>` (Android: `MessageParser`; iOS: `MLMessageProcessor`, `XMPPMessage`, `MLXMLNode`).
- Onde as informações da mensagem ficam guardadas (modelo + banco). Precisamos persistir algo ("é menção a mim" ou a lista de menções) para:
  - mensagens vindas do MAM (XEP-0313) no catch-up
  - mensagens processadas na Notification Service Extension do iOS (processo separado, com restrição de memória e tempo)
- O app já trata o `<fallback>` da XEP-0461 para replies? Onde?

### 3. Occupant-id (XEP-0421)
- O app já lê o `<occupant-id/>` das presenças e mensagens de MUC? Onde fica guardado?
- O app sabe qual é **o meu** occupant-id em cada sala (vem na self-presence, status 110)? Se não sabe, apontar onde capturar.
- Como o app sabe se a sala anuncia `urn:xmpp:occupant-id:0` (cache de disco da sala)?

### 4. Envio
- Onde fica o autocomplete de `@` e como o texto é inserido.
- Onde a stanza de saída é montada, para anexar o `<mention/>`.
- Como converter o offset do cursor/seleção (UTF-16) para code points.
- Como as correções (XEP-0308) remontam a stanza.

### 5. Disco / caps
- Onde a lista de features do cliente é definida (para incluir `urn:xmpp:mentions:0`) e se a mudança recalcula o hash de caps automaticamente.

### 6. Configurações
- Onde ficam as preferências globais de notificação e se já existe configuração de notificação **por sala** (Android: as opções de notificação por conversa; iOS: configurações do contato/sala). Dá para estender com o modo de menção?
- Onde os textos traduzidos ficam (pt-BR e en), para os textos da tabela acima.

### 7. Riscos
- Divergências com o upstream que vão dificultar merges futuros.
- Impacto de desempenho (regex por mensagem, parsing extra na NSE).
- Qualquer lugar onde o nick é comparado por string e que vai precisar passar a usar o occupant-id.

---

## Casos de teste a mapear

Para cada caso, diga onde o comportamento atual ficaria diferente do desejado:

1. Nick `perdido`, mensagem "tô perdido aqui", sem `<mention/>`: notifica só no modo `all`.
2. "@perdido vem cá", sem `<mention/>`: notifica em `all` e `called`.
3. "perdido: vem cá", sem `<mention/>`: notifica em `all` e `called`.
4. "vem cá perdido", sem `<mention/>`: notifica só em `all`.
5. Body com "perdido" e `<mention/>` apontando para **outro** ocupante: não notifica em nenhum modo.
6. `<mention occupantid='<meu>'/>` e body sem meu nick: notifica em todos os modos.
7. `<mention occupantid='<meu>'><noping/></mention>`: não notifica.
8. Reply (XEP-0461) cujo trecho citado contém meu nick, sem `<mention/>`: não notifica por causa da citação.
9. Mensagem minha que contém meu nick: não notifica.
10. `<mention mentions='urn:xmpp:mentions:0#channel'/>`: ignorado sem erro, sem notificação por causa dele.
11. Mensagem antiga recuperada via MAM com `<mention/>` para mim: mesmo resultado que ao vivo.
12. iOS: o mesmo resultado na Notification Service Extension e no app em primeiro plano.
13. Envio com emoji antes do `@nick` (ex.: "👋 @perdido"): `begin`/`end` em code points corretos.

---

## Fora do escopo

- Menções de grupo (`#channel`, `#space`, `#server`, `#associations`, hats) e o formulário de permissões de menção da sala.
- XEP-0452 (notificação de menção em salas onde o usuário não está).
- Qualquer mudança no servidor Prosody.

---

## Formato do relatório

Entregue um markdown por app (`analise-mencoes-android.md`, `analise-mencoes-ios.md`) com:

1. **Mapa do código**: tabela com o ponto (itens 1–6 acima), arquivo:linha, classe/método e o que faz hoje.
2. **Comportamento atual** da detecção de menção, descrito com precisão (citar o código).
3. **Lacunas**: o que falta para cada parte do comportamento desejado.
4. **Plano de implementação** em passos pequenos e ordenados, cada um com os arquivos afetados e a estimativa de tamanho (P/M/G).
5. **Casos de teste**: resultado esperado vs. o que o código atual faria.
6. **Riscos e dúvidas em aberto**, incluindo as decisões que precisam da Isadora.

Não invente nomes de arquivo ou método: se não encontrar algo, diga que não encontrou e onde procurou.

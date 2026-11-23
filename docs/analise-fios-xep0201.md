# Análise: fios de conversa (XEP-0201, Message Threads)

Escrita em 23/11/2026. Só análise, sem código.

## 1. Onde estamos

- **No isaCloud iOS:** nada de `<thread>`. O app não lê nem manda o elemento. Toda ocorrência de "thread" no código é sobre threads do sistema ou sobre o `threadIdentifier` das notificações (`MLNotificationManager.m`), que agrupa por conversa.
- **Reply (XEP-0461):** ainda não implementado. A análise está em `docs/analise-reply-xep0461.md` e a regra em `docs/contrato-reply-xep0461.md`. O fio depende dele (seção 2).

## 2. A âncora: `<thread>` sozinho não é um fio

A XEP-0201 define `<thread>id</thread>`, com um `parent=` opcional para fios dentro de fios. Ela nasceu para marcar uma **sessão de conversa**, e não uma discussão presa a uma mensagem. Por isso alguns clientes põem `<thread>` em **todas** as mensagens de um 1:1. Se toda mensagem com `<thread>` virasse fio na tela, a conversa inteira com quem usa esses clientes viraria um fio só.

**Regra proposta:** só existe fio visível quando ele está **ancorado** a uma mensagem.

- **Ao abrir um fio na mensagem M:** se M já tem `thread`, usa o mesmo. Se não tem, gera um UUID T. A primeira resposta leva `<thread>T</thread>` mais o `<reply id=M>` (XEP-0461), com o fallback de citação do contrato.
- **Ao receber:** um `thread` com `reply` liga T a M, e M passa a ser a raiz. Um `thread` que nunca foi ancorado é ignorado na tela, e a mensagem aparece normal na conversa.

O `reply` diz **a qual mensagem** o fio pertence, e o `thread` diz **quem faz parte dele**. Um cliente sem suporte a fios ainda mostra a citação graças ao fallback, e ninguém perde o contexto. Por isso a ordem é: **reply primeiro, fio depois**.

```xml
<message type='groupchat' to='sala@conference.isacloud.im' id='ID'>
  <body>&gt; Ana: Alguém topa churrasco no sábado?
Levo a carne!</body>
  <thread>9f1c…-uuid</thread>
  <reply xmlns='urn:xmpp:reply:0' to='sala@conference.isacloud.im/Ana' id='STANZA-ID-DA-RAIZ'/>
  <fallback xmlns='urn:xmpp:fallback:0' for='urn:xmpp:reply:0'>
    <body start='0' end='38'/>
  </fallback>
</message>
```

As mensagens seguintes do fio levam só `<thread>T</thread>`. O `<reply>` vai junto apenas quando a pessoa responde a uma mensagem específica dentro do fio.

## 3. Visual

### Na conversa
- Embaixo da mensagem raiz aparece um **rodapé de fio**: avatares de quem respondeu, "N respostas · há X min", uma bolinha de não lida e uma seta. Tocar abre o fio.
- As respostas do fio **saem da linha do tempo** (como no Slack), a não ser que a pessoa marque **"Enviar também à conversa"**. Nesse caso a mensagem aparece também na conversa, com "respondeu no fio" e a citação clicável que leva ao fio.
- Um botão na barra de cima abre a **lista de fios** da conversa, com contador de não lidas, ordenada pela última atividade.

### A tela do fio
- É uma tela empurrada na navegação. Uma *sheet* não serve, porque ela briga com o teclado e com o visualizador de mídia. No título, "Fio" e embaixo "em <conversa>".
- Ordem na tela: a raiz no alto, depois um divisor "N respostas", depois as respostas, e embaixo uma barra de digitação própria com "Enviar também à conversa".
- Reaproveitar o `ExyteChatView` com a lista filtrada por T. A `ChatView.swift` já monta `messages: [ChatViewMessage]`, então o fio é outra fonte de dados com a mesma célula. O rodapé entra pelo `messageBuilder` do fork.

### Como entrar no fio
- No menu de toque longo, entra **"Responder no fio"** ao lado de "Responder". O deslizar continua sendo reply.

## 4. 1:1 e canais

- **Canais e grupos:** é o caso principal. As respostas ficam fora da linha do tempo por padrão.
- **1:1:** deixar "Enviar também à conversa" marcado por padrão, ou nem oferecer fio na primeira versão. Numa conversa a dois, esconder mensagens confunde mais do que ajuda.

## 5. Notificações e não lidas

- Tocar numa notificação de uma mensagem do fio abre **direto o fio**.
- Em canais, só notifica respostas em fios que a pessoa **segue**: os que ela abriu, respondeu ou cuja raiz é dela. Um sininho no topo do fio liga e desliga isso.
- O número de não lidas na lista de conversas conta só os fios seguidos. Os outros aparecem só na bolinha do rodapé.

## 6. Dados e limitações

- **Banco:** colunas `thread`, `threadParent` e a raiz ancorada na tabela de mensagens, com índice por conta, contato e thread, criadas por migração. Toda chave nova de preferência precisa de valor padrão antes da tela que a lê (C18).
- **MAM não filtra por `thread`**, nem no Prosody nem na XEP-0313. O fio é montado a partir do banco local. Se a raiz for antiga e o histórico ainda não tiver sido baixado, o fio aparece incompleto: mostrar "carregar anteriores" no topo.
- **OMEMO:** `<thread>` vai **fora** da criptografia, como o `<reply>` do contrato.
- **Capacidades:** não há namespace próprio para anunciar no disco. O fallback do reply garante a leitura em clientes sem suporte.

## 7. Compatibilidade com o Android e a web

- Escrever um contrato igual ao do reply, para o Conversations e o Fluux seguirem a mesma regra da âncora.
- Até onde sei, o Cheogram (fork do Conversations) já mostra fios e serve de referência visual. **A conferir:** como o Conversations atual trata o `<thread>` ao responder (se copia ou gera um novo), antes de fechar o contrato.

## 8. Ordem sugerida

1. Reply XEP-0461 (contrato pronto).
2. A parte invisível do fio: ler e gravar `<thread>`, a regra da âncora e a migração do banco.
3. O rodapé na conversa e a tela do fio.
4. "Enviar também à conversa", a lista de fios e as notificações por fio.
5. Contrato com o Android e teste cruzado.

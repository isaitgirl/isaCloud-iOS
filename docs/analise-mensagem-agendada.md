# Mensagem agendada: análise, decisões e especificação

Recurso para **agendar a entrega de uma mensagem para depois**: em 5 minutos, em 30 minutos, em 1 hora ou numa data e hora escolhidas.
Este documento é o contrato entre o módulo do Prosody (`isacloud-custom-plugins`) e os apps (iOS agora; Android e Web pelo guia `docs/guia-mensagem-agendada-android-web.md`).

## 1. Decisões (27/11/2026)

| Pergunta | Decisão |
|---|---|
| Onde fica o agendamento | **No servidor** (módulo próprio do Prosody). Os apps só oferecem a interface. |
| Quais conversas | **Só 1:1.** Grupos privados ficam para uma decisão futura. Canais (abertos ou de outros servidores) estão fora. |
| Prazo máximo | **72 h** a partir do momento do agendamento (bem menor que a validade dos anexos, 15 dias, e que o histórico). |
| Horário que o destinatário vê | **O horário marcado para a entrega**, não o momento em que a mensagem foi escrita. Se o servidor atrasar (reinício, queda), a mensagem leva `<delay>` com o horário marcado. |
| Conteúdo na fase 1 do iOS | Texto, com ou sem OMEMO. Anexo, resposta (reply), enquete e figurinha ficam para depois: a opção de agendar não aparece quando há resposta ou edição em curso. |

### Por que não fica só nos apps

- **iOS:** o `BGTaskScheduler` não garante horário e o sistema pode matar o app. Sem rede ou com o iPhone desligado, a mensagem não sai.
- **Android:** `AlarmManager` exato funciona com o aparelho ligado e online; desde o Android 14, alarme exato depende de permissão.
- **Web:** depende de a aba estar aberta.
- A mensagem ficaria presa ao aparelho que agendou. No servidor ela sai mesmo com todos os aparelhos desligados.

### Não existe XEP para isso

A XEP-0079 (AMP) trata de regras de entrega e expiração, não de "enviar depois"; a XEP-0203 só marca atraso. Por isso o namespace é nosso: **`urn:isacloud:schedule:0`**, no mesmo padrão de `urn:isacloud:quote:0`. Outros clientes (Conversations, Gajim, Dino) não veem a opção, e o destinatário recebe uma mensagem comum, em qualquer servidor.

## 2. Protocolo

Todas as consultas são IQs do app para **o próprio servidor da conta** (o `to` é o domínio da conta, ou fica sem `to`).

### 2.1 Descoberta

O servidor anuncia a feature `urn:isacloud:schedule:0` no disco#info do domínio (XEP-0030), junto com um formulário XEP-0128 (`FORM_TYPE` = `urn:isacloud:schedule:0`) que traz os limites:

```xml
<x xmlns='jabber:x:data' type='result'>
  <field var='FORM_TYPE' type='hidden'><value>urn:isacloud:schedule:0</value></field>
  <field var='max-delay'><value>259200</value></field>      <!-- segundos (72 h) -->
  <field var='max-pending'><value>50</value></field>        <!-- por conta -->
</x>
```

O app só mostra a opção se a feature estiver presente. Se o formulário faltar, o app usa 72 h e 50.

### 2.2 Agendar

```xml
<iq type='set' id='s1'>
  <schedule xmlns='urn:isacloud:schedule:0' at='2026-11-27T21:00:00Z'>
    <forwarded xmlns='urn:xmpp:forward:0'>
      <message xmlns='jabber:client' to='fulano@xmpp.social.br' type='chat' id='3F2A…'>
        <body>…</body>                <!-- ou <encrypted xmlns='eu.siacs.conversations.axolotl'> + EME -->
        <request xmlns='urn:xmpp:receipts'/>
        <markable xmlns='urn:xmpp:chat-markers:0'/>
        <store xmlns='urn:xmpp:hints'/>
      </message>
    </forwarded>
  </schedule>
</iq>
```

Resposta:

```xml
<iq type='result' id='s1'>
  <scheduled xmlns='urn:isacloud:schedule:0' id='k7…' at='2026-11-27T21:00:00Z'/>
</iq>
```

- `at` em UTC, formato XEP-0082. Para "em 5 minutos", o app calcula o horário absoluto. Se houver diferença grande entre o relógio do aparelho e o do servidor (XEP-0202), o app corrige pela hora do servidor.
- O `id` devolvido é do servidor; o `id` da `<message>` é o do app e **é preservado** na entrega (o app usa esse id para casar o eco).
- O servidor **ignora** o `from` da mensagem interna e põe o da conta na hora do disparo.

Erros (todos `type='modify'`, salvo indicação):

| Condição | Quando |
|---|---|
| `bad-request` | sem `at`, `at` inválido, sem `<forwarded><message>`, mensagem sem `to` |
| `not-acceptable` | `type` diferente de `chat`; `at` mais de 72 h no futuro; `at` mais de 5 min no passado |
| `resource-constraint` (`type='wait'`) | a conta já tem `max-pending` mensagens pendentes |

`at` no passado até 5 min (relógio adiantado) é aceito e sai no disparo seguinte.

### 2.3 Listar

```xml
<iq type='get' id='l1'>
  <list xmlns='urn:isacloud:schedule:0' with='fulano@xmpp.social.br'/>   <!-- with é opcional -->
</iq>

<iq type='result' id='l1'>
  <list xmlns='urn:isacloud:schedule:0'>
    <item id='k7…' at='2026-11-27T21:00:00Z' to='fulano@xmpp.social.br' message-id='3F2A…' created='2026-11-27T20:10:00Z'/>
  </list>
</iq>
```

A lista **não traz o conteúdo**: cada app guarda o texto que agendou. Um agendamento feito em outro aparelho aparece como "agendada em outro aparelho", com o horário.

### 2.4 Cancelar

```xml
<iq type='set' id='c1'>
  <cancel xmlns='urn:isacloud:schedule:0' id='k7…'/>
</iq>
```

Resultado vazio. Se o id não existir ou a mensagem já tiver saído: `item-not-found` (`type='cancel'`). Para editar, o app cancela e agenda de novo.

## 3. Entrega pelo servidor

1. Na hora marcada, o módulo monta a mensagem com `from` = `usuario@dominio/isaCloud-agendada` e a injeta com `core_post_stanza` por uma **sessão sintética** (`type = "c2s"`, `username`, `host`, `full_jid`, `send` que não faz nada). Assim os hooks `pre-message/*` tratam a mensagem como enviada por um cliente da conta:
   - o `mod_mam` grava no histórico de quem enviou (usa `origin.username`);
   - o `mod_carbons` manda a cópia `<sent>` para **todos** os aparelhos conectados da pessoa (só a sessão sintética fica de fora);
   - roteamento, push do destinatário e federação seguem o caminho normal.
2. Se a entrega sai mais de 60 s depois de `at`, a mensagem leva `<delay xmlns='urn:xmpp:delay' from='dominio' stamp='at'/>`, e o destinatário vê o horário marcado.
3. Ao subir, o módulo relê os pendentes e arma o timer. O que venceu com o servidor fora do ar sai logo, com `<delay>`.
4. Quando a conta é apagada (`user-deleted`), os pendentes dela também são.
5. O conteúdo das mensagens nunca vai para o log, só ids, contas e horários.

**Privacidade:** com OMEMO o servidor guarda só o texto cifrado. Sem OMEMO, o texto fica guardado no servidor até a hora marcada (no máximo 72 h), como já fica no MAM depois da entrega.

**OMEMO:** o app cifra na hora de agendar, para os aparelhos que o destinatário e a própria conta têm naquele momento. Um aparelho adicionado depois não consegue ler essa mensagem. Isso é aceitável para um prazo de até 72 h.

## 4. Como o app casa o eco

O Monal **descarta** a cópia de uma mensagem OMEMO vinda do próprio aparelho (`sentByOwnOmemoDevice` em `MLMessageProcessor.m`): o aparelho que agendou não consegue decifrar a cópia que o servidor manda. Por isso:

- ao agendar, o app guarda **localmente** (tabela própria) o texto, o id da mensagem, o id do servidor, a conversa e o horário. A mensagem **não** entra no histórico da conversa;
- quando chega uma cópia `<sent>` (carbon) ou um resultado do MAM de mensagem **nossa** cujo `id` está na tabela, o app põe a mensagem no histórico com o texto guardado e a data do horário marcado, e apaga a linha. Não importa se ela veio cifrada;
- os outros aparelhos da mesma conta recebem a cópia normal (cifrada também para eles) e a mostram como qualquer mensagem enviada.

## 5. Interface (iOS)

- **Toque longo no botão de enviar**, só em conversa 1:1, com texto no campo, sem edição e sem resposta em curso, e com o servidor anunciando a feature. Aparece o menu:
  - 🕐 Em 5 minutos
  - 🕐 Em 30 minutos
  - 🕐 Em 1 hora
  - 📅 Escolher data e hora… (folha com `DatePicker`, de agora + 1 min até agora + 72 h)
- Ao confirmar, o campo esvazia, como num envio, e aparece uma faixa acima do campo: **"🕐 1 mensagem agendada · 21:00"** ("N mensagens agendadas" quando houver mais).
- Tocar na faixa abre a lista das agendadas da conversa: texto (ou "Agendada em outro aparelho"), horário e o botão **Cancelar envio**. Ao cancelar, o texto volta para o campo, se ele estiver vazio.
- Ao abrir a conversa, o app pede a lista ao servidor. Uma cópia local cujo horário já passou some da faixa, mas **fica guardada até o eco chegar** (pelo carbon ou pelo MAM, talvez dias depois, se o iPhone estava desligado). Só uma cópia 7 dias depois do horário é descartada. Se fosse apagada antes, o eco OMEMO deste aparelho seria descartado e a mensagem sumiria do histórico.
- Sem conexão, a opção fica indisponível: o agendamento precisa da resposta do servidor.

## 6. Riscos e pontos a conferir

- **Sessão sintética:** algum módulo pode olhar campos da sessão de origem que a sessão sintética não tem (`mod_isacloud_passport`, limites, firewall). Isso precisa ser testado no servidor de teste antes da produção.
- **Disco depois da retomada:** se a sessão é retomada sem nova descoberta (assunto do build 134), as features do servidor precisam continuar disponíveis no app. Conferir que `serverDiscoFeatures` está preenchido depois de uma retomada.
- **Recusa do destinatário:** um erro de entrega volta para `usuario@dominio/isaCloud-agendada`, que não existe. O Prosody devolve o erro ao JID puro, e os aparelhos podem mostrar a falha. Conferir no teste.
- **Grupos privados (futuro):** a pessoa precisa estar na sala na hora do disparo. Numa sala do nosso servidor o módulo poderia entregar direto, respeitando as permissões. Em sala de outro servidor não há jeito confiável.

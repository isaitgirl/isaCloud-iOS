# Instruções para os agentes do Android e do Web: mensagem agendada

Documento para o agente (ou a pessoa) que for implementar o **agendamento de mensagens** no isaCloud Android (`isaCloudMessenger`, fork do Conversations) e no isaCloud Web (`isaCloud-Web`, fork do Converse.js). É autossuficiente: dá para implementar só com ele. O porquê das decisões está em `docs/analise-mensagem-agendada.md` (repositório do iOS).

**Estado em 27/11/2026:** o servidor já está em produção (módulo `mod_isacloud_schedule` nos hosts `isacloud.im`, `xmpp.social.br` e `voz.social.br`) e o iOS já implementou e testou no `.dev` (com OMEMO, sem OMEMO e cancelamento). Android e Web ainda não têm o recurso.

Namespace: **`urn:isacloud:schedule:0`** (atenção: não é `urn:xmpp:isacloud:...`).

## 1. Regras de produto (decididas, não mudar)

1. **Só conversas 1:1.** Nunca oferecer em grupo, grupo privado ou canal. O servidor recusa `type` diferente de `chat`.
2. **Prazo máximo: 72 h** a partir de agora. No máximo **50 pendentes** por conta. Os dois valores vêm do servidor (seção 3).
3. O destinatário vê o **horário marcado** (o servidor cuida disso). O app não mexe em data da mensagem que envia.
4. **Fase 1: só texto**, com ou sem OMEMO. Sem anexo, sem resposta (reply), sem correção (edição), sem enquete, sem figurinha: com qualquer um desses em curso, a opção de agendar não aparece.
5. Agendar e cancelar **precisam de conexão** (resposta do servidor). Offline, a opção fica indisponível.
6. Toda mudança no changelog técnico do app vem com a linha correspondente no changelog para usuários (tom simpático, um emoji no começo).

## 2. Como funciona, em uma figura

```
App                                   Servidor (mod_isacloud_schedule)              Destinatário
 │ monta a <message> como num envio     │                                            │
 │ normal (OMEMO cifrado agora)         │                                            │
 │ ── IQ set <schedule at> ───────────▶ │ guarda (texto cifrado, se OMEMO)            │
 │ ◀── <scheduled id at> ─────────────  │                                            │
 │ guarda o texto localmente            │                                            │
 │                                      │  ... na hora marcada ...                   │
 │                                      │ envia como se fosse a própria conta ─────▶ │
 │ ◀── carbon <sent> / MAM ──────────── │ (MAM da conta + carbons p/ todos aparelhos)│
 │ põe no histórico com o texto guardado│                                            │
```

## 3. Protocolo

Todos os IQs vão para **o próprio servidor da conta**: sem `to`, ou com `to` = domínio da conta.

### 3.1 Descoberta

Depois do login, leia o disco#info **do domínio da conta**:

- feature `urn:isacloud:schedule:0` presente → recurso disponível;
- formulário XEP-0128 no mesmo disco#info:

```xml
<x xmlns='jabber:x:data' type='result'>
  <field var='FORM_TYPE' type='hidden'><value>urn:isacloud:schedule:0</value></field>
  <field var='max-delay'><value>259200</value></field>   <!-- segundos -->
  <field var='max-pending'><value>50</value></field>
</x>
```

Sem o formulário, use 259200 s e 50. Contas de outros servidores não têm a feature: a opção não aparece para elas. Se o app guarda as features entre retomadas de sessão (XEP-0198), confira que a feature continua lá depois de uma retomada.

### 3.2 Agendar

```xml
<iq type='set' id='s1'>
  <schedule xmlns='urn:isacloud:schedule:0' at='2026-11-27T21:00:00Z'>
    <forwarded xmlns='urn:xmpp:forward:0'>
      <message xmlns='jabber:client' to='fulano@xmpp.social.br' type='chat' id='3F2A…'>
        <body>Oi!</body>
        <request xmlns='urn:xmpp:receipts'/>
        <markable xmlns='urn:xmpp:chat-markers:0'/>
        <store xmlns='urn:xmpp:hints'/>
      </message>
    </forwarded>
  </schedule>
</iq>
```

Resposta de sucesso:

```xml
<iq type='result' id='s1'>
  <scheduled xmlns='urn:isacloud:schedule:0' id='k7…' at='2026-11-27T21:00:00Z'/>
</iq>
```

- `at`: UTC, formato XEP-0082 (`AAAA-MM-DDTHH:MM:SSZ`). "Em 5 minutos" é calculado no app como horário absoluto.
- A `<message>` interna é **montada exatamente como num envio normal**: mesmo `id` gerado pelo app, recibo, `markable`, `store`. Com OMEMO, o corpo vai cifrado (`<encrypted xmlns='eu.siacs.conversations.axolotl'>` + `<encryption xmlns='urn:xmpp:eme:0'>`), cifrado **na hora de agendar**. Só que ela não vai para o socket: vai dentro do IQ.
- O `id` da `<message>` é preservado pelo servidor na entrega. É por ele que o app reconhece o eco (seção 4).
- O `id` do `<scheduled>` é do servidor e serve para cancelar.

Erros:

| Condição | Tipo | Quando | Texto para a pessoa |
|---|---|---|---|
| `bad-request` | modify | faltou `at`, `<forwarded><message>` ou `to` | "Não foi possível agendar a mensagem." |
| `not-acceptable` | modify | `type` ≠ `chat`, mais de 72 h à frente ou mais de 5 min no passado | "Não é possível agendar a mensagem para esse horário. Escolha um horário nas próximas 72 horas." |
| `resource-constraint` | wait | a conta já tem o máximo de pendentes | "Você já tem o número máximo de mensagens agendadas." |
| sem resposta / outro | — | | "O servidor não conseguiu agendar a mensagem. Tente de novo mais tarde." |

### 3.3 Listar

```xml
<iq type='get' id='l1'>
  <list xmlns='urn:isacloud:schedule:0' with='fulano@xmpp.social.br'/>   <!-- with opcional -->
</iq>

<iq type='result' id='l1'>
  <list xmlns='urn:isacloud:schedule:0'>
    <item id='k7…' at='2026-11-27T21:00:00Z' to='fulano@xmpp.social.br'
          message-id='3F2A…' created='2026-11-27T20:10:00Z'/>
  </list>
</iq>
```

A lista **não traz o conteúdo**. Item sem cópia local = agendado em outro aparelho: mostrar "Agendada em outro aparelho" com o horário.

### 3.4 Cancelar

```xml
<iq type='set' id='c1'>
  <cancel xmlns='urn:isacloud:schedule:0' id='k7…'/>
</iq>
```

Resultado vazio = cancelado. `item-not-found` (cancel) = já saiu ou já foi cancelada ("Esta mensagem já foi enviada ou cancelada."). Editar = cancelar + agendar de novo.

## 4. O ponto que mais engana: o eco no aparelho que agendou

Na hora marcada o servidor envia a mensagem pela conta, grava no MAM da conta e manda a cópia `<sent>` (Carbons, XEP-0280) para **todos** os aparelhos conectados, inclusive o que agendou.

**Com OMEMO, o aparelho que agendou não consegue decifrar essa cópia** (ninguém cifra para o próprio aparelho). O iOS e o Conversations descartam ou marcam como indecifrável a cópia do próprio aparelho. Então:

1. **Ao agendar com sucesso**, guarde localmente: conta, `id` da mensagem, `id` do servidor, JID da conversa, texto, se foi cifrada, horário marcado. **Não** ponha a mensagem no histórico da conversa ainda.
2. **Quando chegar uma mensagem nossa** (carbon `<sent>` ou resultado de MAM de saída, inclusive o catch-up depois de ficar offline) cujo `id` está guardado: ponha a mensagem no histórico **com o texto guardado** e a **data = horário marcado**, com o estado de enviada, e apague o registro local. Faça isso **antes** de qualquer tentativa de decifrar, e não mostre "não foi possível decifrar". Vale também sem OMEMO (evita duplicata).
3. **Não apague o registro local só porque o horário passou** ou porque o servidor não lista mais a mensagem: o eco pode chegar só no catch-up do MAM, dias depois, se o aparelho estava desligado. Apagar antes faz a mensagem sumir do histórico de quem enviou. Só descarte registros 7 dias depois do horário.
4. Os **outros aparelhos** da mesma conta conseguem decifrar a cópia (ela foi cifrada para eles) e mostram como qualquer mensagem enviada por outro aparelho. Nada a fazer.

## 5. Interface

Igual ao iOS, para a experiência ser a mesma nos três apps.

**Onde fica:** toque longo (Android) / menu no botão (Web) **no botão de enviar**, só quando: 1:1, feature disponível, conectado, texto não vazio, sem anexo, sem resposta e sem edição em curso. Tocar normalmente continua enviando na hora.

> Lição do iOS: o menu deve abrir **ancorado no botão**, sem mover a conversa. No iOS, o `.contextMenu` levantava o botão e subia tudo para o terço superior da tela; foi trocado por um `Menu` com ação principal.

**O menu:**
- 🕐 Em 5 minutos
- 🕐 Em 30 minutos
- 🕐 Em 1 hora
- 📅 Escolher data e hora… (de agora + 1 min até agora + 72 h)

**Depois de agendar:** o campo esvazia (só se ainda tiver o texto agendado), e aparece uma faixa discreta acima do campo: **"🕐 1 mensagem agendada · 21:00"** / **"🕐 3 mensagens agendadas · 21:00"** (o horário é o da próxima; se não for hoje, mostra também a data). Tocar na faixa abre a lista da conversa: texto (ou "Agendada em outro aparelho"), horário e **Cancelar envio**. Ao cancelar, o texto volta ao campo se ele estiver vazio. A faixa só mostra pendentes com horário no futuro.

**Sincronização:** ao abrir a conversa (e ao reconectar), pedir `list with=<contato>` e montar a faixa juntando a lista do servidor com os textos guardados localmente.

**Textos pt-BR (os mesmos do iOS):**

| Chave (en) | pt-BR |
|---|---|
| In 5 minutes | Em 5 minutos |
| In 30 minutes | Em 30 minutos |
| In 1 hour | Em 1 hora |
| Choose date and time… | Escolher data e hora… |
| Date and time | Data e hora |
| Schedule | Agendar |
| %d scheduled message · %@ | %d mensagem agendada · %@ |
| %d scheduled messages · %@ | %d mensagens agendadas · %@ |
| Scheduled messages | Mensagens agendadas |
| Scheduled on another device | Agendada em outro aparelho |
| Cancel sending | Cancelar envio |

E os textos de erro da tabela da seção 3.2.

## 6. Android (`isaCloudMessenger`): por onde começar

Confira no código; os nomes abaixo são do upstream do Conversations e podem ter mudado no fork.

| Peça | Onde |
|---|---|
| Descoberta | `xmpp/XmppConnection.java` → classe `Features`: acrescente `scheduledMessages()` usando o disco do domínio (`hasDiscoFeature(account.getDomain(), "urn:isacloud:schedule:0")`). O formulário vem no `ServiceDiscoveryResult` do domínio. |
| Montar a mensagem sem enviar | `generator/MessageGenerator.java` (`generateChat`, `generateAxolotlChat`) monta a stanza do envio normal; reaproveite para obter a `<message>` (com OMEMO pelo `AxolotlService`, que no Conversations é assíncrono: espere a mensagem cifrada ficar pronta antes de montar o IQ). Embrulhe em `<schedule><forwarded>` e envie com `sendIqPacket`. |
| Guardar o texto | Tabela nova no banco (`persistance/DatabaseBackend.java`), seguindo `docs/decisoes-banco-e-migrations.md` do repo. |
| Eco | `parser/MessageParser.java`: no tratamento de carbon `sent` e de MAM de saída, **antes** do processamento OMEMO, procure o `id` na tabela; se achar, crie a `Message` com o texto guardado, status enviada, `timeSent` = horário marcado, e apague a linha. |
| Menu no enviar | `ui/ConversationFragment.java` + `ui/util/SendButtonTool.java`: o Conversations já usa toque longo no enviar para escolher o modo (texto, foto, voz…). Acrescente "Agendar envio" nesse menu quando o modo for texto e as condições da seção 5 valerem, ou abra direto o menu de agendamento. Data/hora: `MaterialDatePicker` + `MaterialTimePicker`. |
| Faixa e lista | Acima da caixa de texto no layout da conversa (`fragment_conversation.xml`), com bottom sheet para a lista. |

## 7. Web (`isaCloud-Web`, Converse.js): por onde começar

| Peça | Onde |
|---|---|
| Descoberta | `api.disco.supports('urn:isacloud:schedule:0', domínio)`; os campos do formulário em `api.disco.entities.get(domínio)` → `dataforms`. |
| Montar a mensagem sem enviar | `src/headless/plugins/chat/model.js` (`getOutgoingMessageAttributes`) e `src/headless/shared/model-with-messages.js` (`sendMessage`) mostram o caminho do envio normal. O OMEMO entra pelos hooks em `src/web/plugins/omemo/`. Monte a stanza pelo mesmo caminho (com o hook do OMEMO), mas em vez de `api.send`, embrulhe em `<schedule><forwarded>` e envie com `api.sendIQ`. Não crie o modelo da mensagem na conversa ainda. |
| Guardar o texto | Armazenamento persistente do Converse (o mesmo que guarda as mensagens, por conta), não `sessionStorage`: o eco pode chegar dias depois. |
| Eco | `src/headless/plugins/chat/parsers.js` / `utils.js` (tratamento de carbons e de resultados MAM): antes da decifragem OMEMO, se a mensagem é nossa e o `id` está guardado, crie a mensagem com o texto guardado e `time` = horário marcado, e apague o registro. |
| Menu no enviar | `src/web/plugins/chatview/templates/message-form.js` e `src/web/shared/chat/templates/toolbar.js`: um botão de relógio 🕐 ao lado do enviar (ou uma seta ▾ no próprio botão) que abre o menu ancorado nele. Data/hora: `<input type="datetime-local">` com `min`/`max`. Botão direito no enviar pode abrir o menu, mas não ser o único caminho. |
| Faixa e lista | Acima do campo de mensagem, com um modal ou popover para a lista. |

Siga as convenções de `isacloud-docs/` do repo Web (customizações isoladas, para facilitar o merge com o upstream).

## 8. Como testar (os mesmos passos do iOS)

Conta de teste em `isacloud.im`, conversa 1:1 com outra conta de teste:

1. **OMEMO, em 5 minutos, app fechado:** a mensagem chega ao destinatário no horário, com o app de quem enviou fechado.
2. **Reabrir o app:** a mensagem aparece na conversa de quem enviou, no horário marcado, com o texto legível (sem "não foi possível decifrar"), e a faixa some.
3. **Sem OMEMO:** mesmo resultado, sem duplicata.
4. **Cancelar** uma em 30 minutos: nada chega; o texto volta ao campo.
5. **Outro aparelho da mesma conta** (ex.: o iOS): vê "Agendada em outro aparelho" antes e a mensagem normal depois.
6. **Limites:** daqui a 4 dias o app não deixa (ou mostra o aviso do `not-acceptable`); grupo e canal não mostram a opção.

No servidor, o log do Prosody registra cada passo, só com ids e horários: `scheduled message <id> for <conta> at <horário>`, `delivered scheduled message …`, `cancelled scheduled message …`. Peça para quem administra o servidor conferir.

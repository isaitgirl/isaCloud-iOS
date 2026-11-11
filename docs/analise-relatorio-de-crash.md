# Análise: enviar o relatório de crash sem depender do e-mail

Escrita em 10/11/2026. Só análise, sem código. **Caminho escolhido pela Isadora: Compartilhar + XMPP**, e o e-mail sai. Decisões na seção 6.

## 1. Como funciona hoje

- **Código:** `MLCrashReporter.m`, herdado do Monal, com o KSCrash.
- **O que acontece:** quando o app abre depois de um crash, `reportPendingCrashes` pergunta "Crash Detected… Send a crash report?" ("Sure, send it!" ou "No, thanks"). Se a pessoa aceita, o app monta **um `.mcrash.gz` por crash** com:
  - informações extras (`KSCrashReportFilterMLAddAuxInfo`);
  - o relatório no formato da Apple, já com os símbolos;
  - o JSON do KSCrash;
  - **o log do app** (`*.rawlog.gz`), que pode conter mensagens e contatos, como o próprio aviso diz;
  - o perfil (`*.profraw`), quando existe.
- **Envio:** o último filtro da cadeia (`filterReports:onCompletion:`) abre o `MFMailComposeViewController` para `sysadmin@isacloud.cc`, com os arquivos anexados.
- **O problema:** se o aparelho **não tem o app Mail configurado**, aparece "This device is not configured to send email" e os relatórios são descartados. Muita gente não usa o Mail do iPhone, então provavelmente perdemos relatórios assim. No simulador, os arquivos são gravados no contêiner do app.
- Esse relatório é diferente do relatório de crash do TestFlight e do Xcode (Organizer), que a Apple coleta por conta própria.

## 2. Proposta

Depois do "sim" da pessoa, uma **segunda escolha**:

```
Enviar relatório de crash
  ▸ Enviar ao suporte do isaCloud   (pelo XMPP, criptografado)
  ▸ Compartilhar…                  (planilha de compartilhar do iOS)
  ▸ Cancelar
```

**O e-mail sai** (decisão de 10/11/2026): some o `MFMailComposeViewController` do relatório de crash. O "Contato" das Configurações (`composeMail` em `MLSettingsTableViewController.m`) é outra coisa e não muda.

### 2.1. Compartilhar (cerca de 1 a 2 h)
- Grava os `.mcrash.gz` numa pasta temporária e abre a planilha de compartilhar (`UIActivityViewController`) com os arquivos.
- A pessoa escolhe para onde vai: iCloud Drive, Arquivos, AirDrop, outro mensageiro, ou uma conversa do próprio isaCloud.
- **Também substitui o erro "This device is not configured to send email":** nunca mais o relatório some.
- O app já usa a planilha em outros lugares (`ActivityViewController` em `SwiftuiHelpers.swift`).
- Os arquivos temporários são apagados quando a planilha fecha.

### 2.2. Enviar ao suporte pelo XMPP (cerca de 1 a 1,5 dia)

**Ideia:** o relatório vai como **arquivo criptografado** para uma conta de suporte, pelo mesmo caminho de qualquer anexo do app:
1. sobe pelo HTTP Upload do servidor (XEP-0363) com criptografia (`MLFiletransfer uploadFile:onAccount:withEncryption:YES`): o servidor recebe só o arquivo cifrado;
2. o link `aesgcm://…`, que traz a chave, vai numa mensagem **OMEMO** para a conta de suporte.

**O que já existe e é reaproveitado:**
- o upload com criptografia e os limites do servidor (200 MiB no isacloud.im e 150 MiB no autozona.cc; o relatório costuma ter de 2 a 6 MB);
- o envio de mensagem com arquivo (`sendMessageAndAddToHistory` com `uploadInfo`), o mesmo caminho do anexo da conversa;
- o OMEMO.

**Decisões de desenho:**

| Tema | Proposta |
|---|---|
| Conta de suporte | **`reports@isacloud.im`** (decisão de 10/11/2026), fixo numa constante do app. A Isadora lê os relatórios pelo Monocles no Android e pelo Gajim. |
| Conta que envia | A primeira conta **habilitada e conectada**. Se houver várias, preferir uma do isacloud.im ou do autozona.cc. |
| App ainda não conectado | Guardar os relatórios numa **fila própria** (pasta no App Group, por exemplo `crash-outbox/`) e enviar quando uma conta conectar. Chamar a conclusão do KSCrash **depois de gravar na fila**, para ele apagar a cópia dele sem perder nada. |
| Crash em sequência (o app cai antes de conectar) | A fila sobrevive: cada abertura tenta de novo. Limite de, por exemplo, 5 relatórios na fila e de 7 dias; os mais antigos saem. |
| OMEMO com a conta de suporte | A conta de suporte precisa ter aparelho OMEMO publicado. O envio usa as chaves que o app já conhece. Se não houver chave confiável, **não manda em claro**: oferece "Compartilhar…" no lugar. |
| Conversa na lista da pessoa | **Aparece** (decisão de 10/11/2026), mas sem parecer uma conta de conversa: ver a seção 2.3. |
| Texto junto do arquivo | Uma linha com versão, build e data do crash, e um campo opcional "O que você estava fazendo?" antes de enviar, como o e-mail pede hoje. |
| Confirmação | Depois de enviar: "Relatório enviado. Obrigado!". Com falha: fica na fila e avisa "Enviaremos assim que o app conectar". |

### 2.3. Deixar claro que `reports@` não é para conversar

A conversa com `reports@isacloud.im` aparece na lista, mas a pessoa não deve achar que ali tem atendimento. Três camadas, da mais barata para a mais elaborada:

1. **Nome e perfil da conta** (sem código): apelido e vCard de `reports@` como "isaCloud – Relatórios de crash (não responde)", com um avatar próprio. É o que aparece no topo da conversa e na lista.
2. **No app:** a mensagem que acompanha o arquivo já diz o que é ("Relatório de crash do isaCloud 0.0.1 (build N)…"). Depois do envio, o app mostra "Relatório enviado. Esta conta só recebe relatórios; para falar com a gente, use …". A tela de Configurações → Contato aponta o canal certo de atendimento.
3. **Resposta automática no servidor (`mod_firewall`):** dá para fazer. Uma regra na cadeia de entrega responde a toda mensagem com corpo enviada para `reports@` com algo como *"Relatório recebido, obrigado! Esta conta só recebe relatórios e ninguém lê as mensagens aqui."* De quebra, isso serve de **confirmação de recebimento**. Rascunho, **a validar no servidor de teste antes de ligar** (a sintaxe exata do `mod_firewall` deve ser conferida na versão instalada):

   ```
   ::deliver
   TO: reports@isacloud.im
   KIND: message
   TYPE: chat|normal
   INSPECT: body
   NOT FROM: reports@isacloud.im
   LIMIT: reports_reply
   REPLY=Relatório recebido, obrigado! Esta conta só recebe relatórios de crash do isaCloud; ninguém lê as mensagens aqui.
   ```

   **Cuidados com a regra:**
   - não responder a mensagens **sem corpo** (recibos de entrega, "digitando…"), a erros nem a `groupchat`, para não criar laço;
   - limitar por remetente (no máximo uma resposta por hora para cada um), para um crash em sequência não gerar uma resposta por relatório;
   - a resposta vai **em claro**, porque o servidor não tem OMEMO. Ela não leva dado nenhum, então tudo bem;
   - mensagens que a própria Isadora mandar de `reports@` (pelo Monocles ou pelo Gajim) não passam por essa regra, que só olha o que **chega** a `reports@`.

   Sugestão: começar pelas camadas 1 e 2, que já resolvem quase tudo, e ligar a 3 se ainda vier gente tentando conversar.

**Por que esse caminho:**
- não precisa de servidor novo: usa o Prosody e o HTTP Upload que já existem;
- é **criptografado de ponta a ponta**: o servidor guarda só o arquivo cifrado, e a chave vai por OMEMO;
- só quem tem conta consegue enviar, então não entra spam anônimo;
- você recebe o relatório no próprio isaCloud, num aparelho onde já lê o `.mcrash.gz`.

**Limites:**
- precisa de uma conta conectada. Se o crash acontece toda vez antes de conectar, a fila não esvazia, e aí o "Compartilhar…" resolve;
- **o arquivo no HTTP Upload expira em 2 semanas** no isacloud.im. O Monocles ou o Gajim precisam **baixar** o relatório antes disso, então o download automático fica ligado nos dois;
- **OMEMO para quem não é contato:** a pessoa não tem `reports@` na lista de contatos. O app precisa conseguir ler a lista de aparelhos OMEMO de `reports@`, então os nós OMEMO de `reports@` têm de estar abertos (`pubsub#access_model` = `open`). Isso é configuração **do nó**, não do Prosody. Como conferir e ajustar: seção 7. `reports@` aceita mensagens de quem não é contato (confirmado pela Isadora em 10/11/2026).
- as **extensões** (compartilhar, notificações) não entram: o KSCrash só reporta no app principal, como hoje.

## 3. Texto do aviso (com tradução pt-BR no override)

Atualizar o aviso para dizer para onde vai e o que contém:

> **O app fechou inesperadamente da última vez.**
> Quer enviar um relatório para nos ajudar a corrigir? Ele inclui o registro do app, que pode conter mensagens e contatos. Usamos só para investigar o problema e apagamos em até 30 dias.

Botões: "Enviar ao suporte", "Compartilhar…" e "Agora não".

O texto atual, herdado do Monal, também promete apagar ("…and delete it afterwards!"). O novo diz o prazo.

## 4. Privacidade e retenção

- **Consentimento a cada crash**, como hoje. Nada sai sem a pessoa tocar em enviar.
- **Pelo XMPP:** criptografado de ponta a ponta.
- **Prazo de 30 dias** (decisão de 10/11/2026): a conta `reports@` continua existindo indefinidamente, mas os relatórios são apagados em até 30 dias. A limpeza vale para os arquivos baixados no Monocles e no Gajim, para as conversas e para o histórico da conta no servidor (MAM). Anotar a regra em `docs/decisoes.md`.
- **No HTTP Upload:** o arquivo cifrado expira sozinho em 2 semanas.
- **Compartilhar:** a pessoa decide o destino; o app só entrega o arquivo.

## 5. Esforço e ordem sugerida

| Etapa | Esforço |
|---|---|
| Compartilhar (inclui acabar com o erro do e-mail) | 1 a 2 h |
| Envio ao suporte pelo XMPP, com fila, conta, OMEMO e confirmação | 1 a 1,5 dia |
| Texto do aviso e traduções | 30 min |
| Conta `reports@` com aparelho OMEMO, PEP aberto, nome e vCard, e teste ponta a ponta | 1 h (fora do código) |
| Regra de resposta automática no `mod_firewall` (opcional) | 30 min a 1 h (servidor) |

**Ordem:**
1. O "Compartilhar…" primeiro, porque já para de perder relatórios.
2. Depois o envio pelo XMPP.

**Teste no `.dev`:** a tela de Depuração já tem botões para derrubar o app de propósito (`CrashTestingView` em `DebugView.swift`: "Bad Access Crash", "Fatal Error Crash" etc.). Basta provocar um crash, abrir o app de novo e testar os três caminhos.

## 6. Decisões (10/11/2026)

1. **JID:** `reports@isacloud.im`, lido pela Isadora no Monocles (Android) e no Gajim.
2. **Conversa na lista:** aparece, mas deixando claro que a conta não é para conversar (seção 2.3). Resposta automática pelo `mod_firewall` é possível; a sugestão é começar pelo nome e perfil da conta e pelo texto no app.
3. **Retenção:** a conta `reports@` é permanente; **os relatórios são apagados em até 30 dias**. O HTTP Upload expira em 2 semanas.
4. **E-mail:** sai.
5. **Android:** não tem relatório de crash parecido; nada a alinhar por enquanto.

6. **`reports@` aceita mensagens de quem não é contato:** sim.

**Antes de implementar, falta só conferir os nós OMEMO de `reports@` (seção 7).**

## 7. Nós OMEMO de `reports@` abertos

**Não há o que configurar no Prosody.** O `mod_pep` guarda o modelo de acesso **de cada nó**, e quem define é o cliente que publica (pelas `publish-options` ou pela configuração do nó). O padrão do PEP é `presence`: só contatos com inscrição leem. Para quem não é contato ler, os nós OMEMO de `reports@` precisam de `access_model` = `open`. O Monocles (derivado do Conversations) e o Gajim costumam publicar o OMEMO como `open`, mas vale conferir.

**Conferir**, de uma conta de teste que **não** tenha `reports@` nos contatos (por exemplo pelo console XML do Gajim):

```xml
<iq type='get' to='reports@isacloud.im' id='t1'>
  <pubsub xmlns='http://jabber.org/protocol/pubsub'>
    <items node='eu.siacs.conversations.axolotl.devicelist'/>
  </pubsub>
</iq>
```

- Volta a lista de aparelhos: está aberto.
- Volta erro (`forbidden` ou `presence-subscription-required`): está fechado.

**Abrir**, logado **como `reports@`** (console XML do Gajim):

```xml
<iq type='set' id='c1'>
  <pubsub xmlns='http://jabber.org/protocol/pubsub#owner'>
    <configure node='eu.siacs.conversations.axolotl.devicelist'>
      <x xmlns='jabber:x:data' type='submit'>
        <field var='FORM_TYPE' type='hidden'><value>http://jabber.org/protocol/pubsub#node_config</value></field>
        <field var='pubsub#access_model'><value>open</value></field>
      </x>
    </configure>
  </pubsub>
</iq>
```

Repetir para o nó de chaves de cada aparelho, `eu.siacs.conversations.axolotl.bundles:<id-do-aparelho>`. Os IDs estão na lista de aparelhos. Depois, repetir a conferência de uma conta que não é contato.

**Conferido em 10/11/2026:** a lista de aparelhos e as chaves de `reports@` vieram na consulta, com um aparelho publicado (`1906983637`). Quando o segundo cliente (Monocles ou Gajim) publicar o dele, conferir de novo.

Se um cliente republicar com outro modelo de acesso, o nó pode voltar a fechar. Vale repetir a conferência depois de instalar um aparelho novo em `reports@`.

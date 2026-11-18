# Foto de visualização única: guia para isaCloud iOS e Android

Escrito em 18/11/2026. **Nada implementado ainda.** Este é o contrato único das duas plataformas: descreve **o comportamento e o protocolo**, não o código. O que precisa ser **igual nos dois apps** vem marcado com **[compatibilidade]**. Onde ainda falta decidir, a seção 11 junta as pendências.

Contexto: a análise de como o Monocles faz mensagens efêmeras (`urn:xmpp:ephemeral:0`, timer por conversa) mostrou que visualização única é outra coisa: o gatilho é **ver**, não ler, e o recurso só precisa existir entre apps isaCloud. Por isso não reaproveitamos o namespace do Monocles.

## 1. O que é

Ao enviar uma foto, a pessoa liga **"Visualização única"**. Quem recebe vê a foto **uma vez**. Ao fechar o visualizador, a foto some do aparelho dele e a mensagem vira um aviso ("Foto aberta"). Quem enviou não guarda cópia dentro do app.

## 2. Regras de escopo (decisões da Isadora, 18/11/2026) [compatibilidade]

| Tema | Decisão |
|---|---|
| Quem pode receber | Só quem usa **isaCloud iOS ou Android**, reconhecido pelo namespace anunciado no disco (seção 3) |
| Tipo de conversa | **Só 1:1.** Nada em canais (MUC) nem em mensagem privada de sala |
| Criptografia | **Só com OMEMO ligado** na conversa. Sem OMEMO, o botão não aparece |
| Tipo de mídia | **Só foto** (imagem escolhida ou tirada). Fora: vídeo, GIF, figurinha, documento |
| Garantia | **Não há.** Print e foto da tela por outro aparelho não dá para impedir, e cliente modificado ou leitura do armazenamento burlam qualquer regra. O texto para o usuário diz que o app "ajuda a evitar", nunca que é impossível salvar. |

## 3. Reconhecer o outro app [compatibilidade]

- **Namespace:** `urn:isacloud:view-once:0`. Cada app o anuncia no disco (caps, XEP-0115), como já anuncia as outras features.
- **Não há segredo compartilhado.** Qualquer segredo embutido no app se extrai do binário, e o destinatário (a pessoa de quem a foto "se protege") controla o aparelho dele. O namespace anunciado já faz o papel de "reconhecer o isaCloud". Provar que o outro lado é o app oficial exigiria Play Integrity e App Attest, que não se aplicam entre dois clientes XMPP.
- **Botão só se todos os aparelhos conhecidos do contato anunciam o namespace.** Um aparelho sem suporte guardaria a foto para sempre.
- **Contato offline:** sem presença não há disco para consultar. Usar o **último suporte conhecido** (guardado por contato) em vez de esconder o botão. Ver pendência 1.
- Os aparelhos sem informação de caps ainda (recém-online) contam como "sem suporte" até o disco chegar. O botão pode levar um instante para aparecer.

## 4. Protocolo [compatibilidade]

### 4.1 Mensagem da foto

É uma mensagem de arquivo comum (HTTP Upload, `aesgcm://` no corpo cifrado), como a das figurinhas, com um elemento a mais **fora** da criptografia:

```xml
<message type='chat' to='contato@isacloud.im' id='…'>
  <encrypted xmlns='eu.siacs.conversations.axolotl'>…</encrypted>   <!-- corpo cifrado: link aesgcm:// -->
  <view-once xmlns='urn:isacloud:view-once:0'/>
  <no-permanent-store xmlns='urn:xmpp:hints'/>
  <origin-id xmlns='urn:xmpp:sid:0' id='ID-DA-FOTO'/>
  <!-- receipts, markable, EME etc. como em qualquer mensagem -->
</message>
```

- **Por que o marcador fica em claro:** os dois apps usam o OMEMO legado (`eu.siacs.conversations.axolotl`), que **cifra só o corpo**. Não existe envelope onde esconder o elemento (isso exigiria OMEMO 2/SCE; ver `docs/analise-omemo2.md`). É o mesmo caminho do `<sticker/>` em `docs/ferramenta-de-figurinhas.md` §2.
- **O que o servidor vê:** que é uma foto de visualização única, mas não qual. A foto continua cifrada.
- **Limitação conhecida:** o servidor pode **tirar** o marcador (a foto chega como foto normal e fica guardada) ou **pôr** um (a foto some depois de vista). Mudança em claro não tem como ser detectada pelo destinatário. Aceitável para a versão 1; ver pendência 2.
- **`no-permanent-store`:** pede que o servidor não arquive a mensagem. O arquivo no servidor de upload **continua lá** até a limpeza dele, e não existe como apagá-lo (o XEP-0363 não prevê isso). Com OMEMO ele está cifrado e a chave só viaja na mensagem.

### 4.2 Aviso de "aberta"

Quando a foto é aberta no destinatário, o app dele envia **dois** avisos, ambos com a dica `<store/>`:

```xml
<message type='chat' to='quem-enviou@isacloud.im' id='…'>
  <opened xmlns='urn:isacloud:view-once:0' id='ID-DA-FOTO'/>
  <store xmlns='urn:xmpp:hints'/>
</message>

<message type='chat' to='o-proprio-jid@isacloud.im' id='…'>   <!-- para os outros aparelhos dele -->
  <opened xmlns='urn:isacloud:view-once:0' id='ID-DA-FOTO'/>
  <store xmlns='urn:xmpp:hints'/>
</message>
```

- **Por que dois:** o primeiro avisa quem enviou ("Aberta"). O segundo chega a todos os aparelhos do próprio destinatário, que apagam a foto. Mensagem sem corpo pode não ser copiada por carbon (XEP-0280); mandar para o próprio JID não depende disso. **Confirmar o comportamento do Prosody em teste.**
- O `id` é o `origin-id` da foto.
- **Quem pode mandar `<opened>`:** o contato (visto por quem enviou) ou o próprio JID (visto pelos outros aparelhos do destinatário). De qualquer outro, ignorar.
- O aviso em claro revela ao servidor que uma foto foi aberta, mas não o conteúdo. Pode o servidor forjar um `<opened>`? Pode, e o efeito é a foto sumir de um aparelho. O servidor já poderia simplesmente não entregar a foto; não piora.

## 5. Envio

1. Na barra de anexos/escolha de foto, o botão **"Visualização única"** (um "1" num círculo) liga **só para a próxima foto**. Depois do envio volta a desligado. Não é configuração da conversa. Mostrar o botão só quando as regras das seções 2 e 3 valem; sem elas, escondido ou desabilitado com a dica "o contato precisa usar o isaCloud".
2. A foto sobe **sem recompressão extra** além da que o app já aplica a fotos, e **sem miniatura de pré-visualização** em lugar nenhum (nem na lista de conversas).
3. A foto tirada pela câmera do app para visualização única **não é salva** na fototeca/galeria.
4. Depois do envio com sucesso, o app **apaga o arquivo local** e mostra, na conversa de quem enviou, o aviso "Foto de visualização única" com estado: **Enviada** → **Aberta** (quando chegar o `<opened>`). Quem enviou não consegue reabrir. Se o envio falhar, o arquivo fica até o reenvio ou o cancelamento.

## 6. Recebimento

- **O balão não mostra a foto nem miniatura.** Mostra "Foto de visualização única" e o toque para abrir. Notificação e prévia da lista: **"📷 Foto de visualização única"**, sem imagem.
- **Download só ao tocar** (nunca automático): impede que a foto fique no aparelho sem ter sido vista, e evita miniatura em cache.
- **Vale a regra "queimar ao abrir":** a foto conta como vista **no momento em que o visualizador abre**, não quando fecha. Assim, matar o app no meio não deixa a foto reabrível. A ordem é: gravar o estado "aberta" → enviar os dois `<opened>` → mostrar a foto.
- **Visualizador** (no iOS é o do fork do ExyteChat, `FullscreenMediaPages`; no Android, o visualizador do app): **sem** compartilhar, salvar, encaminhar, copiar, responder com citação da imagem nem "Mídia Compartilhada". O compartilhar que hoje existe no visualizador e no toque longo da mensagem fica desligado para essas mensagens.
- Ao **fechar**, o app apaga o arquivo baixado, o cache de decodificação e qualquer cópia temporária. O balão vira **"Foto aberta"** (sem imagem, sem como reabrir).
- **Foto nunca aberta:** se o upload expirar no servidor, o download falha e o balão mostra "Esta foto não está mais disponível". Não existe prazo próprio no app (ver pendência 3).

## 7. Vários aparelhos do destinatário

- Ao receber o `<opened>` do próprio JID, o aparelho apaga o arquivo (se tinha baixado) e vira "Foto aberta".
- **Corrida:** dois aparelhos abrindo ao mesmo tempo podem ver os dois. Aceito.
- **Ordem trocada:** o `<opened>` pode chegar antes da foto (catch-up do MAM). O app guarda a lista de `id` já abertos; quando a foto chega com um `id` dessa lista, já nasce como "Foto aberta" e **não é baixada**.
- Aparelho que não anuncia o namespace (não deveria existir, pela seção 3) mostra a foto como uma foto normal.

## 8. O que o app faz contra captura

- **Android:** `FLAG_SECURE` no visualizador (impede print e gravação de tela e esconde o conteúdo no seletor de apps). O Android 14 tem um callback de captura (`registerScreenCaptureCallback`); confirmar antes de prometer aviso ao remetente.
- **iOS:** não dá para impedir. Usar `UIScreen.isCaptured` para **esconder a foto** durante gravação ou espelhamento de tela, e `userDidTakeScreenshotNotification` para **detectar** o print. Ver pendência 4: avisar quem enviou ou não.
- **Os dois:** esconder o conteúdo quando o app vai para segundo plano (seletor de apps) e **excluir a foto temporária do backup** (no iOS, `isExcludedFromBackup` e pasta temporária; no Android, cache sem backup).

## 9. Diferenças em relação às mensagens efêmeras do Monocles

- Não é timer de conversa: **não há** configuração de duração, nem mensagem de controle de timer, nem `<i-want-out/>`.
- O gatilho é a **abertura**, não a leitura (`markRead`).
- Apagar é **imediato e sincronizado** entre os aparelhos do destinatário. No Monocles cada aparelho conta sozinho a partir da própria leitura.
- Não usamos o namespace `urn:xmpp:ephemeral:0`, para um cliente que o conheça não tratar a foto como mensagem com timer.

## 10. O que testar

1. 1:1 com OMEMO e os dois lados isaCloud: botão aparece; sem OMEMO, não aparece; em canal e em mensagem privada de sala, não aparece.
2. Contato com um aparelho que não é isaCloud: botão some ou fica desabilitado.
3. Abrir a foto: some do aparelho; balão vira "Foto aberta"; quem enviou vê "Aberta".
4. Matar o app com a foto aberta: ao voltar, a foto **não** reabre.
5. Dois aparelhos do destinatário: abrir em um, o outro apaga (inclusive o que estava offline durante o envio).
6. Print, gravação e espelhamento de tela nos dois sistemas (resultado esperado: Android bloqueia; iOS esconde na gravação e detecta o print).
7. Notificação e lista de conversas sem miniatura.
8. Compartilhar, salvar, encaminhar e "Mídia Compartilhada" não aparecem para essa mensagem.
9. Foto cujo upload expirou: mensagem de "não está mais disponível".

## 11. Pendências (a decidir)

1. **Botão com o contato offline:** usar o último suporte conhecido (recomendado, o app do outro lado processa quando abrir) ou exigir o contato online (como na regra mais conservadora discutida).
2. **Marcador em claro:** aceitável na v1? A alternativa é esconder o marcador dentro do corpo cifrado, por exemplo como parâmetro na URL `aesgcm://…`, mas isso mexe num formato que outros clientes interpretam. Só vale se a falha do servidor tirar o marcador incomodar.
3. **Foto nunca aberta:** deixar para sempre ou expirar no app depois de N dias (e se sim, quantos).
4. **Aviso de print ao remetente** (iOS detecta, Android 14+ talvez): mandar sempre, só se a pessoa ligar, ou não mandar.
5. **Remetente reabre a foto?** Aqui decidimos que não. Confirmar.
6. **Detalhes do Prosody:** conferir `no-permanent-store` e a entrega de mensagens sem corpo para o próprio JID no servidor do isaCloud.

## 12. Onde mexe (referência)

- **iOS:** envio (onde o marcador `<sticker/>` é acrescentado, no mesmo ponto de `ferramenta-de-figurinhas.md` §2), disco/caps, balão e visualizador no fork do ExyteChat (nova opção desligada por padrão, no formato de `fullscreenSingleAttachment`; entra em `docs/exytechat-fork.md`), compartilhar do toque longo, `MediaViewer` (Mídia Compartilhada). Texto novo de interface sempre com tradução pt-BR no override do isaCloud.
- **Android:** `MessageGenerator`/`MessageParser` (marcador e `<opened>`), disco, balão, visualizador e a lista de mídia compartilhada.
- **Changelog:** quando entrar em build, atualizar `CHANGELOG.md` e `CHANGELOG-USERS.md` (texto leve, sem jargão).

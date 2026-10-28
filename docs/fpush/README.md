# fpush: push do isaCloud para iOS

O app isaCloud registra o push em `push.isacloud.im` (XEP-0357). Esse endereço é o [fpush](https://github.com/monal-im/fpush), rodando como **componente XMPP** (XEP-0114) do Prosody, num container ao lado do container do Prosody.

O app envia o token APNs do aparelho como `node` e escolhe o módulo pela opção `pushModule`:
- `monalProdiOS`: builds do TestFlight e da App Store (APNs produção);
- `monalProdiOS-sandbox`: builds instaladas pelo Xcode (APNs sandbox).

## 1. Apple (conta Apple Developer paga)

1. Registre o App ID `br.com.isacloud.messenger` com a capability **Push Notifications**.
2. Crie o certificado **Apple Push Notification service SSL (Sandbox & Production)** para esse App ID.
3. Importe o `.cer` no Keychain do Mac e exporte como `.p12`, com senha.
4. O OpenSSL 3 da imagem pode recusar `.p12` exportados com cifras antigas. Se o fpush reclamar do certificado, converta (instruções do próprio fpush):
   ```bash
   openssl pkcs12 -legacy -in apple-old.p12 -nodes -out p12-decrypted.tmp
   openssl pkcs12 -in p12-decrypted.tmp -export -out isacloud-apns.p12
   rm p12-decrypted.tmp
   ```

## 2. Prosody

```lua
-- porta de componentes: só na rede interna do Docker (não publicar no host)
component_ports = { 5347 }
component_interfaces = { "0.0.0.0" }

Component "push.isacloud.im"
    component_secret = "UM_SEGREDO_LONGO_E_ALEATORIO"
```

- **Não publique a porta 5347** no host (`ports:` do Prosody): a conexão fpush ↔ Prosody não é criptografada.
- **DNS**: `push.isacloud.im` deve apontar para o servidor do Prosody (A/AAAA e, se usar, SRV `_xmpp-server._tcp`), porque os servidores dos usuários chegam ao push por s2s.
- **Certificado TLS** do Prosody precisa cobrir `push.isacloud.im` (servidores com `s2s_secure_auth` recusam sem ele).
- `cloud_notify` precisa estar ativo nos VirtualHosts (já está no isaCloud).

## 3. Subir o fpush no servidor

Copie esta pasta para o servidor (por exemplo `/opt/fpush`) e:

```bash
cd /opt/fpush
mkdir -p secrets
cp settings.json.example settings.json   # edite: componentKey, certPassword, serverHostname
cp /caminho/isacloud-apns.p12 secrets/isacloud-apns.p12
chmod 600 settings.json secrets/isacloud-apns.p12
chown 10001 settings.json secrets/isacloud-apns.p12   # usuário do container

# nome da rede Docker onde está o Prosody
docker inspect <container-do-prosody> --format '{{json .NetworkSettings.Networks}}'
PROSODY_NETWORK=<nome-da-rede> docker compose up -d --build
docker compose logs -f fpush
```

- `serverHostname` no `settings.json` é o nome do container (ou alias de rede) do Prosody.
- `componentKey` é o mesmo valor de `component_secret` no Prosody.
- No Prosody, `prosodyctl shell` → `server:list_components()` (ou o log) deve mostrar o componente `push.isacloud.im` conectado.

## Problemas já vistos (e como resolver)

- **Prosody: "options that should be in the global section"**: as opções globais (`s2s_require_encryption`, `limits`, `statistics`, `log`, `pidfile`, `trusted_proxies`, etc.) ficaram abaixo do bloco `Component "push.isacloud.im"`. O Prosody lê tudo abaixo de um `Component` como pertencente a ele. Solução: o bloco `Component` vai sempre por último no arquivo, depois de todas as opções globais e dos `VirtualHost`.
- **fpush: `unsupported ... RC2-40-CBC`**: o `.p12` exportado pelo Keychain usa a cifra antiga RC2-40, que o OpenSSL 3 do fpush não aceita. Solução: reconverter o arquivo com `openssl 3` (`-legacy` na leitura), mantendo a mesma senha do `settings.json`:
  ```bash
  openssl pkcs12 -legacy -in isacloud-apns.p12 -nodes -out apns-decrypted.tmp
  openssl pkcs12 -export -in apns-decrypted.tmp -out isacloud-apns-new.p12
  rm apns-decrypted.tmp
  mv isacloud-apns-new.p12 isacloud-apns.p12
  ```
  Depois, confira com `openssl pkcs12 -info -in isacloud-apns.p12 -noout`. O `rm` é obrigatório: o temporário tem a chave privada sem criptografia.
- **fpush parado em "Opening connection to prosody"**: a conexão de componente não foi aceita. Confira no log do Prosody (`External component successfully authenticated` é o sinal de sucesso), se o `componentKey` do `settings.json` é igual ao `component_secret` do Prosody, e se o fpush e o Prosody estão na mesma rede Docker (`docker network inspect prosody`).
- **Push não chega no TestFlight**: o log do Prosody deve mostrar `Push notifications enabled for ...`. Para testar, o app precisa estar em segundo plano e outra conta precisa mandar mensagem. O log do fpush (`docker compose logs -f fpush`) mostra o envio e o resultado do APNs.

## Patches do push enquanto não há push filtering (aplicados em 28/10/2026)

Sem a entitlement `com.apple.developer.usernotifications.filtering` (pedido à Apple em andamento, ver `CLAUDE.md`), todo push de alerta vira uma notificação visível ("New Message / New Message?", com som), mesmo quando o app decide não notificar. Dois patches, um no servidor e um no app, reduzem esses "fantasmas". **Os dois são reversíveis.**

### Servidor (fpush no ar): `0001-silent-unimportant-pushes.v2.patch`
- Aplicado em cima do commit fixo do fpush (`FPUSH_COMMIT` no `Dockerfile`, linha `RUN git apply /tmp/isacloud.patch`), imagem `isacloud/fpush:42359ca-isacloud2`. Push sem `last-message-body` vira push em segundo plano (`content-available`, sem alerta); os de alerta usam o mesmo collapse id (`isacloud-sync`) e o rate limit nunca rebaixa um push importante.
- O módulo `cloud_notify_quiet` do Prosody foi atualizado no servidor junto (ele fica fora deste repositório).
- **Reverter:** no `Dockerfile`, apagar as linhas `COPY 0001-silent-unimportant-pushes.v2.patch ...` e `RUN git apply ...` (deixando só o `cargo build --release --locked -p fpush`), trocar a tag da imagem no `docker-compose.yaml` e rodar `docker compose up -d --build`; no Prosody, voltar o `cloud_notify_quiet` à versão anterior (ou descarregá-lo).

### App: `0002-app-push-placeholder.patch` (o original) e `0002-app-push-placeholder.applied.patch` (o que está no código)
- O que o app faz: quando a extensão de notificação (NSE) entregaria "conteúdo vazio" (o que o iOS ignora sem a entitlement e troca pelo alerta original), ela entrega um aviso **passivo** (sem som, sem banner), com o nome do app como título ("isaCloud" ou "isaCloud.dev") e **sem texto** (a extensão não recebe as traduções do isaCloud), marcado com `isaCloudPushPlaceholder`, e o remove ao fim da extensão (quando ela ainda está viva), no próximo push e ao abrir o app.
- Diferenças do `.applied` para o original: título = nome do app, corpo vazio (o original tinha o texto "Checking for new messages…", sem tradução na extensão) e a tradução pt-BR desse texto não foi adicionada; o comentário sobre a remoção ficou menos otimista.
- Código: `HelperTools.m` (`isaCloudPushPlaceholderContent`, `removeIsaCloudPushPlaceholdersAfter:`, `#define ISACLOUD_HAS_PUSH_FILTERING`), `HelperTools.h`, `NotificationService.m` (dois pontos que entregam conteúdo vazio e uma limpeza na inicialização) e `MonalAppDelegate.m` (limpeza ao abrir o app).
- **Reverter, de três formas:**
  1. **Quando a Apple liberar a entitlement:** recolocar `<key>com.apple.developer.usernotifications.filtering</key><true/>` nos dois `.entitlements` (ver `CLAUDE.md`) e mudar `#define ISACLOUD_HAS_PUSH_FILTERING` para `1` em `HelperTools.m`: o app volta a entregar conteúdo vazio, e o resto do código vira inofensivo.
  2. **Tirar o patch inteiro:** `git apply -R docs/fpush/0002-app-push-placeholder.applied.patch` (já verificado com `--check`; vale se não houver mais mudanças nesses trechos) ou `git revert` do commit que o trouxe.
  3. **Só desligar:** `ISACLOUD_HAS_PUSH_FILTERING 1` sem a entitlement devolve o comportamento antigo (alerta fantasma), útil para comparar.
- **Não testado ainda no aparelho:** se o iOS respeita o nível passivo definido pela extensão, e se o aviso some sozinho; o teste de verdade é com o TestFlight e o servidor com o `0001` (uma noite).

## Segredos

`settings.json` e `secrets/` estão no `.gitignore` do repositório. Nunca faça commit deles.

## Atualizar o fpush

A versão está fixada no `Dockerfile` (`FPUSH_COMMIT`). Para atualizar, leia as mudanças do fpush, troque o commit e a tag da imagem no `docker-compose.yaml`, e rode `docker compose up -d --build`.

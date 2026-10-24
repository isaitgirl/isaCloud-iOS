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

## Segredos

`settings.json` e `secrets/` estão no `.gitignore` do repositório. Nunca faça commit deles.

## Atualizar o fpush

A versão está fixada no `Dockerfile` (`FPUSH_COMMIT`). Para atualizar, leia as mudanças do fpush, troque o commit e a tag da imagem no `docker-compose.yaml`, e rode `docker compose up -d --build`.

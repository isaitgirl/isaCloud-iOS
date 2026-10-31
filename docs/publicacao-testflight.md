# Publicar um novo build do isaCloud no TestFlight

Rotina para enviar um build de distribuição ao App Store Connect e liberá-lo para os testadores internos.

Equipe: `K8Y6S5RF2S`. Bundle da distribuição: `br.com.isacloud.messenger`. Rode os comandos a partir da raiz do repositório, salvo quando indicado.

## Antes de começar

- O app de Xcode tem a conta da equipe K8Y6S5RF2S configurada (Xcode → Settings → Accounts).
- A chave do Giphy está em `isaCloud/local/giphy-api-key.txt` (fora do Git). Sem ela o build sai sem a busca de GIF.
- Confira que o trabalho que vai para o build está no estado certo. O build é feito a partir dos arquivos no disco, não de um commit.

## 1. Subir o número do build

O App Store Connect não aceita dois builds com o mesmo número para a mesma versão. O número fica em `CURRENT_PROJECT_VERSION` no `Monal/Monal.xcodeproj/project.pbxproj`, em 25 lugares. Troque `N` pelo próximo número (o último enviado + 1):

```bash
sed -i '' 's/CURRENT_PROJECT_VERSION = 2;/CURRENT_PROJECT_VERSION = N;/g' Monal/Monal.xcodeproj/project.pbxproj
```

Para conferir:

```bash
grep -o "CURRENT_PROJECT_VERSION = [0-9.]*" Monal/Monal.xcodeproj/project.pbxproj | sort | uniq -c
```

Ajuste o número do build na mesma conta toda vez. Se a versão de marketing (`MARKETING_VERSION`, hoje 0.0.1) mudar, troque nos 5 lugares.

## 2. Arquivar

**Caminho recomendado: `scripts/archive-testflight.sh`** (`--upload` para enviar também). Ele confere que o número do build é o mesmo nos 25 lugares, apaga `/tmp/ddarch`, arquiva, confere número, bundle id e **FTS5** do arquivo e só então envia. Os passos abaixo são o que o script faz, para o caso de precisar fazer à mão.

Use a configuração `AppStore`. A configuração `Release` não existe no projeto.

```bash
cd Monal && xcodebuild archive -workspace Monal.xcworkspace -scheme Monal -sdk iphoneos -configuration AppStore -archivePath "$(pwd)/../build/isaCloud-AppStore.xcarchive" -allowProvisioningUpdates DEVELOPMENT_TEAM=K8Y6S5RF2S ISACLOUD_BUNDLE_ID=br.com.isacloud.messenger ISACLOUD_ENTITLEMENTS_DIR= GIPHY_API_KEY="$(tr -d '[:space:]' < ../isaCloud/local/giphy-api-key.txt)"
```

**Depois de mudar as opções (traits) de um pacote, como o `ENABLE_FTS5` do `sqlite3-package`, arquive com uma pasta de compilação nova** (acrescente `-derivedDataPath /tmp/ddarch` e apague a pasta antes): o Xcode reaproveita a SQLite compilada antes e o arquivo sai sem a opção nova, sem avisar (aconteceu no build 32). Confira no arquivo, antes de enviar:

```bash
strings -a build/isaCloud-AppStore.xcarchive/Products/Applications/*.app/Frameworks/monalxmpp.framework/monalxmpp | grep -c '^ENABLE_FTS5$'
```

O resultado deve ser `1`.

Confira o arquivo gerado (deve sair `2` ou o número escolhido, e `br.com.isacloud.messenger`):

```bash
APP=$(ls -d build/isaCloud-AppStore.xcarchive/Products/Applications/*.app) && /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" -c "Print :CFBundleIdentifier" "$APP/Info.plist"
```

## 3. Enviar ao App Store Connect

Use o plist de upload (`destination` = `upload`), com caminhos absolutos:

```bash
xcodebuild -exportArchive -archivePath /Users/isadora/projects/swift/isaCloud-iOS/build/isaCloud-AppStore.xcarchive -exportOptionsPlist /Users/isadora/projects/swift/isaCloud-iOS/scripts/exportOptions/isaCloud_AppStore_Upload_ExportOptions.plist -allowProvisioningUpdates
```

Quando termina sem erro, o build aparece no App Store Connect depois de processado (alguns minutos, às vezes meia hora).

## 4. Depois do envio: nada a liberar

Os testadores são **internos**: o build fica disponível no app TestFlight assim que o App Store Connect termina de processar (alguns minutos, às vezes meia hora). Não é preciso adicionar o build a um grupo nem liberar nada.

- Para acompanhar: App Store Connect → Apps → isaCloud → TestFlight → **Builds** (status "Processando" até ficar pronto).
- Se aparecer um aviso de conformidade de exportação, responda conforme o uso de criptografia do app (confira antes de responder, pois o texto da pergunta muda de versão para versão do App Store Connect).
- A Apple manda e-mail se o binário for rejeitado.

## Problemas já vistos

- **"App record with bundle identifier not found"** na hora de enviar: o app não está criado com o bundle `br.com.isacloud.messenger` no App Store Connect. Confira o nome exato no cadastro.
- **Build repetido**: o número do build já foi enviado para a mesma versão. Suba `CURRENT_PROJECT_VERSION` e arquive de novo.
- **Erro de assinatura ou de entitlements no arquivo**: o App ID precisa ter as capacidades ativas (Push, App Groups, Communication Notifications). Ative no portal de desenvolvedor e rode o arquivamento de novo com `-allowProvisioningUpdates`.
- **`exportArchive Failed to Use Accounts` / "App Store Connect access for K8Y6S5RF2S is required"** (visto em 26/10/2026, com a conta aparecendo normalmente em Xcode > Settings > Accounts; **resolvido saindo e entrando de novo na conta no Xcode**, depois o envio funcionou): o `xcodebuild` de linha de comando usa um token de sessão do App Store Connect que pode ficar inválido sem aviso. Primeiro tente sair e entrar de novo na conta (Settings > Accounts). Outras saídas: (a) abrir o archive no Organizer (`open build/isaCloud-AppStore.xcarchive`) e usar **Distribute App > App Store Connect > Upload**, onde o Xcode renova a sessão; (b) conferir o papel da conta na equipe (precisa de Admin, App Manager ou Developer com acesso ao App Store Connect); (c) para o envio por linha de comando funcionar sempre, criar uma chave da API do App Store Connect (Users and Access > Integrations) e usar `-authenticationKeyPath`, `-authenticationKeyID` e `-authenticationKeyIssuerID` no `xcodebuild -exportArchive`; o caminho do `.p8` e os ids ficam em `isaCloud/local/NOTAS-LOCAIS.md`, nunca aqui.
- **Build sem push**: o build de distribuição tem push. O build `.dev` para o iPhone (`scripts/isacloud-dev-device.sh`) não tem push **por escolha nossa** (os entitlements de `isaCloud/dev-entitlements/` não pedem `aps-environment`), e não por limite da conta: ele é assinado com a conta paga e tem o App Group do `.dev`. Detalhes em `docs/troubleshooting.md`, seção "Instalar e abrir o isaCloud.dev no iPhone".

## Marcar o build no Git

Depois do envio, a tag fica no commit que tem exatamente o que foi enviado (o commit com o número do build, e o `CHANGELOG.md` com a seção "Não publicado" fechada com esse número):

```bash
git tag -a build-N <commit> -m "Build N (TestFlight, <data>)" && git push origin isaCloud build-N
```

Para saber o que ainda não entrou num build: `git log build-N..isaCloud --oneline` (código: `git diff --stat build-N isaCloud -- Monal`). Não suba o número do build a cada commit; só quando for enviar.

## Depois do envio

O commit e o push só acontecem quando a Isadora pede ("fazer novo build e push"; com "fazer novo build" só o envio, o iPhone e os docs). A rotina completa está em `CLAUDE.md`.

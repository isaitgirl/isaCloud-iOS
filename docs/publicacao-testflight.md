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

Use a configuração `AppStore`. A configuração `Release` não existe no projeto.

```bash
cd Monal && xcodebuild archive -workspace Monal.xcworkspace -scheme Monal -sdk iphoneos -configuration AppStore -archivePath "$(pwd)/../build/isaCloud-AppStore.xcarchive" -allowProvisioningUpdates DEVELOPMENT_TEAM=K8Y6S5RF2S ISACLOUD_BUNDLE_ID=br.com.isacloud.messenger ISACLOUD_ENTITLEMENTS_DIR= GIPHY_API_KEY="$(tr -d '[:space:]' < ../isaCloud/local/giphy-api-key.txt)"
```

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

## 4. Liberar para os testadores internos

1. Abra App Store Connect → Apps → isaCloud → TestFlight.
2. Espere o build aparecer em **Builds** com o status de pronto para testar. Se houver um aviso de conformidade de exportação, responda conforme o uso de criptografia do app (confira antes de responder, pois o texto da pergunta muda de versão para versão do App Store Connect).
3. Em **Testadores internos**, abra o grupo e adicione o build novo.
4. Os testadores internos recebem o aviso no app TestFlight.

## Problemas já vistos

- **"App record with bundle identifier not found"** na hora de enviar: o app não está criado com o bundle `br.com.isacloud.messenger` no App Store Connect. Confira o nome exato no cadastro.
- **Build repetido**: o número do build já foi enviado para a mesma versão. Suba `CURRENT_PROJECT_VERSION` e arquive de novo.
- **Erro de assinatura ou de entitlements no arquivo**: o App ID precisa ter as capacidades ativas (Push, App Groups, Communication Notifications). Ative no portal de desenvolvedor e rode o arquivamento de novo com `-allowProvisioningUpdates`.
- **Build sem push**: o build de distribuição tem push. O build `.dev` para o iPhone (`scripts/isacloud-dev-device.sh`) não tem push, por desenho.

## Depois do envio

Não há commit automático. Os commits ficam com a Isadora, como combinado.

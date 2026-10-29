# Controlar o simulador por fora (DeviceHub): clique, digitação e captura

Como um agente (Claude Code, DeepSeek Harness ou uma pessoa em outro terminal) consegue **tocar, digitar e capturar** o isaCloud rodando no simulador, sem XCUITest e sem plugin nenhum. Validado em 28/10/2026 no simulador **isaCloud iOS27** (iOS 27.0, iPhone 17).

## Resumo do que funciona

| Ação | Como | Precisa de permissão? |
|---|---|---|
| Ver a tela do app | `xcrun simctl io <UDID> screenshot` | não |
| Ver a janela como o usuário vê | `screencapture -R` na janela do DeviceHub | **Gravação de Tela** |
| Tocar | evento de mouse via CoreGraphics | **Acessibilidade** |
| Digitar | keycodes via CoreGraphics (não texto unicode) | **Acessibilidade** |
| Abrir/encerrar app, push, `openurl`, log, banco | `simctl` / `devicectl` | não |

## 1. Permissões (uma vez)

Em **Ajustes do Sistema → Privacidade e Segurança**, para o **DeepSeek Harness**:

- **Gravação de Tela** — sem ela, `screencapture` responde `could not create image from display`.
- **Acessibilidade** — sem ela, o System Events responde `osascript is not allowed assistive access. (-1728)` e os eventos de clique/tecla são descartados.

Depois de conceder, **reinicie o app**: a Acessibilidade só passa a valer num processo novo (a Gravação de Tela costuma pegar na hora).

Teste rápido (se devolver números, a Acessibilidade está valendo):

```bash
osascript -e 'tell application "System Events" to tell process "Device Hub" to get {position, size} of window 1'
```

**Cuidado:** `UI elements enabled` do System Events é uma chave legada e devolve `false` mesmo com a permissão funcionando. Não use ela como teste.

## 2. Use o DeviceHub, não o Simulator

No Xcode 27 o `Simulator.app` não existe mais no bundle; o app que mostra aparelhos e simuladores é o **DeviceHub** (`com.apple.dt.Devices`, em `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`).

O `Simulator.app` do **Xcode 26.2** (`/Applications/Xcode-26.2.app/Contents/Developer/Applications/Simulator.app`) **abre e desenha** um aparelho de iOS 27, mas **não aceita toque nem teclado** nele — é só espelho. Para interagir, DeviceHub. (Fechar o Simulator do 26.2 derrubava os devices que ele tinha aberto: eles voltam com `simctl boot`.)

Traga a janela para a frente e confirme antes de qualquer clique:

```bash
osascript -e 'tell application "Device Hub" to activate'
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
```

## 3. Captura: duas fontes, e por que as duas

```bash
# o framebuffer do aparelho (imagem exata do app, sem moldura)
xcrun simctl io <UDID> screenshot /tmp/app.png

# a janela como está na tela (com moldura, toolbar e o que o usuário vê)
osascript -e 'tell application "System Events" to tell process "Device Hub" to get {position, size} of window 1'
screencapture -x -R <x>,<y>,<w>,<h> /tmp/janela.png
```

O print da janela é **2× (Retina)**: uma janela de 484×800 pontos gera um PNG de 968×1600.

## 4. Calibração: framebuffer → tela

O toque é um clique de mouse em coordenadas de **tela** (pontos). Para converter uma posição do app (framebuffer) na posição da tela:

```
crop  = offset + framebuffer * escala          # em pixels do print da janela (2×)
tela  = origem_da_janela + crop / 2            # em pontos
```

Constantes medidas para uma janela de **484×800** mostrando um **iPhone 17 (1206×2622)**:

```
escala = 0.4934
offset = (186.2, 161.5)
```

Exemplo real: o microfone está em `framebuffer (1121.5, 2441.5)` →

```
crop  = (186.2 + 1121.5*0.4934, 161.5 + 2441.5*0.4934) = (739.5, 1366.1)
tela  = (1028 + 739.5/2, 87 + 1366.1/2)               = (1398, 770)
```

### Como reconferir (obrigatório se a janela for redimensionada)

Mover a janela **não** invalida nada (só muda `origem_da_janela`, que é lida na hora). **Redimensionar** muda a escala e o offset. O teste de sanidade é achar dois elementos cor no print da janela e comparar com o framebuffer:

- o **microfone** (maior bloco rosa, canto inferior direito);
- o **logo do canal** (bloco rosa no cabeçalho).

Se o centro previsto de um deles não bater com o medido, recalcule `escala` e `offset` com esses dois pontos. A proporção da área da tela no print tem de ser a mesma do framebuffer (1206/2622 = 0,459).

### Armadilha que custou tempo

Ao ler pixels com `CGContext`, manter `buf[y*width + x]` com `y` crescendo **de cima para baixo** (foi assim que a medição funcionou). Se as leituras parecerem espelhadas, desconfie de ter invertido `y` "para corrigir" — foi exatamente esse o erro que fez um clique cair no meio do chat em vez da seta de voltar.

## 5. Clique e digitação

O clique precisa devolver o cursor ao lugar: nada de deixar o ponteiro da pessoa parado onde o agente clicou.

```swift
// ui.swift — clique com cursor restaurado
import CoreGraphics
import Foundation

func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func click(_ x: Double, _ y: Double) {
    let saved = cursor()
    let p = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(70_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGWarpMouseCursorPosition(saved)
}
```

**Digitar é por keycode, não por texto.** Eventos com `keyboardSetUnicodeString` são ignorados pelo simulador; o que entra é o mapa de teclas do layout US:

```swift
// kb.swift — teclas do layout US (extrato)
let map: [Character: (CGKeyCode, Bool)] = [
 "a":(0,false),"s":(1,false),"d":(2,false),"f":(3,false),"h":(4,false),"g":(5,false),
 "z":(6,false),"x":(7,false),"c":(8,false),"v":(9,false),"b":(11,false),"q":(12,false),
 "w":(13,false),"e":(14,false),"r":(15,false),"y":(16,false),"t":(17,false),
 "o":(31,false),"u":(32,false),"i":(34,false),"p":(35,false),"l":(37,false),
 "j":(38,false),"k":(40,false),"n":(45,false),"m":(46,false),
 "A":(0,true),"S":(1,true),"P":(35,true),"M":(46,true), // ... maiúsculas = com shift (56)
 " ":(49,false),"@":(19,true),".":(47,false)
]

func press(_ code: CGKeyCode, _ shift: Bool) {
    let saved = cursor()
    if shift { CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true)?.post(tap: .cghidEventTap) }
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(15_000)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    if shift { CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false)?.post(tap: .cghidEventTap) }
    usleep(25_000)
    CGWarpMouseCursorPosition(saved)
}
```

Keycodes úteis: `delete` 51, `return` 36, `esc` 53, `space` 49, `tab` 48.

## 6. Cuidados que já morderam

- **A lista de conversas se reordena quando chega mensagem.** Capture a tela **imediatamente antes** de cada toque e calcule o alvo no framebuffer recém-capturado. Um clique com print de 30 segundos antes pode abrir a conversa errada.
- **Toque em alvo pequeno erra fácil.** Prefira o centro do elemento e confira pelo print seguinte; se nada mudou, o clique não chegou (janela sem foco) ou o alvo estava fora.
- **O primeiro clique pode só dar foco à janela.** Ative o DeviceHub por AppleScript e confirme o `frontmost` antes.
- **O simulador não abre teclado na tela** ao focar um campo quando o teclado físico está ligado; a digitação entra direto.
- **Não deixe o cursor fora do lugar:** sempre `CGWarpMouseCursorPosition` no fim.

## 6b. Não atrapalhar quem está trabalhando (regra de convivência)

Clicar numa janela **traz essa janela para a frente** — não tem como evitar, é o macOS. Quem estiver usando o Mac na hora perde o foco, e isso atrapalha de verdade. Combinado com a Isadora em 28/10/2026:

- **Não ativar o DeviceHub a cada clique.** Ler a posição da janela no momento do clique (`System Events`) e clicar; nada de `open -a`/`activate` antes de cada passo.
- **Trabalhar em lote:** uma sequência de toques de cada vez (abrir o share, escolher o destino, enviar), não um toque a cada minuto enquanto ela usa o Mac.
- **Devolver o foco no fim do lote:** `osascript -e 'tell application "DeepSeek Harness" to activate'`.
- **Nunca reaproveitar coordenada de print antigo.** Capturar o framebuffer com `simctl` imediatamente antes, calcular o alvo, clicar e conferir com outra captura. Se o esperado não aconteceu, **parar e re-sincronizar** em vez de tentar de novo no mesmo lugar.
- **A janela só muda quando é redimensionada.** Mover muda só a origem (lida na hora). Se o tamanho mudar, recalibrar.
- **`CGWindowListCreateImage` não existe mais no macOS 26** (ScreenCaptureKit no lugar), então capturar a janela coberta não é trivial: prefira derivar o mapa uma vez e reusar, em vez de capturar a janela a cada passo. E lembre que `screencapture -R` captura **o que está na tela**: se a janela do DeviceHub estiver coberta, você fotografa a janela errada.
- **`CGEvent.postToPid` também traz a janela para a frente** — não é uma saída para o problema do foco.

## 7. O que não precisa de GUI nenhuma

```bash
# push simulado (payload próprio — ótimo para os avisos passivos)
xcrun simctl push <UDID> br.com.isacloud.messenger payload.json

# convites e deep links
xcrun simctl openurl <UDID> "xmpp:poli@isacloud.im?roster;preauth=<token>;ibr=y"

# log do app
xcrun simctl spawn <UDID> log show --last 3m --style compact --predicate 'process == "isaCloud"'

# banco do app (App Group)
xcrun simctl get_app_container <UDID> br.com.isacloud.messenger groups   # <grupo>/sworim.sqlite
sqlite3 -readonly "<grupo>/sworim.sqlite" "select account_id, username, domain, enabled from account;"
```

O `sqlite3` abre o banco em modo somente leitura, sem atrapalhar o app. Tabelas úteis: `account`, `buddylist`, `muc_favorites`, `message_history`, `message_search` (índice FTS5 do isaCloud).

## 8. Compilar por versão (contexto)

- **iOS 27** → Xcode 27.1 (SDK 27.1).
- **iOS 18.6** → Xcode 26.2 (`DEVELOPER_DIR=/Applications/Xcode-26.2.app/Contents/Developer`); um app compilado com o SDK 27 não abre no 18 (falta `libswiftCompatibilitySpan`).

```bash
xcodebuild -workspace Monal/Monal.xcworkspace -scheme Monal \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath build/sim27 \
  -clonedSourcePackagesDirPath build/dev-device/SourcePackages \
  -configuration Debug build
```

**Nunca use `CODE_SIGNING_ALLOWED=NO`**: sem assinatura o app perde o App Group e aborta na abertura (`MLAssert` em `getContainerURLForPathComponents:` dentro de `initSystem`). O `xcodebuild` e o SwiftPM precisam de acesso a `~/Library/Caches/org.swift.swiftpm` e abrem um sandbox próprio — num sandbox restrito isso falha com `Could not resolve package dependencies`.

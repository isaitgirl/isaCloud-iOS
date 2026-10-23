# isaCloud para iOS

Fork do Monal (cliente XMPP para iOS) com a marca e os ajustes do isaCloud. Branch de trabalho: `isaCloud`.

## Capturas de tela

- Salve toda captura de tela do simulador que mostre o app em `docs/screenshots/`, inclusive as tiradas só para conferir uma mudança.
- Nome do arquivo: `AAAA-MM-DD-HHMM-<aparelho>-<ios>-<tela-ou-assunto>.png`, em minúsculas e com hífens. Exemplo: `2026-10-23-1359-iphone-xr-ios18-boas-vindas.png`.
- Não apague nem sobrescreva capturas antigas; elas registram como o app estava em cada momento.
- As capturas feitas pela Isadora no app Simulator (⌘S) também caem nessa pasta, com o nome padrão do Simulator.

## Pendências

- **Reativar o push filtering.** A entitlement `com.apple.developer.usernotifications.filtering` foi removida em 23/10/2026 de `Monal/Monal.ios.entitlements` e `Monal/NotificationService/NotificationService.ios.entitlements`, porque a Apple só a libera mediante pedido (texto de referência em `push_filtering_entitlement.md`). Sem ela, todo push vira notificação visível. Depois de aprovada para a conta do isaCloud, recolocar `<key>com.apple.developer.usernotifications.filtering</key><true/>` nos dois arquivos.

# isaCloud para iOS

Fork do Monal (cliente XMPP para iOS) com a marca e os ajustes do isaCloud. Branch de trabalho: `isaCloud`.

## Instruções

- Pode ser simpático, sem ser engraçadinho demais o tempo todo!
- Responda às gentilezas e elogios com simpatia e humildade :)
- Qualquer alteração que possa causa complexidade no merge com o Monal deve ser validada.
- Os builds e testes devem sempre levar em consideração do iOS 18 ao 27.
- Não perguntar a todo instante sobre commitar o projeto, aguardar instrução do usuário.
- As traduções devem seguir os padrões do Monal, considerando o merge com weblate, mas as traduções do isaCloud devem prevalecer sobre elas.
- Estamos escrevendo o software em pt-br, mas você deve seguir as convenções de código do Monal, usando o idioma padrão dele e usando nosso mecanismo de tradução pro pt-br.
- Se identificar textos em inglês não traduzidos nos simuladores, você deve avisar o usuário e confirmar qual será a tradução.
- Busque implementar seguindo as convenções atuais do Monal, é importante respeitarmos esse legado para mantermos a menor fricção possível nos merges futuros.

## Capturas de tela

- Salve toda captura de tela do simulador que mostre o app em `docs/screenshots/`, inclusive as tiradas só para conferir uma mudança.
- Nome do arquivo: `AAAA-MM-DD-HHMM-<aparelho>-<ios>-<tela-ou-assunto>.png`, em minúsculas e com hífens. Exemplo: `2026-10-23-1359-iphone-xr-ios18-boas-vindas.png`.
- Não apague nem sobrescreva capturas antigas; elas registram como o app estava em cada momento.
- As capturas feitas pela Isadora no app Simulator (⌘S) também caem nessa pasta, com o nome padrão do Simulator.

## Notas locais (fora do Git)

- Dados sensíveis ou pessoais (UDID de aparelhos, números de pedidos da Apple, contas de teste, caminhos de segredos) ficam em `isaCloud/local/NOTAS-LOCAIS.md`, que está no `.gitignore`. Modelo em `docs/NOTAS-LOCAIS.exemplo.md`.
- Os `.md` que vão para o Git (como este) não podem conter esses dados: aponte para as notas locais. Nunca cole valores de segredos em nenhum `.md`.

## ExyteChat (fork)

- O chat usa um fork nosso do ExyteChat (`isaitgirl/ExyteChat`, branch `isaCloud`, clone em `~/projects/swift/ExyteChat`). Mudanças na biblioteca ficam lá, pequenas, comentadas e em commits separados. Rotina de atualização e o que o fork muda: `docs/exytechat-fork.md`.

## Troubleshooting

- Comandos e procedimentos para investigar crashes e travamentos (TestFlight e isaCloud.dev, iPhone e simulador): `docs/troubleshooting.md`. Quando aprender um comando útil novo, acrescente lá.

## Pendências

- **Reativar o push filtering.** A entitlement `com.apple.developer.usernotifications.filtering` foi removida em 23/10/2026 de `Monal/Monal.ios.entitlements` e `Monal/NotificationService/NotificationService.ios.entitlements`, porque a Apple só a libera mediante pedido (texto de referência em `push_filtering_entitlement.md`). Sem ela, todo push vira notificação visível. Pedido enviado à Apple em 24/10/2026 (número do pedido em `isaCloud/local/NOTAS-LOCAIS.md`); a resposta chega por e-mail. Enquanto isso, o app de produção mostra a notificação genérica "New Message / New Message?" (texto do payload do `fpush`) quando decide não notificar. Depois de aprovada para a conta do isaCloud, ativar a capacidade nos App IDs do app e da extensão (`br.com.isacloud.messenger` e `.notificationService`), recolocar `<key>com.apple.developer.usernotifications.filtering</key><true/>` nos dois arquivos.

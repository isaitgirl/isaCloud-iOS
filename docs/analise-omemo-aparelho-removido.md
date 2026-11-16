# OMEMO: mensagens de aparelho removido da lista eram descartadas (build 111)

## Sintoma

Em grupos criptografados (e em conversas em geral), mensagens genuínas de um contato se perdiam. O app mostrava "Não é possível descriptografar pois você não confiou no dispositivo N do remetente". Esse texto estava errado: a usuária nunca recusou aparelho nenhum.

## Evidência (log e banco de produção, 15/11/2026)

- Log: três mensagens distintas do mesmo contato, com cerca de 40 a 50 segundos de intervalo, todas com `prekey='true'` para o aparelho da usuária, todas descartadas com a mensagem "não confiou".
- Banco: o contato tem um único aparelho com `trustLevel=1` (ToFU padrão, ou seja, sem decisão da usuária) e `removedFromDeviceList` marcado em 11/11 às 13:30. A última mensagem recebida desse aparelho é de 04/11.
- O aparelho continua em uso pelo contato: ele mandou as mensagens hoje.

## Causa no código

- `Monal/Classes/MLSignalStore.m`, `knownDevicesForAddressName:withRemovedDevices:` e as consultas com `removedFromDeviceList IS NULL` (cerca das linhas 252-282): o aparelho marcado como removido sai do `recipientDeviceMap` usado em `decryptOmemoEnvelope`.
- `Monal/Classes/MLOMEMO.m`, `decryptOmemoEnvelope:` (cerca das linhas 1430-1470): sem o aparelho no mapa, a mensagem caía no `else` final ("but not trusted: ignoring!") e devolvia o texto de "não confiou". A única exceção existente era para aparelho desconhecido (sem identidade gravada), do `allowMixedTrustInGroups`.

## Comparação com o Android

No fork do Conversations usado pelo Android (`src/main/java/eu/siacs/conversations/crypto/axolotl/AxolotlService.java`, linhas 459-485 e 2204-2260):

- A lista de aparelhos só marca sessões como inativas ou ativas (`toInactive` / `toActive`). Isso serve para **enviar**.
- No **receber**, `getReceivingSession` acha ou cria a sessão por (jid, deviceId) e decifra. Não consulta a lista, o estado ativo nem a confiança.
- O aparelho volta a ficar ativo quando reaparece na lista.

Ou seja, no Android a mensagem de um aparelho que saiu da lista é decifrada normalmente.

## O que foi implementado (build 111)

Em `decryptOmemoEnvelope:` (`MLOMEMO.m`), antes do `else if(deviceIsUnknown)` e do `else` final, foram acrescentados dois ramos:

1. **Aceitar** quando o aparelho é conhecido, está marcado como removido da lista, é apenas ToFU (`trustLevel=1`, nunca marcado pela usuária), o contato não tem decisão explícita de confiança, `allowMixedTrustInGroups` está ligado e a mensagem é um PreKeyMessage para o nosso aparelho. Nesse caso o app:
   - grava um log `isaCloud: accepting prekey message from device ... that was removed from the device list (still in use), reactivating...`;
   - limpa a marca de removido (`removeDeviceDeletedMark:`, já existente);
   - pede de novo a lista de aparelhos do contato (`queryOMEMODevices:withSubscribe:NO`), para que a lista real seja a fonte da verdade;
   - segue com a decifração normal.
2. **Texto novo** quando o aparelho está removido da lista e a condição acima não se aplica (exceto se a usuária marcou o aparelho como não confiável): "Could not decrypt because the sender's device %u was removed from their device list.", com tradução pt-BR no override do isaCloud (`isaCloud/localization/pt-BR.lproj/Localizable.strings`). O texto "você não confiou" ficou só para aparelho realmente não confiável.

Também foi acrescentado em `MLOMEMO.m` um cálculo de `deviceIsRemovedFromList`, `deviceIsTofuOnly` e `deviceIsExplicitlyUntrusted`, usando `getRemovedFromDevicelistTime:` e `getInternalTrustLevel:identityKey:`, ambos já declarados em `MLSignalStore.h`.

Os comentários `//isaCloud:` no código explicam o porquê e as ressalvas.

## Decisão e ressalvas

- **Risco de segurança:** o app passa a aceitar um aparelho que o contato removeu da lista. Se o contato removeu de propósito um aparelho, mensagens desse aparelho podem ser decifradas. Mitigação: exige PreKeyMessage para o nosso aparelho, ToFU, sem confiança explícita e a opção `allowMixedTrustInGroups`.
- **Possível passo seguinte:** a Isadora avaliou seguir o Android por completo (decifrar de qualquer aparelho conhecido, sem exigir PreKeyMessage nem a opção de grupos). O motivo é que o risco real de decifrar nesses casos é baixo e usuárias estão perdendo mensagens genuínas. Isso ainda não foi feito.
- **Mensagens já descartadas** continuam com o aviso. Elas não são recuperadas automaticamente: o contato precisa enviar de novo, ou a usuária pode pedir.

## Como validar

- Log: `isaCloud: accepting prekey message from device ... that was removed from the device list`, seguido de uma decifração bem-sucedida.
- Nova mensagem do contato, enviada depois do aceite, decifra na conversa.
- Para aparelho que a usuária não confia, o texto continua "você não confiou".

## Como desfazer

Remover os dois ramos novos (o ramo `deviceIsRemovedFromList && deviceIsTofuOnly` e o `else if(deviceIsRemovedFromList && !deviceIsExplicitlyUntrusted)`), as três variáveis novas e a chave pt-BR nova. O texto em inglês volta a cair no "não confiou" do `else` final.

## Build 112

### Por que o 111 não bastou

- O 111 aceitava o aparelho removido só com quatro condições juntas: ToFU, sem confiança explícita do remetente, `allowMixedTrustInGroups` ligado e PreKeyMessage para o nosso aparelho.
- Em 16/11/2026 o contato mandou nova mensagem num grupo e o 111 ainda descartou ("removido da lista de dispositivos"). Algum dos critérios falhou, provavelmente o de PreKeyMessage, mas o log não cobre o momento, então isso não está confirmado.

### O que mudou

- Em `decryptOmemoEnvelope:` (`MLOMEMO.m`), o ramo de aceite passa a valer para qualquer aparelho conhecido (com identidade gravada) marcado como removido da lista. Não exige mais PreKeyMessage, ToFU nem `allowMixedTrustInGroups`. Assim como no Android (receber não consulta a lista), a mensagem é decifrada.
- Ao aceitar: log `DDLogInfo` com o caminho usado e os valores (PreKey, confiança interna, confiança explícita do remetente, opção de grupos), `removeDeviceDeletedMark:` e `queryOMEMODevices:withSubscribe:NO` para o remetente.
- Recusa de aparelho removido: `DDLogWarn` com o motivo exato. A recusa de aparelho não confiável também grava os valores.
- O aparelho desconhecido (sem identidade gravada) continua com o mesmo comportamento.

### Bloqueios mantidos

1. Aparelho que a usuária marcou como não confiável (`MLOmemoInternalNotTrusted`) continua bloqueado, com o texto "você não confiou".
2. Remetente com confiança explícita ativada (`hasExplicitOmemoTrustActivated`) não aceita aparelho removido automaticamente.

### Como validar

- Log: `isaCloud: accepting message from known device ... (path: known removed device; ...)`, seguido de decifração bem-sucedida.
- Nova mensagem do contato, enviada depois do aceite, decifra na conversa.
- Se ainda recusar, o log `isaCloud: refusing message ...` diz qual bloqueio pegou.
- Mensagens já descartadas não são recuperadas por esta mudança.

### Pendência

- Recuperar mensagens já descartadas (reprocessar do histórico ou do MAM) é uma frente à parte.

### Como desfazer

- Voltar ao build 111 ou remover o ramo `accept known removed device` em `decryptOmemoEnvelope:`.

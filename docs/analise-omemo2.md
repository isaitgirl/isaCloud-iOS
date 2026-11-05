# OMEMO 2 (XEP-0384 com `urn:xmpp:omemo:2`): situação em 05/11/2026

Levantamento feito para saber se vale a pena o isaCloud acompanhar o OMEMO 2. **Resumo:** a especificação existe há anos, mas só dois clientes grandes já usam o OMEMO 2 (Converse.js 14 e Kaidan). Nem o Monal nem o Conversations estão nesse caminho, então por enquanto não há motivo para mexer.

## A XEP-0384 (OMEMO Encryption)

- **Situação:** versão **0.9.1**, de 06/04/2026, ainda **Experimental**. Nunca chegou a Draft ou Stable.
- **O que é o "OMEMO 2":** é o namespace `urn:xmpp:omemo:2`, que existe desde a versão 0.8.0 (2021). Usa os nós PEP `urn:xmpp:omemo:2:devices` e `urn:xmpp:omemo:2:bundles`, e o conteúdo vai dentro de um envelope **SCE** (XEP-0420, `urn:xmpp:sce:1`). Hoje o OMEMO só cifra o corpo da mensagem; com o SCE, outros elementos podem ir cifrados também (anexos, reações, figurinhas).
- **É um protocolo separado** do legado `eu.siacs.conversations.axolotl` (a versão 0.3, a que o Monal e o Conversations usam): sessões, bundles e lista de aparelhos são outros. Um cliente que quiser conversar com os dois mundos precisa manter os dois em paralelo.
- **Histórico recente:**

| Versão | Data | Mudança |
|---|---|---|
| 0.8.0 | 28/09/2021 | Namespace `urn:xmpp:omemo:2` e SCE v0.4 (`envelope`/`content`, `urn:xmpp:sce:1`). |
| 0.8.1 | 07/10/2021 | Nós `:bundles` e `:devices` sob `urn:xmpp:omemo:2`. |
| 0.8.2 / 0.8.3 | dez/2021, jan/2022 | Tamanho do HMAC (32 vs 16 bytes) e links. |
| 0.9.0 | 07/04/2025 | Rótulos de aparelho assinados com a chave de identidade (`labelsig`); lista de aparelhos pode vir vazia; texto deixa claro que ToFU e BTBV ("confiar até verificar") continuam válidos; orientação para quem não tem assinatura de presença; saiu a referência ao "session healing". |
| 0.9.1 | 06/04/2026 | Só corrigiu os exemplos que usavam id 0. |

- **Em grupos:** a sala precisa ser não anônima (de preferência só para membros); o remetente busca as listas de membros, admins e donos e cifra para os JIDs reais de todos, inclusive os offline; a mensagem leva um `to` dentro do envelope SCE.

## O que se tem discutido

- **Pós-quântico:** há uma thread na lista standards@xmpp.org ("Post-quantum security of OMEMO"). Uma resposta de julho de 2026 conta que o **monocles** trabalha numa variante pós-quântica (`pq-omemo-2`, no Codeberg). Por enquanto é só do monocles, não virou proposta de XEP. A XEP em si não fala do assunto.
- **MLS como alternativa:** é por isso que o Monal não fez o OMEMO novo (ver a seção do Monal).
- **Conversations parado no legado:** num log do grupo de criptografia da XSF (E2EE SIG) de 12/02/2026, alguém registra que o Conversations 2.19.10 ainda não tinha passado para o `omemo:2`. Não achei anúncio oficial de planos.

## Quem implementa

| Cliente | OMEMO 2 | Observação |
|---|---|---|
| **Converse.js 14** | sim | Lançado em 26/06/2026 com a nova libomemo.js (WebAssembly, financiada pela NLnet). Mantém o legado em paralelo. Sites com CSP estrita precisam liberar `wasm-unsafe-eval`. |
| **Kaidan** | sim | Via QXmpp; foi o primeiro grande a adotar. Já foi só OMEMO 2, por isso não falava com o resto. |
| **Libervia, Moxxy, monocles (desktop)** | sim | Libervia usa o python-twomemo. |
| **Dino** | não | O pedido (dino/dino#1442) segue aberto; a última versão é a 0.5.1 (nov/2025). |
| **Gajim** | provavelmente não | O OMEMO embutido desde a 1.8 é o legado. Uma issue de terceiros diz que ele "lê" o OMEMO 2, mas não achei confirmação oficial. |
| **Conversations** | não | No legado. O fork Android do isaCloud (`isaCloudMessenger`) também não tem nenhum `omemo:2`. |
| **Monal** | não | Ver abaixo. |

## No repositório do Monal

- **Código:** o Monal é **100% legado** (`eu.siacs.conversations.axolotl` em `Monal/Classes/MLOMEMO.m` e `Monal/Classes/MLMessageProcessor.m`). Os únicos sinais de OMEMO 2 são dois comentários de preparação em `MLOMEMO.m` (perto das linhas 962 e 1118): avisam que, no OMEMO 2, a comparação com "nosso próprio aparelho" precisa considerar o JID, não só o device id.
- **Issue monal-im/Monal#372** ("Implement (new) OMEMO:1"): fechada em 2023 pelo Thilo Molitor, porque ele acha que "a maioria dos clientes vai pular direto para o MLS".
- **Sem PR nem branch de OMEMO 2** no GitHub deles. A única branch com OMEMO no nome é `friedrich/omemo_changes_in_history`, que trata de outra coisa (avisos de aparelhos no histórico).
- **O mais recente lá:** um retrabalho de pré-chaves e aparelhos ("Rework OMEMO preKey, device and session handling", Thilo, 10/10/2026), que já está na nossa `develop`. No histórico também há uma reescrita grande do OMEMO ("Refactor/rewrite whole OMEMO code") que foi revertida.

## O que isso significa para o isaCloud

Por enquanto não há motivo para mexer. Os clientes com quem mais conversamos (Conversations, o nosso Android e o Monal) só falam o legado. Fazer o OMEMO 2 por conta própria seria uma mudança grande no núcleo do OMEMO, justamente o tipo de divergência que complica o merge com o Monal.

Vale ficar de olho em três coisas:

1. o Conversations migrar para o `omemo:2`;
2. o Monal se decidir entre OMEMO 2 e MLS;
3. a XEP sair de Experimental.

## Fontes

- [XEP-0384: OMEMO Encryption](https://xmpp.org/extensions/xep-0384.html)
- [UPDATED: XEP-0384 (lista standards)](https://mail.jabber.org/hyperkitty/list/standards@xmpp.org/thread/ZOJCCMBLGS7VSX75EUOMFFW535Y5JQXP/)
- [Post-quantum security of OMEMO (lista standards)](https://mail.jabber.org/hyperkitty/list/standards@xmpp.org/thread/UTZPYT5WA3QVJPCDUWIOFPB7V43R6ATI/)
- [Converse.js v14.0.0](https://github.com/conversejs/converse.js/releases/tag/v14.0.0)
- [libomemo.js v2.0.0](https://github.com/conversejs/libomemo.js/releases/tag/v2.0.0)
- [Debian XMPP Team: Trixie (Kaidan com OMEMO 2)](https://xmpp-team.pages.debian.net/blog/2025/05/xmpp-debian-13-trixie-news.html)
- [Kaidan (KDE)](https://apps.kde.org/kaidan/)
- [dino/dino#1442](https://github.com/dino/dino/issues/1442)
- [libomemo-c (Dino)](https://github.com/dino/libomemo-c)
- [Log do E2EE SIG, 12/02/2026](https://logs.xmpp.org/e2ee/2026-02-12)
- [JumpLink/curlew#106](https://github.com/JumpLink/curlew/issues/106)
- [Fórum FreeBSD: OMEMO for XMPP](https://forums.freebsd.org/threads/omemo-for-xmpp-on-freebsd.90599/)
- [monal-im/Monal#372](https://github.com/monal-im/Monal/issues/372)
- [monal-im/Monal#9](https://github.com/monal-im/Monal/issues/9)
- [Are we OMEMO yet?](https://omemo.top/)

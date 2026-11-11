# Análise pré-implementação: convites de grupos e canais como solicitações pendentes

Status: **analisado em 11/11/2026, nada implementado** (roadmap 168). Fontes: o código desta árvore (isaCloud/Monal) e o isaCloud Android (`~/projects/java/isaCloudMessenger`, branch `custom`), em especial `docs/decisoes-convites-pendentes.md`, `PendingInviteManager` e `PendingInviteStore`. Nada foi testado nos servidores.

## 1. O que o Android passou a fazer

No Android, nenhum convite de grupo ou canal faz o app entrar sozinho na sala, nem quando quem convida é um contato. Todo convite vira uma **pendência** com **Aceitar** e **Recusar**. Ela aparece junto dos pedidos de contato, numa seção no topo da aba **Todos** de Contatos, e o botão **Iniciar conversa** mostra um selo com a soma dos dois tipos. A regra completa está em `docs/decisoes-convites-pendentes.md` no repositório do Android. Este documento resume essa regra e diz o que muda no iOS.

## 2. As duas XEPs envolvidas

| | Convite mediado (XEP-0045, §7.8.2) | Convite direto (XEP-0249) |
|---|---|---|
| Caminho | quem convida → sala → convidado | quem convida → convidado |
| Elemento | `<x xmlns="http://jabber.org/protocol/muc#user"><invite from="…"/></x>`, `from` da mensagem = sala | `<x xmlns="jabber:x:conference" jid="sala"/>`, `from` da mensagem = quem convida |
| Quem convidou | campo `invite@from`, preenchido pela sala: JID real **ou JID de ocupante** (`sala@conference/Apelido`) | o `from` da própria mensagem, autenticado pelo servidor |
| Recusa | `<decline>` pela sala | não existe recusa padronizada |

**O bug que o Android corrigiu:** os canais públicos são criados com `whois=moderators` (salas semi-anônimas). Nesse caso o Prosody põe o JID de ocupante em `invite@from`, para não expor o JID real. O convidado não reconhece esse endereço como contato e, com **Convites de desconhecidos** desligado, descarta o convite. Por isso, para canais públicos (sem `membersonly`), o Android passou a enviar convite direto. Para grupos ele mantém o mediado, porque grupo é `members-only` com `whois=anyone`: o JID real aparece e o convite vem acompanhado da afiliação de membro.

## 3. Como o iOS está hoje

### Envio

`-[MLMucProcessor inviteUser:inMuc:]` (`MLMucProcessor.m`, perto da linha 1557) **sempre** manda convite direto (XEP-0249), tanto para grupo quanto para canal, e o iOS não tem envio mediado. Os pontos de chamada são `CreateGroupMenu.swift` (que antes dá `setAffiliation member`) e `MemberList.swift` (convidar ou reconvidar).

Conclusão: **o problema de envio que o Android corrigiu não acontece no iOS.** Como os convites do iOS chegam ao Android com o JID real, eles já caem nas pendências de lá. Não há o que mudar no envio.

### Recebimento

O recebimento fica em `-[MLMucProcessor processMessage:…]` (`MLMucProcessor.m`, linhas 571 a 613). `MLMessageProcessor` já descarta convites que chegam pelo MAM ao rolar o histórico.

- **Mediado:** pega o JID de `invite@from` com `splitJid(...)[@"user"]`. Se o contato tem assinatura `from` (`isSubscribedFrom`), entra na hora (`sendDiscoQueryFor:withJoin:YES andBookmarksUpdate:YES`). Caso contrário, ignora em silêncio.
- **Direto:** mesma regra, mas o JID de quem convida vem do `from` da mensagem.
- Copiar a própria mensagem (carbon) e mensagens que não são para a própria conta: ignorados.

Diferenças em relação ao Android:

1. **Não existe pendência.** Convite de contato faz o app entrar sozinho (o comportamento original do Monal).
2. **Não existe a opção "Convites de desconhecidos".** Convite de quem não é contato é descartado sempre. (A linha `allowNonRosterContacts` está comentada no código do Monal.)
3. **O mesmo bug de recebimento do Android acontece aqui.** Num convite mediado vindo de canal com `whois=moderators`, `splitJid("sala@conference/Apelido")` vira `sala@conference`, que não é contato, e o convite é descartado. Hoje isso só acontece quando quem convida usa um cliente que manda convite mediado para canal: o Android antes da correção, o Conversations, o Gajim, etc. Os grupos criados pelo iOS usam `whois=anyone` (`_mandatoryGroupConfigOptions`, `MLMucProcessor.m:77`), então neles o JID real chega normalmente.
4. **Não há limite de idade, limite de quantidade nem verificação de bloqueio** antes de entrar.

## 4. Proposta para o iOS (acompanhando o Android)

### Regras de recebimento (iguais às do Android, na mesma ordem)

1. **Idade:** usar o horário original (`<delay>` ou MAM) e ignorar convites com mais de 30 dias.
2. **Bloqueado:** se quem convidou está bloqueado, ignorar.
3. **Própria conta:** carbon ou MAM de um convite que a própria conta enviou; ignorar.
4. **Desconhecido:** quem convidou não está no roster e a opção está desligada; descartar. Convite mediado com JID de ocupante (o recurso do `invite@from` é a própria sala) conta como **desconhecido**, porque não há como confirmar quem convidou. É o mesmo efeito do Android.
5. **Já está na sala:** ignorar e apagar uma pendência que já exista para essa sala.
6. **Limite:** 50 pendências por conta; um convite para uma sala nova acima disso é descartado, mas atualizar uma pendência que já existe continua valendo.
7. **Uma pendência por conta e sala:** um convite novo atualiza quem convidou, a senha e o horário, e o horário nunca volta para trás.
8. Gravar e avisar a UI (`MLNotificationQueue`). Buscar nome e tipo da sala por `disco#info` em segundo plano.

**Atenção:** a NSE (`NotificationService`) também roda o `MLMucProcessor`, então o convite pode chegar com o app fechado. A gravação da pendência precisa funcionar lá dentro e não pode puxar código de UI.

### Tela

- Seção de pendências junto do `ContactRequestsMenu.swift` (que hoje lista só pedidos de contato), com as **pendências de convite** depois dos pedidos de contato. O ícone e a ordem seguem o Android: pedidos de A a Z e convites do mais recente para o mais antigo.
- **Aceitar:** apagar a pendência, aplicar a senha do convite, desarquivar e voltar a mostrar a sala, se for o caso (ver roadmap 164 e a sincronização de arquivados), entrar com bookmark e abrir a conversa. Se a conta estiver desconectada, **manter** a pendência e avisar.
- **Recusar:** apagar a pendência. Se o convite foi mediado, mandar `<decline to="quem convidou"/>` para a sala. Se foi direto, só apagar.
- **Bloquear:** bloquear quem convidou e apagar a pendência.
- Selo com a soma de convites e pedidos no ponto de entrada (no Android fica no botão Iniciar conversa; no iOS, onde hoje aparecem os pedidos de contato).
- Opção **Convites de desconhecidos** em Privacidade, desligada por padrão. Precisa de valor padrão antes de qualquer tela ler a chave (crash C18, ver `docs/analises-crashes.md`). Os textos novos precisam de tradução pt-BR no override do isaCloud.

## 5. Banco: sem tocar na escada do Monal

O Android criou um **banco SQLite próprio** (`IsacloudDatabase`, com versão própria) para não mexer no `DATABASE_VERSION` do Conversations.

**O iOS já resolve isso de outro jeito:** os dados do isaCloud ficam no mesmo `sworim.sqlite`, mas com uma **escada de migrations própria**, fora da escada do Monal:

- `+[DataLayerMigrations migrateISACloudDB:]` roda depois do último passo do Monal (7.013) e guarda a versão na flag `isacloud_dbversion` (1, 2, 3…; hoje está em **7**, arquivados).
- Os primeiros builds usavam os números 7.014 a 7.016 da escada do Monal. `moveISACloudMigrationsOutOfMonalLadder:` devolve esses bancos para 7.013, para que as próximas migrations do Monal rodem normalmente quando chegarem num merge.
- Os passos do isaCloud podem rodar de novo sem estrago (`IF NOT EXISTS`, ou consultando `pragma_table_info` antes de um `ALTER`).

**Recomendação:** criar o passo **8** da escada do isaCloud com uma **tabela nova e só nossa**, `isacloud_pending_invites`, com `CREATE TABLE IF NOT EXISTS`. A tabela não deve ter `ALTER` nem chave estrangeira apontando para tabelas do Monal (só `account_id` como inteiro) e precisa de `UNIQUE(account_id, room)`. Colunas, iguais às do Android: `account_id`, `room`, `invited_by`, `password`, `received_at`, `mediated`, `room_name`, `is_channel`. Assim:

- a versão do Monal não muda e nenhuma tabela do Monal é alterada; um merge que traga 7.014+ do Monal roda sem conflito;
- o prefixo `isacloud_` evita choque de nome com tabelas que o Monal venha a criar;
- ao remover uma conta, apagar as pendências dela no mesmo ponto em que o Monal apaga o resto, e limpar pendências de contas que não existem mais na abertura do app (como o `pruneOrphans` do Android).

Um banco separado, como no Android, **não compensa** no iOS. O app e a NSE já compartilham o `sworim.sqlite` pelo App Group, com o bloqueio de escrita do `MLSQLite`. Um segundo arquivo exigiria abrir e coordenar outra conexão nos dois processos, sem ganho, já que a escada própria já separa as migrations.

## 6. Custo e riscos

- **Esforço:** médio, cerca de 2 a 3 dias. Banco e loja de pendências: 0,5. Regras de recebimento com a NSE: 0,5 a 1. Tela, aceitar/recusar/bloquear e selo: 1. Opção, traduções e testes: 0,5.
- **Risco principal:** mexer em `MLMucProcessor.processMessage` (código do Monal) exige atenção no próximo merge. Manter a mudança pequena, com comentário `//isaCloud`, delegando para um arquivo nosso.
- **Comportamento novo para quem usa:** convites de contatos deixam de entrar sozinhos. Isso vale também para o grupo que alguém cria pelo iOS e onde já marca a pessoa como membro: ela vai precisar aceitar. É o mesmo comportamento do Android.
- **Testes:** convite direto de contato; convite mediado de grupo (`whois=anyone`) e de canal (`whois=moderators`, que deve contar como desconhecido); desconhecido com a opção ligada e desligada; convite com o app fechado (NSE); aceitar com a conta desconectada; recusar um mediado (o Android deve ver o `decline`).

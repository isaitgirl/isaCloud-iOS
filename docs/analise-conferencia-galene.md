# Vídeo conferência pelo Galene — análise (Android + servidor)

Data: 21/11/2026. Branch: `custom`. Status: **análise concluída, nada implementado**.

Objetivo: ter no clipe de anexos do isaCloud Messenger uma ação **“Criar conferência”** que
gera um link de vídeo chamada e o insere no compositor; quem recebe o link cai numa tela com
nome/descrição/anfitrião da sala, campo de apelido e botão de entrar; a sala é efêmera e morre
quando o anfitrião sai (ou quando todos saem).

Servidor analisado: `srv-05.isacloud.cc`, `/opt/docker/galene`, imagem própria
`cr.isacloud.cc/apps/galene:latest` (Galene **1.2.1**, compilado a partir do fonte no Dockerfile),
publicado em <https://meet.isacloud.cc> via nginx do próprio servidor.

---

## 1. Resumo da recomendação

1. **Salas efêmeras**: usar **auto-subgroups** do Galene dentro do grupo `u`
   (`https://meet.isacloud.cc/u/<id>/`). A sala nasce na primeira entrada, existe **só em memória**
   e desaparece sozinha depois de ficar vazia. Nenhum arquivo é criado em `groups/`.
2. **Encerrar quando o anfitrião sai**: `autokick: true` no `u.json` (herdado pelos subgrupos).
   Testado: o anfitrião sai e todos são expulsos, e quem tenta entrar depois é barrado com
   “there are no operators in this group”.
   **Não** usar `autolock` (que está ligado hoje): ele bloqueia também os convidados **com o
   anfitrião dentro**, até alguém digitar `/unlock`. Ver §4.3.
3. **Identidade/entrada**: **tokens stateful** (não JWT). Um token por pessoa, com
   `group = u/<id>`, `username = apelido` e `expires`. O anfitrião recebe permissões de operador,
   o convidado recebe só `present`. A entrada é `https://meet.isacloud.cc/u/<id>/?token=<token>`,
   que o cliente Galene conecta direto, sem tela de login.
4. **Precisa de um serviço pequeno** (`meet-api`) porque:
   - emitir token exige credencial de admin do Galene (não pode ir no APK);
   - auto-subgroups **não guardam metadados por sala** (nome/descrição/anfitrião vêm todos do
     `u.json`), então esses dados têm que morar em algum lugar nosso.
5. **Link compartilhado** é neutro: `https://meet.isacloud.cc/join/<id>` (mostra a info e o campo
   de apelido). O token **nunca** vai no link compartilhado — só na URL que o app do anfitrião
   abre, depois da tela de entrada.

---

## 2. Como o servidor está hoje

| Item | Estado |
|---|---|
| Versão | Galene 1.2.1 (upstream mais recente: 1.2.2) |
| Execução | container `galene`, HTTP simples na 8443 atrás do nginx (`-insecure`), TURN embutido em `meet.isacloud.cc:1194` e UDP 49160–49200 |
| Grupos | `groups/*.json`: `default`, `aulapro`, `daily`, `federana`, `isa`, `luasmile`, `og`, `u` |
| Grupo `u` | `displayName: "isaCloud Meet"`, `auto-subgroups: true`, `autolock: true`, `authPortal: https://passport.isacloud.cc/galene/login`, `authKeys` HS256 (`kid passport-2026-08`) |
| Usuários | `u.json` não tem `users` nem `wildcard-user` → no `u` só entra quem tem token. Os outros grupos usam senha (bcrypt) |
| Admin | `data/config.json` tem `admin` com permissão `admin`, `writableGroups: true`, `canonicalHost: meet.isacloud.cc` |
| API administrativa | `galene-api/v0/` **está exposta na internet** (401 sem credencial) |
| Credenciais do `galenectl` | `galenectl.json` diz `admin/admin`, mas a senha real é outra (a que está no `dados.txt`); o `galenectl` como está **não autentica** |
| Portal de autenticação | `passport.isacloud.cc/galene/login` responde **404**. Existe o serviço `isacloud-passport` (Go, systemd, SQLite, SMTP) no `srv-07`, mas ele só faz recuperação de conta — não há rota de Galene |
| Proxy | nginx do `srv-05`: `/ws` com upgrade, `/u/([^/]+)/?` → `/group/u/$1/`, `/` → `/group/default/` |

O `authPortal` apontando para uma URL 404 é um problema atual: qualquer pessoa que abra
`https://meet.isacloud.cc/u/qualquer/` sem token é redirecionada para uma página quebrada.

---

## 3. O que o Galene oferece para cada requisito

### 3.1 Salas efêmeras — auto-subgroups

`u.json` com `"auto-subgroups": true` faz qualquer nome `u/<qualquer>` existir sob demanda:

- a descrição é **herdada** do `u.json` (usuários, chaves, autolock/autokick, `max-clients`…);
- o grupo vive **apenas em memória**, não cria arquivo em `groups/`;
- subgrupo é sempre não público (não aparece em `/public-groups.json`, não aparece na home);
- `group.Update()` remove da memória qualquer grupo não público **vazio** cuja última atividade
  passou de `max-history-age` (padrão 4 h).

Consequência: **nome/descrição/anfitrião por sala não existem no Galene**. Todos os subgrupos
compartilham o mesmo `displayName` do `u.json`. Por isso a tela de entrada tem que buscar esses
dados no nosso serviço.

### 3.2 Encerramento

| Campo | Comportamento verificado no código |
|---|---|
| `autokick: true` | quem não é operador **não entra** enquanto não houver operador na sala; quando o último operador sai, **todos são expulsos** |
| `autolock: true` | a sala **começa trancada** e volta a trancar quando não há operador; destrancar é manual (`/unlock`, menu ou comando) |
| `max-history-age` | tempo até o grupo vazio sair da memória (também define retenção do chat) |
| `expires` / `not-before` | valem para o arquivo de grupo, ou seja, **não dá para usar por sala** em auto-subgroups |

### 3.3 Autenticação

| Mecanismo | Como funciona | Serve aqui? |
|---|---|---|
| `users` / `wildcard-user` (senha) | usuário/senha por grupo, com bcrypt | Não: senha é por grupo, não por sala; `wildcard-user` daria a mesma senha para todos |
| **Token stateful** | token aleatório guardado no servidor (`data/var/tokens.jsonl`), com grupo, usuário, permissões e validade; criado por `/invite` na sala ou pela API (`POST .groups/<grupo>/.tokens/`) | **Sim** — é a base da proposta |
| Token criptográfico (JWT) | assinado por terceiro com `authKeys` (HS256/ES256/RS256), `sub`, `aud`, `permissions`, `exp` obrigatório | Sim, se existir um emissor confiável (o `authKeys` já está no `u.json`) |
| `authServer` / `authPortal` | delega o login a um serviço externo | Não no estado atual: o portal aponta para 404 e o cliente redireciona **sem informar a sala** |

Detalhes que importam para o desenho:

- Permissão no token é **lista crua**. `["op"]` faz a pessoa ser operadora mas **sem publicar
  áudio/vídeo**. O correto é a lista expandida: anfitrião
  `["op","present","message","caption","token"]`, convidado `["present","message"]`.
  (Foi exatamente o que o `galenectl create-token -permissions op` faz por baixo.)
- Token stateful com `username` preenchido dispensa a tela de login; o nome que o cliente mandar
  é ignorado. Sem `username`, o Galene pede o nome (“need-username”).
- `POST .groups/u/<id>/.tokens/` **funciona mesmo que `u/<id>` ainda não exista** (a descrição é
  resolvida no `u.json`). Testado.
- Token para grupo que não é subgrupo de um `auto-subgroups` → 404. Testado.
- O cliente web lê `?token=` na query e conecta direto; depois faz `history.replaceState` e tira
  o token da barra de endereço.

### 3.4 O que o cliente web mostra antes de entrar

`static/galene.html` só tem título (do `displayName`) + campos de usuário/senha. **Não mostra
descrição nem anfitrião.** O `/u/<id>/.status` de um subgrupo devolve
`name`, `location`, `endpoint`, `displayName` e `authPortal` — sem `description` e sem contagem de
clientes (visitante não autenticado).

Ou seja: a “tela de entrada” pedida **não existe** no Galene e tem que ser nossa (página web
e/ou Activity no app).

---

## 4. Validação feita no servidor em 21/11/2026

Tudo abaixo foi executado contra `meet.isacloud.cc` e desfeito depois (tokens apagados, grupo de
teste removido; `tokens.jsonl` terminou vazio).

### 4.1 API administrativa e criação de token

- `GET /galene-api/v0/.groups/` autentica com o usuário `admin` e a senha do `dados.txt`
  (a do `galenectl.json` não funciona).
- `POST /galene-api/v0/.groups/u/teste-isa/.tokens/` com
  `{"permissions":["present","message"],"username":"Convidado","expires":"..."}` → **201**,
  retornando o token no cabeçalho `Location`.
- `DELETE` do token → **204**.

### 4.2 Entrada com token

Cliente WebSocket cru (`wss://meet.isacloud.cc/ws`, handshake versão 2 + `join` com `token`):

- token de operador (`["op","present","message","caption","token"]`) → **entrou**, permissões
  devolvidas iguais às enviadas;
- token de convidado com o `u.json` atual → **falhou: “this group is locked”**.

### 4.3 O problema do `autolock`

Com `autolock: true` (estado atual):

1. o anfitrião entra normalmente (é operador);
2. o convidado **continua barrado** com “this group is locked”;
3. só depois de o anfitrião enviar `/unlock` o convidado entra;
4. quando o anfitrião sai, a sala tranca de novo.

Ou seja, o fluxo “clicou no link, digitou o apelido, entrou” **não funciona** com `autolock`.

### 4.4 `autokick` resolve

Grupo de teste com `{"autokick": true, "max-history-age": 600}`:

1. anfitrião entra;
2. convidado entra na hora, sem `/unlock`;
3. anfitrião sai → convidado recebe `usermessage/kicked` (“there are no operators in this group”)
   e a conexão fecha;
4. novo convidado sem anfitrião → **barrado** com “there are no operators in this group”.

Também confirma que a sala fica “inutilizável” assim que o anfitrião sai, mesmo que o objeto do
grupo ainda fique na memória até o `max-history-age`.

### 4.5 Outros achados

- `https://meet.isacloud.cc/galene-api/v0/.groups/` responde 401 pela internet (API exposta).
- `data/var/tokens.jsonl` não é servido pelo nginx (404).
- `/u/<id>/` é reescrito para `/group/u/<id>/` preservando a query string.
- `/u/<id>/.status` devolve o JSON do subgrupo (sem descrição).

---

## 5. Arquitetura proposta

```
Android (clipe de anexos)                nginx (srv-05)                Galene (srv-05)
        |                                     |                             |
        |-- POST /meet-api/v1/rooms --------->|--- meet-api (Go) ---------->| POST .groups/u/<id>/.tokens/  (admin)
        |                                     |      SQLite (salas)          |
        |<-- { roomUrl, hostUrl } ------------|                             |
        |                                     |                             |
        |-- POST /meet-api/v1/rooms/<id>/join |                             |
        |      (apelido)                      |                             |
        |<-- { joinUrl (com token) } ---------|                             |
        |                                     |                             |
        |-- Custom Tabs: /u/<id>/?token=... -->|---------------------------->| WebRTC
```

### 5.1 Serviço `meet-api`

Serviço Go pequeno no `srv-05`, no mesmo padrão do `isacloud-passport` (binário + `config.json`
+ SQLite + systemd + log em arquivo). Fica ao lado do Galene, então fala com a API
administrativa por rede local.

| Endpoint | Função |
|---|---|
| `POST /meet-api/v1/rooms` | cria a sala: id aleatório, título, descrição, apelido do anfitrião; emite token de operador; devolve `roomUrl` (link a compartilhar) e `hostUrl` (com token, só para o anfitrião) |
| `GET /meet-api/v1/rooms/{id}` | metadados públicos: título, descrição, apelido do anfitrião, se ainda aceita entrada |
| `POST /meet-api/v1/rooms/{id}/join` | recebe o apelido, emite token de convidado com esse nome, devolve a URL com token |
| `DELETE /meet-api/v1/rooms/{id}` | encerra: apaga os tokens da sala e marca como encerrada (usado pelo botão “Encerrar” e pela faxina) |
| `GET /join/{id}` | página web de entrada (título/descrição/anfitrião + apelido + botão), usada por desktop, iOS e navegador |

Modelo de dados (SQLite): `rooms(id, title, description, host_name, host_jid, host_token,
created_at, closed_at)`, `room_tokens(room_id, token, role, created_at)`, para conseguir revogar
tudo de uma sala.

Rotas no nginx do `srv-05`: `location /join/` e `location /meet-api/` para o serviço; o resto
continua no Galene. Colocar `X-Robots-Tag: noindex` e `Referrer-Policy: no-referrer` no `/join/`.

### 5.2 `u.json` alvo

```json
{
  "displayName": "isaCloud Meet",
  "auto-subgroups": true,
  "autokick": true,
  "max-history-age": 900,
  "max-clients": 30
}
```

- sai o `autolock` (quebra a entrada de convidados);
- sai o `authPortal` (aponta para 404; a entrada passa a ser sempre por token);
- `authKeys` pode ficar para o futuro, mas não é necessário para tokens stateful;
- `max-history-age: 900` reduz para 15 min o tempo em que uma sala vazia continua na memória
  (só afeta retenção do chat da sala, não a chamada em andamento);
- `max-clients` limita abuso.

### 5.3 Ciclo de vida

- **Criação**: o app (anfitrião) chama a API, recebe `hostUrl` e guarda localmente
  (a sala pode ser reaberta depois pelo mesmo link de anfitrião).
- **Entrada do convidado**: `roomUrl` → tela → `POST /join` → token novo com o apelido → Galene.
- **Anfitrião sai**: `autokick` expulsa todos; sem operador, ninguém mais entra (o Galene responde
  “there are no operators in this group”).
- **Sala vazia**: sai da memória após `max-history-age`.
- **Reabrir**: o anfitrião abre o `hostUrl` guardado e a sala volta com o mesmo link.
- **Encerrar de vez**: botão “Encerrar” marca `closed_at` e revoga tokens; aí nem o anfitrião
  reabre aquele id.

### 5.4 Link compartilhado x link do anfitrião

| | URL | Vai no chat? |
|---|---|---|
| Sala | `https://meet.isacloud.cc/join/<id>` | **sim** |
| Entrada com token (convidado) | `https://meet.isacloud.cc/u/<id>/?token=<token>` | gerada na hora, só no navegador da pessoa |
| Anfitrião | `https://meet.isacloud.cc/u/<id>/?token=<token-op>` | não; guardada no app |

---

## 6. Lado Android

Mapa do código atual (nomes exatos):

| Assunto | Onde |
|---|---|
| Lista do clipe | `ConversationFragment.ATTACHMENT_CHOICES` (`ui/ConversationFragment.java:215`) |
| Item do clipe | `im/conversations/android/model/AttachmentChoice.java` (`record` + `enum Type`) |
| Despacho do clique | `ConversationFragment.handleAttachmentChoice` (`:2626`) — `switch` exaustivo, compilar quebra se faltar `case` |
| Inserir texto | `ConversationFragment.appendText(String, boolean)` (`:5201`) |
| Link no balão | `de/gultsch/common/Linkify` → `ui/text/FixedURLSpan.open` (`:86`) |
| Cliente HTTP | OkHttp 5 (`build.gradle:139`), modelos em `link/LinkPreviewHttp.java` e `gif/GifRepository.java` |
| Activity modelo | `ui/ChangelogActivity.java` (AppBar + MaterialToolbar) |
| Bottom sheet modelo | `ui/widget/GifPickerSheet.java` |
| Cores | `isacloud_pink_800 #FF006F`, `isacloud_blue_800 #1070A0` (`values/colors-md.xml`) |
| WebView | **não existe**; o app usa Custom Tabs (`androidx.browser`, `EditAccountActivity:557`) |
| Conta | `entities/Account#getJid`, `#getPassword`; banco local isaCloud em `persistance/IsacloudDatabase.java` |

Plano:

1. novo `AttachmentChoice.Type.CONFERENCE` (ícone `ic_videocam_24dp`, `quickAction = false`) +
   entrada em `ATTACHMENT_CHOICES` + `case` no `handleAttachmentChoice`;
2. a ação abre um diálogo curto (título opcional; padrão “Conferência”) e chama
   `POST /meet-api/v1/rooms`; ao voltar, `appendText(getString(R.string.video_conference_message, roomUrl), true)`
   → “Acesse a vídeo conferência pelo link: …”;
3. o `hostUrl` fica guardado em `IsacloudDatabase` (id da sala → token), para o anfitrião reabrir;
4. `FixedURLSpan.open` reconhece `https://meet.isacloud.cc/join/...` e abre a tela de entrada em
   vez do navegador (cobre balão e cartão de pré-visualização);
5. tela de entrada (Activity, modelo `ChangelogActivity`): carrega a sala, mostra título,
   descrição e anfitrião, campo de apelido (pré-preenchido com o nome da conta), botão “Entrar”;
   ao entrar, abre o `joinUrl` em Custom Tabs (fallback `Intent.ACTION_VIEW`);
6. strings novas em `values/strings.xml` e `values-pt-rBR/strings.xml` (prefixo `video_conference_`
   para não colidir com as strings de MUC que já usam `conference_`);
7. app link (`https://meet.isacloud.cc/join/...` interceptado fora do app) fica como fase 2: exige
   `/.well-known/assetlinks.json` com a impressão digital de cada assinatura (site, Play e `.dev`).

---

## 7. Segurança e privacidade

- **`galene-api` está aberto na internet.** Qualquer automação futura deve vir com
  `location /galene-api/ { allow 127.0.0.1; deny all; }` (ou allowlist), senão a única barreira é a
  senha de admin. A senha do `galenectl.json` está errada — vale corrigir e restringir.
- **O `meet-api` não deve ter a senha de admin em texto no repositório**: `config.json` no servidor,
  como o `isacloud-passport`.
- **Token na query string** aparece no log de acesso do nginx. Recomendado: `access_log off` para
  `/u/` ou formato de log sem query; token curto e por pessoa limita o estrago. O Galene limpa a
  URL do histórico do navegador.
- **Quem pode criar sala**: se o endpoint ficar aberto, qualquer pessoa na internet cria salas e
  tokens (a sala morre sozinha, mas consome memória e polui o `tokens.jsonl`). Mitigação mínima:
  rate limit por IP + TTL curto + faxina. Identidade forte (JID + senha conferidos) fica como fase
  seguinte — hoje o `isacloud-passport` só tem recuperação de conta, não tem API de verificação de
  senha pronta.
- **Apelido/anfitrião**: o nome do anfitrião vai aparecer para qualquer um com o link. Se quisermos
  privacidade, mostrar só o apelido escolhido, nunca o JID.
- **A sala em si não é autenticada**: quem tem o link entra. É o modelo “link secreto”, igual a
  Zoom/Jitsi — o id tem que ser aleatório e longo.

---

## 8. Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| **Sem backend**: app sorteia `u/<id>`, link direto, senha compartilhada no `wildcard-user` | não dá operador por sala (sem `autokick`), não tem nome/descrição/anfitrião e a senha fica no APK |
| **JWT HS256 com a chave no app** (`authKeys` já existe) | a chave simétrica vazaria do APK e qualquer um assinaria token de operador |
| **`authPortal` no `passport`** | hoje é 404; o cliente redireciona sem informar a sala; exigiria construir um portal de login inteiro. Bom caminho para uma fase futura de identidade |
| **Criar grupo de verdade por sala (arquivo JSON)** | ganha nome/descrição por sala, mas deixa de ser efêmero: precisa de `DELETE` e de faxina própria |
| **`/invite` na sala** | assume que o anfitrião já entrou e tem conta/senha no Galene; não serve para “gerar link antes de entrar” |
| **Só a página web, sem tela no app** | funciona, mas perde a integração pedida (clipe + tela nativa) |

---

## 9. Riscos e casos de borda

1. **Queda do anfitrião derruba a sala** (`autokick`). Em celular/rede móvel isso é real. Se
   incomodar, a alternativa é `autolock` (a sala espera o anfitrião voltar), mas aí é preciso
   `/unlock` manual e o fluxo “clicou e entrou” morre. Sugestão: manter `autokick` e orientar o
   anfitrião a usar computador/tablet; ou aceitar que os convidados reentrem pelo mesmo token.
2. **Mensagem de erro em inglês** (“there are no operators in this group”) quando o convidado
   chega antes do anfitrião. A tela de entrada pode avisar antes de mandar para o Galene.
3. **Sala vazia continua na memória** por até `max-history-age` (15 min na proposta). Não é
   reutilizável sem operador, mas ocupa memória.
4. **Título/descrição não existem no Galene**: se alguém abrir `/u/<id>/` direto, vê só o
   `displayName` genérico. Por isso o link compartilhado é o `/join/<id>`, nunca o `/u/<id>/`.
5. **Tokens órfãos** em `tokens.jsonl` se a sala for abandonada; o Galene só remove tokens que
   expiraram há mais de 7 dias (`token.Expire`), então o `meet-api` deve apagar os tokens da sala
   ao encerrar.
6. **Pré-visualização de link** no próprio app: o cartão vai buscar `/join/<id>`; a página deve ter
   `og:title`/`og:description` e não exigir login.
7. **Custom Tabs** respeitam o proxy/Tor do app? O `LinkPreviewHttp` considera
   `AppSettings.isUseTor()`. Vale checar o comportamento com proxy ligado antes de publicar.
8. **Galene 1.2.1** é a versão instalada; 1.2.2 já existe, mas nada do que precisamos mudou.

---

## 10. Decisões pendentes

1. Criar um `meet-api` novo no `srv-05` **ou** acrescentar um módulo ao `isacloud-passport` (que já
   tem SQLite, métricas e systemd, mas roda no `srv-07`)?
2. Autenticação da criação de sala: **aberta com rate limit** (rápido) ou **JID + senha conferidos**
   (mais trabalho; precisa de rota nova no `passport`)?
3. Quem pode entrar: só quem tem o link (modelo link secreto) ou exigir conta isaCloud?
4. Tela de entrada: **nativa no app** + página web para os demais (recomendado) ou só a página web?
5. O anfitrião pode **reabrir a mesma sala** (guardando o token no app) ou cada conferência é um
   link novo?
6. `autokick` (encerra quando o anfitrião sai — recomendado) ou `autolock` (espera o anfitrião
   voltar, com `/unlock` manual)?

---

## 11. Esforço estimado

| Frente | Estimativa |
|---|---|
| Configuração do Galene (`u.json`, nginx, restringir `galene-api`) | 0,5 dia |
| `meet-api` (Go + SQLite + 5 endpoints + deploy/systemd) | 2–3 dias |
| Página `/join/<id>` | 1 dia |
| Android: clipe + diálogo + cliente HTTP + inserir texto | 1–2 dias |
| Android: tela de entrada + interceptação do link + guardar token do anfitrião | 2 dias |
| Testes no emulador, `.dev` no isaFashionPhone2, traduções e docs | 1–2 dias |

Total aproximado: **1 a 2 semanas**, em fases (servidor primeiro, depois app).

---

## 12. Implementação — fase 1 concluída em 21/11/2026

Decisões tomadas pela Isadora e já aplicadas:

- **Serviço novo em Go**, dockerizado, sidecar do Galene no `srv-05`; repo
  `ssh://git@code.isacloud.cc:222/isadora/galene-meet-api` (branch `main`).
- **Rate limit simples** por IP (20 salas/h, 120 entradas/h).
- **Entrada só pela página web** nesta fase (o app cria a sala e insere o link).
- **`autokick`** no grupo `u` (o `autolock` foi removido por quebrar a entrada de
  convidados — ver §4.3).

### O que está no ar

| Item | Onde |
|---|---|
| Projeto | `~/projects/go/galene-meet-api` (local) = repo Forgejo |
| Imagem | `cr.isacloud.cc/meet-api:0.1.0` |
| Container | `srv-05:/opt/docker/meet-api` (`docker-compose.yaml`, `config.json`, `data/rooms.json`) |
| Redes | `nginx_container-net` (`172.29.11.10`) e `galene_container-net` (`172.38.0.10`) |
| API do Galene | `http://172.38.0.2:8443/galene-api/v0/` (admin) |
| nginx | `srv-05:/opt/docker/nginx/conf.d/default.conf` → `location /join/` e `location /meet-api/` |
| Grupo Galene | `srv-05:/opt/docker/galene/groups/u.json` com `auto-subgroups` + `autokick` |
| Documentação de operação | `docs/deploy-meet-api.md` (aqui) e `docs/deploy.md` (no repo do meet-api) |

### Endpoints

- `POST /meet-api/v1/rooms` → `{roomID, roomURL, hostURL, hostKey, expiresAt}`
- `GET /meet-api/v1/rooms/{id}` → metadados públicos
- `POST /meet-api/v1/rooms/{id}/join` → `{joinURL, expiresAt}`
- `DELETE /meet-api/v1/rooms/{id}` (`X-Host-Key`) → encerra e revoga tokens
- `GET /join/{id}` → página de entrada (pt-BR)
- `GET /meet-api/healthz`

### O que foi validado

1. Testes de unidade/HTTP no projeto (`make test`).
2. Sala real criada pela API (tokens emitidos no Galene), página renderizada,
   entrada pela página (303 com token) e encerramento revogando os tokens.
3. Fluxo completo em produção: anfitrião entra como operador, convidado entra,
   anfitrião sai → convidado recebe `kicked` (“there are no operators in this
   group”) e um novo convidado é barrado.

### App Android (fase 1) — branch `feature/conferencia-galene`

Implementado (worktree `~/projects/java/isaCloudMessenger-conferencia`, ainda **sem commit**):

- `AttachmentChoice.Type.CONFERENCE` + item “Criar conferência” no clipe.
- `ConferenceApi` (OkHttp, https fixo, sem redirect, Tor quando ligado) chamando
  `POST /meet-api/v1/rooms` com o nome de exibição da conta.
- Texto “Acesse a vídeo conferência pelo link: <roomURL>” no compositor e Snackbar
  com ação “Entrar” (abre o `hostURL`).
- `ConferenceStore`: `hostURL` + validade em SharedPreferences (`conference_rooms`),
  nunca vai para o chat.
- `FixedURLSpan` intercepta `/join/<id>`: abre o `hostURL` guardado (anfitrião) ou a
  página de entrada (convidado), em Custom Tabs com fallback para `ACTION_VIEW`.
- Strings em inglês e pt-BR; nenhuma permissão/activity nova.

Validado no emulador (`isacloud.messenger.dev` 2.21.2-73, dados preservados):

1. O item aparece no clipe; tocar cria a sala, insere o texto e mostra o Snackbar.
2. Tocar no link já enviado abre o **hostURL** (log “opening conference room … as host”)
   em Custom Tabs, com o token: o Galene mostra a tela de pré-entrada e o anfitrião
   entra com câmera e microfone.
3. Convidado (segundo emulador, navegador) abre `/join/<id>`, vê título, anfitrião,
   campo de apelido, entra e aparece para o anfitrião com o apelido digitado.
4. Quando o anfitrião sai, o convidado é expulso (`kicked`) e novos convidados são
   barrados — já validado também por WebSocket direto.

**Bug encontrado e corrigido no nginx nessa validação:** a reescrita de `/u/` só cobria
`/u/<id>/`; o `GET /u/<id>/.status` caía sem reescrita (404), e a página abria sem
status, exibindo o formulário de login em vez de conectar com o token. A regra agora
cobre `/u/<id>(/.*)?` e preserva a query string.

### Ajustes visuais (21/11/2026)

- **Flash do campo de senha** ao entrar com token: o cliente chamava
  `setVisibility('passwordform', true)` no submit do formulário. Agora só mostra
  quando não há token (patch em `galene.js`), então o anfitrião nunca vê o campo
  de senha. Validado por gravação de tela no emulador (nenhum frame com senha).
- **Logo novo** na página `/join/<id>` (embutido no binário do meet-api e servido
  em `/join/logo.png`) e no topo da lista de participantes do Galene.
- **Degradê** no cabeçalho do Galene (rosa `#ff006f` → azul `#1780ad`, como no
  site) e barra de degradê no cartão da página de entrada.
- **Tradução pt-BR** da tela inicial (“Ativar ao entrar”, “Nada”, “Microfone”,
  “Câmera e microfone”, “Entrar”), das configurações e das principais mensagens.
- Bug de CSP: a página bloqueava a própria imagem (`img-src data:`); corrigido
  para `img-src 'self' data:` (versão `0.1.2` do meet-api).
- `meet-api` agora em `0.1.2`; arquivos estáticos do Galene com backup
  `.bak-20261121-102930` e *cache busting* `?v=20261121`.

### Presença do anfitrião (21/11/2026)

O convidado que entrava antes do anfitrião via um toast vermelho e caía na tela
de login do Galene. Resolvido em três frentes:

1. **Heartbeat**: o `hostURL` leva uma chave de presença (`pk`); o cliente Galene
   envia `POST /meet-api/v1/rooms/<id>/presence` a cada 15 s (e `online:false` ao
   fechar a aba). A sala conta como “anfitrião presente” por 90 s após o último
   sinal.
2. **Página de entrada**: consulta `GET /meet-api/v1/rooms/<id>` a cada 5 s,
   mostra “Aguardando o anfitrião entrar…” com o botão desabilitado e libera
   quando ele entra. O `POST` de entrada responde 409 enquanto ele não está,
   então o convidado não é mais mandado para o Galene sem chance de entrar.
3. **Retorno**: quando a entrada por token falha ou o convidado é expulso (o
   anfitrião saiu), o `galene.js` volta para `/join/<id>` em vez de mostrar a
   tela de login. Validado no emulador: host sai → convidado volta para a página
   com “Aguardando o anfitrião entrar…”.

Validado também: página “Aguardando” → host entra → em até 5 s ela muda para
“O anfitrião está na sala. Pode entrar!” e o botão fica rosa/habilitado.

### Atalho na lista de conversas (21/11/2026)

A anfitriã não precisa do Snackbar (que some) para reentrar: um card abaixo dos chips da
lista de conversas mostra "Sua conferência está pronta" com **Entrar** e um "x" para
esconder. Ele aparece quando o aparelho tem um link de anfitrião válido, abre a sala em
Custom Tabs e volta a aparecer quando uma nova conferência é criada. Validado no
emulador: aparece, abre como anfitriã, some ao tocar no "x" e continua escondido ao
voltar para o app.

### Ajustes finais de texto e visual (21/11/2026)

- **Termo neutro**: a página de entrada passou a usar “Sala criada por: <nome>” e
  “Aguardando quem criou a sala entrar…”; a dica do app virou “Toque em Entrar para
  abrir a sala”.
- **Cabeçalho do Galene**: rosa sólido (`#ff006f`). As tentativas de degradê
  (horizontal e vertical) ficaram “duras” demais na avaliação visual.
- **Fontes**: o cliente passou a usar a pilha de fontes do próprio sistema, a mesma
  do site `isacloud.com.br` (sem Metropolis).
- **Verde do Galene**: o botão de apresentar e o indicador “conectado” agora usam o
  azul da marca (`#1780ad`).
- **Toasts**: erro vermelho, aviso âmbar e informação azul (antes a informação era
  verde). As mensagens do servidor são traduzidas no cliente.
- **Manutenção**: as customizações do `static/` estão versionadas em
  `galene-static/` no repo do meet-api, e as traduções dinâmicas ficam em
  `isacloud-ptbr.js` (arquivo separado, sem conflito com o upstream).

### Implementação no iOS

O guia para o app iOS (contrato da API, fluxos, mapa de arquivos do Monal, textos e checklist de
testes) está em [`implementacao-video-conferencia-ios.md`](implementacao-video-conferencia-ios.md).

### Pendências

- App: app link (`/join/<id>` aberto fora do app) via `assetlinks.json`; recuperar o
  `hostURL` se o aparelho do anfitrião perder os dados (hoje o `hostKey` não é guardado).
- Restringir `https://meet.isacloud.cc/galene-api/` por IP (hoje exposto, 401 sem
  credencial).
- Avaliar identidade forte (JID) na criação da sala, hoje só rate limit.

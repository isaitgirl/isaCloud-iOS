# Decisões — Criar conferência (Galene + meet-api), fase 1 no app

Data: 21/11/2026 · Branch: `feature/conferencia-galene`

Integração com o serviço externo de vídeo conferência descrito em
`docs/analise-conferencia-galene.md` (operado em `srv-05`).

## O que a fase 1 faz

- Item **“Criar conferência”** no clipe de anexos (`AttachmentChoice.Type.CONFERENCE`).
- Ao tocar, chama `POST https://meet.isacloud.cc/meet-api/v1/rooms` com `{"hostName": ...}` e
  insere no compositor: *“Acesse a vídeo conferência pelo link: <roomURL>”*.
- Snackbar de confirmação com a ação **“Entrar”**, que abre o `hostURL` (anfitrião). Em erro,
  Snackbar com mensagem para tentar de novo.
- Link `/join/<id>` tocado no balão ou no cartão de pré-visualização é aberto em Custom Tabs,
  com fallback para `Intent.ACTION_VIEW`.

## Decisões

- **Sem diálogo nesta fase.** O hostName vem do nome de exibição da conta e, quando vazio, da
  parte local do JID. Título/descrição ficam para uma fase futura.
- **`hostURL` é credencial e fica só no aparelho.** Guardado em SharedPreferences próprias
  (`conference_rooms`), indexado pelo `roomID`, junto com `expiresAt`; expirados são removidos ao
  salvar e ao consultar. Não vai para o banco de mensagens nem para o chat. Foi preferido ao
  `IsacloudDatabase` citado na análise para não alterar esquema nem migração nesta fase.
- **Só abre o hostURL guardado se ele continuar https e no host do serviço**; caso contrário cai
  no link público, para o convidado usar a página de entrada.
- **Cliente HTTP dedicado** (OkHttp): https fixo, `followRedirects(false)`, timeouts 5/10/15 s,
  User-Agent do app e proxy do Tor quando ligado. Resposta 201 com JSON validado; qualquer outro
  código vira erro. Callback sempre na main thread.
- **Detecção do link** exige `https`, host `meet.isacloud.cc` e caminho exatamente `/join/<id>`
  com `id` em `[A-Za-z0-9_-]+`. Qualquer outra coisa segue o comportamento normal do app.
- **Sem permissões novas e sem activities novas**; abertura via Custom Tabs
  (`androidx.browser`, já dependência).
- Strings com prefixo `video_conference_` e `attachment_choice_conference` (não reutiliza as
  strings de MUC `conference_*`).

## Atalho na lista de conversas (21/11/2026)

- Quando este aparelho tem um link de anfitrião válido, a lista de conversas mostra um
  card abaixo dos chips: "Sua conferência está pronta" + botão **Entrar** + "x".
- **Entrar** abre o `hostURL` em Custom Tabs (mesmo caminho do Snackbar e do link no chat).
- O "x" grava `dismissed_room` nas preferências da conferência; o card só volta quando
  uma nova conferência é criada (o `save` limpa a dispensa) ou quando o link expira.
- O card elege a conferência mais recente por `savedAt` (entradas antigas usam `expiresAt`).
- Estado em `ConferenceStore` (`activeHostRoom`/`dismiss`); UI em
  `ConversationsOverviewFragment` e `fragment_conversations_overview.xml`.
- Strings: `video_conference_active`, `video_conference_active_hint`,
  `video_conference_dismiss` (en + pt-BR).

## Pendências / riscos

- O link de anfitrião é por dispositivo: quem criou a sala em outro aparelho entra como convidado
  (a página pede apelido e o Galene aplica `autokick`). Regenerar o `hostURL` exigiria o
  `hostKey`, que não é guardado nesta fase.
- O clipe passa a ter 10 itens (4 linhas de 3 no telefone). Validar a altura da bandeja em telas
  pequenas com o app `.dev`.
- App link (`/join/<id>` aberto fora do app) exige `assetlinks.json` — fase 2.

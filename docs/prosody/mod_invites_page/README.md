# Página de convite do isaCloud (`mod_invites_page`)

Modelos HTML simples para a página de entrada do convite do Prosody (`mod_invites_page`, módulo da comunidade), no lugar da página padrão que lista vários aplicativos. Mostra o balão do isaCloud, o botão **Registrar via aplicativo** (link `xmpp:` do convite, que o isaCloud abre na tela de criar conta), o próprio link, e o botão **Registrar pelo site** (a página `register?t=<token>` do `mod_invites_register_web`). Sem aplicativos, sem Bootstrap e sem arquivos externos.

## Arquivos
- `invite.html`: a página do convite (`html/invite.html` do módulo).
- `invite_invalid.html`: a página de convite vencido, usado ou inválido (`html/invite_invalid.html`). A original dizia só "Invite expired" para qualquer token que o servidor não encontra; vale lembrar que um link com o token mal formado (por exemplo `?t=<token>` em vez de `?<token>`) também cai nela.

O balão é o mesmo do app (`isaCloud/branding/logo-isacloud-im-transp-ico-balao-2000px.png`), reduzido e embutido no HTML (data URI), assim a página funciona sem `mod_http_libjs` nem arquivos em `/static`.

## Como instalar no servidor
1. Copie a pasta `mod_invites_page` do `prosody-modules` para uma pasta de módulos **sua** (a primeira em `plugin_paths`), para o `hg update` dos módulos da comunidade não apagar a mudança. Se preferir, copie só os dois arquivos por cima de `html/invite.html` e `html/invite_invalid.html` dentro da pasta do módulo, sabendo que uma atualização do módulo os desfaz.
2. Substitua `html/invite.html` e `html/invite_invalid.html` pelos desta pasta.
3. Não precisa recarregar o Prosody para ver a mudança no HTML: o módulo lê os modelos a cada requisição (`module:load_resource` dentro de `serve_invite_page`). Se mudou a cópia do módulo de pasta, recarregue: `module:reload("invites_page", "isacloud.im")` no `prosodyctl shell`.
4. No `prosody.cfg.lua`, para o endereço da página sair certo atrás do proxy reverso (o padrão leva a porta 5281): `invites_page = "https://{host}/invites_page?{invite.token}"`. Os convites **já criados** podem ter o endereço antigo; só vale para os novos.
5. Teste com um convite novo: `prosodyctl shell invite create_contact <seu_jid> --allow-registration` e abra `https://<dominio>/invites_page?<token>` (o token puro depois do `?`, sem `t=`).

## Link direto para o registro web (`#web`)
A página manda direto para `register?t=<token>` quando o endereço termina em `#web` (um script de uma linha no `<head>` do `invite.html`). Serve para um link como `/signup` que cria o convite pela API (`mod_invites_api`) e quer ir direto ao formulário do site: o redirecionamento deve apontar para `https://<dominio>/invites_api?key=<chave>&redirect=1#web`. O fragmento (`#web`) não vai ao servidor e o navegador o mantém quando segue o redirecionamento 303 do Prosody para `…/invites_page?<token>`, por isso funciona sem mudar o módulo. Sem o `#web` a página aparece normal. Um parâmetro comum (`&direto=1`) não serve: o módulo usa a query inteira como token e o convite ficaria inválido.
- Testado: um servidor local imitando o redirecionamento 303, no navegador (com `#web` foi para o registro; sem, ficou na página). Não testado no `isacloud.im`.
- Sem JavaScript no navegador, o `#web` é ignorado e a página normal aparece (os dois botões continuam funcionando).
- A chave da API **não** deve ir em arquivo do projeto nem em `.md`; o ideal é que o `/signup` seja feito do lado do servidor web (por exemplo, um `return 302` do proxy), e a documentação do módulo recomenda mandar a chave no cabeçalho `Authorization: Bearer` quando for uma chamada de programa.

## Cuidados ao editar
- O Prosody interpreta `{ ... }` no HTML como variável do modelo (`util.interpolation`). Por isso a página **não tem `<style>` nem JavaScript com chaves**: tudo é `style="..."` inline e o botão de copiar usa um `onclick` de uma expressão só. Se precisar de CSS com chaves, ponha num arquivo em `static/` (e confira o tipo MIME: o módulo só mapeia `png`, `svg` e `js`).
- Variáveis que o módulo entrega à página: `{site_name}`, `{token}`, `{uri}` (o link `xmpp:`), `{type}`, `{jid}`, `{inviter}` e `{static}`. `{inviter&texto {inviter}}` só aparece se houver `inviter`.
- O botão "Copiar link" usa `navigator.clipboard`, que só funciona em HTTPS.

## O que foi e o que não foi testado
- Testado: a página renderizada num navegador (celular), com variáveis de exemplo (convite fictício), e a de convite inválido.
- **Não testado no Prosody de verdade:** a substituição das variáveis foi simulada fora do Prosody. Se a página mostrar `{...}` em texto ou o link `xmpp:` vazio, o problema é a sintaxe do modelo; confira com um convite real.

# Análise: Klipy como segundo provedor de GIF

Atualizada em 10/11/2026. Branch: `feature/gif-klipy`.

## Decisão

- O **GIPHY continua como padrão** e o **Klipy entra como segunda opção**.
- A troca fica **na própria tela de GIFs** (menu no canto esquerdo da barra) e também em Configurações → Anexos → GIFs. As duas usam a mesma configuração (`gifProvider`: `giphy` ou `klipy`).
- Se o build não tiver a chave de um provedor, ele não aparece como opção. Se a escolha salva não tiver chave, a tela usa o outro.
- Os anúncios do Klipy estão desligados no Partner Panel da chave.

## Como estava

- `GiphySearch.swift` monta as URLs de busca e de "em alta", lê o JSON e baixa o GIF original.
- `GifPickerView.swift` mostra a grade, pagina ao chegar no fim e mostra "Powered by GIPHY".
- O resto do app (anexo `.animatedGif`, envio, balão, reações, citação) recebe só um arquivo `.gif` local. Por isso a troca de provedor não mexe em nada fora desses dois arquivos.
- A chave vem do build: `GiphyAPIKey` no `Info.plist`, preenchida por `GIPHY_API_KEY` nos scripts, que leem `isaCloud/local/giphy-api-key.txt`.

## API do Klipy (conferida com a chave em 10/11/2026)

- **Em alta:** `GET https://api.klipy.com/api/v1/{CHAVE}/gifs/trending?page=1&per_page=24&rating=g`
- **Busca:** `GET https://api.klipy.com/api/v1/{CHAVE}/gifs/search?q=...&page=1&per_page=24&rating=g`
- A chave vai **no caminho** da URL. A paginação usa `page` (começa em 1) e `per_page` (8 a 50).
- O `customer_id` **não é obrigatório**: sem ele a resposta veio 200. O app não manda identificador de usuário.
- **Resposta:** `{"result": true, "data": {"data": [...], "current_page": 1, "per_page": 24, "has_next": true}}`.
- **Cada item** traz `id` (número de 16 dígitos), `slug`, `title`, `type` (`"gif"`) e `file`, que tem os tamanhos `hd`, `md`, `sm` e `xs`. Cada tamanho tem `gif`, `webp`, `jpg`, `mp4` e `webm`, e cada formato tem `url`, `width`, `height` e `size`.
- **Escolhas:** a prévia na grade usa `xs.gif` (cerca de 170 px, ~110 KB), ou `sm.gif` se faltar. O envio usa `hd.gif`, ou `md.gif` se faltar.
- Anúncios viriam como itens com outro `type`. Mesmo desligados, o parse ignora qualquer item que não seja `"gif"`.

## Limite da chave de teste

A chave é de teste, e o Klipy disse que ela pode ser usada. O limite é de **100 chamadas por hora para a chave inteira**, não por pessoa. Cada abertura da tela, cada busca confirmada e cada página nova ao rolar gastam uma chamada. A busca só dispara ao confirmar, não a cada letra. Com o GIPHY como padrão, só quem escolher o Klipy gasta esse limite. Se o uso crescer, pedir a chave de produção no Partner Panel.

## Pontos ainda em aberto

- **Termos:** o ToS geral do Klipy fala em uso "pessoal e não comercial" e remete a "API Terms" que não encontrei publicados. Vale pedir ao Klipy.
- **Marca:** o Klipy pede "Powered by KLIPY" e o texto "Search KLIPY" no campo de busca. O guia completo está numa pasta do Google Drive que não li.
- **Privacidade:** o Klipy recebe o IP e os termos buscados, como o GIPHY.

## Esforço

Cerca de um dia. O código novo fica em `GiphySearch.swift` (mesmo arquivo, para não mexer no `project.pbxproj`), mais `GifPickerView.swift`, a tela de Anexos, a migração em `MLXMPPManager.m`, as traduções, os dois scripts, o `Info.plist` e os testes.

## Cache (10/11/2026)

As duas chaves (GIPHY e KLIPY) têm limite de 100 chamadas por hora para todos os usuários juntos. Por isso a busca de GIF ganhou dois caches.

**Cabeçalhos medidos:**

| | API | Imagens |
|---|---|---|
| KLIPY | `max-age=21600` (6 h) | `max-age=86400` (1 dia) |
| GIPHY | sem cabeçalho de cache | `max-age=604800` (7 dias) |

**A. Cache HTTP só dos GIFs.** Uma `URLSession` própria (`GifNetwork`) com `URLCache` de 8 MB em memória e 100 MB em disco, em `Caches/gif-http-cache`. Ela segue o que cada servidor permite: o "em alta" do KLIPY por 6 h (as buscas também, se vierem com o mesmo cabeçalho, o que ainda não medi) e as prévias de 1 a 7 dias. A API do GIPHY não entra, porque não manda cabeçalho de cache.

**B. Primeira tela de cada provedor guardada.** O "em alta" vem numa página de 50 (o máximo das duas APIs) e fica salvo em `Caches/gif-trending/<provedor>.json`. Ele vale **6 h no KLIPY** (o que o servidor permite) e **1 h no GIPHY**. Cada abertura embaralha a ordem, o que substitui a página sorteada de antes. Rolar até o fim continua buscando as páginas seguintes, **até 3 páginas** (150 GIFs no "em alta" e 72 numa busca). No teste de 10/11, uma rolagem rápida gastou 4 chamadas em 7 segundos.

**Como avaliar (logs do `.dev`):** todas as linhas começam com `GIF cache:`.
- De onde veio cada lista: lista salva, cache HTTP ou rede.
- O que resta do limite do KLIPY (`rate limit remaining`).
- Ao fechar a tela: quantas chamadas e prévias vieram do cache e quantas da rede.
- O termo buscado não vai para o log, só o tamanho dele.

O cache é de cada aparelho. Ele corta as repetições de cada pessoa, mas o limite de 100 por hora continua dividido entre todos.

## Resultado no `.dev` (10/11/2026, 16:01–16:09)

- **Lista salva:** o GIPHY foi à rede só na primeira abertura, e as 5 seguintes vieram da lista salva. Com o KLIPY foi igual: 1 abertura pela rede e 10 da lista salva.
- **Cache HTTP:** a mesma busca no KLIPY veio do cache na segunda vez, então as buscas também ficam guardadas por ele. A página 1 do "em alta" veio do cache ao rolar de novo. As prévias foram de 0 para 21 de 21 vindas do cache nas aberturas seguintes.
- **Consumo:** o KLIPY fez 6 chamadas em cerca de 16 aberturas, uma busca e uma rolagem longa. O GIPHY fez 1 chamada em 6 aberturas. A rolagem longa motivou o limite de 3 páginas.
- **Leitura do log:** quando a resposta vem do cache HTTP, o `rate limit remaining` mostra o valor guardado, não o atual. Os contadores de prévias contam carregamentos, não GIFs diferentes, porque a grade recarrega as células que voltam à tela.

## Versão do GIF enviado (11/11/2026)

O GIF enviado era sempre a maior versão: a `original` do GIPHY chega a ~10 MB, e o `hd` do KLIPY a ~20 MB (medido em 10/11).

**Regra nova:** vai a **primeira versão de até 2 MB**, na ordem abaixo, pelo tamanho que a própria API informa. Se nenhuma couber, vai a menor. Uma versão sem tamanho informado é pulada; se nenhuma informar, vale a primeira, como antes.

| Provedor | Ordem das versões | Na prática |
|---|---|---|
| GIPHY | `original`, `downsized_large`, `downsized_medium`, `downsized`, `fixed_width` | quase sempre `downsized`, que o GIPHY já garante abaixo de 2 MB (234 a 344 px) |
| KLIPY | `hd`, `md`, `sm`, `xs` | `md` quando ela é leve; nos GIFs pesados, `sm` (220 px) |

Continua indo `.gif`, porque MP4 e WebP viram vídeo ou imagem parada em outros clientes. As prévias da grade não mudam. As listas de "em alta" salvas antes da mudança apontavam para as versões grandes, então o arquivo da lista salva passou a ser `<provedor>-v2.json`.

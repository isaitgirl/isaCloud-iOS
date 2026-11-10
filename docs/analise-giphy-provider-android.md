# Provedor de GIF (GIPHY e KLIPY): guia para o isaCloud Android

Escrito em 10/11/2026 a partir do que o iOS fez no PR 62 (`feature/gif-klipy`, mesclado na `isaCloud`). O objetivo é o Android seguir **as mesmas regras**, para os dois apps se comportarem igual. A análise completa do iOS está em `docs/analise-gif-klipy.md`.

Este guia descreve **o comportamento**, não o código. Os nomes de arquivos e de classes do iOS aparecem só como referência. No Android, use o que o projeto já tiver (cliente HTTP, preferências, telas).

## 1. Decisões

| Tema | Decisão |
|---|---|
| Provedores | **GIPHY** (padrão) e **KLIPY** (segunda opção) |
| Onde trocar | No **menu da própria tela de GIFs** e nas **Configurações → Anexos → GIFs**. Os dois usam a mesma preferência. |
| Preferência | Chave `gifProvider`, valores `giphy` ou `klipy`, padrão `giphy` |
| Sem chave | O provedor sem chave no build não aparece como opção. Se a escolha salva não tiver chave, a tela usa o padrão; se o padrão também não tiver, usa o outro. Sem nenhuma chave: "Busca de GIF indisponível". |
| Menu e seção | O menu da tela e a seção de Configurações só aparecem quando o build tem **as duas** chaves |
| Anúncios do KLIPY | Desligados no Partner Panel da chave. Mesmo assim, o app ignora qualquer item que não seja GIF. |
| Privacidade | **Não mandar `customer_id`** nem nenhum identificador de usuário ao KLIPY. Não registrar o termo buscado nos logs. |
| Classificação | `rating=g` nos dois provedores |
| Rolagem | No máximo **3 páginas** por lista |
| Cache | Cache HTTP que segue os cabeçalhos dos servidores, mais o "em alta" de cada provedor salvo no aparelho (seção 5) |

## 2. Chaves

- As duas chaves têm **limite de 100 chamadas por hora, somando todos os usuários**. Os dois apps também se somam se usarem a mesma chave. **Vale ter chaves separadas para o Android** (uma do GIPHY e uma do KLIPY). Se a chave for a mesma, iOS e Android dividem o limite.
- A chave do KLIPY do iOS é de teste, e o KLIPY liberou o uso. Na conta do KLIPY, os anúncios ficam desligados por chave, no Partner Panel → "Update App Details".
- **A chave nunca vai para o Git.** No iOS ela fica num arquivo local ignorado (`isaCloud/local/klipy-api-key.txt`) e o build a injeta. No Android, a forma equivalente é ler de `local.properties` (ou de uma variável de ambiente) para um `buildConfigField`. Sem a chave, o build continua funcionando e a opção simplesmente não aparece.

## 3. API do KLIPY (conferida com a chave em 10/11/2026)

- **Em alta:** `GET https://api.klipy.com/api/v1/{CHAVE}/gifs/trending?page=1&per_page=50&rating=g`
- **Busca:** `GET https://api.klipy.com/api/v1/{CHAVE}/gifs/search?q={TERMO}&page=1&per_page=24&rating=g`
- **Chave:** vai **no caminho** da URL, como um segmento (codificado). Não é parâmetro.
- **Paginação:** `page` começa em **1**; `per_page` vai de 8 a 50.
- **Identificador de usuário:** `customer_id` não é obrigatório (sem ele a resposta veio 200). Não mandar.
- **Resposta:**
  ```json
  {"result": true,
   "data": {"data": [ITEM, ...], "current_page": 1, "per_page": 50, "has_next": true, "meta": {...}}}
  ```
- **Item:**
  ```json
  {"id": 6561878491986958, "slug": "...", "title": "...", "type": "gif",
   "file": {"hd": {"gif": {"url": "...", "width": 498, "height": 258, "size": 1090997},
                   "webp": {...}, "jpg": {...}, "mp4": {...}, "webm": {...}},
            "md": {...}, "sm": {...}, "xs": {...}},
   "tags": [], "blur_preview": "data:image/jpeg;base64,..."}
  ```
- **Regras de leitura:**
  - O `id` é **número** de 16 dígitos: ler como `long` (ou aceitar texto). Para não colidir com os ids do GIPHY, usar `klipy-<id>`.
  - **Ignorar** itens cujo `type` exista e não seja `"gif"`, porque anúncios viriam com outro tipo.
  - **Prévia na grade:** `file.xs.gif.url` (cerca de 170 px, ~110 KB), ou `file.sm.gif.url` se faltar.
  - **GIF enviado:** `file.hd.gif.url`, ou `file.md.gif.url` se faltar.
  - Ignorar o item sem as URLs necessárias.
  - **Há mais páginas** quando `data.has_next` é verdadeiro.
- **Cabeçalhos úteis:** `x-ratelimit-limit` e `x-ratelimit-remaining`, que mostram quanto resta do limite da hora.

## 4. GIPHY (o que o iOS já fazia, com os ajustes)

- **Endereços:** `https://api.giphy.com/v1/gifs/trending` e `/v1/gifs/search`, com `api_key`, `limit`, `offset` e `rating=g`.
- **Paginação:** `offset = página × tamanho`. Há mais quando a página veio cheia.
- **Prévia:** `images.fixed_width_small`, ou `fixed_width_small_still` se faltar. **Enviado:** `images.original.url`.
- O "em alta" agora vem numa página de **50**, como no KLIPY (seção 5).

## 5. Cache e limite de chamadas

Cabeçalhos medidos em 10/11/2026:

| | API | Imagens |
|---|---|---|
| KLIPY | `Cache-Control: public, max-age=21600` (6 h) | `max-age=86400` (1 dia) |
| GIPHY | sem cabeçalho de cache | `max-age=604800` (7 dias) |

**A. Cache HTTP só dos GIFs.** Um cliente HTTP próprio para a busca de GIF, com cache em disco de **100 MB** na pasta de cache do app, que o sistema pode limpar. No Android, por exemplo, o `Cache` do OkHttp num diretório próprio em `cacheDir`. Ele **segue os cabeçalhos**, sem forçar nada:
- a API do KLIPY (o "em alta" e as buscas) fica 6 h;
- as prévias ficam de 1 a 7 dias;
- a API do GIPHY não entra, porque não manda cabeçalho de cache.

Usar o mesmo cliente para as prévias e para baixar o GIF escolhido.

**B. "Em alta" salvo por provedor.**
- Na primeira abertura, o "em alta" vem numa página de **50** (o máximo das duas APIs) e fica salvo num arquivo por provedor, com a hora da busca. No iOS: `Caches/gif-trending/<provedor>.json`, com provedor, hora, "tem mais" e a lista.
- **Validade:** **6 h no KLIPY** (o que o servidor permite) e **1 h no GIPHY**. Não confiar numa hora mais de 1 minuto no futuro.
- Com a lista salva válida, a tela mostra a lista na hora, **sem chamada nenhuma**, com a **ordem embaralhada a cada abertura**. Isso substitui a página sorteada que o iOS usava antes.
- **Não salvar uma lista vazia**, senão a tela mostraria "Nenhum GIF" até a lista vencer.
- Arquivo ilegível, de outro provedor ou vencido: buscar de novo.

**C. Rolagem limitada a 3 páginas.** Ao chegar no fim da grade, pede a próxima página até a terceira: no máximo **150 GIFs** no "em alta" (3 × 50) e **72** numa busca (3 × 24). No teste do iOS, uma rolagem rápida gastou 4 chamadas em 7 segundos.

**Busca:** só chama a API ao **confirmar** a pesquisa, não a cada letra digitada. Apagar o texto volta ao "em alta" (salvo).

**Resultado no iOS (`.dev`, 10/11/2026):** o KLIPY fez 6 chamadas em cerca de 16 aberturas, uma busca e uma rolagem longa. O GIPHY fez 1 chamada em 6 aberturas. A busca repetida e as páginas já vistas vieram do cache HTTP.

## 6. Tela de GIFs

- **Menu no canto da barra superior**, à esquerda no iOS, com o nome do provedor e uma setinha ("GIPHY ⌄"). Ele lista os provedores com chave. Na troca, a tela salva a escolha em `gifProvider` e refaz o que estava na tela: a mesma busca, se houver texto, ou o "em alta".
- **Atribuição no rodapé:** "Powered by GIPHY" ou "Powered by KLIPY", conforme o provedor.
- **Texto do campo de busca:** "Buscar GIFs" no GIPHY e "Buscar no KLIPY" no KLIPY (o KLIPY pede o nome dele no campo).
- **Configurações → Anexos → GIFs:** seletor "Provedor de GIF" e a nota "Também dá para trocar na própria busca de GIFs."
- **O resto não muda:** o GIF escolhido é baixado e enviado como arquivo animado, igual ao que já acontece com o GIPHY.

**Textos (inglês → pt-BR, como no iOS):**

| Inglês | pt-BR |
|---|---|
| Powered by GIPHY | Powered by GIPHY |
| Powered by KLIPY | Powered by KLIPY |
| Search GIFs | Buscar GIFs |
| Search KLIPY | Buscar no KLIPY |
| GIF provider | Provedor de GIF |
| GIFs | GIFs |
| You can also switch it in the GIF search. | Também dá para trocar na própria busca de GIFs. |
| GIF search is not available | Busca de GIF indisponível |
| The GIF search key is not set in this build. | A chave da busca de GIF não está configurada neste build. |
| Could not search GIFs | Não foi possível buscar GIFs |
| No GIFs found | Nenhum GIF encontrado |

## 7. Logs para avaliar o cache

No iOS, todas as linhas começam com `GIF cache:`, para facilitar a busca:
- `GIF cache: trending <provedor> from saved list, age <N> min, <n> GIFs`
- `GIF cache: <trending|search> <provedor> page <n>[, query of <k> chars] from <HTTP cache|network>, <n> GIFs, rate limit remaining <n|unknown>`
- `GIF cache: picker closed, API <a> from HTTP cache / <b> from network, previews <c> from cache / <d> from network`

Regras:
- **Nunca registrar a chave, a URL completa nem o termo buscado**, só o tamanho dele.
- Quando a resposta vem do cache HTTP, o `rate limit remaining` mostra o valor guardado, não o atual.
- No OkHttp, `response.cacheResponse != null && response.networkResponse == null` indica que veio do cache.

## 8. Testes sugeridos

**Unitários:**
- leitura do KLIPY: itens GIF, item de anúncio ignorado, item sem `hd`/`md` ignorado, os tamanhos alternativos (`sm`, `md`), `has_next`, id numérico e id em texto, resposta inválida;
- URLs: a chave no caminho, `page`, `per_page`, `rating=g`, sem `customer_id`;
- escolha do provedor, em todos os casos da tabela da seção 1;
- lista salva: ida e volta, validade de 1 h e 6 h, provedores separados, arquivo corrompido, hora no futuro.

**No aparelho:**
1. Abrir a busca: GIPHY, com o menu e "Powered by GIPHY".
2. Trocar para KLIPY: a grade recarrega, o campo diz "Buscar no KLIPY" e o rodapé "Powered by KLIPY".
3. Fechar e abrir: a tela lembra o provedor, e o "em alta" vem da lista salva, em outra ordem e sem chamada.
4. Buscar, fechar, abrir e buscar a mesma palavra no KLIPY: deve vir do cache HTTP.
5. Rolar até o fim: para na terceira página.
6. Enviar um GIF de cada provedor: sai animado.
7. Configurações → Anexos → GIFs: mostra a mesma escolha do menu.

## 9. Pontos em aberto (os mesmos do iOS)

- **Termos do KLIPY:** o ToS geral fala em uso "pessoal e não comercial" e remete a "API Terms" que não encontrei publicados. Vale pedir ao KLIPY.
- **Guia de marca:** o KLIPY tem um guia de marca numa pasta do Google Drive, ainda não lido.
- **Chave de produção:** se o uso crescer, pedir a chave de produção do KLIPY e subir o plano do GIPHY.

# Figurinha a partir de GIF: guia para o isaCloud Android

Escrito em 13/11/2026 e atualizado em 17/11/2026, depois de a feature ficar pronta e testada no iOS (branch `feature/gif-como-figurinha`). A seção 10 reúne o que foi decidido ou descoberto na implementação. A análise do iOS está em `docs/feature-enviar-gif-figurinha.md`. Este guia complementa outros dois:

- `docs/ferramenta-de-figurinhas.md`: as figurinhas em geral (protocolo, biblioteca, telas);
- `docs/analise-giphy-provider-android.md`: o seletor de GIF (GIPHY e KLIPY).

O guia descreve **o comportamento**, não o código. Nomes do iOS aparecem só como referência. No Android, use o que o projeto já tiver. O que precisa ser **igual nas duas plataformas** vem marcado com **[compatibilidade]**.

## 1. O que é

No seletor de GIF, um interruptor **"Figurinha"**. Ligado, o GIF tocado vai como figurinha, na menor versão do provedor, e fica salvo na biblioteca de figurinhas.

## 2. Decisões da Isadora (13/11/2026)

| Tema | Decisão |
|---|---|
| Onde | Interruptor **"Figurinha"** na barra de cima do seletor de GIF, ao lado do menu do provedor |
| Estado inicial | **Desligado toda vez que o seletor abre.** Não é salvo em preferência. |
| Desligado | Tudo como hoje: o GIF vai como GIF normal |
| Ligado, ao tocar num GIF | Baixa a **menor versão**, salva na biblioteca, **envia na hora** como figurinha (sem passar pela barra de anexos), fecha o seletor e mostra o aviso passageiro **"Figurinha salva"** |
| Versão do GIF | A **menor animada** do provedor (seção 4). Se borrar no aparelho, a regra muda para "a menor com pelo menos ~200 px". Vale para as duas plataformas. |
| Folha de figurinhas | As figurinhas GIF **animam na grade** |
| Na conversa | A figurinha GIF **anima**, sem balão, no mesmo tamanho fixo das outras (128 dp), com o GIF inteiro dentro do quadrado (*fit*) |

## 3. Protocolo [compatibilidade]

Nada novo no XML. A figurinha de GIF é uma figurinha comum, com outro tipo de arquivo:

- Mensagem de arquivo (HTTP Upload + OOB, ou OMEMO), com `<sticker xmlns='urn:xmpp:stickers:0'/>`, como em `ferramenta-de-figurinhas.md` §2.
- **Arquivo:** `image/gif`, com extensão **`.gif`**, nas dimensões em que o provedor entrega. Não é redimensionado nem convertido para 512×512.
- **Regra do tipo, atualizada:** figurinha é **PNG 512×512 ou GIF animado de tamanho livre**. Quem recebe olha o tipo do arquivo (pela extensão ou pelos primeiros bytes), nunca supõe PNG.
- **O GIF não pode passar pela compressão de imagem do app.** Se o Conversations recomprimir a imagem antes do upload, ela vira JPEG parado e perde a animação e a transparência. A figurinha (PNG ou GIF) tem que subir como está.

## 4. A menor versão [compatibilidade]

É a mesma versão que o seletor já usa para a prévia da grade. Por isso costuma já estar em cache:

| Provedor | Versão | Largura típica | Se faltar |
|---|---|---|---|
| GIPHY | `images.fixed_width_small` | 100 px | **Não usar** `fixed_width_small_still`, que é parada. Sem versão animada pequena, o GIF não pode virar figurinha: avisar ou usar a próxima animada (`fixed_width`). |
| KLIPY | `file.xs.gif` | ~170 px, ~110 KB | `file.sm.gif` |

Sempre o arquivo `.gif`, nunca o `mp4` nem o `webp` que os provedores também oferecem: os outros apps mostrariam vídeo ou imagem parada.

## 5. Biblioteca local

A biblioteca de `ferramenta-de-figurinhas.md` §4 passa a guardar dois formatos:

- **Arquivo:** `<id>.png` ou `<id>.gif`.
- **Índice:** cada entrada ganha o campo **`format`** (`"png"` ou `"gif"`). Entrada sem o campo é PNG, assim o índice antigo continua valendo sem migração.
- **Formato pelos bytes, não pelo nome:** `GIF8` no começo é GIF, e `89 50 4E 47` é PNG. Isso vale para o GIF do seletor e para o **"Salvar figurinha"** de uma figurinha recebida.
- **Sem duplicata:** o `sha256` é calculado sobre os bytes do arquivo, como hoje. Tocar no mesmo GIF de novo, com o interruptor ligado, reaproveita a figurinha que já está na biblioteca: envia e atualiza o "usado por último", sem criar outra.
- **Ordem, favoritas e exclusão:** iguais às do PNG.

**Erro que o iOS tem hoje e que o Android deve evitar:** o "Salvar figurinha" grava qualquer arquivo recebido como `.png`. Uma figurinha GIF salva assim fica parada e, se for reenviada, sobe com extensão `.png` e conteúdo GIF. O iOS corrige isso no mesmo PR da feature.

## 6. Exibição

- **Na conversa:** mensagem com o marcador e arquivo GIF usa a mesma linha sem balão das figurinhas, com o GIF animado. Antes de o arquivo baixar, vale o comportamento atual: a visualização normal de imagem.
- **Na grade da folha de figurinhas:** animada. Os arquivos são pequenos (dezenas a poucas centenas de KB), mas a grade pode ter muitas ao mesmo tempo. Se o projeto já usa uma biblioteca de imagem com suporte a GIF (Glide, Coil...), ela resolve cache e reciclagem. Se não, `AnimatedImageDrawable` (API 28+) via `ImageDecoder`.
- **Toque:** como nas outras figurinhas, abre o visualizador. Lá o GIF deve animar, se o visualizador já animar GIFs.
- **Citação e notificação:** como nas outras figurinhas ("🎭 Figurinha" na citação; "Imagem" na notificação).

## 7. Compatibilidade entre versões

| Quem recebe | O que vê |
|---|---|
| isaCloud iOS e Android com esta feature | figurinha animada, sem balão |
| isaCloud iOS até o build 108 | figurinha **parada** (primeiro quadro), sem balão |
| isaCloud Android sem esta feature | depende de como a figurinha é desenhada hoje; se for como imagem parada, o primeiro quadro |
| Monal, Conversations e outros | ignoram o `<sticker/>`; mostram como GIF comum (no Conversations, se anima ou não ainda não foi verificado) |

## 8. Textos (inglês na chave, pt-BR no override do isaCloud)

- `Sticker` = Figurinha (já existe; rótulo do interruptor)
- `Send as sticker` = Enviar como figurinha (acessibilidade do interruptor)
- `Sticker saved` = Figurinha salva (já existe)
- `Could not save the sticker` = Não foi possível salvar a figurinha (já existe; erro ao baixar ou gravar o GIF)

Se o texto final mudar no iOS durante a implementação, este guia é atualizado.

## 9. Como testar

1. Interruptor desligado: o GIF vai como GIF normal, na versão de até 2 MB, pela barra de anexos.
2. Ligado: o GIF vai na hora, sem balão, animado, e aparece na folha de figurinhas, animado na grade.
3. Fechar e abrir o seletor: o interruptor volta desligado.
4. O mesmo GIF duas vezes como figurinha: uma entrada só na biblioteca.
5. Stanza: o arquivo é `.gif`, `image/gif`, e o `<sticker/>` está presente, com e sem OMEMO.
6. **Cruzado com o iOS:** figurinha GIF do Android no iOS e vice-versa, animada dos dois lados. "Salvar figurinha" dos dois lados mantém a animação.
7. Figurinha PNG antiga continua igual (biblioteca, envio e exibição).
8. GIPHY e KLIPY, os dois provedores.
9. Receber no Conversations puro e anotar se anima.

## 10. O que o iOS decidiu e confirmou na implementação (17/11/2026)

A Isadora testou no iPhone (`.dev`) e aprovou ("ficou tudo ótimo"). Vale para o Android seguir o mesmo:

**Decisões confirmadas**
1. **A menor versão pura ficou.** Não foi preciso passar para a versão de ~200 px. Se um dia borrar, a regra muda nas duas plataformas ao mesmo tempo.
2. **O interruptor não é guardado.** Fica só na tela, desligado a cada abertura do seletor. Não criar preferência.
3. **A grade da folha anima** os GIFs.
4. **O toque envia na hora**, sem passar pela barra de anexos, e o seletor fecha sozinho.

**Detalhes de comportamento que o iOS escolheu** (seguir, a menos que o Android tenha motivo)
- **Interruptor sempre visível**, mesmo quando o build tem só um provedor (o menu GIPHY/KLIPY é que some). Fica na barra de cima, à esquerda: ícone de carinha + texto "Figurinha"; ligado, o ícone fica cheio e na cor de destaque. Para leitor de tela: "Enviar como figurinha", e o estado ligado é anunciado como selecionado.
- **A escolha vale para o toque seguinte.** O iOS lê o interruptor no momento do toque, antes de baixar, então desligar no meio do download não muda o que está indo.
- **Sem versão animada pequena:** se o GIF não tiver a menor versão animada (GIPHY sem `fixed_width_small` nem `fixed_width`; KLIPY sem `xs` nem `sm`), vai a **versão normal do GIF (a de até 2 MB), ainda como figurinha**. É raro. Não mostrar erro.
- **Baixar a versão pequena:** conferir resposta 200 e que o arquivo começa com `GIF8` antes de gravar. Arquivo sem isso é erro de download.
- **Ordem ao enviar:** (1) ler os bytes do arquivo baixado e apagar o temporário; (2) guardar na biblioteca (por hash, sem duplicar); (3) enviar a figurinha da biblioteca; (4) mostrar o aviso "Figurinha salva" cerca de 0,3 s depois (o seletor ainda está fechando; aviso pedido durante o fechamento não aparece).
- **Se guardar falhar:** alerta "Não foi possível salvar a figurinha" com "Fechar", também com atraso (0,5 s no iOS) pelo mesmo motivo.
- **O envio usa o arquivo da biblioteca,** não o temporário: a figurinha continua disponível se o envio falhar e for repetido.
- **Sem compressão** e **sem renomear:** o tipo `image/gif` sai da extensão `.gif` do arquivo. Conferir que nada no caminho de upload do Android força PNG ou JPEG.
- **Reenvio com falha** continua marcando o `<sticker/>`, como nas outras figurinhas.
- **"Salvar figurinha" de uma recebida** grava com o formato detectado pelos bytes (no iOS, o mesmo método da biblioteca serve para os dois caminhos: GIF do seletor e figurinha recebida).

**Cache da lista "em alta" (GIPHY e KLIPY)**
- O iOS passou a guardar também a URL da figurinha em cada GIF e **mudou o nome do arquivo do cache para `<provedor>-v3.json`**, para ignorar as listas antigas (que não têm a URL). Se o Android guarda a lista "em alta" no aparelho, fazer o mesmo: invalidar o cache antigo quando o formato do item mudar, senão o interruptor ligado falha ou cai na versão grande nos GIFs que vieram do cache.

**Índice da biblioteca**
- Campo novo **`format`** por figurinha, **opcional**: ausente = PNG, `"gif"` = GIF. O índice antigo continua valendo sem migração. O arquivo é `<id>.png` ou `<id>.gif`.
- Ao carregar, uma entrada cujo arquivo sumiu é descartada, olhando a extensão certa do formato.
- **Atenção a versões antigas:** um aplicativo sem esta feature que ler um índice com `"format": "gif"` não encontra o `<id>.png` e descarta essas entradas na próxima gravação. Isso só importa se o índice for compartilhado entre versões (hoje não é).

**Exibição**
- Para saber se um arquivo recebido é GIF, **ler os primeiros 4 bytes (`GIF8`) e guardar a resposta por URL/arquivo** (para a grade não reabrir o arquivo a cada redesenho). Nunca pela extensão: com OMEMO o nome do arquivo vira um UUID.
- O GIF anima em loop sem parar na conversa e na grade, sem balão, no mesmo quadrado das outras figurinhas, com o GIF inteiro dentro (*fit*).

**O que o iOS ainda não tem**
- Testes automáticos da biblioteca com GIF (índice antigo, PNG e GIF juntos, duplicata). Os testes do iOS cobrem só a escolha das URLs (GIPHY e KLIPY), o cache `v3` e a leitura do formato pelos bytes. No Android, vale escrever os da biblioteca desde o começo.
- Teste no Conversations puro (se anima ou não): ainda não feito.

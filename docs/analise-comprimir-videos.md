# Análise: comprimir vídeos ao enviar e deixar num formato compatível

Data: 04/11/2026; medições com vídeo real de iPhone acrescentadas em 06/11/2026; decisões da primeira entrega (galeria, 480p) em 06/11/2026. Status: **implementação da galeria em andamento** (branch `feature/comprimir-video-galeria`, sem PR; roadmap 161). Câmera implementada em 09/11/2026 (conversão + duração máxima pelo limite); a folha de compartilhar só confere o tamanho, sem converter. Teste pela Isadora no `.dev`, sem simulador (créditos).

## Primeira entrega: galeria, 480p (06/11/2026)

Decidido pela Isadora em 06/11/2026, depois das medições:

- **Escopo:** só a galeria (seletor de mídia do chat). Câmera (gravação direta) e folha de compartilhar ficam para a segunda etapa, quando a galeria estiver validada no `.dev`.
- **Só 480p.** A opção 720p sai do escopo: o preset passa do limite de 200 MB em cerca de 2 min e 25 s de vídeo (medido). Volta quando houver conversão com bitrate próprio (`AVAssetWriter`) ou um limite de duração para ela.
- **Opções em Anexos:** "Original" ou "480p" (padrão 480p). Configuração própria, separada da de fotos (chave `videoCompressionMode`).
- **Não converter abaixo de 512 KB** (igual ao Android).
- ~~**Duração máxima de 300 s.**~~ (Removida em 09/11/2026: vale só o limite de upload da conta, com o tamanho real conferido antes de subir; ver `docs/decisoes.md`.) Acima disso o envio era recusado antes da conversão, com aviso. Margem com o limite de 200 MB: 480p de 250 s deu 123 MB, então 300 s dá cerca de 147 MB (estimativa linear a partir da medição).
- **Localização (GPS): remover com o filtro de compartilhamento** (`AVMetadataItemFilter.forSharing()` no `AVAssetExportSession`). Ainda **não verificado**: antes de liberar qualquer build, conferir no log do `.dev` que a saída sai com `gps=não`. Se sair `gps=sim`, o recurso não vai para o TestFlight.
- **Só com o app aberto**, sem tarefa em segundo plano. Aviso "Mantenha o app aberto" durante a conversão.
- **Falha da conversão:** envia o original e registra no log. Se o original passar de 200 MB, o envio falha pelo caminho de erro que já existe.
- **Miniatura:** não gerada no MVP (usa a do original, como hoje).
- **Log:** tamanho original, duração, dimensões, codec, taxa, tamanho final, tempo, resultado (`converted`, `kept_small`, `kept_original_after_failure`, `too_long`) e `gps=sim/não`. Sem nome nem caminho do arquivo.

Pergunta: vídeos gravados pelo iPhone são `.mov` (HEVC por padrão), e no Android eles não tocam bem. Como reduzir e converter o vídeo no envio para que chegue em formato compatível com qualquer cliente, e como cobrir os três caminhos de entrada.

## Resumo

- **O Android já faz o que propomos para o próprio envio.** Vídeo acima de 512 KB é reencodado para MP4 H.264 + AAC (padrão 480p) antes de sair. O lado Android está pronto; o problema é só o vídeo que vem **do iPhone**.
- **Para o iPhone, quase todo vídeo precisa ser convertido.** Gravações e vídeos da galeria são `.mov` HEVC. O modo "Apenas se necessário" converteria quase tudo, então, na prática, a escolha real é **a resolução de saída** e se existe um modo "Original".
- **Os presets da Apple servem:** `Preset1280x720` e `Preset640x480` geram H.264 + AAC em MP4 (testado). `PresetMediumQuality` saiu pequeno demais (568×320) e os `PresetHEVC*` mantêm HEVC, então não servem.
- **Metadados:** o `avconvert` padrão **apaga a localização** (GPS). Só mantém com `--disableMetadataFilter` (testado). **Com `AVAssetExportSession` (o caminho proposto), a localização continua no arquivo** (medido em 06/11/2026 com vídeo real). Para remover o GPS é preciso filtrar os metadados ou usar `AVAssetWriter`.
- **Vídeo real de iPhone (06/11/2026, medido no Mac):** 480p saiu em 123 MB para 4 min e 11 s, em 10 s. 720p saiu em 346 MB, em 28 s. O 720p **não reduz o suficiente** para o limite de 200 MB (ver "Limite" abaixo).
- **Ainda falta medir no iPhone XR** (tempo e aquecimento) e confirmar a rotação com um vídeo gravado em retrato.

## Os três caminhos de entrada

Todos os três hoje mandam o arquivo **como está**, sem transcodificar. Nenhum usa `AVAssetExportSession` nem `AVAssetWriter` para vídeo (só `HelperTools createAVURLAssetFromFile`, para reproduzir, e `MediaViewer`/`MLFileTransferVideoCell`, que leem).

1. **Galeria (`PHPicker`)**
   - `Monal/Classes/SwiftuiHelpers.swift` (~400 a 430): `provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier)` copia o arquivo da biblioteca e entrega com `isVideo: true`. Não é reencodado.
2. **Câmera (gravação direta)**
   - `Monal/Classes/SwiftuiHelpers.swift` (~480 a 495): `UIImagePickerController`, `info[.mediaURL]` copiado para uma pasta temporária. Sem ajuste de `videoQuality`, então sai no formato padrão do aparelho (HEVC).
   - A tela antiga (`chatViewController.m` ~1700) segue o mesmo caminho (`prepareFileUpload`).
3. **Compartilhar (extensão `shareSheet`)**
   - `Monal/shareSheet-iOS/ShareViewController.m` (~233): aceita `audiovisual` e grava com `addShareSheetPayload`. A extensão tem pouco tempo e pouca memória, então a conversão tem de acontecer no app principal (`sendAllOutboxes`, `MonalAppDelegate`), como proposto para fotos.

Em comum: `+[MLFiletransfer prepareFileUpload:]` (`MLFiletransfer.m` ~696) manda o arquivo como está, com o MIME tirado do nome. Para `.mov` dá `video/quicktime`. Só a foto tem ponto de decisão (`prepareUIImageUpload:`); vídeo não tem nenhum.

## O que o Android faz (repositório `~/projects/java/isaCloudMessenger`)

Verificado no código do cliente Android:

- **Envio:** `AttachFileToConversationRunnable.java` (`processAsVideo`, ~75 a 140). Só converte se o arquivo é `video/*`, passa de `auto_accept_filesize` (512 KB, `defaults.xml`) e a preferência `video_compression` não é `uncompressed`. Padrão: **480** (`strings.xml`/`defaults.xml`). Opções: 360, 480, 720, 1080, original.
- **Biblioteca:** `com.otaliastudios.transcoder`, com as estratégias de `utils/TranscoderStrategies.java`:

  | Opção | Vídeo máximo | Bitrate | Quadros | Keyframe | Áudio |
  |---|---|---|---|---|---|
  | 1080 | 1080 px | 4 Mbps | 30 | 3 s | AAC 192 kbps, estéreo |
  | 720 | 720 px | 2 Mbps | 30 | 3 s | AAC 192 kbps, estéreo |
  | 480 | 480 px | 1 Mbps | 30 | 3 s | AAC 96 kbps, estéreo |
  | 360 | 360 px | 500 kbps | 30 | 3 s | AAC 96 kbps, estéreo |

- **Regra de tamanho:** se o convertido não ficar menor que o original, o Android manda o original (`onTranscodeCompleted`).
- **Recebimento:** `MimeUtils.java` mapeia `.mov`/`.qt` para `video/quicktime` e `.mp4` para `video/mp4`. Não há tratamento especial de HEVC nem de QuickTime no envio nem na reprodução (verificado por leitura; não testado em aparelho).

**Consequência:** a especificação de qualidade do Android (720p a 2 Mbps, 480p a 1 Mbps) é o alvo natural para o iOS. Assim, quem manda do iOS recebe o mesmo tipo de arquivo que o Android já manda.

## Por que `.mov` não toca no Android

Hipótese (ainda não confirmada em aparelho): o Android decodifica bem H.264 em MP4, mas HEVC e o contêiner QuickTime dependem do aparelho e da versão do sistema. O resultado seria o vídeo aparecer como anexo genérico ou falhar a miniatura.

**Para confirmar:** um `.mov` real de iPhone enviado a um Android (aparelho ou emulador), anotando MIME, codec e o que o cliente mostra.

## Testes feitos no Mac (vídeos sintéticos, dados de teste)

Gerados com `ffmpeg` (fonte sintética) em uma pasta temporária, fora do repositório:

| Entrada | Saída (`avconvert`) | Codec | Resolução | Tamanho |
|---|---|---|---|---|
| HEVC 1080p, 8 s | `PresetMediumQuality` | H.264 Main | 568×320 | 0,86 MB |
| HEVC 1080p, 8 s | `Preset1280x720` | H.264 Main, AAC | 1280×720 | 5,8 MB |
| HEVC 1080p, 8 s | `Preset1920x1080` | H.264 High, AAC | 1920×1080 | 8,6 MB |
| HEVC 1080p, 8 s | `PresetHEVC1920x1080` | **HEVC** | 1920×1080 | 8,2 MB |
| HEVC retrato 1080×1920, 8 s | `Preset1280x720` | H.264 Main | **720×1280** | 6,6 MB |
| HEVC 4K, 60 s, 302 MB | `Preset1280x720` | H.264 Main | 1280×720 | 47,8 MB, 5 s |
| HEVC 4K, 60 s, 302 MB | `Preset1920x1080` | H.264 High | 1920×1080 | 71,1 MB, 8 s |
| HEVC 4K, 60 s, 302 MB | `Preset640x480` | H.264 Main | 640×360 (mantém proporção) | 13,8 MB, 4 s |

Leituras:

- **Compatibilidade:** os `Preset` de tamanho fixo (`Preset1280x720`, `Preset640x480`, `Preset1920x1080`) geram H.264 + AAC em MP4. Esse é o formato alvo.
- **Retrato:** a orientação se mantém (720×1280 de um 1080×1920). **Rotação por metadado (matriz de exibição) não foi verificada:** o vídeo sintético não gravou essa matriz. Precisa de um `.mov` de iPhone gravado em retrato.
- **Tamanho:** o 720p do preset deu cerca de **6,2 Mbps** (sintético, 4K de 40 Mbps). Com **vídeo real de iPhone** (HEVC 13 Mbps, 4 min e 11 s, medido em 06/11/2026) deu **11,1 Mbps**, quase o dobro, e o 480p deu **3,6 Mbps**. O padrão do Android é 2 Mbps para 720p e 1 Mbps para 480p. Os presets ficam **acima** do alvo do Android; para bater com ele é preciso controle de bitrate, o que só dá com `AVAssetWriter` (ver "Como converter").
- **Descartados:** `PresetMediumQuality` (resolução baixa demais no teste), `PresetHEVC*` (mantêm HEVC), `PresetPassthrough` (não converte).
- **Tempo:** 60 s de 4K para 720p em 5 s neste Mac. **No iPhone XR não medido**; é o número que decide se a conversão no envio é aceitável.

## Formato alvo proposto

- **Contêiner:** MP4 (`video/mp4`, `.mp4`).
- **Vídeo:** H.264 Main ou High, nível 4.0 para 1080p (o que o Android decodifica em qualquer aparelho).
- **Áudio:** AAC estéreo, 96 kbps (480p) ou 192 kbps (720p e acima), igual ao Android.
- **Resolução e bitrate** (igual às opções do Android):
  - 720p, 2 Mbps, AAC 192 kbps (proposta de padrão);
  - 480p, 1 Mbps, AAC 96 kbps (economia);
  - Original (sem conversão).
- **Rotação:** preservar, confirmar com vídeo real de iPhone em retrato.

## Modos e padrão

Como o iPhone grava HEVC `.mov` por padrão, o modo "Apenas se necessário" (converter só o que não é H.264 em MP4) **converteria quase todo vídeo do iPhone**. Por isso o desenho é espelhar as opções do Android:

- **Original:** envia como hoje (sem conversão). Não serve para vídeo acima de 200 MB (limite de upload do isaCloud, aumentado de 150 MB pela Isadora em 06/11/2026).
- **720p:** converte para H.264 + AAC, até 720 px, 2 Mbps.
- **480p (padrão):** igual, até 480 px, 1 Mbps (economia de dados e de tempo). Decidido.

Vídeo abaixo de 512 KB passa sem conversão, como no Android. Acima disso, segue a opção escolhida.

**Configuração própria para vídeo, separada da de imagens (decidido).** Quem tinha "Enviar imagens originais" ligada (migrada para `Nunca` no build 90) não herda nada para vídeo: a configuração de vídeo começa em 480p.

## Como converter (iOS)

- **Conversão: Opção A, `AVAssetExportSession` com preset** (`Preset640x480` para 480p, `Preset1280x720` para 720p, `outputFileType = .mp4`). **Decidido.** Simples, sem bibliotecas, testado. Limitação: sem controle de bitrate, então o 720p sai acima do alvo do Android. A Opção B (`AVAssetWriter`, bitrate igual ao Android) fica de reserva, só se o tamanho incomodar.
- **Progresso:** `exportSession.progress` (ou o callback do writer) alimenta "Preparando vídeo N de M…", como no plano de fotos.
- **Falha:** se a conversão falhar, enviar o original e avisar que o vídeo foi enviado sem conversão. O aviso vermelho de falha só aparece se o upload falhar.
- **Segundo plano: esperar (decidido).** A conversão só continua com o app aberto. Se a pessoa sair, a conversão recomeça ao voltar, e a mensagem fica pendente até lá. Mostrar o aviso "mantenha o app aberto" durante a conversão. Não cancelamos nem enviamos o original: o original de vídeo longo (350 MB para 4 minutos) passa do limite de 200 MB, então não tem como sair.
- **Limite de 200 MB (decidido: prever antes de converter).** O servidor passou a aceitar 200 MB (decisão da Isadora em 06/11/2026). Checar a duração no início e recusar com aviso antes de converter, com margem de segurança. Com o vídeo real (06/11/2026): **480p** saiu 123 MB para 250 s, ou seja, **cerca de 6 min e 47 s** para bater 200 MB (200 ÷ 123 × 250 s ≈ 407 s); o teto de 300 s segura antes disso, com cerca de 147 MB no pior caso. **720p** saiu 346 MB para 250 s, ou seja, **cerca de 2 min e 25 s** para bater 200 MB. Isso já mostra que o 720p do preset não serve para vídeos longos; a opção 720p precisaria de limite de duração próprio ou de `AVAssetWriter`. Testar `estimatedOutputFileLength` do `AVAssetExportSession` no iPhone antes de confiar nele. Depois da conversão, conferir o tamanho real de novo antes do envio.
- **Log (decidido, como nas fotos):** registrar o original (tamanho, duração, resolução, codec, bitrate), o preset usado, o arquivo final (tamanho), o tempo de conversão e o resultado (convertido, falha, recusado pelo limite). Sem nome de arquivo nem caminho completo.
- **Extensão de compartilhar:** adiar a conversão para o app principal (`sendAllOutboxes`), igual às fotos.
- **Metadados:** `avconvert` padrão **remove a localização** (testado: GPS presente na entrada, ausente na saída). Com `--disableMetadataFilter` ela se mantém. **`AVAssetExportSession` mantém a localização** (medido em 06/11/2026: GPS presente na entrada e na saída de 480p e 720p). Por isso o GPS **não sai só com o preset**: é preciso filtrar os metadados ou converter com `AVAssetWriter`. **Decidido: remover o GPS** (privacidade). Dizer isso na tela de Anexos.
- **Miniatura:** gerar a miniatura do MP4 convertido (hoje `MLFiletransferInfo` e `MLFileTransferVideoCell` usam a do original).

## Riscos e merge

- Não muda protocolo nem banco: o arquivo continua sendo um anexo HTTP Upload (XEP-0363) com `video/mp4`. Qualquer cliente recebe.
- Toca em `SwiftuiHelpers.swift`, `MLFiletransfer.m`, `ShareViewController.m`, `GeneralSettings.swift` e `MLXMPPManager.m`. Registrar em `docs/decisoes.md` para os merges futuros com o Monal.
- Conversão no aparelho gasta bateria, esquenta e usa memória. Testar no iPhone XR (iOS 18) além do iPhone da Isadora.
- Armazenamento temporário: o MP4 convertido ocupa espaço até o envio terminar. Limpar os `tmp.<uuid>` órfãos com a mesma rotina proposta para imagens.

## Validação (quando for implementar)

- Vídeos de teste, com dados de teste (nada de pessoas nem conversas reais): HEVC 1080p, H.264, `.mp4` H.264 pequeno, 4K de mais de 2 minutos e um vídeo gravado em retrato, todos gerados para o teste ou gravados no próprio aparelho de teste.
- Nos três caminhos (galeria, câmera, compartilhar), conferir formato, tamanho e rotação de cada envio.
- Nos três modos (Original, 720p, 480p) no simulador iOS 18.6 e 27 e no iPhone XR e no da Isadora.
- Receptor: isaCloud (iOS) e isaCloudMessenger (Android), com reprodução e miniatura.
- Captura da tela de Anexos e do progresso, em `docs/screenshots/`, sem dados pessoais.
- **Limitação:** o simulador não tem câmera; a gravação direta só se testa no iPhone (`.dev`).

## Decisões registradas (04/11/2026)

1. **Padrão:** 480p. Opções: Original, 720p e 480p.
2. **Conversão:** Opção A (preset da Apple). Opção B fica de reserva.
3. **GPS:** removido.
4. **Segundo plano:** esperar, com o app aberto. Sem envio do original em caso de espera longa.
5. **Limite de 200 MB:** checado pela duração antes de converter.
6. **Configuração de vídeo separada da de imagens.** Não herda nada da configuração de imagens; começa em 480p.
7. **Log como nas fotos** (original, preset, arquivo final, tempo, resultado).

## Pendências (não bloqueiam as decisões acima)

1. **Rotação e tempo no iPhone:** não verificados. O tempo medido (10 s a 28 s para 4 min) foi no Mac; no iPhone XR precisa de medição. A Isadora testa no `.dev`, com a instrumentação do log. Rotação: o vídeo real de 06/11/2026 é paisagem (matriz 0°); falta um em retrato.
1b. **720p acima do limite de 200 MB** para vídeos de mais de cerca de 2 min e 25 s (medido em 06/11/2026). Decidir: 720p só para vídeos curtos, 720p com `AVAssetWriter` (bitrate próprio), ou tirar a opção 720p por enquanto.
1c. **GPS no `AVAssetExportSession`:** a localização continua no arquivo (medido em 06/11/2026). Decidir o caminho para remover (filtro de metadados ou `AVAssetWriter`).
2. **`estimatedOutputFileLength`:** testar no iPhone antes de usar a estimativa.
3. **Opção "Original" para vídeo acima de 200 MB:** decidir se ela some, fica desabilitada ou só avisa.
4. **Mensagens antigas:** não convertemos o que já foi enviado.
5. **Android não testado em aparelho:** a hipótese de HEVC/QuickTime como causa precisa de um teste com `.mov` real no cliente Android.

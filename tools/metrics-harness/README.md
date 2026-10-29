# Harness de métricas do isaCloud

Envia para um InfluxDB 2.x as métricas que o app isaCloud coleta no aparelho:
as amostras periódicas (memória, CPU, bateria/térmica, banco) e os payloads do
MetricKit. A entrada é o JSON que o app exporta — ou o diretório do container
do app, com os arquivos brutos.

Faz parte do harness o dashboard do Grafana 12.0.1 em
[`grafana/isaCloud-metrics-12.0.1.json`](grafana/isaCloud-metrics-12.0.1.json).

Requisitos: Python 3.8 ou mais novo. **Só biblioteca padrão** — não precisa de
`pip install`, `influx` CLI nem nada além do Python.

## Como o app exporta

No app: **Depuração → Métricas do aparelho → "Exportar métricas"**. O app grava
um arquivo JSON único, com esta forma (resumida):

```json
{
  "exportedAt": "2026-10-29T14:20:00Z",
  "build": "54",
  "samples": [
    {
      "ts": "2026-10-29T14:20:00Z",
      "build": "54",
      "short": "0.0.1",
      "ios": "26.7.2",
      "model": "iPhone13,3",
      "mem_footprint_mb": 142.3,
      "mem_available_mb": 58.9,
      "cpu_ms": 3120,
      "wall_ms": 60000,
      "thermal": "nominal",
      "low_power": false,
      "battery": 0.62,
      "accounts_idle": true,
      "last_appex_start": "2026-10-29T14:05:00Z",
      "db_mb": 37.2,
      "db_lock_waits": 0,
      "db_lock_max_ms": 0,
      "wal_mb": 0.4
    }
  ],
  "metrickit": [
    { "kind": "metric", "receivedAt": "2026-10-29T13:00:00Z", "build": "54", "payload": { } }
  ]
}
```

O diretório do container do app (o `<grupo>/metrics` do app, copiado pelo
Xcode/Finder) tem ainda os arquivos brutos:

- `samples-AAAA-MM-DD.jsonl` — uma amostra JSON por linha, mesmo schema de `samples`;
- `metrickit-*.json` — um payload MetricKit por arquivo (`dictionaryRepresentation` do sistema).

O `send.py` aceita as duas formas: o **arquivo único exportado** ou um
**diretório** com os arquivos brutos (e, se houver um export completo dentro do
diretório, ele também é lido). Todos os arquivos são lidos e validados antes de
qualquer envio: um arquivo malformado aborta a execução sem enviar nada.

## Configuração: `.credentials`

As credenciais ficam em um arquivo `.credentials` **no mesmo diretório deste
`send.py`** (ele é ignorado pelo Git). Comece copiando o exemplo:

```sh
cd tools/metrics-harness
cp .credentials.example .credentials
chmod 600 .credentials
$EDITOR .credentials
```

Formato: `CHAVE=valor`, uma por linha; linhas em branco e linhas começando com
`#` são comentários. O `#` só vale no começo da linha (não há comentário no fim
da linha). Valores podem vir entre aspas simples ou duplas.

| Variável | Obrigatória | Padrão | O que é |
| --- | --- | --- | --- |
| `INFLUX_URL` | sim | — | URL base do InfluxDB 2.x, sem `/api/v2` e sem barra no fim (ex.: `http://localhost:8086`) |
| `INFLUX_TOKEN` | sim | — | token de API com permissão de **escrita** no bucket |
| `INFLUX_ORG` | sim | — | organização dona do bucket |
| `INFLUX_MEASUREMENT` | sim | — | measurement das amostras; o MetricKit usa `<valor>_metrickit` (ex.: `isacloud_metrics`) |
| `INFLUX_BUCKET` | não | `isacloud_ios` | bucket de destino |
| `INFLUX_TIMEOUT` | não | `10` | timeout de cada POST, em segundos |

O token nunca é impresso: mensagens de erro passam por uma função que troca o
token por `***` antes de escrever na tela.

> **Atenção (para agentes e para mim mesmo):** `.credentials` e `.sent-state.json`
> são **dados de quem usa o harness**, não arquivos temporários. Nunca apagar,
> nem "limpar" o diretório assumindo que são restos de teste. Para testar, use
> `--credentials /tmp/algum.credentials` (nunca o arquivo real).

### Apagar os pontos de uma measurement

Quando o schema muda (é o caso depois de trocar inteiro por float), use o
`reset-measurement.sh`: ele lê o mesmo `.credentials`, chama o `influx delete`
por você, mostra o comando com o token redigido no `--dry-run` e, ao final,
**limpa o `.sent-state.json`** (senão o harness acharia que os registros já
foram enviados e não os reenviaria). `--keep-state` preserva o estado.

```sh
./reset-measurement.sh --dry-run    # confere bucket/org/measurement
./reset-measurement.sh              # apaga
```

## Tipos de field (importante)

Todo **número** é enviado como **float** (com ponto decimal: `cpu_ms=0.0`,
`wall_ms=406.93`). O InfluxDB fixa o tipo de cada field na primeira escrita; se a
mesma coluna chegasse como inteiro numa amostra e float na seguinte, o lote seria
recusado com `field type conflict`.

Se você já tiver dados gravados por uma versão anterior do harness (que mandava
inteiros como `0i`), apague a measurement antes de enviar de novo:

```sh
influx delete --bucket isacloud --org <org> \
  --start 1970-01-01T00:00:00Z --stop $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --predicate '_measurement="isacloud_metrics"'
```

(ou troque `INFLUX_MEASUREMENT` e ajuste as queries do dashboard).

## Ambiente (venv)

O harness não tem dependências de terceiros (só a biblioteca padrão), mas o
diretório tem um `.venv` pronto para isolar o Python e para o dia em que alguma
dependência aparecer:

```sh
python3 -m venv .venv                 # já criado neste repositório
.venv/bin/pip install -r requirements.txt   # hoje: nada a instalar
```

Os comandos abaixo usam `.venv/bin/python`; se preferir o Python do sistema,
basta trocar por `python3`.

## Como rodar

Sempre a partir de qualquer diretório (o script acha o próprio `.credentials`):

```sh
cd tools/metrics-harness

# 1) conferir o line protocol sem enviar nada (e sem gravar estado)
python3 send.py /caminho/para/export.json --dry-run --verbose

# 2) enviar o arquivo único exportado
python3 send.py /caminho/para/export.json --verbose

# 3) enviar o diretório do container do app (samples-*.jsonl + metrickit-*.json)
python3 send.py /caminho/para/container/metrics --verbose

# 4) usar um estado de idempotência em outro lugar
python3 send.py /caminho/para/container/metrics --state ~/.isacloud-metrics-state.json
```

Opções:

| Opção | Efeito |
| --- | --- |
| `--dry-run` | imprime o line protocol no **stdout** (uma linha por registro), não envia e **não** grava estado; avisos/resumo vão para o stderr |
| `--state ARQUIVO` | estado de idempotência (padrão: `.sent-state.json` no diretório do harness) |
| `--verbose` | mostra no stderr cada arquivo lido, contagens, lotes e resposta HTTP |

Códigos de saída: `0` tudo certo (inclusive "nada novo"); `1` alguma escrita
falhou no InfluxDB; `2` erro de configuração, credenciais ou entrada.

O `--dry-run` também carrega o `.credentials` (as quatro variáveis precisam
existir), mas não usa o token nem o host: para só conferir o line protocol, copie
o `.credentials.example` e deixe os valores de exemplo.

### Exemplo real de `--dry-run`

Saída para uma amostra de build 54 em `2026-10-29T14:20:00Z` (repare no `\,`
escapando a vírgula de `iPhone13,3` e no `i` dos inteiros):

```text
isacloud_metrics,build=54,ios=26.7.2,low_power=false,model=iPhone13\,3,thermal=nominal accounts_idle=true,battery=0.62,cpu_ms=3120i,db_mb=37.2,mem_available_mb=58.9,mem_footprint_mb=142.3,wal_mb=0.4,wall_ms=60000i 1793283600000
```

E um payload MetricKit do mesmo build (medição separada, fields achatados):

```text
isacloud_metrics_metrickit,build=54,kind=metric applicationLaunchMetrics_histogrammedTimeToFirstDraw_histogramBucketCount=7i,applicationLaunchMetrics_histogrammedTimeToFirstDraw_histogramValue_average=512.25,cpuMetrics_cumulativeCPUInstructions=987654321i,cpuMetrics_cumulativeCPUTime=1234.5,includesMultipleApplicationVersions=false,memoryMetrics_averageSuspendedMemory_averageValue=134217728i,memoryMetrics_averageSuspendedMemory_sampleCount=42i,memoryMetrics_peakMemoryUsage=268435456i 1793278800000
```

## O que é enviado

O envio é um `POST` para
`{INFLUX_URL}/api/v2/write?org={ORG}&bucket={BUCKET}&precision=ms`, com
`Authorization: Token {TOKEN}`, `Content-Type: text/plain; charset=utf-8` e
todas as linhas no corpo. HTTP 2xx (o InfluxDB responde **204**) é sucesso; um
status de erro é mostrado com o corpo da resposta (limitado a 500 caracteres) e
o processo termina com código 1. Em 401/403 o envio é interrompido na hora;
falha de conexão também.

### Medição das amostras

- **measurement**: o valor de `INFLUX_MEASUREMENT` (exemplo: `isacloud_metrics`)
- **tags**: `build`, `ios`, `model`, `thermal`, `low_power` (`low_power` vai como `true`/`false`)
- **fields**: todos os campos numéricos ou booleanos da amostra —
  `mem_footprint_mb`, `mem_available_mb`, `cpu_ms`, `wall_ms`, `battery`,
  `db_mb`, `wal_mb`, `accounts_idle` (e qualquer campo numérico novo que o app
  passar a exportar)
- **timestamp**: `ts` convertido para **milissegundos** desde 1970

Campos de texto da amostra (`short`, `last_appex_start`) **não** são enviados —
o harness ignora strings de propósito. Se precisar deles, viram tag ou são
convertidos em outro lugar (ver Limitações).

### Medição do MetricKit

- **measurement**: `<INFLUX_MEASUREMENT>_metrickit` (exemplo: `isacloud_metrics_metrickit`)
- **tags**: `build`, `kind` (`kind` vem do export; em arquivo cru, do nome do arquivo — `diagnostic`, `crash`, `hang`, `spin`, `diskwrite`; senão `metric`)
- **fields**: o `payload` achatado com `_`; **números e booleanos** viram fields.
  - dicionários aninhados viram caminhos: `memoryMetrics.averageSuspendedMemory.sampleCount` → `memoryMetrics_averageSuspendedMemory_sampleCount`
  - **strings são ignoradas** (`appVersion`, `osVersion`, `deviceType`, etc.) — mantém a cardinalidade baixa e o código simples; o que importa para série temporal são os números
  - **listas são ignoradas** (ex.: `signpostMetrics`); seria possível achatar por índice, mas o ganho não paga a complexidade
- **timestamp**: `receivedAt` do registro do export; em arquivo cru, na ordem `receivedAt` → `receivedDate` → `timestampEnd`; se nenhum existir, usa o `mtime` do arquivo (com aviso em `--verbose`). Tudo em milissegundos.

### Escapes do line protocol

Medição, tags e chaves de field escapam `,`, `=` (quando aplicável) e espaço com
`\`; strings de field (hoje nenhuma é enviada) escapariam `\` e `"`. Valores de
tag são texto: booleanos viram `true`/`false`, e quebras de linha viram espaço.
Inteiros saem com sufixo `i` (`3120i`), floats com ponto (`142.3`, `60000.0`) —
o tipo do field fica estável no InfluxDB.

## Idempotência (`.sent-state.json`)

Rodar o harness duas vezes sobre o mesmo export (ou sobre o arquivo e o
diretório, que se sobrepõem) não duplica pontos. Para cada registro já enviado,
o estado guarda uma chave:

```text
tipo|build|timestamp_ms|sha1_16(canonical do registro)
```

- `tipo`: `sample` ou `metrickit`
- `build`: o build da amostra/payload
- `timestamp_ms`: o timestamp já em milissegundos
- `sha1_16`: os 16 primeiros hex do SHA-1 do JSON canônico (tags + fields + ts), então mudar qualquer valor gera outra chave

O `.sent-state.json` é um JSON `{"version": 1, "sent": {"<chave>": "<quando>"}}`,
gravado de forma atômica (arquivo `.tmp` + `rename`) **só depois** de o InfluxDB
aceitar o lote. Se um lote falhar, suas chaves não entram no estado e a próxima
execução tenta de novo. `--dry-run` **não lê nem grava** o estado.

O arquivo cresce com o número de registros enviados (não há poda automática);
para reiniciar do zero, apague o `.sent-state.json` (isso reenvia pontos, que o
InfluxDB sobrescreve por timestamp+tags).

## Dashboard do Grafana 12.0.1

Importe em **Dashboards → New → Import → Upload JSON** e escolha o datasource
InfluxDB quando o Grafana pedir. O dashboard tem **uma única variável de
template**, `datasource` (tipo `datasource`, plugin `influxdb`, sem "All" e sem
multi), e todos os painéis apontam para ela — não há filtro por build nem
variável de intervalo: o período é o do seletor de tempo (padrão: últimas 6 h) e
o `refresh` é `30s`.

| Painel | Tipo | O que mostra |
| --- | --- | --- |
| Memória (MB) | timeseries | `mem_footprint_mb` e `mem_available_mb` por build |
| CPU (ms por amostra e taxa) | timeseries | `cpu_ms` médio por janela e taxa = `cpu_ms / wall_ms × 100` (% de um núcleo) |
| Banco de dados e WAL (MB) | timeseries | `db_mb` e `wal_mb` por build |
| Bateria | gauge | última leitura de `battery`, com faixas (vermelho < 20%, laranja < 50%) |
| Energia (low_power) | state timeline | tag `low_power` como estado (Normal/Economia) |
| Térmica | state timeline | tag `thermal` como estado (Nominal/Razoável/Sério/Crítico) |
| Última amostra por build | tabela | último valor de cada field por build, com ios/model/thermal/low_power |
| Amostras por build | bar chart | quantidade de amostras distintas (por timestamp) em cada build |

As queries são Flux, com `from(bucket: "isacloud_ios")`, `range(start: v.timeRangeStart, stop: v.timeRangeStop)`,
a measurement como constante `"isacloud_metrics"` e agrupamento por `build`
(veja a documentação dos macros Flux do Grafana: `v.timeRangeStart`,
`v.timeRangeStop` e `v.windowPeriod` — este último é o intervalo calculado pelo
dashboard, então não existe variável de intervalo).

**Atenção:** o bucket (`isacloud_ios`) e a measurement (`isacloud_metrics`) são
constantes nas queries. Se você mudar `INFLUX_BUCKET` ou `INFLUX_MEASUREMENT` no
`.credentials`, edite as queries no dashboard (ou faça uma cópia) para casar.

Cada série aparece como `build · campo` (ex.: `54 · mem_footprint_mb`), então dá
para comparar builds no mesmo painel sem variável de filtro.

## Segurança

- `.credentials` está no `.gitignore` deste diretório e **nunca** deve ir para o Git,
  para um print, para uma issue ou para uma mensagem. Se vazar, revogue o token
  no InfluxDB e crie outro.
- O token só existe no header `Authorization`; o log de erro troca o token por `***`.
- O `.sent-state.json` não tem segredo (só hashes), mas também é ignorado.
- Prefira um token só com permissão de escrita no bucket (não use o token de
  operador/admin).

## Limitações conhecidas

- `short` (versão curta) e `last_appex_start` das amostras não são enviados: são
  strings e o schema do InfluxDB pedido só tem tags/fields numéricos. Se virarem
  tag, a cardinalidade cresce por release — avalie antes.
- MetricKit: strings e listas do payload são descartadas (decisão para manter o
  harness simples). `signpostMetrics` e histogramas em lista não aparecem.
- O state não tem poda automática e o harness carrega a entrada inteira em
  memória (tranquilo para exports de dias; para anos de amostras, divida por
  arquivo).
- O envio é em lotes de até 500 linhas / 512 KB, sem retry com backoff. Se a
  rede cair no meio, rode de novo: o estado evita reenviar o que já entrou.
- Reenviar um registro com o mesmo `ts` e as mesmas tags faz o InfluxDB
  sobrescrever os fields daquele ponto (não cria ponto duplicado), mas um field
  ausente no reenvio não apaga o valor antigo.
- Amostras sem `ts` válido, sem nenhum field numérico ou payloads MetricKit sem
  timestamp são ignorados com aviso (e contados no resumo).
- `INFLUX_URL` deve ser a URL base; se você colocar `/api/v2` no caminho, o
  endpoint fica duplicado e o InfluxDB responde 404.

## Aberturas a frio (`launches-*.jsonl`)

Desde o build 63 o app grava **uma linha por abertura** em `<grupo>/metrics/launches-AAAA-MM-DD.jsonl`
(e no campo `launches` do export de métricas). O `send.py` reconhece esses arquivos e envia para a
medida **`<measurement>_launch`**, com `build`, `ios` e `model` como tags:

| campo | o que é |
|---|---|
| `launch_ms` | de `main()` até a tela de conversas aparecer (o que a pessoa espera) |
| `app_delegate_ms` | trabalho na thread principal no `didFinishLaunching` |
| `list_build_ms` | montagem da lista no refresh (banco + filtros + reload) |
| `list_ready_ms` | marco de quando a lista ficou pronta |
| `first_frame_ms` | marco do primeiro desenho da tela |
| `main_ms` | `app_delegate_ms + list_build_ms` (o que dá para otimizar na main) |
| `cold` | sempre `true` (processo novo) |

O painel **"Abertura a frio (ms)"** do dashboard mostra esses campos por build.

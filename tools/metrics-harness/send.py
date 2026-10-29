#!/usr/bin/env python3
"""Harness de envio das métricas do isaCloud para um InfluxDB 2.x.

Lê o JSON exportado pelo app (Depuração -> "Exportar métricas") ou um
diretório com os arquivos brutos do container do app e envia cada amostra e
cada payload MetricKit como line protocol, por HTTP POST.

Somente biblioteca padrão do Python 3 (nada de pip install).

Uso:
    python3 send.py <arquivo.json | diretório> [--dry-run] [--state ARQUIVO] [--verbose]

Códigos de saída:
    0  tudo certo (ou nada novo para enviar)
    1  alguma escrita falhou no InfluxDB
    2  erro de configuração/credenciais/entrada
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, NamedTuple, Optional, Tuple

# ---------------------------------------------------------------- constantes

SCRIPT_DIR = Path(__file__).resolve().parent
# o .credentials do harness; dá para apontar outro arquivo com --credentials ou
# com a variável de ambiente INFLUX_CREDENTIALS (útil para testes sem tocar no
# arquivo de quem usa o harness)
CREDENTIALS_PATH = Path(os.environ.get("INFLUX_CREDENTIALS") or (SCRIPT_DIR / ".credentials"))
DEFAULT_STATE_PATH = SCRIPT_DIR / ".sent-state.json"

REQUIRED_KEYS = ("INFLUX_URL", "INFLUX_TOKEN", "INFLUX_ORG", "INFLUX_MEASUREMENT")
DEFAULTS = {"INFLUX_BUCKET": "isacloud_ios", "INFLUX_TIMEOUT": "10"}

# tags que o harness publica em cada tipo de registro (o resto é field/tag do payload)
SAMPLE_TAGS = ("build", "ios", "model", "thermal", "low_power")
METRICKIT_TAGS = ("build", "kind")

# chaves da amostra que nunca viram field (timestamp e tags)
SAMPLE_SKIP_KEYS = frozenset(("ts",) + SAMPLE_TAGS)

BATCH_MAX_LINES = 500
BATCH_MAX_BYTES = 512 * 1024
STATE_VERSION = 1

_VERBOSE = False


# ------------------------------------------------------------------- erros


class HarnessError(Exception):
    """Erro fatal de configuração, credenciais ou entrada."""


class RecordError(Exception):
    """Registro individual inválido: é ignorado com aviso, sem abortar."""


# -------------------------------------------------------------------- saída


def info(message: str) -> None:
    """Mensagem normal (vai para stderr para não poluir o line protocol)."""
    print(message, file=sys.stderr)


def debug(message: str) -> None:
    """Detalhe só em --verbose."""
    if _VERBOSE:
        print(message, file=sys.stderr)


def warn(message: str) -> None:
    print(f"aviso: {message}", file=sys.stderr)


def fail(message: str) -> None:
    print(f"erro: {message}", file=sys.stderr)


def redact(text: str, token: str) -> str:
    """Remove o token de qualquer texto antes de imprimir."""
    if text and token:
        return text.replace(token, "***")
    return text


# --------------------------------------------------------------- credenciais


class Config(NamedTuple):
    url: str
    token: str
    org: str
    measurement: str
    bucket: str
    timeout: float


def load_config(path: Path = CREDENTIALS_PATH) -> Config:
    """Lê CHAVE=valor de .credentials e valida o que é obrigatório."""
    if not path.is_file():
        raise HarnessError(
            f"arquivo de credenciais não encontrado: {path}\n"
            "copie .credentials.example para .credentials e preencha os valores"
        )
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise HarnessError(f"não foi possível ler {path}: {exc}") from None

    values: Dict[str, str] = {}
    for number, raw_line in enumerate(raw_text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise HarnessError(f"{path.name}:{number}: linha inválida (esperado CHAVE=valor)")
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if not key:
            raise HarnessError(f"{path.name}:{number}: chave vazia")
        # aceita valores entre aspas simples ou duplas
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        values[key] = value

    missing = [key for key in REQUIRED_KEYS if not values.get(key)]
    if missing:
        raise HarnessError("variáveis obrigatórias ausentes em .credentials: " + ", ".join(missing))

    timeout_text = values.get("INFLUX_TIMEOUT") or DEFAULTS["INFLUX_TIMEOUT"]
    try:
        timeout = float(timeout_text)
    except ValueError:
        raise HarnessError(f"INFLUX_TIMEOUT inválido: {timeout_text!r}") from None
    if not math.isfinite(timeout) or timeout <= 0:
        raise HarnessError(f"INFLUX_TIMEOUT precisa ser positivo: {timeout_text!r}")

    return Config(
        url=values["INFLUX_URL"].rstrip("/"),
        token=values["INFLUX_TOKEN"],
        org=values["INFLUX_ORG"],
        measurement=values["INFLUX_MEASUREMENT"],
        bucket=values.get("INFLUX_BUCKET") or DEFAULTS["INFLUX_BUCKET"],
        timeout=timeout,
    )


# ------------------------------------------------------------ line protocol


def _escape(value: str, chars: Tuple[str, ...]) -> str:
    """Escapa barra invertida e os caracteres especiais informados."""
    text = str(value).replace("\\", "\\\\")
    for char in chars:
        text = text.replace(char, "\\" + char)
    return text


def escape_measurement(value: str) -> str:
    return _escape(value, (",", " "))


def escape_tag(value: str) -> str:
    return _escape(value, (",", "=", " "))


def escape_field_key(value: str) -> str:
    return _escape(value, (",", "=", " "))


def escape_string_field(value: str) -> str:
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def _tag_text(value: Any) -> str:
    """Converte um valor de tag para texto (bool -> true/false)."""
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value).replace("\r", " ").replace("\n", " ")
    return text.strip()


def format_field_value(value: Any) -> Optional[str]:
    """Formata um field em line protocol; devolve None se não for numérico/bool.

    Todo número sai como float (com ponto decimal). O tipo de um field é fixo no
    InfluxDB: se a mesma coluna fosse inteiro numa amostra (`cpu_ms=0` sem ponto)
    e float na seguinte (`cpu_ms=164.3`), o servidor recusaria o lote com
    "field type conflict". Por isso a conversão é sempre para float.
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        number = float(value)
        if not math.isfinite(number):
            raise RecordError("field numérico não finito (NaN/Inf)")
        text = repr(number)
        if "e" in text or "E" in text:
            # notação científica: o line protocol aceita, mas decimal é mais previsível
            text = format(number, ".17f").rstrip("0").rstrip(".")
        if "." not in text:
            text += ".0"
        return text
    return None


def render_line(
    measurement: str,
    tags: Dict[str, str],
    fields: Dict[str, Any],
    ts_ms: int,
) -> str:
    """Monta uma linha do line protocol (tags/fields ordenados para ser estável)."""
    head = [escape_measurement(measurement)]
    for key in sorted(tags):
        value = tags[key]
        if value is None or value == "":
            continue  # InfluxDB rejeita tag vazia
        head.append(f"{escape_tag(key)}={escape_tag(value)}")

    rendered_fields: List[str] = []
    for key in sorted(fields):
        rendered = format_field_value(fields[key])
        if rendered is None:
            continue
        rendered_fields.append(f"{escape_field_key(key)}={rendered}")
    if not rendered_fields:
        raise RecordError("nenhum field numérico/booleano para enviar")

    return f"{','.join(head)} {','.join(rendered_fields)} {int(ts_ms)}"


# ---------------------------------------------------------------- timestamps


def parse_time_ms(value: Any, context: str) -> int:
    """Converte ISO-8601 ou epoch em milissegundos desde 1970 (UTC)."""
    if isinstance(value, bool):
        raise RecordError(f"{context}: timestamp inválido")
    if isinstance(value, (int, float)):
        number = float(value)
        if not math.isfinite(number) or number <= 0:
            raise RecordError(f"{context}: timestamp numérico inválido")
        # heurística: >= 1e12 já está em ms; abaixo disso é epoch em segundos
        millis = number if number >= 1e12 else number * 1000.0
        return int(round(millis))
    if isinstance(value, str):
        text = value.strip()
        if not text:
            raise RecordError(f"{context}: timestamp vazio")
        if text.endswith(("Z", "z")):
            text = text[:-1] + "+00:00"
        try:
            parsed = datetime.fromisoformat(text)
        except ValueError:
            raise RecordError(f"{context}: timestamp ISO inválido: {value!r}") from None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return int(round(parsed.timestamp() * 1000))
    raise RecordError(f"{context}: timestamp ausente ou inválido")


# ----------------------------------------------------------------- registros


def make_record(
    kind: str,
    tags: Dict[str, str],
    fields: Dict[str, Any],
    ts_ms: int,
    source: str,
) -> Dict[str, Any]:
    return {
        "kind": kind,
        "tags": tags,
        "fields": fields,
        "ts_ms": ts_ms,
        "source": source,
        "note": None,
    }


def build_sample_record(sample: Any, source: str) -> Dict[str, Any]:
    """Normaliza uma amostra de `samples` (ou de uma linha .jsonl)."""
    if not isinstance(sample, dict):
        raise RecordError("amostra não é um objeto JSON")

    ts_ms = parse_time_ms(sample.get("ts"), f"{source}: campo 'ts'")

    tags: Dict[str, str] = {}
    for key in SAMPLE_TAGS:
        value = sample.get(key)
        if value is None or value == "" or isinstance(value, (dict, list)):
            continue
        tags[key] = _tag_text(value)

    fields: Dict[str, Any] = {}
    for key, value in sample.items():
        if key in SAMPLE_SKIP_KEYS:
            continue
        if isinstance(value, bool):
            fields[key] = value
        elif isinstance(value, (int, float)) and math.isfinite(float(value)):
            fields[key] = value
        # strings (short, last_appex_start) e nulos são ignorados de propósito

    if not fields:
        raise RecordError("amostra sem fields numéricos/booleanos")
    return make_record("sample", tags, fields, ts_ms, source)


def flatten_payload(payload: Any, counters: Dict[str, int], prefix: str = "") -> Dict[str, Any]:
    """Achata o payload MetricKit: dicts viram `a_b`, números/bools viram fields."""
    fields: Dict[str, Any] = {}
    if isinstance(payload, dict):
        for key, value in payload.items():
            child = f"{prefix}_{key}" if prefix else str(key)
            fields.update(flatten_payload(value, counters, child))
    elif isinstance(payload, list):
        counters["listas"] += 1  # listas são ignoradas de propósito (simplicidade)
    elif isinstance(payload, bool):
        if prefix:
            fields[prefix] = payload
    elif isinstance(payload, (int, float)):
        if prefix and math.isfinite(float(payload)):
            fields[prefix] = payload
    elif isinstance(payload, str):
        counters["strings"] += 1  # strings são ignoradas (evita explodir cardinalidade)
    else:
        counters["outros"] += 1
    return fields


def _first_non_empty(*values: Any) -> Optional[str]:
    for value in values:
        if value is None or value == "":
            continue
        return _tag_text(value)
    return None


def build_metrickit_record(
    item: Any,
    source: str,
    kind_hint: Optional[str] = None,
    fallback_ts_ms: Optional[int] = None,
) -> Dict[str, Any]:
    """Normaliza um payload MetricKit (do export ou de um metrickit-*.json)."""
    if not isinstance(item, dict):
        raise RecordError("payload MetricKit não é um objeto JSON")

    if isinstance(item.get("payload"), dict):
        # registro já no formato do export: {kind, receivedAt, build, payload}
        body = item["payload"]
        kind = _first_non_empty(item.get("kind"), kind_hint, "metric")
        build = _first_non_empty(item.get("build"))
        received = item.get("receivedAt")
    else:
        # dictionaryRepresentation cru do MetricKit
        body = item
        kind = _first_non_empty(item.get("kind"), kind_hint, "metric")
        build = _first_non_empty(item.get("build"), item.get("appVersion"))
        received = _first_non_empty(
            item.get("receivedAt"), item.get("receivedDate"), item.get("timestampEnd")
        )

    note = None
    if received is not None:
        ts_ms = parse_time_ms(received, f"{source}: receivedAt")
    elif fallback_ts_ms is not None:
        ts_ms = int(fallback_ts_ms)
        note = "sem receivedAt/receivedDate/timestampEnd; usando mtime do arquivo"
    else:
        raise RecordError("payload MetricKit sem receivedAt/receivedDate/timestampEnd")

    counters = {"strings": 0, "listas": 0, "outros": 0}
    fields = flatten_payload(body, counters)
    if not fields:
        raise RecordError("payload MetricKit sem fields numéricos/booleanos")

    tags: Dict[str, str] = {}
    if build:
        tags["build"] = build
    if kind:
        tags["kind"] = kind

    record = make_record("metrickit", tags, fields, ts_ms, source)
    if counters["strings"] or counters["listas"]:
        record["note"] = (
            f"{counters['strings']} string(s) e {counters['listas']} lista(s) ignoradas"
        )
    return record


def record_key(record: Dict[str, Any]) -> str:
    """Identificador estável do registro: tipo + build + ts + hash do conteúdo."""
    canonical = json.dumps(
        {
            "kind": record["kind"],
            "tags": record["tags"],
            "fields": record["fields"],
            "ts": record["ts_ms"],
        },
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    digest = hashlib.sha1(canonical.encode("utf-8")).hexdigest()[:16]
    build = record["tags"].get("build", "")
    return f"{record['kind']}|{build}|{record['ts_ms']}|{digest}"


# ------------------------------------------------------------------- entrada


def read_json(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise HarnessError(f"{path.name}: não foi possível ler: {exc}") from None
    if not text.strip():
        raise HarnessError(f"{path.name}: arquivo vazio")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise HarnessError(
            f"{path.name}: JSON inválido (linha {exc.lineno}, coluna {exc.colno}): {exc.msg}"
        ) from None


def kind_from_filename(name: str) -> str:
    """Deduz o `kind` de um metrickit-*.json pelo nome do arquivo."""
    lowered = name.lower()
    for candidate in ("diagnostic", "crash", "hang", "spin", "diskwrite"):
        if candidate in lowered:
            return candidate
    return "metric"


def iter_jsonl(path: Path) -> Iterator[Tuple[str, Any, str, None, None]]:
    """Lê samples-*.jsonl (um JSON por linha)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise HarnessError(f"{path.name}: não foi possível ler: {exc}") from None
    if not text.strip():
        raise HarnessError(f"{path.name}: arquivo vazio")
    for number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise HarnessError(
                f"{path.name}:{number}: JSON inválido ({exc.msg})"
            ) from None
        yield ("sample", item, f"{path.name}:{number}", None, None)


def iter_export(data: Dict[str, Any], name: str) -> Iterator[Tuple[str, Any, str, None, None]]:
    """Percorre o arquivo único exportado (samples + metrickit)."""
    samples = data.get("samples")
    if isinstance(samples, list):
        for index, item in enumerate(samples):
            yield ("sample", item, f"{name}:samples[{index}]", None, None)
    metrickit = data.get("metrickit")
    if isinstance(metrickit, list):
        for index, item in enumerate(metrickit):
            yield ("metrickit", item, f"{name}:metrickit[{index}]", None, None)


def iter_metrickit_file(path: Path) -> Iterator[Tuple[str, Any, str, Optional[str], int]]:
    """Lê um metrickit-*.json (dictionaryRepresentation cru)."""
    data = read_json(path)
    items = data if isinstance(data, list) else [data]
    kind_hint = kind_from_filename(path.name)
    try:
        fallback_ts = int(path.stat().st_mtime * 1000)
    except OSError:
        fallback_ts = None
    for index, item in enumerate(items):
        source = path.name if len(items) == 1 else f"{path.name}[{index}]"
        yield ("metrickit", item, source, kind_hint, fallback_ts)


def iter_file(path: Path) -> List[Tuple[str, Any, str, Optional[str], Optional[int]]]:
    """Lê um arquivo e devolve a lista de itens brutos tipados."""
    name = path.name
    if name.startswith("metrickit-") and name.endswith(".json"):
        return list(iter_metrickit_file(path))
    if name.endswith(".jsonl"):
        return list(iter_jsonl(path))

    data = read_json(path)
    if isinstance(data, dict) and ("samples" in data or "metrickit" in data):
        return list(iter_export(data, name))
    if isinstance(data, dict) and isinstance(data.get("payload"), dict):
        return [("metrickit", data, name, None, None)]
    if isinstance(data, dict) and "ts" in data:
        return [("sample", data, name, None, None)]
    if isinstance(data, list):
        if data and all(isinstance(item, dict) and "ts" in item for item in data):
            return [("sample", item, f"{name}[{i}]", None, None) for i, item in enumerate(data)]
        return [("metrickit", item, f"{name}[{i}]", None, None) for i, item in enumerate(data)]

    raise HarnessError(
        f"{name}: formato não reconhecido; use o JSON exportado pelo app "
        "ou um diretório com samples-*.jsonl e metrickit-*.json"
    )


def is_export_file(path: Path) -> bool:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return isinstance(data, dict) and ("samples" in data or "metrickit" in data)


def discover_directory(directory: Path) -> List[Tuple[str, Path]]:
    """Lista os arquivos brutos conhecidos do container do app."""
    found: List[Tuple[str, Path]] = []
    for entry in sorted(directory.iterdir(), key=lambda item: item.name):
        if not entry.is_file() or entry.name.startswith("."):
            continue
        name = entry.name
        if name.startswith("samples-") and name.endswith(".jsonl"):
            found.append(("samples-*.jsonl", entry))
        elif name.startswith("metrickit-") and name.endswith(".json"):
            found.append(("metrickit-*.json", entry))
        elif name.endswith(".json") and is_export_file(entry):
            found.append(("export", entry))  # export completo guardado no diretório
    return found


def collect_input(path: Path) -> List[Tuple[str, Any, str, Optional[str], Optional[int]]]:
    """Lê a entrada inteira (arquivo único ou diretório) antes de enviar."""
    if path.is_dir():
        files = discover_directory(path)
        if not files:
            raise HarnessError(
                f"nenhum arquivo reconhecido em {path} "
                "(esperado samples-*.jsonl, metrickit-*.json ou um JSON exportado)"
            )
        items: List[Tuple[str, Any, str, Optional[str], Optional[int]]] = []
        for kind, file_path in files:
            debug(f"lendo {file_path.name} ({kind})")
            items.extend(iter_file(file_path))
        return items
    if not path.exists():
        raise HarnessError(f"entrada não encontrada: {path}")
    return iter_file(path)


# -------------------------------------------------------------------- estado


def load_state(path: Path) -> Dict[str, str]:
    """Lê o estado de idempotência (chaves já enviadas)."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HarnessError(
            f"estado ilegível em {path}: {exc}\napague o arquivo para recomeçar do zero"
        ) from None
    sent = data.get("sent") if isinstance(data, dict) else None
    if not isinstance(sent, dict):
        raise HarnessError(f"estado inválido em {path} (esperado {{\"sent\": {{...}}}})")
    return {str(key): str(value) for key, value in sent.items()}


def save_state(path: Path, sent: Dict[str, str]) -> None:
    """Grava o estado de forma atômica (tmp + rename)."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + ".tmp")
        payload = json.dumps(
            {"version": STATE_VERSION, "sent": dict(sorted(sent.items()))},
            indent=2,
            ensure_ascii=False,
        )
        temporary.write_text(payload + "\n", encoding="utf-8")
        os.replace(temporary, path)
    except OSError as exc:
        raise HarnessError(f"não foi possível gravar o estado em {path}: {exc}") from None


# --------------------------------------------------------------------- HTTP


def build_endpoint(config: Config) -> str:
    query = urllib.parse.urlencode(
        {"org": config.org, "bucket": config.bucket, "precision": "ms"}
    )
    return f"{config.url}/api/v2/write?{query}"


def post_write(
    endpoint: str, token: str, body: str, timeout: float
) -> Tuple[Optional[int], str]:
    """POST do line protocol; devolve (status, corpo) ou (None, erro de rede)."""
    request = urllib.request.Request(
        endpoint,
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Token {token}",
            "Content-Type": "text/plain; charset=utf-8",
            "User-Agent": "isaCloud-metrics-harness/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace").strip()
    except urllib.error.HTTPError as exc:
        try:
            payload = exc.read().decode("utf-8", "replace")
        except Exception:  # pragma: no cover - leitura defensiva
            payload = ""
        return exc.code, payload.strip()[:500]
    except urllib.error.URLError as exc:
        return None, f"falha de conexão: {exc.reason}"
    except TimeoutError:
        return None, "timeout ao conectar no InfluxDB"
    except OSError as exc:
        return None, f"erro de rede: {exc}"


def chunk_entries(
    entries: List[Tuple[str, str]],
    max_lines: int = BATCH_MAX_LINES,
    max_bytes: int = BATCH_MAX_BYTES,
) -> Iterator[List[Tuple[str, str]]]:
    """Agrupa (chave, linha) em lotes por quantidade e por tamanho."""
    batch: List[Tuple[str, str]] = []
    size = 0
    for entry in entries:
        line_size = len(entry[1].encode("utf-8")) + 1
        if batch and (len(batch) >= max_lines or size + line_size > max_bytes):
            yield batch
            batch, size = [], 0
        batch.append(entry)
        size += line_size
    if batch:
        yield batch


# --------------------------------------------------------------------- main


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Envia as métricas do isaCloud para o InfluxDB 2.x "
            "(line protocol via /api/v2/write)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "input",
        metavar="<arquivo.json|diretório>",
        help="JSON exportado pelo app ou diretório com os arquivos brutos",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="imprime o line protocol no stdout sem enviar e sem gravar estado",
    )
    parser.add_argument(
        "--state",
        metavar="ARQUIVO",
        default=None,
        help="estado de idempotência (padrão: .sent-state.json no diretório do harness)",
    )
    parser.add_argument(
        "--credentials",
        metavar="ARQUIVO",
        default=None,
        help="arquivo de credenciais (padrão: .credentials no diretório do harness, ou INFLUX_CREDENTIALS)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="mostra detalhes de leitura e envio no stderr",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    global _VERBOSE

    args = parse_args(argv)
    _VERBOSE = args.verbose
    state_path = Path(args.state) if args.state else DEFAULT_STATE_PATH

    try:
        config = load_config(Path(args.credentials) if args.credentials else CREDENTIALS_PATH)
    except HarnessError as exc:
        fail(str(exc))
        return 2

    try:
        raw_items = collect_input(Path(args.input))
    except HarnessError as exc:
        fail(str(exc))
        return 2

    # normaliza cada item; um item ruim não derruba o lote inteiro
    records: List[Dict[str, Any]] = []
    skipped_invalid = 0
    for kind, item, source, kind_hint, fallback_ts in raw_items:
        try:
            if kind == "sample":
                record = build_sample_record(item, source)
            else:
                record = build_metrickit_record(
                    item, source, kind_hint=kind_hint, fallback_ts_ms=fallback_ts
                )
        except RecordError as exc:
            warn(f"{source}: {exc} (registro ignorado)")
            skipped_invalid += 1
            continue
        if record["note"]:
            debug(f"{source}: {record['note']}")
        records.append(record)

    samples = sum(1 for record in records if record["kind"] == "sample")
    metrickit = len(records) - samples
    debug(f"{len(records)} registro(s) válido(s): {samples} amostra(s), {metrickit} MetricKit")

    # estado de idempotência (dry-run não lê nem grava)
    state: Dict[str, str] = {}
    if not args.dry_run:
        try:
            state = load_state(state_path)
        except HarnessError as exc:
            fail(str(exc))
            return 2
        debug(f"estado: {state_path} ({len(state)} chave(s))")

    seen: set = set()
    already_sent = 0
    entries: List[Tuple[str, str]] = []
    skipped_invalid_after_state = 0
    for record in records:
        key = record_key(record)
        if key in seen or key in state:
            already_sent += 1
            continue
        seen.add(key)

        measurement = config.measurement
        if record["kind"] == "metrickit":
            measurement = f"{config.measurement}_metrickit"
        try:
            line = render_line(measurement, record["tags"], record["fields"], record["ts_ms"])
        except RecordError as exc:
            warn(f"{record['source']}: {exc} (registro ignorado)")
            skipped_invalid_after_state += 1
            continue
        entries.append((key, line))

    ignored = skipped_invalid + skipped_invalid_after_state

    if args.dry_run:
        for _, line in entries:
            print(line)
        info(
            f"resumo (dry-run): {samples} amostra(s), {metrickit} MetricKit, "
            f"{len(entries)} linha(s) impressas, {ignored} ignorada(s)"
        )
        return 0

    if not entries:
        info(
            f"resumo: nada novo para enviar ({samples} amostra(s), {metrickit} MetricKit, "
            f"{already_sent} já no estado, {ignored} ignorada(s))"
        )
        return 0

    endpoint = build_endpoint(config)
    debug(f"endpoint: {endpoint}")
    failures = 0
    sent = 0
    dirty = False

    for batch in chunk_entries(entries):
        body = "".join(line + "\n" for _, line in batch)
        debug(f"enviando {len(batch)} linha(s) ({len(body.encode('utf-8'))} bytes)")
        status, message = post_write(endpoint, config.token, body, config.timeout)
        message = redact(message, config.token)

        if status is not None and 200 <= status < 300:
            sent += len(batch)
            stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            for key, _ in batch:
                state[key] = stamp
            dirty = True
            debug(f"HTTP {status} OK ({len(batch)} linha(s))")
            continue

        failures += 1
        if status is None:
            fail(f"envio interrompido: {message}")
            break  # sem rede não adianta insistir nos próximos lotes
        fail(f"InfluxDB respondeu HTTP {status}: {message or '(corpo vazio)'}")
        if status in (401, 403):
            fail("credenciais sem permissão de escrita nesse bucket; interrompendo")
            break

    if dirty:
        try:
            save_state(state_path, state)
            debug(f"estado atualizado: {state_path}")
        except HarnessError as exc:
            fail(str(exc))
            failures += 1

    info(
        f"resumo: {samples} amostra(s), {metrickit} MetricKit, "
        f"{already_sent} já no estado, {sent} enviada(s), "
        f"{failures} falha(s), {ignored} ignorada(s)"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

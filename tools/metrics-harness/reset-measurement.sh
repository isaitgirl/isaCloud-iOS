#!/bin/bash
#
# isaCloud — apaga os pontos de uma measurement do InfluxDB 2.x.
#
# Usado quando o schema de fields muda (o InfluxDB fixa o tipo de cada field na
# primeira escrita e não aceita mudar depois: "field type conflict"). As
# credenciais vêm do .credentials do harness, o mesmo arquivo usado pelo send.py.
#
# Uso:
#   ./reset-measurement.sh                 # apaga a measurement do .credentials
#   ./reset-measurement.sh outra_measurement
#   ./reset-measurement.sh --dry-run       # só mostra o que faria (sem token)
#   ./reset-measurement.sh --keep-state    # não mexe no .sent-state.json
#   ./reset-measurement.sh --credentials /tmp/teste.credentials  # outro arquivo
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
credentials="${INFLUX_CREDENTIALS:-$here/.credentials}"
dry_run=0
keep_state=0
measurement=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --keep-state) keep_state=1 ;;
        --credentials) read_next_credentials=1 ;;
        --credentials=*) credentials="${arg#--credentials=}" ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            if [[ "${read_next_credentials:-0}" -eq 1 ]]; then
                credentials="$arg"; read_next_credentials=0
            else
                measurement="$arg"
            fi
            ;;
    esac
done

if [[ ! -f "$credentials" ]]; then
    echo "erro: $credentials não existe. Copie .credentials.example e preencha." >&2
    exit 2
fi

# shellcheck disable=SC1090
set -a; . "$credentials"; set +a

: "${INFLUX_URL:?falta INFLUX_URL no .credentials}"
: "${INFLUX_TOKEN:?falta INFLUX_TOKEN no .credentials}"
: "${INFLUX_ORG:?falta INFLUX_ORG no .credentials}"
bucket="${INFLUX_BUCKET:-isacloud}"
measurement="${measurement:-${INFLUX_MEASUREMENT:-isacloud_metrics}}"

command=(influx delete
    --host "$INFLUX_URL"
    --token "$INFLUX_TOKEN"
    --org "$INFLUX_ORG"
    --bucket "$bucket"
    --start 1970-01-01T00:00:00Z
    --stop "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    --predicate "_measurement=\"$measurement\"")

if [[ "$dry_run" -eq 1 ]]; then
    echo "medindo: $measurement (bucket $bucket, org $INFLUX_ORG, host $INFLUX_URL)"
    printf '%q ' "${command[@]}" | sed 's/--token [^ ]*/--token ***/'
    echo
    exit 0
fi

echo "apagando os pontos de '$measurement' no bucket '$bucket' (org $INFLUX_ORG)..."
"${command[@]}"
echo "pronto."

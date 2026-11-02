#!/usr/bin/env python3
"""Classifica os relatórios de crash (.ips) do isaCloud e da extensão de notificação.

Uso:
  python3 scripts/classificar-crashes.py --dir PASTA [--since AAAA-MM-DD] [--details]
  python3 scripts/classificar-crashes.py --pull [UDID] [--dir PASTA] [--since AAAA-MM-DD]

Lê os arquivos isaCloud*.ips e NotificationService*.ips (inclusive na subpasta
Retired/) e mostra:
- uma linha por relatório, em ordem de data;
- uma tabela por dia, com a contagem por tipo;
- para os 0xdead10cc, a contagem por mecanismo (o que a thread fazia quando o iOS
  matou o app por segurar o banco de dados);
- totais por build, para comparar as versões.

Tipos: 0xdead10cc (watchdog do banco), 0x8badf00d (watchdog de inicialização ou de
fundo), abort (SIGABRT/SIGTRAP; mostra o primeiro símbolo do app) e outro.

--pull copia os relatórios do iPhone (xcrun devicectl) antes de ler. O UDID não
fica neste arquivo: vem do argumento de --pull ou da variável de ambiente
ISACLOUD_IPHONE_UDID, quando --pull é usado sem valor.

--details imprime, para cada relatório, a pilha resumida das threads que levaram
à classificação.
"""

import argparse
import datetime
import json
import os
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict

DEAD_10CC_CODE = 3735883980
BADF00D_CODE = 2343432205
ABORT_SIGNALS = ('SIGABRT', 'SIGTRAP')
FILE_PREFIXES = ('isaCloud', 'NotificationService')
APP_IMAGE_KEYWORDS = ('monalxmpp', 'isacloud', 'notificationservice')
MAX_FRAMES = 60
DETAIL_FRAMES = 12
TYPES = ['0xdead10cc', '0x8badf00d', 'abort', 'outro']
DEAD_10CC = '0xdead10cc'


def parse_date(value):
    try:
        datetime.datetime.strptime(value, '%Y-%m-%d')
    except ValueError as error:
        raise argparse.ArgumentTypeError('use o formato AAAA-MM-DD') from error
    return value


def parse_args(argv):
    parser = argparse.ArgumentParser(description='Classifica crashes .ips do isaCloud.')
    parser.add_argument('--dir', metavar='PASTA', help='pasta com os .ips (busca recursiva)')
    parser.add_argument('--pull', metavar='UDID', nargs='?', const='', default=None,
                        help='copia os relatórios do iPhone antes de ler (sem valor: usa ISACLOUD_IPHONE_UDID)')
    parser.add_argument('--since', metavar='AAAA-MM-DD', type=parse_date,
                        help='ignora relatórios anteriores a esta data')
    parser.add_argument('--details', action='store_true',
                        help='mostra a pilha resumida das threads de cada relatório')
    return parser.parse_args(argv)


def resolve_udid(value):
    udid = value or os.environ.get('ISACLOUD_IPHONE_UDID', '')
    if not udid:
        sys.exit('erro: informe o UDID em --pull UDID ou na variável ISACLOUD_IPHONE_UDID')
    return udid


def pull_crash_logs(udid, folder):
    command = ['xcrun', 'devicectl', 'device', 'copy', 'from',
               '--device', udid, '--domain-type', 'systemCrashLogs',
               '--source', '/', '--destination', folder]
    print(f'Copiando relatórios do iPhone para {folder}')
    result = subprocess.run(command, check=False)
    if result.returncode != 0:
        sys.exit(f'erro: devicectl terminou com código {result.returncode}')


def read_ips(path):
    """Return (header, body) of an .ips file; raise ValueError if malformed."""
    with open(path, encoding='utf-8', errors='replace') as file:
        text = file.read()
    parts = text.split('\n', 1)
    if len(parts) != 2:
        raise ValueError('arquivo sem a segunda parte JSON')
    try:
        header = json.loads(parts[0])
        body = json.loads(parts[1])
    except json.JSONDecodeError as error:
        raise ValueError(f'JSON inválido: {error}') from error
    if not isinstance(header, dict) or not isinstance(body, dict):
        raise ValueError('JSON que não é objeto')
    return header, body


def image_name(frame, images):
    index = frame.get('imageIndex')
    if isinstance(index, int) and 0 <= index < len(images):
        return images[index].get('name', '')
    return ''


def frame_symbol(frame, images):
    if frame.get('symbol'):
        return frame['symbol']
    return f"{image_name(frame, images)}+{frame.get('imageOffset', 0)}"


def thread_stack(thread, images):
    frames = thread.get('frames') or []
    symbols = [frame_symbol(frame, images) for frame in frames[:MAX_FRAMES]]
    return {
        'frames': frames,
        'symbols': symbols,
        'text': ' <- '.join(symbols),
        'top': symbols[0] if symbols else '',
        'triggered': bool(thread.get('triggered')),
    }


# Mechanism rules for 0xdead10cc. Each returns the indexes of the matching threads.
def _has(stack, *needles):
    return all(needle in stack['text'] for needle in needles)


def _has_any(stack, *needles):
    return any(needle in stack['text'] for needle in needles)


def _where(stacks, predicate):
    return [index for index, stack in enumerate(stacks) if predicate(stack)]


def rule_log_sincrono(stacks):
    return _where(stacks, lambda s: _has(s, 'queueLogMessage:asynchronously:')
                  and _has_any(s, 'kevent_id', '_dispatch_sync_f_slow', '__DISPATCH_WAIT_FOR_QUEUE__')
                  and _has_any(s, 'WriteTransaction', 'createTransaction'))


def rule_disconnect_rede(stacks):
    hits = _where(stacks, lambda s: _has(s, 'disconnectWithStreamError', 'voidWriteTransaction'))
    if not hits:
        return []
    if any(_has(s, 'MLOutputStream write:maxLength:') for s in stacks):
        return hits
    # No output-stream write thread in the report: accept the thread parked on psynch.
    return [index for index in hits if '__psynch_cvwait' in stacks[index]['top']]


def rule_filetransfer(stacks):
    return _where(stacks, lambda s: _has(s, 'MLFiletransfer', 'voidWriteTransaction'))


def rule_persist_state(stacks):
    return _where(stacks, lambda s: _has(s, 'voidWriteTransaction')
                  and _has_any(s, 'realPersistState', 'serializeObject'))


def rule_parse_na_transacao(stacks):
    return _where(stacks, lambda s: _has(s, 'processInput:withDelayedReplay:', 'voidWriteTransaction'))


def _exit_symbol(symbol):
    return symbol in ('exit', '_exit') or '__cxa_finalize' in symbol or 'killAppex' in symbol


def rule_extensao_exit(stacks):
    return _where(stacks, lambda s: any(_exit_symbol(sym) for sym in s['symbols']))


MECHANISM_RULES = [
    ('log-sincrono', rule_log_sincrono),
    ('disconnect-rede', rule_disconnect_rede),
    # persistState before filetransfer: a filetransfer thread often only waits in beginWriteTransaction while the parser
    # holds the lock serializing the state (02/11/2026 11:02)
    ('persistState', rule_persist_state),
    ('filetransfer', rule_filetransfer),
    ('parse-na-transacao', rule_parse_na_transacao),
    ('extensao-exit', rule_extensao_exit),
]
MECHANISMS = [name for name, _ in MECHANISM_RULES] + ['sem-banco']


def dead_mechanism(stacks, process, fallback):
    for name, rule in MECHANISM_RULES:
        if name == 'extensao-exit' and process != 'extensao':
            continue
        hits = rule(stacks)
        if hits:
            return name, hits
    return 'sem-banco', fallback


def triggered_threads(body, stacks):
    for index, stack in enumerate(stacks):
        if stack['triggered']:
            return [index]
    faulting = body.get('faultingThread')
    if isinstance(faulting, int) and 0 <= faulting < len(stacks):
        return [faulting]
    return [0] if stacks else []


def abort_symbol(body, stacks, images, fallback):
    frames = body.get('lastExceptionBacktrace') or []
    if not frames and fallback:
        frames = stacks[fallback[0]]['frames']
    for frame in frames:
        if any(key in image_name(frame, images).lower() for key in APP_IMAGE_KEYWORDS):
            return frame_symbol(frame, images)
    return '(sem símbolo do app)'


def classify(body, process, stacks, images):
    """Return (type, detail, relevant thread indexes)."""
    termination = body.get('termination') or {}
    exception = body.get('exception') or {}
    fallback = triggered_threads(body, stacks)
    code = termination.get('code')
    if code == DEAD_10CC_CODE:
        mechanism, threads = dead_mechanism(stacks, process, fallback)
        return DEAD_10CC, mechanism, threads
    if code == BADF00D_CODE:
        return '0x8badf00d', '-', fallback
    if exception.get('signal') in ABORT_SIGNALS:
        return 'abort', abort_symbol(body, stacks, images, fallback), fallback
    return 'outro', '-', fallback


def make_report(name, header, body):
    images = body.get('usedImages') or []
    stacks = [thread_stack(thread, images) for thread in body.get('threads') or []]
    process = 'app' if name.startswith('isaCloud') else 'extensao'
    kind, detail, threads = classify(body, process, stacks, images)
    timestamp = str(header.get('timestamp') or body.get('captureTime') or '')
    return {
        'name': name,
        'process': process,
        'build': str(header.get('build_version', '?')),
        'timestamp': timestamp,
        'date': timestamp[:10],
        'type': kind,
        'detail': detail,
        'threads': threads,
        'stacks': stacks,
    }


def find_reports(folder, since):
    reports = []
    for root, _dirs, files in os.walk(folder):
        for name in files:
            if not name.endswith('.ips') or not name.startswith(FILE_PREFIXES):
                continue
            try:
                header, body = read_ips(os.path.join(root, name))
            except (OSError, ValueError) as error:
                print(f'aviso: ignorado {name}: {error}', file=sys.stderr)
                continue
            report = make_report(name, header, body)
            if since and report['date'] < since:
                continue
            reports.append(report)
    reports.sort(key=lambda report: report['timestamp'])
    return reports


def format_line(report):
    detail = report['detail'] if report['type'] in (DEAD_10CC, 'abort') else '-'
    return (f"{report['timestamp'][:16]} | {report['process']} | build {report['build']} | "
            f"{report['type']} | {detail}")


def print_details(report):
    for index in report['threads']:
        stack = report['stacks'][index]
        marker = ' (disparada)' if stack['triggered'] else ''
        print(f'    thread {index}{marker}:')
        for symbol in stack['symbols'][:DETAIL_FRAMES]:
            print(f'      {symbol}')


def render_table(headers, rows):
    table = [headers] + rows
    widths = [max(len(str(row[column])) for row in table) for column in range(len(headers))]
    return '\n'.join('  '.join(str(cell).ljust(width) for cell, width in zip(row, widths))
                     for row in table)


def group_by(reports, key):
    groups = defaultdict(list)
    for report in reports:
        groups[key(report)].append(report)
    return groups


def day_table(reports):
    rows = []
    for day, group in sorted(group_by(reports, lambda r: r['date']).items()):
        counts = Counter(report['type'] for report in group)
        rows.append([day, len(group)] + [counts[kind] for kind in TYPES])
    return render_table(['data', 'total'] + TYPES, rows)


def mechanism_table(reports):
    rows = []
    for day, group in sorted(group_by(reports, lambda r: r['date']).items()):
        dead = [report['detail'] for report in group if report['type'] == DEAD_10CC]
        if dead:
            counts = Counter(dead)
            rows.append([day, len(dead)] + [counts[name] for name in MECHANISMS])
    if not rows:
        return '(nenhum 0xdead10cc)'
    return render_table(['data', 'total'] + MECHANISMS, rows)


def build_sort_key(build):
    return (0, int(build), '') if build.isdigit() else (1, 0, build)


def build_table(reports):
    rows = []
    groups = group_by(reports, lambda r: r['build'])
    for build in sorted(groups, key=build_sort_key):
        group = groups[build]
        counts = Counter(report['type'] for report in group)
        rows.append([build, len(group)] + [counts[kind] for kind in TYPES])
    return render_table(['build', 'total'] + TYPES, rows)


def print_report(reports, details):
    if not reports:
        print('Nenhum relatório do isaCloud ou da extensão encontrado.')
        return
    print(f'Relatórios: {len(reports)}')
    print('(no abort, a última coluna é o primeiro símbolo do app; no 0xdead10cc, o mecanismo)\n')
    for report in reports:
        print(format_line(report))
        if details:
            print_details(report)
    print('\n== Por dia: tipo ==')
    print(day_table(reports))
    print('\n== 0xdead10cc por mecanismo ==')
    print(mechanism_table(reports))
    print('\n== Totais por build ==')
    print(build_table(reports))


def main(argv=None):
    args = parse_args(argv)
    folder = args.dir
    if args.pull is not None:
        udid = resolve_udid(args.pull)
        folder = folder or tempfile.mkdtemp(prefix='crashes-isacloud-')
        os.makedirs(folder, exist_ok=True)
        pull_crash_logs(udid, folder)
    if not folder:
        sys.exit('erro: informe --dir PASTA ou --pull')
    if not os.path.isdir(folder):
        sys.exit(f'erro: pasta não encontrada: {folder}')
    print_report(find_reports(folder, args.since), args.details)


if __name__ == '__main__':
    main()

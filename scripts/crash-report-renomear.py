#!/usr/bin/env python3
"""Dá nome legível aos relatórios de crash recebidos em reports@ e, se pedido, separa as partes.

O servidor de upload troca o nome do arquivo por um hash (ex.: zb2rh...uS.gz), então o nome amigável é feito aqui, a partir do
conteúdo: build, data e hora do crash (sempre em UTC, com Z) e o sinal. Exemplo: ios-b117-20261117-1447Z-sigtrap.mcrash.gz

uso:
  scripts/crash-report-renomear.py [pasta]               renomeia os que ainda não têm nome legível
  scripts/crash-report-renomear.py --dry-run [pasta]     só mostra o que faria
  scripts/crash-report-renomear.py --extrair arquivo.gz  separa as partes (aux.txt, apple.crash, relatorio.json, log.rawlog, perfil.profraw)

A pasta padrão é ~/Nextcloud/Projetos/isacloud/crash-reports/ios. O relatório pode conter mensagens e contatos (o log do app):
trate como dado pessoal e apague em até 30 dias (docs/analise-relatorio-de-crash.md, seção 4).
"""
import gzip
import os
import re
import sys
from datetime import datetime, timezone

PASTA_PADRAO = os.path.expanduser("~/Nextcloud/Projetos/isacloud/crash-reports/ios")
SEPARADOR = re.compile(r"\n*-------- d049d576-9bf0-47dd-839f-dee6b07c1df9 -------- (.*?) -------- d049d576-9bf0-47dd-839f-dee6b07c1df9 --------\n*")
NOMES_DAS_PARTES = {
    "AUX Info (*.txt)": "aux.txt",
    "Apple Report (*.crash)": "apple.crash",
    "JSON Report (*.json)": "relatorio.json",
    "Logfile (*.rawlog.gz)": "log.rawlog",
    "Profile (*.profraw)": "perfil.profraw",
}


def ler_partes(caminho):
    with gzip.open(caminho, "rb") as f:
        texto = f.read().decode("utf-8", errors="replace")
    pedacos = SEPARADOR.split(texto)
    # pedacos: [antes, titulo1, corpo1, titulo2, corpo2, ...]
    return {pedacos[i]: pedacos[i + 1] for i in range(1, len(pedacos) - 1, 2)}


def nome_legivel(caminho):
    partes = ler_partes(caminho)
    aux = partes.get("AUX Info (*.txt)", "")
    apple = partes.get("Apple Report (*.crash)", "")
    build = re.search(r"reporterVersion:.*\((\d+)\)", aux)
    data = re.search(r"Date/Time:\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\S* ([+-]\d{4})", apple)
    sinal = re.search(r"Exception Type:\s+\S+ \((\w+)\)", apple)
    if not (build and data):
        return None
    momento = datetime.strptime(data.group(1) + " " + data.group(2), "%Y-%m-%d %H:%M:%S %z").astimezone(timezone.utc)
    return "ios-b%s-%sZ-%s.mcrash.gz" % (
        build.group(1), momento.strftime("%Y%m%d-%H%M"), sinal.group(1).lower() if sinal else "crash")


def extrair(caminho):
    destino = re.sub(r"(\.mcrash)?\.gz$", "", caminho) + "-partes"
    os.mkdir(destino)  # falha se já existir: nunca sobrescreve
    for titulo, corpo in ler_partes(caminho).items():
        nome = NOMES_DAS_PARTES.get(titulo, re.sub(r"\W+", "-", titulo))
        if nome == "log.rawlog":
            # o log vem em hexadecimal: volta para os bytes originais
            corpo = bytes.fromhex(re.sub(r"\s+", "", corpo)) if corpo.strip() else b""
            modo = "wb"
        else:
            modo = "w"
        with open(os.path.join(destino, nome), modo, **({} if modo == "wb" else {"encoding": "utf-8"})) as f:
            f.write(corpo)
    print("partes em", destino)


def main(argumentos):
    dry = "--dry-run" in argumentos
    if "--extrair" in argumentos:
        extrair(argumentos[argumentos.index("--extrair") + 1])
        return 0
    restantes = [a for a in argumentos if not a.startswith("--")]
    pasta = restantes[0] if restantes else PASTA_PADRAO
    for nome in sorted(os.listdir(pasta)):
        if nome.startswith("ios-b") or nome.startswith(".") or not nome.endswith(".gz"):
            continue
        origem = os.path.join(pasta, nome)
        try:
            novo = nome_legivel(origem)
        except (OSError, EOFError, gzip.BadGzipFile) as erro:
            print("pulado (não abriu): %s (%s)" % (nome, erro))
            continue
        if novo is None:
            print("pulado (sem build ou data): %s" % nome)
            continue
        destino = os.path.join(pasta, novo)
        if os.path.exists(destino):
            print("pulado (já existe %s): %s" % (novo, nome))
            continue
        print("%s -> %s" % (nome, novo))
        if not dry:
            os.rename(origem, destino)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""tests/fuzz_pe.py — fuzz mínimo do PE loader do Dexter (R-5.4 Fase 4).

O quê: muta bytes de um PE x64 válido e roda dexter sobre cada mutante.
Por quê: dexter nunca deve crashar com input corrompido — só saídas
  documentadas (0 ok, 1 uso, 2 I/O, 3 PE inválido, 5 rebuild).
  Crash = returncode fora de {0,1,2,3,5} (ex: -1073741819 = 0xC0000005),
  timeout (hang) ou exceção do runner.
Como testar: python tests/fuzz_pe.py --cases 20 --seed 7  (rápido, suíte)
  python tests/fuzz_pe.py --cases 200 --seed 42  (bateria manual maior)
Segurança: o MUTANTE nunca é executado (só lido pelo dexter, como dado).
Determinismo: seed fixo -> mesmos mutantes, mesmos bytes, mesma ordem.
"""

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

OK_CODES = {0, 1, 2, 3, 5}  # 4 = reservado (fallback db, nunca sai 4)


def mutate(data, rng):
    """Retorna (bytes_mutados, descrição). Operadores determinísticos."""
    op = rng.randrange(8)
    d = bytearray(data)
    n = len(d)
    if op == 0:  # flips aleatórios (1-8 bytes)
        k = rng.randrange(1, 9)
        for _ in range(k):
            d[rng.randrange(n)] = rng.randrange(256)
        return bytes(d), "randflip(%d)" % k
    if op == 1:  # MZ inválido
        d[0:2] = b"ZZ"
        return bytes(d), "bad-mz"
    if op == 2:  # e_lfanew absurdo
        d[0x3C:0x40] = rng.choice([b"\x00\x00\x00\x00", b"\xFF\xFF\xFF\x7F",
                                   b"\x00\x10\x00\x00"])
        return bytes(d), "bad-lfanew"
    if op == 3:  # assinatura PE / Machine
        pos = int.from_bytes(d[0x3C:0x40], "little")
        if 0 <= pos + 6 <= n:
            d[pos:pos + 4] = b"XX\0\0"
            if rng.random() < 0.5 and pos + 6 <= n:
                d[pos + 4:pos + 6] = b"\x4C\x01"  # i386 fora de escopo
        return bytes(d), "bad-sig-machine"
    if op == 4:  # NumberOfSections / SizeOfImage absurdos
        pos = int.from_bytes(d[0x3C:0x40], "little")
        if 0 <= pos + 60 <= n:
            d[pos + 6:pos + 8] = b"\xFF\xFF"
            # SizeOfOptionalHeader+... SizeOfImage fica em opt+56
            d[pos + 24 + 56:pos + 24 + 60] = b"\xFF\xFF\xFF\xFF"
        return bytes(d), "bad-sections-sizeimage"
    if op == 5:  # DataDirectory de imports zerada/lixo
        pos = int.from_bytes(d[0x3C:0x40], "little")
        dd = pos + 24 + 96 + 8  # 2º diretório (imports): RVA
        if 0 <= dd + 8 <= n:
            d[dd:dd + 8] = rng.choice([b"\x00" * 8, b"\xFF" * 8])
        return bytes(d), "bad-importdir"
    if op == 6:  # truncamento (corta fim do arquivo)
        cut = rng.randrange(64, n)
        return bytes(d[:cut]), "trunc(%d)" % cut
    # op == 7: bloco zerado em offset aleatório (16-64 bytes)
    k = rng.randrange(16, 65)
    off = rng.randrange(max(1, n - k))
    d[off:off + k] = b"\x00" * k
    return bytes(d), "zero-block(%d@%d)" % (k, off)


def main():
    ap = argparse.ArgumentParser(description="fuzz mínimo do dexter (só 0-3/5, nunca crash)")
    ap.add_argument("--dexter", default="out\\dexter.exe")
    ap.add_argument("--input", default="tests\\hello.exe")
    ap.add_argument("--cases", type=int, default=20)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--keep", action="store_true",
                    help="mantém mutantes (default: só crashers em tests\\out\\fuzz)")
    args = ap.parse_args()

    with open(args.input, "rb") as f:
        orig = f.read()
    rng = random.Random(args.seed)
    tmpdir = tempfile.mkdtemp(prefix="dexfuzz_")
    crashdir = os.path.join("tests", "out", "fuzz")
    os.makedirs(crashdir, exist_ok=True)
    # limpa crashers de rodada anterior (repro atual, sem acumular lixo)
    for fn in os.listdir(crashdir):
        if fn.startswith("crash_"):
            os.remove(os.path.join(crashdir, fn))

    bad = 0
    for i in range(args.cases):
        blob, desc = mutate(orig, rng)
        path = os.path.join(tmpdir, "m%03d.exe" % i)
        with open(path, "wb") as f:
            f.write(blob)
        try:
            p = subprocess.run([args.dexter, path, "-o", "NUL", "-q"],
                               capture_output=True, timeout=args.timeout)
            code = p.returncode
        except subprocess.TimeoutExpired:
            code = "TIMEOUT"
        if code not in OK_CODES:
            bad += 1
            dst = os.path.join(crashdir, "crash_%03d.exe" % i)
            shutil.copy(path, dst)
            print("CRASH case=%d op=%s code=%s size=%d -> %s"
                  % (i, desc, code, len(blob), dst))
        if not args.keep:
            try:
                os.remove(path)
            except OSError:
                pass
    try:
        os.rmdir(tmpdir)
    except OSError:
        pass
    ok = args.cases - bad
    print("fuzz: %d/%d ok, crashes=%d (seed=%d)"
          % (ok, args.cases, bad, args.seed))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

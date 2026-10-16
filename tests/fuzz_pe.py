#!/usr/bin/env python3
"""tests/fuzz_pe.py — fuzz mínimo do PE loader do Dexter (R-5.4 Fase 4).

O quê: muta bytes de um PE x64 válido e roda dexter sobre cada mutante.
Por quê: dexter nunca deve crashar com input corrompido — só saídas
  documentadas (0 ok, 1 uso, 2 I/O, 3 PE inválido, 5 rebuild).
  Crash = returncode fora de {0,1,2,3,5} (ex: -1073741819 = 0xC0000005),
  timeout (hang) ou exceção do runner.
Como testar: python tests/fuzz_pe.py --cases 20 --seed 7  (rápido, suíte)
  python tests/fuzz_pe.py --cases 200 --seed 42  (bateria manual maior)
  python tests/fuzz_pe.py --input tests/exc.exe --cases 20 --seed 7  (SEH)
Além do loader, há operadores F4 que miram o encadeamento SEH/unwind:
EXCEPTION_DIRECTORY, entradas RUNTIME_FUNCTION (.pdata) e UNWIND_INFO
(.xdata) — o emissor simbólico (R-5.4 F2/F3) precisa continuar honesto
(path seguro: sem .pdata -> .xdata crua) e nunca crashar/hangar.
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


def pe_unwind_regions(data):
    """Localiza (offset no arquivo) o EXCEPTION_DIRECTORY e as seções
    .pdata/.xdata. Nunca lança; chaves ausentes ficam None. Só para mirar
    a mutação — a validação real é sempre do dexter."""
    r = {"exc_dd": None, "pdata": None, "pdata_len": 0,
         "xdata": None, "xdata_len": 0}
    try:
        if len(data) < 0x40:
            return r
        e = int.from_bytes(data[0x3C:0x40], "little")
        if e + 24 > len(data) or data[e:e + 4] != b"PE\0\0":
            return r
        coff = e + 4
        nsec = int.from_bytes(data[coff + 2:coff + 4], "little")
        optsz = int.from_bytes(data[coff + 16:coff + 18], "little")
        opt = coff + 20
        if opt + optsz > len(data):
            return r
        dd = opt + 112               # 3º diretório (índice 3): EXCEPTION
        if dd + 3 * 8 + 8 <= len(data):
            r["exc_dd"] = dd + 3 * 8
        so = opt + optsz
        for i in range(nsec):
            b = so + i * 40
            if b + 40 > len(data):
                break
            name = bytes(data[b:b + 8]).rstrip(b"\x00")
            rp = int.from_bytes(data[b + 20:b + 24], "little")
            rs = int.from_bytes(data[b + 16:b + 20], "little")
            if rp and rs and rp + rs <= len(data):
                if name == b".pdata":
                    r["pdata"], r["pdata_len"] = rp, rs
                elif name == b".xdata":
                    r["xdata"], r["xdata_len"] = rp, rs
    except Exception:  # noqa: BLE001 - só reconhecimento, nunca falha
        pass
    return r


def mutate(data, rng):
    """Retorna (bytes_mutados, descrição). Operadores determinísticos."""
    op = rng.randrange(12)
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
    # --- operadores SEH/unwind (F4): miram o encadeamento .pdata/.xdata ---
    reg = pe_unwind_regions(data)
    if op == 8 and reg["exc_dd"] is not None:
        base = reg["exc_dd"]
        d[base:base + 8] = rng.choice([
            b"\x00" * 8,
            b"\xFF" * 8,
            rng.randrange(n).to_bytes(4, "little") + b"\x00\x10\x00\x00",
            b"\x00\x10\x00\x00" + b"\xFF\xFF\x00\x00",
        ])
        return bytes(d), "exc-dir"
    if op == 9 and reg["pdata"]:
        k = rng.randrange(1, 9)
        for _ in range(k):
            d[reg["pdata"] + rng.randrange(reg["pdata_len"])] = rng.randrange(256)
        return bytes(d), "pdata-flip(%d)" % k
    if op == 10 and reg["xdata"]:
        k = rng.randrange(1, 9)
        for _ in range(k):
            d[reg["xdata"] + rng.randrange(reg["xdata_len"])] = rng.randrange(256)
        return bytes(d), "xdata-flip(%d)" % k
    if op == 11 and reg["pdata"] and reg["pdata_len"] >= 12:
        idx = rng.randrange(reg["pdata_len"] // 12)
        u = reg["pdata"] + idx * 12 + 8   # campo UnwindData da RUNTIME_FUNCTION
        d[u:u + 4] = rng.choice([b"\xFF\xFF\xFF\xFF", b"\x01\x00\x00\x00",
                                 rng.randrange(0x80000000).to_bytes(4, "little")])
        return bytes(d), "pdata-unwind-ptr"
    # op == 7 (e fallback dos ops 8-11 quando a região alvo não existe):
    # bloco zerado em offset aleatório (16-64 bytes)
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
    ap.add_argument("--bin-native", action="store_true",
                    help="roda dexter com -m bin -native (exercita o emissor "
                         "simbólico de .pdata/.xdata, não só o loader)")
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
        dargs = [args.dexter, path, "-o", "NUL", "-q"]
        if args.bin_native:
            dargs += ["-m", "bin", "-native"]
        try:
            p = subprocess.run(dargs, capture_output=True, timeout=args.timeout)
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

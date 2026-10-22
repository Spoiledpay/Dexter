#!/usr/bin/env python3
"""x87_native_check.py — oráculo do x87 nativo (2a).

Uso:
  python tests\\x87_native_check.py x64 <asm_gerado> <exe_original> <tsv> <nasm>
  python tests\\x87_native_check.py x32 <asm_gerado> <fixture_asm> <tsv> <nasm>

x64 (modo `-m bin -native`):
  1. o .asm gerado remonta com `nasm -f bin` byte-a-byte igual ao .exe;
  2. as 2048 codificações saem na ordem (opcode, modrm) do TSV, e cada uma
     respeita a classificação: native=1 -> instrução real; native=0 -> db
     (invalid ou sem forma no NASM, com o mnemônico no comentário).

x32 (modo `-native`, link win32):
  1. as linhas do payload (2048, após o prólogo) são montadas isoladamente
     (`bits 32`, sem relocs no payload) e comparadas byte-a-byte com os
     bytes do fixture gerado (tests/x87nat32.asm);
  2. mesma verificação de ordem/classificação, coluna native32 do TSV.

Sai 0 se tudo confere; 1 com o primeiro motivo.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ENTRY_LINES = {"x64": 3, "x32": 5}   # prólogo antes do payload (linhas de instrução)

def die(msg):
    print("FALHA: " + msg)
    return 1

def load_tsv(path):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        idx, op, modrm, native, native32, mne = line.split("\t")
        rows.append((int(idx), int(op, 16), int(modrm, 16), int(native), int(native32), mne))
    if len(rows) != 2048:
        raise SystemExit("TSV com %d linhas (esperado 2048)" % len(rows))
    return rows

def text_insns(asm_path):
    """linhas de instrução da seção .text, na ordem (labels/comentários fora)."""
    text = Path(asm_path).read_text(encoding="utf-8", errors="replace")
    m = re.search(r'(?m)^\s*section\s+\.text\b[^\n]*$', text)
    if m:
        body = text[m.end():]
        stops = (r'(?m)^\s*section\s+',)
    else:
        # modo bin: seções são comentários "; ---- .text" e "; ---- .rdata"
        m = re.search(r'(?m)^; ---- \.text\s*$', text)
        if not m:
            raise SystemExit("secao .text nao encontrada em %s" % asm_path)
        body = text[m.end():]
        stops = (r'(?m)^; ---- ',)
    for stop in stops:
        m2 = re.search(stop, body)
        if m2:
            body = body[:m2.start()]
    out = []
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith(";") or s.startswith("label_"):
            continue
        if s.startswith("global ") or s.startswith("extern ") or s.startswith("align "):
            continue
        out.append(s)
    return out

def check_order(rows, blob, col, arch):
    n_native = n_db_invalid = n_db_named = n_db_mode = 0
    for (idx, op, modrm, native, native32, mne), line in zip(rows, blob):
        n_arch = native if arch == "x64" else native32
        is_db = line.startswith("db ")
        if n_arch:
            if is_db:
                return 1, "codificacao %d (%02X/%02X %s) caiu em db: %s" % (idx, op, modrm, mne, line)
            n_native += 1
        else:
            if not is_db:
                return 1, "codificacao %d (%02X/%02X) deveria ser db: %s" % (idx, op, modrm, line)
            if mne == "-":
                n_db_invalid += 1
            elif native:
                n_db_mode += 1          # forma existe, mas o modo não a emite (x32)
            else:
                if mne not in line:
                    return 1, "db %d (%02X/%02X) sem o comentario '%s'" % (idx, op, modrm, mne)
                n_db_named += 1
    return 0, "OK: %d nativas, %d db invalidas, %d db sem forma no NASM, %d db por limite de modo" % (
        n_native, n_db_invalid, n_db_named, n_db_mode)

def fixture_payload(fixture_asm):
    """bytes do payload do fixture gerado (linhas db entre o marcador e .rdata)."""
    text = Path(fixture_asm).read_text(encoding="utf-8", errors="replace")
    m = re.search(r'(?m)^; ---- payload', text)
    if not m:
        raise SystemExit("marcador de payload ausente em %s" % fixture_asm)
    body = text[m.end():]
    m2 = re.search(r'(?m)^section\s+\.rdata', body)
    if m2:
        body = body[:m2.start()]
    out = bytearray()
    for line in body.splitlines():
        mm = re.match(r'\s*db\s+(.*?)(?:\s*;.*)?$', line)
        if not mm:
            continue
        for tok in mm.group(1).split(","):
            tok = tok.strip()
            if tok:
                out.append(int(tok, 16))
    return bytes(out)

def main(argv):
    if len(argv) != 6 or argv[1] not in ("x64", "x32"):
        return die("uso: x87_native_check.py x64|x32 <asm> <origem> <tsv> <nasm>")
    arch, asm, origin, tsv, nasm = argv[1], argv[2], argv[3], argv[4], argv[5]
    rows = load_tsv(tsv)
    insns = text_insns(asm)
    need = ENTRY_LINES[arch] + len(rows)
    if len(insns) < need:
        return die("so %d linhas de instrucao (esperado >= %d)" % (len(insns), need))
    blob = insns[ENTRY_LINES[arch]:need]

    if arch == "x64":
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "rt.bin"
            r = subprocess.run([nasm, "-f", "bin", "-o", str(out), asm],
                               capture_output=True, text=True)
            if r.returncode != 0:
                err = (r.stderr or r.stdout).strip().splitlines()
                return die("nasm do .asm gerado falhou: %s" % (err[-1] if err else "?"))
            got = out.read_bytes()
        want = Path(origin).read_bytes()
        if got != want:
            if len(got) != len(want):
                return die("tamanho difere: nasm=%d exe=%d" % (len(got), len(want)))
            for i, (a, b) in enumerate(zip(want, got)):
                if a != b:
                    return die("byte 0x%X difere: exe=%02X nasm=%02X" % (i, a, b))
    else:
        # payload montado isoladamente (x32 não tem RIP/rel no payload)
        src = "bits 32\n" + "\n".join(blob) + "\n"
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "p.asm"
            o = Path(td) / "p.bin"
            p.write_text(src, encoding="utf-8")
            r = subprocess.run([nasm, "-f", "bin", "-o", str(o), str(p)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                err = (r.stderr or r.stdout).strip().splitlines()
                return die("nasm do payload x32 falhou: %s" % (err[-1] if err else "?"))
            got = o.read_bytes()
        want = fixture_payload(origin)
        if got != want:
            if len(got) != len(want):
                return die("payload x32: tamanho difere nasm=%d fixture=%d" % (len(got), len(want)))
            for i, (a, b) in enumerate(zip(want, got)):
                if a != b:
                    return die("payload x32: byte 0x%X difere fixture=%02X nasm=%02X" % (i, a, b))

    rc, msg = check_order(rows, blob, 3 if arch == "x64" else 4, arch)
    print(msg)
    return rc

if __name__ == "__main__":
    sys.exit(main(sys.argv))

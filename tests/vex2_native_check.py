#!/usr/bin/env python3
"""vex2_native_check.py — oráculo do VEX2 nativo (2b).

Uso: python tests\\vex2_native_check.py <asm_gerado> <exe_original> <manifesto> <nasm>

1. o .asm gerado remonta com `nasm -f bin` byte-a-byte igual ao .exe;
2. cada instrução do payload (após o prólogo) respeita o manifesto:
   native -> instrução real (não `db`); db -> `db` com o mnemônico no
   comentário (encodings que o NASM normaliza: L reservado em escalar).
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ENTRY = 3   # sub rsp / mov ecx,42 / call ExitProcess

def die(msg):
    print("FALHA: " + msg)
    return 1

def load_manifest(path):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        idx, hexs, kind, mne = line.split("\t")
        rows.append((int(idx), hexs.upper(), kind, mne))
    return rows

def text_insns(asm):
    text = Path(asm).read_text(encoding="utf-8", errors="replace")
    m = re.search(r'(?m)^; ---- \.text\s*$', text)
    if not m:
        raise SystemExit("secao .text ausente em %s" % asm)
    body = text[m.end():]
    m2 = re.search(r'(?m)^; ---- ', body)
    if m2:
        body = body[:m2.start()]
    out = []
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith(";") or s.startswith("label_"):
            continue
        out.append(s)
    return out

def main(argv):
    if len(argv) != 5:
        return die("uso: vex2_native_check.py <asm> <exe> <manifesto> <nasm>")
    asm, exe, man, nasm = argv[1], argv[2], argv[3], argv[4]
    rows = load_manifest(man)

    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "rt.bin"
        r = subprocess.run([nasm, "-f", "bin", "-o", str(out), asm],
                           capture_output=True, text=True)
        if r.returncode != 0:
            err = (r.stderr or r.stdout).strip().splitlines()
            return die("nasm do .asm gerado falhou: %s" % (err[-1] if err else "?"))
        got = out.read_bytes()
    want = Path(exe).read_bytes()
    if got != want:
        if len(got) != len(want):
            return die("tamanho difere: nasm=%d exe=%d" % (len(got), len(want)))
        for i, (a, b) in enumerate(zip(want, got)):
            if a != b:
                return die("byte 0x%X difere: exe=%02X nasm=%02X" % (i, a, b))

    insns = text_insns(asm)
    need = ENTRY + len(rows)
    if len(insns) < need:
        return die("so %d linhas de instrucao (esperado >= %d)" % (len(insns), need))
    blob = insns[ENTRY:need]
    n_native = n_db = 0
    for (idx, hexs, kind, mne), line in zip(rows, blob):
        is_db = line.startswith("db ")
        if kind == "native":
            if is_db:
                return die("insn %d (%s %s) caiu em db: %s" % (idx, hexs, mne, line))
            n_native += 1
        else:
            if not is_db:
                return die("insn %d (%s %s) deveria ser db: %s" % (idx, hexs, mne, line))
            if mne not in line:
                return die("db %d (%s) sem o comentario '%s'" % (idx, hexs, mne))
            n_db += 1
    print("OK: %d nativas, %d db declaradas" % (n_native, n_db))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))

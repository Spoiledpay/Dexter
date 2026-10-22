#!/usr/bin/env python3
"""label_drift.py ASM ORIG.exe [--nasm PATH]

Mede a EXATIDÃO de comprimento do `-native` sem depender de símbolos do
COFF (o nasm não exporta `label_`): monta o `.asm` com `-l` (listing) e
compara, para cada par de labels consecutivos na MESMA seção,

    delta_emitido (offset no listing)  ==  delta_original (VA2 - VA1)

Uma diferença significa que alguma instrução foi reencodada com outro
tamanho: todos os labels seguintes deslocam e ponteiros de dados que
apontam para código passam a valer 1..N bytes errado (foi o que quebrou
o `.CRT`/callbacks de TLS do `exc`).

Sai 0 se todos os deltas batem; 1 com os primeiros casos (label, deltas).
Nunca executa o binário.
"""
import os
import re
import subprocess
import sys
import tempfile

import secdump

LAB = re.compile(r'^\s*\d+\s+.*\blabel_([0-9A-Fa-f]{6,16}):\s*$')
SEC = re.compile(r'^\s*\d+\s+section\s+(\S+)')
OFF = re.compile(r'^\s*\d+\s+([0-9A-F]{8})\s')


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    asm, orig_p = args[0], args[1]
    nasm = r"C:\Nasm\nasm.exe"
    i = 2
    while i < len(args):
        if args[i] == '--nasm' and i + 1 < len(args):
            nasm = args[i + 1]
            i += 2
        else:
            print(f"argumento desconhecido: {args[i]}")
            return 2
    if not os.path.exists(nasm):
        print(f"nasm nao encontrado: {nasm}")
        return 2
    orig = secdump.load(orig_p)
    base = orig['imagebase']
    tmp = tempfile.mkdtemp(prefix='dexd')
    obj = os.path.join(tmp, 'a.obj')
    lst = os.path.join(tmp, 'a.lst')
    r = subprocess.run([nasm, '-f', 'win64', '-o', obj, '-l', lst, asm],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"nasm falhou ({r.returncode}): {r.stderr.strip()[:400]}")
        return 2
    marks = []          # (section, va, offset)
    sec = '?'
    pending = None
    for line in open(lst, 'r', errors='replace'):
        m = SEC.match(line)
        if m:
            sec = secdump.norm(m.group(1))
            pending = None
            continue
        m = LAB.match(line)
        if m:
            pending = int(m.group(1), 16)
            continue
        if pending is not None:
            m = OFF.match(line)
            if m:
                marks.append((sec, pending, int(m.group(1), 16)))
                pending = None
    if not marks:
        print("nenhum label com offset no listing")
        return 2
    bad = []
    prev = None
    for (sec, va, off) in marks:
        oname, ooff = secdump.locate(orig['secs'], va - base)
        if oname is None or secdump.norm(oname) != sec:
            prev = None
            continue
        if prev is not None and prev[0] == sec:
            d_emit = off - prev[2]
            d_orig = ooff - prev[1]
            if d_emit != d_orig:
                bad.append((prev[3], prev[1], prev[2], d_orig, d_emit))
        prev = (sec, ooff, off, va)
    print(f"labels medidos: {len(marks)} | divergentes: {len(bad)}")
    if not bad:
        print("OK: todo delta de label bate (comprimentos exatos)")
        return 0
    for (va, ooff, off, d_orig, d_emit) in bad[:15]:
        print(f"  VA 0x{va:X}: original {d_orig} B, emitido "
              f"{d_emit} B (delta {d_emit - d_orig:+d})")
    if len(bad) > 15:
        print(f"  ... +{len(bad) - 15}")
    print(f"\nFALHA: {len(bad)} instrucao(oes) com comprimento divergente")
    return 1


if __name__ == '__main__':
    sys.exit(main())

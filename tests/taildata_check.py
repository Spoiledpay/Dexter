#!/usr/bin/env python3
"""taildata_check.py ASM ORIG.exe REBUILT.exe

Gate estrutural da D-19 fatia 2c-3 (`.data` com vsize > raw):

  1. a `.data` do REBUILT tem vsize igual a do ORIG e raw >= vsize
     (o tail zerado foi emitido como bytes no arquivo);
  2. os alvos m1/m2 (offsets 0x800/0xC00 de tests/taildata.asm) existem
     como `label_<VA>:` no `.asm` (o dib do emissor ficou simbolico);
  3. o `.asm` usa `times 0x... db 0` para o tail (nao um dump byte a byte).

Nao executa binario (o comportamento exit 42 e checado no .bat).
Sai 0 OK; 1 divergencia; 2 uso/erro de leitura.
"""
import re
import sys

import secdump

LABEL = re.compile(r'^\s*label_([0-9A-Fa-f]+):\s*$')
TIMES = re.compile(r'^\s+times\s+0x[0-9A-Fa-f]+\s+db\s+0\s*$')
MARKER_OFFSETS = (0x800, 0xC00)      # m1 e m2 em tests/taildata.asm


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    asm_p, orig_p, reb_p = sys.argv[1:4]
    orig = secdump.load(orig_p)
    reb = secdump.load(reb_p)

    def get_data(pe, path):
        hits = [s for s in pe['secs'] if secdump.norm(s['name']) == '.data']
        if len(hits) != 1:
            print(f"FALHA: {path}: esperada 1 secao .data, achei {len(hits)}")
            return None
        return hits[0]

    od = get_data(orig, orig_p)
    rd = get_data(reb, reb_p)
    if od is None or rd is None:
        return 1
    if od['vsz'] != rd['vsz']:
        print(f"FALHA: .data vsize orig=0x{od['vsz']:X} rebuilt=0x{rd['vsz']:X}")
        return 1
    if rd['rsz'] < rd['vsz']:
        print(f"FALHA: .data rebuilt raw=0x{rd['rsz']:X} < vsize=0x{rd['vsz']:X} "
              f"(tail nao emitido)")
        return 1

    labels = set()
    times = 0
    for line in open(asm_p, 'r', errors='replace'):
        m = LABEL.match(line)
        if m:
            labels.add(int(m.group(1), 16))
        elif TIMES.match(line):
            times += 1
    base = orig['imagebase'] + od['va']
    missing = [off for off in MARKER_OFFSETS if base + off not in labels]
    if missing:
        print("FALHA: alvo do tail sem label: " +
              ", ".join(f".data+0x{off:X} (VA 0x{base+off:X})" for off in missing))
        return 1
    if times == 0:
        print("FALHA: tail sem `times 0x.. db 0`")
        return 1
    print(f"OK: .data vsize=0x{od['vsz']:X} raw=0x{rd['rsz']:X} "
          f"labels={len(labels)} times={times}")
    return 0


if __name__ == '__main__':
    sys.exit(main())

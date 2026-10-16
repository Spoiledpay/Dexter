#!/usr/bin/env python3
# tests/pe_exc_dir.py — confere que um PE x64 tem EXCEPTION_DIRECTORY válido
# (F2, R-5.4): rva != 0, size != 0 e size múltiplo de sizeof(RUNTIME_FUNCTION)=12.
# Uso: python tests/pe_exc_dir.py <exe>   -> imprime "EXC rva=0x.. size=0x.."
# Exit: 0 válido; 1 inválido/erro.
import struct
import sys

if len(sys.argv) != 2:
    print("uso: pe_exc_dir.py <exe>")
    sys.exit(1)
try:
    d = open(sys.argv[1], "rb").read()
    e = struct.unpack_from("<I", d, 0x3C)[0]
    if d[e:e + 4] != b"PE\x00\x00":
        print("nao-PE")
        sys.exit(1)
    coff = e + 4
    optsz = struct.unpack_from("<H", d, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", d, opt)[0]
    if magic != 0x20B:
        print("nao-PE32+")
        sys.exit(1)
    dd = opt + 112
    rva, sz = struct.unpack_from("<II", d, dd + 3 * 8)
except Exception as exc:  # noqa: BLE001
    print("erro:", exc)
    sys.exit(1)

print(f"EXC rva=0x{rva:X} size=0x{sz:X}")
if rva == 0 or sz == 0 or (sz % 12) != 0:
    sys.exit(1)
sys.exit(0)

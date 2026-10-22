#!/usr/bin/env python3
"""taildata_patch.py IN.exe OUT.exe [RAW]

Gera o fixture D-19 2c-3: copia IN.exe e reduz SizeOfRawData da secao
`.data` para RAW (default 0x400), mantendo VirtualSize. O loader passa a
zerar o tail [RAW, vsize); os marcadores m1/m2 de tests/taildata.asm caem
nesse tail.

Falha (exit 1) se a secao nao existir, se vsize <= RAW, se RAW > raw atual
ou se o header estiver fora dos limites do arquivo. Nunca executa o PE.
"""
import struct
import sys


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    inp, outp = sys.argv[1], sys.argv[2]
    new_raw = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x400
    data = bytearray(open(inp, 'rb').read())
    if len(data) < 0x40 or data[0:2] != b'MZ':
        print("FALHA: nao e PE (MZ)")
        return 1
    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
    if e_lfanew + 24 > len(data) or data[e_lfanew:e_lfanew + 4] != b'PE\0\0':
        print("FALHA: NT headers invalidos")
        return 1
    nsec = struct.unpack_from('<H', data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from('<H', data, e_lfanew + 20)[0]
    sec_off = e_lfanew + 24 + opt_size
    if nsec == 0 or nsec > 96 or sec_off + nsec * 40 > len(data):
        print("FALHA: tabela de secoes invalida")
        return 1
    for i in range(nsec):
        off = sec_off + i * 40
        name = data[off:off + 8].rstrip(b'\0')
        if name != b'.data':
            continue
        vsize, vaddr, raw_size, raw_ptr = struct.unpack_from('<IIII', data, off + 8)
        if new_raw >= vsize:
            print(f"FALHA: RAW=0x{new_raw:X} >= vsize=0x{vsize:X}")
            return 1
        if new_raw > raw_size:
            print(f"FALHA: RAW=0x{new_raw:X} > raw atual=0x{raw_size:X}")
            return 1
        if raw_ptr + raw_size > len(data):
            print("FALHA: raw_ptr+raw_size fora do arquivo")
            return 1
        struct.pack_into('<I', data, off + 16, new_raw)
        open(outp, 'wb').write(data)
        print(f".data vaddr=0x{vaddr:X} vsize=0x{vsize:X} "
              f"raw=0x{raw_size:X}->0x{new_raw:X} (tail=0x{vsize-new_raw:X})")
        return 0
    print("FALHA: secao .data ausente")
    return 1


if __name__ == '__main__':
    sys.exit(main())

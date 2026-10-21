#!/usr/bin/env python3
"""pe_dirs.py ORIG REBUILT

Oráculo estrutural da D-19 fatia 2a: cada DataDirectory não-nulo do ORIGINAL
deve resolver, no REBUILT, para a MESMA (seção, offset-dentro-da-seção).
O `link.exe` reordena/funde seções, então a RVA crua muda; o que tem de ser
preservado é o par (nome-de-seção, offset).

Sai 0 se tudo casa; 1 caso contrário (imprime as divergências).
"""
import struct, sys

NAMES = ["EXPORT", "IMPORT", "RESOURCE", "EXCEPTION", "SECURITY", "BASERELOC",
         "DEBUG", "ARCH", "GLOBALPTR", "TLS", "LOADCFG", "BOUNDIMP", "IAT",
         "DELAYIMP", "CLR", "RESV"]


def load(path):
    d = open(path, 'rb').read()
    if len(d) < 0x40 or d[:2] != b'MZ':
        raise SystemExit(f"{path}: nao e PE (sem MZ)")
    e = struct.unpack_from('<I', d, 0x3C)[0]
    if d[e:e+4] != b'PE\0\0':
        raise SystemExit(f"{path}: assinatura PE ausente")
    nsec = struct.unpack_from('<H', d, e+6)[0]
    optsz = struct.unpack_from('<H', d, e+20)[0]
    opt = e + 24
    is64 = struct.unpack_from('<H', d, opt)[0] == 0x20B
    dd = opt + (112 if is64 else 96)
    secoff = opt + optsz
    secs = []
    for i in range(nsec):
        o = secoff + i * 40
        name = d[o:o+8].rstrip(b'\0').decode('latin1')
        vsz, va, rsz, rp = struct.unpack_from('<IIII', d, o+8)
        secs.append((name, va, vsz, rp, rsz))
    dirs = [struct.unpack_from('<II', d, dd + i*8) for i in range(16)]
    return secs, dirs


def locate(secs, rva):
    for (name, va, vsz, rp, rsz) in secs:
        if va <= rva < va + max(vsz, rsz):
            return name, rva - va
    return None, None


def norm(name):
    # o gerador sanitiza setores COFF `/NNN` -> `_NNN` (strtab)
    return ('_' + name[1:]) if name.startswith('/') else name


def main():
    if len(sys.argv) != 3:
        print("uso: pe_dirs.py ORIG REBUILT")
        return 2
    osec, odir = load(sys.argv[1])
    bsec, bdir = load(sys.argv[2])
    fails = 0
    checked = 0
    for i in range(16):
        orva, osz = odir[i]
        if orva == 0:
            continue
        # SECURITY (4) e DEBUG (6) sao "regeneraveis": o link.exe produz o
        # proprio DEBUG dir e o certificado (SECURITY, offset de arquivo) nao
        # e copiado por design. Nao exigimos (secao,offset) iguais; apenas que
        # o dir continue valido (ou ausente).
        if i in (4, 6):
            brva, bsz = bdir[i]
            ok = (brva == 0) or (locate(bsec, brva)[0] is not None)
            tag = "OK* " if ok else "BAD"
            if not ok:
                fails += 1
            checked += 1
            print(f"{tag} dir[{i:2}] {NAMES[i]:10} regeneravel: orig=0x{orva:X}"
                  f" rebuilt=0x{brva:X} size {osz:#x}->{bsz:#x}")
            continue
        checked += 1
        oname, ooff = locate(osec, orva)
        brva, bsz = bdir[i]
        bname, boff = locate(bsec, brva)
        ok = (oname is not None and bname is not None
              and norm(oname) == bname and ooff == boff and bsz == osz)
        tag = "OK " if ok else "BAD"
        if not ok:
            fails += 1
        print(f"{tag} dir[{i:2}] {NAMES[i]:10} orig={oname}+0x{ooff:X}"
              f"  rebuilt={bname}+{('0x%X' % boff) if boff is not None else '?'}"
              f"  size {osz:#x}->{bsz:#x}")
    if fails:
        print(f"\nFALHA: {fails}/{checked} DataDirectories mal remapeados")
        return 1
    print(f"\nOK: {checked} DataDirectories remapeados por (secao, offset)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""secdump.py PE|OBJ [PE|OBJ ...]         -> tabela de secoes/headers
secdump.py --diff ORIG REBUILT          -> confronto secao-a-secao (D-19)

Oráculo estrutural da D-19 fatia 2c. Responde, sem desassemblar nada:
  * quais secoes existem no .obj (COFF do nasm) e no .exe (PE do link.exe);
  * ordem, RVA, vsize, raw, characteristics (flags decodificadas);
  * quais DataDirectories do PE apontam para onde.

Modo --diff confronta ORIG (PE de referencia) com REBUILT e lista:
  * secao ausente / duplicada / fora de ordem;
  * divergencia de characteristics que o link "funde" (LNK4078);
  * secoes que viraram dado inicializado (perderam nobits/UNINIT).
Nunca executa o binario. Saida deterministica; sai 0 (sem --diff) ou
0/1 (--diff: 1 quando ha divergencia estrutural).
"""
import struct
import sys

# IMAGE_SCN_* / IMAGE_FILE_*
SCN = [
    (0x00000020, "CNT_CODE"),
    (0x00000040, "CNT_INITDATA"),
    (0x00000080, "CNT_UNINIT"),
    (0x00000100, "LNK_OTHER"),
    (0x00000200, "LNK_INFO"),
    (0x00000800, "LNK_REMOVE"),
    (0x00001000, "LNK_COMDAT"),
    (0x00004000, "NO_DEFER_SPECEXC"),
    (0x00008000, "GPREL"),
    (0x01000000, "LNK_NRELOC_OVFL"),
    (0x02000000, "MEM_DISCARDABLE"),
    (0x04000000, "MEM_NOT_CACHED"),
    (0x08000000, "MEM_NOT_PAGED"),
    (0x10000000, "MEM_SHARED"),
    (0x20000000, "MEM_EXECUTE"),
    (0x40000000, "MEM_READ"),
    (0x80000000, "MEM_WRITE"),
]
ALIGN = ["-", "1", "2", "4", "8", "16", "32", "64", "128", "256",
         "512", "1K", "2K", "4K", "8K", "16K"]
DIRNAMES = ["EXPORT", "IMPORT", "RESOURCE", "EXCEPTION", "SECURITY",
            "BASERELOC", "DEBUG", "ARCH", "GLOBALPTR", "TLS", "LOADCFG",
            "BOUNDIMP", "IAT", "DELAYIMP", "CLR", "RESV"]


def flags_str(ch):
    out = [n for (m, n) in SCN if ch & m]
    out.append("ALIGN_" + ALIGN[(ch >> 20) & 0xF])
    return "|".join(out)


def read_coff_name(d, raw, stroff):
    if raw[:1] == b'/':
        try:
            off = int(raw[1:].split(b'\0')[0])
        except ValueError:
            return raw.rstrip(b'\0').decode('latin1')
        end = d.find(b'\0', stroff + off)
        return d[stroff + off:end].decode('latin1')
    return raw.rstrip(b'\0').decode('latin1')


def load_coff(d):
    mach, nsec, tds, psym, nsym, optsz, chars = struct.unpack_from(
        '<HHIIIHH', d, 0)
    secoff = 20 + optsz
    # string table: logo apos a symbol table (18 bytes/simbolo)
    stroff = psym + nsym * 18
    secs = []
    for i in range(nsec):
        o = secoff + i * 40
        name = read_coff_name(d, d[o:o + 8], stroff)
        vsz, va, rsz, rp, prel, plno, nrel, nlno, ch = struct.unpack_from(
            '<IIIIIIHHI', d, o + 8)
        secs.append({'name': name, 'va': va, 'vsz': vsz, 'rp': rp,
                     'rsz': rsz, 'ch': ch, 'nrel': nrel})
    return {'kind': 'COFF', 'machine': mach, 'chars': chars,
            'imagebase': 0, 'entry': 0, 'sizeimage': 0, 'secalign': 0,
            'subsystem': 0, 'dirs': [None] * 16, 'secs': secs}


def load_pe(d):
    if len(d) < 0x40 or d[:2] != b'MZ':
        raise SystemExit("nao e PE (sem MZ)")
    e = struct.unpack_from('<I', d, 0x3C)[0]
    if d[e:e + 4] != b'PE\0\0':
        raise SystemExit("assinatura PE ausente")
    mach, nsec = struct.unpack_from('<HH', d, e + 4)
    optsz = struct.unpack_from('<H', d, e + 20)[0]
    chars = struct.unpack_from('<H', d, e + 22)[0]
    opt = e + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    is64 = magic == 0x20B
    if magic not in (0x10B, 0x20B):
        raise SystemExit("optional header desconhecido")
    entry = struct.unpack_from('<I', d, opt + 16)[0]
    imagebase = (struct.unpack_from('<Q', d, opt + 24)[0] if is64
                 else struct.unpack_from('<I', d, opt + 28)[0])
    secalign, filealign = struct.unpack_from('<II', d, opt + 32)
    sizeimage = struct.unpack_from('<I', d, opt + 56)[0]
    subsystem = struct.unpack_from('<H', d, opt + 68)[0]
    dd = opt + (112 if is64 else 96)
    ndirs = min(struct.unpack_from('<I', d, opt + (108 if is64 else 92))[0], 16)
    dirs = []
    for i in range(16):
        dirs.append(struct.unpack_from('<II', d, dd + i * 8) if i < ndirs else None)
    secoff = opt + optsz
    secs = []
    for i in range(nsec):
        o = secoff + i * 40
        name = d[o:o + 8].rstrip(b'\0').decode('latin1')
        vsz, va, rsz, rp = struct.unpack_from('<IIII', d, o + 8)
        ch = struct.unpack_from('<I', d, o + 36)[0]
        secs.append({'name': name, 'va': va, 'vsz': vsz, 'rp': rp,
                     'rsz': rsz, 'ch': ch, 'nrel': 0})
    return {'kind': 'PE64' if is64 else 'PE32', 'machine': mach,
            'chars': chars, 'imagebase': imagebase, 'entry': entry,
            'sizeimage': sizeimage, 'secalign': secalign,
            'subsystem': subsystem, 'dirs': dirs, 'secs': secs}


def load(path):
    d = open(path, 'rb').read()
    if len(d) >= 2 and d[:2] == b'MZ':
        return load_pe(d)
    mach = struct.unpack_from('<H', d, 0)[0]
    if mach in (0x8664, 0x14C):
        return load_coff(d)
    raise SystemExit(f"{path}: formato desconhecido (nem MZ nem COFF)")


def dump(path, x):
    print(f"== {path} [{x['kind']}] machine=0x{x['machine']:04X} "
          f"chars=0x{x['chars']:04X}")
    if x['kind'].startswith('PE'):
        print(f"   imagebase=0x{x['imagebase']:X} entry=0x{x['entry']:X} "
              f"sizeimage=0x{x['sizeimage']:X} secalign=0x{x['secalign']:X} "
              f"subsystem={x['subsystem']}")
        for i, dr in enumerate(x['dirs']):
            if dr and dr[0]:
                print(f"   dir[{i:2}] {DIRNAMES[i]:10} rva=0x{dr[0]:X} "
                      f"size=0x{dr[1]:X}")
    print(f"   {'#':>2} {'secao':12} {'rva':>10} {'vsize':>10} {'rawptr':>10} "
          f"{'rawsize':>10} {'chars':>10}  flags")
    for i, s in enumerate(x['secs']):
        print(f"   {i:2} {s['name']:12} {s['va']:#10X} {s['vsz']:#10X} "
              f"{s['rp']:#10X} {s['rsz']:#10X} 0x{s['ch']:08X}  "
              f"{flags_str(s['ch'])}")


def locate(secs, rva):
    for s in secs:
        if s['va'] <= rva < s['va'] + max(s['vsz'], s['rsz']):
            return s['name'], rva - s['va']
    return None, None


def norm(name):
    return ('_' + name[1:]) if name.startswith('/') else name


def diff(orig_path, reb_path):
    o = load(orig_path)
    r = load(reb_path)
    print(f"ORIG    {orig_path} [{o['kind']}] secoes={len(o['secs'])}")
    print(f"REBUILT {reb_path} [{r['kind']}] secoes={len(r['secs'])}")
    fails = 0
    onames = [norm(s['name']) for s in o['secs']]
    rnames = [norm(s['name']) for s in r['secs']]

    print("\n-- secoes --")
    dup = {n for n in rnames if rnames.count(n) > 1}
    for n in sorted(dup):
        # .bss/.data duplicados sao a assinatura do LNK4078
        chs = {f"0x{s['ch']:08X}" for s in r['secs'] if norm(s['name']) == n}
        print(f"DUP  rebuilt tem {rnames.count(n)}x '{n}' "
              f"chars={','.join(sorted(chs))}")
        fails += 1
    for n in onames:
        if n not in rnames:
            print(f"MISS rebuilt sem a secao '{n}'")
            fails += 1
    for s in o['secs']:
        n = norm(s['name'])
        matches = [t for t in r['secs'] if norm(t['name']) == n]
        if not matches:
            print(f"MISS '{n}': orig chars=0x{s['ch']:08X} "
                  f"({flags_str(s['ch'])}) rva=0x{s['va']:X} vsz=0x{s['vsz']:X}")
            continue
        t = matches[0]
        oi, ri = onames.index(n), rnames.index(n)
        tags = []
        if oi != ri:
            tags.append(f"ordem {oi}->{ri}")
        if (s['ch'] >> 20) & 0xF != (t['ch'] >> 20) & 0xF:
            tags.append(f"align {(s['ch'] >> 20) & 0xF}->{(t['ch'] >> 20) & 0xF}")
        if bool(s['ch'] & 0x80) != bool(t['ch'] & 0x80):
            tags.append(f"UNINIT {bool(s['ch'] & 0x80)}->{bool(t['ch'] & 0x80)}")
        if s['ch'] != t['ch']:
            tags.append(f"chars 0x{s['ch']:08X}->0x{t['ch']:08X}")
        if s['vsz'] != t['vsz']:
            tags.append(f"vsize 0x{s['vsz']:X}->0x{t['vsz']:X}")
        if tags:
            print(f"DIFF '{n}': " + " | ".join(tags))
            fails += 1
        else:
            print(f"OK   '{n}' chars=0x{s['ch']:08X} vsize=0x{s['vsz']:X}")

    if o['dirs'] and r['dirs']:
        print("\n-- DataDirectories do ORIG no REBUILT (secao+offset) --")
        for i in range(16):
            if not o['dirs'][i] or not o['dirs'][i][0]:
                continue
            if not r['dirs'] or not r['dirs'][i]:
                print(f"BAD  dir[{i:2}] {DIRNAMES[i]:10} ausente no rebuilt")
                fails += 1
                continue
            orva, osz = o['dirs'][i]
            brva, bsz = r['dirs'][i] or (0, 0)
            on, oo = locate(o['secs'], orva)
            bn, bo = locate(r['secs'], brva)
            ok = on is not None and bn is not None and norm(on) == bn and oo == bo
            print(f"{'OK ' if ok else 'BAD'} dir[{i:2}] {DIRNAMES[i]:10} "
                  f"{on}+0x{oo:X} -> {bn}+{'-' if bo is None else hex(bo)}")
            if not ok:
                fails += 1
    print(f"\n{'FALHA' if fails else 'OK'}: {fails} divergencia(s) estrutural(is)")
    return 1 if fails else 0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    if args[0] == '--diff':
        if len(args) != 3:
            print("uso: secdump.py --diff ORIG REBUILT")
            return 2
        return diff(args[1], args[2])
    for p in args:
        dump(p, load(p))
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
# tests/pe_impdesc.py — valida que a tabela de imports ficou SIMBOLICA no .asm
# gerado por `dexter -m bin -native` (R-5.3 F2/F3). Oráculo = bytes do PE
# original:
#   * cada descritor IMAGE_IMPORT_DESCRIPTOR vira `label_<VA>:` + 5 linhas `dd`;
#   * cada campo RVA (OriginalFirstThunk/Name/FirstThunk) cujo alvo cai numa
#     seção de dados com bytes (não executável, não `.pdata`/`.xdata`) sai
#     `dd label_<alvoVA> + 0x<C>`, C = vaddr - raw_ptr da seção do alvo, e o
#     alvo ganha `label_<alvoVA>:` no .asm;
#   * alvo sem label garantida cai em `dd 0x<rva>` cru (fiel).
# F3: as entradas nao-nulas das arrays de thunks (OFT=ILT e FT=IAT) saem
# `dq label_<hint/name VA> + 0x<C>` quando o valor e um RVA by-name rotulavel;
# ordinal (bit63), bound (v>32 bits) ou alvo nao-rotulavel cai em `dq 0x<v>`
# cru (byte-fiel) e o alvo ganha `label_`.
# Uso: python tests/pe_impdesc.py <exe> <asm>   -> imprime "IMPDESC ...".
# Exit: 0 tudo conferido; 1 divergencia/erro.
import struct
import sys

if len(sys.argv) != 3:
    print("uso: pe_impdesc.py <exe> <asm>")
    sys.exit(1)

exe, asm = sys.argv[1], sys.argv[2]
try:
    d = open(exe, "rb").read()
    e = struct.unpack_from("<I", d, 0x3C)[0]
    if d[e:e + 4] != b"PE\x00\x00":
        print("nao-PE")
        sys.exit(1)
    nsec = struct.unpack_from("<H", d, e + 6)[0]
    optsz = struct.unpack_from("<H", d, e + 20)[0]
    opt = e + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    if magic != 0x20B:
        print("nao-PE32+ (F2 e x64)")
        sys.exit(0)  # x32 nao usa F2: nada a conferir
    imgbase = struct.unpack_from("<Q", d, opt + 24)[0]
    szhdr = struct.unpack_from("<I", d, opt + 60)[0]
    imp_rva, imp_sz = struct.unpack_from("<II", d, opt + 112 + 8)
    secoff = e + 24 + optsz
    secs = []
    for i in range(nsec):
        s = secoff + i * 40
        name = d[s:s + 8].rstrip(b"\x00")
        vs, va, rs, rp, ch = struct.unpack_from("<IIIII", d, s + 8)
        secs.append((name, va, vs, rs, rp, ch))
except Exception as exc:  # noqa: BLE001
    print("erro:", exc)
    sys.exit(1)


def r2o(rva):
    if rva < szhdr:
        return rva if rva < len(d) else None
    for _, va, vs, rs, rp, _ch in secs:
        if va <= rva < va + max(vs, rs):
            off = rva - va
            return rp + off if off < rs else None
    return None


def target_section(rva):
    for s in secs:
        if s[1] <= rva < s[1] + max(s[2], s[3]):
            return s
    return None


if imp_rva == 0 or imp_sz == 0:
    print("IMPDESC sem imports")
    sys.exit(0)

o = r2o(imp_rva)
if o is None:
    print("IMPDESC import dir nao mapeavel")
    sys.exit(1)

try:
    text = open(asm, "r", encoding="latin1").read()
except Exception as exc:  # noqa: BLE001
    print("erro:", exc)
    sys.exit(1)

CNT_CODE = 0x20
EXEC = 0x20000000


def labelable(sec):
    """Secao de dados com bytes, nao executavel, nao .pdata/.xdata."""
    if sec is None:
        return False
    name, va, vs, rs, rp, ch = sec
    return rs > 0 and not (ch & (CNT_CODE | EXEC)) and name not in (b".pdata", b".xdata")


descs = []
n = 0
symbolic = 0
rawf = 0
bad = 0
while True:
    if o + 20 > len(d):
        print("IMPDESC descritor fora do arquivo")
        sys.exit(1)
    oft, ts, fc, nm, ft = struct.unpack_from("<IIIII", d, o)
    d_rva = imp_rva + n * 20
    d_va = imgbase + d_rva
    descs.append((oft, nm, ft))
    if f"label_{d_va:X}:" not in text:
        print(f"  FALTA label do descritor: label_{d_va:X}:")
        bad += 1
    for label, rva in (("OFT", oft), ("Name", nm), ("FT", ft)):
        if rva == 0:
            continue
        s = target_section(rva)
        if s is None:
            continue
        name, va, vs, rs, rp, ch = s
        off = rva - va
        if not (labelable(s) and off < rs):
            exp = f"dd 0x{rva:X}"
            if exp in text:
                rawf += 1
            else:
                print(f"  FALTA campo cru: {exp} ({label} rva={rva:#x})")
                bad += 1
            continue
        c = (va - rp) & 0xFFFFFFFF
        tgt_va = imgbase + rva
        exp = f"dd label_{tgt_va:X} + 0x{c:X}"
        if exp in text:
            symbolic += 1
        else:
            print(f"  FALTA campo simbolico: {exp}")
            bad += 1
        if f"label_{tgt_va:X}:" not in text:
            print(f"  FALTA label do alvo: label_{tgt_va:X}:")
            bad += 1
    if oft == 0 and ts == 0 and fc == 0 and nm == 0 and ft == 0:
        break
    n += 1
    o += 20
    if n > 4096:
        print("IMPDESC runaway")
        sys.exit(1)

# ---- F3: arrays de thunks (OFT=ILT; FT=IAT) -> `dq label_<hint/name> + C` ----
thunks_sym = 0
thunks_raw = 0
for oft, nm, ft in descs:
    for arr in (oft, ft):
        if arr == 0:
            continue
        o2 = r2o(arr)
        if o2 is None:
            continue
        if not labelable(target_section(arr)):
            continue  # .asm emite essa secao como db puro: nada a conferir
        k = 0
        while True:
            if o2 + 8 > len(d):
                break
            v = struct.unpack_from("<Q", d, o2)[0]
            if v == 0:
                break  # terminador: fica em db (fiel)
            exp = None
            if (v >> 63) == 0 and v <= 0xFFFFFFFF:
                s = target_section(v)
                if labelable(s) and (v - s[1]) < s[3]:
                    c = (s[1] - s[4]) & 0xFFFFFFFF
                    tgt_va = imgbase + v
                    exp = f"dq label_{tgt_va:X} + 0x{c:X}"
                    if f"label_{tgt_va:X}:" not in text:
                        print(f"  FALTA label do hint/name: label_{tgt_va:X}:")
                        bad += 1
            if exp is None:
                exp = f"dq 0x{v:X}"
                if exp in text:
                    thunks_raw += 1
                else:
                    print(f"  FALTA thunk cru: {exp} (arr={arr:#x} k={k})")
                    bad += 1
            else:
                if exp in text:
                    thunks_sym += 1
                else:
                    print(f"  FALTA thunk simbolico: {exp} (arr={arr:#x} k={k})")
                    bad += 1
            k += 1
            o2 += 8
            if k > 4096:
                print("IMPDESC thunk runaway")
                sys.exit(1)

print(f"IMPDESC descs={n + 1} simbolicos={symbolic} crus={rawf} "
      f"thunks={thunks_sym + thunks_raw} sym={thunks_sym} raw={thunks_raw} "
      f"ruins={bad}")
sys.exit(1 if bad else 0)

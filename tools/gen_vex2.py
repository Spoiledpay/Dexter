#!/usr/bin/env python3
"""gen_vex2.py — gera src/disasm/vex2_tbl.inc (mapa 0F sob VEX2) e o
manifesto tests/expected/vex2.tsv.

Requer capstone (ferramenta de desenvolvimento; o BUILD não depende dele).
Metodo (sem heurística de "v+ mnemônico"): para cada (pp, L, opcode) monta
alvos VEX2 canônicos e pergunta ao NASM qual texto reencoda os bytes exatos.
Ordem: reg/reg e memória, com vvvv usado (2) e não usado (0); sem ModRM por
último. Entradas cujo encoding o NASM normaliza (L reservado em escalar)
ficam em db, com contagem no manifesto.

Uso: python tools\\gen_vex2.py
"""
import itertools
import subprocess
import tempfile
from collections import Counter
from pathlib import Path

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parent.parent
NASM = r"C:\Nasm\nasm.exe"
OUT_INC = ROOT / "src" / "disasm" / "vex2_tbl.inc"
OUT_TSV = ROOT / "tests" / "expected" / "vex2.tsv"

md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True
GP32 = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"]
GP64 = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"]

ROLE = {"R": 1, "V": 2, "M": 3, "I": 4}
CLASS = {"V16": 1, "V32": 2, "G32": 3, "K": 4, "M": 5, "M4": 6, "M8": 7, "I8": 8, "G64": 9}

def dec(b):
    try:
        insns = list(md.disasm(bytes(b), 0x1000))
    except Exception:
        return None
    if not insns:
        return None
    i = insns[0]
    if i.size != len(b) or i.mnemonic.startswith("("):
        return None
    return i

def v2(pp, L, rbar, vvvv):
    return ((rbar & 1) << 7) | ((~vvvv & 0xF) << 3) | ((L & 1) << 2) | (pp & 3)

def assemble(src):
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "t.asm"
        o = Path(td) / "t.bin"
        p.write_text("bits 64\ndefault rel\n" + src + "\n", encoding="ascii")
        r = subprocess.run([NASM, "-f", "bin", "-o", str(o), str(p)],
                           capture_output=True, text=True)
        return o.read_bytes() if r.returncode == 0 else None

def kinds_of(i):
    out = []
    for o in i.operands:
        if o.type == 1:
            name = i.reg_name(o.reg) or "?"
            if name[:3] == "xmm":
                out.append(("V16", None))
            elif name[:3] == "ymm":
                out.append(("V32", None))
            elif name[0] == "k" and name[1:].isdigit():
                out.append(("K", None))
            else:
                out.append(("G64" if name in GP64 else "G32", None))
        elif o.type == 2:
            out.append(("I8", None))
        elif o.type == 3:
            out.append(("M", None))
        else:
            out.append(("?", None))
    return out

def render(mne, kinds, roles, memkw):
    parts = []
    for k, (cls, _) in enumerate(kinds):
        if cls in ("V16", "V32", "G32", "G64", "K"):
            idx = {"R": 1, "V": 2, "M": 3}[roles[k]]
            if cls == "V16":
                parts.append("xmm%d" % idx)
            elif cls == "V32":
                parts.append("ymm%d" % idx)
            elif cls == "K":
                parts.append("k%d" % idx)
            else:
                parts.append((GP64 if cls == "G64" else GP32)[idx])
        elif cls == "M":
            parts.append(("%s [rax]" % memkw) if memkw else "[rax]")
        elif cls == "I8":
            parts.append("0x1b")
    return "    %s %s" % (mne, ", ".join(parts))

def try_shapes(mne, kinds, target):
    reg_idx = [k for k, (cls, _) in enumerate(kinds) if cls not in ("M", "I8", "?")]
    has_mem = any(c == "M" for c, _ in kinds)
    if has_mem:
        pool = ["R", "V"]
    elif len(reg_idx) == 2:
        pool = ["R", "M"]
    else:
        pool = ["R", "V", "M"]
    if len(reg_idx) > len(pool):
        return None
    mem_opts = [None, "dword", "qword"] if has_mem else [None]
    for order in itertools.permutations(pool, len(reg_idx)):
        roles = dict(zip(reg_idx, order))
        for memkw in mem_opts:
            txt = render(mne, kinds, roles, memkw)
            if assemble(txt) == target:
                ops = []
                for k, (cls, _) in enumerate(kinds):
                    role = roles.get(k, {"M": "M", "I8": "I"}.get(cls, "?"))
                    c = cls
                    if cls == "M" and memkw:
                        c = {"dword": "M4", "qword": "M8"}[memkw]
                    ops.append((role, c))
                return ops, txt.strip()
    return None

def attempt(pp, L, op, vvvv, tail, imm):
    b = [0xC5, v2(pp, L, 1, vvvv), op]
    if tail == "rr":
        b.append(0xCB)
    elif tail == "mem":
        b.append(0x08)
    if imm:
        b.append(0x1B)
    i = dec(b)
    if not i:
        return None, None
    return i.mnemonic, try_shapes(i.mnemonic, kinds_of(i), bytes(b))

def derive():
    rows = []
    for pp in range(4):
        for L in range(2):
            for op in range(256):
                hit = None
                seen = None          # último alvo válido (p/ flags de decode)
                for vvvv, vtag in ((2, "used"), (0, "unused")):
                    for tail in ("rr", "mem"):
                        for imm in (False, True):
                            mne, r = attempt(pp, L, op, vvvv, tail, imm)
                            if mne:
                                seen = (mne, vtag, True, imm)
                            if r:
                                hit = (mne, vtag, r[0], r[1], True, imm)
                                break
                        if hit:
                            break
                    if hit:
                        break
                if hit:
                    rows.append({"pp": pp, "L": L, "op": op, "mne": hit[0],
                                 "vvvv": hit[1], "ops": hit[2], "tmpl": hit[3],
                                 "modrm": hit[4], "imm": hit[5]})
                    continue
                i = dec([0xC5, v2(pp, L, 1, 0), op])
                if i and assemble("    " + i.mnemonic) == bytes([0xC5, v2(pp, L, 1, 0), op]):
                    rows.append({"pp": pp, "L": L, "op": op, "mne": i.mnemonic,
                                 "vvvv": "unused", "ops": [], "tmpl": i.mnemonic,
                                 "modrm": False, "imm": False})
                    continue
                if seen:
                    rows.append({"pp": pp, "L": L, "op": op, "mne": seen[0],
                                 "vvvv": "db", "ops": None, "tmpl": "",
                                 "modrm": seen[2], "imm": seen[3]})
    return rows

def emit(rows):
    lines = []
    lines.append(";=============================================================================\n")
    lines.append("; Dexter/src/disasm/vex2_tbl.inc\n")
    lines.append("; Tabela VEX2 (C5, mapa 0F): mnemônico + forma de operando.\n")
    lines.append(";\n")
    lines.append("; GERADO por tools/gen_vex2.py (capstone 5.0.7 + NASM como juiz).\n")
    lines.append("; NAO EDITAR A MAO. Regenerar: python tools\\gen_vex2.py\n")
    lines.append(";\n")
    lines.append("; Descritor (20 B, alinhado a 4):\n")
    lines.append(";   dq mnemônico\n")
    lines.append(";   db nops | 0x80 (vvvv precisa ser 0/não usado)\n")
    lines.append(";   db role0, class0, role1, class1\n")
    lines.append(";   db role2, class2, role3, class3\n")
    lines.append(";   db 0,0,0\n")
    lines.append("; Índice: vex2_idx[(pp*2+L)*256+op] = id do descritor (0xFFFF = db).\n")
    lines.append(";=============================================================================\n\n")
    lines.append("%define VEX2_DESC_NONE 0xFFFF\n")
    lines.append("%define VEX2_DESC_SIZE 20\n\n")
    names = []
    lines.append("section .rodata\n\n")
    for n, r in enumerate(rows):
        label = "s_v2_%03d" % n
        names.append((n, label, r))
        lines.append('%s: db "%s", 0\n' % (label, r["mne"]))
    lines.append("\nalign 8\nvex2_desc:\n")
    ids = {}
    did = 0
    for n, label, r in names:
        ids[(r["pp"], r["L"], r["op"])] = did
        did += 1
        flags = 0x80 if r["vvvv"] == "unused" else 0
        if r["ops"] is None:
            flags |= 0x40            # sem forma: mne vai p/ o comentário do db
            nops = 0
        else:
            nops = len(r["ops"])
        if r["modrm"]:
            flags |= 0x08            # ModRM presente (decode)
        if r["imm"]:
            flags |= 0x10            # imm8 presente (decode)
        ops = list(r["ops"] or []) + [("?", "?")] * (4 - nops)
        lines.append("    dq %s\n" % label)
        lines.append("    db %d, %d, %d, %d, %d\n" % (
            nops | flags,
            ROLE.get(ops[0][0], 0) or 0, CLASS.get(ops[0][1], 0) or 0,
            ROLE.get(ops[1][0], 0) or 0, CLASS.get(ops[1][1], 0) or 0))
        lines.append("    db %d, %d, %d, %d\n" % (
            ROLE.get(ops[2][0], 0) or 0, CLASS.get(ops[2][1], 0) or 0,
            ROLE.get(ops[3][0], 0) or 0, CLASS.get(ops[3][1], 0) or 0))
        lines.append("    db 0, 0, 0\n")
    lines.append("\nalign 8\nvex2_idx:\n")
    key = 0
    for pp in range(4):
        for L in range(2):
            lines.append("    ; pp=%d L=%d\n" % (pp, L))
            vals = []
            for op in range(256):
                vals.append(ids.get((pp, L, op), 0xFFFF))
            for i in range(0, 256, 16):
                lines.append("    dw " + ", ".join("0x%04X" % v for v in vals[i:i + 16]) + "\n")
    OUT_INC.write_text("".join(lines), encoding="utf-8", newline="\n")
    return did

def main():
    rows = derive()
    nd = emit(rows)
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TSV.open("w", encoding="utf-8", newline="\n") as f:
        f.write("# pp\tL\top\tvvvv\tmnemonic\tshape\ttemplate\n")
        for r in rows:
            shape = "" if r["ops"] is None else " ".join("%s:%s" % o for o in r["ops"])
            f.write("%d\t%d\t%02X\t%s\t%s\t%s\t%s\n" % (
                r["pp"], r["L"], r["op"], r["vvvv"], r["mne"], shape, r["tmpl"]))
    print("entradas: %d | descritores: %d | db: %d" % (
        len(rows), nd, sum(1 for r in rows if r["ops"] is None)))
    print("vvvv:", dict(Counter(r["vvvv"] for r in rows)))

if __name__ == "__main__":
    main()

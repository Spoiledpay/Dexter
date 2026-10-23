#!/usr/bin/env python3
"""gen_vex2_fixture.py — gera tests/vex2nat.asm + tests/expected/vex2nat.tsv.

Lê a tabela derivada (tests/expected/vex2.tsv, de tools/gen_vex2.py) e monta
um fixture com VARIAÇÕES de cada entrada VEX2 (mapa 0F):
  - reg/reg canônico (reg=1, vvvv=2, rm=3)
  - reg/reg com registradores altos (reg=10, vvvv=11, rm=5)
  - memória [rax] / [rbx+0x10] / [rsi+rcx*4+0x1000] (quando o encoding aceita)
  - imediato do próprio encoding (0x1B)
Cada variante só entra se o capstone decodificar o mesmo mnemônico E o NASM
reencodar os bytes com o texto que o Dexter deve emitir (juiz duplo).

Saída: fixture (payload inalcançável após ExitProcess, exit 42) + manifesto
com expectativa por instrução (native/db). Regenerar:
  python tools\\gen_vex2.py && python tools\\gen_vex2_fixture.py
"""
import subprocess
import tempfile
from pathlib import Path

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parent.parent
NASM = r"C:\Nasm\nasm.exe"
IN_TSV = ROOT / "tests" / "expected" / "vex2.tsv"
OUT_ASM = ROOT / "tests" / "vex2nat.asm"
OUT_TSV = ROOT / "tests" / "expected" / "vex2nat.tsv"

md = Cs(CS_ARCH_X86, CS_MODE_64)
GP32 = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"]

HEADER = """; vex2nat.asm — CORPUS 2b: VEX2 (C5, mapa 0F), variações de operando.
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; GERADO por tools/gen_vex2_fixture.py — não editar à mão.
; Payload inalcançável (após ExitProcess); o fixture sai com 42.
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    sub rsp, 40
    mov ecx, 42
    call ExitProcess

; ---- payload VEX2 (uma instrução por linha) ----
"""

FOOTER = """
section .rdata
align 8
vex2data: dq 0x3FF0000000000000
"""

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

def assemble(src):
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "t.asm"
        o = Path(td) / "t.bin"
        p.write_text("bits 64\ndefault rel\n" + src + "\n", encoding="ascii")
        r = subprocess.run([NASM, "-f", "bin", "-o", str(o), str(p)],
                           capture_output=True, text=True)
        return o.read_bytes() if r.returncode == 0 else None

def load_rows():
    rows = []
    for line in IN_TSV.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        pp, L, op, vvvv, mne, shape, tmpl = line.split("\t")
        ops = []
        for tok in shape.split():
            role, cls = tok.split(":")
            ops.append((role, cls))
        rows.append({"pp": int(pp), "L": int(L), "op": int(op, 16),
                     "vvvv": vvvv, "mne": mne, "ops": ops})
    return rows

def render(mne, ops, regs, memtext, imm, memvariant):
    parts = []
    for role, cls in ops:
        if role == "I":
            parts.append("0x%X" % imm)
            continue
        if role == "M" and memvariant:
            kw = {"M4": "dword ", "M8": "qword ", "G32": "dword ", "G64": "qword "}.get(cls, "")
            parts.append("%s[%s]" % (kw, memtext))
            continue
        n = regs.get(role)
        if cls == "V16":
            parts.append("xmm%d" % n)
        elif cls == "V32":
            parts.append("ymm%d" % n)
        elif cls == "K":
            parts.append("k%d" % n)
        elif cls == "G32":
            parts.append(GP32[n & 7])
        elif cls == "G64":
            parts.append(GP32[n & 7])   # VEX2 (W=0) não usa G64; defensivo
        else:
            kw = {"M4": "dword ", "M8": "qword "}.get(cls, "")
            parts.append("%s[%s]" % (kw, memtext))
    return "    %s %s" % (mne, ", ".join(parts))

def encode(pp, L, op, reg, vvvv, mode, imm):
    """mode: ('rr', rm) | ('mem', rm, mod, disp, sib) | ('none',)"""
    rbar = 1 if (reg & 8) == 0 else 0
    v2 = (rbar << 7) | ((~vvvv & 0xF) << 3) | ((L & 1) << 2) | (pp & 3)
    b = [0xC5, v2, op]
    if mode[0] == "none":
        return b
    if mode[0] == "rr":
        rm = mode[1]
        b.append(0xC0 | ((reg & 7) << 3) | (rm & 7))
        if imm is not None:
            b.append(imm)
        return b
    rm, mod, disp, sib = mode[1], mode[2], mode[3], mode[4]
    b.append((mod << 6) | ((reg & 7) << 3) | rm)
    if rm == 4:
        b.append(sib)
    if mod == 1:
        b.append(disp & 0xFF)
    elif mod == 2:
        b += list((disp & 0xFFFFFFFF).to_bytes(4, "little"))
    if imm is not None:
        b.append(imm)
    return b

def main():
    rows = load_rows()
    body = []
    manifest = ["# idx\tbytes\tkind\tmnemonic"]
    idx = 0
    nvars = {"rr": 0, "mem": 0, "db": 0, "skip": 0}
    for r in rows:
        pp, L, op, ops = r["pp"], r["L"], r["op"], r["ops"]
        is_db = r["vvvv"] == "db" or not ops
        has_imm = any(role == "I" for role, _ in ops)
        has_mem = any(role == "M" for role, _ in ops)
        imm = 0x1B if has_imm else None
        variants = []
        if is_db:
            variants.append((("rr", 3), 1, 2, "db"))
        else:
            # vvvv unused exige o campo 1111 (lógico 0); usá-lo com outro valor
            # é encoding reservado (o NASM normaliza e o round-trip não fecha).
            v1, v2 = (0, 0) if r["vvvv"] == "unused" else (2, 11)
            variants.append((("rr", 3), 1, v1, "rr"))
            variants.append((("rr", 5), 10, v2, "rr"))
            if has_mem:
                variants.append((("mem", 0, 0, 0, 0), 1, v1, "mem"))
                variants.append((("mem", 3, 1, 0x10, 0), 1, v1, "mem"))
                variants.append((("mem", 4, 2, 0x1000, 0x8E), 1, v1, "mem"))
        for mode, reg, vvvv, kind in variants:
            b = encode(pp, L, op, reg, vvvv, mode, imm)
            ci = dec(b)
            if not ci or ci.mnemonic != r["mne"]:
                nvars["skip"] += 1
                continue
            if kind == "db":
                body.append("    db %s   ; %s\n" % (", ".join("0x%02X" % x for x in b), r["mne"]))
                manifest.append("%d\t%s\tdb\t%s" % (idx, "".join("%02X" % x for x in b), r["mne"]))
            else:
                if mode[0] == "rr":
                    regs = {"R": reg, "V": vvvv, "M": mode[1]}
                    memtext = None
                else:
                    regs = {"R": reg, "V": vvvv, "M": 0}
                    memtext = {0: "rax", 3: "rbx+0x10", 4: "rsi+rcx*4+0x1000"}[mode[1]]
                txt = render(r["mne"], ops, regs, memtext, 0x1B, mode[0] == "mem")
                got = assemble(txt)
                if got != bytes(b):
                    nvars["skip"] += 1
                    continue
                body.append("    db %s   ; %s\n" % (", ".join("0x%02X" % x for x in b), txt.strip()))
                manifest.append("%d\t%s\tnative\t%s" % (idx, "".join("%02X" % x for x in b), r["mne"]))
            nvars["db" if kind == "db" else "mem" if kind == "mem" else "rr"] += 1
            idx += 1
    OUT_ASM.write_text(HEADER + "".join(body) + FOOTER, encoding="utf-8", newline="\n")
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    OUT_TSV.write_text("\n".join(manifest) + "\n", encoding="utf-8", newline="\n")
    print("instrucoes: %d | rr=%d mem=%d db=%d | variantes descartadas=%d" % (
        idx, nvars["rr"], nvars["mem"], nvars["db"], nvars["skip"]))
    print("nativas no manifesto: %d" % sum(1 for m in manifest[1:] if "\tnative\t" in m))

if __name__ == "__main__":
    main()

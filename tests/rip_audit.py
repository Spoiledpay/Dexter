#!/usr/bin/env python3
"""rip_audit.py ASM ORIG.exe REBUILT.exe

Auditoria da D-19 (win64 `-native`): encontra instrucoes emitidas como `db`
que contem operando RIP-relative e cujo disp32 foi CONGELADO do original.
Como o `link.exe` reordena/move secoes, um disp32 congelado passa a apontar
para outro lugar (ou para zero na `.bss`) -> ponteiro/funcao invalidos.

Metodo (sem confiar no texto do emissor):
  1. le o `.asm` gerado: `label_<VA>:` + linhas `db 0x..,..`;
  2. decodifica os bytes com capstone no VA do label;
  3. para cada operando [rip+disp] calcula o alvo = VA + len + disp;
  4. localiza o alvo no ORIG (secao+offset) e recalcula a VA equivalente no
     REBUILT pela secao homonima (mesmo criterio do pe_dirs.py);
  5. se a VA equivalente difere da congelada, o site e FALSO (latente).

Saida: resumo por secao-alvo + os N primeiros sites (deterministico).
Sai 0 quando nao ha site falso; 1 quando ha (gate da fatia).
Nunca executa binario.
"""
import re
import sys

import capstone

import secdump

LABEL = re.compile(r'^\s*label_([0-9A-Fa-f]+):\s*$')
DB = re.compile(r'^\s+db\s+([^;]*?)\s*(?:;.*)?$')
BYTE = re.compile(r'0x([0-9A-Fa-f]{2})')


def load_asm(path):
    """-> lista de (va, bytes) para cada bloco `db` sob um label_<VA>."""
    out = []
    cur = None
    for line in open(path, 'r', errors='replace'):
        m = LABEL.match(line)
        if m:
            cur = int(m.group(1), 16)
            continue
        m = DB.match(line)
        if m and cur is not None:
            raw = bytes(int(x, 16) for x in BYTE.findall(m.group(1)))
            if raw:
                out.append((cur, raw))
            cur = None
    return out


def load_labels(path):
    labs = set()
    for line in open(path, 'r', errors='replace'):
        m = LABEL.match(line)
        if m:
            labs.add(int(m.group(1), 16))
    return labs


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    asm, orig_p, reb_p = sys.argv[1:4]
    orig = secdump.load(orig_p)
    reb = secdump.load(reb_p)
    rebmap = {secdump.norm(s['name']): s for s in reb['secs']}
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    base = orig['imagebase']
    blocks = load_asm(asm)
    labels = load_labels(asm)
    bad = []
    scanned = 0
    for va, raw in blocks:
        scanned += 1
        for ins in md.disasm(raw, va):
            for op in ins.operands:
                if op.type != capstone.x86.X86_OP_MEM:
                    continue
                if op.mem.base != capstone.x86.X86_REG_RIP:
                    continue
                tgt = ins.address + ins.size + op.mem.disp
                oname, ooff = secdump.locate(orig['secs'], tgt - base)
                if oname is None:
                    continue
                key = secdump.norm(oname)
                tsec = rebmap.get(key)
                if tsec is None:
                    new_va = None
                else:
                    new_va = reb['imagebase'] + tsec['va'] + ooff
                if new_va != tgt:
                    bad.append((ins.address, tgt, key, ooff, new_va,
                                ins.mnemonic, tgt in labels))
    print(f"db-blocks={len(blocks)} decodificados={scanned} labels={len(labels)}")
    if not bad:
        print("OK: nenhuma referencia RIP-relative congelada aponta p/ secao movida")
        return 0
    bysec = {}
    bymne = {}
    for (_, _, key, _, _, mne, _) in bad:
        bysec[key] = bysec.get(key, 0) + 1
        bymne[mne] = bymne.get(mne, 0) + 1
    fixable = [b for b in bad if b[6]]
    unfix = [b for b in bad if not b[6]]
    print(f"FALSOS: {len(bad)} referencia(s) RIP-relative em `db` com seção alvo movida")
    for key in sorted(bysec):
        print(f"  alvo {key:12} {bysec[key]:4}x")
    print("  mnemonicos " + " ".join(f"{m}={n}" for m, n in
                                    sorted(bymne.items(), key=lambda kv: -kv[1])))
    print(f"  corrigiveis (label_<VA> existe) {len(fixable)} | "
          f"limite honesto (sem label) {len(unfix)}")
    for (va, tgt, key, ooff, new_va, mne, has) in bad[:40]:
        ns = f"0x{new_va:X}" if new_va is not None else "ausente"
        print(f"  VA 0x{va:X} {mne:8} -> congelado 0x{tgt:X} "
              f"({key}+0x{ooff:X}) correto {ns}"
              f"{'' if has else ' [sem label]'}")
    if len(bad) > 40:
        print(f"  ... +{len(bad) - 40}")
    # gate: so as corrigiveis bloqueiam; as sem label sao limite declarado
    return 1 if fixable else 0


if __name__ == '__main__':
    sys.exit(main())

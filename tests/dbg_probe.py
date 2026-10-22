#!/usr/bin/env python3
"""dbg_probe.py TARGET [--ref ORIG] [--timeout MS]

Sonda forense da D-19 fatia 2c: roda TARGET sob depurador (CreateProcessA com
DEBUG_ONLY_THIS_PROCESS + WaitForDebugEvent), sem injetar nada no alvo, e
relata a PRIMEIRA excecao de primeira-chance que nao seja breakpoint:

  * codigo da excecao, RIP, RSP e registradores de uso geral;
  * [AV] operacao (leitura/escrita/execucao) e endereco acessado;
  * secao+RVA do RIP no TARGET (via secdump) e o par (secao,offset) no --ref;
  * secao dos enderecos envolvidos (RIP, acesso, RSP), no TARGET e no --ref.

Saida deterministica; nao executa nada alem do alvo (fixture do corpus).
Sai 0 sempre que a sonda roda (o veredito e o que sai impresso), 2 em uso
incorreto e 3 se o alvo nao puder ser iniciado.
"""
import ctypes
import ctypes.wintypes as wt
import struct
import sys

import secdump

DEBUG_ONLY_THIS_PROCESS = 0x00000002
CREATE_NEW_CONSOLE = 0x00000010
STARTF_USESTDHANDLES = 0x00000100
EXCEPTION_DEBUG_EVENT = 1
CREATE_PROCESS_DEBUG_EVENT = 3
EXIT_PROCESS_DEBUG_EVENT = 5
LOAD_DLL_DEBUG_EVENT = 6
DBG_CONTINUE = 0x00010002
DBG_EXCEPTION_NOT_HANDLED = 0x80010001
CONTEXT_FLAGS = 0x0010001B          # CONTROL|INTEGER|SEGMENTS|FP|DEBUG
CONTEXT_SIZE = 1232                 # sizeof(CONTEXT) amd64
OFF_RSP, OFF_RIP = 152, 248
OFF_CONTEXT_FLAGS = 48
REGS = [("rax", 120), ("rcx", 128), ("rdx", 136), ("rbx", 144),
        ("rsp", 152), ("rbp", 160), ("rsi", 168), ("rdi", 176),
        ("r8", 184), ("r9", 192), ("r10", 200), ("r11", 208),
        ("r12", 216), ("r13", 224), ("r14", 232), ("r15", 240),
        ("rip", 248), ("eflags", 68)]
STACK_QWORDS = 32
STATUS = {
    0xC0000005: "ACCESS_VIOLATION", 0xC000001D: "ILLEGAL_INSTRUCTION",
    0xC0000094: "INT_DIVIDE_BY_ZERO", 0xC00000FD: "STACK_OVERFLOW",
    0xC0000135: "DLL_NOT_FOUND", 0xC0000142: "DLL_INIT_FAILED",
    0xC000007B: "INVALID_IMAGE_FORMAT", 0xC0000409: "STACK_BUFFER_OVERRUN",
    0x80000003: "BREAKPOINT", 0x80000004: "SINGLE_STEP",
    0x4000001F: "WOW64_SYSTEM", 0x40010006: "OUTPUT_DEBUG_STRING",
}


class STARTUPINFOA(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("cb", wt.DWORD), ("lpReserved", wt.LPSTR),
                ("lpDesktop", wt.LPSTR), ("lpTitle", wt.LPSTR),
                ("dwX", wt.DWORD), ("dwY", wt.DWORD),
                ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
                ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD),
                ("dwFillAttribute", wt.DWORD), ("dwFlags", wt.DWORD),
                ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
                ("lpReserved2", ctypes.POINTER(ctypes.c_ubyte)),
                ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
                ("hStdError", wt.HANDLE)]


class PROCESS_INFORMATION(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE),
                ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]


class EXCEPTION_RECORD(ctypes.Structure):
    _fields_ = [("ExceptionCode", wt.DWORD), ("ExceptionFlags", wt.DWORD),
                ("ExceptionRecord", ctypes.c_void_p),
                ("ExceptionAddress", ctypes.c_void_p),
                ("NumberParameters", wt.DWORD), ("__pad", wt.DWORD),
                ("ExceptionInformation", ctypes.c_ulonglong * 15)]


class EXCEPTION_DEBUG_INFO(ctypes.Structure):
    _fields_ = [("ExceptionRecord", EXCEPTION_RECORD),
                ("dwFirstChance", wt.DWORD)]


class CREATE_PROCESS_DEBUG_INFO(ctypes.Structure):
    _fields_ = [("hFile", wt.HANDLE), ("hProcess", wt.HANDLE),
                ("hThread", wt.HANDLE), ("lpBaseOfImage", ctypes.c_void_p),
                ("dwDebugInfoFileOffset", wt.DWORD),
                ("nDebugInfoSize", wt.DWORD),
                ("lpThreadLocalBase", ctypes.c_void_p),
                ("lpStartAddress", ctypes.c_void_p),
                ("lpImageName", ctypes.c_void_p), ("fUnicode", wt.WORD)]


class LOAD_DLL_DEBUG_INFO(ctypes.Structure):
    _fields_ = [("hFile", wt.HANDLE), ("lpBaseOfDll", ctypes.c_void_p),
                ("dwDebugInfoFileOffset", wt.DWORD),
                ("nDebugInfoSize", wt.DWORD),
                ("lpImageName", ctypes.c_void_p), ("fUnicode", wt.WORD)]


class EXIT_PROCESS_DEBUG_INFO(ctypes.Structure):
    _fields_ = [("dwExitCode", wt.DWORD)]


class _U(ctypes.Union):
    _fields_ = [("Exception", EXCEPTION_DEBUG_INFO),
                ("CreateProcessInfo", CREATE_PROCESS_DEBUG_INFO),
                ("LoadDll", LOAD_DLL_DEBUG_INFO),
                ("ExitProcess", EXIT_PROCESS_DEBUG_INFO),
                ("CreateThread", ctypes.c_ulonglong * 3),
                ("ExitThread", wt.DWORD),
                ("UnloadDll", ctypes.c_void_p),
                ("RipInfo", wt.DWORD * 3)]


# DEBUG_EVENT amd64 = 176 bytes (3 DWORDs + padding + union de 160 no offset 16)
class DEBUG_EVENT(ctypes.Structure):
    _fields_ = [("dwDebugEventCode", wt.DWORD), ("dwProcessId", wt.DWORD),
                ("dwThreadId", wt.DWORD), ("u", _U)]


k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.CreateProcessA.restype = wt.BOOL
k32.CreateProcessA.argtypes = [wt.LPCSTR, wt.LPSTR, ctypes.c_void_p,
                               ctypes.c_void_p, wt.BOOL, wt.DWORD,
                               ctypes.c_void_p, wt.LPCSTR,
                               ctypes.POINTER(STARTUPINFOA),
                               ctypes.POINTER(PROCESS_INFORMATION)]
k32.WaitForDebugEvent.argtypes = [ctypes.POINTER(DEBUG_EVENT), wt.DWORD]
k32.WaitForDebugEvent.restype = wt.BOOL
k32.ContinueDebugEvent.argtypes = [wt.DWORD, wt.DWORD, wt.DWORD]
k32.GetThreadContext.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.OpenThread.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenThread.restype = wt.HANDLE
k32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
k32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.DebugActiveProcessStop.argtypes = [wt.DWORD]
k32.CreateFileA.restype = wt.HANDLE
k32.CreateFileA.argtypes = [wt.LPCSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p,
                            wt.DWORD, wt.DWORD, wt.HANDLE]
k32.ReadProcessMemory.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                 ctypes.c_size_t,
                                 ctypes.POINTER(ctypes.c_size_t)]
k32.K32GetMappedFileNameA.restype = wt.DWORD
k32.K32GetMappedFileNameA.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.LPSTR,
                                     wt.DWORD]


def rd64(buf, off):
    return struct.unpack_from('<Q', buf, off)[0]


def read_ctx(thread):
    # GetThreadContext exige buffer alinhado a 16 (falha 87 se desalinhado)
    buf = ctypes.create_string_buffer(CONTEXT_SIZE + 16)
    addr = (ctypes.addressof(buf) + 15) & ~15
    ctypes.memset(addr, 0, CONTEXT_SIZE)
    ctypes.memmove(addr + OFF_CONTEXT_FLAGS,
                   struct.pack('<I', CONTEXT_FLAGS), 4)
    if not k32.GetThreadContext(thread, ctypes.c_void_p(addr)):
        raise OSError(ctypes.get_last_error(), "GetThreadContext")
    return ctypes.string_at(addr, CONTEXT_SIZE)


def describe_seen(seen):
    return " ".join(f"[t{t[0]}]0x{t[1]:08X}@0x{t[2]:X}"
                    f"{' 1st' if t[6] else ' 2nd'}" for t in seen)


def describe_mod(mods, va):
    best = None
    for (base, name) in mods:
        if base <= va and (best is None or base > best[0]):
            best = (base, name)
    if best is None:
        return None
    return f"{best[1]}+0x{va - best[0]:X}"


def describe(img, va, label):
    base = img['imagebase']
    if not base or va < base:
        return f"{label}=0x{va:X} (fora da imagem)"
    rva = va - base
    name, off = secdump.locate(img['secs'], rva)
    if name is None:
        return f"{label}=0x{va:X} rva=0x{rva:X} (fora de secao)"
    return f"{label}=0x{va:X} rva=0x{rva:X} {name}+0x{off:X}"


def probe(target, ref, timeout):
    img = secdump.load(target)
    timg = secdump.load(ref) if ref else None
    nul = k32.CreateFileA(b"NUL", 0xC0000000, 3, None, 3, 0x80, None)
    si = STARTUPINFOA()
    si.cb = ctypes.sizeof(STARTUPINFOA)
    si.dwFlags = STARTF_USESTDHANDLES
    si.hStdInput = si.hStdOutput = si.hStdError = nul
    pi = PROCESS_INFORMATION()
    cmd = ctypes.create_string_buffer(target.encode('mbcs'))
    flags = DEBUG_ONLY_THIS_PROCESS | CREATE_NEW_CONSOLE
    ok = k32.CreateProcessA(None, cmd, None, None, True, flags, None,
                            None, ctypes.byref(si), ctypes.byref(pi))
    k32.CloseHandle(nul)
    if not ok:
        err = ctypes.get_last_error()
        print(f"ALVO {target}: CreateProcessA falhou (erro {err})")
        return 3
    print(f"ALVO {target}")
    ev = DEBUG_EVENT()
    seen = []
    mods = []
    module_base = img['imagebase']
    exit_code = None
    while True:
        if not k32.WaitForDebugEvent(ctypes.byref(ev), timeout):
            err = ctypes.get_last_error()
            k32.TerminateProcess(pi.hProcess, 0xDEAD)
            print(f"SEM EVENTO apos {timeout} ms (erro {err}) -> terminado")
            exit_code = 0xDEAD
            break
        code = ev.dwDebugEventCode
        if code == CREATE_PROCESS_DEBUG_EVENT:
            hfile = ev.u.CreateProcessInfo.hFile
            if hfile:
                k32.CloseHandle(hfile)
            base = ev.u.CreateProcessInfo.lpBaseOfImage or 0
            if base:
                module_base = base
        elif code == LOAD_DLL_DEBUG_EVENT:
            hfile = ev.u.LoadDll.hFile
            if hfile:
                k32.CloseHandle(hfile)
            dbase = ev.u.LoadDll.lpBaseOfDll or 0
            if dbase:
                buf = ctypes.create_string_buffer(512)
                n = k32.K32GetMappedFileNameA(pi.hProcess,
                                           ctypes.c_void_p(dbase), buf,
                                           len(buf))
                dname = (buf.raw[:n].decode('latin1') if n else "?")
                dname = dname.rsplit('\\', 1)[-1]
                mods.append((dbase, dname))
        elif code == EXCEPTION_DEBUG_EVENT:
            rec = ev.u.Exception.ExceptionRecord
            exc_code = rec.ExceptionCode & 0xFFFFFFFF
            exc_addr = rec.ExceptionAddress or 0
            nparams = rec.NumberParameters
            info = [rec.ExceptionInformation[i] for i in range(min(nparams, 2))]
            if exc_code not in (0x80000003, 0x80000004,
                                0x40010006, 0x4000001F):
                th = k32.OpenThread(0x0008, False, ev.dwThreadId)  # GET_CONTEXT
                ctx = read_ctx(th) if th else None
                if th:
                    k32.CloseHandle(th)
                stack = []
                if ctx:
                    sp = rd64(ctx, OFF_RSP)
                    buf = ctypes.create_string_buffer(8 * STACK_QWORDS)
                    got = ctypes.c_size_t(0)
                    if k32.ReadProcessMemory(pi.hProcess, ctypes.c_void_p(sp),
                                             buf, len(buf.raw),
                                             ctypes.byref(got)):
                        stack = [rd64(buf.raw, 8 * i)
                                 for i in range(got.value // 8)]
                seen.append((ev.dwThreadId, exc_code, exc_addr, info, ctx,
                             stack, ev.u.Exception.dwFirstChance))
            if exc_code == 0x80000003 and exc_addr in (module_base, 0x7FFE0000):
                # breakpoint inicial do loader: continua
                k32.ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId,
                                       DBG_CONTINUE)
                continue
            k32.ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId,
                                   DBG_EXCEPTION_NOT_HANDLED)
            continue
        elif code == EXIT_PROCESS_DEBUG_EVENT:
            exit_code = ev.u.ExitProcess.dwExitCode
            k32.ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, DBG_CONTINUE)
            break
        k32.ContinueDebugEvent(ev.dwProcessId, ev.dwThreadId, DBG_CONTINUE)

    if exit_code is None:
        k32.DebugActiveProcessStop(pi.dwProcessId)
        dword = wt.DWORD(0)
        k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(dword))
        exit_code = dword.value
    k32.CloseHandle(pi.hThread)
    k32.CloseHandle(pi.hProcess)

    signed = exit_code - 0x100000000 if exit_code >= 0x80000000 else exit_code
    print(f"EXIT 0x{exit_code:08X} ({signed})")
    # Uma excecao TRATADA (ex.: C++ EH 0x20474343) nao e achado: o status de
    # saida do processo e o codigo da excecao que ficou sem handler. So essa
    # vira o achado ("fatal"); as demais sao listadas como tratadas.
    fatal = None
    if exit_code >= 0x80000000:
        hits = [e for e in seen if e[1] == exit_code]
        # a excecao fatal e a de 2a chance (sem handler); senao, a ultima
        fatal = ([e for e in hits if not e[6]] or hits or [None])[-1]
        if fatal is None and seen:
            fatal = seen[-1]
    if fatal is None:
        extra = f" ({len(seen)} primeira-chance tratada(s))" if seen else ""
        print("SEM EXCECAO FATAL" + extra)
        if seen:
            print("EXCS " + describe_seen(seen))
        return 0

    tid, exc_code, exc_addr, info, ctx, stack, _ = fatal
    print(f"EXC  0x{exc_code:08X} {STATUS.get(exc_code, '?')} "
          f"em 0x{exc_addr:X} [t{tid}]")
    base = module_base or img['imagebase']
    img['imagebase'] = base
    print("RIP  " + describe(img, exc_addr, "rip") +
          (f" [{describe_mod(mods, exc_addr)}]"
           if describe_mod(mods, exc_addr) else ""))
    if exc_code == 0xC0000005 and info:
        op = {0: "leitura", 1: "escrita", 8: "execucao"}.get(info[0],
                                                             f"op={info[0]}")
        acc = info[1]
        print(f"AV   {op} em 0x{acc:X} (" + describe(img, acc, "acesso")[7:] + ")")
        if timg:
            tbase = timg['imagebase']
            if acc >= tbase:
                rva = acc - tbase
                on, oo = secdump.locate(timg['secs'], rva)
                print(f"REF  acesso no ORIG: rva=0x{rva:X} "
                      f"{on}+0x{oo:X}" if on else
                      f"REF  acesso rva=0x{rva:X} fora de secao do ORIG")
            else:
                print("REF  acesso nao e VA de imagem do ORIG")
    if ctx:
        vals = {n: rd64(ctx, o) for n, o in REGS}
        print("REGS " + " ".join(f"{n}=0x{vals[n]:X}" for n, _ in REGS))
        print("RSP  " + describe(img, vals['rsp'], "rsp"))
        for i, q in enumerate(stack):
            extra = describe_mod(mods, q)
            print(f"STACK+{i * 8:02X} " + describe(img, q, "q") +
                  (f" [{extra}]" if extra else ""))
        if timg and exc_addr >= timg['imagebase']:
            rva = exc_addr - timg['imagebase']
            on, oo = secdump.locate(timg['secs'], rva)
            if on:
                print(f"REF  RIP no ORIG: rva=0x{rva:X} {on}+0x{oo:X}")
    if len(seen) > 1:
        print("EXCS " + describe_seen(seen))
    return 0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    target, ref, timeout = args[0], None, 20000
    i = 1
    while i < len(args):
        if args[i] == '--ref' and i + 1 < len(args):
            ref = args[i + 1]
            i += 2
        elif args[i] == '--timeout' and i + 1 < len(args):
            timeout = int(args[i + 1])
            i += 2
        else:
            print(f"argumento desconhecido: {args[i]}")
            return 2
    return probe(target, ref, timeout)


if __name__ == '__main__':
    sys.exit(main())

// tests/exc_cpp.cpp — fixture de exceção REAL (R-5.4 F4, SEH/unwind).
//
// O quê: programa C++ com exceção lançada no fundo de uma recursão NÃO-tail e
//   capturada em main. Cada frame empilhado tem um objeto com destrutor não
//   trivial, então o desenrolar (unwind) do Windows precisa percorrer os
//   RUNTIME_FUNCTION/UNWIND_INFO reais da .pdata/.xdata para rodar os
//   destrutores e achar o handler (__CxxFrameHandler3).
// Por quê: prova que a .pdata/.xdata reemitida pelo Dexter é funcional:
//   se o unwind estiver errado, ou o processo aborta ou o contador de
//   limpezas não fecha -> exit != 42.
// Contrato: exit 42 se caught==7 && cleanups==DEPTH; exit 1 caso contrário.
// Como testar: compilar e rodar (deve imprimir "caught=7 cleanups=6" e sair 42).
//
// Build do fixture (MinGW-w64 g++, SEH x64; binário versionado tests/exc.exe):
//   g++ -O1 -o tests/exc.exe tests/exc_cpp.cpp
#include <cstdio>

static int g_cleanups = 0;

struct Guard {
    ~Guard() { ++g_cleanups; }   // efeito colateral: nunca elidido
};

// Recursão NÃO-tail: força DEPTH+1 frames distintos, cada um com um Guard.
static int depth(int x) {
    Guard g;
    if (x <= 0) {
        throw 7;                 // lança no frame mais profundo
    }
    int r = depth(x - 1);
    return r + 1;                // impede otimização para loop (não-tail)
}

static const int DEPTH = 5;

int main() {
    int caught = 0;
    try {
        depth(DEPTH);
    } catch (int e) {
        caught = e;
    }
    std::printf("caught=%d cleanups=%d\n", caught, g_cleanups);
    return (caught == 7 && g_cleanups == DEPTH + 1) ? 42 : 1;
}

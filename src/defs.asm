; =============================================================================
; Definiciones - constantes y macros que usan todos los módulos
; =============================================================================

; ---- números de syscall de Linux x86-64 (sacados de la tabla de syscalls) ----
SYS_READ            equ 0
SYS_WRITE           equ 1
SYS_MMAP            equ 9
SYS_MUNMAP          equ 11
SYS_RT_SIGACTION    equ 13
SYS_RT_SIGRETURN    equ 15
SYS_MADVISE         equ 28
SYS_NANOSLEEP       equ 35
SYS_EXIT            equ 60
SYS_SYSINFO         equ 99
SYS_IOPL            equ 172
SYS_IOPERM          equ 173
SYS_CLOCK_GETTIME   equ 228

STDIN               equ 0
STDOUT              equ 1

; ---- banderas de mmap / madvise / clock_gettime ----
PROT_RW             equ 0x3             ; PROT_READ | PROT_WRITE
MAP_ANON_PRIV       equ 0x22            ; MAP_PRIVATE | MAP_ANONYMOUS
MAP_POPULATE        equ 0x8000          ; que la memoria ya venga lista desde el inicio
MADV_HUGEPAGE       equ 14              ; pedimos páginas grandes para medir mejor la RAM
CLOCK_MONOTONIC     equ 1

; ---- señales (las usa el módulo 2) ----
SIGSEGV             equ 11
SA_SIGINFO          equ 0x4
SA_RESTORER         equ 0x04000000
UC_RIP              equ 168             ; dónde guarda Linux la instrucción en la que íbamos

; ---- bits de cpu_flags (los llena cpu_detect en el módulo 1) ----
CF_SSE2             equ 0
CF_AVX              equ 1               ; solo se prende si el CPU Y el SO lo soportan
CF_AVX2             equ 2
CF_AVX512           equ 3

; ---- macros ----
; PRINT etiqueta -> imprime el string (terminado en 0) que está en esa etiqueta
%macro PRINT 1
    lea     rdi, [rel %1]
    call    print_str
%endmacro

; TSC_START: lee el contador de ciclos (en RAX) al empezar a medir. Los LFENCE
; son para que el CPU no se adelante ni se atrase con otras instrucciones.
%macro TSC_START 0
    lfence
    rdtsc
    lfence
    shl     rdx, 32
    or      rax, rdx
%endmacro

; TSC_STOP: lee el contador al terminar. RDTSCP espera a que acabe todo lo
; de antes, así la medición sale justa.
%macro TSC_STOP 0
    rdtscp
    lfence
    shl     rdx, 32
    or      rax, rdx
%endmacro

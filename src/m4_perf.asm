; =============================================================================
; Módulo 4 - Monitor de rendimiento del CPU
; Ponemos al procesador a hacer tres tipos de trabajo, medimos cuánto se
; tarda y con eso sacamos los ciclos, el CPI, el IPC y los GFLOPS.
; =============================================================================

PERF_ITER   equ 10000000                ; vueltas de cada carga
FLOP_PER_IT equ 16                      ; 8 operaciones x 2 números cada una

section .data
    m4_title    db 10, "=== Módulo 4: Monitor de rendimiento del CPU ===", 10, 0
    s_freq      db "Frecuencia (TSC):  ", 0
    s_ghz_tsc   db " GHz (calibrada con clock_gettime)", 10, 0
    s_load_a    db 10, "Carga A  (ALU independiente)  ", 0
    s_load_b    db "Carga B  (cadena de imul)     ", 0
    s_load_c    db "Carga C  (SSE2 punto flotante)", 0
    s_pl_cyc    db " ciclos ", 0
    s_pl_ins    db "  instr ", 0
    s_pl_cpi    db "  CPI ", 0
    s_pl_ipc    db "  IPC ", 0
    s_tot_cyc   db 10, "Ciclos totales:    ", 0
    s_tot_ins   db "Instrucciones:     ", 0
    s_cpi_avg   db "CPI promedio:      ", 0
    s_ipc_avg   db "IPC:               ", 0
    s_src       db "Fuente:            ciclos del TSC + instrucciones contadas en el código", 10, 0
    s_tput      db "Throughput:        ", 0
    s_gflops_nl db " GFLOPS (SSE2, doble precisión)", 10, 0

    alignb 16
    f64_one2    dq 1.0, 1.0
    f64_tiny2   dq 1.0e-9, 1.0e-9
    ts_sleep    dq 0, 50000000          ; 0 s + 50 000 000 ns = 50 ms

section .bss
    tsc_hz      resq 1                  ; ticks del TSC por segundo
    ts0         resq 2                  ; hora: {segundos, nanosegundos}
    ts1         resq 2

section .text

; -----------------------------------------------------------------------------
; tsc_calibrate: contamos cuántos ciclos pasan en 50 ms y con eso sabemos
; la frecuencia (tsc_hz). Se llama una vez al inicio del programa.
; -----------------------------------------------------------------------------
tsc_calibrate:
    push    rbx
    push    r12

    mov     eax, SYS_CLOCK_GETTIME
    mov     edi, CLOCK_MONOTONIC
    lea     rsi, [rel ts0]
    syscall
    TSC_START
    mov     rbx, rax

    mov     eax, SYS_NANOSLEEP          ; nos dormimos 50 ms
    lea     rdi, [rel ts_sleep]
    xor     esi, esi
    syscall

    TSC_STOP
    mov     r12, rax
    mov     eax, SYS_CLOCK_GETTIME
    mov     edi, CLOCK_MONOTONIC
    lea     rsi, [rel ts1]
    syscall

    ; ns transcurridos = (s1 - s0) * 1e9 + (ns1 - ns0)
    mov     rax, [rel ts1]
    sub     rax, [rel ts0]
    imul    rax, rax, 1000000000
    add     rax, [rel ts1 + 8]
    sub     rax, [rel ts0 + 8]
    mov     rcx, rax
    ; hz = ticks * 1e9 / ns
    mov     rax, r12
    sub     rax, rbx
    mov     edx, 1000000000
    mul     rdx
    div     rcx
    mov     [rel tsc_hz], rax

    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Cargas de trabajo: los 3 tipos de trabajo que medimos
; -----------------------------------------------------------------------------

; A: 6 add independientes + dec + jnz = 8 instrucciones por vuelta
work_alu:
    mov     ecx, PERF_ITER
    xor     eax, eax
.loop:
    add     rax, 1
    add     rdx, 1
    add     rsi, 1
    add     rdi, 1
    add     r8, 1
    add     r9, 1
    dec     rcx
    jnz     .loop
    ret

; B: 4 multiplicaciones donde cada una espera a la anterior + dec + jnz
;    = 6 instrucciones por vuelta
work_dep:
    mov     ecx, PERF_ITER
    mov     eax, 3
.loop:
    imul    rax, rax
    imul    rax, rax
    imul    rax, rax
    imul    rax, rax
    dec     rcx
    jnz     .loop
    ret

; C: 4 multiplicaciones + 4 sumas con decimales (2 números cada una) + dec + jnz
;    = 10 instrucciones y 16 operaciones de punto flotante por vuelta
; (multiplicamos por 1.0 y sumamos 1e-9 para que no se desborde nunca)
work_flops:
    movapd  xmm8, [rel f64_one2]
    movapd  xmm9, [rel f64_tiny2]
    movapd  xmm0, xmm8
    movapd  xmm1, xmm8
    movapd  xmm2, xmm8
    movapd  xmm3, xmm8
    xorpd   xmm4, xmm4
    xorpd   xmm5, xmm5
    xorpd   xmm6, xmm6
    xorpd   xmm7, xmm7
    mov     ecx, PERF_ITER
.loop:
    mulpd   xmm0, xmm8
    mulpd   xmm1, xmm8
    mulpd   xmm2, xmm8
    mulpd   xmm3, xmm8
    addpd   xmm4, xmm9
    addpd   xmm5, xmm9
    addpd   xmm6, xmm9
    addpd   xmm7, xmm9
    dec     ecx
    jnz     .loop
    ret

; perf_line: RDI = ciclos, RSI = instrucciones. Imprime ciclos, instr, CPI, IPC.
perf_line:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    PRINT   s_pl_cyc
    mov     rdi, rbx
    call    print_u64
    PRINT   s_pl_ins
    mov     rdi, r12
    call    print_u64
    PRINT   s_pl_cpi
    mov     rdi, rbx
    mov     rsi, r12
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    PRINT   s_pl_ipc
    mov     rdi, r12
    mov     rsi, rbx
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    call    print_nl
    pop     r12
    pop     rbx
    ret

; PERF_CASE etiqueta, rutina, instrucciones: mide cuántos ciclos tarda la rutina
; y va sumando los totales en R13 (ciclos) y R14 (instrucciones).
%macro PERF_CASE 3
    PRINT   %1
    TSC_START
    mov     r12, rax
    call    %2
    TSC_STOP
    sub     rax, r12
    mov     r15, rax
    add     r13, rax
    add     r14, %3
    mov     rdi, rax
    mov     esi, %3
    call    perf_line
%endmacro

; -----------------------------------------------------------------------------
; mod_perf: reporte del módulo 4
; -----------------------------------------------------------------------------
mod_perf:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    PRINT   m4_title

    PRINT   s_freq
    mov     rdi, [rel tsc_hz]
    mov     esi, 1000000000
    call    ratio_x100                  ; GHz x 100
    mov     rdi, rax
    call    print_fix2
    PRINT   s_ghz_tsc

    xor     r13d, r13d                  ; ciclos totales
    xor     r14d, r14d                  ; instrucciones totales
    PERF_CASE s_load_a, work_alu,   8 * PERF_ITER
    PERF_CASE s_load_b, work_dep,   6 * PERF_ITER
    PERF_CASE s_load_c, work_flops, 10 * PERF_ITER   ; R15 queda con los ciclos de C

    PRINT   s_tot_cyc
    mov     rdi, r13
    call    print_u64
    call    print_nl
    PRINT   s_tot_ins
    mov     rdi, r14
    call    print_u64
    call    print_nl
    PRINT   s_cpi_avg
    mov     rdi, r13
    mov     rsi, r14
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    call    print_nl
    PRINT   s_ipc_avg
    mov     rdi, r14
    mov     rsi, r13
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    call    print_nl
    PRINT   s_src

    ; GFLOPS = FLOP / ns
    PRINT   s_tput
    mov     rdi, r15
    call    cycles_to_ns
    mov     rsi, rax
    mov     edi, FLOP_PER_IT * PERF_ITER
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    PRINT   s_gflops_nl

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

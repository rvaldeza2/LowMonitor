; =============================================================================
; Módulo 6 - Operaciones SIMD (bonus)
; Hacemos sumas, multiplicaciones y comparaciones con varios números a la
; vez (SSE2, AVX2 y AVX-512) y vemos cuánto más rápido sale.
; =============================================================================

SIMD_N      equ 2048                    ; floats por arreglo
SIMD_REPS   equ 20000
SIMD_FLOPS  equ 2 * SIMD_N * SIMD_REPS  ; 1 suma + 1 multiplicación por elemento

section .data
    m6_title    db 10, "=== Módulo 6: Operaciones SIMD (bonus) ===", 10, 0
    s_sse2_en   db "SSE2 habilitado:     ", 0
    s_avx2_en   db "AVX2 habilitado:     ", 0
    s_a512_en   db "AVX-512 habilitado:  ", 0
    s_isa_sse   db 10, "[SSE2]    registros XMM de 128 bits", 10, 0
    s_isa_avx2  db 10, "[AVX2]    registros YMM de 256 bits", 10, 0
    s_isa_a512  db 10, "[AVX-512] registros ZMM de 512 bits", 10, 0
    s_isa_na    db "          no disponible (CPU o sistema operativo sin soporte)", 10, 0
    s_lanes     db "          Throughput:          ", 0
    s_lanes2    db " operaciones paralelas (float 32 bits)", 10, 0
    s_bench     db "          Benchmark (a+b)*b:   ", 0
    s_gflops    db " GFLOPS", 10, 0
    s_verif     db "          Verificación:        ", 0
    s_v_ok      db "correcta (coincide con el cálculo escalar)", 10, 0
    s_v_bad     db " elementos distintos", 10, 0
    s_cmp       db "          Comparación a > b:   ", 0
    s_cmp2      db " de 2048 (esperado 2045)", 10, 0
    s_speedup   db "          Aceleración vs SSE2: ", 0
    s_x_nl      db "x", 10, 0

    f32_two     dd 2.0

section .bss
    alignb 64                           ; AVX-512 pide que los datos empiecen en múltiplo de 64
    va          resd SIMD_N
    vb          resd SIMD_N
    vc          resd SIMD_N

section .text

; a[i] = i, b[i] = 2.0
simd_init:
    lea     r8, [rel va]
    lea     r9, [rel vb]
    mov     eax, 0x40000000             ; así se escribe 2.0 en binario
    xor     ecx, ecx
.loop:
    cvtsi2ss xmm0, ecx
    movss   [r8 + rcx*4], xmm0
    mov     [r9 + rcx*4], eax
    inc     ecx
    cmp     ecx, SIMD_N
    jb      .loop
    ret

; limpiamos c para que una corrida no "herede" el resultado de la otra
simd_clear:
    lea     rdi, [rel vc]
    xor     eax, eax
    mov     ecx, SIMD_N
    rep stosd
    ret

; simd_check -> EAX = cuántos c[i] no son (i + 2) * 2 (calculado escalar)
simd_check:
    lea     r10, [rel vc]
    movss   xmm2, [rel f32_two]
    xor     eax, eax
    xor     ecx, ecx
.loop:
    cvtsi2ss xmm0, ecx
    addss   xmm0, xmm2
    mulss   xmm0, xmm2
    ucomiss xmm0, [r10 + rcx*4]
    jp      .bad                        ; NaN también cuenta como malo
    je      .ok
.bad:
    inc     eax
.ok:
    inc     ecx
    cmp     ecx, SIMD_N
    jb      .loop
    ret

; --- núcleos: c = (a + b) * b, repetido SIMD_REPS veces ---------------------
; Procesamos 2 registros por vuelta para que el CPU tenga trabajo en paralelo.
%macro SIMD_KERNEL_SETUP 0
    lea     r8, [rel va]
    lea     r9, [rel vb]
    lea     r10, [rel vc]
    mov     r11d, SIMD_REPS
%endmacro

; versión SSE2: 4 números por registro
simd_sse_kernel:
    SIMD_KERNEL_SETUP
.rep:
    xor     ecx, ecx
.loop:
    movaps  xmm0, [r8 + rcx]
    movaps  xmm1, [r8 + rcx + 16]
    addps   xmm0, [r9 + rcx]
    addps   xmm1, [r9 + rcx + 16]
    mulps   xmm0, [r9 + rcx]
    mulps   xmm1, [r9 + rcx + 16]
    movaps  [r10 + rcx], xmm0
    movaps  [r10 + rcx + 16], xmm1
    add     rcx, 32
    cmp     rcx, SIMD_N * 4
    jb      .loop
    dec     r11d
    jnz     .rep
    ret

; AVX2 (8 números) y AVX-512 (16 números) se escriben igual, solo cambia el
; tamaño del registro, así que salen de la misma macro: nombre, ymm|zmm, bytes
%macro SIMD_VEX_KERNEL 3
%1:
    SIMD_KERNEL_SETUP
%%rep:
    xor     ecx, ecx
%%loop:
    vmovaps %{2}0, [r8 + rcx]
    vmovaps %{2}1, [r8 + rcx + %3]
    vaddps  %{2}0, %{2}0, [r9 + rcx]
    vaddps  %{2}1, %{2}1, [r9 + rcx + %3]
    vmulps  %{2}0, %{2}0, [r9 + rcx]
    vmulps  %{2}1, %{2}1, [r9 + rcx + %3]
    vmovaps [r10 + rcx], %{2}0
    vmovaps [r10 + rcx + %3], %{2}1
    add     rcx, 2 * %3
    cmp     rcx, SIMD_N * 4
    jb      %%loop
    dec     r11d
    jnz     %%rep
    vzeroupper                          ; limpiamos para que SSE no se ponga lento después
    ret
%endmacro

    SIMD_VEX_KERNEL simd_avx2_kernel,   ymm, 32
    SIMD_VEX_KERNEL simd_avx512_kernel, zmm, 64

; --- comparación vectorial: EAX = cuántos i cumplen a[i] > b[i] -------------
simd_sse_cmp:
    lea     r8, [rel va]
    lea     r9, [rel vb]
    xor     eax, eax
    xor     ecx, ecx
.loop:
    movaps  xmm0, [r9 + rcx]
    cmpltps xmm0, [r8 + rcx]            ; compara 4 a la vez: donde a > b queda en 1
    movmskps edx, xmm0                  ; juntamos los 4 resultados en 4 bits
    popcnt  edx, edx
    add     eax, edx
    add     rcx, 16
    cmp     rcx, SIMD_N * 4
    jb      .loop
    ret

simd_avx2_cmp:
    lea     r8, [rel va]
    lea     r9, [rel vb]
    xor     eax, eax
    xor     ecx, ecx
.loop:
    vmovaps ymm0, [r8 + rcx]
    vcmpps  ymm0, ymm0, [r9 + rcx], 0x1E ; 0x1E = "mayor que"
    vmovmskps edx, ymm0
    popcnt  edx, edx
    add     eax, edx
    add     rcx, 32
    cmp     rcx, SIMD_N * 4
    jb      .loop
    vzeroupper
    ret

simd_avx512_cmp:
    lea     r8, [rel va]
    lea     r9, [rel vb]
    xor     eax, eax
    xor     ecx, ecx
.loop:
    vmovaps zmm0, [r8 + rcx]
    vcmpps  k1, zmm0, [r9 + rcx], 0x1E  ; en AVX-512 el resultado queda en k1
    kmovw   edx, k1
    popcnt  edx, edx
    add     eax, edx
    add     rcx, 64
    cmp     rcx, SIMD_N * 4
    jb      .loop
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; simd_case: RDI = núcleo, RSI = comparación, EDX = carriles.
; Lo corre, lo mide, lo verifica e imprime. RAX = ciclos del núcleo.
; -----------------------------------------------------------------------------
simd_case:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx

    PRINT   s_lanes
    mov     edi, r13d
    call    print_u64
    PRINT   s_lanes2

    call    simd_clear
    call    rbx                         ; una corrida de calentamiento
    TSC_START
    mov     r14, rax
    call    rbx                         ; esta es la que medimos
    TSC_STOP
    sub     rax, r14
    mov     r14, rax

    PRINT   s_bench                     ; GFLOPS = FLOP / ns
    mov     rdi, r14
    call    cycles_to_ns
    mov     rsi, rax
    mov     edi, SIMD_FLOPS
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    PRINT   s_gflops

    PRINT   s_verif
    call    simd_check
    test    eax, eax
    jnz     .verif_bad
    PRINT   s_v_ok
    jmp     .compare
.verif_bad:
    mov     edi, eax
    call    print_u64
    PRINT   s_v_bad

.compare:
    PRINT   s_cmp
    call    r12
    mov     edi, eax
    call    print_u64
    PRINT   s_cmp2

    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; SIMD_SPEEDUP: RAX = ciclos de esta versión, R12 = ciclos de SSE2
%macro SIMD_SPEEDUP 0
    mov     rbx, rax                    ; PRINT pisa RDI/RSI, lo guardamos
    PRINT   s_speedup
    mov     rdi, r12
    mov     rsi, rbx
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    PRINT   s_x_nl
%endmacro

; PRINT_FLAG etiqueta, bit: imprime "etiqueta Sí/No\n" según cpu_flags
%macro PRINT_FLAG 2
    PRINT   %1
    mov     edi, [rel cpu_flags]
    shr     edi, %2
    and     edi, 1
    call    print_yesno
    call    print_nl
%endmacro

; -----------------------------------------------------------------------------
; mod_simd: reporte del módulo 6
; -----------------------------------------------------------------------------
mod_simd:
    push    rbx
    push    r12
    PRINT   m6_title
    PRINT_FLAG s_sse2_en, CF_SSE2
    PRINT_FLAG s_avx2_en, CF_AVX2
    PRINT_FLAG s_a512_en, CF_AVX512

    call    simd_init

    ; SSE2 es parte de x86-64, siempre está
    PRINT   s_isa_sse
    lea     rdi, [rel simd_sse_kernel]
    lea     rsi, [rel simd_sse_cmp]
    mov     edx, 4
    call    simd_case
    mov     r12, rax

    PRINT   s_isa_avx2
    bt      dword [rel cpu_flags], CF_AVX2
    jnc     .no_avx2
    lea     rdi, [rel simd_avx2_kernel]
    lea     rsi, [rel simd_avx2_cmp]
    mov     edx, 8
    call    simd_case
    SIMD_SPEEDUP
    jmp     .avx512
.no_avx2:
    PRINT   s_isa_na

.avx512:
    PRINT   s_isa_a512
    bt      dword [rel cpu_flags], CF_AVX512
    jnc     .no_avx512
    lea     rdi, [rel simd_avx512_kernel]
    lea     rsi, [rel simd_avx512_cmp]
    mov     edx, 16
    call    simd_case
    SIMD_SPEEDUP
    jmp     .out
.no_avx512:
    PRINT   s_isa_na
.out:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; Módulo 3 - Diagnóstico de memoria
; Llenamos un pedazo de RAM con patrones conocidos (0xAA, 0x55 y una
; secuencia), lo volvemos a leer y contamos cuántos bits salieron mal.
; =============================================================================

MEM_TEST_SIZE   equ 64 * 1024 * 1024   ; 64 MB

section .data
    m3_title    db 10, "=== Módulo 3: Diagnóstico de memoria ===", 10, 0
    s_memtotal  db "Memoria total:     ", 0
    s_detected  db " detectada", 10, 0
    s_memfree   db "Memoria libre:     ", 0
    s_region    db "Región de prueba:  ", 0
    s_at        db " en 0x", 0
    s_pat_aa    db "Patrón 0xAA:       ", 0
    s_pat_55    db "Patrón 0x55:       ", 0
    s_pat_inc   db "Secuencia incr.:   ", 0
    s_pass      db "PASADA (0 bits erróneos)", 0
    s_fail      db "FALLIDA (", 0
    s_fail2     db " bits erróneos)", 0
    s_wbw       db "   escritura NT ", 0
    s_rbw       db " GB/s, lectura ", 0
    s_gbs_nl    db " GB/s", 10, 0
    s_selftest  db "Autoprueba:        1 bit invertido a propósito -> ", 0
    s_st_ok     db " bit(s) detectado(s)   [detector OK]", 10, 0
    s_st_bad    db " bit(s) detectado(s)   [detector FALLÓ]", 10, 0
    s_err_mmap  db "no se pudo reservar memoria con mmap", 0
    s_err_sysinfo db "sysinfo falló", 0

    ; tabla de patrones: etiqueta, valor inicial, paso
    pat_table   dq s_pat_aa,  0xAAAAAAAAAAAAAAAA, 0
                dq s_pat_55,  0x5555555555555555, 0
                dq s_pat_inc, 0, 1
    pat_end:

section .bss
    sysinfo_buf resb 128                ; struct sysinfo

section .text

; -----------------------------------------------------------------------------
; mem_fill: RDI = dirección, RSI = valor inicial, RDX = paso
; Llena todo el bloque con el patrón, escribiendo 16 bytes por vuelta.
; -----------------------------------------------------------------------------
mem_fill:
    movq        xmm0, rsi
    lea         rax, [rsi + rdx]
    movq        xmm2, rax
    punpcklqdq  xmm0, xmm2              ; XMM0 = [v, v+paso]
    lea         rax, [rdx * 2]
    movq        xmm1, rax
    punpcklqdq  xmm1, xmm1              ; XMM1 = [2*paso, 2*paso]
    mov         ecx, MEM_TEST_SIZE / 16
.loop:
    movntdq     [rdi], xmm0             ; 16 bytes directo a la RAM (sin pasar por caché)
    paddq       xmm0, xmm1
    add         rdi, 16
    dec         ecx
    jnz         .loop
    sfence                              ; esperamos a que todo termine de escribirse
    ret

; -----------------------------------------------------------------------------
; mem_verify: RDI = dirección, RSI = valor inicial, RDX = paso -> RAX = bits malos
; Revisamos 8 valores por vuelta y vamos pidiendo de una vez los datos que
; vienen adelante, para no estar esperando a la RAM.
; -----------------------------------------------------------------------------
mem_verify:
    xor         eax, eax
    mov         ecx, MEM_TEST_SIZE / 64
.loop:
    prefetcht0  [rdi + 1024]
%rep 8
    mov         r8, [rdi]
    xor         r8, rsi                 ; los bits distintos quedan en 1
    popcnt      r8, r8
    add         rax, r8
    add         rsi, rdx                ; siguiente valor esperado
    add         rdi, 8
%endrep
    dec         ecx
    jnz         .loop
    ret

; print_gbs: RDI = ciclos que tardó en pasar MEM_TEST_SIZE bytes -> imprime GB/s
; (bytes / ns = GB/s)
print_gbs:
    call    cycles_to_ns
    mov     rsi, rax
    mov     edi, MEM_TEST_SIZE
    call    ratio_x100
    mov     rdi, rax
    jmp     print_fix2

; mem_report: RDI = bits malos, RSI = ciclos escritura, RDX = ciclos lectura
mem_report:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    test    rbx, rbx
    jnz     .fail
    PRINT   s_pass
    jmp     .bandwidth
.fail:
    PRINT   s_fail
    mov     rdi, rbx
    call    print_u64
    PRINT   s_fail2
.bandwidth:
    PRINT   s_wbw
    mov     rdi, r12
    call    print_gbs
    PRINT   s_rbw
    mov     rdi, r13
    call    print_gbs
    PRINT   s_gbs_nl
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; mod_mem: reporte del módulo 3
;   R12 = base del bloque, R15 = fila de la tabla de patrones
; -----------------------------------------------------------------------------
mod_mem:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    PRINT   m3_title

    ; --- memoria total y libre con sysinfo ---
    ; sysinfo nos llena el buffer con la RAM total y la libre
    mov     eax, SYS_SYSINFO
    lea     rdi, [rel sysinfo_buf]
    syscall
    test    rax, rax
    jns     .sysinfo_ok
    lea     rdi, [rel s_err_sysinfo]
    mov     rsi, rax
    call    err_report
    jmp     .alloc
.sysinfo_ok:
    PRINT   s_memtotal
    mov     eax, [rel sysinfo_buf + 104]
    mov     rdi, [rel sysinfo_buf + 32]
    imul    rdi, rax                    ; lo pasamos a bytes
    call    print_size
    PRINT   s_detected
    PRINT   s_memfree
    mov     eax, [rel sysinfo_buf + 104]
    mov     rdi, [rel sysinfo_buf + 40]
    imul    rdi, rax
    call    print_size
    call    print_nl

    ; --- pedimos el bloque de prueba ---
.alloc:
    mov     edi, MEM_TEST_SIZE
    mov     esi, MAP_POPULATE
    call    mem_alloc
    cmp     rax, -4095                  ; entre -4095 y -1 es un error
    jae     .mmap_fail
    mov     r12, rax

    PRINT   s_region
    mov     edi, MEM_TEST_SIZE
    call    print_size
    PRINT   s_at
    mov     rdi, r12
    mov     esi, 12
    call    print_hex
    call    print_nl

    ; --- los 3 patrones: escribir, verificar y medir con el TSC ---
    lea     r15, [rel pat_table]
.pattern:
    mov     rdi, [r15]
    call    print_str
    TSC_START
    mov     r13, rax
    mov     rdi, r12
    mov     rsi, [r15 + 8]
    mov     rdx, [r15 + 16]
    call    mem_fill
    TSC_STOP
    sub     rax, r13
    mov     r13, rax                    ; R13 = ciclos de escritura
    TSC_START
    mov     r14, rax
    mov     rdi, r12
    mov     rsi, [r15 + 8]
    mov     rdx, [r15 + 16]
    call    mem_verify
    mov     rbx, rax                    ; RBX = bits malos
    TSC_STOP
    sub     rax, r14                    ; RAX = ciclos de lectura
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, rax
    call    mem_report
    add     r15, 24
    lea     rax, [rel pat_end]
    cmp     r15, rax
    jb      .pattern

    ; --- autoprueba: volteamos 1 bit a propósito y el detector debe verlo ---
    ; (en memoria quedó la secuencia incremental, la última de la tabla)
    PRINT   s_selftest
    xor     byte [r12 + 0x12345], 0x08
    mov     rdi, r12
    xor     esi, esi
    mov     edx, 1
    call    mem_verify
    mov     rbx, rax
    mov     rdi, rax
    call    print_u64
    lea     rdi, [rel s_st_ok]
    cmp     rbx, 1
    je      .st_print
    lea     rdi, [rel s_st_bad]
.st_print:
    call    print_str

    mov     eax, SYS_MUNMAP
    mov     rdi, r12
    mov     esi, MEM_TEST_SIZE
    syscall
    jmp     .out

.mmap_fail:
    lea     rdi, [rel s_err_mmap]
    mov     rsi, rax
    call    err_report
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

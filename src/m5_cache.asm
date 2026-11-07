; =============================================================================
; Módulo 5 - Gestión jerárquica de memoria
; Medimos cuánto se tarda en leer un dato desde los registros, la caché
; L1, L2, L3 y la RAM, para ver que entre más lejos está, más lento es.
; =============================================================================

CHASE_RAM_SIZE  equ 128 * 1024 * 1024   ; mucho más grande que cualquier L3
CHASE_STEPS     equ 2000000             ; tiene que ser múltiplo de 8
SINGLE_SAMPLES  equ 20000
REG_OPS         equ 8000000
COL_BLOCK       equ 13                  ; columnas de la tabla
COL_CHAIN       equ 25
COL_SINGLE      equ 43

section .data
    m5_title    db 10, "=== Módulo 5: Gestión jerárquica de memoria ===", 10, 0
    s_caches    db "Caché (CPUID):     L1d ", 0
    s_c_l2      db ", L2 ", 0
    s_c_l3      db ", L3 ", 0
    s_c_line    db ", línea ", 0
    s_bytes_nl  db " B", 10, 0
    s_header    db 10, "Nivel        Bloque      Cadena (prom.)    Individual (rdtsc)", 10, 0
    s_lv_reg    db "Registros", 0
    s_lv_l1     db "L1 caché", 0
    s_lv_l2     db "L2 caché", 0
    s_lv_l3     db "L3 caché", 0
    s_lv_ram    db "RAM", 0
    s_dash      db "-", 0
    s_cyc       db " ciclos", 0
    s_below     db "< 1 (bajo la resolución)", 0
    s_note      db 10, "Nota: son ciclos del TSC (frecuencia nominal). Con turbo el núcleo va más", 10
                db "rápido, por eso un registro puede salir en menos de 1 ciclo.", 10, 0
    s_err_chase db "no se pudo reservar el bloque para RAM", 0

    rng_state   dq 0x9E3779B97F4A7C15   ; semilla del xorshift64

section .bss
    l1_size     resq 1
    l2_size     resq 1
    l3_size     resq 1
    line_size   resq 1

section .text

; -----------------------------------------------------------------------------
; cache_detect: le preguntamos al CPU cuánto mide cada caché. Nos va
; respondiendo una caché a la vez con sus datos (vías, conjuntos, tamaño de
; línea) y al multiplicarlos sale el tamaño.
; Si algo falla nos quedamos con valores típicos.
; -----------------------------------------------------------------------------
cache_detect:
    push    rbx                         ; CPUID cambia EBX, lo guardamos
    mov     qword [rel l1_size], 32 * 1024
    mov     qword [rel l2_size], 256 * 1024
    mov     qword [rel l3_size], 8 * 1024 * 1024
    mov     qword [rel line_size], 64

    mov     r8d, 4
    cmp     dword [rel cpu_vendor + 8], 'cAMD'   ; "AuthenticAMD"
    jne     .intel
    cmp     dword [rel cpu_maxext], 0x8000001D
    jb      .done
    mov     r8d, 0x8000001D
    jmp     .start
.intel:
    cmp     dword [rel cpu_maxleaf], 4
    jb      .done
.start:
    xor     r9d, r9d                    ; número de caché que preguntamos
.loop:
    mov     eax, r8d
    mov     ecx, r9d
    cpuid
    mov     r10d, eax
    and     r10d, 0x1F
    jz      .done                       ; ya no hay más cachés
    cmp     r10d, 2
    je      .next                       ; la de instrucciones no nos interesa
    mov     r11d, ebx
    shr     r11d, 22
    inc     r11d                        ; vías
    mov     esi, ebx
    shr     esi, 12
    and     esi, 0x3FF
    inc     esi                         ; particiones
    imul    r11d, esi
    mov     esi, ebx
    and     esi, 0xFFF
    inc     esi                         ; bytes por línea
    mov     [rel line_size], rsi
    imul    r11d, esi
    inc     ecx                         ; conjuntos
    imul    r11, rcx                    ; R11 = tamaño en bytes
    shr     eax, 5
    and     eax, 7                      ; nivel
    lea     rdx, [rel l1_size - 8]      ; lo guardamos en l1_size, l2_size o l3_size
    dec     eax
    cmp     eax, 2                      ; solo nos sirven los niveles 1 a 3
    ja      .next
    inc     eax
    mov     [rdx + rax*8], r11
.next:
    inc     r9d
    cmp     r9d, 16
    jb      .loop
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; chase_build: RDI = base, RSI = bytes. Arma una "cadena" donde cada pedazo
; de memoria apunta al siguiente en orden al azar, así el CPU no puede
; adivinar cuál sigue:
;   1) numeramos los pedazos
;   2) los revolvemos (algoritmo de Sattolo, así quedan en un solo círculo)
;   3) cambiamos los números por direcciones
; -----------------------------------------------------------------------------
chase_build:
    mov     rcx, rsi
    shr     rcx, 6                      ; RCX = cuántas líneas
    xor     eax, eax
.init:
    mov     rdx, rax
    shl     rdx, 6
    mov     [rdi + rdx], rax
    inc     rax
    cmp     rax, rcx
    jb      .init

    lea     r8, [rcx - 1]               ; i = n - 1
.shuffle:
    test    r8, r8
    jz      .link
    mov     rax, [rel rng_state]        ; sacamos un número al azar
    mov     rdx, rax
    shl     rdx, 13
    xor     rax, rdx
    mov     rdx, rax
    shr     rdx, 7
    xor     rax, rdx
    mov     rdx, rax
    shl     rdx, 17
    xor     rax, rdx
    mov     [rel rng_state], rax
    xor     edx, edx
    div     r8                          ; RDX = j entre 0 e i-1
    mov     r9, r8
    shl     r9, 6
    shl     rdx, 6
    mov     r10, [rdi + r9]             ; intercambio
    mov     r11, [rdi + rdx]
    mov     [rdi + r9], r11
    mov     [rdi + rdx], r10
    dec     r8
    jmp     .shuffle

.link:
    xor     eax, eax
.link_loop:
    mov     rdx, rax
    shl     rdx, 6
    mov     r9, [rdi + rdx]
    shl     r9, 6
    add     r9, rdi                     ; índice -> dirección
    mov     [rdi + rdx], r9
    inc     rax
    cmp     rax, rcx
    jb      .link_loop
    ret

; chase_avg: RDI = inicio de la cadena -> RAX = ciclos por acceso x 100
chase_avg:
    mov     r8, rdi
    mov     ecx, CHASE_STEPS            ; primero una pasada para calentar la caché
.warm:
    mov     r8, [r8]
    dec     ecx
    jnz     .warm
    TSC_START
    mov     r9, rax
    mov     r10d, CHASE_STEPS / 8
.loop:
%rep 8
    mov     r8, [r8]                    ; cada carga depende de la anterior
%endrep
    dec     r10d
    jnz     .loop
    TSC_STOP
    sub     rax, r9
    mov     rdi, rax
    mov     esi, CHASE_STEPS
    jmp     ratio_x100

; -----------------------------------------------------------------------------
; chase_single: RDI = inicio -> RAX = ciclos por acceso x 100.
; En cada muestra: medimos "nada" (costo del TSC) y luego UN acceso, y
; sumamos la diferencia. Si da negativo lo dejamos en 0.
; -----------------------------------------------------------------------------
chase_single:
    push    rbx
    mov     rbx, rdi                    ; RBX = puntero de la cadena
    xor     r9d, r9d                    ; R9 = suma (con signo)
    mov     r10d, SINGLE_SAMPLES
.loop:
    TSC_START                           ; medición vacía
    mov     r8, rax
    TSC_STOP
    sub     rax, r8
    sub     r9, rax
    TSC_START                           ; medición del acceso
    mov     r8, rax
    mov     rbx, [rbx]
    TSC_STOP
    sub     rax, r8
    add     r9, rax
    dec     r10d
    jnz     .loop
    xor     eax, eax
    test    r9, r9
    js      .out
    mov     rdi, r9
    mov     esi, SINGLE_SAMPLES
    call    ratio_x100
.out:
    pop     rbx
    ret

; reg_latency: -> RAX = ciclos x 100 por ADD de una cadena que nunca sale
; de los registros (el dato no toca memoria)
reg_latency:
    TSC_START
    mov     r9, rax
    xor     r8d, r8d
    mov     r10d, REG_OPS / 8
.loop:
%rep 8
    add     r8, 1
%endrep
    dec     r10d
    jnz     .loop
    TSC_STOP
    sub     rax, r9
    mov     rdi, rax
    mov     esi, REG_OPS
    jmp     ratio_x100

; -----------------------------------------------------------------------------
; level_test: RDI = nombre, RSI = bytes del bloque, RDX = base del buffer.
; Imprime una fila de la tabla.
; -----------------------------------------------------------------------------
level_test:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rsi
    mov     r12, rdx
    call    print_str
    mov     edi, COL_BLOCK
    call    pad_to
    mov     rdi, rbx
    call    print_size

    mov     rdi, r12
    mov     rsi, rbx
    call    chase_build
    mov     rdi, r12
    call    chase_avg
    mov     r13, rax
    mov     rdi, r12
    call    chase_single
    mov     rbx, rax

    mov     edi, COL_CHAIN
    call    pad_to
    mov     rdi, r13
    call    print_fix2
    PRINT   s_cyc
    mov     edi, COL_SINGLE
    call    pad_to
    cmp     rbx, 100                    ; menos de 1 ciclo ya no se puede medir así
    jae     .single
    PRINT   s_below
    jmp     .end_row
.single:
    mov     rdi, rbx
    call    print_fix2
    PRINT   s_cyc
.end_row:
    call    print_nl
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; mod_cache: reporte del módulo 5
; -----------------------------------------------------------------------------
mod_cache:
    push    r12
    PRINT   m5_title
    call    cache_detect

    PRINT   s_caches
    mov     rdi, [rel l1_size]
    call    print_size
    PRINT   s_c_l2
    mov     rdi, [rel l2_size]
    call    print_size
    PRINT   s_c_l3
    mov     rdi, [rel l3_size]
    call    print_size
    PRINT   s_c_line
    mov     rdi, [rel line_size]
    call    print_u64
    PRINT   s_bytes_nl

    ; un solo bloque para todos los niveles. Pedimos páginas grandes para
    ; que la medición de la RAM salga más limpia.
    mov     edi, CHASE_RAM_SIZE
    xor     esi, esi
    call    mem_alloc
    cmp     rax, -4095
    jae     .mmap_fail
    mov     r12, rax
    mov     eax, SYS_MADVISE
    mov     rdi, r12
    mov     esi, CHASE_RAM_SIZE
    mov     edx, MADV_HUGEPAGE
    syscall                             ; si no se puede, seguimos con páginas de 4 KB

    PRINT   s_header
    PRINT   s_lv_reg
    mov     edi, COL_BLOCK
    call    pad_to
    PRINT   s_dash
    mov     edi, COL_CHAIN
    call    pad_to
    call    reg_latency
    mov     rdi, rax
    call    print_fix2
    PRINT   s_cyc
    call    print_nl

    lea     rdi, [rel s_lv_l1]
    mov     rsi, [rel l1_size]
    shr     rsi, 1
    mov     rdx, r12
    call    level_test

    lea     rdi, [rel s_lv_l2]
    mov     rsi, [rel l2_size]
    shr     rsi, 1
    mov     rdx, r12
    call    level_test

    ; para L3 usamos un bloque más grande que L2 pero no tanto, para que
    ; de verdad quede en L3
    mov     rsi, [rel l3_size]
    shr     rsi, 1
    mov     rax, [rel l2_size]
    shl     rax, 1
    cmp     rax, rsi
    cmovb   rsi, rax
    lea     rdi, [rel s_lv_l3]
    mov     rdx, r12
    call    level_test

    lea     rdi, [rel s_lv_ram]
    mov     esi, CHASE_RAM_SIZE
    mov     rdx, r12
    call    level_test

    PRINT   s_note

    mov     eax, SYS_MUNMAP
    mov     rdi, r12
    mov     esi, CHASE_RAM_SIZE
    syscall
    jmp     .out
.mmap_fail:
    lea     rdi, [rel s_err_chase]
    mov     rsi, rax
    call    err_report
.out:
    pop     r12
    ret

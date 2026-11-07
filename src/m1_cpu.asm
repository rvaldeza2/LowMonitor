; =============================================================================
; Módulo 1 - Identificación del CPU
; Le preguntamos al procesador cómo se llama, quién lo fabricó y qué
; extensiones trae (SSE, AVX, etc.) para mostrarlo en pantalla.
; =============================================================================

section .data
    m1_title    db 10, "=== Módulo 1: Identificación del CPU ===", 10, 0
    s_brand     db "Procesador:      ", 0
    s_vendor    db "Fabricante:      ", 0
    s_arch      db "Arquitectura:    x86_64 (modo largo de 64 bits: ", 0
    s_family    db "Familia:         ", 0
    s_model     db "   Modelo: ", 0
    s_model_hex db " (0x", 0
    s_stepping  db ")   Stepping: ", 0
    s_ext       db "Extensiones:     ", 0
    s_other     db "Otras:           ", 0
    s_xcr0      db "XCR0 (SO):       0x", 0
    s_avx_os    db "   AVX usable: ", 0
    s_avx512_os db "   AVX-512 usable: ", 0
    s_no512     db "AVX-512:         no implementado en este procesador", 10, 0
    s_unknown   db "(desconocido)", 0
    s_close     db ")", 10, 0

    f_sse       db "SSE", 0
    f_sse2      db "SSE2", 0
    f_sse3      db "SSE3", 0
    f_ssse3     db "SSSE3", 0
    f_sse41     db "SSE4.1", 0
    f_sse42     db "SSE4.2", 0
    f_avx       db "AVX", 0
    f_avx2      db "AVX2", 0
    f_fma       db "FMA", 0
    f_avx512f   db "AVX-512F", 0
    f_avx512dq  db "AVX-512DQ", 0
    f_avx512bw  db "AVX-512BW", 0
    f_avx512vl  db "AVX-512VL", 0
    f_popcnt    db "POPCNT", 0
    f_rdtscp    db "RDTSCP", 0
    f_invtsc    db "TSC invariante", 0
    f_htt       db "HTT", 0

section .bss
    cpu_vendor      resb 16             ; 12 letras + el 0 del final
    cpu_brand       resb 52
    cpu_maxleaf     resd 1
    cpu_maxext      resd 1
    cpu_l1ecx       resd 1              ; respuestas de CPUID (cada "hoja" es una pregunta)
    cpu_l1edx       resd 1
    cpu_l7ebx       resd 1              ; hoja 7
    cpu_e1edx       resd 1              ; hoja 80000001h
    cpu_e7edx       resd 1              ; hoja 80000007h
    cpu_xcr0        resd 1
    cpu_flags       resd 1              ; bits CF_* (ver defs.asm)
    cpu_family      resd 1
    cpu_model       resd 1
    cpu_stepping    resd 1
    feat_count      resb 1

section .text

; FEAT variable, bit, nombre: si el bit está en 1 imprime el nombre
%macro FEAT 3
    bt      dword [rel %1], %2
    jnc     %%skip
    lea     rdi, [rel %3]
    call    print_feat
%%skip:
%endmacro

; -----------------------------------------------------------------------------
; cpu_detect: le pregunta todo al CPU y lo guarda (no imprime nada).
; Se llama una vez al inicio porque los módulos 5 y 6 usan estos datos.
; -----------------------------------------------------------------------------
cpu_detect:
    push    rbx                         ; CPUID cambia EBX, así que lo guardamos

    ; pregunta 0: el fabricante, viene en 3 pedazos ("Genu" "ineI" "ntel")
    xor     eax, eax
    cpuid
    mov     [rel cpu_maxleaf], eax
    mov     [rel cpu_vendor], ebx
    mov     [rel cpu_vendor + 4], edx
    mov     [rel cpu_vendor + 8], ecx

    ; pregunta 1: la versión del CPU y qué extensiones trae
    mov     eax, 1
    cpuid
    mov     [rel cpu_l1ecx], ecx
    mov     [rel cpu_l1edx], edx

    ; de la versión sacamos familia, modelo y stepping
    ; (vienen como pedacitos de bits dentro de EAX)
    mov     ecx, eax
    and     ecx, 0xF
    mov     [rel cpu_stepping], ecx
    mov     ecx, eax
    shr     ecx, 8
    and     ecx, 0xF                    ; ECX = familia base
    mov     edx, eax
    shr     edx, 4
    and     edx, 0xF                    ; EDX = modelo base
    mov     r8d, ecx                    ; copia de la familia base
    cmp     ecx, 0xF                    ; si la familia es 15 se le suma la extendida
    jne     .no_extfam
    mov     r9d, eax
    shr     r9d, 20
    and     r9d, 0xFF
    add     ecx, r9d
.no_extfam:
    cmp     r8d, 6                      ; y el modelo ext. solo en familias 6 y 15
    je      .extmod
    cmp     r8d, 0xF
    jne     .store_sig
.extmod:
    mov     r9d, eax
    shr     r9d, 16
    and     r9d, 0xF
    shl     r9d, 4
    add     edx, r9d                    ; modelo = (ext << 4) + base
.store_sig:
    mov     [rel cpu_family], ecx
    mov     [rel cpu_model], edx

    ; pregunta 7: aquí vienen AVX2 y AVX-512
    cmp     dword [rel cpu_maxleaf], 7
    jb      .no_leaf7
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    mov     [rel cpu_l7ebx], ebx
.no_leaf7:

    ; preguntas extendidas (de 80000000h para arriba)
    mov     eax, 0x80000000
    cpuid
    mov     [rel cpu_maxext], eax
    cmp     eax, 0x80000001
    jb      .no_ext
    mov     eax, 0x80000001
    cpuid
    mov     [rel cpu_e1edx], edx

    ; nombre comercial: viene en 3 pedazos de 16 letras = 48
    cmp     dword [rel cpu_maxext], 0x80000004
    jb      .no_brand
    lea     rdi, [rel cpu_brand]
    mov     esi, 0x80000002
.brand_loop:
    mov     eax, esi
    cpuid
    mov     [rdi], eax
    mov     [rdi + 4], ebx
    mov     [rdi + 8], ecx
    mov     [rdi + 12], edx
    add     rdi, 16
    inc     esi
    cmp     esi, 0x80000004
    jbe     .brand_loop
.no_brand:
    cmp     dword [rel cpu_maxext], 0x80000007
    jb      .no_ext
    mov     eax, 0x80000007
    cpuid
    mov     [rel cpu_e7edx], edx
.no_ext:

    ; XCR0 dice qué registros grandes activó el sistema operativo.
    ; Solo se puede leer si el SO lo permite (bit 27).
    xor     eax, eax
    bt      dword [rel cpu_l1ecx], 27
    jnc     .no_xgetbv
    xor     ecx, ecx
    xgetbv                              ; EAX = XCR0
.no_xgetbv:
    mov     [rel cpu_xcr0], eax

    ; cpu_flags: lo que de verdad se puede usar
    xor     ebx, ebx
    bt      dword [rel cpu_l1edx], 26   ; SSE2 (en x86-64 siempre está)
    jnc     .sse2_done
    bts     ebx, CF_SSE2
.sse2_done:
    mov     eax, [rel cpu_xcr0]
    and     eax, 0x6                    ; ¿el SO guarda los registros XMM y YMM?
    cmp     eax, 0x6
    jne     .flags_done                 ; si no, no se puede usar AVX
    bt      dword [rel cpu_l1ecx], 28
    jnc     .flags_done
    bts     ebx, CF_AVX
    bt      dword [rel cpu_l7ebx], 5
    jnc     .avx2_done
    bts     ebx, CF_AVX2
.avx2_done:
    mov     eax, [rel cpu_xcr0]
    and     eax, 0xE6                   ; para AVX-512 también tiene que guardar los ZMM
    cmp     eax, 0xE6
    jne     .flags_done
    bt      dword [rel cpu_l7ebx], 16   ; AVX-512F
    jnc     .flags_done
    bts     ebx, CF_AVX512
.flags_done:
    mov     [rel cpu_flags], ebx

    pop     rbx
    ret

; print_feat: RDI = nombre. Del segundo en adelante le pone ", " antes.
print_feat:
    push    rdi
    cmp     byte [rel feat_count], 0
    je      .first
    PRINT   sep_str
.first:
    inc     byte [rel feat_count]
    pop     rdi
    jmp     print_str

; -----------------------------------------------------------------------------
; mod_cpu: imprime el reporte del módulo 1
; -----------------------------------------------------------------------------
mod_cpu:
    PRINT   m1_title

    ; Intel rellena el nombre con espacios a la izquierda, se los saltamos
    PRINT   s_brand
    lea     rdi, [rel cpu_brand]
    cmp     byte [rdi], 0
    jne     .skip_spaces
    lea     rdi, [rel s_unknown]
.skip_spaces:
    cmp     byte [rdi], ' '
    jne     .print_brand
    inc     rdi
    jmp     .skip_spaces
.print_brand:
    call    print_str
    call    print_nl

    PRINT   s_vendor
    PRINT   cpu_vendor
    call    print_nl

    PRINT   s_arch
    mov     edi, [rel cpu_e1edx]
    shr     edi, 29                     ; ¿el CPU soporta 64 bits?
    and     edi, 1
    call    print_yesno
    PRINT   s_close

    PRINT   s_family
    mov     edi, [rel cpu_family]
    call    print_u64
    PRINT   s_model
    mov     edi, [rel cpu_model]
    call    print_u64
    PRINT   s_model_hex
    mov     edi, [rel cpu_model]
    mov     esi, 2
    call    print_hex
    PRINT   s_stepping
    mov     edi, [rel cpu_stepping]
    call    print_u64
    call    print_nl

    ; extensiones SIMD que pide el enunciado (y algunas más)
    mov     byte [rel feat_count], 0
    PRINT   s_ext
    FEAT    cpu_l1edx, 25, f_sse
    FEAT    cpu_l1edx, 26, f_sse2
    FEAT    cpu_l1ecx, 0,  f_sse3
    FEAT    cpu_l1ecx, 9,  f_ssse3
    FEAT    cpu_l1ecx, 19, f_sse41
    FEAT    cpu_l1ecx, 20, f_sse42
    FEAT    cpu_l1ecx, 28, f_avx
    FEAT    cpu_l7ebx, 5,  f_avx2
    FEAT    cpu_l1ecx, 12, f_fma
    FEAT    cpu_l7ebx, 16, f_avx512f
    FEAT    cpu_l7ebx, 17, f_avx512dq
    FEAT    cpu_l7ebx, 30, f_avx512bw
    FEAT    cpu_l7ebx, 31, f_avx512vl
    call    print_nl

    ; las que usan los otros módulos (POPCNT en el 3, RDTSCP/TSC en el 4 y 5)
    mov     byte [rel feat_count], 0
    PRINT   s_other
    FEAT    cpu_l1ecx, 23, f_popcnt
    FEAT    cpu_e1edx, 27, f_rdtscp
    FEAT    cpu_e7edx, 8,  f_invtsc
    FEAT    cpu_l1edx, 28, f_htt
    call    print_nl

    bt      dword [rel cpu_l7ebx], 16
    jc      .has512
    PRINT   s_no512
.has512:

    ; lo que habilitó el sistema operativo
    PRINT   s_xcr0
    mov     edi, [rel cpu_xcr0]
    mov     esi, 2
    call    print_hex
    PRINT   s_avx_os
    mov     edi, [rel cpu_flags]
    shr     edi, CF_AVX
    and     edi, 1
    call    print_yesno
    PRINT   s_avx512_os
    mov     edi, [rel cpu_flags]
    shr     edi, CF_AVX512
    and     edi, 1
    call    print_yesno
    jmp     print_nl

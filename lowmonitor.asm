; =============================================================================
; LowMonitor - Programa principal
; Aquí arranca todo: muestra el menú y llama a cada módulo según lo que
; escoja el usuario (también se puede: ./lowmonitor 3 o ./lowmonitor all).
; =============================================================================

%include "src/defs.asm"

section .data
    ; Constantes, strings, tablas de datos
    banner      db "==============================================================", 10
                db "  LowMonitor - Diagnóstico y monitorización de hardware x86-64", 10
                db "  UMG - Ingeniería en Sistemas - 2026", 10
                db "==============================================================", 10, 0
    menu_text   db 10, "  1) Identificación del CPU", 10
                db "  2) Monitor de puertos E/S", 10
                db "  3) Diagnóstico de memoria", 10
                db "  4) Monitor de rendimiento del CPU", 10
                db "  5) Gestión jerárquica de memoria", 10
                db "  6) Operaciones SIMD (bonus)", 10
                db "  7) Ejecutar todos", 10
                db "  0) Salir", 10
                db "Opción: ", 0
    s_badopt    db "Opción no válida.", 10, 0
    s_bye       db "Fin de LowMonitor.", 10, 0
    s_usage     db "Uso: lowmonitor [1-6 | all]", 10, 0

    ; tabla de saltos: el módulo N está en la posición N-1
    module_table dq mod_cpu, mod_io, mod_mem, mod_perf, mod_cache, mod_simd

section .bss
    ; Variables reservadas (buffers, contadores)
    input_buf   resb 16

section .text
    global _start

; -----------------------------------------------------------------------------
; Punto de entrada principal.
; Linux nos deja en la pila cuántos argumentos hay y cuáles son.
; -----------------------------------------------------------------------------
_start:
    call    cpu_detect                  ; primero vemos qué CPU es (otros módulos lo ocupan)
    call    tsc_calibrate               ; y medimos la velocidad del reloj del CPU
    PRINT   banner
    cmp     qword [rsp], 2
    jb      menu_loop                   ; sin argumentos -> menú
    mov     rax, [rsp + 16]
    movzx   edi, byte [rax]             ; solo vemos la primera letra del argumento
    call    dispatch
    mov     ebx, eax                    ; 0 = todo bien, 1 = opción inválida
    test    eax, eax
    jz      .fin
    PRINT   s_usage
.fin:
    mov     edi, ebx
    jmp     exit_program

; -----------------------------------------------------------------------------
; menu_loop: lee lo que escribe el usuario y lo manda a dispatch
; -----------------------------------------------------------------------------
menu_loop:
    PRINT   menu_text
    mov     eax, SYS_READ
    mov     edi, STDIN
    lea     rsi, [rel input_buf]
    mov     edx, 16
    syscall
    test    rax, rax
    jle     .quit                       ; EOF (Ctrl+D) o error -> nos salimos
    movzx   edi, byte [rel input_buf]
    cmp     dil, '0'
    je      .quit
    cmp     dil, 'q'
    je      .quit
    call    dispatch
    test    eax, eax
    jz      menu_loop
    PRINT   s_badopt
    jmp     menu_loop
.quit:
    PRINT   s_bye
    xor     edi, edi
    jmp     exit_program

; -----------------------------------------------------------------------------
; dispatch: DIL = opción ('1'-'6', o '7'/'a' para todos) -> EAX = 0 si era válida
; Se usa tanto en el menú como cuando viene por línea de comandos.
; -----------------------------------------------------------------------------
dispatch:
    cmp     dil, '7'
    je      run_all
    cmp     dil, 'a'
    je      run_all
    movzx   eax, dil
    sub     eax, '1'                    ; '1'..'6' -> 0..5
    cmp     eax, 5
    ja      .bad                        ; si no está entre 1 y 6, es inválida
    lea     rcx, [rel module_table]
    call    [rcx + rax*8]               ; llamamos al módulo que toca
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

run_all:
    push    rbx
    xor     ebx, ebx
.loop:
    lea     rax, [rel module_table]
    call    [rax + rbx*8]
    inc     ebx
    cmp     ebx, 6
    jb      .loop
    pop     rbx
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; Funciones auxiliares, rutinas de salida y handlers de errores
; -----------------------------------------------------------------------------
%include "src/util.asm"

; -----------------------------------------------------------------------------
; Módulos
; -----------------------------------------------------------------------------
%include "src/m1_cpu.asm"
%include "src/m2_io.asm"
%include "src/m3_mem.asm"
%include "src/m4_perf.asm"
%include "src/m5_cache.asm"
%include "src/m6_simd.asm"

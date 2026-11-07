; =============================================================================
; Módulo 2 - Monitor de puertos E/S
; Leemos y escribimos en algunos puertos del sistema (teclado, panel y COM1).
; Si Linux no nos da permiso, atrapamos el error para que no se caiga el programa.
; =============================================================================

section .data
    m2_title    db 10, "=== Módulo 2: Monitor de puertos E/S ===", 10, 0
    s_try_iopl  db "Permiso de E/S: iopl(3)   -> ", 0
    s_try_iopm  db "                ioperm()  -> ", 0
    s_ret_ok    db "concedido", 10, 0
    s_ret_err   db "denegado (errno ", 0
    s_eperm     db ", EPERM: requiere CAP_SYS_RAWIO", 0
    s_enosys    db ", ENOSYS: el kernel no implementa iopl/ioperm, p. ej. WSL2", 0
    s_noperm    db "  Sin acceso a puertos: cada IN/OUT causará #GP (SIGSEGV), que el", 10
                db "  manejador propio captura. En Linux nativo, 'sudo ./lowmonitor 2'", 10
                db "  da acceso real.", 10, 0
    s_rflags    db "RFLAGS = 0x", 0
    s_iopl_fld  db "   IOPL = ", 0
    s_cpl_end   db "   CPL = 3 (modo usuario)", 10, 10, 0

    s_p60       db "Puerto 60h  (teclado)        IN  8b      : ", 0
    s_p61       db "Puerto 61h  (panel sistema)  IN/OUT 8b   : ", 0
    s_p3ff      db "Puerto 3FFh (COM1, scratch)  OUT/IN 8b   : ", 0
    s_p3f8w     db "Puerto 3F8h (COM1)           IN  16b     : ", 0
    s_p3f8d     db "Puerto 3F8h (COM1)           IN  32b     : ", 0
    s_p80       db "Puerto 80h  (POST)           OUT 8/16/32 : ", 0

    s_val       db "valor 0x", 0
    s_ok        db "   [OK]", 10, 0
    s_fault     db "[FALLO #GP capturado -> SIGSEGV]", 10, 0
    s_mismatch  db "[ERROR: lo leído no coincide con lo escrito]", 10, 0
    s_absent    db "sin UART (lee 0xFF)   [NO PRESENTE]", 10, 0
    s_scr_ok    db "escrito 5Ah/A5h, leído 5Ah/A5h   [OK]", 10, 0
    s_p80_ok    db "3 escrituras sin excepción   [OK]", 10, 0
    s_sum1      db 10, "Resumen: ", 0
    s_sum2      db " operaciones IN/OUT, ", 0
    s_sum3      db " excepciones capturadas", 10, 0
    s_segv_fatal db 10, "ERROR: violación de segmento fuera de una operación de E/S", 10, 0

section .bss
    io_fault    resb 1                  ; 1 si la última lectura/escritura falló
    io_mode     resb 1                  ; 0 = sin permiso, 1 = iopl, 2 = ioperm
    alignb 8
    io_ops      resd 1                  ; cuántas operaciones hicimos
    io_faults   resd 1                  ; cuántas fallaron
    io_recover  resq 1                  ; a dónde saltar si falla (0 = a ningún lado)
    sa_buf      resq 4                  ; datos para registrar nuestro manejador de errores

section .text

; -----------------------------------------------------------------------------
; segv_handler (manejador de errores). Si un IN/OUT falla por no tener
; permiso, Linux manda la señal SIGSEGV y caemos aquí. Anotamos la falla y le
; decimos que siga con la siguiente instrucción en vez de cerrar el programa.
; -----------------------------------------------------------------------------
segv_handler:
    mov     rax, [rel io_recover]
    test    rax, rax
    jz      .fatal                      ; fue otro SIGSEGV, ese sí es error de verdad
    mov     byte [rel io_fault], 1
    mov     [rdx + UC_RIP], rax
    ret                                 ; de aquí sigue sig_restorer
.fatal:
    PRINT   s_segv_fatal
    mov     edi, 139
    jmp     exit_program

; Cuando termina el manejador, Linux viene aquí y el programa sigue
; donde le dijimos.
sig_restorer:
    mov     eax, SYS_RT_SIGRETURN
    syscall

; io_set_handler: RDI = handler (0 = dejar el comportamiento normal)
io_set_handler:
    mov     [rel sa_buf], rdi
    xor     eax, eax
    test    rdi, rdi
    jz      .flags
    mov     eax, SA_SIGINFO | SA_RESTORER
.flags:
    mov     [rel sa_buf + 8], rax
    lea     rax, [rel sig_restorer]
    mov     [rel sa_buf + 16], rax
    mov     qword [rel sa_buf + 24], 0  ; no bloqueamos ninguna señal
    mov     eax, SYS_RT_SIGACTION
    mov     edi, SIGSEGV
    lea     rsi, [rel sa_buf]
    xor     edx, edx
    mov     r10d, 8                     ; tamaño que pide Linux
    syscall
    ret

; -----------------------------------------------------------------------------
; Funciones para leer y escribir puertos de 8, 16 y 32 bits (con macro para
; no repetir código):
;   io_inN : EDI = puerto              -> EAX = valor leído
;   io_outN: EDI = puerto, ESI = valor
; Antes de cada IN/OUT anotamos a dónde saltar si falla. Todas terminan en
; io_done, que lleva la cuenta.
; -----------------------------------------------------------------------------
%macro IO_IN 2                          ; nombre, registro (al/ax/eax)
%1:
    mov     byte [rel io_fault], 0
    lea     rax, [rel %%rec]
    mov     [rel io_recover], rax
    mov     edx, edi
    xor     eax, eax
    in      %2, dx
%%rec:
    jmp     io_done
%endmacro

%macro IO_OUT 2                         ; nombre, registro (al/ax/eax)
%1:
    mov     byte [rel io_fault], 0
    lea     rax, [rel %%rec]
    mov     [rel io_recover], rax
    mov     edx, edi
    mov     eax, esi
    out     dx, %2
%%rec:
    jmp     io_done
%endmacro

    IO_IN   io_in8,   al
    IO_IN   io_in16,  ax
    IO_IN   io_in32,  eax
    IO_OUT  io_out8,  al
    IO_OUT  io_out16, ax
    IO_OUT  io_out32, eax

; teclado 60h con la forma de puerto inmediato (sigue directo a io_done)
io_in8_kbd:
    mov     byte [rel io_fault], 0
    lea     rax, [rel .rec]
    mov     [rel io_recover], rax
    xor     eax, eax
    in      al, 0x60
.rec:

io_done:
    inc     dword [rel io_ops]          ; contamos la operación (EAX sigue con lo leído)
    cmp     byte [rel io_fault], 0
    je      .ok
    inc     dword [rel io_faults]
.ok:
    mov     qword [rel io_recover], 0
    ret

; -----------------------------------------------------------------------------
; io_report_ret: RDI = lo que devolvió iopl/ioperm. Lo imprime.
; RAX = 1 si nos dieron permiso, 0 si no.
; -----------------------------------------------------------------------------
io_report_ret:
    push    rbx
    mov     rbx, rdi
    test    rbx, rbx
    js      .err
    PRINT   s_ret_ok
    mov     eax, 1
    pop     rbx
    ret
.err:
    PRINT   s_ret_err
    mov     rdi, rbx
    neg     rdi
    call    print_u64
    lea     rdi, [rel s_eperm]
    cmp     rbx, -1                     ; -EPERM
    je      .why
    lea     rdi, [rel s_enosys]
    cmp     rbx, -38                    ; -ENOSYS
    jne     .close
.why:
    call    print_str
.close:
    PRINT   s_paren_nl
    xor     eax, eax
    pop     rbx
    ret

; io_report_read: EDI = valor leído, ESI = dígitos hex. Revisa io_fault.
io_report_read:
    cmp     byte [rel io_fault], 0
    jne     .fault
    push    rdi
    push    rsi
    PRINT   s_val
    pop     rsi
    pop     rdi
    call    print_hex
    PRINT   s_ok
    ret
.fault:
    PRINT   s_fault
    ret

; ioperm(desde, cuántos, activar) -> RAX
%macro IOPERM 3
    mov     eax, SYS_IOPERM
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    syscall
%endmacro

; -----------------------------------------------------------------------------
; mod_io: reporte del módulo 2
; Para pruebas de varias operaciones guardamos io_faults en R13 al inicio y
; al final comparamos: si cambió es que alguna falló.
; -----------------------------------------------------------------------------
mod_io:
    push    rbx
    push    r12
    push    r13
    PRINT   m2_title

    xor     eax, eax
    mov     [rel io_ops], eax
    mov     [rel io_faults], eax
    mov     [rel io_recover], rax
    mov     [rel io_mode], al
    lea     rdi, [rel segv_handler]
    call    io_set_handler

    ; --- 1) pedimos permiso, primero iopl y si no ioperm ---
    PRINT   s_try_iopl
    mov     eax, SYS_IOPL
    mov     edi, 3
    syscall
    mov     rdi, rax
    call    io_report_ret
    test    eax, eax
    jz      .try_ioperm
    mov     byte [rel io_mode], 1
    jmp     .show_flags
.try_ioperm:
    PRINT   s_try_iopm
    IOPERM  0x60, 2, 1                  ; 60h y 61h
    mov     rdi, rax
    call    io_report_ret
    test    eax, eax
    jz      .no_perm
    mov     byte [rel io_mode], 2
    IOPERM  0x80, 4, 1                  ; 80h-83h (el OUT de 32 bits ocupa 4)
    IOPERM  0x3F8, 8, 1                 ; 3F8h-3FFh, todo COM1
    jmp     .show_flags
.no_perm:
    PRINT   s_noperm

    ; --- 2) mostramos RFLAGS y su campo IOPL ---
    ; Ojo: en Linux nuevo IOPL sale en 0 aunque sí nos hayan dado permiso,
    ; porque el permiso lo maneja de otra forma.
.show_flags:
    pushfq
    pop     rbx
    PRINT   s_rflags
    mov     rdi, rbx
    mov     esi, 8
    call    print_hex
    PRINT   s_iopl_fld
    mov     rdi, rbx
    shr     rdi, 12
    and     edi, 3
    call    print_u64
    PRINT   s_cpl_end

    ; --- 3) teclado 60h ---
    PRINT   s_p60
    call    io_in8_kbd
    mov     edi, eax
    mov     esi, 2
    call    io_report_read

    ; --- 4) panel 61h: leemos, escribimos lo mismo y volvemos a leer ---
    ; Solo comparamos los 4 bits de abajo, los de arriba cambian solitos.
    PRINT   s_p61
    mov     r13d, [rel io_faults]
    mov     edi, 0x61
    call    io_in8
    mov     r12d, eax
    mov     edi, 0x61
    mov     esi, r12d
    call    io_out8                     ; escribir el mismo valor no cambia nada
    mov     edi, 0x61
    call    io_in8
    cmp     [rel io_faults], r13d
    jne     .p61_fault
    xor     eax, r12d
    test    eax, 0x0F
    jnz     .p61_bad
    mov     edi, r12d
    mov     esi, 2
    call    io_report_read
    jmp     .com1
.p61_fault:
    PRINT   s_fault
    jmp     .com1
.p61_bad:
    PRINT   s_mismatch

    ; --- 5) COM1: registro de prueba (3FFh) ---
    ; Es un espacio libre del puerto serial, ahí se puede escribir y leer
    ; sin miedo. Si no hay puerto serial, se lee 0xFF.
.com1:
    PRINT   s_p3ff
    mov     r13d, [rel io_faults]
    mov     edi, 0x3FF
    mov     esi, 0x5A
    call    io_out8
    mov     edi, 0x3FF
    call    io_in8
    mov     r12d, eax
    mov     edi, 0x3FF
    mov     esi, 0xA5
    call    io_out8
    mov     edi, 0x3FF
    call    io_in8
    shl     r12d, 8
    or      r12d, eax                   ; R12 = 1ra lectura : 2da lectura
    lea     rdi, [rel s_fault]
    cmp     [rel io_faults], r13d
    jne     .scr_print
    lea     rdi, [rel s_scr_ok]
    cmp     r12d, 0x5AA5
    je      .scr_print
    lea     rdi, [rel s_absent]
    cmp     r12d, 0xFFFF
    je      .scr_print
    lea     rdi, [rel s_mismatch]
.scr_print:
    call    print_str

    ; --- 6) lecturas de 16 y 32 bits (agarran puertos seguidos) ---
    PRINT   s_p3f8w
    mov     edi, 0x3F8
    call    io_in16
    mov     edi, eax
    mov     esi, 4
    call    io_report_read

    PRINT   s_p3f8d
    mov     edi, 0x3F8
    call    io_in32
    mov     edi, eax
    mov     esi, 8
    call    io_report_read

    ; --- 7) escrituras de 8/16/32 bits al puerto de diagnóstico POST ---
    PRINT   s_p80
    mov     r13d, [rel io_faults]
    mov     edi, 0x80
    mov     esi, 0x55
    call    io_out8
    mov     edi, 0x80
    mov     esi, 0x55AA
    call    io_out16
    mov     edi, 0x80
    mov     esi, 0x12345678
    call    io_out32
    lea     rdi, [rel s_p80_ok]
    cmp     [rel io_faults], r13d
    je      .p80_print
    lea     rdi, [rel s_fault]
.p80_print:
    call    print_str

    ; --- 8) resumen y soltamos los permisos ---
    PRINT   s_sum1
    mov     edi, [rel io_ops]
    call    print_u64
    PRINT   s_sum2
    mov     edi, [rel io_faults]
    call    print_u64
    PRINT   s_sum3

    cmp     byte [rel io_mode], 1
    jne     .rel_ioperm
    mov     eax, SYS_IOPL
    xor     edi, edi
    syscall
    jmp     .restore
.rel_ioperm:
    cmp     byte [rel io_mode], 2
    jne     .restore
    IOPERM  0x60, 2, 0
    IOPERM  0x80, 4, 0
    IOPERM  0x3F8, 8, 0
.restore:
    xor     edi, edi                    ; dejamos SIGSEGV como estaba
    call    io_set_handler

    pop     r13
    pop     r12
    pop     rbx
    ret

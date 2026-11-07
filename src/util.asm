; =============================================================================
; Utilidades - funciones que usan todos los módulos
; Imprimir texto y números, pedir memoria y mostrar errores.
; =============================================================================

section .data
    hexdigits       db "0123456789ABCDEF"
    sep_str         db ", ", 0
    str_kb          db " KB", 0
    str_mb          db " MB", 0
    str_gb          db " GB", 0
    str_yes         db "Sí", 0
    str_no          db "No", 0
    s_err_prefix    db "ERROR: ", 0
    s_errno         db " (errno ", 0
    s_paren_nl      db ")", 10, 0

section .bss
    numbuf          resb 32             ; aquí armamos los números antes de imprimirlos
    charbuf         resb 1
    alignb 4
    out_col         resd 1              ; columna donde va el cursor (para alinear tablas)

section .text

; -----------------------------------------------------------------------------
; write_out: RSI = texto, RDX = cuántos bytes. Lo manda a la pantalla y lleva
; la cuenta de en qué columna vamos (para alinear las tablas). Las letras con
; tilde ocupan 2 bytes pero cuentan como 1. Un salto de línea regresa a 0.
; -----------------------------------------------------------------------------
write_out:
    mov     r8d, [rel out_col]
    xor     ecx, ecx
.count:
    cmp     rcx, rdx
    jae     .write
    movzx   eax, byte [rsi + rcx]
    cmp     al, 10
    jne     .not_nl
    xor     r8d, r8d
    jmp     .next
.not_nl:
    and     al, 0xC0
    cmp     al, 0x80                    ; ¿es la 2da parte de una letra con tilde?
    je      .next
    inc     r8d
.next:
    inc     rcx
    jmp     .count
.write:
    mov     [rel out_col], r8d
    mov     eax, SYS_WRITE
    mov     edi, STDOUT
    syscall
    ret

; pad_to: EDI = columna. Mete espacios hasta llegar ahí.
pad_to:
    push    rbx
    mov     ebx, edi
.loop:
    cmp     [rel out_col], ebx
    jae     .done
    mov     edi, ' '
    call    print_char
    jmp     .loop
.done:
    pop     rbx
    ret

; strlen: RDI = string -> RAX = largo (no toca RSI)
strlen:
    xor     eax, eax
.loop:
    cmp     byte [rdi + rax], 0
    je      .done
    inc     rax
    jmp     .loop
.done:
    ret

; print_str: RDI = string terminado en 0
print_str:
    mov     rsi, rdi
    call    strlen
    mov     rdx, rax
    jmp     write_out

; print_char: DIL = carácter
print_char:
    mov     [rel charbuf], dil
    lea     rsi, [rel charbuf]
    mov     edx, 1
    jmp     write_out

print_nl:
    mov     edi, 10
    jmp     print_char

; -----------------------------------------------------------------------------
; print_u64: RDI = número sin signo. Lo vamos dividiendo entre 10 y metemos
; los residuos al buffer de derecha a izquierda.
; -----------------------------------------------------------------------------
print_u64:
    mov     rax, rdi
    lea     rsi, [rel numbuf + 31]
    mov     ecx, 10
    xor     r8d, r8d                    ; R8 = cuántos dígitos llevamos
.loop:
    xor     edx, edx
    div     rcx
    add     dl, '0'
    mov     [rsi], dl
    dec     rsi
    inc     r8
    test    rax, rax
    jnz     .loop
    inc     rsi                         ; RSI apunta al primer dígito
    mov     rdx, r8
    jmp     write_out

; -----------------------------------------------------------------------------
; print_fix2: RDI = valor x 100 -> imprime "entero.dd"
; Así sacamos decimales (CPI, GHz, GFLOPS) sin usar punto flotante.
; -----------------------------------------------------------------------------
print_fix2:
    push    rbx
    mov     rax, rdi
    xor     edx, edx
    mov     ecx, 100
    div     rcx
    mov     rbx, rdx                    ; RBX = los centésimos
    mov     rdi, rax
    call    print_u64
    mov     edi, '.'
    call    print_char
    cmp     rbx, 10                     ; si es menor a 10 le ponemos el 0 de adelante
    jae     .two
    mov     edi, '0'
    call    print_char
.two:
    mov     rdi, rbx
    call    print_u64
    pop     rbx
    ret

; print_hex: RDI = valor, RSI = cuántos dígitos hex queremos ver
print_hex:
    lea     r8, [rel numbuf]
    lea     r9, [rel hexdigits]
    mov     rcx, rsi
    mov     rdx, rsi
.loop:
    mov     eax, edi
    and     eax, 0xF                    ; agarramos el último dígito hex
    mov     al, [r9 + rax]
    mov     [r8 + rcx - 1], al
    shr     rdi, 4
    dec     rcx
    jnz     .loop
    mov     rsi, r8
    jmp     write_out

; print_size: RDI = bytes -> lo imprime en KB, MB o GB
print_size:
    cmp     rdi, 1 << 30
    jae     .gb
    cmp     rdi, 1 << 20
    jae     .mb
    shr     rdi, 10
    call    print_u64
    PRINT   str_kb
    ret
.mb:
    lea     rax, [rel str_mb]
    mov     esi, 1 << 20
    jmp     .frac
.gb:
    lea     rax, [rel str_gb]
    mov     esi, 1 << 30
.frac:
    push    rax                         ; guardamos la unidad para el final
    call    ratio_x100
    mov     rdi, rax
    call    print_fix2
    pop     rdi
    jmp     print_str

; print_yesno: EDI = 0 -> "No", cualquier otro -> "Sí"
print_yesno:
    lea     rax, [rel str_no]
    lea     rdx, [rel str_yes]
    test    edi, edi
    cmovnz  rax, rdx
    mov     rdi, rax
    jmp     print_str

; -----------------------------------------------------------------------------
; ratio_x100: RAX = (RDI * 100) / RSI, redondeado.
; Con esto sacamos divisiones con 2 decimales sin usar punto flotante.
; -----------------------------------------------------------------------------
ratio_x100:
    test    rsi, rsi
    jz      .zero                       ; no vamos a dividir entre 0
    mov     rax, rdi
    mov     ecx, 100
    mul     rcx
    mov     rcx, rsi
    shr     rcx, 1
    add     rax, rcx                    ; + den/2 para redondear
    adc     rdx, 0
    div     rsi
    ret
.zero:
    xor     eax, eax
    ret

; cycles_to_ns: RDI = ciclos del TSC -> RAX = nanosegundos (ciclos*1e9/tsc_hz)
cycles_to_ns:
    mov     rcx, [rel tsc_hz]
    test    rcx, rcx
    jz      .zero
    mov     rax, rdi
    mov     edx, 1000000000
    mul     rdx
    div     rcx
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; mem_alloc: RDI = bytes, ESI = opciones extra -> RAX = dirección del bloque
; Si falla devuelve un número negativo (el código de error).
; -----------------------------------------------------------------------------
mem_alloc:
    mov     r10d, MAP_ANON_PRIV
    or      r10d, esi
    mov     rsi, rdi                    ; largo
    xor     edi, edi                    ; que el kernel escoja la dirección
    mov     edx, PROT_RW
    mov     r8, -1                      ; sin archivo
    xor     r9d, r9d
    mov     eax, SYS_MMAP
    syscall
    ret

; -----------------------------------------------------------------------------
; err_report: RDI = mensaje, RSI = código de error (viene negativo).
; Imprime "ERROR: <mensaje> (errno N)".
; -----------------------------------------------------------------------------
err_report:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    PRINT   s_err_prefix
    mov     rdi, rbx
    call    print_str
    PRINT   s_errno
    mov     rdi, r12
    neg     rdi                         ; viene negativo, lo volteamos
    call    print_u64
    PRINT   s_paren_nl
    pop     r12
    pop     rbx
    ret

; exit_program: EDI = código de salida. De aquí ya no se regresa.
exit_program:
    mov     eax, SYS_EXIT
    syscall

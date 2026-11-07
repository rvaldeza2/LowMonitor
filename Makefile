# LowMonitor - compilación automática
# Se necesita: nasm (>= 2.15), GNU ld y make

ASM      = nasm
ASMFLAGS = -f elf64 -g -F dwarf
LD       = ld
TARGET   = lowmonitor
SRC      = lowmonitor.asm
INCS     = $(wildcard src/*.asm)

.PHONY: all run run-io bench clean

all: $(TARGET)

# Enlazamos sin libc, el punto de entrada es _start
$(TARGET): $(TARGET).o
	$(LD) -o $@ $<

# Los módulos entran con %include, por eso si cambia cualquiera se recompila
$(TARGET).o: $(SRC) $(INCS)
	$(ASM) $(ASMFLAGS) -o $@ $(SRC)

# Corre todos los módulos sin pasar por el menú
run: $(TARGET)
	./$(TARGET) all

# Módulo 2 con acceso real a los puertos (pide root)
run-io: $(TARGET)
	sudo ./$(TARGET) 2

# Todo amarrado al núcleo 0 para que las mediciones no brinquen entre núcleos P/E
bench: $(TARGET)
	taskset -c 0 ./$(TARGET) all

clean:
	rm -f $(TARGET).o $(TARGET)

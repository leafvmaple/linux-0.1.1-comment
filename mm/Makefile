CC := gcc
CFLAGS := -O -m32 -Wall -fstrength-reduce -fomit-frame-pointer -finline-functions -nostdinc -I../include
LD  := ld
LDFLAGS := -m elf_i386 -nostdlib
CPP	:= gcc -E -nostdinc -I../include

.c.o:
	$(CC) $(CFLAGS) \
	-c -o $*.o $<
.s.o:
	$(CC) $(CFLAGS) -c -Os -o $*.o $<
.c.s:
	$(CC) $(CFLAGS) \
	-S -o $*.s $<

OBJS := memory.o page.o

all: mm.o

mm.o: $(OBJS)
	$(LD) $(LDFLAGS) -r -o mm.o $^

clean:
	rm -f core *.o *.a tmp_make
	for i in *.c;do rm -f `basename $$i .c`.s;done

dep:
	sed '/\#\#\# Dependencies/q' < Makefile > tmp_make
	(for i in *.c;do $(CPP) -M $$i;done) >> tmp_make
	cp tmp_make Makefile

### Dependencies:
memory.o : memory.c ../include/signal.h ../include/sys/types.h \
  ../include/asm/system.h ../include/linux/sched.h ../include/linux/head.h \
  ../include/linux/fs.h ../include/linux/mm.h ../include/linux/kernel.h 

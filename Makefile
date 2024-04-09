#
# if you want the ram-disk device, define this to be the
# size in blocks.
#

LD      := ld
LDFLAGS := -m elf_i386 -nostdlib

CC	:= gcc
CFLAGS := -g -fno-builtin -Wall -ggdb -march=i386 -m32 -gstabs -nostdinc -fno-stack-protector

HOSTCC := gcc
HOSTCFLAGS := -g -Wall -O2

CPP	=cpp -nostdinc -Iinclude

DASM = ndisasm

QEMU := qemu-system-i386
TERMINAL :=gnome-terminal

OBJDUMP := objdump
OBJCOPY := objcopy

#
# ROOT_DEV specifies the default root-device when making the image.
# This can be either FLOPPY, /dev/xxxx or empty, in which case the
# default of /dev/hd6 is used by 'build'.
#
ROOT_DEV=/dev/hd6

ARCHIVES := kernel/kernel.o mm/mm.o fs/fs.o
DRIVERS  := kernel/blk_drv/blk_drv.a kernel/chr_drv/chr_drv.a
MATH	 := kernel/math/math.a
LIBS	 := lib/lib.a

.c.s:
	$(CC) $(CFLAGS) -nostdinc -Iinclude -S -o $*.s $<
.s.o:
	$(CC) $(CFLAGS) -c -Os -o $*.o $<

.c.o:
	$(CC) $(CFLAGS) -nostdinc -Iinclude -c -o $*.o $<

linux.img: boot/bootsect.bin boot/setup.bin
	dd if=/dev/zero of=$@ count=8064
	dd if=boot/bootsect.bin of=$@ conv=notrunc
	dd if=boot/setup.bin of=$@ seek=1 conv=notrunc

debug: linux.img
	$(QEMU) -S -s -parallel stdio -hda $< -serial null &
	sleep 2
	$(TERMINAL) -e "gdb -q -x tools/gdbinit"

boot/head.o: boot/head.s

tools/system: boot/head.o init/main.o $(ARCHIVES) $(DRIVERS) $(MATH) $(LIBS)
	$(LD) $(LDFLAGS) boot/head.o init/main.o $(ARCHIVES) $(DRIVERS) $(MATH) $(LIBS) -o tools/system > System.map

kernel/math/math.a:
	(cd kernel/math; make)

kernel/blk_drv/blk_drv.a:
	(cd kernel/blk_drv; make)

kernel/chr_drv/chr_drv.a:
	(cd kernel/chr_drv; make)

kernel/kernel.o:
	(cd kernel; make)

mm/mm.o:
	(cd mm; make)

fs/fs.o:
	(cd fs; make)

lib/lib.a:
	(cd lib; make)

boot/setup: boot/setup.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x0 $@.o -o $@
	$(OBJDUMP) -S $@ > $@.gas

boot/bootsect: boot/bootsect.o
	$(LD) $(LDFLAGS) -N -e _start -Ttext 0x0 $< -o $@
	$(OBJDUMP) -S $@ > $@.gas

boot/setup.bin: boot/setup
	$(OBJCOPY) -S -O binary boot/setup $@
	$(DASM) -b 16 $@ > boot/setup.disasm

boot/bootsect.bin: boot/bootsect
	$(OBJCOPY) -S -O binary boot/bootsect $@
	$(DASM) -b 16 $@ > boot/bootsect.disasm

tmp.s:	boot/bootsect.s tools/system
	(echo -n "SYSSIZE = (";ls -l tools/system | grep system \
		| cut -c25-31 | tr '\012' ' '; echo "+ 15 ) / 16") > tmp.s
	cat boot/bootsect.s >> tmp.s

clean:
	rm -f linux.img Image System.map tmp_make core boot/bootsect boot/bootsect.bin boot/setup
	rm -f init/*.o tools/system tools/build boot/*.o
	(cd mm;make clean)
	(cd fs;make clean)
	(cd kernel;make clean)
	(cd lib;make clean)

backup: clean
	(cd .. ; tar cf - linux | compress - > backup.Z)
	sync

dep:
	sed '/\#\#\# Dependencies/q' < Makefile > tmp_make
	(for i in init/*.c;do echo -n "init/";$(CPP) -M $$i;done) >> tmp_make
	cp tmp_make Makefile
	(cd fs; make dep)
	(cd kernel; make dep)
	(cd mm; make dep)

### Dependencies:
init/main.o: init/main.c include/unistd.h include/sys/stat.h \
  include/sys/types.h include/sys/times.h include/sys/utsname.h \
  include/utime.h include/time.h include/linux/tty.h include/termios.h \
  include/linux/sched.h include/linux/head.h include/linux/fs.h \
  include/linux/mm.h include/signal.h include/asm/system.h include/asm/io.h \
  include/stddef.h include/stdarg.h include/fcntl.h 

bochs: linux.img
	bochs -q -f bochsrc.bxrc
#include "asm.h"
#
#	setup.s		(C) 1991 Linus Torvalds
#
# setup.s is responsible for getting the system data from the BIOS,
# and putting them into the appropriate places in system memory.
# both setup.s and system has been loaded by the bootblock.
#
# This code asks the bios for memory/disk/other parameters, and
# puts them in a "safe" place: 0x90000-0x901FF, ie where the
# boot-block used to be. It is then up to the protected mode
# system to read them from there before the area is overwritten
# for buffer-blocks.
#

# NOTE; These had better be the same as in bootsect.s;

.set INITSEG, 0x9000	# we move boot here - out of the way
.set SYSSEG, 0x1000		# system loaded at 0x10000 (65536).
.set SETUPSEG, 0x9020	# this is the current segment

.code16
.globl start

start:

# ok, the read went well so we get current cursor position and save it for
# posterity.
# ah=0x3, int0x10 -> DH=Row, DL=Colunm
	mov $INITSEG, %ax 	# this is done in bootsect already, but...
	mov %ax     , %ds
	mov $0x03   , %ah	# read cursor pos
	xor %bh     , %bh
	int $0x10			# save it in known place, con_init fetches
	mov %dx     , 0	# save data to 0x90000.

# Get memory size (extended mem, kB)
# ah=0x88, int0x15 -> AH=Memory Size (KB)
	mov $0x88, %ah 
	int	$0x15
	mov	%ax  , 2

# Get video-card data:
# ah=0x0f, int0x10 -> AH=Screen Width(Chars), AL=Video Mode, BH=Video Page
# Video Mode 3: 80 x 25 CGA, EGA B800
	mov	$0x0f, %ah
	int	$0x10
	mov	%bx  , 4 		# bh = display page
	mov	%ax  , 6		# al = video mode, ah = window width

# check for EGA/VGA and some config parameters
# ah=12h, bl=10h, int10h -> bh=BIOS setup, bl=Mem Size Code, ch=Feature Bits, cl=Switch Settings
# Mem Size Code 3: 256K
	mov	$0x12, %ah
	mov	$0x10, %bl
	int	$0x10
	mov	%ax  , 8
	mov	%bx  , 10		# bh=BIOS setup, bl=Mem Size Code
	mov	%cx  , 12		# ch=Feature Bits, cl=Switch Settings

# Get hd0 data
# Get HD0 Data to [0x90080, 0x90090)
	mov $0x0    , %ax
	mov	%ax     , %ds
	lds	4 * 0x41, %si	# Int 0x41 is Get HD0 Param Pointers, located in 0x41 * 4(Interupt Size)
	mov	$INITSEG, %ax
	mov	%ax     , %es
	mov	$0x80   , %di
	mov	$0x10   , %cx
	rep
	movsb				# move [cx] bytes ds:si to es:di

# Get hd1 data
# Get HD0 Data to [0x90090, 0x900A0)
	mov $0x0    , %ax
	mov	%ax     , %ds
	lds	4 * 0x46, %si	# Int 0x46 is Get HD1 Param Pointers, located in 0x46 * 4(Interupt Size)
	mov	$INITSEG, %ax
	mov	%ax     , %es
	mov	$0x90   , %di
	mov	$0x10   , %cx
	rep
	movsb				# move [cx] bytes ds:si to es:di

# Check that there IS a hd1 :-)

	mov $0x01500, %ax
	mov	$0x81   , %dl	# dl=0x81: HD1
	int	$0x13
	jc	no_disk1		# CF is set to CY: Error
	cmp	$3      , %ah   # ah=0x3: it's a hard disk
	je	is_disk1
no_disk1:				# reset [0x90090, 0x90100)
	mov	$INITSEG, %ax
	mov	%ax     , %es
	mov	$0x90   , %di
	mov	$0x10   , %cx
	mov	$0x00   , %ax
	rep
	stosb
is_disk1:

# now we want to move to protected mode ...

	cli					# no interrupts allowed ;

# first we move the system to it's rightful place
# move [0x10000, 0x90000) to [0x00000, 0x80000)]
	mov $0x0000, %ax
	cld					# 'direction'=0, movs moves forward
do_move:
	mov %ax, %es 		# destination segment
	add	$0x1000, %ax
	cmp	$0x9000, %ax 
	jz	end_move
	mov	%ax, %ds 		# source segment
	xor	%di, %di
	xor	%si, %si
	mov $0x8000, %cx 	# 0x8000 Words = 0x10000 Bytes
	rep
	movsw
	jmp	do_move

# then we load the segment descriptors

end_move:
	mov $SETUPSEG, %ax 	# right, forgot this at first. didn't work :-)
	mov	%ax      , %ds

	lidt idt_48			# load idt with 0, 0; lidt ds:idt_48
	lgdt gdt_48			# load gdt with whatever appropriate; lgdt ds:gdt_48

# that was painless, now we enable A20

	call empty_8042
	mov	 $0xD1, %al		# command write
	outb %al  , $0x64
	call empty_8042
	mov  $0xDF, %al		# A20 on
	outb %al  , $0x60
	call empty_8042

# well, that went ok, I hope. Now we have to reprogram the interrupts :-(
# we put them right after the intel-reserved hardware interrupts, at
# int 0x20-0x2F. There they won't mess up anything. Sadly IBM really
# messed this up with the original PC, and they haven't been able to
# rectify it afterwards. Thus the bios puts interrupts at 0x08-0x0f,
# which is used for the internal hardware interrupts as well. We just
# have to reprogram the 8259's, and it isn't fun.

#	mov	al,$0x11		# initialization sequence
#	out	$0x20,al		# send it to 8259A-1
#	.word	0x00eb,0x00eb		# jmp $+2, jmp $+2
#	out	$0xA0,al		# and to 8259A-2
#	.word	0x00eb,0x00eb
#	mov	al,$0x20		# start of hardware int's (0x20)
#	out	$0x21,al
#	.word	0x00eb,0x00eb
#	mov	al,$0x28		# start of hardware int's 2 (0x28)
#	out	$0xA1,al
#	.word	0x00eb,0x00eb
#	mov	al,$0x04		# 8259-1 is master
#	out	$0x21,al
#	.word	0x00eb,0x00eb
#	mov	al,$0x02		# 8259-2 is slave
#	out	$0xA1,al
#	.word	0x00eb,0x00eb
#	mov	al,$0x01		# 8086 mode for both
#	out	$0x21,al
#	.word	0x00eb,0x00eb
#	out	$0xA1,al
#	.word	0x00eb,0x00eb
#	mov	al,$0xFF		# mask off all interrupts for now
#	out	$0x21,al
#	.word	0x00eb,0x00eb
#	out	$0xA1,al

# well, that certainly wasn't fun :-(. Hopefully it works, and we don't
# need no steenking BIOS anyway (except for the initial loading :-).
# The BIOS-routine wants lots of unnecessary data, and it's less
# "interesting" anyway. This is how REAL programmers do it.
#
# Well, now's the time to actually move into protected mode. To make
# things as simple as possible, we do no register set-up or anything,
# we let the gnu-compiled 32-bit programs do that. We just jump to
# absolute address 0x00000, in 32-bit protected mode.

	mov	$0x0001, %ax 	# protected mode (PE) bit
	lmsw %ax			# This is it;
	jmp $8     , $0		# jmp offset 0 of segment 8 (cs), gdd[1]

# This routine checks that the keyboard command queue is empty
# No timeout is used - if this hangs there is something wrong with
# the machine, and we probably couldn't proceed anyway.
empty_8042:
	in   $0x64, %al		# 8042 status port
	test $2   , %al		# is input buffer full?
	jnz	 empty_8042		# yes - loop
	ret

gdt:					# seg for bootloader and kernel
	SEG_NULLASM								# dummy
	SEG_ASM(STA_X|STA_R, 0x0, 0x7fffff)		# code, limit=8MB
    SEG_ASM(STA_W, 0x0, 0x7fffff)			# data, limit=8MB		

idt_48:
	.word 0			# idt limit=0
	.word 0, 0		# idt base=0L

gdt_48:
	.word 0x800					# gdt limit=2048, 256 GDT entries
	.long SETUPSEG << 4 + gdt	# gdt base = 0x90200 + [gdt]

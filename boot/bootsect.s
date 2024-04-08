#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
.set SYSSIZE, 0x3000
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE; currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

.set SETUPLEN, 4					# nr of setup-sectors
.set BOOTSEG, 0x07c0				# original address of boot-sector
.set INITSEG, 0x9000				# we move boot here - out of the way
.set SETUPSEG, 0x9020				# setup starts here
.set SYSSEG, 0x1000					# system loaded at 0x10000 (65536).
.set ENDSEG, SYSSEG + SYSSIZE		# where to stop loading

.set ROOT_DEV, 0x306

.code16
.globl begtext, begdata, begbss, endtext, enddata, endbss, start
.text
begtext:
.data
begdata:
.bss
begbss:
.text

# ROOT_DEV:	0x000 - same type of floppy as boot.
#		0x301 - first partition on first drive etc

start:
# ||| copy [0x7c00, 0x7e00) to [0x90000, 0x90200)
	movw $BOOTSEG , %ax
	movw %ax      , %ds
	movw $INITSEG , %ax 
	movw %ax      , %es 
	movw $0x100   , %cx	# 256 Words = 512 Bytes
	xorw %si      , %si
	xorw %di      , %di
	rep
	movsw
	ljmpw $INITSEG, $go	# jump to INITSEG:go -> cs=0x9000, ip=go

go:
	movw %cs, %ax
	movw %ax, %ds
	movw %ax, %es
# put stack at 0x0xFF00.
	movw %ax, %ss
# Stack in ss:sp=0x90400
	movw $0xFF00, %sp	# arbitrary value >> 512 

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.

# ||| Load Cylinder[0] Head[0] Sector[2] 4 Sectors(2KB) to ES:BX [0x90200, 0x90A00)
load_setup:
	movw $0x0080, %dx	# drive 0, head 0
	movw $0x0002, %cx	# sector 2, track 0
	movw $0x0200, %bx	# address = cs:0x200 = 0x90200
	movw $0x0200 + SETUPLEN, %ax	# service 2, nr of sectors
	int	 $0x13			# read it
	jnc	 ok_load_setup	# ok - continue
	movw $0x0000, %dx
	movw $0x0000, %ax	# reset the diskette
	int  $0x13
	jmp  load_setup

ok_load_setup:

# ||| Print Message!

# Get disk drive parameters, specifically nr of sectors/track
# AH=0x8, INT0x13 -> DL=Drives, CH=Cylinders-1, DH=Heads-1, CL=Sectors
	movb $0x80   , %dl
	movw $0x0800 , %ax 		# AH=8 is get drive parameters
	int	 $0x13
	mov  $1 , %eax
	add  $1 , %ch
	add  $1 , %dh
	mul  %ch
	mul  %dh
	xor  %ch, %ch
	mul  %cx
	# movw %ax     , sectors
	movw $127	 , sectors
	movw $INITSEG, %ax
	movw %ax     , %es

# Print some inane message
# AH=0x3, INT0x10 -> DH=Row, DL=Colunm
	movb $0x03 , %ah			# read cursor pos
	xor	 %bh   , %bh
	int	 $0x10
# AH=0x13, INT0x10, AL=Write Mode, BH=Page, BL=Color, CX=Char Numbers, DH=Row, DL=Column, ES:BP=String Offset
	movw $24    , %cx       # Countof msg1 is 24
	mov  $0x0007, %bx		# page 0, attribute 7 (normal)
	mov  $msg1   , %bp
	mov  $0x1301, %ax 		# write string, move cursor
	int  $0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	mov  $SYSSEG, %ax
	mov  %ax    , %es			# segment of 0x010000
	call read_it
#	call kill_motor				# Turns Off Floppy

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	ljmp $SETUPSEG, $0	# jump to INITSEG:0 -> cs=0x9020, ip=0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#

# move to es
read_it:
	xor %bx, %bx		# bx is starting address within segment

	# read track
    mov  $dap , %si
    movb $0x42, %ah                                 # AH=0x42, LAB模式读取磁盘
    movb $0x80, %dl                                 # DL=0, Driver 0
    int  $0x13
	ret

.align 16
dap:
    .byte 0x10
    .byte 0x00
sectors:
    .word 0
    .word 0x00
    .word SYSSEG
sread:
    .quad 1 + SETUPLEN

#sectors:
#	.word 0

msg1:
	.ascii "\r\nLoading system ...\r\n\r\n"

.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:

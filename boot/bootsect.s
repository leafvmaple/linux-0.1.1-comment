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
# ||| copy [0x7c00] 512B to [0x90000]
	movw $BOOTSEG, %ax
	movw %ax, %ds
	movw $INITSEG, %ax 
	movw %ax, %es 
	movw $0x100, %cx	# 256 Words = 512 Bytes
	xorw %si, %si
	xorw %di, %di
	rep
	movsw
#	ljmp $INITSEG, $go	# jump to INITSEG:go -> cs=0x9000, ip=go

go:	movw %cs, %ax
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
	movw $0x0200, %bx	# address = 512, in INITSEG
	movw $0x0200 + SETUPLEN, %ax	# service 2, nr of sectors
	int	$0x13			# read it
	jnc	ok_load_setup	# ok - continue
	movw $0x0000, %dx
	movw $0x0000, %ax	# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:

# ||| Print Message!

# Get disk drive parameters, specifically nr of sectors/track

	movb $0x80, %dl
	movw $0x0800, %ax 		# AH=8 is get drive parameters
	int	$0x13
	movb $0x00, %ch 
	movw %cx, sectors		# [sectors] = sectors of driver
	movw $INITSEG, %ax
	movw %ax, %es

# Print some inane message

	movb $0x03, %ah			# read cursor pos
	xor	%bh, %bh
	int	$0x10
	
	movw $24, %cx
	mov $0x0007, %bx		# page 0, attribute 7 (normal)
	mov	msg1, %bp
	mov	$0x1301, %ax 		# write string, move cursor
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	mov	$SYSSEG, %ax
	mov	%ax, %es			# segment of 0x010000
	call read_it
	call kill_motor

# After that we check which root-device to use. If the device is
# defined (!= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	movw root_dev, %ax
	cmp	$0, %ax
	jne	root_defined
	mov sectors, %bx
	mov $0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx
	je	root_defined
	mov $0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	mov %ax, root_dev

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	ljmp $SETUPSEG, $0

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	.word 1 + SETUPLEN	# sectors read of current track
head:	.word 0			# current head
track:	.word 0			# current track

# move to es
read_it:
	mov %es, %ax
	test $0x0fff, %ax
die: jne die			# es must be at 64kB boundary
	xor %bx, %bx		# bx is starting address within segment
rp_read:
	mov %es, %ax 
	cmp $ENDSEG, %ax	# have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	mov sectors, %ax
	sub sread, %ax
	mov %ax, %cx		# cx = sectors - 5
	shl $9, %cx			# cx * 512
	add %bx, %cx
	jnc ok2_read
	je ok2_read
	xor %ax, %ax
	sub %bx, %ax 
	shr $9, %ax
ok2_read:
	call read_track
	mov %ax, %cx
	add sread, %ax
	cmp sectors, %ax
	jne ok3_read
	mov $1, %ax
	sub head, %ax
	jne ok4_read
	incw track
ok4_read:
	mov %ax, head
	xor %ax, %ax
ok3_read:
	mov %ax, sread
	shl $9, %cx
	add %cx, %bx
	jnc rp_read
	mov %es, %ax
	add $0x1000, %ax
	mov %ax, %es
	xor %bx, %bx
	jmp rp_read

# read [ax] sectors from C[track] H[head] S[sread]
read_track:
	push %ax
	push %bx
	push %cx
	push %dx
	mov track, %dx		# DL = track
	mov sread, %cx		# CL = spead
	inc %cx				# CL = ++sread, 读取sread号扇区
	mov %dl, %ch		# CH=track, 读取track号柱面
	mov head, %dx		# DL=head
	mov %dl, %dh		# DH=head
	mov $0, %dl			# DL=0, Driver 0
	and $0x0100, %dx	# DH=head&1, 读取第head&1磁头
	mov $2, %ah			# AH=2, 读磁盘
	int $0x13
	jc bad_rt
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	ret
bad_rt:	mov $0, %ax
	mov $0, %dx
	int $0x13
	pop %dx
	pop %cx
	pop %bx
	pop %ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push %dx
	mov $0x3f2, %dx
	mov $0, %al
	outb %al, %dx
	pop %dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

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

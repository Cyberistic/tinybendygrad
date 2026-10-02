	.text
	.globl _f
_f:
	mov	x0, #1
	ret
	.data
	.globl _d
_d:	.word	7
	.section	.note.GNU-stack,"",@progbits

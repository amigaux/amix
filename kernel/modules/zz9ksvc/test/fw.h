/*
 * fw.h -- the host test's stand-in runtime (fw.c), in plain types.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#define FW_MBOXLEN	8192
#define FW_HEAP_ARM	0x01000000UL	/* the host-visible heap, in the firmware's addresses */
#define FW_HEAP_LEN	0x01000000UL	/* 16 MiB */
#define FW_NBUF		256

struct fw_state {
	int		reqn, cmpn;
	int		hold;		/* take nothing while set */
	unsigned	park_op;	/* take requests with this opcode, answer them only at fw_unpark */
	unsigned char	parked[8][64];
	int		nparked;
	int		dead;		/* never answer again */
	int		delay, wait;	/* steps between answers */
	unsigned	status;		/* nonzero: answer service requests with it */
	unsigned	alloc_status;	/* nonzero: fail ALLOC_SHARED with it */
	int		alloc_outside;	/* place the next buffers outside the window */
	unsigned	alloc_extra;	/* report this many bytes more than asked */
	unsigned long	next_handle;
	unsigned long	live[FW_NBUF];	/* handles allocated and not freed */
	unsigned long	live_arm[FW_NBUF], live_len[FW_NBUF];	/* where each lies */
	int		nlive, nalloc, nfree, bad_free, not_queued, steps;
	unsigned	last_op;
	unsigned char	last_payload[48];
	unsigned long	last_align, last_alloc_flags;
};

extern unsigned char fw_mbox[FW_MBOXLEN];
extern struct fw_state fw;
void fw_init(int reqn, int cmpn, unsigned long caps);
void fw_restart(void);
unsigned char *fw_heap_at(unsigned long arm);
unsigned long fw_alg_raw(void), fw_alg_zlib(void), fw_alg_gzip(void);
unsigned long fw_deflate(unsigned long alg, const unsigned char *src, unsigned long n,
    unsigned char *dst, unsigned long cap);
unsigned long fw_crc32(const unsigned char *p, unsigned long n);
void fw_break(int how);
void fw_step(void);
void fw_stray(unsigned long id);
int fw_queued(void);
void fw_unpark(void);
unsigned long fw_caps_mailbox(void), fw_op_decompress(void), fw_op_decompress_test(void);
unsigned long fw_op_ping(void), fw_op_query_caps(void), fw_op_module_status(void);
unsigned long fw_op_mem_copy(void), fw_status_ok(void), fw_status_bad_handle(void);

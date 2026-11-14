/*
 * zhostk.h -- the host tests' model of the kernel interfaces z3660eth.c
 * uses (every sys/*.h in inc/ includes it).  Names and fields are the
 * kernel's; the layouts are the host's own, which is all the tests need.
 */
#ifndef _ZHOSTK_H
#define _ZHOSTK_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

typedef char		*caddr_t;
typedef unsigned int	host_ulong;	/* the kernel's ulong: 32 bits */
#define ulong		host_ulong
typedef unsigned short	ushort;
typedef unsigned short	u_short;
typedef unsigned char	u_char;
typedef unsigned long	dev_t;
typedef struct cred	cred_t;

#define HZ		60
#define NBPP		2048
#define PG_V		1
#define VSECT1		0x40000000UL
#define phystopfn(p)	((unsigned long)(p) >> 11)
extern unsigned char	*host_window;		/* stands for physical memory */
extern unsigned long	host_window_phys;
#define phystokv(p)	(host_window + ((unsigned long)(p) - host_window_phys))

/* STREAMS */
struct datab { unsigned char db_type; unsigned char *db_base, *db_lim; };
typedef struct msgb {
    struct msgb		*b_next, *b_prev, *b_cont;
    unsigned char	*b_rptr, *b_wptr;
    struct datab	*b_datap;
} mblk_t;
struct module_info {
    unsigned short mi_idnum; char *mi_idname;
    long mi_minpsz, mi_maxpsz; unsigned long mi_hiwat, mi_lowat;
};
struct qinit {
    int (*qi_putp)(); int (*qi_srvp)(); int (*qi_qopen)(); int (*qi_qclose)();
    int (*qi_qadmin)(); struct module_info *qi_minfo; void *qi_mstat;
};
struct streamtab {
    struct qinit *st_rdinit, *st_wrinit, *st_muxrinit, *st_muxwinit;
};
typedef struct queue {
    mblk_t		*q_first, *q_last;	/* the queue's messages */
    struct queue	*q_next;		/* read side: the stream head */
    char		*q_ptr;
    struct queue	*q_other;
    int			q_read;
    int			full;			/* stream head: canput fails */
    mblk_t		*up_first, *up_last;	/* stream head: what arrived */
} queue_t;
#define RD(q)		((q)->q_read ? (q) : (q)->q_other)
#define WR(q)		((q)->q_read ? (q)->q_other : (q))
#define OTHERQ(q)	((q)->q_other)

#define M_DATA		0x00
#define M_PROTO		0x01
#define M_IOCTL		0x0e
#define M_IOCDATA	0x26
#define M_PCPROTO	0x81
#define M_FLUSH		0x86
#define M_IOCACK	0x81 + 0x20
#define M_IOCNAK	0x81 + 0x21
#define M_COPYOUT	0x81 + 0x22
#define FLUSHR		0x01
#define FLUSHW		0x02
#define FLUSHALL	1
#define BPRI_MED	1
#define MODOPEN		1
#define CLONEOPEN	2
#define TRANSPARENT	(unsigned int)(-1)

struct iocblk {
    int ioc_cmd; void *ioc_cr; unsigned int ioc_id; unsigned int ioc_count;
    int ioc_error; int ioc_rval;
};
struct copyreq {
    int cq_cmd; void *cq_cr; unsigned int cq_id; caddr_t cq_addr;
    unsigned int cq_size; int cq_flag; mblk_t *cq_private;
};
struct copyresp {
    int cp_cmd; void *cp_cr; unsigned int cp_id; caddr_t cp_rval;
};
#define SIOCSIFFLAGS	0x8010
#define SIOCGIFFLAGS	0x8011

struct ifstats {
    struct ifstats *ifs_next; char *ifs_name; short ifs_unit; short ifs_active;
    void *ifs_addrs; short ifs_mtu;
    int ifs_ipackets, ifs_ierrors, ifs_opackets, ifs_oerrors, ifs_collisions;
};

/* DLPI, the stock header's names */
#define DL_INFO_REQ	0x00
#define DL_BIND_REQ	0x01
#define DL_UNBIND_REQ	0x02
#define DL_INFO_ACK	0x03
#define DL_BIND_ACK	0x04
#define DL_ERROR_ACK	0x05
#define DL_OK_ACK	0x06
#define DL_UNITDATA_REQ	0x07
#define DL_UNITDATA_IND	0x08
#define DL_ATTACH_REQ	0x0b
#define DL_DETACH_REQ	0x0c
#define DL_UNBOUND	0x00
#define DL_IDLE		0x03
#define DL_BADSAP	0x00
#define DL_BADPRIM	0x09
#define DL_ETHER	0x04
#define DL_CLDLS	0x02
#define DL_STYLE1	0x0500
typedef struct { ulong dl_primitive; } dl_info_req_t;
typedef struct {
    ulong dl_primitive, dl_max_sdu, dl_min_sdu, dl_addr_length, dl_mac_type,
	dl_reserved, dl_current_state, dl_max_idu, dl_service_mode,
	dl_qos_length, dl_qos_offset, dl_qos_range_length, dl_qos_range_offset;
    long dl_provider_style;
    ulong dl_addr_offset, dl_growth;
} dl_info_ack_t;
typedef struct {
    ulong dl_primitive, dl_sap, dl_max_conind;
    ushort dl_service_mode, dl_conn_mgmt;
} dl_bind_req_t;
typedef struct {
    ulong dl_primitive, dl_sap, dl_addr_length, dl_addr_offset, dl_max_conind,
	dl_growth;
} dl_bind_ack_t;
typedef struct { ulong dl_primitive, dl_correct_primitive; } dl_ok_ack_t;
typedef struct {
    ulong dl_primitive, dl_error_primitive, dl_errno, dl_unix_errno;
} dl_error_ack_t;
typedef struct {
    ulong dl_primitive, dl_dest_addr_length, dl_dest_addr_offset, dl_reserved[2];
} dl_unitdata_req_t;
typedef struct {
    ulong dl_primitive, dl_dest_addr_length, dl_dest_addr_offset,
	dl_src_addr_length, dl_src_addr_offset, dl_reserved;
} dl_unitdata_ind_t;
union DL_primitives {
    ulong dl_primitive;
    dl_info_ack_t info_ack;
    dl_bind_req_t bind_req;
    dl_unitdata_req_t unitdata_req;
};

#define getminor(d)	((int)((d) & 0xff))
#define getmajor(d)	((int)(((d) >> 8) & 0xff))
#define makedevice(ma, mi) ((dev_t)(((ma) << 8) | (mi)))

#define CE_CONT		0
#define CE_NOTE		1
void	cmn_err(int, char *, ...);


mblk_t	*allocb(), *getq();
void	freemsg(), putnext(), qreply(), flushq();
int	putq(), putbq(), canput();
int	timeout();
void	untimeout();
extern long	lbolt;
extern char	*panicstr;
int	spl6(), splx();
#define splxs()		spl6()
int	intr_attach(), intr_detach(), if_attach(), if_detach();
int	autocon(), bprobe();
caddr_t	sptalloc();
void	sptfree();

/* what z3660eth.c needs beyond the common model */
typedef unsigned long	paddr_t;
#define DL_UNATTACHED	0x04
#define IFF_BROADCAST	0x2
#define IFF_NOTRAILERS	0x20
#define IFF_RUNNING	0x40
#define PZERO		25
void	wakeup();
int	sleep();

#endif

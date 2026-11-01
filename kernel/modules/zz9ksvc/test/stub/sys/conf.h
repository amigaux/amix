struct bdevsw { int (*d_open)(); int (*d_close)(); int (*d_strategy)(); int (*d_print)(); };
struct cdevsw { int (*d_open)(); int (*d_close)(); int (*d_read)(); int (*d_write)();
	int (*d_ioctl)(); int (*d_mmap)(); };

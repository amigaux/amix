struct mod_drv_data {
	struct bdevsw drv_bdevsw; int drv_bmajor, drv_bcount;
	struct cdevsw drv_cdevsw; int drv_cmajor, drv_ccount;
};
#define MOD_DRV_WRAPPER(p, l, u, h, d) \
	int (*td_load)(char *) = l; int (*td_unload)(void) = u; char *td_desc = d

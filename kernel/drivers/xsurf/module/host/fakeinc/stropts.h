/* stropts.h -- the host's stand-in for the box's, for t_xsf.c */
#ifndef _FAKE_STROPTS_H
#define _FAKE_STROPTS_H
#define I_STR	(('S' << 8) | 010)
struct strioctl {
    int		ic_cmd;
    int		ic_timout;
    int		ic_len;
    char	*ic_dp;
};
int	ioctl(int, int, ...);
#endif

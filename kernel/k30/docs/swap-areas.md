# Swap areas on the k30 kernel: how large one area may be

From cut 68030-261106-72 the kernel refuses a swap area (`swap -a` prints `SC_ADD failed` and `swap: Not enough space`)
whose anon array, 16 bytes for every 2 KiB page of the area,

1. would take more than an eighth of `maxmem` (the kernel's count of pageable pages): at most 16 x `maxmem` pages,
   that is 32 KiB x `maxmem`, per area;
2. finds no free run of the kernel's map space (kvseg, 8 MiB) large enough, after 5 tries a second apart; or
3. would leave kvseg no free run of 1 MiB, when the array comes out of kvseg.

Each area is judged alone; there is no running total. The first area, the one the kernel adds at boot from its
configured swap device, is exempt from rules 1 and 3. `maxmem` can be read with
`echo maxmem/D | adb -k /stand/unix /dev/kmem`.

## Measured

Areas of 30, 64, 128, 192, 256, 384, 512 and 768 MiB added one at a time to a raw slice and removed again, on a
disk-booted 68030 in emulation with kvseg at 8 MiB and the guard of 68030-261106-72, at idle after boot and again after
a session (memck of 8, 20 or 40 MiB beside a 64 MiB file written and read back, `ls -lR /usr`, a tar of `/usr/lib`).

| RAM | maxmem | Rule 1 limit | Largest accepted, idle | After a session | First refused | Refused by |
|---|---|---|---|---|---|---|
| 16 MiB | 7104 | 222 MiB | 192 MiB | 192 MiB | 256 MiB | rule 1 |
| 32 MiB | 15021 | 469 MiB | 384 MiB | 384 MiB | 512 MiB | rule 1 |
| 64 MiB | 30855 | 964 MiB | 384 MiB | 384 MiB | 512 MiB | rule 3 |

Only the sizes listed were tried, so each limit lies between the last size accepted and the first refused. A 64 MiB
machine takes no more in one area than a 32 MiB one: its page array already fills more of kvseg. More swap is had with
more areas.

A RAM-disk installer has fewer pageable pages than the same machine booted from disk (`maxmem` 6119 at 16 MiB), so its
rule 1 limit is lower: 191 MiB at 16 MiB, where 128 MiB is the largest size of the list that fits.

# Changelog

## Unreleased

## 2026-10-26 — monsw: the console monitor switch as a module for k30 and k46 (b954ce9)

The source comes from amix-040-060-port ab53a85 src/monsw.c with the module glue under MONSW_MODULE; the static object is
byte-identical to the port's (59c76b95). include/sys/monsw.h is published, byte-equal to the port's. Module: class demand,
c:52, unload=never, param config:int:-1:-1:51; imports copyout, drv_priv, printf (+ the wrapper's mod_drvops); exports the
monsw_* API. modcheck ok on both lines (k30 7a5e2ff3, k46 82966137; 5109 B). Host test 87 checks; monsw/test/monswtest.c is
the /dev/monsw instrument. Package version monsw/module/VERSION 1.0.0-1 (monsw30 / monsw46; contents in monsw/README.md).

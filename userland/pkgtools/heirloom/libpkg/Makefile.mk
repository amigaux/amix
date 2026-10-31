INC = -I. -I../hdrs -I../libgendb

.c.o:
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(INC) $(PATHS) $(WARN) $<


OBJ = ainfo.o canonize.o ckparam.o ckvolseq.o cvtpath.o dbsql.o devtype.o \
	dsepoch.o dstream.o fmkdir.o gpkglist.o gpkgmap.o isdir.o nokeystore.o \
	logerr.o mappath.o ncgrpw.o nhash.o pkgerr.o \
	pkgexecl.o pkgexecv.o pkgmount.o pkgstr.o pkgtrans.o \
	pkgxpand.o ppkgmap.o progerr.o putcfile.o rrmdir.o runcmd.o \
	srchcfile.o tputcfent.o verify.o vfpops.o

all: libpkg.a

# AMIX PORT: putcfile/verify were once -O0-forced on the
# pkgdbmerg/do_like_ent path (see mk.config.amix MERGPATH_OPT) as a
# codegen precaution.  The real defect was the toolchain tdivs/tdivu
# remainder-divide miscompile (nhash.c HASH()), fixed in gcc-cross-amix
# 984192a (AMIX-PORT.md item 0); MERGPATH_OPT is now $(CFLAGS) => -O.
putcfile.o: putcfile.c
	$(CC) -c $(MERGPATH_OPT) $(CPPFLAGS) $(INC) $(PATHS) $(WARN) putcfile.c
verify.o: verify.c
	$(CC) -c $(MERGPATH_OPT) $(CPPFLAGS) $(INC) $(PATHS) $(WARN) verify.c
# AMIX PORT: ncgrpw/nhash are the name-cache init reached from averify's
# first attribute mismatch (v14) - and nhash.c HASH() is exactly where
# the tdivs.l modulo miscompile lived (HASH()'s "hv % hsz" lost its
# remainder register in GNU as 2.8.1).  The fix was in the TOOLCHAIN,
# not -O0 (gcc-cross-amix 984192a; AMIX-PORT.md item 0); MERGPATH_OPT is
# now $(CFLAGS) => both build at -O.
ncgrpw.o: ncgrpw.c
	$(CC) -c $(MERGPATH_OPT) $(CPPFLAGS) $(INC) $(PATHS) $(WARN) ncgrpw.c
nhash.o: nhash.c
	$(CC) -c $(MERGPATH_OPT) $(CPPFLAGS) $(INC) $(PATHS) $(WARN) nhash.c

libpkg.a: $(OBJ)
	$(AR) -rv $@ $(OBJ)
	$(RANLIB) $@

install: all

clean:
	rm -f libpkg.a $(OBJ) core log *~

mrproper: clean

ainfo.o: ainfo.c ./pkglib.h ../hdrs/pkgstrct.h pkglocale.h
canonize.o: canonize.c
ckparam.o: ckparam.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h pkglocale.h
ckvolseq.o: ckvolseq.c ../hdrs/pkgstrct.h ./pkglib.h ../hdrs/pkgdev.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h pkglocale.h
cvtpath.o: cvtpath.c
dbsql.o: dbsql.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h ../libgendb/genericdb.h \
  dbtables.h dbsql.h cfext.h pkglibmsgs.h ../hdrs/libadm.h
devtype.o: devtype.c ../hdrs/pkgdev.h ./pkglib.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h
dstream.o: dstream.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h pkglocale.h \
  ../hdrs/libadm.h
fmkdir.o: fmkdir.c pkglib.h
gpkglist.o: gpkglist.c ../hdrs/valtools.h ../hdrs/pkginfo.h ./pkglib.h \
  ../hdrs/pkgdev.h ../hdrs/pkgstrct.h ./pkgerr.h ./keystore.h ./cfext.h \
  ./pkglibmsgs.h pkglocale.h
gpkgmap.o: gpkgmap.c ../hdrs/pkgstrct.h pkglib.h ../hdrs/pkgdev.h \
  pkgerr.h keystore.h cfext.h pkglibmsgs.h pkglocale.h ../hdrs/libadm.h
isdir.o: isdir.c ../hdrs/archives.h pkglocale.h pkglibmsgs.h
nokeystore.o: nokeystore.c pkgerr.h keystore.h pkglib.h \
  ../hdrs/pkgdev.h ../hdrs/pkgstrct.h cfext.h pkglibmsgs.h
logerr.o: logerr.c pkglocale.h
mappath.o: mappath.c
ncgrpw.o: ncgrpw.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h nhash.h
nhash.o: nhash.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h nhash.h pkglocale.h
p12lib.o: p12lib.c p12lib.h
pkgerr.o: pkgerr.c pkgerr.h
pkgexecl.o: pkgexecl.c pkglocale.h pkglibmsgs.h ./pkglib.h \
  ../hdrs/pkgdev.h ../hdrs/pkgstrct.h ./pkgerr.h ./keystore.h ./cfext.h
pkgexecv.o: pkgexecv.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h pkglocale.h ../hdrs/libadm.h
pkgmount.o: pkgmount.c ../hdrs/pkgdev.h ../hdrs/pkginfo.h \
  ../hdrs/devmgmt.h ./pkglib.h ../hdrs/pkgstrct.h ./pkgerr.h ./keystore.h \
  ./cfext.h ./pkglibmsgs.h pkglocale.h
pkgstr.o: pkgstr.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h
pkgtrans.o: pkgtrans.c ../hdrs/pkginfo.h ../hdrs/pkgstrct.h \
  ../hdrs/pkgtrans.h ../hdrs/pkgdev.h ../hdrs/devmgmt.h ./pkglib.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h ./keystore.h \
  pkglocale.h pkgerr.h ../hdrs/libadm.h
pkgweb.o: pkgweb.c ../hdrs/libadm.h
pkgxpand.o: pkgxpand.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h
ppkgmap.o: ppkgmap.c ../hdrs/pkgstrct.h
progerr.o: progerr.c pkglocale.h pkgerr.h
putcfile.o: putcfile.c ../hdrs/pkgstrct.h pkglib.h ../hdrs/pkgdev.h \
  pkgerr.h keystore.h cfext.h ../hdrs/libadm.h
rrmdir.o: rrmdir.c pkglocale.h pkglib.h ../hdrs/pkgdev.h \
  ../hdrs/pkgstrct.h pkgerr.h keystore.h cfext.h
runcmd.o: runcmd.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h pkglibmsgs.h ../hdrs/libadm.h
security.o: security.c ../hdrs/pkgstrct.h ../hdrs/pkginfo.h pkgerr.h \
  pkglib.h ../hdrs/pkgdev.h keystore.h cfext.h pkglibmsgs.h pkglocale.h \
  p12lib.h
srchcfile.o: srchcfile.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h pkglibmsgs.h
tputcfent.o: tputcfent.c ../hdrs/pkgstrct.h pkglocale.h
verify.o: verify.c ../hdrs/pkgstrct.h ./pkglib.h ../hdrs/pkgdev.h \
  ./pkgerr.h ./keystore.h ./cfext.h ./pkglibmsgs.h pkglocale.h
vfpops.o: vfpops.c ./pkglib.h ../hdrs/pkgdev.h ../hdrs/pkgstrct.h \
  ./pkgerr.h ./keystore.h ./cfext.h pkglocale.h

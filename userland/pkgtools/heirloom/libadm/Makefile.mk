.c.o:
	$(CC) -c $(CFLAGS) $(CPPFLAGS) \
  -I../hdrs $(PATHS) $(WARN) $<


OBJ = ckdate.o ckgid.o ckint.o ckitem.o ckkeywd.o ckpath.o ckrange.o \
	ckstr.o cktime.o ckuid.o ckyorn.o data.o devattr.o devreserv.o \
	devtab.o dgrpent.o fulldevnm.o getdev.o getdgrp.o getinput.o \
	getvol.o listdev.o listdgrp.o pkginfo.o pkgnmchk.o pkgparam.o \
	putdev.o putdgrp.o puterror.o puthelp.o putprmpt.o puttext.o \
	rdwr_vtoc.o regexp.o space.o \
	strlcat.o strlcpy.o closefrom.o sigsend.o cftime.o getpass.o \
	mkdirp.o getopt.o $(COMPATOBJ)

all: libadm.a

libadm.a: $(OBJ)
	$(AR) -rv $@ $(OBJ)
	$(RANLIB) $@

install: all

clean:
	rm -f libadm.a $(OBJ) snprintf.o amixcompat.o fnmatch.o core log *~

mrproper: clean

ckdate.o: ckdate.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckgid.o: ckgid.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckint.o: ckint.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckitem.o: ckitem.c ../hdrs/valtools.h ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckkeywd.o: ckkeywd.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckpath.o: ckpath.c ../hdrs/valtools.h ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckrange.o: ckrange.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckstr.o: ckstr.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
cktime.o: cktime.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckuid.o: ckuid.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
ckyorn.o: ckyorn.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
data.o: data.c
devattr.o: devattr.c ../hdrs/devmgmt.h ../hdrs/devtab.h
devreserv.o: devreserv.c ../hdrs/devmgmt.h ../hdrs/devtab.h
devtab.o: devtab.c ../hdrs/devmgmt.h ../hdrs/devtab.h
dgrpent.o: dgrpent.c ../hdrs/devmgmt.h ../hdrs/devtab.h
fulldevnm.o: fulldevnm.c ../hdrs/sys/vfstab.h ../hdrs/libadm.h \
  ../hdrs/sys/vtoc.h ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h \
  ../hdrs/pkginfo.h ../hdrs/valtools.h ../hdrs/install.h
getdev.o: getdev.c ../hdrs/devmgmt.h ../hdrs/devtab.h
getdgrp.o: getdgrp.c ../hdrs/devmgmt.h ../hdrs/devtab.h
getinput.o: getinput.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
getvol.o: getvol.c ../hdrs/devmgmt.h ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
listdev.o: listdev.c ../hdrs/devmgmt.h ../hdrs/devtab.h
listdgrp.o: listdgrp.c ../hdrs/devmgmt.h ../hdrs/devtab.h
pkginfo.o: pkginfo.c ../hdrs/pkginfo.h ../hdrs/pkgstrct.h \
  ../hdrs/pkglocs.h ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/valtools.h ../hdrs/install.h
pkgnmchk.o: pkgnmchk.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
pkgparam.o: pkgparam.c ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/pkglocs.h ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/valtools.h ../hdrs/install.h
putdev.o: putdev.c ../hdrs/devmgmt.h ../hdrs/devtab.h
putdgrp.o: putdgrp.c ../hdrs/devmgmt.h ../hdrs/devtab.h
puterror.o: puterror.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
puthelp.o: puthelp.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
putprmpt.o: putprmpt.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
puttext.o: puttext.c ../hdrs/libadm.h ../hdrs/sys/vtoc.h \
  ../hdrs/sys/dklabel.h ../hdrs/pkgstrct.h ../hdrs/pkginfo.h \
  ../hdrs/valtools.h ../hdrs/install.h
rdwr_vtoc.o: rdwr_vtoc.c ../hdrs/sys/vtoc.h ../hdrs/sys/dklabel.h
regexp.o: regexp.c regexp.h
space.o: space.c

# --- Amix compat shims (built only when COMPATOBJ is set, see mk.config.amix)
# AMIX PORT: snprintf.o uses $(MERGPATH_OPT) because its convert()
# "value % base" was one of the eight files -O0-forced against the
# suspected modulo miscompile.  Root-caused to the toolchain tdivs/tdivu
# fixup (gcc-cross-amix 984192a; AMIX-PORT.md item 0) - MERGPATH_OPT is
# now $(CFLAGS), so snprintf builds at -O too (where "value % base" is in
# fact a __umoddi3 64-bit libcall, immune to the defect).
# amixcompat.o/fnmatch.o always used $(CFLAGS).
snprintf.o: ../compat/snprintf.c ../compat/amixcompat.h
	$(CC) -c $(MERGPATH_OPT) $(CPPFLAGS) ../compat/snprintf.c -o snprintf.o
amixcompat.o: ../compat/amixcompat.c ../compat/amixcompat.h \
  ../compat/wchar.h ../compat/wctype.h
	$(CC) -c $(CFLAGS) $(CPPFLAGS) ../compat/amixcompat.c -o amixcompat.o
fnmatch.o: ../compat/fnmatch.c ../compat/fnmatch.h ../compat/charclass.h
	$(CC) -c $(CFLAGS) $(CPPFLAGS) ../compat/fnmatch.c -o fnmatch.o

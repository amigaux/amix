/*
 * harness.c — minimal driver around Heirloom pkgtools srchcfile()
 *
 * Modes:
 *   scan <contents>            — emulate pkgrm delmap.c / pkginfo rdcontents():
 *                                srchcfile(ept, "*", vfp, NULL) loop; abort at first n<0
 *                                (like the real tools) but ALSO try to resume to show
 *                                whether the stream is positioned past the bad line.
 *   merge <contents> <path>    — emulate pkgadd pkgdbmerg: search for a specific path
 *                                with a tmp output VFP, then drain with path=NULL,
 *                                print the resulting new contents file.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pkglib.h>
#include <pkgstrct.h>

/* ---- stubs for symbols srchcfile.c/vfpops.c pull in ---- */
char *errstr = NULL;
void setErrstr(char *s) { errstr = s; }
char *getErrstr(void) { return errstr; }
/* pkglocale pkg_gt normally does gettext lookup */
char *pkg_gt(const char *s) { return (char *)s; }
void progerr(char *fmt, ...) { (void)fmt; }
void logerr(char *fmt, ...) { (void)fmt; }

static void
print_ept(struct cfent *ept)
{
	struct pinfo *pi;
	printf("  OK path='%s' ftype='%c' class='%s' mode=%lo size=%ld cksum=%ld modtime=%ld npkgs=%d pkgs=",
	    ept->path ? ept->path : "(nil)",
	    ept->ftype,
	    ept->pkg_class,
	    (unsigned long)ept->ainfo.mode,
	    (long)ept->cinfo.size, (long)ept->cinfo.cksum,
	    (long)ept->cinfo.modtime, ept->npkgs);
	for (pi = ept->pinfo; pi != NULL; pi = pi->next)
		printf("[%s]", pi->pkg);
	if (ept->ainfo.local)
		printf(" local='%s'", ept->ainfo.local);
	printf("\n");
}

int
main(int argc, char **argv)
{
	VFP_T *vfp, *tmpvfp = NULL;
	struct cfent ept;
	int n, rec = 0, errs = 0;

	if (argc < 3) {
		fprintf(stderr, "usage: %s scan|merge <contents> [searchpath]\n", argv[0]);
		return 2;
	}

	if (vfpOpen(&vfp, argv[2], "r", VFP_NEEDNOW) != 0) {
		perror("vfpOpen");
		return 2;
	}

	if (strcmp(argv[1], "scan") == 0) {
		/* exactly the pkgrm/pkginfo consumption pattern */
		for (;;) {
			memset(&ept, 0, sizeof (ept));
			n = srchcfile(&ept, "*", vfp, (VFP_T *)NULL);
			if (n == 0) {
				printf("== end of contents file, records=%d errors=%d\n",
				    rec, errs);
				break;
			}
			if (n < 0) {
				char *e = getErrstr();
				errs++;
				printf("  ERROR n=%d pathname=%s problem=%s\n",
				    n,
				    (ept.path && *ept.path) ? ept.path : "Unknown",
				    (e && *e) ? e : "Unknown");
				printf("  [real pkgrm delmap.c would exit(99) HERE; "
				    "real pkginfo rdcontents() would exit(1) HERE]\n");
				printf("  ...harness continues to test resumability:\n");
				continue;
			}
			rec++;
			print_ept(&ept);
		}
		return errs ? 1 : 0;
	}

	if (strcmp(argv[1], "merge") == 0) {
		char *search = argv[3];
		if (vfpOpen(&tmpvfp, "newcontents.out", "w", VFP_NONE) != 0) {
			perror("vfpOpen tmp");
			return 2;
		}
		/* size the output buffer like ocfile does */
		if (vfpSetSize(tmpvfp, vfpGetBytesRemaining(vfp) + 100000) != 0) {
			perror("vfpSetSize");
			return 2;
		}
		memset(&ept, 0, sizeof (ept));
		n = srchcfile(&ept, search, vfp, tmpvfp);
		printf("srchcfile(\"%s\") = %d", search, n);
		if (n < 0) {
			char *e = getErrstr();
			printf("  problem=%s", (e && *e) ? e : "Unknown");
		}
		printf("\n");
		if (n == 1)
			print_ept(&ept);
		if (n == 2) {
			/* insertion point: pkgdbmerg would putcvfpfile() the new
			   entry here; we just note it */
			printf("  [insertion point found before '%s']\n",
			    ept.path ? ept.path : "(nil)");
		}
		/* drain the rest, as pkgdbmerg does at end of extlist */
		memset(&ept, 0, sizeof (ept));
		n = srchcfile(&ept, NULL, vfp, tmpvfp);
		printf("drain srchcfile(NULL) = %d\n", n);
		if (vfpClose(&tmpvfp) != 0)
			perror("vfpClose tmp");
		printf("---- resulting new contents file ----\n");
		{
			FILE *f = fopen("newcontents.out", "r");
			int c;
			while ((c = getc(f)) != EOF)
				putchar(c);
			fclose(f);
		}
		printf("---- end ----\n");
		return 0;
	}

	fprintf(stderr, "unknown mode\n");
	return 2;
}

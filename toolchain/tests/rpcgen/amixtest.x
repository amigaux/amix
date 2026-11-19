/*
 * amixtest.x: the protocol toolchain/test-rpcgen runs rpcgen on.  Its
 * generated client, server and XDR files must compile with gcc14 against
 * the AMIX sysroot and link against AMIX's libnsl.
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
const NAMELEN = 32;

enum kind { K_NONE = 0, K_NUM = 1, K_TEXT = 2 };

typedef unsigned int counter;

/* six ints in a row: rpcgen writes its inline XDR_INLINE code for them */
struct point { int x; int y; int z; int w; int u; int v; };

struct item {
	string name<NAMELEN>;
	counter count;
	bool on;
	short small;
	unsigned char flags;
	double weight;
	opaque tag[4];
	int fixed[8];
	int vals<>;
	point where;
	item *next;
};

union result switch (kind k) {
case K_NUM:
	int num;
case K_TEXT:
	string text<>;
default:
	void;
};

program AMIXTEST_PROG {
	version AMIXTEST_VERS {
		result LOOKUP(item) = 1;
		string ECHO(string) = 2;
		void PING(void) = 3;
	} = 1;
} = 0x20000777;

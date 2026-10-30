#!/usr/bin/env python3
# Faithful reimplementation of amiga/boot/rel.c ET_REL path (big-endian m68k ELF).
# Reproduces findsections/bindsections/allocbss/specialsyms/relocsections/symvaddr
# and reports exactly which COMPLAIN (-> D245 Alert) would fire, if any.
#
# SCOPE -- READ THIS BEFORE TRUSTING A GREEN VERDICT.
# This is a kernel-RECORD oracle, not a boot oracle.  It answers exactly one question:
# "are THIS kernel's relocation records relocatable under rel.c's source semantics?"
# It does NOT and cannot answer "will this disk boot".  The second-stage loader actually
# installed at /stand/boot2.boot is a free variable entirely outside its scope: a FOREIGN
# name-based loader (e.g. the Amix 2.1 install-media boot2, sha256 5ab360b1...) fires the
# D245/RELA Guru on a perfectly valid flags-based ET_REL kernel that this tool greens --
# correctly.  (Such a boot failure was once blamed on this tool "false-greening" a
# host-cross kernel; a single-variable splice showed the real loader's rel.c relocates
# cross and on-box kernels alike, and the foreign loader was the cause.)  The loader-level
# gate is tools/bootchain-verify.py -- run BOTH; they answer different questions, and
# neither substitutes for the other.
#
# NOR is a green verdict a completeness claim about D245 corruption: over 21 corrupt
# kernels captured from damaged links this oracle caught 15 and MISSED 6.  Only a
# byte-diff against a known-good link caught all 21.
#
# FAIL-CLOSED CONTRACT.  A D245-damaged kernel is frequently damaged in its
# *section header table* -- the table is the last 400 bytes of the file and gets overwritten
# with foreign data (in 4 of the 5 cases measured, with ASCII compiler diagnostics).  Such a
# file has no locatable SHT_SYMTAB, so there is nothing to analyse.  This tool used to die
# with an uncaught `TypeError: 'NoneType' object is not subscriptable` on exactly that input
# -- a traceback is NOT a verdict, and anything gating on it would have to guess.  So:
#
#   exit 0  -- analysed, zero complaints                       (CLEAN)
#   exit 1  -- analysed, one or more complaints                (would fire D245)
#   exit 2  -- STRUCTURALLY UNANALYZABLE -> treat as CORRUPT   (one-line diagnostic, no traceback)
#   exit 3  -- usage error
#
# Exit 2 is a *verdict*, not an error: a kernel whose ELF structure cannot be walked is not
# a kernel that boots.  Callers must treat 1 and 2 alike (both = do not ship this link).
# With several files the worst status wins.
#
# `relsim.py --selftest` builds synthetic ELFs carrying each damage shape and asserts the
# exit codes above; given captured kernels (--fixtures DIR, default the gitignored
# work/d245 beside tools/) it additionally replays every one and requires that none of
# them tracebacks.
import sys, struct, os

SHT_PROGBITS=1; SHT_SYMTAB=2; SHT_NOBITS=8; SHT_RELA=4
SHF_WRITE=1; SHF_ALLOC=2; SHF_EXECINSTR=4
SHN_UNDEF=0; SHN_ABS=0xfff1; SHN_COMMON=0xfff2
R_68K_32=1; R_68K_PC32=4; R_68K_PC16=5; R_68K_PC8=6

# --------------------------------------------------------------------------------------
# WHICH LOADER'S rel.c ARE WE SIMULATING?  (--loader, default `stock`)
#
# The relocation types a kernel may use are a property of the LOADER on the target disk,
# not of the kernel -- so the answer this oracle gives depends on which boot2 will read it.
# The default stays STOCK, i.e. the metal-proven flags-based f287ff3a loader whose rel.c
# handles R_68K_32 and nothing else.  Anything else it COMPLAINs about, and that verdict
# must not soften just because a second loader now exists: a kernel with PC-relative
# relocations on a stock-boot2 disk still Alerts 'RELA' at boot.  Opt in explicitly with
#   --loader boot2-040
# and you are asserting that the disk carries the boot2-040 loader (src/boot2-patches/),
# whose rel.c adds R_68K_PC32/PC16/PC8 with the S + A - P rule and range checks.
# --------------------------------------------------------------------------------------
LOADER_STOCK='stock'; LOADER_040='boot2-040'
LOADERS=(LOADER_STOCK, LOADER_040)
_PCREL={R_68K_PC32:32, R_68K_PC16:16, R_68K_PC8:8}
_PCREL_LIMIT={R_68K_PC16:(-32768,32767), R_68K_PC8:(-128,127)}

EXIT_CLEAN=0; EXIT_COMPLAINTS=1; EXIT_UNANALYZABLE=2; EXIT_USAGE=3

SHDR_SIZE=40      # minimum ELF32 section header we index into
SYMENT_MIN=16     # minimum ELF32 symbol entry we index into
RELAENT_MIN=12    # minimum ELF32 RELA entry we index into


class Unanalyzable(Exception):
    """The file's ELF structure cannot be walked -- treat the kernel as CORRUPT."""


def u32(b,o): return struct.unpack_from('>I',b,o)[0]
def u16(b,o): return struct.unpack_from('>H',b,o)[0]


def _type_handled(reltype, loader):
    """True if <loader>'s rel.c has a `case` for this relocation type (no COMPLAIN)."""
    if reltype == R_68K_32:
        return True
    return loader == LOADER_040 and reltype in _PCREL


def _region_ok(off, size, flen):
    """True if [off, off+size) lies inside a file of `flen` bytes (overflow-safe)."""
    return off <= flen and size <= flen and off + size <= flen


def analyze(path, quiet=False, loader=LOADER_STOCK):
    """Return the list of COMPLAINTs rel.c would raise, or raise Unanalyzable.

    Every structural precondition rel.c itself relies on is checked BEFORE it is used,
    so a damaged file yields a diagnosis instead of a traceback.
    """
    try:
        with open(path,'rb') as fh:
            d = fh.read()
    except OSError as e:
        raise Unanalyzable("cannot read: %s" % e.strerror)
    flen = len(d)
    if flen < 52:
        raise Unanalyzable("%d bytes -- shorter than an ELF32 header" % flen)
    if d[:4] != b'\x7fELF':
        raise Unanalyzable("not an ELF file (magic %s)" % d[:4].hex())
    try:
        return _analyze(d, flen, path, quiet, loader)
    except Unanalyzable:
        raise
    except (struct.error, IndexError, ValueError, ZeroDivisionError, MemoryError) as e:
        # Belt-and-braces: no malformed-input path may escape as a traceback.
        raise Unanalyzable("ELF walk failed (%s: %s)" % (type(e).__name__, e))


def _analyze(d, flen, path, quiet, loader=LOADER_STOCK):
    e_type=u16(d,16); e_shoff=u32(d,32); e_shentsize=u16(d,46)
    e_shnum=u16(d,48); e_shstrndx=u16(d,50)
    # ---- section header table must exist and lie inside the file ----
    if e_shnum == 0:
        raise Unanalyzable("e_shnum=0 -- no section header table")
    if e_shentsize < SHDR_SIZE:
        raise Unanalyzable("e_shentsize=%d -- too small for an ELF32 section header" % e_shentsize)
    if e_shoff == 0:
        raise Unanalyzable("e_shoff=0 -- no section header table")
    if not _region_ok(e_shoff, e_shnum*e_shentsize, flen):
        raise Unanalyzable("section header table truncated (e_shoff=%d e_shnum=%d "
                           "e_shentsize=%d > %d bytes)" % (e_shoff,e_shnum,e_shentsize,flen))
    S=[]
    for i in range(e_shnum):
        o=e_shoff+i*e_shentsize
        S.append(dict(name=u32(d,o),type=u32(d,o+4),flags=u32(d,o+8),
                      addr=u32(d,o+12),offset=u32(d,o+16),size=u32(d,o+20),
                      link=u32(d,o+24),info=u32(d,o+28),entsize=u32(d,o+36)))
    if e_shstrndx >= e_shnum:
        raise Unanalyzable("e_shstrndx=%d out of range (e_shnum=%d)" % (e_shstrndx,e_shnum))
    sh=S[e_shstrndx]
    if not _region_ok(sh['offset'], sh['size'], flen):
        raise Unanalyzable("section-name string table outside the file "
                           "(offset=%d size=%d > %d bytes)" % (sh['offset'],sh['size'],flen))
    shstr=d[sh['offset']:sh['offset']+sh['size']]
    def snm(i):
        if not (0 <= i < e_shnum): return '?'
        n=S[i]['name']
        if n >= len(shstr): return '?'
        end=shstr.find(b'\0',n)
        return shstr[n:end if end>=0 else len(shstr)].decode('latin1')
    # ---- findsections (by FLAGS, exactly like rel.c) ----
    thdr=rhdr=dhdr=bhdr=symhdr=None
    symhdr_idx=None
    for i,s in enumerate(S):
        if s['type']==SHT_PROGBITS:
            if s['size']>0 and (s['flags']&SHF_ALLOC):
                if s['flags']&SHF_EXECINSTR: thdr=s
                elif s['flags']&SHF_WRITE:   dhdr=s
                else:                        rhdr=s
        elif s['type']==SHT_NOBITS:
            if (s['flags']&SHF_WRITE) and s['size']>0: bhdr=s
        elif s['type']==SHT_SYMTAB:
            symhdr=s; symhdr_idx=i
    # bound = sh_addr set by bindsections; mark which section dicts get bound
    bound=set()
    vaddr=0x07800000; end=vaddr
    for s in (thdr,rhdr,dhdr,bhdr):
        if s is not None:
            s['addr']=end; end+=s['size']; bound.add(id(s))
    boundidx={i for i,s in enumerate(S) if id(s) in bound}
    bhdr_idx = next((i for i,s in enumerate(S) if s is bhdr), None) if bhdr is not None else None
    # ---- the symtab rel.c needs must be locatable and intact ----
    # This is the D245 hot spot: the section header table is the tail of the file and gets
    # overwritten wholesale, taking SHT_SYMTAB with it.  No symtab -> no analysis possible.
    if symhdr is None:
        raise Unanalyzable("no SHT_SYMTAB section header among %d sections "
                           "(section header table damaged?)" % e_shnum)
    if symhdr['entsize'] < SYMENT_MIN:
        raise Unanalyzable(".symtab sh_entsize=%d -- too small for an ELF32 symbol"
                           % symhdr['entsize'])
    if symhdr['size'] == 0:
        raise Unanalyzable(".symtab is empty (sh_size=0)")
    if not _region_ok(symhdr['offset'], symhdr['size'], flen):
        raise Unanalyzable(".symtab outside the file (offset=%d size=%d > %d bytes)"
                           % (symhdr['offset'],symhdr['size'],flen))
    if symhdr['link'] >= e_shnum:
        raise Unanalyzable(".symtab sh_link=%d out of range (e_shnum=%d)"
                           % (symhdr['link'],e_shnum))
    strsec=S[symhdr['link']]
    if not _region_ok(strsec['offset'], strsec['size'], flen):
        raise Unanalyzable(".strtab outside the file (offset=%d size=%d > %d bytes)"
                           % (strsec['offset'],strsec['size'],flen))
    syo=symhdr['offset']; syent=symhdr['entsize']; syn=symhdr['size']//syent
    if syn == 0:
        raise Unanalyzable(".symtab holds no symbols (sh_size=%d sh_entsize=%d)"
                           % (symhdr['size'],syent))
    shndx_override={}
    def sym(idx):
        o=syo+idx*syent
        sh=shndx_override.get(idx, u16(d,o+14))
        return dict(name=u32(d,o),value=u32(d,o+4),size=u32(d,o+8),
                    info=d[o+12],shndx=sh)
    strtab=d[strsec['offset']:strsec['offset']+strsec['size']]
    def symname(idx):
        n=sym(idx)['name']
        if n >= len(strtab): return ''
        end=strtab.find(b'\0',n)
        return strtab[n:end if end>=0 else len(strtab)].decode('latin1')
    # ---- allocbss(): SHN_COMMON -> bss (bound) ----
    for idx in range(syn):
        if sym(idx)['shndx']==SHN_COMMON and bhdr_idx is not None:
            shndx_override[idx]=bhdr_idx
    # ---- specialsyms(): etext/edata/end -> SHN_ABS (applied AFTER allocbss, so it wins) ----
    for idx in range(syn):
        nm=symname(idx)
        if nm in ('etext','edata','end'):
            shndx_override[idx]=SHN_ABS
    # ---- enumerate relocs, apply symvaddr() test ----
    complaints=[]
    typehist={}
    nrel_total=0
    for si,s in enumerate(S):
        if s['type']!=SHT_RELA: continue
        if s['entsize'] < RELAENT_MIN:
            raise Unanalyzable("%s sh_entsize=%d -- too small for an ELF32 RELA entry"
                               % (snm(si), s['entsize']))
        if not _region_ok(s['offset'], s['size'], flen):
            raise Unanalyzable("%s outside the file (offset=%d size=%d > %d bytes)"
                               % (snm(si), s['offset'], s['size'], flen))
        nrel=s['size']//s['entsize']
        base=s['offset']
        nrel_total+=nrel
        for k in range(nrel):
            o=base+k*s['entsize']
            r_info=u32(d,o+4)
            reltype=r_info&0xff; symidx=r_info>>8
            typehist[reltype]=typehist.get(reltype,0)+1
            # A relocation naming a symbol past the end of .symtab is a record-level
            # defect, not a structural one -- rel.c would index straight off the table.
            if symidx >= syn:
                complaints.append(('sym_out_of_range',snm(si),symidx,'?',-1,'',reltype))
                if not _type_handled(reltype, loader):
                    complaints.append(('bad_reltype',snm(si),symidx,'?',-1,'',reltype))
                continue
            sy=sym(symidx); shndx=sy['shndx']
            # symvaddr() logic:
            if 0<shndx<e_shnum:
                if shndx not in boundidx:
                    complaints.append(('unbound_section',snm(si),symidx,symname(symidx),shndx,snm(shndx),reltype))
            elif shndx==SHN_ABS:
                pass
            elif shndx==SHN_COMMON:
                # allocbss() reassigns COMMON -> bhdr (bound) BEFORE relocsections, so OK if bhdr exists
                if bhdr is None:
                    complaints.append(('common_no_bss',snm(si),symidx,symname(symidx),shndx,'COMMON',reltype))
            else:  # SHN_UNDEF (0) or out of range
                complaints.append(('undef_or_oor',snm(si),symidx,symname(symidx),shndx,'UND' if shndx==0 else '?',reltype))
            if not _type_handled(reltype, loader):
                complaints.append(('bad_reltype',snm(si),symidx,symname(symidx),shndx,'',reltype))
            elif reltype in _PCREL_LIMIT:
                # boot2-040's rel.c computes value = S + A - P with
                #   P = relsechdr->sh_addr + r_offset
                # and REFUSES (COMPLAIN) rather than truncate when the displacement will
                # not fit.  Reproduce that here: a silent truncation is a wild branch.
                tgt=s['info']
                raw_shndx=u16(d,syo+symidx*syent+14)
                if not (0 <= tgt < e_shnum) or tgt not in boundidx:
                    complaints.append(('pcrel_unbound_target',snm(si),symidx,symname(symidx),
                                       shndx,snm(tgt) if 0<=tgt<e_shnum else '?',reltype))
                elif raw_shndx==SHN_ABS or (0<raw_shndx<e_shnum and raw_shndx in boundidx):
                    sv=sym(symidx)
                    Sval = sv['value'] if raw_shndx==SHN_ABS else S[raw_shndx]['addr']+sv['value']
                    r_off=u32(d,o); r_add=struct.unpack_from('>i',d,o+8)[0]
                    v=Sval + r_add - (S[tgt]['addr'] + r_off)
                    v=((v + 0x80000000) & 0xffffffff) - 0x80000000     # wrap to signed 32
                    lo,hi=_PCREL_LIMIT[reltype]
                    if not (lo <= v <= hi):
                        complaints.append(('pcrel_overflow',snm(si),symidx,symname(symidx),
                                           shndx,'disp=%d'%v,reltype))
    if not quiet:
        print(f"== {path} ==  e_type={e_type:#x} shnum={e_shnum}  loader={loader}")
        print(f"   bound sections (idx): {sorted(boundidx)}  text={snm(S.index(thdr)) if thdr else None}")
        print(f"   reloc type histogram: {typehist}")
        print(f"   COMPLAINTS (would fire D245): {len(complaints)}")
        seen=set()
        for c in complaints:
            key=(c[0],c[3],c[4])
            if key in seen: continue
            seen.add(key)
            print(f"     [{c[0]}] reloc-sect={c[1]} sym#{c[2]} '{c[3]}' shndx={c[4]}({c[5]}) type={c[6]}")
            if len(seen)>=40: print("     ... (truncated)"); break
    return complaints


def verdict(path, quiet=False, loader=LOADER_STOCK):
    """Analyse `path` and return one of the EXIT_* codes.  Never raises on bad input."""
    try:
        complaints = analyze(path, quiet=quiet, loader=loader)
    except Unanalyzable as e:
        line = "relsim: UNANALYZABLE: %s: %s -- treat as CORRUPT" % (path, e)
        if not quiet:
            print(f"== {path} ==")
            print("   UNANALYZABLE (structurally damaged -- treat as CORRUPT): %s" % e)
        print(line, file=sys.stderr)
        return EXIT_UNANALYZABLE
    return EXIT_COMPLAINTS if complaints else EXIT_CLEAN


# --------------------------------------------------------------------------------------
# selftest
# --------------------------------------------------------------------------------------

def _build_elf(damage=None):
    """A minimal well-formed big-endian m68k ET_REL kernel-shaped ELF, optionally damaged.

    Section layout mirrors the real relocunix: NULL, .text, .data, .bss, .symtab, .strtab,
    .shstrtab, .rela.text.
    """
    shnames = b'\0.text\0.data\0.bss\0.symtab\0.strtab\0.shstrtab\0.rela.text\0'
    def shname(n): return shnames.index(b'\0'+n+b'\0')+1
    symnames = [b'', b'_foo', b'etext', b'edata', b'end', b'_bar', b'_common', b'_und']
    strtab = b'\0'
    stroff = {}
    for n in symnames[1:]:
        stroff[n] = len(strtab); strtab += n + b'\0'
    stroff[b''] = 0
    # symbols: (name, value, size, info, shndx)
    syms = [(b'',0,0,0,SHN_UNDEF),
            (b'_foo',0,4,0x12,1),        # .text
            (b'etext',0,0,0x10,1),
            (b'edata',0,0,0x10,2),
            (b'end',0,0,0x10,3),
            (b'_bar',0,4,0x11,2),        # .data
            (b'_common',0,4,0x11,SHN_COMMON),
            (b'_und',0,0,0x10,SHN_UNDEF)]
    symtab = b''.join(struct.pack('>IIIBBH', stroff[n], v, sz, info, 0, sx)
                      for (n,v,sz,info,sx) in syms)
    # (r_offset, symidx, type, r_addend)
    relocs = [(0x00,1,R_68K_32,0), (0x08,2,R_68K_32,0),
              (0x10,5,R_68K_32,0), (0x18,6,R_68K_32,0)]
    if damage == 'reloc_undef':   relocs.append((0x20,7,R_68K_32,0))   # names _und (SHN_UNDEF)
    if damage == 'reloc_badtype': relocs.append((0x20,1,7,0))          # not R_68K_32
    if damage == 'reloc_symoor':  relocs.append((0x20,999,R_68K_32,0)) # past end of .symtab
    if damage == 'reloc_unbound': relocs.append((0x20,8,R_68K_32,0))   # sym in an unbound section
    if damage == 'reloc_unbound':
        syms.append((b'_str',0,0,0x10,5))   # .symtab's own index -- never bound
        symtab += struct.pack('>IIIBBH', 0,0,0,0x10,0,5)
    # PC-relative shapes: a COMPLAINT under the stock loader (no case for the type) and,
    # under boot2-040, clean iff the displacement S + A - P fits the field.
    if damage == 'reloc_pcrel':
        relocs.append((0x20,1,R_68K_PC16,0))        # disp = 0 - 0x20 = -32     -> fits
        relocs.append((0x28,1,R_68K_PC8,0))         # disp = 0 - 0x28 = -40     -> fits
    if damage == 'reloc_pcrel_oor':
        relocs.append((0x20,1,R_68K_PC16,100000))   # disp = 100000-0x20 = 99968 -> overflows 16
        relocs.append((0x28,1,R_68K_PC8,1000))      # disp = 1000-0x28   = 960   -> overflows 8
    rela = b''.join(struct.pack('>IIi', off, (si<<8)|ty, add) for (off,si,ty,add) in relocs)

    text = b'\x4e\x71'*32          # 64 B of NOP
    data = b'\x11'*16
    body = [(b'.text', text), (b'.data', data), (b'.symtab', symtab),
            (b'.strtab', strtab), (b'.shstrtab', shnames), (b'.rela.text', rela)]
    off = 52
    offs = {}
    blob = b''
    for name, payload in body:
        offs[name] = off; blob += payload; off += len(payload)
    # (name, type, flags, offset, size, link, info, entsize)
    secs = [(0, 0, 0, 0, 0, 0, 0, 0),
            (shname(b'.text'),      SHT_PROGBITS, SHF_ALLOC|SHF_EXECINSTR, offs[b'.text'],   len(text),   0, 0, 0),
            (shname(b'.data'),      SHT_PROGBITS, SHF_ALLOC|SHF_WRITE,     offs[b'.data'],   len(data),   0, 0, 0),
            (shname(b'.bss'),       SHT_NOBITS,   SHF_ALLOC|SHF_WRITE,     offs[b'.data']+len(data), 32,  0, 0, 0),
            (shname(b'.symtab'),    SHT_SYMTAB,   0,                       offs[b'.symtab'], len(symtab), 5, 1, 16),
            (shname(b'.strtab'),    3,            0,                       offs[b'.strtab'], len(strtab), 0, 0, 0),
            (shname(b'.shstrtab'),  3,            0,                       offs[b'.shstrtab'], len(shnames), 0, 0, 0),
            (shname(b'.rela.text'), SHT_RELA,     0,                       offs[b'.rela.text'], len(rela), 4, 1, 12)]
    shoff = 52 + len(blob)
    ehdr = bytearray(52)
    ehdr[0:4] = b'\x7fELF'
    ehdr[4] = 1; ehdr[5] = 2; ehdr[6] = 1              # ELF32, big-endian, v1
    struct.pack_into('>HHI', ehdr, 16, 1, 4, 1)        # e_type=ET_REL, e_machine=EM_68K, e_version
    struct.pack_into('>III', ehdr, 24, 0, 0, shoff)    # e_entry, e_phoff, e_shoff
    struct.pack_into('>IHHHHHH', ehdr, 36, 0, 52, 0, 0, 40, len(secs), 6)
    sht = b''.join(struct.pack('>IIIIIIIIII', n,t,f,0,o,sz,lk,inf,4,es)
                   for (n,t,f,o,sz,lk,inf,es) in secs)
    d = bytearray(bytes(ehdr) + blob + sht)

    # ---- structural damage shapes, each taken from a real captured corruption ----
    if damage == 'symtab_type':
        # SHT_SYMTAB's sh_type byte flipped -> findsections finds no symtab at all.
        # (control-8mb-b2b r006: every sh_type in the table came back garbage.)
        struct.pack_into('>I', d, shoff + 4*40 + 4, 0x30)
    elif damage == 'symtab_entsize':
        struct.pack_into('>I', d, shoff + 4*40 + 36, 0)
    elif damage == 'symtab_offset':
        struct.pack_into('>I', d, shoff + 4*40 + 16, 0x7fff0000)
    elif damage == 'symtab_link':
        struct.pack_into('>I', d, shoff + 4*40 + 24, 999)
    elif damage == 'sht_overwritten':
        # The observed dominant shape: the whole 400-byte section header table (the tail
        # of the file) overwritten with foreign ASCII -- in the real artifacts, `as:`
        # assembler diagnostics.  4 of the 5 crashers looked exactly like this.
        filler = b'as: "/tmp/cc2932.s", line 90: error - statement syntax\n'
        d[shoff:] = (filler * 40)[:len(d)-shoff]
    elif damage == 'shoff_past_eof':
        struct.pack_into('>I', d, 32, len(d) + 4096)
    elif damage == 'shnum_zero':
        struct.pack_into('>H', d, 48, 0)
    elif damage == 'rela_entsize':
        struct.pack_into('>I', d, shoff + 7*40 + 36, 0)
    elif damage == 'rela_offset':
        struct.pack_into('>I', d, shoff + 7*40 + 16, 0x7fff0000)
    elif damage == 'shstrndx':
        struct.pack_into('>H', d, 50, 99)
    elif damage == 'truncated':
        d = d[:len(d)//3]
    elif damage == 'not_elf':
        d[0:4] = b'\x00\x00\x00\x00'
    elif damage == 'stub':
        d = d[:8]
    return bytes(d)


# (damage, expected exit, what it stands for)
_CASES = [
    (None,               EXIT_CLEAN,        "well-formed kernel-shaped ET_REL"),
    ('reloc_undef',      EXIT_COMPLAINTS,   "reloc names an SHN_UNDEF symbol"),
    ('reloc_badtype',    EXIT_COMPLAINTS,   "reloc type is not R_68K_32"),
    ('reloc_symoor',     EXIT_COMPLAINTS,   "reloc names a symbol past the end of .symtab"),
    ('reloc_unbound',    EXIT_COMPLAINTS,   "reloc names a symbol in an unbound section"),
    ('reloc_pcrel',      EXIT_COMPLAINTS,   "PC-relative relocs -- stock rel.c has no case for them"),
    ('reloc_pcrel_oor',  EXIT_COMPLAINTS,   "PC-relative relocs that overflow their field"),
    ('symtab_type',      EXIT_UNANALYZABLE, "SHT_SYMTAB sh_type damaged (the historical TypeError)"),
    ('symtab_entsize',   EXIT_UNANALYZABLE, ".symtab sh_entsize = 0"),
    ('symtab_offset',    EXIT_UNANALYZABLE, ".symtab sh_offset past EOF"),
    ('symtab_link',      EXIT_UNANALYZABLE, ".symtab sh_link out of range"),
    ('sht_overwritten',  EXIT_UNANALYZABLE, "whole section header table overwritten (the real shape)"),
    ('shoff_past_eof',   EXIT_UNANALYZABLE, "e_shoff past EOF"),
    ('shnum_zero',       EXIT_UNANALYZABLE, "e_shnum = 0"),
    ('rela_entsize',     EXIT_UNANALYZABLE, ".rela sh_entsize = 0"),
    ('rela_offset',      EXIT_UNANALYZABLE, ".rela sh_offset past EOF"),
    ('shstrndx',         EXIT_UNANALYZABLE, "e_shstrndx out of range"),
    ('truncated',        EXIT_UNANALYZABLE, "file truncated mid-body"),
    ('not_elf',          EXIT_UNANALYZABLE, "ELF magic destroyed"),
    ('stub',             EXIT_UNANALYZABLE, "8-byte stub"),
]

_EXITNAME = {EXIT_CLEAN:"CLEAN(0)", EXIT_COMPLAINTS:"COMPLAINTS(1)",
             EXIT_UNANALYZABLE:"UNANALYZABLE(2)", EXIT_USAGE:"USAGE(3)"}


def selftest(fixtures=None):
    """Assert the exit-code contract on synthetic damage, then replay real artifacts."""
    import subprocess, tempfile, glob
    me = os.path.abspath(__file__)
    fails = 0
    print("relsim selftest -- synthetic damage shapes")
    with tempfile.TemporaryDirectory(prefix="relsim-selftest-") as td:
        for damage, want, what in _CASES:
            p = os.path.join(td, (damage or "clean") + ".unix")
            with open(p, 'wb') as fh:
                fh.write(_build_elf(damage))
            r = subprocess.run([sys.executable, me, p], capture_output=True)
            got = r.returncode
            err = r.stderr.decode('latin1', 'replace')
            ok = (got == want) and ("Traceback" not in err)
            if not ok: fails += 1
            note = ""
            if "Traceback" in err:
                note = "  <-- TRACEBACK"
            elif want == EXIT_UNANALYZABLE:
                note = "  " + err.strip().split("\n")[-1][:96]
            print("  %-4s %-18s %-14s %s%s" % ("ok" if ok else "FAIL", damage or "(clean)",
                                               _EXITNAME.get(got, got), what, note))
    # ---- the --loader axis ------------------------------------------------------------
    # Two claims that only mean something together: opting in to boot2-040 must ACCEPT
    # PC-relative relocations that fit, and must still REFUSE the ones that do not.  The
    # first case above already showed the same fixture COMPLAINing under the default
    # loader, so neither assertion can pass vacuously.
    print("\nloader axis -- --loader boot2-040")
    with tempfile.TemporaryDirectory(prefix="relsim-loader-") as td:
        for damage, want, needle, what in (
                ('reloc_pcrel',     EXIT_CLEAN,       None,
                 "PC16/PC8 in range -> accepted"),
                ('reloc_pcrel_oor', EXIT_COMPLAINTS,  "pcrel_overflow",
                 "PC16/PC8 out of range -> refused, never truncated")):
            p = os.path.join(td, damage + ".unix")
            with open(p, 'wb') as fh:
                fh.write(_build_elf(damage))
            r = subprocess.run([sys.executable, me, '--loader', 'boot2-040', p],
                               capture_output=True)
            out = r.stdout.decode('latin1', 'replace')
            err = r.stderr.decode('latin1', 'replace')
            ok = (r.returncode == want) and ("Traceback" not in err) \
                 and (needle is None or needle in out)
            if not ok: fails += 1
            print("  %-4s %-18s %-14s %s" % ("ok" if ok else "FAIL", damage,
                                             _EXITNAME.get(r.returncode, r.returncode), what))
        # and the flag itself must fail closed on nonsense
        for argv, what in ((['--loader'], "--loader with no value"),
                           (['--loader', 'nope', '/dev/null'], "--loader with an unknown loader"),
                           (['--loader', 'boot2-040'], "--loader with no kernel")):
            r = subprocess.run([sys.executable, me] + argv, capture_output=True)
            ok = r.returncode == EXIT_USAGE
            if not ok: fails += 1
            print("  %-4s %-18s %-14s %s" % ("ok" if ok else "FAIL", "argguard",
                                             _EXITNAME.get(r.returncode, r.returncode), what))

    # Real captured corruptions, when a fixtures directory holds any (--fixtures DIR, or the
    # gitignored work/d245 beside tools/).  Skipped otherwise.
    if fixtures is None:
        fixtures = os.path.join(os.path.dirname(os.path.dirname(me)), "work", "d245")
    real = sorted(glob.glob(os.path.join(fixtures, "*", "artifacts", "*.unix"))) or \
           sorted(glob.glob(os.path.join(fixtures, "*.unix")))
    if not real:
        print("\nreal-artifact regression: SKIPPED (no captured kernels under %s)" % fixtures)
    else:
        print("\nreal-artifact regression -- %d captured kernels under %s" % (len(real), fixtures))
        hist = {}
        for p in real:
            r = subprocess.run([sys.executable, me, p], capture_output=True)
            hist[r.returncode] = hist.get(r.returncode, 0) + 1
            if "Traceback" in r.stderr.decode('latin1', 'replace'):
                print("  FAIL traceback on %s" % p); fails += 1
            if r.returncode not in (EXIT_CLEAN, EXIT_COMPLAINTS, EXIT_UNANALYZABLE):
                print("  FAIL unexpected exit %d on %s" % (r.returncode, p)); fails += 1
            if os.path.basename(p) == "ref.unix" and r.returncode != EXIT_CLEAN:
                print("  FAIL reference link %s did not come back CLEAN (exit %d)"
                      % (p, r.returncode)); fails += 1
        print("  verdicts: " + "  ".join("%s=%d" % (_EXITNAME.get(k,k), v)
                                         for k, v in sorted(hist.items())))
        print("  (no tracebacks, every reference link CLEAN)")
    print("\n%s -- %d failure(s)" % ("SELFTEST PASS" if fails == 0 else "SELFTEST FAIL", fails))
    return 0 if fails == 0 else 1


def main(argv):
    args = argv[1:]
    if not args:
        print(__doc__ or "usage: relsim.py [--selftest [--fixtures DIR]] <kernel-elf>...",
              file=sys.stderr)
        print("usage: relsim.py <kernel-elf>...   |   relsim.py --selftest [--fixtures DIR]",
              file=sys.stderr)
        return EXIT_USAGE
    if args[0] == '--selftest':
        fixtures = None
        rest = args[1:]
        if rest[:1] == ['--fixtures']:
            if len(rest) < 2:
                print("relsim: --fixtures needs a directory", file=sys.stderr)
                return EXIT_USAGE
            fixtures = rest[1]; rest = rest[2:]
        if rest:
            print("relsim: unexpected argument(s) after --selftest: %s" % " ".join(rest),
                  file=sys.stderr)
            return EXIT_USAGE
        return selftest(fixtures)
    loader = LOADER_STOCK
    if args[:1] == ['--loader']:
        if len(args) < 2:
            print("relsim: --loader needs one of: %s" % " ".join(LOADERS), file=sys.stderr)
            return EXIT_USAGE
        loader = args[1]; args = args[2:]
        if loader not in LOADERS:
            print("relsim: unknown loader '%s' (want one of: %s)" % (loader, " ".join(LOADERS)),
                  file=sys.stderr)
            return EXIT_USAGE
        if not args:
            print("relsim: --loader %s given but no kernel to analyse" % loader, file=sys.stderr)
            return EXIT_USAGE
    for a in args:
        if a.startswith('-'):
            print("relsim: unknown option %s" % a, file=sys.stderr)
            return EXIT_USAGE
    worst = EXIT_CLEAN
    for p in args:
        rc = verdict(p, loader=loader)
        print()
        worst = max(worst, rc)
    return worst


if __name__=='__main__':
    sys.exit(main(sys.argv))

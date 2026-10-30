#!/usr/bin/perl
# asmfix.pl -- post-process gcc-2.7.2.3 m68k SVR4 (SGS-syntax) assembly so
# GNU as 2.8.1 assembles it CORRECTLY.  Usage: perl asmfix.pl <file.s>
# (edits in place).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# This is the contents-fsck-local copy of the amix-gcc-wrapper.sh fix_asm
# fixups, plus the .swbeg fix (see below) that the shared wrapper still
# lacks; tools/wrapper-swbeg.patch is the corresponding upstream patch.
#
# Fixup 1: .swbeg  (THE LOAD-BEARING ONE -- found via contents-fsck)
#   gcc emits every switch jump table as
#         mov.w  .LDnn(%pc,%a0.l*2),%d0
#         jmp    6(%pc,%d0.w)
#         .swbeg &<entries>
#   .Lnn: .short .Lcase-.Lnn ...
#   The hard-coded displacement 6 assumes the SGS assembler's ".swbeg"
#   directive occupies 4 bytes (ext word at jmp+2; 2 more bytes of jmp;
#   4 bytes of swbeg => table at ext+6).  GNU as parses .swbeg but emits
#   ZERO bytes, so the computed dispatch target is <case label> + 4:
#   every switch case is entered 4 bytes late, skipping its first
#   instruction(s) and branching on stale condition codes.  On Amix this
#   made contents-fsck's validate_rest() reject nearly every record
#   ("too few fields" regardless of n).  Replacing .swbeg with an
#   explicit 4-byte filler restores the layout gcc assumed.
#
# Fixup 2: .lcomm alignment argument
#   gcc emits ".lcomm name,size,align"; this gas accepts only 2 operands.
#
# Fixup 3: cmp operand order
#   gcc emits "cmp.l <dst>,<src>" (flags = first - second); GNU as
#   implements the Motorola convention "cmp.l <src>,<dst>" (flags =
#   second - first) and REJECTS non-encodable orders (memory/immediate
#   destination).  Swapping the operands preserves gcc's intended
#   semantics in every form (reg,reg / reg,mem / reg,imm / mem,imm /
#   areg forms -- verified by known-answer disassembly, tests/kat-*).

use strict;
use warnings;

my $file = shift or die "usage: asmfix.pl <file.s>\n";

local $/;
open(my $fh, '<', $file) or die "asmfix.pl: $file: $!\n";
my $s = <$fh>;
close($fh);

# --- fixup 1: .swbeg -> 4-byte filler -------------------------------
$s =~ s/^(\s*)\.swbeg\s+&(\d+)\s*$/$1.long $2/mg;

# --- fixup 2: strip .lcomm 3rd (alignment) argument -----------------
$s =~ s/^(\s*\.lcomm\s+[^,\n]+,[^,\n]+),\d+\s*$/$1/mg;

# --- fixup 3: swap cmp.[bwl] operand order --------------------------
sub split_operands {
    my ($ops) = @_;
    my $depth = 0;
    for (my $i = 0; $i < length($ops); $i++) {
        my $ch = substr($ops, $i, 1);
        $depth++ if $ch eq "(";
        $depth-- if $ch eq ")";
        if ($ch eq "," && $depth == 0) {
            return (substr($ops, 0, $i), substr($ops, $i + 1));
        }
    }
    return;
}

$s =~ s{^(\s*cmp\.[bwl]\s+)([^\n]+)$}{
    my ($prefix, $ops) = ($1, $2);
    my ($left, $right) = split_operands($ops);
    defined $right ? "$prefix$right,$left" : "$prefix$ops";
}egm;

open($fh, '>', $file) or die "asmfix.pl: $file: $!\n";
print $fh $s;
close($fh);

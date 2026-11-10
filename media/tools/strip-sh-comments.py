#!/usr/bin/env python3
"""strip-sh-comments.py -- remove FULL-LINE comments and blank lines from a
pre-POSIX SVR4 /bin/sh script, at STAGING time only.

WHY THIS EXISTS (and it is not cosmetics)
=========================================
The 68040 install lane walls at PARSE time. `/bin/sh` reading a large installer
script floods

    NOTICE: User BUS ERROR at 4AFC0003, PC:800023FC FAULT:6 PID:n CMD:sh <script>

and dies with `no space`. Root cause is the 040/060 port's ISSUE-10 (see
../amix-040-060-port/docs/ISSUE10-SETUPSH-WALL-260819.md): a first-touch WRITE
demand-fill on a freshly brk'd anon page returns unresolved, the CPU's valid
pending write-back is dropped, and `sh`'s own catch-and-grow resumes past the
lost store. The trigger is measured to be ARENA GROWTH DISTANCE, not file size
(that doc, section 3): a script truncated to 34 KiB parses clean, 38 KiB and
beyond walls every time; a synthetic 64 KiB script of repeated identical chunks
parses clean because each repeat redefines rather than grows the parse tree.

Our installer scripts are ~2/3 comment by volume. Dropping comments at staging
time is therefore the one lever available that shrinks the parse arena WITHOUT
touching a single line of executable shell. It is a DODGE, not a fix -- the
kernel defect is unchanged and is being worked separately.

THE SOURCE FILES ARE NEVER MODIFIED. src/installer/*.sh keep every comment, so
`git diff` provenance and the selftest audits that read them are untouched. Only
the copy that lands in /install/bin on the medium is stripped.

WHAT IS REMOVED, AND ONLY THIS
==============================
  * a line that is entirely blank/whitespace, and
  * a line that is optional whitespace then `#` (a FULL-LINE comment),
  * ...but ONLY when the shell lexer says that line begins in NORMAL state --
    not inside a quoted string, not inside a command substitution, not on a
    backslash line-continuation.
  * LINE 1 IS ALWAYS KEPT (`#!` interpreter semantics, and stock's first line).
  * A TRAILING comment on a code line is NEVER touched -- removing it would
    require rewriting the line, and rewriting executable lines is out of scope.

THE HAZARD THIS FILE IS BUILT AROUND
====================================
It is NOT here-docs -- the installer scripts contain zero `<<` (the miniroot sh
materialises a here-doc body to /tmp, which is the FLOPPY, at parse time, so this
project banned them long ago). It IS MULTI-LINE QUOTED STRINGS: these scripts
quote the stock 1991 installer's screens verbatim, and those screens contain
blank lines and lines that begin with characters we must not touch. A blank line
inside

        echo "\\nAvailable key mappings are:

 1)     cdn     Canadien Francais
"

is DATA -- the blank line the operator sees on the console. Strip it and the
screen changes. So this tool lexes; it does not grep.

FAIL CLOSED, NEVER GUESS
========================
Two constructs make safe line classification genuinely hard, and both are BANNED
in this codebase already (installer-selftest audit A forbids `$(...)`; the
project forbids here-docs). Rather than implement a half-correct parser for
them, this tool REFUSES a file that contains either:

  * `<<`  -- any here-doc operator
  * `$(`  -- POSIX command substitution

A refusal is a hard error that stops the build. If someone legitimately needs
one of these in an installer script later, the honest move is to extend this
lexer with tests, not to loosen the gate.

VERIFICATION IS PART OF THE TOOL, NOT A SEPARATE STEP
=====================================================
Every strip runs seven gates before the output is accepted (see verify()). The
load-bearing one is G6: the token streams of the original and the stripped file,
produced by Python's `shlex` -- an INDEPENDENT lexer nobody here wrote -- must be
byte-identical. If this tool's own lexer were wrong about where a string starts
and it deleted a line out of the middle of one, the quoted content would change
and shlex would disagree. A bug in our lexer does not hide behind our lexer.

usage:
    strip-sh-comments.py IN OUT        strip IN -> OUT (all gates must pass)
    strip-sh-comments.py --self-test   prove each gate fires; needs no media
"""

import os
import re
import shlex
import subprocess
import sys
import tempfile

PROG = os.path.basename(sys.argv[0])

# A full-line comment: optional whitespace, then '#'. A blank line: whitespace only.
RE_FULL_COMMENT = re.compile(r"^[ \t]*#")
RE_BLANK = re.compile(r"^[ \t]*$")

class StripError(Exception):
    pass


# ---------------------------------------------------------------------------
# The lexer
# ---------------------------------------------------------------------------
# State at the START of each line is all we need. The alphabet:
#   'N'  normal (command text) -- the ONLY state a line may be stripped from
#   'S'  inside '...'
#   'D'  inside "..."
#   'B'  inside `...` (command substitution)
# plus `cont`: the previous line ended in an unescaped backslash, so this line is
# a CONTINUATION of it. A '#' opening such a line is an argument, not a comment.


def line_states(text):
    """([(state, cont), ...], final_mode, refusals) -- one entry per line START.

    Line i's entry is the lexer state immediately before its first character.

    `refusals` is [(lineno, construct), ...] for the banned constructs, detected
    ONLY WHERE THEY WOULD EXECUTE. This distinction is load-bearing: every one of
    these scripts opens with a portability header that spells out the rules in
    prose --

        #   * NO $(...)      -- use `backticks`

    -- so a raw substring scan refuses every file in the repo for quoting the
    very rule that makes it safe. `$(` counts inside "..." and `...` too (command
    substitution is live there); `<<` counts only in NORMAL (inside quotes it is
    just two characters of data).
    """
    out = []
    refusals = []
    mode = "N"
    stack = []          # for nested `...` inside "..." etc.
    cont = False
    at_line_start = True
    prev_significant = None   # last char seen in NORMAL, for '#'-word detection
    i = 0
    n = len(text)
    in_comment = False
    lineno = 1

    out.append(("N", False))

    def hit(what):
        refusals.append((lineno, what))

    while i < n:
        c = text[i]

        if c == "\n":
            out.append((mode, cont))
            in_comment = False
            at_line_start = True
            prev_significant = None
            cont = False
            lineno += 1
            i += 1
            continue

        if in_comment:
            i += 1
            continue

        # Banned constructs, in the states where they would actually execute.
        if c == "$" and i + 1 < n and text[i + 1] == "(" and mode in ("N", "D", "B"):
            hit("POSIX command substitution `$(`")
        if c == "<" and i + 1 < n and text[i + 1] == "<" and mode == "N":
            hit("here-doc operator `<<`")

        if mode == "S":
            # No escapes whatsoever inside single quotes -- not even backslash.
            if c == "'":
                mode = stack.pop() if stack else "N"
            i += 1
            at_line_start = False
            continue

        if mode == "D":
            if c == "\\":
                # Inside "...", a backslash escapes the next char (and a newline
                # continues the string). Consume both, but if the next char is a
                # newline we must still record the line break.
                if i + 1 < n and text[i + 1] == "\n":
                    out.append((mode, False))
                    i += 2
                    at_line_start = True
                    continue
                i += 2
                at_line_start = False
                continue
            if c == '"':
                mode = stack.pop() if stack else "N"
            elif c == "`":
                stack.append(mode)
                mode = "B"
            i += 1
            at_line_start = False
            continue

        if mode == "B":
            if c == "\\":
                if i + 1 < n and text[i + 1] == "\n":
                    out.append((mode, False))
                    i += 2
                    at_line_start = True
                    continue
                i += 2
                at_line_start = False
                continue
            if c == "`":
                mode = stack.pop() if stack else "N"
            elif c == "'":
                stack.append(mode)
                mode = "S"
            elif c == '"':
                stack.append(mode)
                mode = "D"
            i += 1
            at_line_start = False
            continue

        # mode == 'N'
        if c == "\\":
            if i + 1 < n and text[i + 1] == "\n":
                # Unescaped backslash-newline: line continuation.
                out.append(("N", True))
                i += 2
                at_line_start = True
                prev_significant = None
                cont = True
                continue
            i += 2
            at_line_start = False
            prev_significant = "x"
            continue
        if c == "'":
            stack.append("N")
            mode = "S"
            i += 1
            at_line_start = False
            continue
        if c == '"':
            stack.append("N")
            mode = "D"
            i += 1
            at_line_start = False
            continue
        if c == "`":
            stack.append("N")
            mode = "B"
            i += 1
            at_line_start = False
            continue
        if c == "#":
            # '#' opens a comment only at the start of a WORD: at line start, or
            # after whitespace or a command separator. `${x#pat}`, `$#`, `a#b`
            # are all literal, and every one of them occurs in these scripts.
            if at_line_start or (prev_significant is not None and prev_significant in " \t;&|()"):
                in_comment = True
            i += 1
            at_line_start = False
            prev_significant = "#"
            continue

        prev_significant = c
        if c not in " \t":
            at_line_start = False
        i += 1

    # `out` has one entry per line START; drop the phantom past the final newline
    # so len(out) == number of lines.
    nlines = len(text.split("\n"))
    while len(out) > nlines:
        out.pop()
    while len(out) < nlines:
        out.append((mode, cont))
    return out, mode, refusals


def strip_text(text, name="<text>"):
    """Return (stripped_text, removed_line_numbers)."""
    states, final, refusals = line_states(text)
    if refusals:
        ln, what = refusals[0]
        raise StripError(
            "%s: REFUSING to strip -- %s in CODE at line %d (%d site(s) total). This "
            "tool does not guess at constructs it cannot lex safely; extend the lexer "
            "with tests instead of loosening the gate." % (name, what, ln, len(refusals))
        )
    if final != "N":
        raise StripError(
            "%s: REFUSING to strip -- the file does not end in NORMAL lexer state "
            "(ended in %r): an unterminated quote or command substitution." % (name, final)
        )
    lines = text.split("\n")
    keep = []
    removed = []
    for idx, ln in enumerate(lines):
        state, cont = states[idx]
        strippable = (
            idx > 0                                  # line 1 is always kept
            and state == "N"
            and not cont
            and (RE_BLANK.match(ln) or RE_FULL_COMMENT.match(ln))
        )
        # The final element of split("\n") is the empty string after the trailing
        # newline; keep it so the file still ends with exactly one newline.
        if idx == len(lines) - 1 and ln == "":
            keep.append(ln)
            continue
        if strippable:
            removed.append(idx + 1)
        else:
            keep.append(ln)
    return "\n".join(keep), removed


# ---------------------------------------------------------------------------
# The gates
# ---------------------------------------------------------------------------
def _tokens(text):
    """Independent oracle: shlex is a lexer nobody in this repo wrote."""
    lx = shlex.shlex(text, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    lx.commenters = "#"
    return list(lx)


def _code_lines(text):
    states, _, _ = line_states(text)
    out = []
    for idx, ln in enumerate(text.split("\n")):
        state, cont = states[idx]
        if state == "N" and not cont and (RE_BLANK.match(ln) or RE_FULL_COMMENT.match(ln)):
            if idx > 0:
                continue
        out.append(ln)
    return out


def _dash_n(text, name):
    sh = "/usr/bin/dash" if os.path.exists("/usr/bin/dash") else "sh"
    fd, path = tempfile.mkstemp(suffix=".sh")
    try:
        os.write(fd, text.encode())
        os.close(fd)
        return subprocess.call([sh, "-n", path], stderr=subprocess.DEVNULL) == 0
    finally:
        os.unlink(path)


def verify(orig, stripped, removed, name):
    """Seven gates. Any failure raises -- the caller must not write the output."""
    o_lines = orig.split("\n")
    s_lines = stripped.split("\n")

    # G1 -- the output is a SUBSEQUENCE of the input (nothing added, nothing reordered)
    it = iter(o_lines)
    if not all(any(x == y for y in it) for x in s_lines):
        raise StripError("%s: G1 FAILED -- output is not a subsequence of the input" % name)

    # G2 -- every removed line really is blank or a full-line comment
    for n in removed:
        ln = o_lines[n - 1]
        if not (RE_BLANK.match(ln) or RE_FULL_COMMENT.match(ln)):
            raise StripError("%s: G2 FAILED -- removed line %d is not blank/comment: %r" % (name, n, ln))

    # G3 -- line 1 survived
    if not s_lines or s_lines[0] != o_lines[0]:
        raise StripError("%s: G3 FAILED -- line 1 was not preserved" % name)

    # G4 -- both files lex to a balanced final state
    for label, text in (("input", orig), ("output", stripped)):
        _, final, _ = line_states(text)
        if final != "N":
            raise StripError("%s: G4 FAILED -- %s ends in lexer state %r, not NORMAL" % (name, label, final))

    # G5 -- the stripped file still parses
    if not _dash_n(stripped, name):
        raise StripError("%s: G5 FAILED -- `sh -n` refuses the stripped output" % name)

    # G6 -- ★ INDEPENDENT ORACLE: shlex token streams must be identical.
    # This is what catches a line deleted out of the middle of a quoted string:
    # the quoted content would change, and shlex -- which we did not write --
    # would render a different token.
    to, ts = _tokens(orig), _tokens(stripped)
    if to != ts:
        for i, (a, b) in enumerate(zip(to, ts)):
            if a != b:
                raise StripError(
                    "%s: G6 FAILED -- shlex token %d differs: input %r vs output %r" % (name, i, a, b)
                )
        raise StripError("%s: G6 FAILED -- shlex token COUNT differs: %d vs %d" % (name, len(to), len(ts)))

    # G7 -- the surviving code lines are byte-identical to the input's code lines
    if _code_lines(orig) != _code_lines(stripped):
        raise StripError("%s: G7 FAILED -- a non-comment, non-blank line changed" % name)


def strip_file(src, dst):
    with open(src, "r", encoding="utf-8", errors="surrogateescape") as f:
        orig = f.read()
    name = os.path.basename(src)
    stripped, removed = strip_text(orig, name)
    verify(orig, stripped, removed, name)
    with open(dst, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(stripped)
    # Report BYTES, not characters: the comments carry multi-byte UTF-8 (the
    # repo's `star` and `section` marks), so a character count understates the
    # input by ~60 bytes and the whole point of this tool is a byte budget.
    return os.path.getsize(src), os.path.getsize(dst), len(removed)


# ---------------------------------------------------------------------------
# Self-test -- every gate and every hazard, proven to fire. No media needed.
# ---------------------------------------------------------------------------
def self_test():
    fails = []

    def ok(msg):
        print("  OK    %s" % msg)

    def bad(msg):
        print("  FAIL  %s" % msg)
        fails.append(msg)

    def expect_kept(label, body, needle):
        try:
            out, _ = strip_text(body, label)
        except StripError as e:
            bad("%s: unexpectedly refused (%s)" % (label, e))
            return
        if needle in out:
            ok(label)
        else:
            bad("%s: %r was stripped but is DATA" % (label, needle))

    def expect_refused(label, body, why):
        try:
            strip_text(body, label)
        except StripError:
            ok("%s (refused: %s)" % (label, why))
            return
        bad("%s: was NOT refused" % label)

    print("strip-sh-comments: proving each hazard is handled (synthetic, no media)\n")

    # 1. A blank line inside a multi-line double-quoted string is DATA.
    expect_kept(
        "blank line inside a multi-line \"...\" string",
        '#!/bin/sh\necho "menu:\n\n 1) one\n"\n# a real comment\n',
        'echo "menu:\n\n 1) one\n"',
    )

    # 2. A '#'-leading line inside a multi-line string is DATA.
    expect_kept(
        "'#'-leading line inside a multi-line \"...\" string",
        '#!/bin/sh\necho "head\n# not a comment\ntail"\n',
        "# not a comment",
    )

    # 3. Same, single-quoted.
    expect_kept(
        "'#'-leading line inside a multi-line '...' string",
        "#!/bin/sh\nx='head\n# not a comment\ntail'\n",
        "# not a comment",
    )

    # 4. After a backslash line-continuation, a '#' line is an ARGUMENT.
    expect_kept(
        "'#'-leading line after a backslash continuation",
        "#!/bin/sh\nset -- one \\\n  '#two'\n",
        "'#two'",
    )

    # 5. Inside backticks.
    expect_kept(
        "blank line inside `...` command substitution",
        "#!/bin/sh\nx=`echo a\n\necho b`\n",
        "echo a\n\necho b",
    )

    # 6. Here-doc -> hard refusal.
    expect_refused("here-doc present", "#!/bin/sh\ncat <<EOF\n# data\nEOF\n", "<<")

    # 7. $( ) -> hard refusal.
    expect_refused("$( ) present", "#!/bin/sh\nx=$(echo hi)\n", "$(")

    # 8. Unterminated quote -> refusal (G4 via strip_text).
    expect_refused("unterminated quote", '#!/bin/sh\necho "oops\n', "unbalanced")

    # 9. ${VAR#pat} is not a comment, and the line survives untouched.
    expect_kept("${VAR#pat} is not a comment", "#!/bin/sh\necho ${x#foo}\n", "${x#foo}")

    # 10. $# is not a comment.
    expect_kept("$# is not a comment", "#!/bin/sh\necho $#\n", "echo $#")

    # 11. A trailing comment on a code line is left alone.
    expect_kept("trailing comment on a code line is untouched", "#!/bin/sh\necho hi   # tail\n", "echo hi   # tail")

    # 12. Line 1 is always kept even though it is a '#' line.
    src = "#!/bin/sh\n# gone\necho hi\n"
    out, removed = strip_text(src, "line-1")
    if out.startswith("#!/bin/sh\n") and "# gone" not in out and removed == [2]:
        ok("line 1 kept, line 2 comment removed")
    else:
        bad("line-1 handling: out=%r removed=%r" % (out, removed))

    # 13. Ordinary comments and blanks really do go.
    src = "#!/bin/sh\n\n# one\n   # two\necho hi\n\n\n# three\n"
    out, removed = strip_text(src, "ordinary")
    if out == "#!/bin/sh\necho hi\n" and len(removed) == 6:
        ok("ordinary comments + blank lines removed (6 lines)")
    else:
        bad("ordinary strip: out=%r removed=%r" % (out, removed))

    # 14. The verify() gates must FIRE on a corrupted output.
    orig = '#!/bin/sh\necho "a\n\nb"\n'
    corrupt = '#!/bin/sh\necho "a\nb"\n'          # blank line wrongly deleted from a string
    try:
        verify(orig, corrupt, [3], "corrupt")
        bad("verify() did NOT fire on a line deleted out of a quoted string")
    except StripError as e:
        if "G6" in str(e) or "G7" in str(e) or "G1" in str(e):
            ok("verify() fires on a line deleted out of a quoted string (%s)" % str(e).split("--")[0].strip())
        else:
            bad("verify() fired with an unexpected gate: %s" % e)

    # 15. verify() must FIRE if a code line is altered.
    try:
        verify("#!/bin/sh\necho hi\n", "#!/bin/sh\necho HI\n", [], "altered")
        bad("verify() did NOT fire on an altered code line")
    except StripError:
        ok("verify() fires on an altered code line")

    print("\nstrip-sh-comments self-test: %s" % ("PASS" if not fails else "FAIL (%d)" % len(fails)))
    return 1 if fails else 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 3:
        sys.stderr.write("usage: %s IN OUT   |   %s --self-test\n" % (PROG, PROG))
        return 2
    try:
        a, b, nrm = strip_file(argv[1], argv[2])
    except StripError as e:
        sys.stderr.write("%s: STOP: %s\n" % (PROG, e))
        return 1
    sys.stderr.write(
        "%s: %s  %d -> %d bytes (-%d, %.0f%%), %d comment/blank lines removed; 7/7 gates passed\n"
        % (PROG, os.path.basename(argv[1]), a, b, a - b, 100.0 * (a - b) / a, nrm)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

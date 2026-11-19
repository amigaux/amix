# gencat catalogue formats

What the AMIX 2.1c `gencat` writes, and what this host `gencat` writes
byte for byte. Every integer is 32 bits, big-endian. There is no padding
and every byte is defined: the same input always gives the same output.

## Command line

    gencat [-l] [-m] catfile [msgfile ...]

- Options are read one per argument, and only the letter after the `-`
  counts (`-lm` is the same as `-l`).
- `-m` writes one file in the old "malloc" format. Without it, two files
  are written: `catfile` (the set table) and `catfile.m` (the strings, in
  `mkmsgs` format).
- `-l` lists the messages of an existing `catfile` as they are read back.
- With no msgfile, the source comes from standard input. With more than
  one, each name is printed on standard output (`name:`) before it is read.
- An existing `catfile` is read first, whatever its format (the first word
  is checked for the magic number), and the source is merged over it.
  For the default format the strings come from `catfile.m`; if that file
  is missing, the old messages are dropped.
- The usage text of the target tool shows `-s`, but that tool does not
  accept it.
- `gencat --dump catfile` is an extension of this host tool. It prints
  every message the way `catgets(3C)` returns it.

Unlike the target tool, the host tool exits with status 1 when nothing was
written because the source had errors, or on a usage error. The target
tool exits 0 in both cases.

## The "malloc" catalogue (`-m`)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `0xFF88FF89` |
| 4 | 4 | number of sets |
| 8 | 4 | size of everything after this header |
| 12 | 4 | offset of the message headers, from the end of this header (= 12 x sets) |
| 16 | 4 | offset of the text, from the end of this header (= 12 x (sets + messages)) |

Then one 12-byte header per set, in ascending set number:

| Size | Field |
|---|---|
| 4 | set number |
| 4 | number of messages in the set (can be 0) |
| 4 | index of the set's first message header (counting from 0 over the whole file) |

Then one 12-byte header per message, set by set, ascending message number:

| Size | Field |
|---|---|
| 4 | message number |
| 4 | length of the text including its NUL |
| 4 | offset of the text in the text area |

Then the text area: every message followed by one NUL, in header order.

## The default catalogue

`catfile`:

| Size | Field |
|---|---|
| 4 | N, the highest set number |
| 8 x N | for set i = 1..N: `first`, `last` |

`first` is the index in `catfile.m` of message 1 of set i. `last` is the
highest message number in that set. Message m of set i is string
`first + m - 1`. A set number that is not in use, and a set with no
messages, has `first = last = 0`.

`catfile.m` (the format `mkmsgs` writes):

| Size | Field |
|---|---|
| 4 | K, the number of strings |
| 4 x K | offset of string k (k = 1..K), from the start of the file |
| ... | the strings, each followed by a NUL |

Within a set, the message numbers below `last` that are not defined take
the one-byte string `\001`. The readers treat it as "no such message".
Every catalogue has a set 1, even an empty one.

## Source syntax, as the tool reads it

Lines are read with a 1024-byte buffer. "Spaces" below means the space
character and the byte 0xA0 (the target classifies the upper half of the
byte range as ISO 8859-1). "White space" adds tab, newline, vertical tab,
form feed and carriage return.

- Leading spaces are skipped. A line that is empty or only spaces is
  ignored.
- `$set n`, `$delset n`, `$quote c`: the number or character is the first
  non-space character after the keyword (tabs are not skipped there).
  Text after the set number is a comment. Any other line that starts with
  `$` is a comment. A set number outside 1..1024 is ignored with a
  warning. `$delset` of the current set makes set 1 current. Deleting
  set 1 leaves an empty set 1.
- `$quote` with nothing after it turns quoting off. Each source file
  starts with quoting off and with set 1 current.
- Message line: a decimal number (1..32767), then:
  - a newline right after the number deletes the message;
  - spaces only, then the end of the line, stores an empty message;
  - otherwise all spaces after the number are skipped. With quoting off,
    one more white-space character (for example a tab) is skipped as well.
    The rest of the line is the text.
- With quoting on, white space before the opening quote is skipped. After
  the closing quote only white space may follow. Text that does not start
  with the quote character is taken as it is, but a bare quote character
  inside it is an error. `\` followed by the quote character gives that
  character.
- Escapes: `\n \t \v \b \r \f \\ \" \'`. `\` followed by digits is octal,
  with any number of digits, kept modulo 256. `\0x` or `\0X` followed by
  hexadecimal digits is hexadecimal. A backslash at the end of the line
  joins the next line to this one. Before any other character, the
  backslash is dropped.
- At most 1024 bytes of text per message. Any error in a message (an
  unmatched quote, an unexpected quote, extra characters, a text that is
  too long) means that nothing is written at all.
- A last line with no newline is an error when quoting is off.

## Default mode: the mkmsgs pass

In the default format, `\n` and `\\` stay as two-character escapes in the
text that is passed to the `mkmsgs` step. All other escapes are already
turned into bytes. Each message becomes one line. The `mkmsgs` step then
applies its own escapes: `\n \t \b \r \f \v \a \\`, one to three octal
digits, and any other character stands for itself. The string ends at its
first NUL. As a result:

- a message that contains a newline byte made with an octal or hex escape
  (for example `\012`) splits into two strings, and every string after it
  in `catfile.m` moves down by one;
- a message that contains a NUL byte (`\0`) makes the `mkmsgs` step
  refuse the input. `catfile` is still written, but `catfile.m` is left
  as it was;
- a backslash byte made with an escape (`\134`) starts a second escape.

The `-m` format stores the bytes as they are, so for such text the two
formats differ. Reading a catalogue back escapes newline and backslash
again, so a default catalogue merges into itself unchanged. When a
catalogue is converted between the two formats by merging, those two
escapes are carried over literally.

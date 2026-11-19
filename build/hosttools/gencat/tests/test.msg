$ test catalogue for the host gencat
$ messages before any $set go to set 1
1 Default set message one
3 Default set message three
2 Will be replaced
2 Default set message two

$set 2 second set, comment after the number
5 Five comes first in the file
1 One\tTab escape
2 Newline\nescape
3 Vertical\vtab backspace\b cr\r ff\f end
4 Backslash \\ escaped
6 Octal \7 \60 \101 four-digit \1015 hex \0x41
7 Unknown \q escape drops the backslash
8 This line continues \
on the next line
9 
10 to be deleted
10
12 Gap before me
$set 5
1	Tab separator
2  Two spaces after the number
$quote "
3 "Quoted with trailing spaces   "
4 ""
5 "Quoted \"inner\" quotes"
6 Unquoted after quote is set
$quote
7 Quote char "off" again
$set 9 a set to delete
1 Deleted with the set
$delset 9 comment after delset
$set 12
1 Last set

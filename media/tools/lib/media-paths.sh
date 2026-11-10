# tools/lib/media-paths.sh -- where the media tools read and write, sourced after `repo` (media/) is set.
#
#   MEDIA_TOP      the amix checkout (media/..)
#   MEDIA_SCRATCH  scratch for every build step: out/build/media of the checkout (gitignored with out/)
#   L11_IN         the media's inputs, laid out by media/build.sh from make dist's out/ (MEDIA_SCRATCH/in)
#
# Each may be set by the caller. Nothing here reads outside the checkout.
MEDIA_TOP="${MEDIA_TOP:-$(cd "$repo/.." && pwd)}"
MEDIA_SCRATCH="${MEDIA_SCRATCH:-$MEDIA_TOP/out/build/media}"
L11_IN="${L11_IN:-$MEDIA_SCRATCH/in}"
export MEDIA_TOP MEDIA_SCRATCH L11_IN
# the one ufs reader: amix tools/lib (media's own lib first for the rest)
export PYTHONPATH="$repo/tools/lib:$MEDIA_TOP/tools/lib${PYTHONPATH:+:$PYTHONPATH}"

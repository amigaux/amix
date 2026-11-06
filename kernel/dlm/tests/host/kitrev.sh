#!/bin/sh
# kitrev.sh -- mkkit's short_rev: eight digits from a real git, in any clone;
# the label a recipe gives from the export's git, which answers --short alone;
# unknown outside a repository.
set -e
T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT
sed -n '/^short_rev() {/,/^}/p' tools/mkkit.sh > "$T/f.sh"
. "$T/f.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$T/r"
git -C "$T/r" commit -q --allow-empty -m one
full=$(git -C "$T/r" rev-parse HEAD)
[ "$(short_rev "$T/r")" = "$(echo "$full" | cut -c1-8)" ]
# whatever this clone's own abbreviation is
git -C "$T/r" config core.abbrev 12
[ "$(short_rev "$T/r")" = "$(echo "$full" | cut -c1-8)" ]
mkdir "$T/none"
[ "$(GIT_CEILING_DIRECTORIES=$T short_rev "$T/none")" = unknown ]
# an export's git: the recipe's label, of whatever length, and nothing else
mkdir "$T/bin"
cat > "$T/bin/git" <<'SHIM'
#!/bin/sh
case "$*" in
*"rev-parse --short HEAD") echo abcdef1234 ;;
*) exit 1 ;;
esac
SHIM
chmod +x "$T/bin/git"
[ "$(PATH=$T/bin:$PATH short_rev "$T/r")" = abcdef1234 ]
echo "kitrev: ok"

# package.sh -- Vim 9.1.0000 (P-31 sec 10.9); assignments only.
NAME=vim
PKG=vim
VERSION=9.1.0000
PKGREV=1
SUMMARY="Vim 9.1 - the editor, terminal only"
DESC="Vim 9.1.0000 with the normal feature set, terminal only (no GUI, no X), linked statically against ncurses 6.6, with its runtime (syntax, filetype plugins, help) in /opt/amix/share/vim, vimtutor and xxd. Installs /opt/amix/bin/vim with ex, view, vimdiff, rvim and rview; the stock vi is untouched. Needs a UFS file system (runtime names over 14 bytes)."
CATEGORY=editor
SET=extra
LICENSE=Vim
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/vim-9.1.0000/v9.1.0000.tar.gz
URL=https://github.com/vim/vim/archive/refs/tags/v9.1.0000.tar.gz
SHA256=8d2a74e358be9cf260174e15e2e29dba4773f2670718b5bf728db6f54b90e25d
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS="ncurses"

# docs

Documentation for building and working on Amix.

- [BUILDING.md](BUILDING.md): building Amix yourself: `make tools`, `make dist`, its steps and out/, checking a build against a release, and the rules that make a build reproducible.
- [build-tools.md](build-tools.md): which build tools come from the build container (perl, m4, bison, flex, Tcl, OpenSP, rpcgen) and which are built from our sources (gencat, bdftopcf, mkfontdir, imake, makedepend), and why.
- [RELEASING.md](RELEASING.md): how releases are made: betas, tags, the package repositories, fixes.
- [ci.md](ci.md): what CI runs on every push and pull request, and how to run it locally.

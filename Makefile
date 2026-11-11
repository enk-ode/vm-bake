# vm-bake Makefile (BSD make).
#
#   make metadata   regenerate the anchor tables in vm-bake.sh and the test
#                   suites from the anchor functions in include/*.sh
#   make check      syntax-check every shell source (sh -n)
#   make test       the architecture rules, then the unit tests
#   make manpage    docs/vm-bake.8.md from the help blocks (vm-bake help manual),
#                   docs/vm-bake.8 (pandoc) and docs/vm-bake.html, index.html
#                   (mandoc) -- the GitHub Pages site is served from /docs
#   make install    the wrapper ${BINDIR}/vm-bake execs this checkout, the
#                   manual page into ${MANDIR}

SCRIPT=		vm-bake.sh
TESTS=		vm-bake-architecture-test.sh vm-bake-unit-test.sh
INCLUDE_DIR=	include
INCLUDES!=	echo ${INCLUDE_DIR}/*.sh
MODULE_SRCS!=	echo ${INCLUDE_DIR}/*.sh | tr ' ' '\n' | grep -v engine.sh | tr '\n' ' '

.PHONY: metadata check test archtest unittest manpage install uninstall

# Terminals: exactly ONE leading underscore. Modules: every anchor (_, __,
# ___) mapped to its basename. The lists replace the maintained lines in
# ${SCRIPT} and the suites in place; run `make metadata` after adding or
# renaming anchors.
metadata:
	@terms=$$(grep -hE '^_[a-z][a-z0-9_]*\(\)' ${INCLUDES} \
	    | sed 's/().*//' | tr '\n' ' ' | sed 's/ $$//'); \
	mods=$$(awk 'FNR == 1 { f = FILENAME; sub(".*/", "", f) } \
	    /^_+[a-z][a-z0-9_]*\(\)/ { n = $$0; sub(/\(\).*/, "", n); printf "%s:%s ", n, f }' \
	    ${MODULE_SRCS} | sed 's/ $$//'); \
	combs=$$(grep -hE '^__[a-z][a-z0-9_]*\(\)' ${INCLUDES} \
	    | sed 's/().*//' | tr '\n' ' ' | sed 's/ $$//'); \
	batches=$$(grep -hE '^___[a-z][a-z0-9_]*\(\)' ${INCLUDES} \
	    | sed 's/().*//' | tr '\n' ' ' | sed 's/ $$//'); \
	stems=$$(printf '%s\n' $$terms $$combs $$batches | awk '{ s = $$0; sub(/^_+/, "", s); sub(/[0-9]$$/, "", s); \
	    if (!(s in t)) { order[++n] = s; t[s] = $$0 } else t[s] = t[s] " " $$0 } \
	    END { for (i = 1; i <= n; i++) printf "ANCHOR_STEM_%s=\047%s\047 ", order[i], t[order[i]] }' | sed 's/ $$//'); \
	sed -i.mkbak \
	    -e "s|^TERMINAL_FUNCTIONS=.*|TERMINAL_FUNCTIONS=\"$$terms\"|" \
	    -e "s|^COMBINATOR_FUNCTIONS=.*|COMBINATOR_FUNCTIONS=\"$$combs\"|" \
	    -e "s|^BATCH_COMBINATOR_FUNCTIONS=.*|BATCH_COMBINATOR_FUNCTIONS=\"$$batches\"|" \
	    -e "s|^ANCHOR_STEM_TABLE=.*|ANCHOR_STEM_TABLE=\"$$stems\"|" \
	    -e "s|^FUNCTION_MODULES=.*|FUNCTION_MODULES=\"$$mods\"|" ${SCRIPT}; \
	rm -f ${SCRIPT}.mkbak; \
	for t in ${TESTS}; do \
	    sed -i.mkbak \
	        -e "s|^TERMINAL_FUNCTIONS=.*|TERMINAL_FUNCTIONS=\"$$terms\"|" \
	        -e "s|^COMBINATOR_FUNCTIONS=.*|COMBINATOR_FUNCTIONS=\"$$combs\"|" \
	        -e "s|^BATCH_COMBINATOR_FUNCTIONS=.*|BATCH_COMBINATOR_FUNCTIONS=\"$$batches\"|" \
	        -e "s|^ANCHOR_FUNCTIONS=.*|ANCHOR_FUNCTIONS=\"$$terms $$combs $$batches\"|" \
	        -e "s|^FUNCTION_MODULES=.*|FUNCTION_MODULES=\"$$mods\"|" "$$t"; \
	    rm -f "$$t.mkbak"; \
	done; \
	echo "metadata: $$(echo $$terms | wc -w | tr -d ' ') terminals," \
	    "$$(echo $$combs | wc -w | tr -d ' ') combinators," \
	    "$$(echo $$batches | wc -w | tr -d ' ') batches -> ${SCRIPT} ${TESTS}"

check:
	@for f in ${SCRIPT} ${INCLUDES} ${TESTS} scripts/*.sh; do sh -n "$$f" || exit 1; done
	@echo "check: syntax ok"

test: archtest unittest

archtest:
	@./vm-bake-architecture-test.sh

unittest:
	@./vm-bake-unit-test.sh ${TESTARGS}

# FreeBSD conventions (bsd.own.mk): PREFIX is the install prefix (default
# /usr/local, needs root), DESTDIR a staging root. A per-user install:
#   make PREFIX=${HOME} install   -> ~/bin/vm-bake
# The wrapper execs THIS checkout: a development install, `git pull` is the
# update.
PREFIX?=	/usr/local
DESTDIR?=
BINDIR?=	${PREFIX}/bin
WRAPPER=	${DESTDIR}${BINDIR}/vm-bake
.if ${PREFIX:M${HOME}*} != ""
COMPLETIONDIR?=	${HOME}/.local/share/bash-completion/completions
.else
COMPLETIONDIR?=	${PREFIX}/share/bash-completion/completions
.endif
COMPLETION=	${DESTDIR}${COMPLETIONDIR}/vm-bake

install:
	@mkdir -p ${DESTDIR}${BINDIR} ${DESTDIR}${COMPLETIONDIR} ${DESTDIR}${MANDIR}
	@printf '#!/bin/sh\n# vm-bake wrapper (make install from %s)\nexec /bin/sh %s/vm-bake.sh "$$@"\n' \
	    '${.CURDIR}' '${.CURDIR}' > ${WRAPPER}.tmp
	@install -m 0755 ${WRAPPER}.tmp ${WRAPPER} && rm -f ${WRAPPER}.tmp
	@rm -f ${COMPLETION} && ln -s ${.CURDIR}/completion/vm-bake.bash ${COMPLETION}
	@echo "install: ${WRAPPER} -> ${.CURDIR}/vm-bake.sh"
	@echo "install: ${COMPLETION} (bash completion)"
	@test ! -f docs/vm-bake.8 || { install -m 0644 docs/vm-bake.8 ${MANPAGE} && echo "install: ${MANPAGE}"; }

uninstall:
	@rm -f ${WRAPPER} ${COMPLETION} ${MANPAGE}
	@echo "uninstall: ${WRAPPER} and ${COMPLETION} removed"

# The manual page is generated: the help blocks of the anchors (make
# metadata keeps their tables) render through `vm-bake help manual` into
# docs/vm-bake.8.md, pandoc turns that into the groff page and mandoc
# renders the HTML with man.css, the same look as the page in a terminal;
# index.html is the copy GitHub Pages serves from /docs. All four are
# committed, so packagers and readers need neither pandoc nor a database.
# `help manual` reads the active database (VM_BAKE_BASE overrides it).
MANDIR?=	${PREFIX}/share/man/man8
MANPAGE=	${DESTDIR}${MANDIR}/vm-bake.8

manpage:
	@command -v pandoc > /dev/null 2>&1 || { echo "manpage: pandoc not found (pkg install hs-pandoc)"; exit 1; }
	@command -v mandoc > /dev/null 2>&1 || { echo "manpage: mandoc not found"; exit 1; }
	@./vm-bake.sh help manual > docs/vm-bake.8.md
	@pandoc -f markdown-tex_math_dollars-raw_tex -s -t man docs/vm-bake.8.md -o docs/vm-bake.8
	@mandoc -T lint docs/vm-bake.8
	@mandoc -T html -O style=man.css docs/vm-bake.8 > docs/vm-bake.html
	@cp docs/vm-bake.html docs/index.html
	@echo "manpage: docs/vm-bake.8.md docs/vm-bake.8 docs/vm-bake.html docs/index.html"

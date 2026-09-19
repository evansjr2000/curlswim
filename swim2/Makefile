# Makefile --- build the swim-times literate program.
#
# The .w file is the source of record; swim-times.c and swim-times.tex
# are build artefacts and are listed in .gitignore.
#
# Targets:
#   all        tangle + compile  (default)
#   tangle     extract swim-times.c from swim-times.w
#   weave      produce swim-times.tex from swim-times.w
#   doc        weave + pdftex -> swim-times.pdf
#   report     typeset the problem/fix report and the test plan
#   compile    build the swim-times executable
#   selftest   run the built-in SHA-256 / HMAC known-answer tests
#   diag       probe USA Swimming data-hub reachability
#   test       run the full requirements test suite
#   db-test    run the Postgres mirror checks
#   clean      remove build artefacts

PROGRAM  = swim-times
SOURCE   = swim-times.w
C_SRC    = swim-times.c
TEX_SRC  = swim-times.tex

# CWEB tools.  Prefer a native ctangle/cweave when one is on PATH (TeX
# Live ships both); fall back to the container wrapper otherwise, so the
# build works with or without Docker.
CTANGLE := $(shell command -v ctangle 2>/dev/null)
CWEAVE  := $(shell command -v cweave  2>/dev/null)
CWEB     = ../cweb.sh

CC       = cc

# libpq (Postgres C client) is reached via pg_config; on macOS Homebrew
# ships it at /opt/homebrew/opt/libpq/bin/pg_config since libpq is a
# keg-only formula.  Override PG_CONFIG on the make command line for
# non-default installations.
PG_CONFIG ?= $(shell command -v pg_config 2>/dev/null || \
                     echo /opt/homebrew/opt/libpq/bin/pg_config)
PG_CFLAGS  = -I$(shell $(PG_CONFIG) --includedir)
PG_LDFLAGS = -L$(shell $(PG_CONFIG) --libdir) -lpq

CFLAGS   = -O2 -Wall $(PG_CFLAGS)
LDFLAGS  = $(shell curl-config --libs 2>/dev/null || echo "-lcurl") $(PG_LDFLAGS)

.PHONY: all tangle weave doc report compile selftest diag test db-test clean

all: tangle compile

# Extract C source from the CWEB literate source
tangle: $(C_SRC)

$(C_SRC): $(SOURCE)
ifeq ($(CTANGLE),)
	$(CWEB) ctangle $(SOURCE)
else
	$(CTANGLE) $(SOURCE)
endif

# Generate TeX documentation from the CWEB literate source
weave: $(TEX_SRC)

# cweave exits non-zero on formatting *warnings* (an over-long verbatim
# line, say) as well as on errors, so its status is not a build failure;
# the pdftex run that follows is the real check.
$(TEX_SRC): $(SOURCE)
ifeq ($(CWEAVE),)
	-$(CWEB) cweave $(SOURCE)
else
	-$(CWEAVE) $(SOURCE)
endif

doc: $(TEX_SRC)
	pdftex -interaction=nonstopmode $(TEX_SRC)
	@errs=`grep -c '^! ' swim-times.log 2>/dev/null`; \
	 if [ "$$errs" != "0" ]; then \
	     echo "pdftex reported $$errs error(s); see swim-times.log"; exit 1; \
	 fi
	@echo "swim-times.pdf written with no TeX errors"

report: swim-times-defect-report.pdf swim-times-stp.pdf

%.pdf: %.tex
	pdflatex -interaction=nonstopmode $< >/dev/null
	pdflatex -interaction=nonstopmode $< >/dev/null

# Compile the tangled C source into an executable
compile: $(PROGRAM)

$(PROGRAM): $(C_SRC)
	$(CC) $(CFLAGS) -o $(PROGRAM) $(C_SRC) $(LDFLAGS)

selftest: $(PROGRAM)
	./$(PROGRAM) -o selftest

diag: $(PROGRAM)
	./$(PROGRAM) -o diag

test: $(PROGRAM)
	./test-swim-times.sh

db-test: $(PROGRAM)
	./test-db.sh

clean:
	rm -f $(C_SRC) $(TEX_SRC) $(PROGRAM) *.idx *.scn *.log *.toc *.aux *.out

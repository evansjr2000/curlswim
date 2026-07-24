CWEB     = ../cweb.sh
PROGRAM  = swim-times
SOURCE   = swim-times.w
C_SRC    = swim-times.c
TEX_SRC  = swim-times.tex

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

.PHONY: all tangle weave compile clean run

all: tangle compile

# Extract C source from the CWEB literate source
tangle: $(C_SRC)

$(C_SRC): $(SOURCE)
	$(CWEB) ctangle $(SOURCE)

# Generate TeX documentation from the CWEB literate source
weave: $(TEX_SRC)

$(TEX_SRC): $(SOURCE)
	$(CWEB) cweave $(SOURCE)

# Compile the tangled C source into an executable
compile: $(PROGRAM)

$(PROGRAM): $(C_SRC)
	$(CC) $(CFLAGS) -o $(PROGRAM) $(C_SRC) $(LDFLAGS)

# Run the compiled program
run: $(PROGRAM)
	./$(PROGRAM)

clean:
	rm -f $(C_SRC) $(TEX_SRC) $(PROGRAM) *.idx *.scn *.log *.toc

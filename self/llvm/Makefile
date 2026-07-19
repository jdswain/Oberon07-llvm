# Self-hosted Oberon compiler, LLVM backend (oc-self).
#
# Frontend: the SHARED ORS/ORB/ORP.Mod (in ../), compiled by the stage-0
# C compiler ../../bin/oc. Backend: ORG.Mod (this dir) + ORG_rt.c (C, LLVM
# API) providing the strong definitions for ORG.Mod's weak stubs. Driver:
# main.c.
#
# The shared frontend .Mod files are COPIED in before compiling so this
# target's .smb/.o/.ll artifacts stay local (type sizes differ per backend,
# so artifacts must not be shared with s816/). Edit the masters in ../.
#
# ORG_rt.c and main.c are GENERATED from ../../src/{ORG,ORP}.c by
# gen_bridge.py — run `python3 gen_bridge.py` after changing those.

OC0 ?= ../../bin/oc
LLVM_CONFIG ?= /opt/homebrew/opt/llvm/bin/llvm-config

LLVM_CFLAGS  := $(shell $(LLVM_CONFIG) --cflags)
LLVM_LDFLAGS := $(shell $(LLVM_CONFIG) --ldflags)
LLVM_LIBS    := $(shell $(LLVM_CONFIG) --libs core bitwriter analysis) \
                $(shell $(LLVM_CONFIG) --system-libs)

RT := ../../runtime/posix

CC     := clang
CFLAGS := -std=c11 -Wall -Wno-unused-parameter -Wno-unused-function -g $(LLVM_CFLAGS)

MODS := ORS ORB ORG ORP
OBJS := $(MODS:%=%.o) ORG_rt.o main.o

all: oc-self

# Copy the shared frontend in from ../ (masters live there).
ORS.Mod: ../ORS.Mod
	cp ../ORS.Mod .
ORB.Mod: ../ORB.Mod
	cp ../ORB.Mod .
ORP.Mod: ../ORP.Mod
	cp ../ORP.Mod .

# Stage-0 compilation. Modules depend on each other's .smb files, so the
# order is fixed: ORS -> ORB -> ORG -> ORP.
ORS.o: ORS.Mod
	$(OC0) -s ORS.Mod
ORB.o: ORB.Mod ORS.o
	$(OC0) -s ORB.Mod
ORG.o: ORG.Mod ORB.o
	$(OC0) -s ORG.Mod
ORP.o: ORP.Mod ORG.o
	$(OC0) -s ORP.Mod

ORG_rt.c main.c: gen_bridge.py ../../src/ORG.c ../../src/ORP.c
	python3 gen_bridge.py

ORG_rt.o: ORG_rt.c
	$(CC) $(CFLAGS) -c -o $@ $<

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

oc-self: $(OBJS)
	$(CC) $(LLVM_LDFLAGS) -o $@ $(OBJS) \
	    $(RT)/Files.o $(RT)/Out.o $(RT)/Errors.o \
	    $(RT)/Files_rt.c $(RT)/Out_rt.c $(RT)/runtime.c \
	    $(LLVM_LIBS)

clean:
	rm -f *.o *.smb *.ll *.deps oc-self ORG_rt.c main.c ORS.Mod ORB.Mod ORP.Mod

.PHONY: all clean

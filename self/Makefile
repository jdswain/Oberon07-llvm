# Self-hosted Oberon compiler (oc-self).
#
# Frontend: ORS/ORB/ORP.Mod (Oberon, compiled by the stage-0 C compiler
# ../bin/oc). Backend: ORG_rt.c (C, LLVM API) providing the strong
# definitions for ORG.Mod's weak stubs. Driver: main.c.
#
# ORG_rt.c and main.c are GENERATED — edit src/ORG.c / the driver in
# src/ORP.c and run `python3 gen_bridge.py`.

OC0 ?= ../bin/oc
LLVM_CONFIG ?= /opt/homebrew/opt/llvm/bin/llvm-config

LLVM_CFLAGS  := $(shell $(LLVM_CONFIG) --cflags)
LLVM_LDFLAGS := $(shell $(LLVM_CONFIG) --ldflags)
LLVM_LIBS    := $(shell $(LLVM_CONFIG) --libs core bitwriter analysis) \
                $(shell $(LLVM_CONFIG) --system-libs)

RT := ../runtime/posix

CC     := clang
CFLAGS := -std=c11 -Wall -Wno-unused-parameter -Wno-unused-function -g $(LLVM_CFLAGS)

MODS := ORS ORB ORG ORP
OBJS := $(MODS:%=%.o) ORG_rt.o main.o

all: oc-self

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

ORG_rt.c main.c: gen_bridge.py ../src/ORG.c ../src/ORP.c
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
	rm -f *.o *.smb *.ll *.deps oc-self ORG_rt.c main.c

.PHONY: all clean

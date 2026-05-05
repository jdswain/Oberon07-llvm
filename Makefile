# Makefile for OC - Oberon front-end with LLVM backend.

LLVM_CONFIG ?= /opt/homebrew/opt/llvm/bin/llvm-config

LLVM_CFLAGS  := $(shell $(LLVM_CONFIG) --cflags)
LLVM_LDFLAGS := $(shell $(LLVM_CONFIG) --ldflags)
LLVM_LIBS    := $(shell $(LLVM_CONFIG) --libs core bitwriter analysis)
LLVM_SYSLIBS := $(shell $(LLVM_CONFIG) --system-libs)

CC      := clang
CFLAGS  := -std=c11 -Wall -Wno-unused-parameter -Wno-parentheses-equality -g -MMD -MP -Iinclude $(LLVM_CFLAGS)
LDFLAGS := $(LLVM_LDFLAGS)
LDLIBS  := $(LLVM_LIBS) $(LLVM_SYSLIBS)

SRC_DIR   := src
BUILD_DIR := build
BIN_DIR   := bin

SOURCES := \
	$(SRC_DIR)/ORS.c \
	$(SRC_DIR)/ORB.c \
	$(SRC_DIR)/ORP.c \
	$(SRC_DIR)/ORG.c \
	$(SRC_DIR)/Files.c \
	$(SRC_DIR)/Texts.c
# ORTool.c is a debug helper for old .816 object/symbol files; not part of the
# compiler driver. It also has pre-existing Texts_Write/Files_ReadNum API
# mismatches. Re-enable later once it has been ported to the LLVM backend.

OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

TARGET := $(BIN_DIR)/oc

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)

-include $(OBJECTS:.o=.d)

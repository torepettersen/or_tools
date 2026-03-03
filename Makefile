# Makefile for compiling CP-SAT NIF with Fine
#
# Required env vars (set in mix.exs):
#   FINE_INCLUDE_DIR — Fine C++ headers
#   ERTS_INCLUDE_DIR — Erlang runtime headers
#
# Optional env vars:
#   ORTOOLS_PREFIX — or-tools install prefix (default: /usr/local)

ORTOOLS_PREFIX ?= /usr/local

SRC = c_src/cp_sat.cpp
TARGET = priv/cp_sat.so

CPPFLAGS += -I$(FINE_INCLUDE_DIR)
CPPFLAGS += -I$(ERTS_INCLUDE_DIR)
CPPFLAGS += -I$(ORTOOLS_PREFIX)/include
CPPFLAGS += -DOR_PROTO_DLL=
CPPFLAGS += -std=c++17
CPPFLAGS += -fvisibility=hidden
CPPFLAGS += -fPIC
CPPFLAGS += -O2

LDFLAGS += -shared
LDFLAGS += -L$(ORTOOLS_PREFIX)/lib
LDFLAGS += -lortools
LDFLAGS += -Wl,-rpath,$(ORTOOLS_PREFIX)/lib

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -undefined dynamic_lookup
endif

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p priv
	$(CXX) $(CPPFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

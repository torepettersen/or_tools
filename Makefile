# Makefile for compiling OR-Tools NIF with Fine

ORTOOLS_PREFIX = /nix/store/8yr2d5ljp846cr62bj3rh51dbw9hf0vl-or-tools-9.14

# Paths
SRC_DIR = c_src
PRIV_DIR = priv

# Source and target
SRC = $(SRC_DIR)/or_tools_nif.cpp
TARGET = $(PRIV_DIR)/or_tools_nif.so

# Compiler flags
CPPFLAGS += -I$(FINE_INCLUDE_DIR)
CPPFLAGS += -I$(ERTS_INCLUDE_DIR)
CPPFLAGS += -I$(ORTOOLS_PREFIX)/include
CPPFLAGS += -I/nix/store/6g3bq1jfh0gghdacmmkpiiff97csiyab-abseil-cpp-20250512.1/include
CPPFLAGS += -I/nix/store/mbk8zngmikgm7pvhc7wfs4yy8ylmfqyx-protobuf-31.1/include
CPPFLAGS += -DOR_PROTO_DLL=
CPPFLAGS += -std=c++17
CPPFLAGS += -fvisibility=hidden
CPPFLAGS += -fPIC
CPPFLAGS += -O2

# Linker flags
LDFLAGS += -shared
LDFLAGS += -L$(ORTOOLS_PREFIX)/lib
LDFLAGS += -lortools
LDFLAGS += -Wl,-rpath,$(ORTOOLS_PREFIX)/lib

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -undefined dynamic_lookup
endif

# Build target
all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CPPFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f $(TARGET)

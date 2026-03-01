# Makefile for compiling OR-Tools NIF with Fine

# Paths
SRC_DIR = c_src
PRIV_DIR = priv

# Source and target
SRC = $(SRC_DIR)/or_tools_nif.cpp
TARGET = $(PRIV_DIR)/or_tools_nif.so

# Compiler flags for C++17 with Fine
CPPFLAGS += -I$(FINE_INCLUDE_DIR)
CPPFLAGS += -I$(ERTS_INCLUDE_DIR)
CPPFLAGS += -std=c++17
CPPFLAGS += -fvisibility=hidden
CPPFLAGS += -fPIC

# Linker flags
LDFLAGS += -shared

# Platform detection
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -undefined dynamic_lookup
endif

# Build target
all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CPPFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

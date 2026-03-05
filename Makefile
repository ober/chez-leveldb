SCHEME = scheme
CC = gcc
CFLAGS = -fPIC -O2 -Wall
LDFLAGS = -shared -lleveldb

SHIM_SO = leveldb_shim.so

.PHONY: all clean test

all: $(SHIM_SO)

$(SHIM_SO): leveldb_shim.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test: $(SHIM_SO)
	$(SCHEME) --script leveldb-test.ss

clean:
	rm -f $(SHIM_SO)

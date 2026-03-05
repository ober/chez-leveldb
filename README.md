# chez-leveldb

LevelDB bindings for Chez Scheme.

## Prerequisites

- Chez Scheme
- LevelDB C library (`libleveldb-dev` on Debian/Ubuntu)
- GCC

## Build

```bash
make
```

This compiles `leveldb_shim.so`, a small C shim that bridges Chez Scheme's FFI
with LevelDB's pointer+length API conventions.

## Test

```bash
make test
```

## Usage

```scheme
(import (leveldb))

;; Open a database
(define db (leveldb-open "/tmp/my-db"))

;; Put / Get / Delete
(leveldb-put db "key" "value")
(utf8->string (leveldb-get db "key"))  ; => "value"
(leveldb-delete db "key")
(leveldb-get db "key")                 ; => #f

;; Write batches (atomic)
(let ([wb (leveldb-writebatch)])
  (leveldb-writebatch-put wb "a" "1")
  (leveldb-writebatch-put wb "b" "2")
  (leveldb-write db wb)
  (leveldb-writebatch-destroy wb))

;; Iterators
(let ([iter (leveldb-iterator db)])
  (leveldb-iterator-seek-first iter)
  (let loop ()
    (when (leveldb-iterator-valid? iter)
      (printf "~a = ~a~%"
        (utf8->string (leveldb-iterator-key iter))
        (utf8->string (leveldb-iterator-value iter)))
      (leveldb-iterator-next iter)
      (loop)))
  (leveldb-iterator-close iter))

;; Fold over a range (start inclusive, limit exclusive)
(leveldb-fold db
  (lambda (key val acc)
    (cons (cons (utf8->string key) (utf8->string val)) acc))
  '()
  "a" "z")

;; Snapshots
(let ([snap (leveldb-snapshot db)])
  (leveldb-put db "key" "new-value")
  (let ([opts (leveldb-read-options 'snapshot snap)])
    (utf8->string (leveldb-get db "key" opts)))  ; => old value
  (leveldb-snapshot-release db snap))

;; Options
(define db2 (leveldb-open "/tmp/my-db2"
  (leveldb-options
    'create-if-missing #t
    'compression #t
    'lru-cache-capacity 10000000
    'bloom-filter-bits 10)))

;; Close
(leveldb-close db)
```

## API Reference

### Core Operations
- `(leveldb-open name [opts])` - Open a database
- `(leveldb-close db)` - Close a database
- `(leveldb-put db key val [write-opts])` - Store a key-value pair
- `(leveldb-get db key [read-opts])` - Retrieve a value (returns bytevector or #f)
- `(leveldb-delete db key [write-opts])` - Delete a key
- `(leveldb-key? db key [read-opts])` - Check if a key exists
- `(leveldb-write db batch [write-opts])` - Apply a write batch atomically

### Write Batches
- `(leveldb-writebatch)` - Create a new write batch
- `(leveldb-writebatch-put batch key val)` - Add a put operation
- `(leveldb-writebatch-delete batch key)` - Add a delete operation
- `(leveldb-writebatch-clear batch)` - Clear all pending operations
- `(leveldb-writebatch-append dest src)` - Append one batch to another
- `(leveldb-writebatch-destroy batch)` - Free a write batch

### Iterators
- `(leveldb-iterator db [read-opts])` - Create an iterator
- `(leveldb-iterator-close iter)` - Destroy an iterator
- `(leveldb-iterator-valid? iter)` - Check if positioned at a valid entry
- `(leveldb-iterator-seek-first iter)` - Seek to the first entry
- `(leveldb-iterator-seek-last iter)` - Seek to the last entry
- `(leveldb-iterator-seek iter key)` - Seek to the first entry >= key
- `(leveldb-iterator-next iter)` / `(leveldb-iterator-prev iter)` - Navigate
- `(leveldb-iterator-key iter)` / `(leveldb-iterator-value iter)` - Read current entry
- `(leveldb-iterator-error iter [raise?])` - Check for iteration errors

### Iteration Helpers
- `(leveldb-fold db proc init [start [limit [read-opts]]])` - Fold over key-value pairs
- `(leveldb-for-each db proc [start [limit [read-opts]]])` - Iterate over key-value pairs
- `(leveldb-fold-keys db proc init [start [limit [read-opts]]])` - Fold over keys only
- `(leveldb-for-each-keys db proc [start [limit [read-opts]]])` - Iterate over keys only

### Snapshots
- `(leveldb-snapshot db)` - Create a point-in-time snapshot
- `(leveldb-snapshot-release db snapshot)` - Release a snapshot

### Options
- `(leveldb-options key val ...)` - Create database options
  - Keys: `create-if-missing`, `error-if-exists`, `paranoid-checks`, `compression`,
    `write-buffer-size`, `max-open-files`, `block-size`, `block-restart-interval`,
    `max-file-size`, `lru-cache-capacity`, `bloom-filter-bits`, `env`
- `(leveldb-default-options)` - Cached default options
- `(leveldb-read-options key val ...)` - Create read options
  - Keys: `verify-checksums`, `fill-cache`, `snapshot`
- `(leveldb-default-read-options)` - Cached default read options
- `(leveldb-write-options key val ...)` - Create write options
  - Keys: `sync`
- `(leveldb-default-write-options)` - Cached default write options

### Database Management
- `(leveldb-compact-range db start-key end-key)` - Trigger compaction (#f for full range)
- `(leveldb-destroy-db name [opts])` - Delete a database
- `(leveldb-repair-db name [opts])` - Repair a corrupted database
- `(leveldb-property db name)` - Query database properties (e.g. "leveldb.stats")
- `(leveldb-approximate-size db start-key end-key)` - Estimate data size in a range

### Version & Environment
- `(leveldb-version)` - Returns (values major minor)
- `(leveldb-default-env)` - Get the default LevelDB environment

### Predicates
- `(leveldb? x)` - Test if x is a database handle
- `(leveldb-error? x)` - Test if x is a LevelDB error condition

## Environment Variables

- `CHEZ_LEVELDB_SHIM` - Override the path to `leveldb_shim.so` (default: `./leveldb_shim.so`)

## License

BSD-style, same as LevelDB.
# chez-leveldb

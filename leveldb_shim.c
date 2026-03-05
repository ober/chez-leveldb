/* leveldb_shim.c — C shim for Chez Scheme LevelDB FFI
 *
 * LevelDB's C API uses (pointer, length) pairs for keys and values.
 * Chez Scheme's FFI passes bytevectors as u8*, but cannot pass the
 * length separately in the same call without an extra parameter.
 * This shim provides wrapper functions that accept a pointer and
 * explicit length, plus helper functions for error handling and
 * slice management.
 */

#include <leveldb/c.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Slice type for returning variable-length data */
typedef struct {
    char*  data;
    size_t len;
    int    own;  /* 1 = caller must free data, 0 = borrowed */
} ldb_slice_t;

/* --- Error pointer management --- */

char** ldb_make_errptr(void) {
    char** p = (char**)malloc(sizeof(char*));
    if (p) *p = NULL;
    return p;
}

void ldb_errptr_clear(char** errptr) {
    if (errptr && *errptr) {
        leveldb_free(*errptr);
        *errptr = NULL;
    }
}

void ldb_errptr_free(char** errptr) {
    if (errptr) {
        ldb_errptr_clear(errptr);
        free(errptr);
    }
}

/* Returns the error string or NULL */
const char* ldb_errptr_message(char** errptr) {
    return errptr ? *errptr : NULL;
}

/* --- Slice management --- */

ldb_slice_t* ldb_slice_create(char* data, size_t len, int own) {
    ldb_slice_t* s = (ldb_slice_t*)malloc(sizeof(ldb_slice_t));
    if (!s) {
        if (own && data) free(data);
        return NULL;
    }
    s->data = data;
    s->len  = len;
    s->own  = own;
    return s;
}

void ldb_slice_free(ldb_slice_t* s) {
    if (s) {
        if (s->own && s->data) free(s->data);
        free(s);
    }
}

size_t ldb_slice_length(ldb_slice_t* s) {
    return s ? s->len : 0;
}

/* Copy slice data into a pre-allocated buffer */
void ldb_slice_copy(ldb_slice_t* s, char* buf, size_t buflen) {
    if (s && buf) {
        size_t n = s->len < buflen ? s->len : buflen;
        memcpy(buf, s->data, n);
    }
}

/* --- Core operations with explicit lengths --- */

void ldb_put(leveldb_t* db, const leveldb_writeoptions_t* opts,
             const char* key, size_t keylen,
             const char* val, size_t vallen,
             char** errptr) {
    leveldb_put(db, opts, key, keylen, val, vallen, errptr);
}

ldb_slice_t* ldb_get(leveldb_t* db, const leveldb_readoptions_t* opts,
                     const char* key, size_t keylen,
                     char** errptr) {
    size_t vallen = 0;
    char* val = leveldb_get(db, opts, key, keylen, &vallen, errptr);
    if (!val) return NULL;
    return ldb_slice_create(val, vallen, 1);
}

void ldb_delete(leveldb_t* db, const leveldb_writeoptions_t* opts,
                const char* key, size_t keylen,
                char** errptr) {
    leveldb_delete(db, opts, key, keylen, errptr);
}

/* --- Write batch with explicit lengths --- */

void ldb_writebatch_put(leveldb_writebatch_t* batch,
                        const char* key, size_t keylen,
                        const char* val, size_t vallen) {
    leveldb_writebatch_put(batch, key, keylen, val, vallen);
}

void ldb_writebatch_delete(leveldb_writebatch_t* batch,
                           const char* key, size_t keylen) {
    leveldb_writebatch_delete(batch, key, keylen);
}

/* --- Iterator with explicit lengths --- */

void ldb_iter_seek(leveldb_iterator_t* iter,
                   const char* key, size_t keylen) {
    leveldb_iter_seek(iter, key, keylen);
}

ldb_slice_t* ldb_iter_key(leveldb_iterator_t* iter) {
    size_t len = 0;
    const char* data = leveldb_iter_key(iter, &len);
    if (!data) return NULL;
    return ldb_slice_create((char*)data, len, 0);  /* borrowed */
}

ldb_slice_t* ldb_iter_value(leveldb_iterator_t* iter) {
    size_t len = 0;
    const char* data = leveldb_iter_value(iter, &len);
    if (!data) return NULL;
    return ldb_slice_create((char*)data, len, 0);  /* borrowed */
}

/* --- Compact range with explicit lengths --- */

void ldb_compact_range(leveldb_t* db,
                       const char* start, size_t start_len,
                       const char* limit, size_t limit_len) {
    leveldb_compact_range(db, start, start_len, limit, limit_len);
}

/* Full compaction (NULL boundaries) */
void ldb_compact_range_all(leveldb_t* db) {
    leveldb_compact_range(db, NULL, 0, NULL, 0);
}

/* --- Approximate sizes for a single range --- */

uint64_t ldb_approximate_size(leveldb_t* db,
                              const char* start, size_t start_len,
                              const char* limit, size_t limit_len) {
    const char* start_keys[1] = { start };
    size_t start_lens[1] = { start_len };
    const char* limit_keys[1] = { limit };
    size_t limit_lens[1] = { limit_len };
    uint64_t sizes[1] = { 0 };
    leveldb_approximate_sizes(db, 1, start_keys, start_lens,
                              limit_keys, limit_lens, sizes);
    return sizes[0];
}

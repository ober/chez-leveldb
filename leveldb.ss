;;; leveldb.ss — LevelDB bindings for Chez Scheme
;;;
;;; Provides a complete wrapper around the LevelDB C API via a small
;;; C shim (leveldb_shim.so) that handles pointer+length conversions.

(library (leveldb)
  (export
    ;; Core
    leveldb-open leveldb-close
    leveldb-put leveldb-get leveldb-delete leveldb-key?
    leveldb-write

    ;; Write batches
    leveldb-writebatch leveldb-writebatch-put leveldb-writebatch-delete
    leveldb-writebatch-clear leveldb-writebatch-append leveldb-writebatch-destroy

    ;; Iterators
    leveldb-iterator leveldb-iterator-close leveldb-iterator-valid?
    leveldb-iterator-seek-first leveldb-iterator-seek-last leveldb-iterator-seek
    leveldb-iterator-next leveldb-iterator-prev
    leveldb-iterator-key leveldb-iterator-value
    leveldb-iterator-error

    ;; Iteration helpers
    leveldb-fold leveldb-for-each
    leveldb-fold-keys leveldb-for-each-keys

    ;; Snapshots
    leveldb-snapshot leveldb-snapshot-release

    ;; Options
    leveldb-options leveldb-default-options
    leveldb-read-options leveldb-default-read-options
    leveldb-write-options leveldb-default-write-options

    ;; Database management
    leveldb-compact-range leveldb-destroy-db leveldb-repair-db
    leveldb-property leveldb-approximate-size

    ;; Environment & version
    leveldb-version leveldb-default-env leveldb-env-test-directory

    ;; Predicates
    leveldb? leveldb-error?)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; Load shared libraries
  ;; -----------------------------------------------------------------------

  (define shim-path
    (or (getenv "CHEZ_LEVELDB_SHIM")
        "./leveldb_shim.so"))

  (define loaded-shim (load-shared-object shim-path))
  (define loaded-leveldb (load-shared-object "libleveldb.so"))

  ;; -----------------------------------------------------------------------
  ;; Low-level foreign procedures — LevelDB C API (direct)
  ;; -----------------------------------------------------------------------

  ;; DB lifecycle
  (define %leveldb-open
    (foreign-procedure "leveldb_open" (void* string void*) void*))
  (define %leveldb-close
    (foreign-procedure "leveldb_close" (void*) void))

  ;; Batch write
  (define %leveldb-write
    (foreign-procedure "leveldb_write" (void* void* void* void*) void))

  ;; Write batch management
  (define %writebatch-create
    (foreign-procedure "leveldb_writebatch_create" () void*))
  (define %writebatch-destroy
    (foreign-procedure "leveldb_writebatch_destroy" (void*) void))
  (define %writebatch-clear
    (foreign-procedure "leveldb_writebatch_clear" (void*) void))
  (define %writebatch-append
    (foreign-procedure "leveldb_writebatch_append" (void* void*) void))

  ;; Iterator management
  (define %create-iterator
    (foreign-procedure "leveldb_create_iterator" (void* void*) void*))
  (define %iter-destroy
    (foreign-procedure "leveldb_iter_destroy" (void*) void))
  (define %iter-valid
    (foreign-procedure "leveldb_iter_valid" (void*) unsigned-8))
  (define %iter-seek-to-first
    (foreign-procedure "leveldb_iter_seek_to_first" (void*) void))
  (define %iter-seek-to-last
    (foreign-procedure "leveldb_iter_seek_to_last" (void*) void))
  (define %iter-next
    (foreign-procedure "leveldb_iter_next" (void*) void))
  (define %iter-prev
    (foreign-procedure "leveldb_iter_prev" (void*) void))
  (define %iter-get-error
    (foreign-procedure "leveldb_iter_get_error" (void* void*) void))

  ;; Options
  (define %options-create
    (foreign-procedure "leveldb_options_create" () void*))
  (define %options-destroy
    (foreign-procedure "leveldb_options_destroy" (void*) void))
  (define %options-set-create-if-missing
    (foreign-procedure "leveldb_options_set_create_if_missing" (void* unsigned-8) void))
  (define %options-set-error-if-exists
    (foreign-procedure "leveldb_options_set_error_if_exists" (void* unsigned-8) void))
  (define %options-set-paranoid-checks
    (foreign-procedure "leveldb_options_set_paranoid_checks" (void* unsigned-8) void))
  (define %options-set-compression
    (foreign-procedure "leveldb_options_set_compression" (void* int) void))
  (define %options-set-write-buffer-size
    (foreign-procedure "leveldb_options_set_write_buffer_size" (void* size_t) void))
  (define %options-set-max-open-files
    (foreign-procedure "leveldb_options_set_max_open_files" (void* int) void))
  (define %options-set-block-size
    (foreign-procedure "leveldb_options_set_block_size" (void* size_t) void))
  (define %options-set-block-restart-interval
    (foreign-procedure "leveldb_options_set_block_restart_interval" (void* int) void))
  (define %options-set-max-file-size
    (foreign-procedure "leveldb_options_set_max_file_size" (void* size_t) void))
  (define %options-set-cache
    (foreign-procedure "leveldb_options_set_cache" (void* void*) void))
  (define %options-set-filter-policy
    (foreign-procedure "leveldb_options_set_filter_policy" (void* void*) void))
  (define %options-set-env
    (foreign-procedure "leveldb_options_set_env" (void* void*) void))

  ;; Cache & filter
  (define %cache-create-lru
    (foreign-procedure "leveldb_cache_create_lru" (size_t) void*))
  (define %cache-destroy
    (foreign-procedure "leveldb_cache_destroy" (void*) void))
  (define %bloom-create
    (foreign-procedure "leveldb_filterpolicy_create_bloom" (int) void*))
  (define %filterpolicy-destroy
    (foreign-procedure "leveldb_filterpolicy_destroy" (void*) void))

  ;; Read options
  (define %readoptions-create
    (foreign-procedure "leveldb_readoptions_create" () void*))
  (define %readoptions-destroy
    (foreign-procedure "leveldb_readoptions_destroy" (void*) void))
  (define %readoptions-set-verify-checksums
    (foreign-procedure "leveldb_readoptions_set_verify_checksums" (void* unsigned-8) void))
  (define %readoptions-set-fill-cache
    (foreign-procedure "leveldb_readoptions_set_fill_cache" (void* unsigned-8) void))
  (define %readoptions-set-snapshot
    (foreign-procedure "leveldb_readoptions_set_snapshot" (void* void*) void))

  ;; Write options
  (define %writeoptions-create
    (foreign-procedure "leveldb_writeoptions_create" () void*))
  (define %writeoptions-destroy
    (foreign-procedure "leveldb_writeoptions_destroy" (void*) void))
  (define %writeoptions-set-sync
    (foreign-procedure "leveldb_writeoptions_set_sync" (void* unsigned-8) void))

  ;; Snapshots
  (define %create-snapshot
    (foreign-procedure "leveldb_create_snapshot" (void*) void*))
  (define %release-snapshot
    (foreign-procedure "leveldb_release_snapshot" (void* void*) void))

  ;; Property & management
  (define %property-value
    (foreign-procedure "leveldb_property_value" (void* string) void*))
  (define %destroy-db
    (foreign-procedure "leveldb_destroy_db" (void* string void*) void))
  (define %repair-db
    (foreign-procedure "leveldb_repair_db" (void* string void*) void))
  (define %leveldb-free
    (foreign-procedure "leveldb_free" (void*) void))

  ;; Version
  (define %major-version
    (foreign-procedure "leveldb_major_version" () int))
  (define %minor-version
    (foreign-procedure "leveldb_minor_version" () int))

  ;; Environment
  (define %create-default-env
    (foreign-procedure "leveldb_create_default_env" () void*))
  (define %env-destroy
    (foreign-procedure "leveldb_env_destroy" (void*) void))
  (define %env-get-test-directory
    (foreign-procedure "leveldb_env_get_test_directory" (void*) void*))

  ;; -----------------------------------------------------------------------
  ;; Low-level foreign procedures — Shim functions
  ;; -----------------------------------------------------------------------

  ;; Error pointer
  (define %make-errptr
    (foreign-procedure "ldb_make_errptr" () void*))
  (define %errptr-clear
    (foreign-procedure "ldb_errptr_clear" (void*) void))
  (define %errptr-free
    (foreign-procedure "ldb_errptr_free" (void*) void))
  (define %errptr-message
    (foreign-procedure "ldb_errptr_message" (void*) string))

  ;; Slice
  (define %slice-free
    (foreign-procedure "ldb_slice_free" (void*) void))
  (define %slice-length
    (foreign-procedure "ldb_slice_length" (void*) size_t))
  (define %slice-copy
    (foreign-procedure "ldb_slice_copy" (void* u8* size_t) void))

  ;; Core with lengths
  (define %ldb-put
    (foreign-procedure "ldb_put" (void* void* u8* size_t u8* size_t void*) void))
  (define %ldb-get
    (foreign-procedure "ldb_get" (void* void* u8* size_t void*) void*))
  (define %ldb-delete
    (foreign-procedure "ldb_delete" (void* void* u8* size_t void*) void))

  ;; Batch with lengths
  (define %ldb-writebatch-put
    (foreign-procedure "ldb_writebatch_put" (void* u8* size_t u8* size_t) void))
  (define %ldb-writebatch-delete
    (foreign-procedure "ldb_writebatch_delete" (void* u8* size_t) void))

  ;; Iterator with lengths
  (define %ldb-iter-seek
    (foreign-procedure "ldb_iter_seek" (void* u8* size_t) void))
  (define %ldb-iter-key
    (foreign-procedure "ldb_iter_key" (void*) void*))
  (define %ldb-iter-value
    (foreign-procedure "ldb_iter_value" (void*) void*))

  ;; Compact & approximate
  (define %ldb-compact-range
    (foreign-procedure "ldb_compact_range" (void* u8* size_t u8* size_t) void))
  (define %ldb-compact-range-all
    (foreign-procedure "ldb_compact_range_all" (void*) void))
  (define %ldb-approximate-size
    (foreign-procedure "ldb_approximate_size" (void* u8* size_t u8* size_t) unsigned-64))

  ;; -----------------------------------------------------------------------
  ;; Conditions
  ;; -----------------------------------------------------------------------

  (define-condition-type &leveldb-error &error
    make-leveldb-error leveldb-error?
    (who leveldb-error-who)
    (msg leveldb-error-msg))

  (define (raise-leveldb-error who msg)
    (raise (condition
            (make-leveldb-error who msg)
            (make-message-condition msg))))

  ;; -----------------------------------------------------------------------
  ;; Helpers
  ;; -----------------------------------------------------------------------

  (define (value->bytevector v)
    (cond
      [(bytevector? v) v]
      [(string? v) (string->utf8 v)]
      [else (error 'leveldb "expected bytevector or string" v)]))

  (define (check-null who ptr)
    (when (zero? ptr)
      (error who "unexpected NULL pointer"))
    ptr)

  ;; Thread-local error pointer (avoids malloc/free per operation)
  ;; Use a parameter since Chez doesn't have thread-local-get/set
  (define current-errptr (make-parameter #f))

  (define (get-errptr)
    (let ([ep (current-errptr)])
      (if ep
          (begin (%errptr-clear ep) ep)
          (let ([ep (%make-errptr)])
            (current-errptr ep)
            ep))))

  (define (check-errptr who errptr)
    (let ([msg (%errptr-message errptr)])
      (when msg
        (let ([s (string-copy msg)])  ;; copy before clear
          (%errptr-clear errptr)
          (raise-leveldb-error who s)))))

  ;; Slice -> bytevector, then free the slice
  (define (slice->bytevector slice)
    (if (zero? slice)
        #f
        (let* ([len (%slice-length slice)]
               [bv (make-bytevector len)])
          (%slice-copy slice bv len)
          (%slice-free slice)
          bv)))

  ;; Bytevector lexicographic >=
  (define (bytevector>=? a b)
    (let ([alen (bytevector-length a)]
          [blen (bytevector-length b)])
      (let loop ([i 0])
        (cond
          [(and (= i alen) (= i blen)) #t]
          [(= i alen) #f]
          [(= i blen) #t]
          [(> (bytevector-u8-ref a i) (bytevector-u8-ref b i)) #t]
          [(< (bytevector-u8-ref a i) (bytevector-u8-ref b i)) #f]
          [else (loop (+ i 1))]))))

  ;; -----------------------------------------------------------------------
  ;; Record types
  ;; -----------------------------------------------------------------------

  (define-record-type ldb
    (fields (mutable ptr) opts)
    (nongenerative leveldb-db-type))

  (define (leveldb? x) (ldb? x))

  (define-record-type ldb-iterator
    (fields (mutable ptr))
    (nongenerative leveldb-iterator-type))

  (define-record-type ldb-snapshot
    (fields db (mutable ptr))
    (nongenerative leveldb-snapshot-type))

  ;; -----------------------------------------------------------------------
  ;; Options
  ;; -----------------------------------------------------------------------

  ;; Options record holds pointers to prevent premature GC of cache/filter
  (define-record-type ldb-options
    (fields ptr cache-ptr filter-ptr)
    (nongenerative leveldb-options-type))

  (define (leveldb-options . args)
    (define (get key default)
      (let loop ([ls args])
        (cond
          [(null? ls) default]
          [(null? (cdr ls)) (error 'leveldb-options "missing value for" key)]
          [(eq? (car ls) key) (cadr ls)]
          [else (loop (cddr ls))])))
    (let ([opts (%options-create)])
      (let ([create-if-missing (get 'create-if-missing #t)]
            [error-if-exists   (get 'error-if-exists #f)]
            [paranoid-checks   (get 'paranoid-checks #f)]
            [compression       (get 'compression #t)]
            [write-buffer-size (get 'write-buffer-size #f)]
            [max-open-files    (get 'max-open-files #f)]
            [block-size        (get 'block-size #f)]
            [block-restart-interval (get 'block-restart-interval #f)]
            [max-file-size     (get 'max-file-size #f)]
            [lru-cache-capacity (get 'lru-cache-capacity #f)]
            [bloom-filter-bits (get 'bloom-filter-bits #f)]
            [env               (get 'env #f)])
        (%options-set-create-if-missing opts (if create-if-missing 1 0))
        (when error-if-exists (%options-set-error-if-exists opts 1))
        (when paranoid-checks (%options-set-paranoid-checks opts 1))
        (%options-set-compression opts (if compression 1 0))
        (when write-buffer-size (%options-set-write-buffer-size opts write-buffer-size))
        (when max-open-files (%options-set-max-open-files opts max-open-files))
        (when block-size (%options-set-block-size opts block-size))
        (when block-restart-interval (%options-set-block-restart-interval opts block-restart-interval))
        (when max-file-size (%options-set-max-file-size opts max-file-size))
        (when env (%options-set-env opts env))
        (let ([cache-ptr
               (and lru-cache-capacity
                    (let ([c (%cache-create-lru lru-cache-capacity)])
                      (%options-set-cache opts c)
                      c))]
              [filter-ptr
               (and bloom-filter-bits
                    (let ([f (%bloom-create bloom-filter-bits)])
                      (%options-set-filter-policy opts f)
                      f))])
          (make-ldb-options opts cache-ptr filter-ptr)))))

  (define default-options-cache #f)
  (define (leveldb-default-options)
    (or default-options-cache
        (let ([o (leveldb-options)])
          (set! default-options-cache o)
          o)))

  (define (leveldb-read-options . args)
    (define (get key default)
      (let loop ([ls args])
        (cond
          [(null? ls) default]
          [(null? (cdr ls)) (error 'leveldb-read-options "missing value for" key)]
          [(eq? (car ls) key) (cadr ls)]
          [else (loop (cddr ls))])))
    (let ([opts (%readoptions-create)])
      (let ([verify (get 'verify-checksums #f)]
            [fill   (get 'fill-cache #f)]
            [snap   (get 'snapshot #f)])
        (when verify (%readoptions-set-verify-checksums opts 1))
        (when fill (%readoptions-set-fill-cache opts 1))
        (when snap
          (%readoptions-set-snapshot opts
            (if (ldb-snapshot? snap) (ldb-snapshot-ptr snap) snap)))
        opts)))

  (define default-read-options-cache #f)
  (define (leveldb-default-read-options)
    (or default-read-options-cache
        (let ([o (leveldb-read-options)])
          (set! default-read-options-cache o)
          o)))

  (define (leveldb-write-options . args)
    (define (get key default)
      (let loop ([ls args])
        (cond
          [(null? ls) default]
          [(null? (cdr ls)) (error 'leveldb-write-options "missing value for" key)]
          [(eq? (car ls) key) (cadr ls)]
          [else (loop (cddr ls))])))
    (let ([opts (%writeoptions-create)])
      (when (get 'sync #f)
        (%writeoptions-set-sync opts 1))
      opts))

  (define default-write-options-cache #f)
  (define (leveldb-default-write-options)
    (or default-write-options-cache
        (let ([o (leveldb-write-options)])
          (set! default-write-options-cache o)
          o)))

  ;; Helper to extract the raw options pointer
  (define (opts-ptr opts)
    (if (ldb-options? opts)
        (ldb-options-ptr opts)
        opts))

  ;; -----------------------------------------------------------------------
  ;; Core API
  ;; -----------------------------------------------------------------------

  ;; Guardian for GC-triggered cleanup of unclosed databases
  (define db-guardian (make-guardian))

  (define (drain-db-guardian)
    (let ([db (db-guardian)])
      (when db
        (when (ldb-ptr db)
          (leveldb-close db))
        (drain-db-guardian))))

  (define leveldb-open
    (case-lambda
      [(name) (leveldb-open name (leveldb-default-options))]
      [(name opts)
       (let* ([errptr (get-errptr)]
              [ptr (%leveldb-open (opts-ptr opts) name errptr)])
         (if (zero? ptr)
             (check-errptr 'leveldb-open errptr)
             (let ([db (make-ldb ptr opts)])
               (db-guardian db)
               db)))]))

  (define (leveldb-close db)
    (let ([ptr (ldb-ptr db)])
      (when ptr
        (%leveldb-close ptr)
        (ldb-ptr-set! db #f))))

  (define (check-open who db)
    (or (ldb-ptr db)
        (error who "database has been closed")))

  (define leveldb-put
    (case-lambda
      [(db key val) (leveldb-put db key val (leveldb-default-write-options))]
      [(db key val opts)
       (let ([ptr (check-open 'leveldb-put db)]
             [k (value->bytevector key)]
             [v (value->bytevector val)]
             [errptr (get-errptr)])
         (%ldb-put ptr opts k (bytevector-length k) v (bytevector-length v) errptr)
         (check-errptr 'leveldb-put errptr))]))

  (define leveldb-get
    (case-lambda
      [(db key) (leveldb-get db key (leveldb-default-read-options))]
      [(db key opts)
       (let ([ptr (check-open 'leveldb-get db)]
             [k (value->bytevector key)]
             [errptr (get-errptr)])
         (let ([slice (%ldb-get ptr opts k (bytevector-length k) errptr)])
           (cond
             [(not (zero? slice)) (slice->bytevector slice)]
             [else
              (check-errptr 'leveldb-get errptr)
              #f])))]))

  (define leveldb-delete
    (case-lambda
      [(db key) (leveldb-delete db key (leveldb-default-write-options))]
      [(db key opts)
       (let ([ptr (check-open 'leveldb-delete db)]
             [k (value->bytevector key)]
             [errptr (get-errptr)])
         (%ldb-delete ptr opts k (bytevector-length k) errptr)
         (check-errptr 'leveldb-delete errptr))]))

  (define leveldb-key?
    (case-lambda
      [(db key) (leveldb-key? db key (leveldb-default-read-options))]
      [(db key opts)
       (let ([ptr (check-open 'leveldb-key? db)]
             [k (value->bytevector key)]
             [errptr (get-errptr)])
         (let ([slice (%ldb-get ptr opts k (bytevector-length k) errptr)])
           (cond
             [(not (zero? slice))
              (%slice-free slice)
              #t]
             [else
              (check-errptr 'leveldb-key? errptr)
              #f])))]))

  (define leveldb-write
    (case-lambda
      [(db batch) (leveldb-write db batch (leveldb-default-write-options))]
      [(db batch opts)
       (let ([ptr (check-open 'leveldb-write db)]
             [errptr (get-errptr)])
         (%leveldb-write ptr opts batch errptr)
         (check-errptr 'leveldb-write errptr))]))

  ;; -----------------------------------------------------------------------
  ;; Write batches
  ;; -----------------------------------------------------------------------

  (define (leveldb-writebatch)
    (check-null 'leveldb-writebatch (%writebatch-create)))

  (define (leveldb-writebatch-put batch key val)
    (let ([k (value->bytevector key)]
          [v (value->bytevector val)])
      (%ldb-writebatch-put batch k (bytevector-length k) v (bytevector-length v))))

  (define (leveldb-writebatch-delete batch key)
    (let ([k (value->bytevector key)])
      (%ldb-writebatch-delete batch k (bytevector-length k))))

  (define (leveldb-writebatch-clear batch)
    (%writebatch-clear batch))

  (define (leveldb-writebatch-append dest src)
    (%writebatch-append dest src))

  (define (leveldb-writebatch-destroy batch)
    (%writebatch-destroy batch))

  ;; -----------------------------------------------------------------------
  ;; Iterators
  ;; -----------------------------------------------------------------------

  (define leveldb-iterator
    (case-lambda
      [(db) (leveldb-iterator db (leveldb-default-read-options))]
      [(db opts)
       (let ([ptr (check-open 'leveldb-iterator db)])
         (make-ldb-iterator
           (check-null 'leveldb-iterator (%create-iterator ptr opts))))]))

  (define (leveldb-iterator-close iter)
    (let ([ptr (ldb-iterator-ptr iter)])
      (when ptr
        (%iter-destroy ptr)
        (ldb-iterator-ptr-set! iter #f))))

  (define (check-iter who iter)
    (or (ldb-iterator-ptr iter)
        (error who "iterator has been closed")))

  (define (leveldb-iterator-valid? iter)
    (not (zero? (%iter-valid (check-iter 'leveldb-iterator-valid? iter)))))

  (define (leveldb-iterator-seek-first iter)
    (%iter-seek-to-first (check-iter 'leveldb-iterator-seek-first iter)))

  (define (leveldb-iterator-seek-last iter)
    (%iter-seek-to-last (check-iter 'leveldb-iterator-seek-last iter)))

  (define (leveldb-iterator-seek iter key)
    (let ([ptr (check-iter 'leveldb-iterator-seek iter)]
          [k (value->bytevector key)])
      (%ldb-iter-seek ptr k (bytevector-length k))))

  (define (leveldb-iterator-next iter)
    (%iter-next (check-iter 'leveldb-iterator-next iter)))

  (define (leveldb-iterator-prev iter)
    (%iter-prev (check-iter 'leveldb-iterator-prev iter)))

  (define (leveldb-iterator-key iter)
    (let ([slice (%ldb-iter-key (check-iter 'leveldb-iterator-key iter))])
      (slice->bytevector slice)))

  (define (leveldb-iterator-value iter)
    (let ([slice (%ldb-iter-value (check-iter 'leveldb-iterator-value iter))])
      (slice->bytevector slice)))

  (define leveldb-iterator-error
    (case-lambda
      [(iter) (leveldb-iterator-error iter #t)]
      [(iter raise?)
       (let ([ptr (check-iter 'leveldb-iterator-error iter)]
             [errptr (get-errptr)])
         (%iter-get-error ptr errptr)
         (let ([msg (%errptr-message errptr)])
           (cond
             [(not msg) #f]
             [raise?
              (let ([s (string-copy msg)])
                (%errptr-clear errptr)
                (raise-leveldb-error 'leveldb-iterator-error s))]
             [else
              (let ([s (string-copy msg)])
                (%errptr-clear errptr)
                s)])))]))

  ;; -----------------------------------------------------------------------
  ;; Iteration helpers (fold/for-each over key ranges)
  ;; -----------------------------------------------------------------------

  (define leveldb-fold
    (case-lambda
      [(db proc init) (leveldb-fold db proc init #f #f)]
      [(db proc init start) (leveldb-fold db proc init start #f)]
      [(db proc init start limit)
       (leveldb-fold db proc init start limit (leveldb-default-read-options))]
      [(db proc init start limit opts)
       (let ([iter (leveldb-iterator db opts)]
             [start-bv (and start (value->bytevector start))]
             [limit-bv (and limit (value->bytevector limit))])
         (dynamic-wind
           (lambda ()
             (if start-bv
                 (leveldb-iterator-seek iter start-bv)
                 (leveldb-iterator-seek-first iter)))
           (lambda ()
             (if (and start-bv limit-bv (bytevector>=? start-bv limit-bv))
                 init
                 (let loop ([acc init])
                   (if (not (leveldb-iterator-valid? iter))
                       acc
                       (let ([key (leveldb-iterator-key iter)])
                         (if (and limit-bv key (bytevector>=? key limit-bv))
                             acc
                             (let ([val (leveldb-iterator-value iter)])
                               (leveldb-iterator-next iter)
                               (loop (proc key val acc)))))))))
           (lambda () (leveldb-iterator-close iter))))]))

  (define leveldb-for-each
    (case-lambda
      [(db proc) (leveldb-for-each db proc #f #f)]
      [(db proc start) (leveldb-for-each db proc start #f)]
      [(db proc start limit)
       (leveldb-for-each db proc start limit (leveldb-default-read-options))]
      [(db proc start limit opts)
       (leveldb-fold db (lambda (k v _) (proc k v)) (void) start limit opts)]))

  (define leveldb-fold-keys
    (case-lambda
      [(db proc init) (leveldb-fold-keys db proc init #f #f)]
      [(db proc init start) (leveldb-fold-keys db proc init start #f)]
      [(db proc init start limit)
       (leveldb-fold-keys db proc init start limit (leveldb-default-read-options))]
      [(db proc init start limit opts)
       (let ([iter (leveldb-iterator db opts)]
             [start-bv (and start (value->bytevector start))]
             [limit-bv (and limit (value->bytevector limit))])
         (dynamic-wind
           (lambda ()
             (if start-bv
                 (leveldb-iterator-seek iter start-bv)
                 (leveldb-iterator-seek-first iter)))
           (lambda ()
             (if (and start-bv limit-bv (bytevector>=? start-bv limit-bv))
                 init
                 (let loop ([acc init])
                   (if (not (leveldb-iterator-valid? iter))
                       acc
                       (let ([key (leveldb-iterator-key iter)])
                         (if (and limit-bv key (bytevector>=? key limit-bv))
                             acc
                             (begin
                               (leveldb-iterator-next iter)
                               (loop (proc key acc)))))))))
           (lambda () (leveldb-iterator-close iter))))]))

  (define leveldb-for-each-keys
    (case-lambda
      [(db proc) (leveldb-for-each-keys db proc #f #f)]
      [(db proc start) (leveldb-for-each-keys db proc start #f)]
      [(db proc start limit)
       (leveldb-for-each-keys db proc start limit (leveldb-default-read-options))]
      [(db proc start limit opts)
       (leveldb-fold-keys db (lambda (k _) (proc k)) (void) start limit opts)]))

  ;; -----------------------------------------------------------------------
  ;; Snapshots
  ;; -----------------------------------------------------------------------

  (define (leveldb-snapshot db)
    (let ([ptr (check-open 'leveldb-snapshot db)])
      (make-ldb-snapshot db (check-null 'leveldb-snapshot (%create-snapshot ptr)))))

  (define (leveldb-snapshot-release db snapshot)
    (cond
      [(ldb-snapshot? snapshot)
       (let ([snap-ptr (ldb-snapshot-ptr snapshot)]
             [db-ptr (check-open 'leveldb-snapshot-release db)])
         (when snap-ptr
           (%release-snapshot db-ptr snap-ptr)
           (ldb-snapshot-ptr-set! snapshot #f)))]
      [else
       (let ([db-ptr (check-open 'leveldb-snapshot-release db)])
         (%release-snapshot db-ptr snapshot))]))

  ;; -----------------------------------------------------------------------
  ;; Database management
  ;; -----------------------------------------------------------------------

  (define leveldb-compact-range
    (case-lambda
      [(db start-key end-key)
       (let ([ptr (check-open 'leveldb-compact-range db)])
         (cond
           [(and (not start-key) (not end-key))
            (%ldb-compact-range-all ptr)]
           [else
            (let ([s (if start-key (value->bytevector start-key) (make-bytevector 0))]
                  [e (if end-key (value->bytevector end-key) (make-bytevector 0))])
              (%ldb-compact-range ptr s (bytevector-length s) e (bytevector-length e)))]))]))

  (define leveldb-destroy-db
    (case-lambda
      [(name) (leveldb-destroy-db name (leveldb-default-options))]
      [(name opts)
       (let ([errptr (get-errptr)])
         (%destroy-db (opts-ptr opts) name errptr)
         (check-errptr 'leveldb-destroy-db errptr))]))

  (define leveldb-repair-db
    (case-lambda
      [(name) (leveldb-repair-db name (leveldb-default-options))]
      [(name opts)
       (let ([errptr (get-errptr)])
         (%repair-db (opts-ptr opts) name errptr)
         (check-errptr 'leveldb-repair-db errptr))]))

  ;; Read a NUL-terminated C string from a pointer
  (define (cstring->string ptr)
    (let loop ([i 0])
      (if (zero? (foreign-ref 'unsigned-8 ptr i))
          (let ([bv (make-bytevector i)])
            (let fill ([j 0])
              (when (< j i)
                (bytevector-u8-set! bv j (foreign-ref 'unsigned-8 ptr j))
                (fill (+ j 1))))
            (utf8->string bv))
          (loop (+ i 1)))))

  (define (leveldb-property db name)
    (let ([ptr (check-open 'leveldb-property db)])
      (let ([cstr (%property-value ptr name)])
        (if (zero? cstr)
            #f
            (let ([s (cstring->string cstr)])
              (%leveldb-free cstr)
              s)))))

  (define (leveldb-approximate-size db start-key end-key)
    (let ([ptr (check-open 'leveldb-approximate-size db)]
          [s (value->bytevector start-key)]
          [e (value->bytevector end-key)])
      (%ldb-approximate-size ptr s (bytevector-length s) e (bytevector-length e))))

  ;; -----------------------------------------------------------------------
  ;; Version & environment
  ;; -----------------------------------------------------------------------

  (define (leveldb-version)
    (values (%major-version) (%minor-version)))

  (define default-env-cache #f)
  (define (leveldb-default-env)
    (or default-env-cache
        (let ([e (check-null 'leveldb-default-env (%create-default-env))])
          (set! default-env-cache e)
          e)))

  (define (leveldb-env-test-directory env)
    (let ([cstr (%env-get-test-directory env)])
      (if (zero? cstr)
          #f
          (let ([s (cstring->string cstr)])
            (%leveldb-free cstr)
            s))))

)

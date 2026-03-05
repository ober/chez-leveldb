;;; leveldb-test.ss — Tests for Chez Scheme LevelDB bindings
;;;
;;; Run: scheme --script leveldb-test.ss
;;; Or:  make test

(import (leveldb))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define (check name expr expected)
  (set! test-count (+ test-count 1))
  (let ([result (guard (e [#t (list 'exception e)])
                  expr)])
    (if (equal? result expected)
        (begin
          (set! pass-count (+ pass-count 1))
          (printf "  PASS: ~a~%" name))
        (begin
          (set! fail-count (+ fail-count 1))
          (printf "  FAIL: ~a~%    expected: ~s~%    got:      ~s~%" name expected result)))))

(define (check-true name expr)
  (check name expr #t))

(define (check-false name expr)
  (check name expr #f))

(define (check-exception name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (begin (set! pass-count (+ pass-count 1))
                       (printf "  PASS: ~a (raised)~%" name))])
    (thunk)
    (set! fail-count (+ fail-count 1))
    (printf "  FAIL: ~a (no exception raised)~%" name)))

(define (bv->string bv)
  (utf8->string bv))

(define test-dir #f)

(define (make-temp-db-path suffix)
  (string-append "/tmp/chez-leveldb-test-" suffix "-"
                 (number->string (random 1000000))))

;; -----------------------------------------------------------------------
;; Tests
;; -----------------------------------------------------------------------

(printf "~%=== Chez LevelDB Test Suite ===~%~%")

;; --- Version ---
(printf "Test: version~%")
(call-with-values leveldb-version
  (lambda (major minor)
    (check-true "major version >= 1" (>= major 1))
    (check-true "minor version is integer" (integer? minor))))

;; --- Options ---
(printf "~%Test: options~%")
(check-true "default-options" (not (not (leveldb-default-options))))
(check-true "default-options cached"
  (eq? (leveldb-default-options) (leveldb-default-options)))
(check-true "default-read-options" (not (not (leveldb-default-read-options))))
(check-true "default-read-options cached"
  (eq? (leveldb-default-read-options) (leveldb-default-read-options)))
(check-true "default-write-options" (not (not (leveldb-default-write-options))))
(check-true "default-write-options cached"
  (eq? (leveldb-default-write-options) (leveldb-default-write-options)))

;; Custom options
(let ([opts (leveldb-options 'max-file-size 4194304)])
  (check-true "custom options" (not (not opts))))

;; Write options with sync
(let ([wo (leveldb-write-options 'sync #t)])
  (check-true "write-options sync" (not (not wo))))

;; --- Open / Close / Predicates ---
(printf "~%Test: open/close/predicates~%")
(set! test-dir (make-temp-db-path "basic"))
(define db (leveldb-open test-dir))
(check-true "leveldb?" (leveldb? db))
(check-false "leveldb? on string" (leveldb? "nope"))
(check-false "leveldb? on #f" (leveldb? #f))

;; --- Put / Get / Delete ---
(printf "~%Test: put/get/delete~%")
(leveldb-put db "abc" "this-is-abc")
(leveldb-put db "def" "this-is-def")
(check "get abc" (bv->string (leveldb-get db "abc")) "this-is-abc")
(check "get def" (bv->string (leveldb-get db "def")) "this-is-def")
(leveldb-delete db "abc")
(check-false "get deleted abc" (leveldb-get db "abc"))
(leveldb-delete db "def")
(check-false "get deleted def" (leveldb-get db "def"))

;; --- key? ---
(printf "~%Test: key?~%")
(leveldb-put db "exists-key" "value")
(check-true "key? existing" (leveldb-key? db "exists-key"))
(check-false "key? missing" (leveldb-key? db "no-such-key"))
(leveldb-delete db "exists-key")

;; --- Write batch ---
(printf "~%Test: write batch~%")
(let ([wb (leveldb-writebatch)])
  (leveldb-writebatch-put wb "abc" "this-is-abc")
  (leveldb-writebatch-put wb "def" "this-is-def")
  (leveldb-write db wb)
  (leveldb-writebatch-destroy wb))
(check "batch get abc" (bv->string (leveldb-get db "abc")) "this-is-abc")
(check "batch get def" (bv->string (leveldb-get db "def")) "this-is-def")

;; --- Batch delete ---
(printf "~%Test: write batch delete~%")
(let ([wb (leveldb-writebatch)])
  (leveldb-writebatch-delete wb "abc")
  (leveldb-write db wb)
  (leveldb-writebatch-destroy wb))
(check-false "batch deleted abc" (leveldb-get db "abc"))
(check "def still exists" (bv->string (leveldb-get db "def")) "this-is-def")

;; --- Batch clear ---
(printf "~%Test: write batch clear~%")
(let ([wb (leveldb-writebatch)])
  (leveldb-writebatch-put wb "clear-a" "val-a")
  (leveldb-writebatch-put wb "clear-b" "val-b")
  (leveldb-writebatch-clear wb)
  (leveldb-writebatch-put wb "clear-c" "val-c")
  (leveldb-write db wb)
  (leveldb-writebatch-destroy wb))
(check-false "cleared a" (leveldb-get db "clear-a"))
(check-false "cleared b" (leveldb-get db "clear-b"))
(check "clear-c exists" (bv->string (leveldb-get db "clear-c")) "val-c")
(leveldb-delete db "clear-c")

;; --- Batch append ---
(printf "~%Test: write batch append~%")
(let ([wb1 (leveldb-writebatch)]
      [wb2 (leveldb-writebatch)])
  (leveldb-writebatch-put wb1 "batch1-key" "batch1-value")
  (leveldb-writebatch-put wb2 "batch2-key" "batch2-value")
  (leveldb-writebatch-append wb1 wb2)
  (leveldb-write db wb1)
  (leveldb-writebatch-destroy wb1)
  (leveldb-writebatch-destroy wb2))
(check "append batch1" (bv->string (leveldb-get db "batch1-key")) "batch1-value")
(check "append batch2" (bv->string (leveldb-get db "batch2-key")) "batch2-value")
(leveldb-delete db "batch1-key")
(leveldb-delete db "batch2-key")

;; --- Iterators ---
(printf "~%Test: iterators~%")
;; Use isolated prefix so other test keys don't interfere
(leveldb-put db "it-abc" "this-is-abc")
(leveldb-put db "it-def" "this-is-def")
(let ([iter (leveldb-iterator db)])
  (leveldb-iterator-seek iter "it-abc")
  (check-true "iter valid after seek" (leveldb-iterator-valid? iter))
  (check "iter first key" (bv->string (leveldb-iterator-key iter)) "it-abc")
  (check "iter first value" (bv->string (leveldb-iterator-value iter)) "this-is-abc")
  (leveldb-iterator-next iter)
  (check-true "iter valid after next" (leveldb-iterator-valid? iter))
  (check "iter second key" (bv->string (leveldb-iterator-key iter)) "it-def")
  (check "iter second value" (bv->string (leveldb-iterator-value iter)) "this-is-def")
  (leveldb-iterator-next iter)
  ;; Next key after "it-def" would be "it-e..." or later, so we check there's nothing in "it-" range
  ;; Instead just verify iteration works by checking we've moved past it-def
  (let ([valid (leveldb-iterator-valid? iter)])
    (when valid
      ;; If valid, the key should be past "it-def" (from other tests)
      (check-true "iter moved past it-def"
        (let ([k (bv->string (leveldb-iterator-key iter))])
          (string>? k "it-def")))))
  (leveldb-iterator-close iter))
(leveldb-delete db "it-abc")
(leveldb-delete db "it-def")

;; --- Iterator seek ---
(printf "~%Test: iterator seek~%")
(leveldb-put db "seek-a" "val-a")
(leveldb-put db "seek-b" "val-b")
(leveldb-put db "seek-c" "val-c")
(let ([iter (leveldb-iterator db)])
  (leveldb-iterator-seek iter "seek-b")
  (check-true "seek valid" (leveldb-iterator-valid? iter))
  (check "seek key" (bv->string (leveldb-iterator-key iter)) "seek-b")
  (leveldb-iterator-seek iter "seek-z")
  (check-false "seek past end" (leveldb-iterator-valid? iter))
  (leveldb-iterator-close iter))

;; --- Iterator seek-last / prev ---
(printf "~%Test: iterator seek-last/prev~%")
(let ([iter (leveldb-iterator db)])
  (leveldb-iterator-seek iter "seek-c")
  (check-true "seek-c valid" (leveldb-iterator-valid? iter))
  (check "seek-c key" (bv->string (leveldb-iterator-key iter)) "seek-c")
  (leveldb-iterator-prev iter)
  (check-true "prev valid" (leveldb-iterator-valid? iter))
  (check "prev key" (bv->string (leveldb-iterator-key iter)) "seek-b")
  (leveldb-iterator-prev iter)
  (check "prev-prev key" (bv->string (leveldb-iterator-key iter)) "seek-a")
  (leveldb-iterator-close iter))
(leveldb-delete db "seek-a")
(leveldb-delete db "seek-b")
(leveldb-delete db "seek-c")

;; --- Iterator error ---
(printf "~%Test: iterator error~%")
(leveldb-put db "err-key" "err-val")
(let ([iter (leveldb-iterator db)])
  (leveldb-iterator-seek-first iter)
  (check-false "no iterator error" (leveldb-iterator-error iter #f))
  (leveldb-iterator-close iter))
(leveldb-delete db "err-key")

;; --- Snapshots ---
(printf "~%Test: snapshots~%")
(leveldb-put db "snap-key" "original-value")
(let ([snap (leveldb-snapshot db)])
  (leveldb-put db "snap-key" "modified-value")
  (check "current value" (bv->string (leveldb-get db "snap-key")) "modified-value")
  (let ([snap-opts (leveldb-read-options 'snapshot snap)])
    (check "snapshot value" (bv->string (leveldb-get db "snap-key" snap-opts)) "original-value"))
  (leveldb-snapshot-release db snap))
(leveldb-delete db "snap-key")

;; --- Property ---
(printf "~%Test: property~%")
(let ([stats (leveldb-property db "leveldb.stats")])
  (check-true "stats is string" (string? stats)))
(check-false "invalid property" (leveldb-property db "invalid.property"))

;; --- Approximate size ---
(printf "~%Test: approximate size~%")
(leveldb-put db "size-a" "value-a")
(leveldb-put db "size-b" "value-b")
(let ([sz (leveldb-approximate-size db "size-" "size-~")])
  (check-true "approximate size >= 0" (>= sz 0)))
(leveldb-delete db "size-a")
(leveldb-delete db "size-b")

;; --- Compact range ---
(printf "~%Test: compact range~%")
(leveldb-put db "compact-a" "val-a")
(leveldb-put db "compact-b" "val-b")
(leveldb-compact-range db "compact-a" "compact-c")
(check "after compact" (bv->string (leveldb-get db "compact-a")) "val-a")
;; Full compaction with #f/#f
(leveldb-compact-range db #f #f)
(check "after full compact" (bv->string (leveldb-get db "compact-b")) "val-b")
(leveldb-delete db "compact-a")
(leveldb-delete db "compact-b")

;; --- fold / for-each ---
(printf "~%Test: fold/for-each~%")
(leveldb-put db "iter-a" "val-a")
(leveldb-put db "iter-b" "val-b")
(leveldb-put db "iter-c" "val-c")

(let ([pairs (leveldb-fold db
               (lambda (k v acc)
                 (cons (cons (bv->string k) (bv->string v)) acc))
               '()
               "iter-a" "iter-d")])
  (check "fold count" (length pairs) 3)
  (check "fold has iter-b" (cdr (assoc "iter-b" pairs)) "val-b"))

;; for-each
(let ([keys '()])
  (leveldb-for-each-keys db
    (lambda (k) (set! keys (cons (bv->string k) keys)))
    "iter-a" "iter-d")
  (check "for-each-keys count" (length keys) 3))

;; Inverted range returns empty
(let ([count 0])
  (leveldb-for-each db
    (lambda (k v) (set! count (+ count 1)))
    "iter-z" "iter-a")
  (check "inverted range" count 0))

;; fold-keys with limit exclusion
(let ([keys (leveldb-fold-keys db
              (lambda (k acc) (cons (bv->string k) acc))
              '()
              "iter-a" "iter-b")])
  (check "fold-keys limit exclusive" keys '("iter-a")))

(leveldb-delete db "iter-a")
(leveldb-delete db "iter-b")
(leveldb-delete db "iter-c")

;; --- Sync write ---
(printf "~%Test: sync write~%")
(let ([wo (leveldb-write-options 'sync #t)])
  (leveldb-put db "sync-test" "sync-val" wo)
  (check "sync write" (bv->string (leveldb-get db "sync-test")) "sync-val")
  (leveldb-delete db "sync-test"))

;; --- Clean up base DB ---
(leveldb-delete db "abc")
(leveldb-delete db "def")
(leveldb-close db)

;; --- Destroy / Repair ---
(printf "~%Test: destroy/repair~%")
(let ([tmp (make-temp-db-path "destroy")])
  (let ([tmp-db (leveldb-open tmp)])
    (leveldb-put tmp-db "key" "value")
    (leveldb-close tmp-db))
  ;; Repair
  (leveldb-repair-db tmp)
  ;; Verify data survives repair
  (let ([tmp-db (leveldb-open tmp (leveldb-options 'create-if-missing #f))])
    (check "after repair" (bv->string (leveldb-get tmp-db "key")) "value")
    (leveldb-close tmp-db))
  ;; Destroy
  (leveldb-destroy-db tmp)
  ;; Opening without create-if-missing should fail
  (check-exception "open destroyed db"
    (lambda () (leveldb-open tmp (leveldb-options 'create-if-missing #f)))))

;; --- Environment ---
(printf "~%Test: environment~%")
(let ([env (leveldb-default-env)])
  (check-true "default env" (not (zero? env)))
  (let ([test-dir (leveldb-env-test-directory env)])
    (check-true "env test directory" (string? test-dir))))

;; --- Report ---
(printf "~%=== Results: ~a/~a passed, ~a failed ===~%"
        pass-count test-count fail-count)

(when (> fail-count 0)
  (exit 1))

;; Source for sstrace_chain.wasm. Adapted from test/regress/ext:stack-switching/resume_chain3.wast.
;; Stack-switching opcodes aren't accepted by `wat2wasm`; rebuild with the stack-switching spec interpreter:
;;
;; wasm-spec/repos/stack-switching/interpreter/wasm test/wizeng/sstrace_chain.wat -o test/wizeng/sstrace_chain.wasm
(module
  (type $f1 (func (param i32) (result i32)))
  (type $c1 (cont $f1))
  (func $foo (param i32) (result i32)
    (if (result i32) (i32.eqz (local.get 0))
      (then (i32.const 0))
      (else
        (i32.add
          (i32.const 1)
          (resume $c1
            (i32.sub (local.get 0) (i32.const 1))
            (cont.new $c1 (ref.func $foo))
          )
        )
      )
    )
  )
  (elem declare func $foo)
  (func $main (param i32) (result i32)
    (resume $c1 (local.get 0) (cont.new $c1 (ref.func $foo)))
  )
  ;; main is left unexported so wizeng's auto-entry picks _start, which drives main(67).
  (func (export "_start")
    (drop (call $main (i32.const 67)))
  )
)

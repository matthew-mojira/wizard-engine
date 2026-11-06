;; A stack switch and a return that land on a function's final end, with the function's locals
;; and its result on the stack.
;; Build with: wasm-as -all test/wizeng/sstrace_end.wat -o test/wizeng/sstrace_end.wasm
(module
  (type $f (func (result i32)))
  (type $c (cont $f))
  (type $f2 (func (param i32) (result i32)))
  (type $c2 (cont $f2))
  (tag $y (result i32))

  ;; The result of the suspend is the function's result.
  (func $g (result i32) (local $l i32)
    (suspend $y))
  (elem declare func $g)

  ;; The result of the resume is the function's result.
  (func $r (param (ref null $c2)) (result i32) (local $a i32)
    (resume $c2 (i32.const 5) (local.get 0)))

  (func (export "main") (local $k (ref null $c2))
    (block $h (result (ref $c2))
      (drop (resume $c (on $y $h) (cont.new $c (ref.func $g))))
      (return))
    (local.set $k)
    (drop (call $r (local.get $k))))
)

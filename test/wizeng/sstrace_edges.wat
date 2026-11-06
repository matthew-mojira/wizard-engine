;; Stack events around an exception that passes through the resumer of a resume_throw,
;; and a catch handler shared with a resume.
;; Build with: wasm-as -all test/wizeng/sstrace_edges.wat -o test/wizeng/sstrace_edges.wasm
(module
  (type $f (func))
  (type $c (cont $f))
  (tag $y)
  (tag $e)

  ;; Suspends once, then returns.
  (func $gen (suspend $y))
  ;; Throws into a suspended child without catching, so the exception unwinds both stacks.
  (func $a
    (block $h (result (ref $c))
      (resume $c (on $y $h) (cont.new $c (ref.func $gen)))
      (return))
    (resume_throw $c $e))
  ;; Throws an exception.
  (func $thrower (throw $e))
  ;; Returns at once.
  (func $ok)
  (elem declare func $gen $a $thrower $ok)

  (func (export "main")
    ;; The exception thrown by $a unwinds its child and $a, and is caught here.
    (block $caught
      (try_table (catch $e $caught)
        (resume $c (cont.new $c (ref.func $a)))))
    ;; The handler of this catch is also the instruction after the second resume.
    (block $h
      (try_table (catch $e $h)
        (resume $c (cont.new $c (ref.func $thrower))))
      (resume $c (cont.new $c (ref.func $ok))))
  )
)

;; Parent resumes A, A resumes B, B returns to A, A returns to parent.
;; Two genOnResumeFinish invocations on different stacks before
;; parent's br_on_cast reads r_curpc.
(module
  (type $st (struct (field i32)))
  (type $f1 (func (result anyref)))
  (type $c1 (cont $f1))
  (func $b (result anyref)
    (struct.new $st (i32.const 42))
  )
  (elem declare func $a $b)
  (func $a (result anyref)
    (resume $c1 (cont.new $c1 (ref.func $b)))
  )
  (func (export "main") (result i32)
    (block $on_struct (result (ref $st))
      (resume $c1 (cont.new $c1 (ref.func $a)))
      (br_on_cast $on_struct anyref (ref $st))
      (drop)
      (return (i32.const 0))
    )
    (struct.get $st 0)
  )
)

(assert_return (invoke "main") (i32.const 42))

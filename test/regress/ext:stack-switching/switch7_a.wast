;; this is the test template for data type passing
;; control flow: main -> $from -> $to -> $from -> main
(module
  (type $f0 (func (result i32 i32 i32)))
  (type $c0 (cont $f0))

  ;; type of $from
  (type $f1 (func (param i32) (result i32 i32 i32)))
  (type $c1 (cont $f1))

  ;; type of continuation generated by switching from $to
  (type $f4 (func (param (ref null $c0)) (result i32 i32 i32)))
  (type $c4 (cont $f4))

  ;; type of continuation generated by switching from $from
  (type $f2 (func (param i32 i32 i32 (ref null $c4)) (result i32 i32 i32)))
  (type $c2 (cont $f2))

  ;; type of $to
  (type $f3 (func (param i32 i32 i32 (ref null $c2)) (result i32 i32 i32)))
  (type $c3 (cont $f3))

  (tag $e (result i32 i32 i32))

  (func $from (param $i i32) (result i32 i32 i32)
    (i32.add (local.get $i) (i32.const 100))
    (i32.add (local.get $i) (i32.const 200))
    (i32.add (local.get $i) (i32.const 300))
    (switch $c3 $e (cont.new $c3 (ref.func $to)))
    (drop)
    (return)
  )
  (elem declare func $from)

  (func $to (param $a i32) (param $b i32) (param $c i32) (param $cont (ref null $c2)) (result i32 i32 i32)
    (i32.add (local.get $a) (i32.const 10))
    (i32.add (local.get $b) (i32.const 20))
    (i32.add (local.get $c) (i32.const 30))
    (switch $c2 $e (local.get $cont))
    (unreachable)
  )
  (elem declare func $to)

  (func (export "main") (param $i i32) (result i32 i32 i32)
    (local.get $i)
    (resume $c1 (on $e switch) (cont.new $c1 (ref.func $from)))
  )
)

(assert_return (invoke "main" (i32.const 0)) (i32.const 110) (i32.const 220) (i32.const 330))

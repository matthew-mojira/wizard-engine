(module
  (func (export "m0") (param ) (result f32)
    (f32.nearest (f32.const 0))
  )
  (func (export "m1") (param ) (result f32)
    (f32.nearest (f32.const 0x1.4CCCCCp0))
  )
  (func (export "m2") (param ) (result f32)
    (f32.nearest (f32.const -0x1.B33334p0))
  )
)
(assert_return (invoke "m0" ) (f32.const 0))
(assert_return (invoke "m1" ) (f32.const 0x1.000000p0))
(assert_return (invoke "m2" ) (f32.const -0x1.000000p1))
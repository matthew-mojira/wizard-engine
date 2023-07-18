(module
  (func (export "bitselect") (param $0 v128) (param $1 v128) (param $2 v128) (result v128)
    (v128.bitselect (local.get $0) (local.get $1) (local.get $2))
  )
)

(assert_return (invoke "bitselect" (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA)
                                   (v128.const i32x4 0xBBBBBBBB 0xBBBBBBBB 0xBBBBBBBB 0xBBBBBBBB)
                                   (v128.const i32x4 0x11111111 0x11111111 0x11111111 0x11111111))
                                   (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA))
(assert_return (invoke "bitselect" (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA)
                                   (v128.const i32x4 0xBBBBBBBB 0xBBBBBBBB 0xBBBBBBBB 0xBBBBBBBB)
                                   (v128.const i32x4 0x01234567 0x89ABCDEF 0xFEDCBA98 0x76543210))
                                   (v128.const i32x4 0xBABABABA 0xBABABABA 0xABABABAB 0xABABABAB))
(assert_return (invoke "bitselect" (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA)
                                   (v128.const i32x4 0x55555555 0x55555555 0x55555555 0x55555555)
                                   (v128.const i32x4 0x01234567 0x89ABCDEF 0xFEDCBA98 0x76543210))
                                   (v128.const i32x4 0x54761032 0xDCFE98BA 0xAB89EFCD 0x23016745))
(assert_return (invoke "bitselect" (v128.const i32x4 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA 0xAAAAAAAA)
                                   (v128.const i32x4 0x55555555 0x55555555 0x55555555 0x55555555)
                                   (v128.const i32x4 0x55555555 0xAAAAAAAA 0x00000000 0xFFFFFFFF))
                                   (v128.const i32x4 0x00000000 0xFFFFFFFF 0x55555555 0xAAAAAAAA))
(assert_return (invoke "bitselect" (v128.const i32x4 01_234_567_890 01_234_567_890 01_234_567_890 01_234_567_890)
                                   (v128.const i32x4 03_060_399_406 03_060_399_406 03_060_399_406 03_060_399_406)
                                   (v128.const i32x4 0xcdefcdef 0xcdefcdef 0xcdefcdef 0xcdefcdef))
                                   (v128.const i32x4 2072391874 2072391874 2072391874 2072391874))
(assert_return (invoke "bitselect" (v128.const i32x4 0x0_1234_5678 0x0_1234_5678 0x0_1234_5678 0x0_1234_5678)
                                   (v128.const i32x4 0x0_90AB_cdef 0x0_90AB_cdef 0x0_90AB_cdef 0x0_90AB_cdef)
                                   (v128.const i32x4 0xcdefcdef 0xcdefcdef 0xcdefcdef 0xcdefcdef))
                                   (v128.const i32x4 0x10244468 0x10244468 0x10244468 0x10244468))

;; Type check
(assert_invalid (module (func (result v128) (v128.bitselect (i32.const 0) (v128.const i32x4 0 0 0 0) (v128.const i32x4 0 0 0 0)))) "type mismatch")
(assert_invalid (module (func (result v128) (v128.bitselect (v128.const i32x4 0 0 0 0) (v128.const i32x4 0 0 0 0) (i32.const 0)))) "type mismatch")
(assert_invalid (module (func (result v128) (v128.bitselect (i32.const 0) (i32.const 0) (i32.const 0)))) "type mismatch")

;; Test operation with empty argument
(assert_invalid
  (module
    (func $v128.bitselect-1st-arg-empty (result v128)
      (v128.bitselect (v128.const i32x4 0 0 0 0) (v128.const i32x4 0 0 0 0))
    )
  )
  "type mismatch"
)
(assert_invalid
  (module
    (func $v128.bitselect-two-args-empty (result v128)
      (v128.bitselect (v128.const i32x4 0 0 0 0))
    )
  )
  "type mismatch"
)
(assert_invalid
  (module
    (func $v128.bitselect-arg-empty (result v128)
      (v128.bitselect)
    )
  )
  "type mismatch"
)

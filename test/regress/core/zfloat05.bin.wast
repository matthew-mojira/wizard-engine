(module binary
  "\00\61\73\6d\01\00\00\00\01\8a\80\80\80\00\01\60"
  "\04\7d\7d\7d\7f\02\7d\7d\03\82\80\80\80\00\01\00"
  "\07\85\80\80\80\00\01\01\66\00\00\0a\b0\80\80\80"
  "\00\01\aa\80\80\80\00\00\20\00\20\02\1a\1a\20\03"
  "\04\40\20\00\22\01\20\02\22\00\21\01\21\02\05\20"
  "\00\22\01\20\02\22\02\21\01\21\00\0b\20\00\20\01"
  "\0b"
)
(assert_return
  (invoke "f"
    (f32.const 0x1.1999_9ap+0)
    (f32.const 0x1.1999_9ap+1)
    (f32.const 0x1.a666_66p+1)
    (i32.const 0x0)
  )
  (f32.const 0x1.1999_9ap+0)
  (f32.const 0x1.a666_66p+1)
)
(assert_return
  (invoke "f"
    (f32.const 0x1.a666_66p+1)
    (f32.const 0x1.1999_9ap+2)
    (f32.const 0x1.6p+2)
    (i32.const 0x1)
  )
  (f32.const 0x1.6p+2)
  (f32.const 0x1.6p+2)
)
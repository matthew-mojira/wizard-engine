(module binary
  "\00\61\73\6d\01\00\00\00\01\8f\80\80\80\00\06\5f"
  "\00\5f\00\5f\00\5f\00\5f\00\60\01\7f\00\03\82\80"
  "\80\80\00\01\05\07\85\80\80\80\00\01\01\66\00\00"
  "\0a\92\80\80\80\00\01\8c\80\80\80\00\00\d0\04\d0"
  "\04\20\00\1c\01\6e\1a\0b"
)
(assert_return (invoke "f" (i32.const 0x0)))
(assert_return (invoke "f" (i32.const 0x1)))

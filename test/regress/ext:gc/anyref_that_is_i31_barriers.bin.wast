(module binary
  "\00\61\73\6d\01\00\00\00\01\90\80\80\80\00\03\60"
  "\01\7f\01\6e\60\02\7f\6e\00\60\02\7f\7f\00\03\84"
  "\80\80\80\00\03\00\01\02\04\85\80\80\80\00\01\6e"
  "\01\01\01\07\8d\80\80\80\00\02\03\67\65\74\00\00"
  "\03\73\65\74\00\02\0a\a8\80\80\80\00\03\86\80\80"
  "\80\00\00\20\00\25\00\0b\88\80\80\80\00\00\20\00"
  "\20\01\26\00\0b\8a\80\80\80\00\00\20\00\20\01\fb"
  "\1c\10\01\0b"
)
(assert_return (invoke "get" (i32.const 0x0)) (ref.null any))
(invoke "set" (i32.const 0x0) (i32.const 0x2a))
(assert_return (invoke "get" (i32.const 0x0)) (ref.i31))
(module binary
  "\00\61\73\6d\01\00\00\00\01\92\80\80\80\00\03\60"
  "\01\7f\01\64\6e\60\02\7f\64\6e\00\60\02\7f\7f\00"
  "\03\84\80\80\80\00\03\00\01\02\04\8d\80\80\80\00"
  "\01\40\00\64\6e\01\01\01\41\00\fb\1c\0b\07\8d\80"
  "\80\80\00\02\03\67\65\74\00\00\03\73\65\74\00\02"
  "\0a\a8\80\80\80\00\03\86\80\80\80\00\00\20\00\25"
  "\00\0b\88\80\80\80\00\00\20\00\20\01\26\00\0b\8a"
  "\80\80\80\00\00\20\00\20\01\fb\1c\10\01\0b"
)
(assert_return (invoke "get" (i32.const 0x0)) (ref.i31))
(invoke "set" (i32.const 0x0) (i32.const 0x2a))
(assert_return (invoke "get" (i32.const 0x0)) (ref.i31))

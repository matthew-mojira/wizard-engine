(module definition binary
  "\00\61\73\6d\01\00\00\00\01\88\80\80\80\00\02\60"
  "\00\02\7f\7f\5d\00\03\84\80\80\80\00\03\00\00\00"
  "\07\88\80\80\80\00\01\04\6d\61\69\6e\00\02\09\86"
  "\80\80\80\00\01\03\00\02\00\01\0a\a8\80\80\80\00"
  "\03\86\80\80\80\00\00\41\2a\41\37\0b\89\80\80\80"
  "\00\00\d2\00\e0\01\e3\01\00\0b\89\80\80\80\00\00"
  "\d2\01\e0\01\e3\01\00\0b"
)
(module instance)
(assert_return (invoke "main") (i32.const 0x2a) (i32.const 0x37))

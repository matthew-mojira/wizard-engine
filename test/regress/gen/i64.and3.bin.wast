(module binary
  "\00\61\73\6d\01\00\00\00\01\85\80\80\80\00\01\60"
  "\00\01\7e\03\82\80\80\80\00\01\00\07\86\80\80\80"
  "\00\01\02\6d\30\00\00\0a\98\80\80\80\00\01\92\80"
  "\80\80\00\00\42\80\fe\83\78\42\ff\ff\ff\ff\8f\e0"
  "\bf\80\7f\83\0b"
)
(assert_return (invoke "m0") (i64.const 0xff00_ff00_ff00_ff00))
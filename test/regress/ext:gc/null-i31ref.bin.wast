(module binary
  "\00\61\73\6d\01\00\00\00\01\85\80\80\80\00\01\60"
  "\00\01\7f\03\83\80\80\80\00\02\00\00\07\9b\80\80"
  "\80\00\02\0a\67\65\74\5f\75\2d\6e\75\6c\6c\00\00"
  "\0a\67\65\74\5f\73\2d\6e\75\6c\6c\00\01\0a\97\80"
  "\80\80\00\02\86\80\80\80\00\00\d0\6c\fb\1e\0b\86"
  "\80\80\80\00\00\d0\6c\fb\1e\0b"
)
(assert_trap (invoke "get_u-null") "null i31 reference")
(assert_trap (invoke "get_s-null") "null i31 reference")

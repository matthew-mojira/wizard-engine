(module binary
  "\00\61\73\6d\01\00\00\00\01\88\80\80\80\00\02\60"
  "\00\00\60\00\01\7f\03\85\80\80\80\00\04\00\01\01"
  "\01\05\83\80\80\80\00\01\00\01\07\e4\80\80\80\00"
  "\05\06\6d\65\6d\6f\72\79\02\00\04\6d\61\69\6e\00"
  "\00\17\74\65\73\74\5f\69\33\32\5f\61\74\6f\6d\69"
  "\63\5f\63\6d\70\78\63\68\67\00\01\19\74\65\73\74"
  "\5f\69\33\32\5f\61\74\6f\6d\69\63\5f\63\6d\70\78"
  "\63\68\67\5f\38\00\02\1a\74\65\73\74\5f\69\33\32"
  "\5f\61\74\6f\6d\69\63\5f\63\6d\70\78\63\68\67\5f"
  "\31\36\00\03\0a\e2\80\80\80\00\04\94\80\80\80\00"
  "\00\41\00\41\05\36\02\00\41\00\41\05\41\03\fe\48"
  "\02\00\1a\0b\93\80\80\80\00\00\41\00\41\05\36\02"
  "\00\41\00\41\05\41\03\fe\48\02\00\0b\93\80\80\80"
  "\00\00\41\00\41\05\36\02\00\41\00\41\05\41\03\fe"
  "\4a\00\00\0b\93\80\80\80\00\00\41\00\41\05\36\02"
  "\00\41\00\41\05\41\03\fe\4b\01\00\0b"
)
(assert_return (invoke "test_i32_atomic_cmpxchg") (i32.const 0x5))
(assert_return (invoke "test_i32_atomic_cmpxchg_8") (i32.const 0x5))
(assert_return (invoke "test_i32_atomic_cmpxchg_16") (i32.const 0x5))
(assert_return (invoke "main"))

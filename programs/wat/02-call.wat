;;STACK_DEPTH 1
;;TOP_OF_STACK 0x1e
(module
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
    local.get $lhs
    local.get $rhs
    i32.add)
  (func $main
	i32.const 10
	i32.const 20
	call $add
	unreachable
	)
  (start $main)
)


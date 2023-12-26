(module
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
	(local $a i32)
	(local $b i32)
	(local $c i64)
	(local $d i64)
    local.get $lhs
    local.get $rhs
	i32.const 5
	local.set $a
	i32.const 7
	local.set $b
	local.get $a
	local.get $b
	i32.mul
	i32.add
	i32.add
	)
  (func $main
	i32.const 10
	i32.const 20
	call $add
	drop)
  (start $main)
)

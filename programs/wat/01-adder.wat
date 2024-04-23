;;STACK_DEPTH 1
;;TOP_OF_STACK 0x1e
(module
  (func $main
	i32.const 10
	i32.const 20
	i32.add
	unreachable
  )
  (start $main)
)

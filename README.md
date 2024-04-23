## Overview
This is a learning project to create a CPU based on the WebAssembly (WASM) instruction set. An important goal for the project is being able to execute bytecode 
without any modification passes.

There is a very simple and incomplete simulator in Python, used to sketch/validate experiments before implementing them in Verilog.

## Interesting Features

### Virtual Memory

Each WASM program operates within its own linear memory space, starting at `0x0`. This requires a Virtual Memory system to map each process' address space to different areas of physical memory.
The memory map table looks something like this:

| Virtual Addr     | Physical Addr    |
|------------------|------------------|
| 0x00000          | 0x10000          |
| 0x10000          | 0x20000          |
| ...              | ...              |

### Indirect Function Calls

Each WASM program has a table describing the functions available in its execution context. The table looks something like this:

| Index | Function Address |
|-------|------------------|
| 0     | 0x00123          |
| 1     | 0x00456          |
| ...   | ...              |


Based on this, the `CALL` instruction operates on an indexm (e.g., `CALL 0` or `CALL 7`).

The structure which holds the task-context keeps a vtable which resolves these indices to function addresses.

### Controlled platform access via imports

WASM, by design, does not expose any way of interacting with host hardware (eg: `cr0` register, `syscall` instruction).

The CPU can be directly controlled through imported "platform" functions.

Examples:

```wasm
  (import "platform" "uart_write" (func $uart_write (param i32)))
  (import "platform" "context_switch" (func $context_switch (param i32)))
```

These imports allow for operations like I/O device access (`uart_write`) and process management (`context_switch`).

## In action

Summarized/annotated output from running a test in simulation with `iverilog`:

The program:
```wat
(module
  (func $add (param $lhs i32) (param $rhs i32) (result i32)
    local.get $lhs
    local.get $rhs
    i32.add)
  (func $main
	i32.const 10
	i32.const 20
	call $add
	drop)
  (start $main)
)
```

The output:
```
[CPU] starting                          
[MEM] Read  41 from 00000040            
[MEM] Read  0a from 00000041            
[E] i32.const 0xa                       
[MEM] Wrote 0a to   000000aa            
[MEM] Read  41 from 00000042            
[MEM] Read  14 from 00000043            
[E] i32.const 0x14                      
[MEM] Wrote 14 to   000000ab            
[MEM] Read  10 from 00000044            ; read CALL operand
[MEM] Read  00 from 00000045            ; immediate (function index) is 0 
[MEM] Read  08 from 00000604            ; read Function Table[0].flags (0x80 = 2 arguments)
[MEM] Read  30 from 00000603            ; read Function Table[0].address
[E] call jmp into 30                    
Fetching operand into reg from stack    ; fetch first argument from stack into register
[MEM] Read  14 from 000000ab            
Fetching operand into reg from stack    ; fetch second argument from stack into register
[MEM] Read  0a from 000000aa            
[E] pc=00000046                         
[E] call 0x0
[E] new PC 00000030                     ; new PC is 0x30, from 0x46 
[MEM] Wrote 46 to   00000055            ; store 0x46 in the callstack
[MEM] Read  20 from 00000030            
[MEM] Read  00 from 00000031            
[E] local_get #0x0 = 0xa                ; write value from the call-register into operand-stack
[MEM] Wrote 0a to   000000aa            
[MEM] Read  20 from 00000032            
[MEM] Read  01 from 00000033            
[E] local_get #0x1 = 0x14               ; write value from the call-register into operand-stack
[MEM] Wrote 14 to   000000ab            
[MEM] Read  6a from 00000034            
Fetching operand into reg from stack    
[MEM] Read  14 from 000000ab            
Fetching operand into reg from stack    
[MEM] Read  0a from 000000aa            
[E] i32.add 0xa 0x14                    ; execute add, consuming 2 elements on the stack and pushing a new one 
[MEM] Wrote 1e to   000000aa            
[MEM] Read  0b from 00000035            
[MEM] Read  46 from 00000055            
[E] EOB (RET) to 46                     ; implicit return from function call
[MEM] Read  1a from 00000046            
Fetching operand into reg from stack    
[MEM] Read  1e from 000000aa            
[E] DROP                                ; drop result from function call
[MEM] Read  0b from 00000047            
[E] pc=00000048                         
[E] EOF end of program                  ; implicit return from main function; call stack empty; finish program
```

## Testing

Placing a `.wat` file in `programs/wat` will get it executed during the test runs.

The depth of the stack and value at top-of-stack must be provided to verify execution, as an example:

```wat
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
```
## Links

- [Spec](https://www.w3.org/TR/wasm-core-1/#binary-codesec)
- [Code exporer](https://wasdk.github.io/wasmcodeexplorer/)
- [MDN WASM Page](https://developer.mozilla.org/en-US/docs/WebAssembly/Understanding_the_text_format)
- [Understanding every byte in a WASM Module](https://danielmangum.com/posts/every-byte-wasm-module/)
- [WebAssembly Opcodes](https://pengowray.github.io/wasm-ops/)

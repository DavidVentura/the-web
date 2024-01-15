

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

## Links

- [Spec](https://www.w3.org/TR/wasm-core-1/#binary-codesec)
- [Code exporer](https://wasdk.github.io/wasmcodeexplorer/)
- [MDN WASM Page](https://developer.mozilla.org/en-US/docs/WebAssembly/Understanding_the_text_format)
- [Understanding every byte in a WASM Module](https://danielmangum.com/posts/every-byte-wasm-module/)
- [WebAssembly Opcodes](https://pengowray.github.io/wasm-ops/)

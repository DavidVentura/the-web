
## Memory

Each program gets 4 memory regions:
- Code (instructions)
- Operand stack 
- Call stack 
- "Memory" pages

The first page is used to control the CPU

* 0x00: Page table base
* 0x08: Page table length
* 0x10: Function table base
* 0x18: Function table length
* 0x20: Operand stack _top_
* 0x28: Call stack _top_
* 0x30: Code (until 0x1000)

## State out of reset

MMU has 1 entry, page 0 points to physical address 0

* PT: 0x1000 (until 0x2000)
* FT: 0x2000 (until 0x3000)
* OP stack: 0x3000 (until 0x4000)
* Memory: 0x4000-0xFFFF 

### Page tables

A page table is defined as a packed list of offsets for physical addresses; the indices into the table
are the page number.

The index lookup is done by shifting the address 16 bits to the right:

* 0x00000-0x10000 => Page 1
* 0x10000-0x20000 => Page 2
* ...

An example mapping with two entries:

```
[0x0, 0x20000]
```

* Virtual addresses 0x00000-0x0FFFF are identity-mapped into the same physical addresses
* Virtual addresses 0x10000-0x20000 are mapped into the physical address `0x20000-0x30000`

### Function tables

List of function-table-entry, index into table = function index

#### Function table entry

Packed:
* Virtual Address = 32 bits
* Arg count = 7 bits
* Is import = 1 bit


## Function calls

a `call` instruction needs some metadata:

- Argument count
- Physical memory address for instruction

Need to save current registers (variable #)
Need to pop $ARGC from the stack into registers (variable #)

=> 32 registers
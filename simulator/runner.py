import sys
import enum
import logging
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

WASM_V1_MAGIC = bytes([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
program = Path(sys.argv[1]).read_bytes()
if not program.startswith(WASM_V1_MAGIC):
    raise ValueError("Illegal program")

mem = [0] * 1024
function_addrs = []
function_type_info = []
params_in_type = []
entrypoint_fn_id = -1
operand_stack = []
call_stack = []
register_stack = []  # TODO, how to do this properly?


@dataclass
class Instruction:
    pass

class Instr(enum.Enum):
    i32_const = 0x41
    call = 0x10
    drop = 0x1A
    end_of_func = 0xB
    i32_add = 0x6a
    i32_mul = 0x6c
    local_get = 0x20
    local_set = 0x21

class CPU:
    FETCH_INSTR = 0
    FETCH_LE128 = 1
    DECODE = 2
    EXEC = 3
    HALT = 4

    def __init__(self, pc: int):
        self.pc = pc
        self.state = CPU.FETCH_INSTR
        self.fetched_instr = None
        self.payload = 0
        self.cur_data_byte = 0
        self.registers = [0] * 4 # how many registers are reasonable?

    def fetch(self) -> int:
        byte = program[self.pc]
        log.debug('fetched', hex(byte))
        self.pc += 1
        return byte

    def decode(self):
        assert self.fetched_instr
        i = Instr(self.fetched_instr)
        match i:
            case Instr.local_get:
                self.state = self.FETCH_LE128
            case Instr.i32_const:
                self.state = self.FETCH_LE128
            case Instr.local_set:
                self.state = self.FETCH_LE128
            case Instr.i32_add:
                self.state = CPU.EXEC
            case Instr.i32_mul:
                self.state = CPU.EXEC
            case Instr.drop:
                self.state = CPU.EXEC
            case Instr.end_of_func:
                self.state = CPU.EXEC
            case Instr.call:
                self.state = self.FETCH_LE128
            case _:
                raise NotImplementedError(f"Can't decode instr {i}")

    def execute(self):
        assert self.fetched_instr
        i = Instr(self.fetched_instr)
        print(f'[E] {i} with [{hex(self.payload)}]')
        match i:
            case Instr.i32_const:
                operand_stack.append(self.payload)
            case Instr.i32_mul:
                a = operand_stack.pop()
                b = operand_stack.pop()
                operand_stack.append(a*b)
            case Instr.i32_add:
                a = operand_stack.pop()
                b = operand_stack.pop()
                operand_stack.append(a+b)
            case Instr.drop:
                operand_stack.pop()
            case Instr.call:
                log.debug(f"saving registers: {self.registers}")
                register_stack.append(self.registers.copy())
                call_stack.append(self.pc)
                param_count = function_type_info[self.payload]
                for i in range(param_count):
                    self.registers[i] = operand_stack.pop()
                self.pc = function_addrs[self.payload]
                log.debug(f"[CALL] {self.payload},\n registers: {self.registers}\n opstack {operand_stack}\n cs {call_stack}\n rs {register_stack}")

            case Instr.end_of_func:
                if not call_stack:
                    self.state = CPU.HALT
                    return
                self.pc = call_stack.pop()
                self.registers = register_stack.pop()
                log.debug(f'ret from {call_stack}, regs are {self.registers}')
            case Instr.local_set:
                self.registers[self.payload] = operand_stack.pop()
            case Instr.local_get:
                operand_stack.append(self.registers[self.payload])
            case _:
                raise NotImplementedError(f"Can't exec instr {i}")

        print("[S]", operand_stack)
        self.state = CPU.FETCH_INSTR

    def step(self):
        match self.state:
            case CPU.FETCH_LE128:
                assert self.fetched_instr
                byte = self.fetch()
                self.payload |= (byte & 0b0111_111) << (7*self.cur_data_byte)
                log.debug(f'[LE128] #{self.cur_data_byte} = {self.payload}')
                if _incomplete_leb(byte):
                    self.cur_data_byte += 1
                else:
                    self.state = CPU.EXEC
            case CPU.FETCH_INSTR:
                self.payload = 0
                self.cur_data_byte = 0
                self.fetched_instr = self.fetch()
                self.state = CPU.DECODE
            case CPU.DECODE:
                self.decode()
            case CPU.EXEC:
                self.execute()
            case CPU.HALT:
                raise NotImplementedError

def _incomplete_leb(b: int) -> bool:
    return b & 0b1000_0000 == 0b1000_0000

def read_leb128(at: int) -> tuple[int, int]:
    res = 0
    counter = 0
    while _incomplete_leb(program[at]):
        res += (program[at] & 0b0111_1111) << (7*counter)
        at += 1
        counter += 1
        if at >= 15:
            raise ValueError("leb128 too big")

    res += (program[at] & 0b0111_1111) << (7*counter)
    counter += 1
    return res, counter


class Section(enum.Enum):
    TYPE = 1
    IMPORT = 2
    FUNCTION = 3
    EXPORT = 7
    START = 8
    CODE = 0xA

def read_section(at: int):
    section = Section(program[at])
    at += 1
    section_size, read = read_leb128(at)
    at += read
    log.debug(f'section {section} of size {section_size}')
    match section:
        case Section.TYPE:
            type_cnt, read = read_leb128(at)
            log.debug('type cnt', type_cnt, at, read)
            at += read
            for idx in range(type_cnt):
                typetag, read = read_leb128(at)
                assert typetag == 0x60, hex(typetag)
                at += read
                param_cnt, read = read_leb128(at)
                at += read
                args = []
                for i in range(param_cnt):
                    param_type, read = read_leb128(at)
                    at += read
                    args.append(param_type)
                params_in_type.append(param_cnt)
                ret_cnt, read = read_leb128(at)
                at += read

                ret= []
                for i in range(ret_cnt):
                    ret_type, read = read_leb128(at)
                    at += read
                    ret.append(ret_type)

                log.debug(f"for func {idx} got {param_cnt} params and {ret_cnt} ret")

        case Section.IMPORT:
            cnt, read = read_leb128(at)
            at += read
            for i in range(cnt):
                module_len, read = read_leb128(at)
                at += read
                module_name = program[at:at+module_len]
                at += module_len
                log.debug("module name", module_name)

                import_name_len, read = read_leb128(at)
                at += read
                import_name = program[at:at+import_name_len]
                at += import_name_len
                log.debug("import name", import_name)

                type_id, read = read_leb128(at)
                at += read
                assert type_id == 0, type_id

                type_idx, read = read_leb128(at)
                log.debug("type idx", type_idx)
                at += read

                function_type_info.append(params_in_type[type_idx])

                # TODO: populatae microcode?
                func_addr = 0
                function_addrs.append(func_addr)

        case Section.FUNCTION:
            cnt, read = read_leb128(at)
            at += read
            for i in range(cnt):
                type_idx, read = read_leb128(at)
                function_type_info.append(params_in_type[type_idx])
                log.debug(f'for func {i} got type_idx {type_idx}')
                at += read

        case Section.EXPORT:
            at += section_size

        case Section.START:
            global entrypoint_fn_id
            entrypoint_fn_id, read = read_leb128(at)
            at += read
            log.debug('start fn id', entrypoint_fn_id)

        case Section.CODE:
            functions_count, read = read_leb128(at)
            at += read
            log.debug('fcount', functions_count)
            for i in range(functions_count):
                fsize, read = read_leb128(at)
                at += read
                log.debug(f"func {i}, is of size{fsize}")
                local_blocks, read = read_leb128(at)
                at += read
                type_info_read = read
                log.debug(f"at func {i}, found {local_blocks} types of locals")
                for j in range(local_blocks):
                    local_count, read = read_leb128(at)
                    at += read
                    type_info_read += read

                    type_of_locals, read = read_leb128(at)
                    at += read
                    type_info_read += read
                    log.debug(f"found {local_count} locals of type {type_of_locals}")
                    
                code_size = fsize - type_info_read
                log.debug('code size', code_size)
                first_instr_idx = at
                function_addrs.append(first_instr_idx)
                instr = program[at:at+code_size]
                assert instr[-1] == 0xb
                at += code_size
                log.debug('istr', [hex(i) for i in instr])
                # vec of locals
                # expr

    return section, at

idx = len(WASM_V1_MAGIC)
while idx < len(program):
    sec, idx = read_section(idx)
    log.debug(sec, idx)

log.debug([hex(a) for a in function_addrs])
c = CPU(function_addrs[entrypoint_fn_id])
while c.state != CPU.HALT:
    c.step()
print("done!")

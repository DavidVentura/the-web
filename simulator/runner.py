import enum
import logging
from dataclasses import dataclass

from simulator.wasm_parser import ProgramInfo, load_program, read_program

log = logging.getLogger(__name__)

mem = [0] * 1024

# parsed

# execution only
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

    def __init__(self, pi: ProgramInfo):
        self.registers = [0] * 4 # how many registers are reasonable?
        self.program_offset = 0
        self.pi = []
        self._initialize(pi, 0)

    def _initialize(self, pi: ProgramInfo, program_offset: int):
        self.pc = pi.function_addrs[pi.entrypoint_fn_id]
        self.state = CPU.FETCH_INSTR
        self.fetched_instr = None
        self.payload = 0
        self.cur_data_byte = 0
        self.pi.append(pi)
        self.program_offset = program_offset

    def fetch(self) -> int:
        byte = self.pi[self.program_offset].flash[self.pc]
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
                # FIXME: leaves the payload in stack
                if self.program_offset == 0:
                    print("Executing microcode CALL, forcing read_program")
                    pi = load_program(1) # FIXME self.payload)
                    self._initialize(pi, 1)
                    return
                log.debug(f"saving registers: {self.registers}")
                register_stack.append(self.registers.copy())
                call_stack.append(self.pc)
                param_count = self.pi[self.program_offset].function_type_info[self.payload]
                for i in range(param_count):
                    self.registers[i] = operand_stack.pop()

                # Should have a mapping of 
                # for this PID, function X comes from table Y?
                self.pc = self.pi[self.program_offset].function_addrs[self.payload]
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
                if byte & 0b1000_0000 == 0b1000_0000:
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


def main():
    pi = load_program(6)
    c = CPU(pi)
    while c.state != CPU.HALT:
        c.step()
    print("done!")

main()

from dataclasses import dataclass
from pathlib import Path
import enum
import logging

WASM_V1_MAGIC = bytes([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])

log = logging.getLogger(__name__)

class Section(enum.Enum):
    TYPE = 1
    IMPORT = 2
    FUNCTION = 3
    EXPORT = 7
    START = 8
    CODE = 0xA

@dataclass
class ProgramInfo:
    function_addrs: list[int]
    function_type_info: list[int]
    entrypoint_fn_id: int
    flash: bytes  # FIXME this is a hack, not necessary


def load_program(offset: int):
    paths = sorted(Path().glob("*.wasm"))
    print(paths)
    path = paths[offset]
    print(path, path)
    program = path.read_bytes()
    pi = read_program(program)
    return pi

def read_program(program: bytes) -> ProgramInfo:
    params_in_type = []
    entrypoint_fn_id = -1
    function_addrs = []
    function_type_info = []

    if not program.startswith(WASM_V1_MAGIC):
        raise ValueError("Illegal program")

    at = len(WASM_V1_MAGIC)

    while at < len(program):
        section = Section(program[at])
        at += 1
        section_size, read = read_leb128(program, at)
        at += read
        log.debug(f'section {section} of size {section_size}')
        match section:
            case Section.TYPE:
                type_cnt, read = read_leb128(program, at)
                log.debug('type cnt', type_cnt, at, read)
                at += read
                for idx in range(type_cnt):
                    typetag, read = read_leb128(program, at)
                    assert typetag == 0x60, hex(typetag)
                    at += read
                    param_cnt, read = read_leb128(program, at)
                    at += read
                    args = []
                    for i in range(param_cnt):
                        param_type, read = read_leb128(program, at)
                        at += read
                        args.append(param_type)
                    params_in_type.append(param_cnt)
                    ret_cnt, read = read_leb128(program, at)
                    at += read

                    ret_types= []
                    for i in range(ret_cnt):
                        ret_type, read = read_leb128(program, at)
                        at += read
                        ret_types.append(ret_type)

                    log.debug(f"for func {idx} got {param_cnt} params and {ret_cnt} ret_types")

            case Section.IMPORT:
                cnt, read = read_leb128(program, at)
                at += read
                for i in range(cnt):
                    module_len, read = read_leb128(program, at)
                    at += read
                    module_name = program[at:at+module_len]
                    at += module_len
                    log.debug("module name", module_name)

                    import_name_len, read = read_leb128(program, at)
                    at += read
                    import_name = program[at:at+import_name_len]
                    at += import_name_len
                    log.debug("import name", import_name)

                    type_id, read = read_leb128(program, at)
                    at += read
                    assert type_id == 0, type_id

                    type_idx, read = read_leb128(program, at)
                    log.debug("type idx", type_idx)
                    at += read

                    function_type_info.append(params_in_type[type_idx])

                    # TODO: populatae microcode?
                    func_addr = 0
                    function_addrs.append(func_addr)

            case Section.FUNCTION:
                cnt, read = read_leb128(program, at)
                at += read
                for i in range(cnt):
                    type_idx, read = read_leb128(program, at)
                    function_type_info.append(params_in_type[type_idx])
                    log.debug(f'for func {i} got type_idx {type_idx}')
                    at += read

            case Section.EXPORT:
                at += section_size

            case Section.START:
                entrypoint_fn_id, read = read_leb128(program, at)
                at += read
                log.debug('start fn id', entrypoint_fn_id)

            case Section.CODE:
                functions_count, read = read_leb128(program, at)
                at += read
                log.debug('fcount', functions_count)
                for i in range(functions_count):
                    fsize, read = read_leb128(program, at)
                    at += read
                    log.debug(f"func {i}, is of size{fsize}")
                    local_blocks, read = read_leb128(program, at)
                    at += read
                    type_info_read = read
                    log.debug(f"at func {i}, found {local_blocks} types of locals")
                    for j in range(local_blocks):
                        local_count, read = read_leb128(program, at)
                        at += read
                        type_info_read += read

                        type_of_locals, read = read_leb128(program, at)
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

    ret = ProgramInfo(
            function_addrs=function_addrs,
            function_type_info=function_type_info,
            entrypoint_fn_id=entrypoint_fn_id,
            flash=program,
            )
    return ret

def read_leb128(program: bytes, at: int) -> tuple[int, int]:
    res = 0
    counter = 0
    while program[at] & 0b1000_0000 == 0b1000_0000:
        res += (program[at] & 0b0111_1111) << (7*counter)
        at += 1
        counter += 1
        if at >= 15:
            raise ValueError("leb128 too big")

    res += (program[at] & 0b0111_1111) << (7*counter)
    counter += 1
    return res, counter


import sys
import subprocess
from pathlib import Path

import pytest

CODE_BASE = 0x40
CODE_AT = 0x50
SRC_FILES = list(str(p) for p in Path("src/").glob("*.v") if p.name != "platform.v")

def byte_line(n: int) -> str:
    ret = ""
    for i in range(7, -1, -1):
        bit = (n & (1 << i)) >> i
        ret += str(bit)
    return ret

assert byte_line(0) == "00000000"
assert byte_line(1) == "00000001"
assert byte_line(0xFF) == "11111111"

def process_file(data: bytes, mem_size: int) -> list[str]:
    ret = []

    for _ in range(0, CODE_BASE):
        ret.append('00000000')

    ret.append(byte_line(CODE_AT))

    for _ in range(CODE_BASE+1, CODE_AT):
        ret.append('00000000')

    for b in data:
        ret.append(byte_line(b))

    needed_size = len(data) + CODE_AT
    delta = mem_size - needed_size
    assert delta > 0, f"Need to populate at least {needed_size}"
    for _ in range(0, delta):
        ret.append('00000000')
    return ret

def parse_expects(p: Path) -> dict:
    ret = {}
    for line in p.open().readlines():
        if not line.startswith(';;'):
            continue
        k, v = line[2:].strip().split()
        ret[k] = v
    return ret

def wat2wasm(program: Path):
    cmd = ["wat2wasm", str(program), "--output=-"]
    p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE)
    return p.stdout

def _test_cases():
    ret = sorted(Path("programs/wat/").glob("*.wat"))
    ret = [pytest.param(p, id=p.name) for p in ret]
    return ret

@pytest.mark.parametrize("program", _test_cases())
def test(tmp_path, program: Path):
    wasm = wat2wasm(program)
    mem = process_file(wasm, 256)

    expects = parse_expects(program)
    expects = [f'+{k}={v}' for k, v in expects.items()]

    build_cmd = ["iverilog", "-DDEBUG=1", "-o", str(tmp_path / "a.out")] + SRC_FILES + ['testbench/cpu_tb.v']
    subprocess.check_call(build_cmd)

    mem_file = tmp_path / f"m_{program.name}"
    with mem_file.open('w') as fd:
        fd.write('\n'.join(mem))
    cmd = ['./a.out', f'+TESTNAME={mem_file.name}', '+PC=50'] + expects
    p = subprocess.run(cmd, cwd=tmp_path, stdout=subprocess.PIPE, check=True)
    output = p.stdout.decode('utf-8')
    print(output)
    if 'ERROR' in output:
        #print(output)
        line = [l for l in output.splitlines() if 'ERROR' in l]
        pytest.fail(f"Error in testcase: {line}")

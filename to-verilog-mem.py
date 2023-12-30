import sys

with open(sys.argv[1], "rb") as fd:
    data = fd.read()

CODE_BASE = 0x30
CODE_AT = 0x40
DEBUG = False

def byte_line(n: int) -> str:
    ret = ""
    for i in range(7, -1, -1):
        bit = (n & (1 << i)) >> i
        ret += str(bit)
    return ret

assert byte_line(0) == "00000000"
assert byte_line(1) == "00000001"
assert byte_line(0xFF) == "11111111"

with open(sys.argv[2], "w") as fd:
    for i in range(0, CODE_BASE):
        fd.write('00000000\n')

    fd.write(byte_line(CODE_AT) + '\n')

    for i in range(CODE_BASE+1, CODE_AT):
        fd.write('00000000\n')

    for b in data:
        fd.write(byte_line(b))
        if DEBUG:
            fd.write(f' {hex(b)}')
        fd.write('\n')

    needed_size = len(data) + CODE_AT
    delta = int(sys.argv[3]) - needed_size
    assert delta > 0, f"Need to populate at least {needed_size}"
    for i in range(0, delta):
        fd.write('00000000\n')

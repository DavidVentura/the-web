
CODE_BASE = 0x40
CODE_AT = 0x50
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

def process_file(fname, mem_size: int) -> list[str]:
    ret = []
    with open(fname, "rb") as fd:
        data = fd.read()

    for _ in range(0, CODE_BASE):
        ret.append('00000000')

    ret.append(byte_line(CODE_AT))

    for _ in range(CODE_BASE+1, CODE_AT):
        ret.append('00000000')

    for b in data:
        ret.append(byte_line(b))
        if DEBUG:
            ret.append(f' {hex(b)}')
        ret.append('\n')

    needed_size = len(data) + CODE_AT
    delta = mem_size - needed_size
    assert delta > 0, f"Need to populate at least {needed_size}"
    for _ in range(0, delta):
        ret.append('00000000\n')
    return ret

if __name__ == "__main__":
    import sys
    data = process_file(sys.argv[1], int(sys.argv[3]))
    with open(sys.argv[2], "w") as fd:
        fd.write('\n'.join(data))

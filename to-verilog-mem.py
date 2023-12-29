import sys

with open(sys.argv[1], "rb") as fd:
    data = fd.read()

DEBUG = False
with open(sys.argv[2], "w") as fd:
    for b in data:
        for i in range(7, -1, -1):
            bit = (b & (1 << i)) >> i
            fd.write(str(bit))
        if DEBUG:
            fd.write(f' {hex(b)}')
        fd.write('\n')

    delta = int(sys.argv[3]) - len(data)
    for i in range(0, delta):
        fd.write('00000000\n')

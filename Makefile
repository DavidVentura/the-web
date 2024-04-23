BOARD=tangnano1k
FREQ_MHZ=27
FAMILY=GW1NZ-1
DEVICE=GW1NZ-LV1QN48C6/I5

test:
	./venv/bin/pytest test.py

web.json: src/cpu.v src/wasm.v src/memory.v src/control.v
	yosys -p "read_verilog $^; synth_gowin -top control -json $@" -e "Multiple conflicting drivers for"

web_pnr.json: web.json ${BOARD}.cst
	nextpnr-gowin --json $(filter %.json,$^) --freq ${FREQ_MHZ} --write $@ --device ${DEVICE} --family ${FAMILY} --cst ${BOARD}.cst

web.fs: web_pnr.json
	gowin_pack -d ${FAMILY} -o $@ $^

flash: web.fs
	openFPGALoader -b ${BOARD} $^ -f

flash_mem: web.fs
	openFPGALoader -b ${BOARD} $^ # write to ram

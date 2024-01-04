BOARD=tangnano1k
FREQ_MHZ=27
FAMILY=GW1NZ-1
DEVICE=GW1NZ-LV1QN48C6/I5

programs/wat/00-module.wasm: programs/wat/00-module.wat
	wat2wasm $^ -o $@

programs/00-const/out: programs/00-const/main.c Makefile
	clang \
   --target=wasm32 \
   -O3 \
   -flto \
   -nostdlib \
   -Wl,--entry=entrypoint \
   -o $@ \
   $(filter %.c,$^)

programs/01-adder/out: programs/01-adder/main.c Makefile
	clang \
   --target=wasm32 \
   -O3 \
   -flto \
   -nostdlib \
   -Wl,--entry=entrypoint \
   -o $@ \
   $(filter %.c,$^)
	# -Wl,-z,stack-size=$[1 * 1024 * 1024] \
	# -Wl,--export-all \
	# -Wl,--lto-O3 \

mem_01_adder.txt:
	python3 to-verilog-mem.py 01-adder.wasm mem_01_adder.txt 256

test: src/cpu.v src/wasm.v src/memory.v src/control.v testbench/cpu_tb.v mem_01_adder.txt
	iverilog -DDEBUG=1 $(filter %.v,$^)
	./a.out +TESTNAME=mem_01_adder.txt

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

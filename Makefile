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

test: src/cpu.v testbench/cpu_tb.v mem_01_adder.txt
	iverilog testbench/cpu_tb.v src/cpu.v
	./a.out +TESTNAME=mem_01_adder.txt

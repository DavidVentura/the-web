module control(input clk, input rx_serial, output tx_serial, output rom_mapped, output a, output b);
	wire [31:0] mem_addr;
	wire [7:0] mem_data_in;
	wire [7:0] mem_data_out;
	wire memory_read_en;
	wire memory_write_en;
	wire mem_ready;

	wire [31:0] rom_addr;
	wire [7:0] rom_data_out;
	wire rom_read_en;
	wire rom_ready;

	//wire rom_mapped;
	wire [31:0] first_instruction;

	assign a = first_instruction[3];
	assign b = mem_addr[3];

	wire [7:0] _rom_data_in = 'h0;
	wire _rom_write_en = 0;

	assign tx_serial = clk;

	cpu c(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready, rom_mapped, first_instruction);
	memory m(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);
	// rom r(clk, rom_addr, rom_data_out, rom_read_en, rom_ready);
	// HACK vv
	memory rom(clk, rom_addr, _rom_data_in, rom_data_out, rom_read_en, _rom_write_en, rom_ready);
	wasm w(clk, rom_addr, rom_data_out, rom_read_en, rom_ready, mem_addr, mem_data_in, memory_write_en, rom_mapped, first_instruction);
endmodule

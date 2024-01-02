module rom(
	input clk,
	input [31:0] addr,
	output [7:0] data_out,
	input read_en,
	output ready
);
	// TODO: this caps out at 255
	reg [7:0] mem [0:255];
	reg [7:0] data_out_r;

	reg [31:0] last_addr = 0;

	reg ready_r = 0;
	assign ready = ready_r;
	assign data_out = data_out_r;
	reg [127:0] testname;
	
	initial begin
		if ($value$plusargs("TESTNAME=%s", testname)) begin
			$display("Running test %s", testname);
			$readmemb(testname, mem);
		end else begin
			$display("Need +TESTNAME=mem.txt");
			$finish;
		end
	end

	always @(posedge clk) begin
		if (read_en && addr !== last_addr) begin
			$display("[ROM] Read  %x from %x", mem[addr & 8'hff], addr);
			data_out_r <= mem[addr & 8'hff];
			last_addr <= addr;
			ready_r <= 1;
		end else begin
			ready_r <= 0;
		end
	end
endmodule
module memory(
	input clk,
	input [31:0] addr,
	input [7:0] data_in,
	output [7:0] data_out,
	input memory_read_en,
	input memory_write_en,
	output ready
);
	// TODO: this caps out at 255
	reg [7:0] mem [0:255];
	reg [7:0] data_out_r;

	reg [31:0] last_addr = 0;

	reg ready_r = 0;
	assign ready = ready_r;
	assign data_out = data_out_r;

	always @(posedge clk) begin
		if (memory_read_en && addr !== last_addr) begin
			$display("[MEM] Read  %x from %x", mem[addr & 8'hff], addr);
			data_out_r <= mem[addr & 8'hff];
			last_addr <= addr;
			ready_r <= 1;
		end else begin
			ready_r <= 0;
			if (memory_write_en) begin
				last_addr <= 1'bx;
				$display("[MEM] Wrote %x to   %x", data_in, addr);
				mem[addr & 8'hff] <= data_in;
			end
		end
	end
endmodule

module cpu_tb;
	reg clk = 0;
	always #1 clk <= ~clk;
	wire [31:0] mem_addr2;
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

	wire rom_mapped;
	wire [31:0] first_instruction;

	reg [31:0] mem_addr_r = 32'bz;
	reg memory_read_en_r = 1'bz;

	assign memory_read_en = memory_read_en_r;
	assign mem_addr = mem_addr_r;

	cpu c(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready, rom_mapped, first_instruction);
	memory m(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);
	rom r(clk, rom_addr, rom_data_out, rom_read_en, rom_ready);
	wasm w(clk, rom_addr, rom_data_out, rom_read_en, rom_ready, mem_addr, mem_data_in, memory_write_en, rom_mapped, first_instruction);

	integer fd;
	initial begin
		#400 $finish;
	end
	initial begin
	  $dumpfile("test.vcd");
	  $dumpvars(0, cpu_tb);

	  @(posedge rom_mapped);
	  #10;
	  // Per BOOT.md

	  $display("[%s]: Expected first FTE at 0x30, got 0x%X", (first_instruction != 8'h30) ? "ERROR" : "OK", first_instruction);

	  #80;

	  mem_addr_r <= 8'hAB;
	  memory_read_en_r <= 1;
	  @(posedge mem_ready);
	  $display("[%s] expected 0x1e, got 0x%X", (mem_data_out !== 8'h1E) ? "ERROR": "OK", mem_data_out);
	  #10;
	  $finish;
	end

endmodule

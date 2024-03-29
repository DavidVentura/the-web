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
	reg [255:0] testname;
	
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

module cpu_tb;
	reg clk = 0;
	always #1 clk <= ~clk;
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

	reg [2:0] mem_access_r;
	wire [2:0] mem_access;
	reg cpu_done = 0;

	assign mem_access = mem_access_r;

	always @(posedge clk) begin
		if(cpu_done) begin
			mem_access_r <= 2;
		end else begin
			mem_access_r <=	rom_mapped ? 1 : 0;
		end
	end
	wire wasm_mem_access = mem_access == 0;
	wire cpu_mem_access = mem_access == 1;

	cpu c(clk, cpu_mem_access, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready, rom_mapped, first_instruction);
	memory m(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);
	rom r(clk, rom_addr, rom_data_out, rom_read_en, rom_ready);
	wasm w(clk, rom_addr, rom_data_out, rom_read_en, rom_ready, wasm_mem_access, mem_addr, mem_data_in, memory_write_en, rom_mapped, first_instruction);

	integer fd;
	initial begin
		#800 $finish;
	end

	reg [31:0] pc;
	initial begin
	  $dumpfile("test.vcd");
	  $dumpvars(0, cpu_tb);

	  @(posedge rom_mapped);
	  #10;
	  // Per BOOT.md

	  if($value$plusargs("PC=%x", pc)) begin
		  $display("[%s]: Expected first FTE at 0x%X, got 0x%X", (first_instruction != pc) ? "ERROR" : "OK", pc, first_instruction);
	  end else begin
		  $display("Did not get PC passed");
		  $finish;
	  end

	  #300;
	  cpu_done <= 1;
	  @(posedge clk);

	  mem_addr_r <= 8'hAA;
	  memory_read_en_r <= 1;
	  @(posedge mem_ready);
	  $display("[%s] ADD expected 0x1e, got 0x%X", (mem_data_out !== 8'h1E) ? "ERROR": "OK", mem_data_out);

	  memory_read_en_r <= 0;
	  @(posedge clk);
	  memory_read_en_r <= 1;
	  mem_addr_r <= 16'h604;
	  @(posedge mem_ready);
	  $display("[%s] FTE expected 0x8, got 0x%X", (mem_data_out !== 8'h08) ? "ERROR": "OK", mem_data_out);

	  memory_read_en_r <= 0;
	  @(posedge clk);
	  memory_read_en_r <= 1;
	  mem_addr_r <= 16'h609;
	  @(posedge mem_ready);
	  $display("[%s] FTE expected 0x0, got 0x%X", (mem_data_out !== 8'h00) ? "ERROR": "OK", mem_data_out);
	  #10;
	  $finish;
	end

endmodule

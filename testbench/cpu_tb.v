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
	
	initial begin
	  $readmemb("output.txt", mem);
	end

	always @(posedge clk) begin
		if (memory_read_en && addr !== last_addr) begin
			$display("Read  %x from %x", mem[addr & 8'hff], addr);
			data_out_r <= mem[addr & 8'hff];
			last_addr <= addr;
			ready_r <= 1;
		end else begin
			ready_r <= 0;
			if (memory_write_en) begin
				last_addr <= 1'bx;
				$display("Wrote %x to   %x", data_in, addr);
				mem[addr & 8'hff] <= data_in;
			end
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

	reg [31:0] mem_addr_r = 32'bz;
	reg memory_read_en_r = 1'bz;

	assign memory_read_en = memory_read_en_r;
	assign mem_addr = mem_addr_r;

	cpu c(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);
	memory m(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);

	integer fd;
	initial begin
	  $dumpfile("test.vcd");
	  $dumpvars(0, cpu_tb);
	  #100;
	  mem_addr_r <= 8'hAB;
	  memory_read_en_r <= 1;
	  #1; 
	  @(posedge mem_ready);
	  if (mem_data_out !== 8'h1E) begin
		  $display("ERROR, expected 0x1e, got 0x%X", mem_data_out);
	  end else $display("[OK] expected 0x1e, got 0x%X", mem_data_out);
	  #10;
	  $finish;
	end

endmodule

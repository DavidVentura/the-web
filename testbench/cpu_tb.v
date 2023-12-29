module memory(
	input clk,
	input [31:0] addr,
	input [7:0] data_in,
	output [7:0] data_out,
	input memory_read_en,
	input memory_write_en,
	output ready
);
	reg [7:0] mem [0:99];
	reg [7:0] data_out_r;

	reg ready_r = 0;
	assign ready = ready_r;
	assign data_out = data_out_r;
	
	wire [7:0] mem0;
	wire [15:8] mem1;
	wire [23:16] mem2;
	wire [31:24] mem3;
	wire [39:32] mem4;
	wire [47:40] mem5;

	assign mem0 = mem[0];
	assign mem1 = mem[8];
	assign mem2 = mem[16];
	assign mem3 = mem[24];
	assign mem4 = mem[32];
	assign mem5 = mem[40];

	initial begin
	  $readmemb("output.txt", mem);
	end

	always @(posedge clk) begin
		if (memory_read_en) begin
			data_out_r <= mem[addr];
			ready_r <= 1;
		end else begin
			ready_r <= 0;
			if (memory_write_en) begin
				mem[addr] <= data_in;
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

	cpu c(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);
	memory m(clk, mem_addr, mem_data_in, mem_data_out, memory_read_en, memory_write_en, mem_ready);

	integer fd;
	initial begin
	  $dumpfile("test.vcd");
	  $dumpvars(0, cpu_tb);
	  #100 $finish;
	end

endmodule

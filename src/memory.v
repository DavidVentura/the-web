module memory(
	input clk,
	input [31:0] addr,
	input [7:0] data_in,
	output [7:0] data_out,
	input memory_read_en,
	input memory_write_en,
	output ready
);
	`define debug_print(statement) `ifdef DEBUG $display``statement `endif
	// bram is 18kbit = 2250 byte = 0x8ca
	// this consumes 2 blocks
	reg [7:0] mem [0:2250*2];
	reg [7:0] data_out_r = 'hz;

	reg [31:0] last_addr = 0;

	reg ready_r = 0;
	assign ready = ready_r;
	assign data_out = data_out_r;
	integer i;
	initial begin
		for(i=0; i<255; i=i+1) begin
			mem[i] = i;
		end
	end

	always @(posedge clk) begin
		if (memory_read_en && addr !== last_addr) begin
			`debug_print(("[MEM] Read  %x from %x", mem[addr & 16'hffff], addr));
			data_out_r <= mem[addr & 16'hffff];
			last_addr <= addr;
			ready_r <= 1;
		end else begin
			ready_r <= 0;
			if (memory_write_en) begin
				last_addr <= 1'bz;
				`debug_print(("[MEM] Wrote %x to   %x", data_in, addr));
				mem[addr & 16'hffff] <= data_in;
			end
		end
	end
endmodule



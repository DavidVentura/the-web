module wasm(
    input clk,
	// mem
	output [31:0] addr,
	output [7:0] data_in,
	input  [7:0] data_out,
	output memory_read_en,
	output memory_write_en,
	input memory_ready,

	// module output
	output rom_mapped,
	output [31:0] first_instruction
);

localparam SECTION_TYPE 	= 1;
localparam SECTION_IMPORT 	= 2;
localparam SECTION_FUNCTION = 3;
localparam SECTION_START 	= 8;
localparam SECTION_CODE 	= 10;
localparam SECTION_NOT_READ_YET = 15;

localparam CODE_BASE = 8'h30; // Per BOOT.md

reg [3:0] section = SECTION_NOT_READ_YET;
reg [31:0] wasm_base = 0;
reg [3:0]  state = 0;

// interface to module
reg memory_read_en_r = 0;
assign memory_read_en = memory_read_en_r;
reg [31:0] addr_r;


always @(posedge clk) begin
	case(section)
		SECTION_NOT_READ_YET: begin
			if (memory_ready) begin
				wasm_base <= data_out;
				memory_read_en_r <= 0;
				state <= SECTION_TYPE;
			end else begin
				addr_r <= CODE_BASE;
				memory_read_en_r <= 1;
			end
		end
		SECTION_TYPE: begin
		end
		SECTION_CODE: begin
		end
	endcase
end
endmodule

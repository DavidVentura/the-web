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

localparam SECTION_HALT 	= 0;
localparam SECTION_TYPE 	= 1;
localparam SECTION_IMPORT 	= 2;
localparam SECTION_FUNCTION = 3;
localparam SECTION_START 	= 8;
localparam SECTION_CODE 	= 10;

// FIXME states
localparam S_HALT 				= 0;
localparam S_PRE_READ_SECTION 	= 1;
localparam S_READ_SECTION 		= 2;
localparam S_READ_WASM_MAGIC 	= 3;
localparam S_STARTUP 			= 4;

localparam CODE_BASE = 8'h30; // Per BOOT.md

reg [4:0] state = S_STARTUP;
reg [4:0] section = S_HALT;
reg [4:0] next_section = 1'bz;
reg [4:0] section_len = 1'bz;
reg [31:0] wasm_base = 0;

reg [15:0] current_b = 0; // index into the program
reg [15:0] sec_idx = 0; // index into the section

reg [31:0] first_instruction_r = 0;
assign first_instruction = first_instruction_r;

// interface to module
reg memory_read_en_r = 1'bz;
assign memory_read_en = memory_read_en_r;
reg [31:0] addr_r = 32'bz;
assign addr = addr_r;

reg rom_mapped_r = 0;
assign rom_mapped = rom_mapped_r;

reg [3:0] _leb_byte = 0;
reg [31:0] _leb128 = 0;


always @(posedge clk) begin
	case(state)
		S_STARTUP: begin
			if (memory_ready) begin
				wasm_base <= data_out;
				current_b <= data_out;
				memory_read_en_r <= 0;
				state <= S_READ_WASM_MAGIC;
			end else begin
				addr_r <= CODE_BASE;
				memory_read_en_r <= 1;
			end
		end
		S_READ_WASM_MAGIC: begin
			if (memory_ready) begin
				current_b <= current_b + 1;
				sec_idx <= sec_idx + 1;
				if ((sec_idx+1) == 8) begin
					state <= S_PRE_READ_SECTION;
					sec_idx <= 0;
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
		S_PRE_READ_SECTION: begin
			state <= S_READ_SECTION;
			memory_read_en_r <= 0;
			sec_idx <= 0;
			_leb_byte <= 0;
			section_len <= 0;
			_leb128 <= 0;
		end
		S_READ_SECTION: begin
			if (memory_ready) begin
				current_b <= current_b + 1;
				sec_idx <= sec_idx + 1;
				if (sec_idx == 0) begin
					next_section <= data_out;
				end else begin
					_leb128 <= _leb128 | ((data_out & 8'h7F) << (7 * _leb_byte));
					if ((data_out & 8'h80) != 8'h80) begin
						$display("Finished reading section %x len %x",
								 next_section,
								 _leb128 | ((data_out & 8'h7F) << (7 * _leb_byte)));
						memory_read_en_r <= 0;
						section_len <= _leb128 | ((data_out & 8'h7F) << (7 * _leb_byte));
						section <= next_section;
						sec_idx <= 0;
						_leb_byte <= 0;
						state <= S_HALT;
					end else begin
						_leb_byte <= _leb_byte + 1;
					end
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
		S_HALT: begin
		end
	endcase
end

always @(posedge clk) begin
	case(section)
		SECTION_TYPE: begin
			// TODO: Store type info ??
			if (memory_ready) begin
				current_b <= current_b + 1;
				$display("In Type at %x read %x", sec_idx, data_out);
				if ((sec_idx + 1) == section_len) begin
					state <= S_PRE_READ_SECTION;
					section <= SECTION_HALT;
				end else begin
					sec_idx <= sec_idx + 1;
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
		SECTION_FUNCTION: begin
			if (memory_ready) begin
				current_b <= current_b + 1;
				$display("In Function at %x read %x", sec_idx, data_out);
				if ((sec_idx + 1) == section_len) begin
					state <= S_PRE_READ_SECTION;
					section <= SECTION_HALT;
				end else begin
					sec_idx <= sec_idx + 1;
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
		SECTION_START: begin
			// TODO: store index into func for PC
			if (memory_ready) begin
				current_b <= current_b + 1;
				$display("In Start at %x read %x", sec_idx, data_out);
				if ((sec_idx + 1) == section_len) begin
					state <= S_PRE_READ_SECTION;
					section <= SECTION_HALT;
				end else begin
					sec_idx <= sec_idx + 1;
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
		SECTION_CODE: begin
			// TODO: read types of locals, count, etc
			if (memory_ready) begin
				if (first_instruction_r == 0) begin
					first_instruction_r <= current_b;
					$display("PC should go roughly at %x", current_b);
				end
				current_b <= current_b + 1;
				$display("In Code at %x read %x", sec_idx, data_out);
				if ((sec_idx + 1) == section_len) begin
					state <= S_HALT;
					section <= SECTION_HALT;
					rom_mapped_r <= 1;
				end else begin
					sec_idx <= sec_idx + 1;
				end
			end else begin
				addr_r <= current_b;
				memory_read_en_r <= 1;
			end
		end
	endcase
end
endmodule

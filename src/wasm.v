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

localparam S_HALT 				= 0;
localparam S_PRE_READ_SECTION 	= 1;
localparam S_READ_SECTION 		= 2;
localparam S_READ_WASM_MAGIC 	= 3;
localparam S_STARTUP 			= 4;

// CODE sub-states
localparam READ_FUNC_COUNT 	= 0;
localparam READ_FUNC_LEN    = 1;
localparam READ_BLOCK_COUNT = 2;
localparam READ_LOCAL_COUNT = 3;
localparam READ_LOCAL_TYPE  = 4;
localparam READ_CODE  		= 5;
localparam FINISH_FUNC 		= 6;

// CODE section regs
reg [7:0] func_count = 1'bz;
reg [7:0] curr_func = 1'bz;
reg [7:0] func_len = 1'bz;
reg [7:0] func_start_at = 1'bz;
reg [7:0] local_blocks = 1'bz;
reg [7:0] local_count = 1'bz;
reg [7:0] local_type = 1'bz;
reg [7:0] read_local_blocks = 1'bz;
reg [7:0] read_func = 1'bz;

// LEB
reg leb_done = 0;

localparam CODE_BASE = 8'h30; // Per BOOT.md

reg [4:0] state = S_STARTUP;
reg [4:0] substate = 1'bz;
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
reg [7:0] pc_func_id = 1'bz;


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
						if(next_section == SECTION_CODE) begin
							substate <= READ_FUNC_COUNT;
							_leb128 <= 0;
						end
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
	if (leb_done) begin
		leb_done <= 0;
		_leb128 <= 0;
	end
end
task read_leb128();
	begin
		if (memory_ready) begin
			_leb128 <= _leb128 | ((data_out & 8'h7F) << (7 * _leb_byte));
			current_b <= current_b + 1;
			if ((data_out & 8'h80) != 8'h80) begin
				leb_done <= 1;
				memory_read_en_r <= 0;
			end
		end else begin
			addr_r <= current_b;
			memory_read_en_r <= 1;
		end
	end
endtask

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
			if (memory_ready) begin
				current_b <= current_b + 1;
				$display("In Start at %x read %x", sec_idx, data_out);
				// TODO: Read a LEB128
				pc_func_id <= data_out;
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
			/* Read 1 LEB for func count, per function:
				 1. Read 1 LEB for length
				 2. Read 1 LEB for block#, per local block:
				   2.a. Read 1 LEB for local count
				   2.b. Read 1 LEB for type of the locals
				 3. Read $length (1.) bytes of code
			 */
			if (leb_done || substate == READ_CODE) begin // ugh
				case(substate)
					READ_FUNC_COUNT: begin
						func_count <= _leb128;
						curr_func <= 0;
						read_func <= 0;
						substate <= READ_FUNC_LEN;
					end
					// vv Repeat #func_count
					READ_FUNC_LEN: begin
						func_len <= _leb128;
						func_start_at <= addr_r;
						substate <= READ_BLOCK_COUNT;
					end
					READ_BLOCK_COUNT: begin
						local_blocks <= _leb128;
						substate <= (_leb128 == 0) ? READ_CODE : READ_LOCAL_COUNT;
					end
					// vv Repeat #local_blocks
					READ_LOCAL_COUNT: begin
						local_count <= _leb128;
						read_local_blocks <= 0;
						substate <= READ_LOCAL_TYPE;
					end
					READ_LOCAL_TYPE: begin
						local_type <= _leb128;
						read_local_blocks <= read_local_blocks + 1;
						if ((read_local_blocks + 1) < local_blocks) begin
							substate <= READ_LOCAL_COUNT;
						end else begin
							substate <= READ_CODE;
						end
					end
					READ_CODE: begin
						// TODO: Write
						// 	* In CODE region (0x30, per BOOT.md), each function
						// 	  - Align up to 0x10
						// * In function table
						// 	  - vADDR (32 bit)
						// 	  - local_count * local_blocks (7 bit)
						// 	  - imported (1 bit, always 0)

						if((read_func == pc_func_id) && first_instruction_r == 0) begin
							$display("Code for start at %x", current_b);
							first_instruction_r <= current_b;
						end
						if (current_b == (func_len + func_start_at)) begin
							substate <= FINISH_FUNC;
							memory_read_en_r <= 0;
						end else begin
							if(!memory_ready) begin
								memory_read_en_r <= 1;
								addr_r <= current_b;
							end else begin
								$display("Found code byte %x", data_out);
								current_b <= current_b + 1;
								memory_read_en_r <= 0;
							end
						end
					end
					FINISH_FUNC: begin
						read_func <= read_func + 1;
						if ((read_func + 1) < func_count) begin
							substate <= READ_FUNC_LEN;
						end else begin
							state <= S_HALT;
							section <= SECTION_HALT;
							rom_mapped_r <= 1;
						end
					end
				endcase
			end else begin // !leb_done
				read_leb128();
			end
		end
	endcase
end
endmodule

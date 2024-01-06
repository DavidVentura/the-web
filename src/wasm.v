module wasm(
    input clk,
	// rom
	output [31:0] rom_addr,
	input  [7:0] rom_data_out,
	output rom_read_en,
	input rom_ready,
	// mem
	input mem_access,
	output [31:0] mem_addr,
	output [7:0] mem_data_in,
	output mem_write_en,

	// module output
	output rom_mapped,
	output [31:0] first_instruction
);

`define debug_print(statement) `ifdef DEBUG $display``statement `endif
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

// TYPE sub-states
localparam TYPE_READ_COUNT 		= 0;
localparam TYPE_READ_TYPE_TAG 	= 1;
localparam TYPE_READ_ARG_COUNT 	= 2;
localparam TYPE_READ_ARG_TYPE 	= 3;
localparam TYPE_READ_RET_COUNT 	= 4;
localparam TYPE_READ_RET_TYPE 	= 5;

// FUNCTION sub-states
localparam FUNCTION_READ_COUNT = 0;
localparam FUNCTION_READ_TYPE 	= 1;

`include "src/platform.v"

// CODE section regs
reg [7:0] func_count = 'hz;
reg [7:0] curr_func = 'hz;
reg [7:0] func_len = 'hz;
reg [7:0] func_start_at = 'hz;
reg [7:0] local_blocks = 'hz;
reg [7:0] local_count = 'hz;
reg [7:0] local_type = 'hz;
reg [7:0] read_local_blocks = 'hz;
reg [7:0] read_func = 'hz;
reg [31:0] code_block_base = CODE_BASE;

// LEB
reg leb_done = 0;

reg [4:0] state = S_STARTUP;
reg [4:0] substate = 'hz;
reg [4:0] section = S_HALT;
reg [4:0] next_section = 'hz;
reg [4:0] section_len = 'hz;
reg [31:0] wasm_base = 0;

reg [15:0] current_b = 0; // index into the program
reg [15:0] sec_idx = 0; // index into the section

reg [31:0] first_instruction_r = 0;
assign first_instruction = first_instruction_r;

// interface to module
reg rom_read_en_r = 'hz;
assign rom_read_en = rom_read_en_r;
reg [31:0] rom_addr_r = 'hz;
assign rom_addr = rom_addr_r;

// interface to mem
reg [31:0] mem_addr_r;
reg [7:0] mem_data_in_r;
reg mem_write_en_r;

assign mem_write_en = mem_access ? mem_write_en_r : 'hz;
assign mem_addr = mem_access ? mem_addr_r : 'hz;
assign mem_data_in = mem_access ? mem_data_in_r : 8'hz;

// result
reg rom_mapped_r = 0;
assign rom_mapped = rom_mapped_r;

reg [3:0] _leb_byte = 0;
reg [31:0] _leb128;
reg [7:0] pc_func_id = 'hz;

task read_leb128();
	begin
		if (rom_ready) begin
			_leb128 <= _leb128 | ((rom_data_out & 8'h7F) << (7 * _leb_byte));
			current_b <= current_b + 1;
			if ((rom_data_out & 8'h80) != 8'h80) begin
				leb_done <= 1;
				rom_read_en_r <= 0;
			end
		end else begin
			rom_addr_r <= current_b;
			rom_read_en_r <= 1;
		end
	end
endtask

reg [7:0] type_count;
reg [7:0] type_cur_idx;
reg [7:0] type_arg_count;
reg [7:0] type_arg_cur_idx;
reg [7:0] type_ret_count;
reg [7:0] type_ret_cur_idx;

// Store up to 16 types
// Each of which may have up to 16 arg
reg [3:0] _type_arg_count [0:15];

reg [3:0] func_idx;
task handle_section(); begin
	case(section)
		SECTION_TYPE: begin
			// TODO: Store type info ??
			if (leb_done) begin
				case(substate)
					TYPE_READ_COUNT: begin
						type_count <= _leb128;
						substate <= TYPE_READ_TYPE_TAG;
						type_cur_idx <= 0;
						`debug_print(("%x types", _leb128));
					end
					// vv Repeat #count
					TYPE_READ_TYPE_TAG: begin
						substate <= TYPE_READ_ARG_COUNT;
						`debug_print(("type-tag %x", _leb128));
					end
					TYPE_READ_ARG_COUNT: begin
						`debug_print(("argc %x", _leb128));
						type_arg_count <= _leb128;
						type_arg_cur_idx <= 0;
						_type_arg_count[type_cur_idx] <= _leb128 & 4'hf;
						if(_leb128 > 0) begin
							substate <= TYPE_READ_ARG_TYPE;
						end else begin
							substate <= TYPE_READ_RET_COUNT;
						end
					end
					// -> Repeat #arg-count
					TYPE_READ_ARG_TYPE: begin
						type_arg_cur_idx <= type_arg_cur_idx + 1;
						`debug_print(("type #%x = %x", type_arg_cur_idx + 1, _leb128));
						if ((type_arg_cur_idx + 1) == type_arg_count) begin
							substate <= TYPE_READ_RET_COUNT;
						end
					end
					TYPE_READ_RET_COUNT: begin
						`debug_print(("retc %x", _leb128));
						type_ret_count <= _leb128;
						type_ret_cur_idx <= 0;
						if(_leb128 > 0) begin
							substate <= TYPE_READ_RET_TYPE;
						end else begin
							type_cur_idx <= type_cur_idx + 1;
							if ((type_cur_idx + 1) == type_count) begin
								state <= S_PRE_READ_SECTION;
								section <= SECTION_HALT;
							end else begin
								substate <= TYPE_READ_TYPE_TAG;
							end
						end
					end
					// -> Repeat #ret-count
					TYPE_READ_RET_TYPE: begin
						type_ret_cur_idx <= type_ret_cur_idx + 1;
						`debug_print(("ret-type #%x = %x", type_ret_cur_idx + 1, _leb128));
						if ((type_ret_cur_idx + 1) == type_ret_count) begin
							type_cur_idx <= type_cur_idx + 1;
							if ((type_cur_idx + 1) == type_count) begin
								state <= S_PRE_READ_SECTION;
								section <= SECTION_HALT;
							end else begin
								substate <= TYPE_READ_TYPE_TAG;
								`debug_print(("Arg count at fn #%x = %x", type_cur_idx, _type_arg_count[type_cur_idx]));
							end
						end
					end
				endcase
			end else begin // !leb_done
				read_leb128();
			end
		end
		SECTION_FUNCTION: begin
			if (leb_done) begin
				case(substate)
					FUNCTION_READ_COUNT: begin
						func_count <= _leb128;
						func_idx <= 0;
						substate <= FUNCTION_READ_TYPE;
					end
					FUNCTION_READ_TYPE: begin
						func_idx <= func_idx + 1;
						mem_write_en_r <= 1;
						// We are writing a function table entry, per BOOT.md:
						// 4 bytes address
						// 1 byte of:
						// 	arg count (6) bits
						// 	is-import (1 bit)
						// 	is-service (1-bit)
						//
						// In this section we only know the value of the last
						// byte
						mem_addr_r <= FUNCTION_TABLE_BASE + (func_idx * 5);
						// by virtue of being in SECTION_FUCTION is-import and
						// is-service _must_ be 0, as these are locally
						// defined functions
						// The 6 bits of argc are shifted 2 to the left as 
						// the bottom two bits are [is-import,is-service]
						// which are [0,0]
						mem_data_in_r <= ((_type_arg_count[func_idx] & 6'b111111) << 2);
						if ((func_idx + 1) == func_count) begin
							state <= S_PRE_READ_SECTION;
							section <= SECTION_HALT;
						end
					end
				endcase
			end else begin // !leb_done
				read_leb128();
			end
		end
		SECTION_START: begin
			if (rom_ready) begin
				current_b <= current_b + 1;
				// TODO: Read a LEB128
				pc_func_id <= rom_data_out;
				`debug_print(("Start functon id is %x", rom_data_out));
				if ((sec_idx + 1) == section_len) begin
					state <= S_PRE_READ_SECTION;
					section <= SECTION_HALT;
				end else begin
					sec_idx <= sec_idx + 1;
				end
			end else begin
				rom_addr_r <= current_b;
				rom_read_en_r <= 1;
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
			if (leb_done || (substate == READ_CODE) || (substate == FINISH_FUNC)) begin // ugh
				case(substate)
					READ_FUNC_COUNT: begin
						func_count <= _leb128;
						curr_func <= 0;
						read_func <= 0;
						substate <= READ_FUNC_LEN;
						`debug_print(("There are %x functions", _leb128));
					end
					// vv Repeat #func_count
					READ_FUNC_LEN: begin
						`debug_print(("Func len is %x", _leb128));
						func_len <= _leb128;
						func_start_at <= rom_addr_r;
						substate <= READ_BLOCK_COUNT;
					end
					READ_BLOCK_COUNT: begin
						local_blocks <= _leb128;
						`debug_print(("There are %x local blocks", _leb128));
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
						if ((read_local_blocks + 1) > local_blocks) begin
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

						// TODO: `-2` means "no local blocks" which is not
						// correct
						if((read_func == pc_func_id) && first_instruction_r == 0) begin
							`debug_print(("Starting to read code for START function"));
							first_instruction_r <= code_block_base + (current_b-func_start_at-2); // FIXME -2
						end

						if(!rom_ready) begin
							rom_read_en_r <= 1;
							rom_addr_r <= current_b;
						end else begin
							current_b <= current_b + 1;
							rom_addr_r <= current_b + 1;
							mem_write_en_r <= 1;
							mem_addr_r <= code_block_base + (current_b-func_start_at-2); // FIXME -2
							mem_data_in_r <= rom_data_out & 8'hFF; // FIXME byte?

							if (current_b == (func_len + func_start_at)) begin
								$display("At byte #%x (==%x), func is done", current_b, rom_data_out);
								substate <= FINISH_FUNC;
								rom_read_en_r <= 0;
								code_block_base <= code_block_base + (func_len & 32'hfffffff0) + 16'h10;
							end else begin
								rom_read_en_r <= 1;
							end
						end
					end
					FINISH_FUNC: begin
						mem_write_en_r <= 0;
						read_func <= read_func + 1;
						if ((read_func + 1) < func_count) begin
							`debug_print(("Done reading function"));
							`debug_print(("Next func starts at %x", code_block_base));
							substate <= READ_FUNC_LEN;
						end else begin
							`debug_print(("Done reading all code"));
							state <= S_HALT;
							section <= SECTION_HALT;
							`debug_print(("Finished reading BOOTROM, pc: %x", first_instruction_r));
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
endtask

always @(posedge clk) begin
	case(state)
		S_STARTUP: begin
			if (rom_ready) begin
				wasm_base <= rom_data_out;
				current_b <= rom_data_out;
				rom_read_en_r <= 0;
				state <= S_READ_WASM_MAGIC;
			end else begin
				rom_addr_r <= CODE_BASE;
				rom_read_en_r <= 1;
			end
		end
		S_READ_WASM_MAGIC: begin
			if (rom_ready) begin
				current_b <= current_b + 1;
				sec_idx <= sec_idx + 1;
				if ((sec_idx+1) == 8) begin
					state <= S_PRE_READ_SECTION;
					sec_idx <= 0;
				end
			end else begin
				rom_addr_r <= current_b;
				rom_read_en_r <= 1;
			end
		end
		S_PRE_READ_SECTION: begin
			state <= S_READ_SECTION;
			rom_read_en_r <= 0;
			sec_idx <= 0;
			_leb_byte <= 0;
			section_len <= 0;
			_leb128 <= 0;
		end
		S_READ_SECTION: begin
			if (rom_ready) begin
				current_b <= current_b + 1;
				sec_idx <= sec_idx + 1;
				if (sec_idx == 0) begin
					next_section <= rom_data_out;
				end else begin
					_leb128 <= _leb128 | ((rom_data_out & 8'h7F) << (7 * _leb_byte));
					if ((rom_data_out & 8'h80) != 8'h80) begin
						`debug_print(("[BR] Section %x: len %x",
								 next_section,
								 _leb128 | ((rom_data_out & 8'h7F) << (7 * _leb_byte))));
						rom_read_en_r <= 0;
						section_len <= _leb128 | ((rom_data_out & 8'h7F) << (7 * _leb_byte));
						section <= next_section;
						substate <= TYPE_READ_COUNT;
						_leb128 <= 0;
						sec_idx <= 0;
						_leb_byte <= 0;
						state <= S_HALT;
					end else begin
						_leb_byte <= _leb_byte + 1;
					end
				end
			end else begin
				rom_addr_r <= current_b;
				rom_read_en_r <= 1;
			end
		end
		S_HALT: begin
		end
	endcase

	handle_section();
	if (leb_done) begin
		leb_done <= 0;
		_leb128 <= 0;
	end
end

endmodule

module cpu(
    input clk,
	// mem
	input mem_access,
	output [31:0] addr,
	output [7:0] data_in,
	input  [7:0] data_out,
	output memory_read_en,
	output memory_write_en,
	input memory_ready,

	// wasm parser
	input  rom_mapped,
	input  [31:0] first_instruction
);
	`define dp(statement) `ifdef DEBUG $display``statement `endif
	`define die(statement) `ifdef DEBUG $display``statement; $finish; `endif
	`include "src/platform.v"

	reg [3:0]  state;
	reg [31:0] pc;
	reg [7:0]  instruction;
	reg [63:0] instr_imm;
	reg [63:0] registers [31:0];
	reg [7:0]  needed_operands;
	reg [7:0]  ready_operands;
	reg [63:0] _operand [1:0];

	reg [31:0] pc_for_call;
	reg [2:0] substate;
	reg call_is_import;
	reg call_is_service;

	reg end_of_prog = 0;

	// sub-states for CALL CALC_OPERANDS
	localparam PREP_OPERAND_COUNT 	= 0;
	localparam LOAD_NEW_PC 			= 1;

	reg exec_done;

	reg [7:0]  op_stack_top;
	reg [7:0]  call_stack_top;
	// DEBUG
	wire [7:0] _op_stack_top;
	wire [7:0] _call_stack_top;
	assign _op_stack_top = op_stack_top;
	assign _call_stack_top = call_stack_top;
	wire [63:0] operand1 = _operand[0];
	wire [63:0] operand2 = _operand[1];

	// /DEBUG

	reg [31:0] addr_r;
	reg [7:0] data_in_r;
	reg memory_read_en_r;
	reg memory_write_en_r;

	assign addr = mem_access ? addr_r : 'hz;
	assign data_in = mem_access ? data_in_r : 8'hz;
	assign memory_read_en = mem_access ? memory_read_en_r : 'hz;
	assign memory_write_en = mem_access ? memory_write_en_r : 'hz;

	localparam STATE_BOOTSTRAP 				= 0;
	localparam STATE_BOOTSTRAP_DONE			= 2;
	localparam STATE_FETCH 					= 3;
	localparam STATE_FETCH_WAIT_START 		= 4;
	localparam STATE_FETCH_WAIT_DONE 		= 5;
	localparam STATE_DECODE 				= 6;
	localparam STATE_RETRIEVE 				= 7;
	localparam STATE_LOAD_REG 				= 8;
	localparam STATE_CALC_OPERANDS 			= 9;
	localparam STATE_EXECUTE 				= 10;
	localparam STATE_HALT 					= 11;

	localparam I32_CONST 	= 8'h41;
	localparam CALL 		= 8'h10;
	localparam DROP 		= 8'h1A;
	localparam END_OF_FUNC 	= 8'h0B;
	localparam I32_ADD 		= 8'h6A;
	localparam I32_MUL 		= 8'h6C;
	localparam LOCAL_GET 	= 8'h20;
	localparam LOCAL_SET 	= 8'h21;
	localparam UNREACHABLE  = 8'h00;

	initial begin
		state <= 0;
		pc <= 'hz;
		instruction <= 0;
		instr_imm <= 0;
		needed_operands <= 0;
		ready_operands <= 0;
		exec_done <= 0;
		op_stack_top <= 8'haa;
		call_stack_top <= 8'h55;
	end
	function needs_immediate(input [7:0] inst);
		begin
			case(inst)
				I32_CONST, CALL, LOCAL_GET, LOCAL_SET: begin
					needs_immediate = 1;
				end
			default: begin
					needs_immediate = 0;
				end
			endcase
		end
	endfunction
	function needs_retrieval(input [7:0] inst);
		begin
		end
	endfunction

	function [2:0] operands_for_instr(input [7:0] inst);
		begin
			case(inst)
				END_OF_FUNC, LOCAL_SET, LOCAL_GET, I32_CONST, UNREACHABLE: begin
					operands_for_instr = 0;
				end
				DROP: begin
					operands_for_instr = 1;
				end
				I32_ADD, I32_MUL: begin
					operands_for_instr = 2;
				end
				default: begin
					`die(("No idea how many operands for %x", inst));
				end
			endcase
		end
	endfunction


	task handle_instruction;
		begin
			`dp(("[E] pc=%x", pc));
			case(instruction)
				I32_CONST: begin
					`dp(("[E] i32.const %x", instr_imm));
					op_stack_top <= op_stack_top + 1;
					addr_r <= op_stack_top;
					memory_write_en_r <= 1;
					data_in_r <= instr_imm;
				end
				I32_ADD: begin
					`dp(("[E] i32.add %x %x", _operand[0], _operand[1]));
					addr_r <= op_stack_top - 1;
					memory_write_en_r <= 1;
					data_in_r <= _operand[0] + _operand[1];
					op_stack_top <= op_stack_top - 1;
				end
				CALL: begin
					`dp(("[E] call %x", instr_imm));
					addr_r <= call_stack_top;
					call_stack_top <= call_stack_top + 1;
					memory_write_en_r <= 1;
					data_in_r <= pc;
					pc <= pc_for_call;
					`dp(("[E] new PC %x", pc_for_call));
				end
				DROP: begin
					`dp(("[E] call %x", instr_imm));
					op_stack_top <= op_stack_top - 1;
				end
				LOCAL_GET: begin
					`dp(("[E] local_get #%x = %x", instr_imm, _operand[instr_imm]));
					op_stack_top <= op_stack_top + 1;
					addr_r <= op_stack_top;
					memory_write_en_r <= 1;
					data_in_r <= _operand[instr_imm];
				end
				END_OF_FUNC: begin
					if (call_stack_top == 8'h55) begin // TODO FIXME
						end_of_prog = 1;
						memory_read_en_r <= 0;
						`dp(("[E] EOF end of program"));
					end else begin
						if (memory_ready) begin
							call_stack_top <= call_stack_top - 1;
							pc <= data_out;
							exec_done <= 1;
							`dp(("[E] EOF (RET) to %x", data_out));
						end else begin
							addr_r <= call_stack_top - 1;
							memory_read_en_r <= 1;
							exec_done <= 0;
						end
					end
				end
				UNREACHABLE: begin
					state <= STATE_HALT;
				end
				default: begin
					`die(("No idea how to exec instruction %x", instruction));
				end
			endcase
			if (instruction != END_OF_FUNC) begin
				exec_done <= 1;
			end
		end
	endtask

	reg [3:0] _cur_retr_byte = 0;
	always @(posedge clk) begin
		case(state)
			STATE_BOOTSTRAP: begin
				if (rom_mapped) begin
					`dp(("[CPU] starting"));
					memory_read_en_r <= 0;
					state <= STATE_BOOTSTRAP_DONE;
					pc <= first_instruction;
				end
			end
			STATE_BOOTSTRAP_DONE: begin
				if(!memory_ready) begin
					state <= STATE_FETCH;
				end
			end
			STATE_FETCH: begin
				if (memory_ready) begin
					instruction <= data_out;
					memory_read_en_r <= 0;
					state <= STATE_DECODE;
					pc <= pc + 1;
					instr_imm <= 0;
				end else begin
					memory_write_en_r <= 0;
					addr_r <= pc;
					memory_read_en_r <= 1;
					exec_done <= 0;
				end
			end
			STATE_DECODE: begin
				if(instruction != CALL) begin
					needed_operands <= operands_for_instr(instruction);
					`dp(("For inst %x need #%x ops", instruction, operands_for_instr(instruction)));
				end
				if (needs_immediate(instruction)) begin
					state <= STATE_RETRIEVE;
				end else begin
					// CALL can't fall into this branch as it requires
					// an immediate
					ready_operands <= 0;
					state <= STATE_LOAD_REG;
					memory_read_en_r <= 0;
				end
			end
			STATE_RETRIEVE: begin
				if (memory_ready) begin
					// Ignore highest bit
					instr_imm <= instr_imm | ((data_out & 8'h7F) << (7 * _cur_retr_byte));
					pc <= pc + 1;

					// If highest bit present, continue
					if ((data_out & 8'h80) == 8'h80) begin
						_cur_retr_byte <= _cur_retr_byte + 1;
					end else begin
						`dp(("[E] Retrieved"));
						memory_read_en_r <= 0;
						ready_operands <= 0;
						state <= instruction == CALL ? STATE_CALC_OPERANDS : STATE_LOAD_REG;
						substate <= 0;
					end
				end else begin
					addr_r <= pc;
					memory_read_en_r <= 1;
				end
			end
			STATE_CALC_OPERANDS: begin
				// CALL requires TYPE_TABLE[instr_imm] operands
				case(substate)
					PREP_OPERAND_COUNT: begin
						if(!memory_ready) begin
							// FIXME base lookup
							addr_r <= FUNCTION_TABLE_BASE + (instr_imm * 5) + 4;
							memory_read_en_r <= 1;
						end else begin
							`dp(("Call requires %x ops", data_out >> 2));
							// per BOOT.md
							call_is_import = data_out[1];
							call_is_service = data_out[0];

							needed_operands <= data_out >> 2;
							substate <= LOAD_NEW_PC;
							// FIXME here reading 1 byte before AKA LSB for addr
							addr_r <= FUNCTION_TABLE_BASE + (instr_imm * 5) + 3;
						end
					end
					LOAD_NEW_PC: begin
						// FIXME need 4 bytes
						// FIXME base lookup
						if(memory_ready) begin
							pc_for_call <= data_out;
							`dp(("[E] call jmp into %x", data_out));
							state <= STATE_LOAD_REG;
							memory_read_en_r <= 0;
						end
					end
				endcase
			end
			STATE_LOAD_REG: begin
				if(needed_operands == 0) begin
					state <= STATE_EXECUTE;
					memory_read_en_r <= 0;
				end else begin
					if (memory_ready) begin
						`dp(("Fetghing operand into reg from stack"));
						_operand[needed_operands-ready_operands-1] <= data_out;
						ready_operands <= ready_operands + 1; 
						addr_r <= op_stack_top - (ready_operands+1) - 1;
						if ((ready_operands + 1) == needed_operands) begin
							op_stack_top <= op_stack_top - needed_operands;
							memory_read_en_r <= 0;
							state <= STATE_EXECUTE;
						end
					end else begin
						addr_r <= op_stack_top - ready_operands - 1;
						memory_read_en_r <= 1;
					end
				end
			end
			STATE_EXECUTE: begin
				if (exec_done) begin
					state <= STATE_FETCH;
					instruction <= 0;
				end else if (end_of_prog) begin
					state <= STATE_HALT;
				end else begin
					handle_instruction();
				end
			end
			STATE_HALT: begin
				memory_read_en_r <= 'hz;
				//addr_r <= 'hz;
			end
		endcase
	end
endmodule

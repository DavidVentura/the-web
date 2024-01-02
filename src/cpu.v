module cpu(
    input clk,
	// mem
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


	reg [3:0]  state = 0;
	reg [31:0] pc = 8'hzz;
	reg [7:0]  instruction = 0;
	reg [63:0] instr_imm = 0;
	reg [63:0] registers [31:0];
	reg [7:0]  needed_operands = 0;
	reg [7:0]  ready_operands = 0;
	reg [63:0] _operand [1:0];

	reg exec_done = 0;

	reg [7:0]  op_stack_top = 8'haa;
	reg [7:0]  call_stack_top = 8'h55;
	// DEBUG
	wire [7:0] _op_stack_top;
	wire [7:0] _call_stack_top;
	assign _op_stack_top = op_stack_top;
	assign _call_stack_top = call_stack_top;
	wire [63:0] operand1 = _operand[0];
	wire [63:0] operand2 = _operand[1];

	reg halted = 0;
	// /DEBUG

	reg [31:0] addr_r = 32'bz;
	reg [7:0] data_in_r = 32'bz;
	reg memory_read_en_r = 1'bz;
	reg memory_write_en_r = 1'bz;

	assign addr = addr_r;
	assign data_in = data_in_r;
	assign memory_read_en = memory_read_en_r;
	assign memory_write_en = memory_write_en_r;

	localparam STATE_BOOTSTRAP 				= 0;
	localparam STATE_PARSING_ROM    		= 1;
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
				END_OF_FUNC, LOCAL_SET, I32_CONST, UNREACHABLE: begin
					operands_for_instr = 0;
				end
				DROP, LOCAL_SET: begin
					operands_for_instr = 1;
				end
				I32_ADD, I32_MUL: begin
					operands_for_instr = 2;
				end
				default: begin
					$display("No idea how many operands for %x", inst);
					$finish;
				end
			endcase
		end
	endfunction

	always @(posedge clk) begin
		if(memory_write_en_r) memory_write_en_r <= 0;
	end
	task handle_instruction;
		begin
			case(instruction)
				I32_CONST: begin
					op_stack_top <= op_stack_top + 1;
					addr_r <= op_stack_top;
					memory_write_en_r <= 1;
					data_in_r <= instr_imm;
				end
				I32_ADD: begin
					addr_r <= op_stack_top - 1;
					memory_write_en_r <= 1;
					data_in_r <= _operand[0] + _operand[1];
					op_stack_top <= op_stack_top - 1;
				end
				CALL: begin
					addr_r <= call_stack_top;
					call_stack_top <= call_stack_top + 1;
					memory_write_en_r <= 1;
					data_in_r <= pc;
				end
				DROP: begin
					op_stack_top <= op_stack_top - 1;
				end
				END_OF_FUNC: begin
					// NOP
				end
				UNREACHABLE: begin
					state <= STATE_HALT;
				end
				default: begin
					$display("No idea how to exec instruction %x", instruction);
				end
			endcase
			exec_done <= 1;
		end
	endtask

	always @(posedge clk) begin
		case(state)
			STATE_BOOTSTRAP: begin
				if (rom_mapped) begin
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
		endcase
	end

	reg [3:0] _cur_retr_byte = 0;
	always @(posedge clk) begin
		case(state)
			STATE_FETCH: begin
				if (memory_ready) begin
					instruction <= data_out;
					memory_read_en_r <= 0;
					state <= STATE_DECODE;
					pc <= pc + 1;
					instr_imm <= 0;
				end else begin
					addr_r <= pc;
					memory_read_en_r <= 1;
					exec_done <= 0;
				end
			end
			STATE_DECODE: begin
				if (needs_immediate(instruction)) begin
					state <= STATE_RETRIEVE;
				end else begin
					// CALL can't fall into this branch as it requires
					// an immediate
					ready_operands <= 0;
					state <= STATE_LOAD_REG;
					memory_read_en_r <= 0;
					needed_operands <= operands_for_instr(instruction);
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
						memory_read_en_r <= 0;
						ready_operands <= 0;
						state <= instruction == CALL ? STATE_CALC_OPERANDS : STATE_LOAD_REG;
					end
				end else begin
					addr_r <= pc;
					memory_read_en_r <= 1;
				end
			end
			STATE_CALC_OPERANDS: begin
				// CALL requires $instr_imm operands
				needed_operands <= instr_imm;
				state <= STATE_LOAD_REG;
				memory_read_en_r <= 0;
			end
			STATE_LOAD_REG: begin
				if(needed_operands == 0) begin
					state <= STATE_EXECUTE;
					memory_read_en_r <= 0;
				end else begin
					if (memory_ready) begin
						_operand[needed_operands-ready_operands-1] <= data_out;
						ready_operands <= ready_operands + 1; 
						addr_r <= op_stack_top - (ready_operands+1) - 1;
						if ((ready_operands + 1) == needed_operands) begin
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
				end else begin
					handle_instruction();
				end
			end
			STATE_HALT: begin
				halted <= 1;
				memory_read_en_r <= 1'bz;
				addr_r <= 32'bz;
				data_in_r <= 8'bz;
			end
		endcase
	end
endmodule

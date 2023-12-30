module cpu(
    input clk,
	output [31:0] addr,
	output [7:0] data_in,
	input  [7:0] data_out,
	output memory_read_en,
	output memory_write_en,
	input memory_ready
);
	reg [3:0]  state = 0;
	reg [31:0] pc = 8'h1A;
	reg [7:0]  instruction = 0;
	reg [63:0] instr_imm = 0;
	reg [63:0] registers [31:0];
	reg [7:0]  needed_operands = 0;
	reg [7:0]  ready_operands = 0;
	reg [63:0] _operand [1:0];

	reg exec_done = 0;

	reg [7:0]  op_stack_top = 8'haa;
	reg [7:0]  call_stack_top = 8'h55;
	wire [7:0] _op_stack_top;
	wire [7:0] _call_stack_top;
	// maybe export these as debug wires?
	assign _op_stack_top = op_stack_top;
	assign _call_stack_top = call_stack_top;

	reg [31:0] addr_r;
	reg [7:0] data_in_r = 0;
	reg memory_read_en_r = 0;
	reg memory_write_en_r = 0;

	assign addr = addr_r;
	assign data_in = data_in_r;
	assign memory_read_en = memory_read_en_r;
	assign memory_write_en = memory_write_en_r;

	localparam STATE_FETCH 					= 0;
	localparam STATE_FETCH_WAIT_START 		= 1;
	localparam STATE_FETCH_WAIT_DONE 		= 2;
	localparam STATE_DECODE 				= 3;
	localparam STATE_RETRIEVE 				= 4;
	localparam STATE_RETRIEVE_WAIT_START 	= 5;
	localparam STATE_RETRIEVE_WAIT_DONE 	= 6;
	// load_r1
	// load_r2
	localparam STATE_EXECUTE 				= 7;
	// store result
	localparam STATE_HALT 					= 8;

	localparam I32_CONST 	= 8'H41;
	localparam CALL 		= 8'H10;
	localparam DROP 		= 8'H1A;
	localparam END_OF_FUNC 	= 8'H0B;
	localparam I32_ADD 		= 8'H6A;
	localparam I32_MUL 		= 8'H6C;
	localparam LOCAL_GET 	= 8'H20;
	localparam LOCAL_SET 	= 8'H21;

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

	function operands_for_instr(input [7:0] inst, input[63:0] imm);
		begin
			case(inst)
				END_OF_FUNC, LOCAL_SET: begin
					operands_for_instr = 0;
				end
				I32_CONST, DROP, LOCAL_SET: begin
					operands_for_instr = 1;
				end
				I32_ADD, I32_MUL: begin
					operands_for_instr = 2;
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
					addr_r <= op_stack_top;
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
				default: begin
					$display("No idea how to exec instruction %x", instruction);
				end
			endcase
			exec_done <= 1;
		end
	endtask

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
				end else state <= STATE_EXECUTE;
			end
			STATE_RETRIEVE: begin
				if (memory_ready) begin
					// Ignore highest bit
					instr_imm <= instr_imm | ((data_out & 8'h7F) << (7 * _cur_retr_byte));
					pc <= pc + 1;

					// If highest bit present, continue
					if ((data_out & 8'h80) == 8'h80) begin
						_cur_retr_byte = _cur_retr_byte + 1;
					end else begin
						state <= STATE_EXECUTE;
						memory_read_en_r <= 0;
						needed_operands <= operands_for_instr(instruction, instr_imm);
						ready_operands <= 0;
					end

				end else begin
					addr_r <= pc;
					memory_read_en_r <= 1;
				end
			end
			STATE_EXECUTE: begin
				if (exec_done) begin
					state <= STATE_FETCH;
					instruction <= 0;
				end else begin
					if (ready_operands == needed_operands) begin
						memory_read_en_r <= 0;
						handle_instruction();
					end else begin
						memory_read_en_r <= 1;
						if (memory_ready) begin
							_operand[needed_operands-ready_operands] <= data_out;
							ready_operands <= ready_operands + 1; 
							addr_r <= op_stack_top - (ready_operands+1);
						end else begin
							addr_r <= op_stack_top - ready_operands;
						end
					end
				end
			end
		endcase
	end
endmodule
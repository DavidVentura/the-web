module cpu(
    input clk,
	output [31:0] addr,
	output  [7:0] data_in,
	input [7:0] data_out,
	output memory_read_en,
	output memory_write_en,
	input memory_ready
);
	reg [3:0]  state = 0;
	reg [31:0] pc = 8'h1A;
	reg [7:0]  instruction = 0;
	reg [63:0] instr_imm = 0;
	reg [63:0] op_stack [127:0];
	reg [6:0]  op_stack_top = 0;

	wire [63:0] stack_top = op_stack[op_stack_top];

	reg [63:0] call_stack [127:0];
	reg [6:0]  call_stack_top = 0;

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

	function needs_retrieval(input [7:0] inst);
		begin
			case(inst)
				I32_CONST, CALL, LOCAL_GET, LOCAL_SET: begin
					needs_retrieval = 1;
				end
			default: begin
					needs_retrieval = 0;
				end
			endcase
		end
	endfunction

	always @(posedge clk) begin
		
	end

	task op_stack_pop(output [63:0] val);
		begin
		end
	endtask

	task op_stack_append(input [63:0] val);
		begin
		end
	endtask

	// temporary values while executing instructions
	reg [63:0] _tmp_a = 0;
	reg [63:0] _tmp_b = 0;
	reg [63:0] _tmp_c = 0;
	task handle_instruction;
		begin
			case(instruction)
				I32_CONST: begin
					op_stack_top <= op_stack_top + 1;
					op_stack[op_stack_top+1] <= instr_imm;
				end
				I32_ADD: begin
					// need retrieve stage?
					_tmp_a <= op_stack[op_stack_top];
					_tmp_b <= op_stack[op_stack_top-1];
					//op_stack[op_stack_top-1] <= _tmp_a + _tmp_b;
					op_stack[op_stack_top-1] <= op_stack[op_stack_top] + op_stack[op_stack_top-1];
					op_stack_top <= op_stack_top - 1;
				end
				CALL: begin
					call_stack[call_stack_top] <= pc;
					call_stack_top <= call_stack_top + 1;
				end
			endcase
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
				end
			end
			STATE_DECODE: begin
				if (needs_retrieval(instruction)) begin
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
					end

				end else begin
					addr_r <= pc;
					memory_read_en_r <= 1;
				end
			end
			STATE_EXECUTE: begin
				state <= STATE_FETCH;
				handle_instruction();
			end
		endcase
	end
endmodule

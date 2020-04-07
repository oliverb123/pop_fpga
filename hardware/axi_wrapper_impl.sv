
`timescale 1 ns / 1 ps

//Modified from xilinx-provided template

module axi_wrapper_impl #
(
	// Users to add parameters here

	// User parameters ends
	// Do not modify the parameters beyond this line

	// Width of S_AXI data bus
	parameter integer C_S_AXI_DATA_WIDTH	= 32,
	// Width of S_AXI address bus
	parameter integer C_S_AXI_ADDR_WIDTH	= 4
)
(
	// Users to add ports here

	// User ports ends
	// Do not modify the ports beyond this line

	// Global Clock Signal
	input wire  S_AXI_ACLK,
	// Global Reset Signal. This Signal is Active LOW
	input wire  S_AXI_ARESETN,
	// Write address (issued by master, acceped by Slave)
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
	// Write channel Protection type. This signal indicates the
		// privilege and security level of the transaction, and whether
		// the transaction is a data access or an instruction access.
	input wire [2 : 0] S_AXI_AWPROT,
	// Write address valid. This signal indicates that the master signaling
		// valid write address and control information.
	input wire  S_AXI_AWVALID,
	// Write address ready. This signal indicates that the slave is ready
		// to accept an address and associated control signals.
	output wire  S_AXI_AWREADY,
	// Write data (issued by master, acceped by Slave) 
	input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
	// Write strobes. This signal indicates which byte lanes hold
		// valid data. There is one write strobe bit for each eight
		// bits of the write data bus.    
	input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
	// Write valid. This signal indicates that valid write
		// data and strobes are available.
	input wire  S_AXI_WVALID,
	// Write ready. This signal indicates that the slave
		// can accept the write data.
	output wire  S_AXI_WREADY,
	// Write response. This signal indicates the status
		// of the write transaction.
	output wire [1 : 0] S_AXI_BRESP,
	// Write response valid. This signal indicates that the channel
		// is signaling a valid write response.
	output wire  S_AXI_BVALID,
	// Response ready. This signal indicates that the master
		// can accept a write response.
	input wire  S_AXI_BREADY,
	// Read address (issued by master, acceped by Slave)
	input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
	// Protection type. This signal indicates the privilege
		// and security level of the transaction, and whether the
		// transaction is a data access or an instruction access.
	input wire [2 : 0] S_AXI_ARPROT,
	// Read address valid. This signal indicates that the channel
		// is signaling valid read address and control information.
	input wire  S_AXI_ARVALID,
	// Read address ready. This signal indicates that the slave is
		// ready to accept an address and associated control signals.
	output wire  S_AXI_ARREADY,
	// Read data (issued by slave)
	output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
	// Read response. This signal indicates the status of the
		// read transfer.
	output wire [1 : 0] S_AXI_RRESP,
	// Read valid. This signal indicates that the channel is
		// signaling the required read data.
	output wire  S_AXI_RVALID,
	// Read ready. This signal indicates that the master can
		// accept the read data and response information.
	input wire  S_AXI_RREADY
);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;//Set by master, 4 bits wide, indicates 32 bit register to write to. Updated on axi_awready + others
	reg  	axi_awready;//Controlled by slave, indicates ready to receive write address
	reg  	axi_wready;//Controlled by slave, indicates ready to receive write data
	reg [1 : 0] 	axi_bresp;//Controlled by slave, response signal to request, should always be 2'b00
	reg  	axi_bvalid;//Controlled by slave, indicates response signal is valid for last transaction
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;//Set by master, 4 bits wide, indicates 32 bit register to read from. Updated on axi_arready + others
	reg  	axi_arready;//Contolled by slave, slave is ready to receive read address
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;//Set by slave, data read as a result of read transaction, latched on arready
	reg [1 : 0] 	axi_rresp;//Same as bresp, generally 0, transaction status signal
	reg  	axi_rvalid;//Controlled by slave, indicates data on axi_rdata is valid

	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 1;

	wire [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;//Output "register", actuall just maps to max_len and max_pos registers from prefix finder

	// I/O Connections assignments
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;

//internal signals:
	wire[7:0] byte_in = S_AXI_WDATA[7:0];
//Push the received byte if it's valid and we're ready to
	wire push = axi_wready && S_AXI_WVALID && S_AXI_WSTRB[0];
//Start a search if one if being requested and we're not doing something else
	wire search = axi_arready && S_AXI_ARVALID;
//Map output "register" to output registers from prefix finder
	wire [3:0] max_len;
	wire [11:0] max_pos;
	assign slv_reg1 = {16'h00000000, max_len, max_pos};
//Reset if the bus is being reset or
//the master is validly driving a reset command (setting bit nine in wdata)
	wire reset_core = ~S_AXI_ARESETN || (S_AXI_WVALID && S_AXI_WDATA[8] && S_AXI_WSTRB[1]);

//Register to track whether our most recent valid result has
//been read yet
	reg read_requested;

//Core status signals
	wire busy, waiting, res_valid;

	max_prefix mp(S_AXI_ACLK,
				 reset_core,
				 push,
				 search,
				 byte_in,
				 waiting,
				 busy,
				 res_valid,
				 max_pos,
				 max_len);

	initial begin//Iniitial state is identical to reset state
		axi_awready <= 1'b0;
		axi_wready <= 1'b0;
		axi_bresp <= 2'b0;
		axi_bvalid <= 1'b0;
		axi_arready <= 1'b0;
		axi_rdata <= 0;
		axi_rresp <= 2'b0;
		axi_rvalid <= 1'b0;
		read_requested <= 1'b0;
	end

	always@(posedge S_AXI_ACLK) begin
		//We don't care about these, so always set them
		axi_awaddr <= S_AXI_AWADDR;
		axi_araddr <= S_AXI_ARADDR;
		if(~S_AXI_ARESETN) begin
			axi_awready <= 1'b0;
			axi_wready <= 1'b0;
			axi_bresp <= 2'b0;
			axi_bvalid <= 1'b0;
			axi_arready <= 1'b0;
			axi_rdata <= 0;
			axi_rresp <= 2'b0;
			axi_rvalid <= 1'b0;
			read_requested <= 1'b0;
		end else begin
//We're always ready to receive a new write address, since you can only write to 1 register
			axi_awready <= 1'b1;
//Accept a new write when we're not busy or waiting on a read
			axi_wready <= !busy;
			axi_bresp <= 2'b0;//Axi-lite forbids slave failure
			axi_bvalid <= axi_wready && S_AXI_WVALID;//Our write response is valid when we're pushing
//We're ready for a new read request when we aren't pushing or handling one already
			axi_arready <= !busy && !push;
			axi_rresp <= 1'b0;//Axi-lite forbids slave failure
//A read has been requested when we're getting a request,
//we're able to receive it and we can't immediately fulfil,
//either because we don't have an answer or because they're not ready
//to receive the answer
			if(axi_arready && S_AXI_ARVALID && (!res_valid || !S_AXI_RREADY)) begin
				read_requested <= 1'b1;
			end
//Handling read data channel updates
//If we have a valid result that hasn't been read yet
			if(res_valid && (read_requested || (axi_arready && S_AXI_ARVALID && S_AXI_RREADY))) begin
//Start outputting the valid result
				axi_rvalid <= 1'b1;
				axi_rdata <= slv_reg1;
//And mark read requested false once they can receive it
				read_requested <= !S_AXI_RREADY;
			end else begin
				axi_rvalid <= 1'b0;
			end
		end
	end

endmodule

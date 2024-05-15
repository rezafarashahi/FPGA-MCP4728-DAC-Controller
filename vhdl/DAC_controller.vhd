--------------------------------------------------------------------------------
--
--   FileName:         DAC_controller.vhd
--   Dependencies:     none
--   Design Software:  Quartus Prime Lite Edition
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 16/05/2024 Reza Farashahi
--     Initial Public Release
-- 
--------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity DAC_controller is
	Generic (slave_addr : std_logic_vector(6 downto 0) := "1100000"); --DAC (MCP4728) Address
	Port (
        clock           : in  std_logic;
        uart_rx         : in  std_logic;
		  
		  oSDA 				: inout STD_LOGIC;
		  oSCL 				: inout STD_LOGIC;
		  ldac				: out	  STD_LOGIC;
			  
		  led_vector      : out std_logic_vector(7 downto 0)
			);
			
end DAC_controller;





architecture Behavioral of DAC_controller is

	component uart is
		 generic (
			  baud                : positive;
			  clock_frequency     : positive
		 );
		 port (  
			  clock               :   in  std_logic;
			  reset               :   in  std_logic;    
			  data_stream_in      :   in  std_logic_vector(7 downto 0);
			  data_stream_in_stb  :   in  std_logic;
			  data_stream_in_ack  :   out std_logic;
			  data_stream_out     :   out std_logic_vector(7 downto 0);
			  data_stream_out_stb :   out std_logic;
			  tx                  :   out std_logic;
			  rx                  :   in  std_logic
		 );
	end component ;
	
	
	component i2c_master IS
	GENERIC(
	 input_clk : INTEGER := 50_000_000; --input clock speed from user logic in Hz
	 bus_clk   : INTEGER := 400_000);   --speed the i2c bus (scl) will run at in Hz
	PORT(
	 clk       : IN     STD_LOGIC;                    --system clock
	 reset_n   : IN     STD_LOGIC;                    --active low reset
	 ena       : IN     STD_LOGIC;                    --latch in command
	 addr      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0); --address of target slave
	 rw        : IN     STD_LOGIC;                    --'0' is write, '1' is read
	 data_wr   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0); --data to write to slave
	 busy      : OUT    STD_LOGIC;                    --indicates transaction in progress
	 data_rd   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0); --data read from slave
	 ack_error : BUFFER STD_LOGIC;                    --flag if improper acknowledge from slave
	 sda       : INOUT  STD_LOGIC;                    --serial data output of i2c bus
	 scl       : INOUT  STD_LOGIC);                   --serial clock output of i2c bus
	END component i2c_master;

	signal uart_data_out     : std_logic_vector(7 downto 0);
	signal reg_uart_data_out     : std_logic_vector(7 downto 0);
	signal uart_data_out_stb : std_logic;
	signal reg_uart_data_out_stb : std_logic;
	signal uart_data_in_ack  : std_logic := '0';
	signal rx, rx_sync, reset_sync, reset_user : std_logic;
	signal reset : std_logic := '1';
	
	signal regBusy,sigBusy,reset_i2c,enable,readwrite, nack, regNack : std_logic;
	signal dataOut : std_logic_vector(7 downto 0);
	
	
	signal byteChoice : integer := 1;
	signal byteChoiceMax : integer := 12; 
	
	
	signal initialCount : integer := 0;
	type state_type is (start,write,stop);
	signal State : state_type := start;
	signal address : std_logic_vector(6 downto 0);
	signal Cnt : integer := 16383;
	signal nack_counter 	: std_logic_vector(7 downto 0) := (others => '0');
	
	
	signal sig_led_vector : std_logic_vector(7 downto 0);
	signal dac_cnt : integer := 1;
	
	signal dataIn : std_logic_vector(95 downto 0) := b"01000001" &
																	 b"00001111" &
																	 b"11111111" &
																	 b"01000011" &
																	 b"00001111" &
																	 b"11111111" &
																	 b"01000101" &
																	 b"00001111" &
																	 b"11111111" &
																	 b"01000111" &
																	 b"00001111" &
																	 b"11111111";
	signal new_uart_data : std_logic := '0';
	
	-- Signal to accumulate received bytes and a counter to keep track of them
	signal byte_count : integer range 0 to 11 := 0; -- Tracks the number of bytes received

	-- Signal to indicate new data reception complete
	signal new_data_received : std_logic := '0';
	
begin
	
	uart_instance : uart
	  generic map (
			baud            => 115200,  -- Adjust as needed
			clock_frequency => 50_000_000  -- Adjust as needed
	  )
	  port map (
			clock               => clock,
			reset               => reset_user,
			data_stream_in      => (others => '0'), -- Not used in this scenario
			data_stream_in_stb  => '0',  -- Not used in this scenario
			data_stream_in_ack  => open, -- Not used in this scenario
			data_stream_out     => uart_data_out,
			data_stream_out_stb => uart_data_out_stb,
			tx                  => open, -- If not transmitting data
			rx                  => rx
	  );
	  
	output: i2c_master
		port map (
			 clk						=>	clock,
			 reset_n					=>	reset_i2c,
			 ena						=>	enable,
			 addr						=>	address,
			 rw						=>	readwrite,
			 data_wr					=>	dataOut,
			 busy						=>	sigBusy,
			 data_rd					=>	OPEN,
			 ack_error				=>	nack,
			 sda						=>	oSDA,
			 scl						=>	oSCL);
	  
	
		deglitch : process (clock)
	begin
	  if rising_edge(clock) then
			rx_sync         <= uart_rx;
			rx              <= rx_sync;
			reset_sync      <= not reset;
			reset_user      <= reset_sync;
	  end if;
	end process;
	




	-- Inside UART receive process
	process(clock)
	begin
		 if rising_edge(clock) then
			  if uart_data_out_stb = '1' then
					-- Store each byte received into dataIn
					case byte_count is
						 when 0 =>
							  dataIn(7 downto 0) <= uart_data_out;
						 when 1 =>
							  dataIn(15 downto 8) <= uart_data_out;
						 when 2 =>
							  dataIn(23 downto 16) <= uart_data_out;
						 when 3 =>
							  dataIn(31 downto 24) <= uart_data_out;
						 when 4 =>
							  dataIn(39 downto 32) <= uart_data_out;
						 when 5 =>
							  dataIn(47 downto 40) <= uart_data_out;
						 when 6 =>
							  dataIn(55 downto 48) <= uart_data_out;
						 when 7 =>
							  dataIn(63 downto 56) <= uart_data_out;
						 when 8 =>
							  dataIn(71 downto 64) <= uart_data_out;
						 when 9 =>
							  dataIn(79 downto 72) <= uart_data_out;
						 when 10 =>
							  dataIn(87 downto 80) <= uart_data_out;
						 when 11 =>
							  dataIn(95 downto 88) <= uart_data_out;
							  new_data_received <= '1';  -- Indicate that all bytes have been received
							  
						 when others =>
							  null;
					end case;
					-- Increment the byte counter or reset if 48-bit data is complete
					if byte_count < 11 then
						 byte_count <= byte_count + 1;
					else
						 byte_count <= 0;
					end if;
			  else
					if new_data_received = '1' then
						 -- Reset the new_data_received flag after it has been processed
						 new_data_received <= '0';
					end if;
			  end if;
		 end if;
	end process;

	
	
	StateChange: process (Clock)
	begin
		if rising_edge(Clock) then
			case State is
				when start =>
				ldac <= '1';
				if Cnt /= 0 then
					Cnt<=Cnt-1;
					reset_i2c<='0';
					State<=start;
					enable<='0';
				else
					reset_i2c<='1';
					enable<='1';
					address<=slave_addr;
					readwrite<='0';
					State<=write;
				end if;
				
				when write=>
				regBusy<=sigBusy;
				if regBusy/=sigBusy and sigBusy='0' then
					if byteChoice /= byteChoiceMax then
						byteChoice<=byteChoice+1;
						State<=write;
					else
						byteChoice<=byteChoiceMax;
						State<=stop;
					end if;
				end if;
				
				when stop=>
				enable<='0';
				ldac <= '0';
				if new_data_received = '1' then
					State<=start;
					byteChoice <= 1;
				else
					State<=stop;
				end if;
			end case;
		end if;
	end process;

	process(byteChoice, clock)
	begin
		 case byteChoice is
			  when 1 => dataOut <= dataIn(95 downto 88);
			  when 2 => dataOut <= dataIn(87 downto 80);
			  when 3 => dataOut <= dataIn(79 downto 72);
			  when 4 => dataOut <= dataIn(71 downto 64);
			  when 5 => dataOut <= dataIn(63 downto 56);
			  when 6 => dataOut <= dataIn(55 downto 48);
			  when 7 => dataOut <= dataIn(47 downto 40);
			  when 8 => dataOut <= dataIn(39 downto 32);
			  when 9 => dataOut <= dataIn(31 downto 24);
			  when 10 => dataOut <= dataIn(23 downto 16);
			  when 11 => dataOut <= dataIn(15 downto 8);
			  when 12 => dataOut <= dataIn(7 downto 0);
			  when others => dataOut <= x"FF";
		 end case;
	end process;


	
	
	led_vector <= dataIn(31 downto 24);
	
end Behavioral;
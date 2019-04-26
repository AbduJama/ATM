
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
-- DE10 Lite has 50MHz Clock for USB Blaster
-- About 20ns per cycle --
-- 1 second is about 50,000,000 cycles but since Timer Clock is 50% Duty  --
-- 25,000,000 cycles for on "1" and 25,000,000 cycles for off "0"

entity ATM is
port ( userinput : in std_logic_vector(2 downto 0); -- User Input
			pb0 : in std_logic;     -- Asynchronous user input enable
			pb1 : in std_logic;     -- Full state reset after service
			clk :  in std_logic;     --System clock
			seven_seg_6 : out std_logic_vector(7 downto 0);  -- read from left to right
			seven_seg_5 : out std_logic_vector(7 downto 0);  -- HELLO, ACC.NO, PASSCO, ERROR
			seven_seg_4 : out std_logic_vector(7 downto 0);  -- Output: Username and Balance (D.09)
			seven_seg_3 : out std_logic_vector(7 downto 0);
			seven_seg_2 : out std_logic_vector(7 downto 0);
			seven_seg_1 : out std_logic_vector(7 downto 0)
);
end ATM;


architecture sequential of ATM is

-- List of Letter Constants for Hex Display HERE --
-- Hex Display of 0 to F
constant D0 : std_logic_vector(7 downto 0):="11000000";
constant D1 : std_logic_vector(7 downto 0):="11111001";
constant D2 : std_logic_vector(7 downto 0):="10100100";
constant D3 : std_logic_vector(7 downto 0):="10110000";
constant D4 : std_logic_vector(7 downto 0):="10011001";
constant D5 : std_logic_vector(7 downto 0):="10010010";  --This is also "S" display
constant D6 : std_logic_vector(7 downto 0):="10000010";	--This is also "G" display
constant D7 : std_logic_vector(7 downto 0):="11111000";
constant D8 : std_logic_vector(7 downto 0):="10000000";
constant D9 : std_logic_vector(7 downto 0):="10010000";
constant DA : std_logic_vector(7 downto 0):="10001000";
constant DB : std_logic_vector(7 downto 0):="10000011";
constant DC : std_logic_vector(7 downto 0):="11000110";
constant DD : std_logic_vector(7 downto 0):="10100001";
constant DE : std_logic_vector(7 downto 0):="10000110";
constant DF : std_logic_vector(7 downto 0):="10001110";
-- Other Letters -- 
constant DH : std_logic_vector(7 downto 0):="10001001";
constant DL : std_logic_vector(7 downto 0):="11000111";
constant DN : std_logic_vector(7 downto 0):="11001000";
constant DP : std_logic_vector(7 downto 0):="10001100";
constant DR : std_logic_vector(7 downto 0):="10001000";
constant DV : std_logic_vector(7 downto 0):= "11000001";
constant Dfhalf_W : std_logic_vector(7 downto 0):="11000011";
constant Dshalf_W : std_logic_vector(7 downto 0):="11100001";
constant Dpoint : std_logic_vector(7 downto 0):="01111111";
constant Doff : std_logic_vector(7 downto 0) := "11111111";


signal ss6 : std_logic_vector(7 downto 0);
signal ss5 : std_logic_vector(7 downto 0);
signal ss4 : std_logic_vector(7 downto 0);
signal ss3 : std_logic_vector(7 downto 0);
signal ss2 : std_logic_vector(7 downto 0);
signal ss1 : std_logic_vector(7 downto 0);
signal divided_clk : std_logic := '0';  -- important to initialize value for ModelSim


type state_type is (sS, s0, s1, s2, s3, s4, s5, s6, s7, s8, sX);
signal state : state_type ;  --initializing state to s0
signal previous_state : state_type ; --In some cases, knowledge of the previous state is desired (see S5 or S6)

signal current_user : std_logic_vector(10 downto 0);
signal passcode : std_logic_vector(2 downto 0); --passcode of current user
signal balance : std_logic_vector(7 downto 0);  --Account balance of current user in session
signal username : std_logic_vector(2 downto 0);
signal upper_BCD, lower_BCD : std_logic_vector(3 downto 0);

-- For Account Balance Hex Display --
signal user : std_logic_vector(7 downto 0);
signal tens_digit : std_logic_vector(7 downto 0);
signal ones_digit : std_logic_vector(7 downto 0);

-- Handle button has Edge detection --
signal past_pb0 : std_logic;
signal event_pb0 : std_logic;

type memory_type is array (0 to 6) of std_logic_vector(10 downto 0);
signal RAM : memory_type := ("001"& X"00", "010"& X"00", "011"& X"00", "100"& X"00", "101"& X"00", "110"& X"00", "111"& X"00");

signal timer_4sec : integer  := 0;
signal timer_3sec : integer := 0;
signal timer_2sec : integer := 0;
signal timer_1min : integer := 0;

begin
-----------------------------------------------------
clock_divider: process (clk)
variable clk_count: integer:=0;
begin
if(clk'event and clk = '1') then
-- for simulation replace 25000000 with smaller number such as 2 or 4 to minimize simulation time
  if clk_count = 25000000 then
    divided_clk <= not divided_clk;
	 
	if (state = s0 and timer_4sec <= 8) then
		timer_4sec <= timer_4sec + 1;
	else
		timer_4sec <= 0;
	end if;
	
	if (state = s8 and timer_3sec <= 6) then
		timer_3sec <= timer_3sec + 1;
	else
		timer_3sec <= 0;
	end if;
	
	if (state = sX and timer_2sec <= 4) then
		timer_2sec <= timer_2sec + 1;
	else
		timer_2sec <= 0;
	end if;
	
	if ((state = s1 or state = s3) and timer_1min <= 120) then
		timer_1min <= timer_1min + 1;
	elsif (state = s2) then
		timer_1min <= 0;
	else
		timer_1min <= 0;
	end if;
	 
    clk_count := 0;
  else
    clk_count := clk_count + 1;
  end if;
end if;
end process;
-----------------------------------------------------

ATM_Response: process(clk,pb1)
variable address : integer ;
variable passcode_chance : integer := 0;
variable tens, ones, int_result : integer := 0 ;
begin
	if (pb1 = '0') then --The reset button
		state <= s0;
	elsif (rising_edge(clk)) then
		past_pb0 <= pb0;
		case state is
		
			when s0=>
				if (timer_4sec >= 8) then
					state <= s1;
				else
					state <= s0; 
				end if;
				
			when s1 =>
				-- ACC.NO is Displayed in s1 state --
				if (event_pb0 = '1' and userinput /= "000") then
					address := to_integer(unsigned(userinput)) - 1;
					current_user <= RAM(address);
					username <= userinput;
					state <= s2;
				elsif (timer_1min >= 120) then
					state <= s0;
				else
					state <= s1;
				end if;
				
			when s2 =>
				passcode <= current_user (10 downto 8); 
				balance <= current_user (7 downto 0);
				--timer_1min <= 0;
				if (timer_1min = 0) then
					state <= s3;
				end if;
				
			when s3 =>
				-- PASSCO is Displayed in s1 state --
				if (passcode_chance = 2) then
					passcode_chance := 0;
					state <= sX;
				elsif (timer_1min >= 120) then
					passcode_chance := 0;
					state <= s0;
				else
					if (event_pb0 = '1' and userinput /= "000") then
						if (userinput = passcode ) then   --In here we do comparison with password stored in memory -- 
							passcode_chance := 0;
							state <= s4;
						elsif (userinput /=  passcode ) then
							passcode_chance := passcode_chance + 1;
							state <= s3;
						end if;
					end if;
				end if;
	
	
			when s4 => 
				--Select Withdrawl or Deposit (W-0 D-1) --
				if (event_pb0 = '1' and userinput(0) = '1') then
					state <= s5;
				elsif (event_pb0 = '1' and userinput(0) = '0') then
					state <= s6;
				end if;

-------------------------------------------------------------------------------			
			when s5 =>
				-- VALUE For enter  value (Deposit is 1) --
				if (event_pb0 = '1' and userinput /= "000") then
					int_result := to_integer(unsigned(balance)) + to_integer(unsigned(userinput));
					if (int_result > 99) then
						previous_state <= s5;
						state <= sX;
					else
						tens := int_result / 10;
						ones := int_result rem 10;
						upper_BCD <= std_logic_vector(to_unsigned(tens,4));
						lower_BCD <= std_logic_vector(to_unsigned(ones,4));
						RAM(address) <= passcode & (std_logic_vector(to_unsigned(int_result,8)));
						state <= s7;
					end if;
				end if;
						
			
			when s6 =>
			-- VALUE For enter  value (Withdrawal is 0) --
				if (event_pb0 = '1' and userinput /= "000") then
					if (balance < userinput) then
						previous_state <= s6;
						upper_BCD <= std_logic_vector(to_unsigned(tens,4));
						lower_BCD <= std_logic_vector(to_unsigned(ones,4));
						state <= sX;
					else
						int_result := to_integer(unsigned(balance)) - to_integer(unsigned(userinput));
						tens := int_result / 10;
						ones := int_result rem 10;
						upper_BCD <= std_logic_vector(to_unsigned(tens,4));
						lower_BCD <= std_logic_vector(to_unsigned(ones,4));
						RAM(address) <= passcode & (std_logic_vector(to_unsigned(int_result,8)));
						state <= s7;
					end if;
				end if;
				
			when s7 =>
			
				case username is 
					when "001" => user <= DA;
					when "010" => user <= DB;
					when "011" => user <= DC;
					when "100" => user <= DD;
					when "101" => user <= DE;
					when "110" => user <= DF;
					when "111" => user <= D6;
					when others => user <= Doff;
				end case;
					
				case upper_BCD is
					when "1001" => tens_digit <= D9;
					when "1000" => tens_digit <= D8;
					when "0111" => tens_digit <= D7;
					when "0110" => tens_digit <= D6;
					when "0101" => tens_digit <= D5;
					when "0100" => tens_digit <= D4;
					when "0011" => tens_digit <= D3;
					when "0010" => tens_digit <= D2;
					when "0001" => tens_digit <= D1;
					when "0000" => tens_digit <= D0;
					when others => tens_digit <= Doff;
				end case;
				
				case lower_BCD is
					when "1001" => ones_digit <= D9;
					when "1000" => ones_digit <= D8;
					when "0111" => ones_digit <= D7;
					when "0110" => ones_digit <= D6;
					when "0101" => ones_digit <= D5;
					when "0100" => ones_digit <= D4;
					when "0011" => ones_digit <= D3;
					when "0010" => ones_digit <= D2;
					when "0001" => ones_digit <= D1;
					when "0000" => ones_digit <= D0;
					when others => ones_digit <= Doff;
				end case;
				
				state <= s8;
				
			when s8 =>
				if (timer_3sec >= 6) then
					state <= s0;
				else
					state <= s8;
				end if;
				
				
			when sX =>
				if (timer_2sec >= 4) then
				-- look at previous state here to see if error came from withdrawl or depsoit so the amount can be shown then go to s0 (HELLO) --
					if (previous_state = s5) then
						previous_state <= s0;  -- resetting the previous state checker
						state <= s8;
					elsif (previous_state = s6) then
						previous_state <= s0;  -- resetting the previous state checker
						state <= s7;
					else
						state <= s0;
					end if;
				else
					state <= sX;
				end if;
-------------------------------------------------------------------------------				
				
			when others =>
				state <= s0;

		end case;
	end if;
	event_pb0 <= pb0 and not past_pb0;
end process;


ATM_Display: process(clk)
-- At any point in time, the Display will hafve some textual information shown -- 
begin
	if (rising_edge(clk)) then
		case state is
		
			when s0 =>
			-- HELLO Display --
				ss6 <= DH;
				ss5 <= DE;
				ss4 <= DL;
				ss3 <= DL;
				ss2 <= D0;
				ss1 <= Doff;
				
			when s1 =>
			-- ACC.NO Display --
				ss6 <= DA;
				ss5 <= DC;
				ss4 <= DC;
				ss3 <= Dpoint;
				ss2 <= DN;
				ss1 <= D0;
				
			when s3 =>
			-- PASSCO Display --
				ss6 <= DP;
				ss5 <= DA;
				ss4 <= D5;
				ss3 <= D5;
				ss2 <= DC;
				ss1 <= D0;
				
			when s4 =>
			-- W-0 D-1 Display --
				ss6 <= Dfhalf_W;
				ss5 <= Dshalf_W;
				ss4 <= D0;
				ss3 <= Doff;
				ss2 <= DD;
				ss1 <= D1;
			
			when s5 =>
			-- VALUE Display --
				ss6 <= DV;
				ss5 <= DA;
				ss4 <= DL;
				ss3 <= DV;
				ss2 <= DE;
				ss1 <= D1;
				
			when s6 =>
			-- VALUE Display --
				ss6 <= DV;
				ss5 <= DA;
				ss4 <= DL;
				ss3 <= DV;
				ss2 <= DE;
				ss1 <= D0;
			
			when s8 =>
			-- Display the amount in account --
				ss6 <= user;
				ss5 <= Dpoint;
				ss4 <= tens_digit;
				ss3 <= ones_digit;
				ss2 <= Doff;
				ss1 <= Doff;
			
			when sX =>
			-- VALUE Display --
				ss6 <= DE;
				ss5 <= DR;
				ss4 <= DR;
				ss3 <= D0;
				ss2 <= DR;
				ss1 <= Doff;
			
			when others =>
				-- Display all lights off --
				ss6 <= Doff;
				ss5 <= Doff;
				ss4 <= Doff;
				ss3 <= Doff;
				ss2 <= Doff;
				ss1 <= Doff;
				
		end case;
	end if;
end process;



seven_seg_6 <= ss6;
seven_seg_5 <= ss5;
seven_seg_4 <= ss4;
seven_seg_3 <= ss3;
seven_seg_2 <= ss2;
seven_seg_1 <= ss1;

end architecture sequential;



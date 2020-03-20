library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.kernel_pkg;

-- Implementation of a 3x3 Convolutional Kernel where only weights which are powers of 2 are valid
-- All multiplications have been replaced by Shift Operations
entity ShiftKernel3x3 is
	generic
	(
		BIT_WIDTH_IN : NATURAL := 8;
		BIT_WIDTH_OUT : NATURAL := 20;
		WEIGHT_SHIFTS : work.kernel_pkg.conv_kernel_3x3_weight_shift_t := (0, 0, 0, 0, 0, 0, 0, 0, 0);
		WEIGHT_SIGNS : work.kernel_pkg.conv_kernel_3x3_weight_sign_t := ('0', '0', '0', '0', '0', '0', '0', '0', '0');
		WEIGHT_WIDTH : NATURAL := 8;
	);
	port
	(
		Clk_i : in std_logic;
		n_Res_i : in std_logic;
		Valid_i : in std_logic;
		X_i : in std_logic_vector(BIT_WIDTH_IN * KERNEL_SIZE - 1 downto 0); -- input vector
		Y_o : out signed(BIT_WIDTH_OUT - 1 downto 0)	-- output value
	);
end Kernel3x3;

architecture beh of ShiftKernel3x3 is
begin
	sync : process (Clk_i, n_Res_i)
	
		type Mult_output_array is array (KERNEL_SIZE - 1 downto 0) of signed(BIT_WIDTH_OUT downto 0);
		variable M_out : Mult_output_array;
		

		variable temp : signed(BIT_WIDTH_IN downto 0);
		variable temp_out : signed(BIT_WIDTH_OUT downto 0);
		variable x_in_i : signed(BIT_WIDTH_IN-1 downto 0); -- iteration variable that holds the i-th input

		begin
		if n_Res_i = '0' then
			Y_o <= (others => '0');
		elsif rising_edge(Clk_i) and Valid_i = '1' then
			
			-- Loop over all outputs
			for I in 0 to KERNEL_SIZE-1 loop

				-- Select the i-th input and store it in a variable
				x_in_i := signed(
					X_i((I+1) * BIT_WIDTH_IN -1 downto I * BIT_WIDTH_IN)
				);
				

				-- We can assume the input is posiive -> ALL RELU LAYERS!
				-- ToDo: Can we done any input checks for this?
				-- Frist do the shift
				-- Shift operators overloaded on types UNSIGNED and SIGNED
				-- srl: Shift Right Logic --> fill up the new values with zeros
				temp_out := x_in_i srl WEIGHT(I); 

				-- And check if the weight was negative
				if (WEIGHT_SIGNS(i) = CONV_KERNEL_WEIGHT_SIGN_NEGATIVE) then
					-- Weight has a negative value
					-- use 2's complement conversion
					temp_out := not temp_out + 1;
				end if;

				M_out(I) := temp_out;

				M_out(I) := resize(to_signed(WEIGHT(I), WEIGHT_WIDTH) * temp, BIT_WIDTH_OUT + 1);
			end loop;
			temp_out := M_out(0) + M_out(1) + M_out(2) + M_out(3) + M_out(4) + M_out(5) + M_out(6) + M_out(7) + M_out(8);
			Y_o <= temp_out(BIT_WIDTH_OUT - 1 downto 0);
		end if;
	end process;
end beh;
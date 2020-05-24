library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
LIBRARY work;
use work.egg_box.all;
use work.clogb2_Pkg.all;

entity Conv_channel is
  Generic ( 
    LAYER_ID : integer := 0; -- ID of the Layer. Reuired for reading correct MIF files
    OUTPUT_CHANNEL_ID : integer := 0; -- ID of the output channel. Required for reading correct MIF files
    INPUT_CHANNEL_NUMBER : integer range 1 to 512 := 1; -- Number of input channels 
    MIF_PATH : STRING  := "C:/Users/lukas/Documents/SoC_Lab/FPGA_MNIST/vivado/NN_IP/EggNet_1.0/mif/"; --try if relative path is working 
    WEIGHT_MIF_PREAMBLE : STRING := "Weight_";
    BIAS_MIF_PREAMBLE : STRING := "Bias_";
    CH_FRAC_MIF_PREAMBLE : STRING := "Channel_Fraction_shift_";
    K_FRAC_MIF_PREAMBLE : STRING := "Kernel_Fraction_shift_"
  );
  Port (
    -- Clk and reset
    Clk_i         : in std_logic;
    Rst_i         : in std_logic;

    -- Slave interface --> connect to memory controller master
    S_Valid_i	    : in std_logic;
    S_X_data_1_i  : in std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 1 |Vector: trans(1,2,3)
    S_X_data_2_i  : in std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 2 |Vector: trans(1,2,3)
    S_X_data_3_i  : in std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 3 |Vector: trans(1,2,3)
    S_Last_i      : in std_logic;
    S_Newrow_i    : in std_logic;
    S_Ready_o     : out std_logic;

    -- Master interface --> connect to memory controller slave
    M_Valid_o	    : out std_logic;
    M_Y_data_o    : out std_logic_vector(ACTIVATION_WIDTH-1 downto 0);
    M_Last_o      : out std_logic;
    M_Ready_i     : in std_logic
  );
end Conv_channel;

architecture Behavioral of Conv_channel is

  type weight_shift_array_t is array (0 to INPUT_CHANNEL_NUMBER-1) of kernel_shift_array_t;
  type weight_sign_array_t is array (0 to INPUT_CHANNEL_NUMBER-1) of kernel_sign_array_t;
  type bias_array_t is array (0 to INPUT_CHANNEL_NUMBER-1) of std_logic_vector(BIAS_WIDTH-1 downto 0);
  type input_array_t is array (0 to INPUT_CHANNEL_NUMBER-1) of kernel_input_array_t;
  type output_array_t is array (0 to INPUT_CHANNEL_NUMBER-1) of std_logic_vector(ACTIVATION_WIDTH-1 downto 0);
  
  impure function init_signs(mif_file_name : in STRING) return weight_sign_array_t is
    file mif_file : text open read_mode is mif_file_name;
    variable mif_line : line;
    variable temp_bv : bit_vector(0 downto 0);
    variable temp_mem : weight_sign_array_t;
  begin
    for i in 0 to INPUT_CHANNEL_NUMBER - 1 loop
      for j in 0 to KERNEL_SIZE - 1 loop
        readline (mif_file, mif_line);
        read(mif_line, temp_bv);
        temp_mem(i)(j) := to_stdlogicvector(temp_bv);
      end loop;  
    end loop;
    return temp_mem;
  end function;

  impure function init_shifts(mif_file_name : in STRING) return weight_shift_array_t is
    file mif_file : text open read_mode is mif_file_name;
    variable mif_line : line;
    variable temp_bv : bit_vector(WEIGHT_SHIFT_BIT_WIDTH - 1 downto 0);
    variable temp_mem : weight_shift_array_t;
  begin
    for i in 0 to INPUT_CHANNEL_NUMBER - 1 loop
      for j in 0 to KERNEL_SIZE - 1 loop
        readline (mif_file, mif_line);
        read(mif_line, temp_bv);
        temp_mem(i)(j) := to_stdlogicvector(temp_bv);
      end loop;  
    end loop;
    return temp_mem;
  end function;
  
  impure function init_bias(mif_file_name : in STRING) return bias_array_t is
    file mif_file : text open read_mode is mif_file_name;
    variable mif_line : line;
    variable temp_bv : bit_vector(BIAS_WIDTH - 1 downto 0);
    variable temp_mem : bias_array_t;
  begin
    for i in 0 to INPUT_CHANNEL_NUMBER - 1 loop
      readline (mif_file, mif_line);
      read(mif_line, temp_bv);
      temp_mem(i) := to_stdlogicvector(temp_bv);
    end loop;
    return temp_mem;
  end function;  
  
  impure function init_kernel_fraction(mif_file_name : in STRING) return std_logic_vector is
    file mif_file : text open read_mode is mif_file_name;
    variable mif_line : line;
    variable temp_bv : bit_vector(KERNEL_FRACTION_SHIFT_WIDTH - 1 downto 0);
    variable temp_mem : std_logic_vector(KERNEL_FRACTION_SHIFT_WIDTH-1 downto 0);
  begin
    readline (mif_file, mif_line);
    read(mif_line, temp_bv);
    temp_mem := to_stdlogicvector(temp_bv);
    return temp_mem;
  end function; 
  
  impure function init_channel_fraction(mif_file_name : in STRING) return integer is
    file mif_file : text open read_mode is mif_file_name;
    variable mif_line : line;
    variable temp_bv : bit_vector(CHANNEL_FRACTION_SHIFT_WIDTH - 1 downto 0);
    variable temp_mem : integer;
  begin
    readline (mif_file, mif_line);
    read(mif_line, temp_bv);
    temp_mem := to_integer(unsigned(to_stdlogicvector(temp_bv)));
    return temp_mem;
  end function; 
  
  
  
  constant SHIFTS_MIF_FILE_NAME : STRING := MIF_PATH & WEIGHT_MIF_PREAMBLE & "Shifts_L" & integer'image(LAYER_ID) & 
                                            "_CO" & integer'image(OUTPUT_CHANNEL_ID);
  constant SIGN_MIF_FILE_NAME : STRING := MIF_PATH & WEIGHT_MIF_PREAMBLE & "Signs_L" & integer'image(LAYER_ID) & 
                                            "_CO" & integer'image(OUTPUT_CHANNEL_ID);
  constant BIAS_MIF_FILE_NAME : STRING := MIF_PATH & BIAS_MIF_PREAMBLE & "_L" & integer'image(LAYER_ID) & 
                                            "_CO" & integer'image(OUTPUT_CHANNEL_ID);         
  constant CH_FRAC_MIF_FILE_NAME : STRING := MIF_PATH & CH_FRAC_MIF_PREAMBLE & "_L" & integer'image(LAYER_ID) & 
                                            "_CO" & integer'image(OUTPUT_CHANNEL_ID);       
  constant K_FRAC_MIF_FILE_NAME : STRING := MIF_PATH & K_FRAC_MIF_PREAMBLE & "_L" & integer'image(LAYER_ID) & 
                                            "_CO" & integer'image(OUTPUT_CHANNEL_ID);  


  constant WEIGHT_SHIFTS          : weight_shift_array_t := init_shifts(SHIFTS_MIF_FILE_NAME);
  constant WEIGHT_SIGNS           : weight_sign_array_t  := init_signs(SIGN_MIF_FILE_NAME);
  constant BIASES                 : bias_array_t := init_bias(BIAS_MIF_FILE_NAME);
  constant KERNEL_FRACTION_SHIFT  : std_logic_vector(KERNEL_FRACTION_SHIFT_WIDTH-1 downto 0) := init_kernel_fraction(K_FRAC_MIF_FILE_NAME);
  constant CHANNEL_FRACTION_SHIFT : integer := init_channel_fraction(CH_FRAC_MIF_FILE_NAME);
  
  
  signal shiftreg_valid_out : std_logic_vector(INPUT_CHANNEL_NUMBER-1 downto 0);
  signal shiftreg_last_out : std_logic_vector(INPUT_CHANNEL_NUMBER-1 downto 0);
  signal shiftreg_is_ready_out : std_logic_vector(INPUT_CHANNEL_NUMBER-1 downto 0);

  signal input_kernels : input_array_t; 
  signal kernel_outputs : output_array_t; 
  signal kernel_last : std_logic_vector(INPUT_CHANNEL_NUMBER-1 downto 0);
  signal kernel_valid : std_logic_vector(INPUT_CHANNEL_NUMBER-1 downto 0);  
  
  constant ADDER_STAGES: integer := clogb2(INPUT_CHANNEL_NUMBER); 
  --type adder_tree_array_t is array (natural range<>) of STD_LOGIC_VECTOR;
  --signal adder_out : adder_outputs(INPUT_CHANNEL_NUMBER-1 downto 0)(ACTIVATION_WIDTH+ADDER_STAGES-1 downto 0); 
  signal adder_out : std_logic_vector(ACTIVATION_WIDTH+ADDER_STAGES-1 downto 0); 
  signal adder_valid : std_logic;
  signal adder_last : std_logic;
  signal adder_ready : std_logic;
begin

  --------################# IN conv2d verschieben !!!! ###################################
  --------||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
  --------VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
  Shiftregisters: for i in 0 to INPUT_CHANNEL_NUMBER-1 generate
    Shiftregister: entity work.ShiftRegister_3x3
      port map(
        Clk_i       => Clk_i, 
        nRst_i      => Rst_i, 
        S_X_data_1_i => S_X_data_1_i((i+1)*ACTIVATION_WIDTH-1 downto i*ACTIVATION_WIDTH), 
        S_X_data_2_i => S_X_data_1_i((i+1)*ACTIVATION_WIDTH-1 downto i*ACTIVATION_WIDTH), 
        S_X_data_3_i => S_X_data_1_i((i+1)*ACTIVATION_WIDTH-1 downto i*ACTIVATION_WIDTH), 
        S_Valid_i  => S_Valid_i,
        S_Newrow_i => S_Newrow_i,
        S_Last_i   => S_Last_i, 
        S_Ready_o  => shiftreg_is_ready_out(i), 
        M_X_data_o => input_kernels(i),
        M_Valid_o  => shiftreg_valid_out(i),
        M_Last_o   => shiftreg_last_out(i), 
        M_Ready_i  => M_Ready_i
      );    
  end generate;
  S_Ready_o <= shiftreg_is_ready_out(0);
  --------^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  --------||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
  --------################# IN conv2d verschieben !!!! ###################################

  Kernels: for i in 0 to INPUT_CHANNEL_NUMBER-1 generate
    Kernel: entity work.Kernel3x3_log2
      Port map( Clk_i => Clk_i,
                Rst_i => Rst_i,
                S_Valid_i => shiftreg_valid_out(0),
                S_Last_i => shiftreg_last_out(0),
                S_shift_i => WEIGHT_SHIFTS(i),
                S_sign_i => WEIGHT_SIGNS(i), 
                S_Bias_i => BIASES(i),
                S_X_data_i => input_kernels(i),
                S_Fraction_shift_i => KERNEL_FRACTION_SHIFT,
                M_Valid_o => kernel_valid(i),
                M_Last_o => kernel_last(i),
                M_Ready_i => M_Ready_i,
                M_Y_data_o => kernel_outputs(i));
  end generate;

  adders: process(Clk_i,Rst_i) is 
    variable add_up :signed(ACTIVATION_WIDTH+ADDER_STAGES downto 0); 
  begin
    if rising_edge(Clk_i) then 
      if Rst_i = '1' then 
        for i in 0 to INPUT_CHANNEL_NUMBER-1 loop 
          add_up := (others => '0');
        end loop;   
        adder_valid <= '0';
        adder_last  <= '0';
      elsif M_Ready_i = '1' then 
        add_up := (others => '0');
        for i in 1 to INPUT_CHANNEL_NUMBER-1 loop 
          add_up := add_up + resize(signed(kernel_outputs(i)),ACTIVATION_WIDTH+ADDER_STAGES+1);
        end loop;
        adder_out <= std_logic_vector(add_up);
        adder_valid <= kernel_valid(0);
        adder_last  <= kernel_last(0);
      end if; 
    end if;
  end process;

  Shift_ReLU: if CHANNEL_FRACTION_SHIFT > 0 generate
    ReLU: process(Clk_i,Rst_i) is 
      variable shifted : std_logic_vector(ACTIVATION_WIDTH+ADDER_STAGES-1 downto 0); 
    begin
      if rising_edge(Clk_i) then 
        if Rst_i = '1' then 
          M_Y_data_o <= (others => '0'); 
        elsif M_Ready_i = '1' then 
          M_Last_o <= adder_last;
          M_valid_o <= adder_valid;
          if adder_out(adder_out'left) = '1' then
              M_Y_data_o <= (others => '0');
          elsif adder_out(adder_out'left downto adder_out'left-CHANNEL_FRACTION_SHIFT+1) /= (adder_out(adder_out'left downto adder_out'left-CHANNEL_FRACTION_SHIFT+1)'range => '0') then
              M_Y_data_o <= (others => '1');
          else
              M_Y_data_o <= adder_out(adder_out'left-CHANNEL_FRACTION_SHIFT downto adder_out'left-CHANNEL_FRACTION_SHIFT-ACTIVATION_WIDTH);
          end if;
        end if;  
      end if;
    end process;  
  end generate;
  
  Quant_ReLU: if CHANNEL_FRACTION_SHIFT = 0 generate
    ReLU: process(Clk_i,Rst_i) is 
      variable shifted : std_logic_vector(ACTIVATION_WIDTH+ADDER_STAGES-1 downto 0); 
    begin
      if rising_edge(Clk_i) then 
        if Rst_i = '1' then  
          M_Y_data_o <= (others => '0');  
        elsif M_Ready_i = '1' then 
          M_Last_o <= adder_last;
          M_valid_o <= adder_valid;
          if adder_out(adder_out'left) = '1' then
              M_Y_data_o <= (others => '0');
          else
              M_Y_data_o <= adder_out(adder_out'left downto adder_out'left-ACTIVATION_WIDTH);
          end if;
        end if;  
      end if;
    end process;  
  end generate;
  -- ** Adder tree coming soon ** 
  
  -- Adder_tree for k in 0 to ADDER_STAGES-1 generate
    -- adders: process(Clk_i,Rst_i) is 
      -- variable adder_out: adder_tree_array_t(k-1 downto 
    -- begin
      -- if rising_edge(Clk_i) then 
        -- if Rst_i = '1' then 
          -- for i in 0 to INPUT_CHANNEL_NUMBER-2 loop 
            -- adder_out <= (others => '0');
          -- end loop;   
        -- else 
          -- for i in 1 to ADDER_STAGES-1 loop 
            -- for j in 0 to INPUT_CHANNEL_NUMBER/(i*2) loop; 
              -- adder_out(j+
            -- end loop;
          -- end loop;
        -- end if; 
      -- end if;
    -- end process;
  -- end generate;
  

end Behavioral;
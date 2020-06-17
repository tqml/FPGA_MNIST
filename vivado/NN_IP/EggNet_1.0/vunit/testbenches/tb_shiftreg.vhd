library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
library vunit_lib;
context vunit_lib.vunit_context;
LIBRARY work;
use work.csv_numpy.all;
use work.egg_box.all;

library OSVVM ; 
  use OSVVM.RandomBasePkg.all ; 
  use OSVVM.RandomPkg.all ; 

entity tb_shiftreg is
  generic (
    RUNNER_CFG : string;
    TB_PATH    : string;
    TB_CSV_DATA_FILE     : string;
    TB_CSV_RESULTS_FILE   : string;
    INPUT_CHANNEL_NUMBER  : integer := 1;
    OUTPUT_CHANNEL_NUMBER  : integer := 16;
    RANDOM_READY          : std_logic := '1';
    MIF_PATH              : string := "../../mif/";
    WEIGHT_MIF_PREAMBLE   : STRING := "Weight_";
    BIAS_MIF_PREAMBLE     : STRING := "Bias_";
    CH_FRAC_MIF_PREAMBLE  : STRING := "Layer_Exponent_shift_";
    K_FRAC_MIF_PREAMBLE   : STRING := "Kernel_Exponent_shift_"
  );
end entity;

architecture tb of tb_shiftreg is

  type VEC_3x1 is array (0 to 2) of std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0);

  constant TbPeriod     : time := 10 ns;
  signal TbClock        : std_logic := '0';
  signal TbSimEnded     : std_logic := '0';
  signal layer_clk	    : std_logic;
  signal layer_aresetn  : std_logic;

  signal s_valid    : std_logic;
  signal s_X_data_1 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 1 |Vector: trans(1,2,3)
  signal s_X_data_2 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 2 |Vector: trans(1,2,3)
  signal s_X_data_3 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 3 |Vector: trans(1,2,3)
  signal s_newrow   : std_logic;
  signal s_last     : std_logic;
  signal s_ready    : std_logic;
  
  signal output_kernels : kernel_input_array_t;
  signal m_Last       :std_logic;
  signal m_Ready      :std_logic;
  signal m_Valid      :std_logic;
  
  signal counter      :integer; 
  signal monitor_counter      :integer; 
  signal dbg_b_idx      :integer; 
  signal dbg_w_idx      :integer; 
  signal dbg_h_idx      :integer; 
  

begin
  
  TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';
  layer_clk <= TbClock;


  main: process
    
  
    procedure run_test(testdata_filepath : string) is
      constant test_img_dim : integer_vector := csvGetNumpyDim(testdata_filepath);
      constant test_img_arr : int_vec_4d_t := csvGetNumpy4d(testdata_filepath);      
      variable activation_vec : VEC_3x1; 
      variable s_data_1 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 1 |Vector: trans(1,2,3)
      variable s_data_2 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 2 |Vector: trans(1,2,3)
      variable s_data_3 : std_logic_vector((ACTIVATION_WIDTH*INPUT_CHANNEL_NUMBER) - 1 downto 0); --  Input vector element 3 |Vector: trans(1,2,3)
      variable tile_index : integer := 0;
      variable RV : RandomPType ; 
      variable DataSigned : signed(7 downto 0) ;
    begin
      printDim(test_img_dim); --[B,H,W,Ci,3]
      layer_aresetn <= '0'; 
      m_Ready <= '0'; 
      counter <= 0;
      s_data_1 := (others => '0');
      s_data_2 := (others => '0');
      s_data_3 := (others => '0');      
      s_X_data_1 <= (others => '0');
      s_X_data_2 <= (others => '0');
      s_X_data_3 <= (others => '0');
      s_newrow <= '0';
      dbg_b_idx <= 0;
      dbg_w_idx <= 0;
      dbg_h_idx <= 0;
      
      s_valid <= '0';
      s_last <= '0'; 
      wait for TbPeriod*3; 
      layer_aresetn <= '1'; 
      m_Ready <= '1'; 
      wait for TbPeriod; 
      -- *** iterate through batches *** 
      for i in 0 to test_img_dim(0)-1 loop
      
        -- *** iterate through image hight and width 
        for j in 0 to test_img_dim(1)-1 loop 
          for k in 0 to test_img_dim(2)-1 loop
            
            tile_index := 0;
            -- *** New image tile ***
            for l in 0 to test_img_dim(3)-1 loop
                activation_vec(l) := std_logic_vector(to_unsigned(test_img_arr(i,j,k,l)
                                                                ,ACTIVATION_WIDTH));
                --report "s_data: [" & integer'image(tile_index) & "]=" & to_hstring(activation_tile(tile_index)) & "h";                                                
            end loop;

            if RANDOM_READY = '1' then
              DataSigned := RV.RandSigned(-1,32, 8);
              if to_integer(DataSigned) < 0 then
                DataSigned := to_signed(1,8);
                while to_integer(DataSigned) > 0 loop
                  m_Ready <= '0'; 
                  DataSigned := RV.RandSigned(-1,127, 8);
                  wait until layer_clk = '1';
                end loop;
                m_Ready <= '1'; 
                wait until layer_clk = '1';
              else
                wait until layer_clk = '1'; 
              end if;
            end if;
            if s_ready /= '1' then
              wait until s_ready = '1'; 
            end if;
            if k = 0 then 
              s_newrow <= '1';
            else
              s_newrow <= '0';
            end if;
            counter <= counter +1;
            dbg_b_idx <= i;
            dbg_w_idx <= j;
            dbg_h_idx <= k; 
            
            s_X_data_1 <= activation_vec(0);
            s_X_data_2 <= activation_vec(1);
            s_X_data_3 <= activation_vec(2);
            s_valid <= '1';
            s_last <= '0';

          end loop;
        end loop;
        s_last <= '1';
      end loop;  
      wait until layer_clk = '1';
      s_valid <= '0';
      wait for TbPeriod*15; 
    end procedure;

  begin
    test_runner_setup(runner, RUNNER_CFG);
    while test_suite loop
      info("Test data CSV file path: " & TB_CSV_DATA_FILE);
      info("Test results CSV file path: " & TB_CSV_RESULTS_FILE);
      if run("CSV test") then
        run_test(TB_CSV_DATA_FILE);
      end if;
    end loop;
    test_runner_cleanup(runner);
    wait;
  end process; 

  Shiftregister: entity work.ShiftRegister_3x3
    port map(
      Clk_i      => layer_clk,     
      Rst_i      => not layer_aresetn,  
      S_X_data_1_i => S_X_data_1, 
      S_X_data_2_i => S_X_data_2, 
      S_X_data_3_i => S_X_data_3, 
      S_Valid_i  => s_valid,
      S_Newrow_i => s_newrow,
      S_Last_i   => s_last, 
      S_Ready_o  => s_ready, 
      M_X_data_o => output_kernels,
      M_Valid_o  => m_Valid,
      M_Last_o   => m_Last, 
      M_Ready_i  => m_Ready
    );     
 
 
  Monitor: process(layer_clk,layer_aresetn)
    constant result_img_dim : integer_vector := csvGetNumpyDim(TB_CSV_RESULTS_FILE);
    constant result_img_arr : int_vec_5d_t := csvGetNumpy5d(TB_CSV_RESULTS_FILE);
    
    variable batch_idx : integer := 0;
    variable width_idx : integer := 0;
    variable height_idx : integer := 0;
    variable kernel_idx : integer := 0;
    variable print_helper : int_vec_3d_t(1 downto 0, 2 downto 0, 2 downto 0);
  begin
    if layer_aresetn = '0' then
      width_idx := 0;
      height_idx := 0;
      batch_idx := 0;
      kernel_idx := 0;
      monitor_counter <= 0;
    elsif rising_edge(layer_clk) and m_Ready = '1' and m_Valid = '1' then
      kernel_idx := 0;
      monitor_counter <= monitor_counter+1;
      for i in 0 to FILTER_HEIGHT-1 loop
        for j in 0 to FILTER_WIDTH-1 loop
          print_helper(0,i,j) := to_integer(unsigned(output_kernels(kernel_idx)));
          print_helper(1,i,j) := result_img_arr(batch_idx,height_idx,width_idx,i,j);
          kernel_idx := kernel_idx+1;
        end loop;
      end loop;
      info("[" & integer'image(batch_idx) & "][" & integer'image(height_idx) & 
      "][" & integer'image(width_idx) & "]");
      print3d(print_helper);    
      kernel_idx := 0;
      for i in 0 to FILTER_HEIGHT-1 loop
        for j in 0 to FILTER_WIDTH-1 loop       
          check_equal(to_integer(unsigned(output_kernels(kernel_idx))),
                result_img_arr(batch_idx,height_idx,width_idx,i,j),
                "[" & integer'image(batch_idx) & "][" & integer'image(height_idx) & "][" &
                integer'image(width_idx) & "][" & integer'image(i) & "][" & integer'image(j) & "]"); 
          kernel_idx := kernel_idx+1;
        end loop;
      end loop;
      if height_idx = (result_img_dim(1)-1) and width_idx = (result_img_dim(2)-1) then 
        check(m_Last = '1', "Expect Last signal to be high at [" & integer'image(batch_idx) & "][" & integer'image(height_idx) & "][" & integer'image(width_idx) & "]"); 
      end if;
      
      if width_idx = result_img_dim(2)-1 then 
        if height_idx = result_img_dim(1)-1 then
          batch_idx := iterate(batch_idx,0,result_img_dim(0)-1);
        end if;
        height_idx := iterate(height_idx,0,result_img_dim(1)-1);
      end if;  
      width_idx := iterate(width_idx,0,result_img_dim(2)-1);
    end if; 
  end process;

 
end architecture;

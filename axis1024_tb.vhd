library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis1024_tb is
  generic (
		-- Parameters of Axi Slave
		C_S_AXIS_TDATA_WIDTH	: integer	:= 1024;

		-- Parameters of Axi Master
		C_M_AXIS_TDATA_WIDTH	: integer	:= 128;
		C_M_AXIS_START_COUNT	: integer	:= 32
	);
end axis1024_tb;

architecture behav of axis1024_tb is
  
  -- Axi Stream Slave
  signal s_axis_aclk    : std_logic := '0';
  signal s_axis_aresetn : std_logic := '0';
  signal s_axis_tready	: std_logic := '0';
  signal s_axis_tdata	  : std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0)     := (others => '0');
  signal s_axis_tstrb	  : std_logic_vector((C_S_AXIS_TDATA_WIDTH/8)-1 downto 0) := (others => '1');
  signal s_axis_tlast	  : std_logic := '0';
  signal s_axis_tvalid  : std_logic := '0';
  
  -- Axi Stream Master
  signal m_axis_aclk    : std_logic := '0';
  signal m_axis_aresetn : std_logic := '0';
  signal m_axis_tready	: std_logic := '0';
  signal m_axis_tdata	  : std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0)     := (others => '0');
  signal m_axis_tstrb	  : std_logic_vector((C_M_AXIS_TDATA_WIDTH/8)-1 downto 0) := (others => '1');
  signal m_axis_tlast	  : std_logic := '0';
  signal m_axis_tvalid  : std_logic := '0';

  constant c_PERIOD     : time := 10 ns; 
  constant c_RST_CYCLES : integer := 10;

begin

  dut : entity work.axis_blake3
    generic map (
      C_S_AXIS_TDATA_WIDTH => C_S_AXIS_TDATA_WIDTH,
      C_M_AXIS_TDATA_WIDTH => C_M_AXIS_TDATA_WIDTH,
      C_M_AXIS_START_COUNT => C_M_AXIS_START_COUNT
    )
    port map (
      -- Axi Stream Slave
      s_axis_aclk     => s_axis_aclk,
      s_axis_aresetn  => s_axis_aresetn,
      s_axis_tready => s_axis_tready,
      s_axis_tdata  => s_axis_tdata,
      s_axis_tstrb  => s_axis_tstrb,
      s_axis_tlast  => s_axis_tlast,
      s_axis_tvalid => s_axis_tvalid,
      
      -- Axi Stream Master
      m_axis_aclk     => m_axis_aclk,
      m_axis_aresetn  => m_axis_aresetn,
      m_axis_tready => m_axis_tready,
      m_axis_tdata  => m_axis_tdata,
      m_axis_tstrb  => m_axis_tstrb,
      m_axis_tlast  => m_axis_tlast,
      m_axis_tvalid => m_axis_tvalid
    );
    
  -- Clock process
  m_axis_aclk <= s_axis_aclk;
  m_axis_aresetn <= s_axis_aresetn;
  process
  begin
    s_axis_aclk <= '0';
    wait for c_PERIOD/2;
    s_axis_aclk <= '1';
    wait for c_PERIOD/2;
  end process;
  
  
  p_TB : process
  begin
    -- Hold Reset Signal Active Low for c_RST_CYCLES clock cycles
    s_axis_aresetn <= '0';
    wait until rising_edge(s_axis_aclk);
    wait for c_PERIOD*c_RST_CYCLES;
    s_axis_aresetn <= '1';
    wait for c_PERIOD*c_RST_CYCLES;
    
    -- Start Transfer
    s_axis_tvalid <= '1';
    s_axis_tlast <= '1';
    s_axis_tdata <=
      x"0000000000000000" &
      x"0000000000000000" &
      -- DFlags & NumBytes
      x"0000000B0000000D" & 
      -- Counter
      x"0000000000000000" &
      -- MBlock
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000a21646c72" &
      x"6f57206f6c6c6548" &
      -- Chain
      x"5be0cd191f83d9ab" &
      x"9b05688c510e527f" &
      x"a54ff53a3c6ef372" &
      x"bb67ae856a09e667";  
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    wait until (s_axis_tready = '1');
    wait for c_PERIOD;
    s_axis_tvalid <= '1';
    s_axis_tlast <= '1';
    s_axis_tdata <=
      x"0000000000000000" &
      x"0000000000000000" &
      -- DFlags & NumBytes
      x"0000000B0000000D" & 
      -- Counter
      x"0000000000000000" &
      -- MBlock
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000000000000" &
      x"0000000a21646c72" &
      x"6f57206f6c6c6548" &
      -- Chain
      x"5be0cd191f83d9ab" &
      x"9b05688c510e527f" &
      x"a54ff53a3c6ef372" &
      x"bb67ae856a09e667";   
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    wait for c_PERIOD*50;
    wait;
  end process;

end behav;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis32_tb is
  generic (
		-- Parameters of Axi Slave
		C_S_AXIS_TDATA_WIDTH	: integer	:= 32;

		-- Parameters of Axi Master
		C_M_AXIS_TDATA_WIDTH	: integer	:= 32;
		C_M_AXIS_START_COUNT	: integer	:= 32
	);
end axis32_tb;

architecture behav of axis32_tb is
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
  
  signal r_hash   : std_logic_vector(511 downto 0);
  signal r_index  : integer := C_M_AXIS_TDATA_WIDTH-1;

  constant c_PERIOD     : time := 10 ns; 
  constant c_RST_CYCLES : integer := 10;
  
  type t_w32_vec is array(natural range <>) of std_logic_vector(31 downto 0);
  -- Chain Values
  constant c_IV : t_w32_vec(7 downto 0) := (
    0 => x"6a09e667",
    1 => x"bb67ae85",
    2 => x"3c6ef372",
    3 => x"a54ff53a",
    4 => x"510e527f",
    5 => x"9b05688c",
    6 => x"1f83d9ab",
    7 => x"5be0cd19"
  );
  -- MBlock Values
  constant c_mblock : t_w32_vec(15 downto 0) := (
    0 => x"6c6c6548",
    1 => x"6f57206f",
    2 => x"21646c72",
    3 => x"0000000a",
    others => (others => '0')
  );

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
  
  
  p_slave_TB : process
  begin
    -- Hold Reset Signal Active Low for c_RST_CYCLES clock cycles
    s_axis_aresetn <= '0';
    wait until rising_edge(s_axis_aclk);
    wait for c_PERIOD*c_RST_CYCLES;
    s_axis_aresetn <= '1';
    wait for c_PERIOD*c_RST_CYCLES;
    
    -- Start Chain Transfer
    s_axis_tvalid <= '1';
    s_axis_tdata <= c_IV(0);
    for i in 0 to (c_IV'high-1) loop
      s_axis_tdata <= c_IV(i);   
      wait for c_PERIOD;
    end loop;
    -- End packet
    s_axis_tlast <= '1';
    s_axis_tdata <= c_IV(c_IV'high);
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    -- Start MBlock Transfer
    s_axis_tvalid <= '1';
    for i in 0 to (c_mblock'high-1) loop
      s_axis_tdata <= c_mblock(i);
      wait for c_PERIOD;
    end loop;
    -- End packet
    s_axis_tlast <= '1';
    s_axis_tdata <= c_mblock(c_mblock'high);
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    -- Start Counter Transfer
    s_axis_tvalid <= '1';
    s_axis_tdata <= x"00000000";
    wait for c_PERIOD;
    -- End packet
    s_axis_tlast <= '1';
    s_axis_tdata <= x"00000000";
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    -- Start NumBytes Transfer
    s_axis_tvalid <= '1';
    s_axis_tlast <= '1';
    s_axis_tdata <= x"0000000D";
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    -- Start DFlags Transfer
    s_axis_tvalid <= '1';
    s_axis_tlast <= '1';
    s_axis_tdata <= x"0000000B";
    wait for c_PERIOD;
    s_axis_tlast  <= '0';
    s_axis_tvalid <= '0';
    
    wait for c_PERIOD*50;
    wait;
  end process;
  
  p_master_TB : process
  begin
    m_axis_tready <= '1';
    wait until (m_axis_tvalid = '1');
    wait until rising_edge(s_axis_aclk);
     
    for i in 0 to ((r_hash'high+1)/C_M_AXIS_TDATA_WIDTH)-1 loop
      if (m_axis_tvalid = '1') then
        r_hash(r_index downto r_index-C_M_AXIS_TDATA_WIDTH+1) <= m_axis_tdata;
        r_index <= r_index + C_M_AXIS_TDATA_WIDTH;
      end if;
      wait for c_PERIOD;
    end loop;
    
    m_axis_tready <= '0';
    wait;
  end process;

end behav;

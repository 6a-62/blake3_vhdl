library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axil_tb is
  generic (
    -- AXI Parameters
    C_S_AXI_DATA_WIDTH : integer := 32;
    C_S_AXI_ADDR_WIDTH : integer := 8
  );
end axil_tb;

architecture behav of axil_tb is

  -- Clock and Reset
  signal s_axi_aclk      : std_logic := '0';
  signal s_axi_aresetn   : std_logic := '0';
  -- Write Address Channel
  signal s_axi_awaddr    : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal s_axi_awvalid   : std_logic := '0';
  signal s_axi_awready   : std_logic := '0';
  -- Write Data Channel
  signal s_axi_wdata     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_axi_wstrb     : std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0) := (others => '1');
  signal s_axi_wvalid    : std_logic := '0';
  signal s_axi_wready    : std_logic := '0';
  -- Read Address Channel
  signal s_axi_araddr    : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal s_axi_arvalid   : std_logic := '0';
  signal s_axi_arready   : std_logic := '0';
  -- Read Data Channel
  signal s_axi_rdata     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_axi_rresp     : std_logic_vector(1 downto 0);
  signal s_axi_rvalid    : std_logic := '0';
  signal s_axi_rready    : std_logic := '0';
  -- Write Response Channel
  signal s_axi_bresp     : std_logic_vector(1 downto 0) := (others => '0');
  signal s_axi_bvalid    : std_logic := '0';
  signal s_axi_bready    : std_logic := '0';

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
  constant c_MBLOCK : t_w32_vec(15 downto 0) := (
    0 => x"6c6c6548",
    1 => x"6f57206f",
    2 => x"21646c72",
    3 => x"0000000a",
    others => (others => '0')
  );

begin

  dut : entity work.axil_blake3
    generic map (
      C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
    )
    port map (
      s_axi_aclk,
      s_axi_aresetn,
      s_axi_awaddr,
      s_axi_awvalid,
      s_axi_awready,
      s_axi_wdata,
      s_axi_wstrb,
      s_axi_wvalid,
      s_axi_wready,
      s_axi_araddr,
      s_axi_arvalid,
      s_axi_arready,
      s_axi_rdata,
      s_axi_rresp,
      s_axi_rvalid,
      s_axi_rready,
      s_axi_bresp,
      s_axi_bvalid,
      s_axi_bready
    );
    
  -- Clock process
  process
  begin
    s_axi_aclk <= '0';
    wait for c_PERIOD/2;
    s_axi_aclk <= '1';
    wait for c_PERIOD/2;
  end process;

  p_TB : process
  begin
    -- Hold Reset Signal Active Low for c_RST_CYCLES clock cycles
    s_axi_aresetn <= '0';
    wait until rising_edge(s_axi_aclk);
    wait for c_PERIOD*c_RST_CYCLES;
    s_axi_aresetn <= '1';
    wait for c_PERIOD*c_RST_CYCLES;
    
    -- Start Chain Transfer
    s_axi_wstrb <= (others => '1');
    for i in 0 to (c_IV'high) loop
      s_axi_wdata   <= c_IV(i);  
      s_axi_awaddr  <= std_logic_vector(to_unsigned(0+i,6)) & "00";
      wait until falling_edge(s_axi_aclk);
      s_axi_awvalid <= '1';
      s_axi_wvalid  <= '1';
      wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
      s_axi_bready  <='1';
      wait until s_axi_bvalid = '1';
      s_axi_awvalid <='0';
      s_axi_wvalid  <='0';
      s_axi_bready  <='1';
      wait until s_axi_bvalid = '0';  -- All finished
      s_axi_bready  <='0';
    end loop;

    -- Start MBlock Transfer
    for i in 0 to (c_MBLOCK'high) loop
      s_axi_wdata   <= c_MBLOCK(i);  
      s_axi_awaddr  <= std_logic_vector(to_unsigned(8+i,6)) & "00";
      wait until falling_edge(s_axi_aclk);
      s_axi_awvalid <= '1';
      s_axi_wvalid  <= '1';
      wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
      s_axi_bready  <='1';
      wait until s_axi_bvalid = '1';
      s_axi_awvalid <='0';
      s_axi_wvalid  <='0';
      s_axi_bready  <='1';
      wait until s_axi_bvalid = '0';  -- All finished
      s_axi_bready  <='0';
    end loop;

    -- Start NumBytes Transfer
    s_axi_wdata <= x"0000000D";  
    s_axi_awaddr <= std_logic_vector(to_unsigned(26,6)) & "00";
    wait until falling_edge(s_axi_aclk);
    s_axi_awvalid <= '1';
    s_axi_wvalid <= '1';
    wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
    s_axi_bready<='1';
    wait until s_axi_bvalid = '1';
    s_axi_awvalid<='0';
    s_axi_wvalid<='0';
    s_axi_bready<='1';
    wait until s_axi_bvalid = '0';  -- All finished
    s_axi_bready<='0';

    -- Start DFlags Transfer
    s_axi_wdata <= x"0000000B";  
    s_axi_awaddr <= std_logic_vector(to_unsigned(27,6)) & "00";
    wait until falling_edge(s_axi_aclk);
    s_axi_awvalid <= '1';
    s_axi_wvalid <= '1';
    wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
    s_axi_bready<='1';
    wait until s_axi_bvalid = '1';
    s_axi_awvalid<='0';
    s_axi_wvalid<='0';
    s_axi_bready<='1';
    wait until s_axi_bvalid = '0';  -- All finished
    s_axi_bready<='0';

    -- Inputs Ready
    s_axi_wdata <= (others => '1');  
    s_axi_awaddr <= std_logic_vector(to_unsigned(28,6)) & "00";
    wait until falling_edge(s_axi_aclk);
    s_axi_awvalid <= '1';
    s_axi_wvalid <= '1';
    wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
    s_axi_bready<='1';
    wait until s_axi_bvalid = '1';
    s_axi_awvalid <='0';
    s_axi_wvalid  <='0';
    s_axi_bready  <='1';
    wait until s_axi_bvalid = '0';  -- All finished
    s_axi_bready  <='0';
    
    s_axi_wdata <= (others => '0');  
    s_axi_awaddr <= std_logic_vector(to_unsigned(28,6)) & "00";
    wait until falling_edge(s_axi_aclk);
    s_axi_awvalid <= '1';
    s_axi_wvalid <= '1';
    wait until (s_axi_awready and s_axi_wready) = '1';  --Client ready to read address/data        
    s_axi_bready<='1';
    wait until s_axi_bvalid = '1';
    s_axi_awvalid <='0';
    s_axi_wvalid  <='0';
    s_axi_bready  <='1';
    wait until s_axi_bvalid = '0';  -- All finished
    s_axi_bready  <='0';
    
    wait for 300 ns;
    wait until rising_edge(s_axi_aclk);
    s_axi_araddr <= std_logic_vector(to_unsigned(29,6)) & "00";
    wait until falling_edge(s_axi_aclk);
    s_axi_arvalid <= '1';
    s_axi_rready  <= '1';
    wait until (s_axi_arready and s_axi_rvalid) = '1';  --Client ready to read address/data        
    s_axi_arvalid <='0';
    s_axi_rready  <='0';
    
    wait;
  end process;

end behav;

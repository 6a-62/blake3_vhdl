library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity axil_blake3 is
  generic (
    -- AXI Parameters
    -- Could support 64bit data width on a full AXI4 core
    -- Only accounts for 32bit and 64bit widths
    C_S_AXI_DATA_WIDTH : integer := 32;
    C_S_AXI_ADDR_WIDTH : integer := 8
  );
  port (
    -- Clock and Reset
    s_axi_aclk      : in  std_logic;
    s_axi_aresetn   : in  std_logic;
    -- Write Address Channel
    s_axi_awaddr    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_awvalid   : in  std_logic;
    s_axi_awready   : out std_logic;
    -- Write Data Channel
    s_axi_wdata     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_wstrb     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
    s_axi_wvalid    : in  std_logic;
    s_axi_wready    : out std_logic;
    -- Read Address Channel
    s_axi_araddr    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_arvalid   : in std_logic;
    s_axi_arready   : out  std_logic;
    -- Read Data Channel
    s_axi_rdata     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_rresp     : out std_logic_vector(1 downto 0);
    s_axi_rvalid    : out std_logic;
    s_axi_rready    : in  std_logic;
    -- Write Response Channel
    s_axi_bresp     : out std_logic_vector(1 downto 0);
    s_axi_bvalid    : out std_logic;
    s_axi_bready    : in  std_logic
  );
end axil_blake3;

architecture behav of axil_blake3 is
  component blake3 is
    port (
      -- Clock
      i_clk   : in std_logic;
      i_reset : in std_logic;
      -- Inputs
      i_chain     : in unsigned(255 downto 0);  -- Input chaining value
      i_mblock    : in unsigned(511 downto 0);  -- Message block
      i_counter   : in unsigned(63 downto 0);   -- Block counter
      i_numbytes  : in unsigned(31 downto 0);   -- Number of input bytes
      i_dflags    : in unsigned(31 downto 0);   -- Domain seperation bit flags :
                                                -- CHUNK_START 2<<0
                                                -- CHUNK_END 2<<1
                                                -- PARENT 2<<2
                                                -- ROOT 2<<^3
                                                -- KEYED_HASH 2<<4
                                                -- DERIVE_KEY_CONTEXT 2<<5
                                                -- DERIVE_KEY_MATERIAL 2<<6
      i_valid     : in std_logic; -- Inputs ready to sample
      -- Outputs
      o_hash  : out unsigned(511 downto 0); -- Output hash
      o_valid : out std_logic -- Output ready to sample
    );
  end component;
  
  -- AXI Signal Registers
  signal w_reset  : std_logic := '0';
  signal r_wready : std_logic := '0';
  signal r_awaddr : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal r_bvalid : std_logic := '0';
  
  signal r_rready : std_logic := '0';
  signal r_rdata  : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
  signal r_rvalid : std_logic := '0';
  
  
  -- Peripheral Registers
  signal r_chain    : unsigned(255 downto 0)  := (others => '0');
  signal r_mblock   : unsigned(511 downto 0)  := (others => '0');  
  signal r_counter  : unsigned(63 downto 0)   := (others => '0');   
  signal r_numbytes : unsigned(31 downto 0)   := (others => '0');   
  signal r_dflags   : unsigned(31 downto 0)   := (others => '0');   
  signal r_i_valid  : std_logic := '0'; 
  signal r_hash     : unsigned(511 downto 0)  := (others => '0'); 
  signal r_o_valid  : std_logic := '0';
  
  -- Address Least Significant Bit, used to drop sub-Word addresses
  constant c_LSB : integer := integer(ceil(log2(real(C_S_AXI_DATA_WIDTH))))-3;
  
  -- Write Apply Strobe Functioon
  impure function f_APPLY_WSTRB (
    r_IN : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0))
    return unsigned is
    variable v_temp : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
  begin
    for ii in 0 to ((C_S_AXI_DATA_WIDTH)/8-1) loop
      if ( S_AXI_WSTRB(ii) = '1' ) then
        v_temp(ii*8+7 downto ii*8) := r_IN(ii*8+7 downto ii*8);
      end if;
    end loop;
    return unsigned(v_temp);
  end function;
      
begin
  -- Map AXI Registers
  -- Write Ready signals are tied together
  S_AXI_AWREADY <= r_wready;
  S_AXI_WREADY  <= r_wready;
  
  S_AXI_ARREADY <= r_rready;
  S_AXI_RDATA   <= r_rdata;
  S_AXI_RVALID  <= r_rvalid;
  S_AXI_RRESP   <= "00"; -- Always respond OKAY
  
  S_AXI_BRESP   <= "00"; -- Always respond OKAY
  S_AXI_BVALID  <= r_bvalid;

  -- BLAKE3 Compression Entity
  e_blake3 : blake3 port map (
    i_clk => S_AXI_ACLK,
    i_reset     => S_AXI_ARESETN, 
    i_chain     => r_chain,     --x00 to x1F
    i_mblock    => r_mblock,    --x20 to x5F
    i_counter   => r_counter,   --x60 to x67
    i_numbytes  => r_numbytes,  --x68 to x6B
    i_dflags    => r_dflags,    --x6C to 6F
    i_valid     => r_i_valid,   --x70 to 0x73
    o_hash      => r_hash,      --x74 to xB7
    o_valid     => r_o_valid    --xB8 to 0xBB
  );
  
  -- Write Ready signals
  process (s_axi_aclk)
  begin
    if rising_edge(s_axi_aclk) then
     if s_axi_aresetn = '0' then
        r_wready <= '0';
      else
        -- Ready to accept Write Address/Data when Valid signals are asserted.
        -- Only assert if low previous cycle, limits to every other cycle
        -- Check Write Response channel, if Ready was set while BVALID & !BREADY a response would be dropped
        r_wready <= (not r_wready) and (s_axi_awvalid and s_axi_wvalid) and ((not r_bvalid) or s_axi_bready);
      end if;
    end if;
  end process;
  
  -- Write Logic
  process (s_axi_aclk)
    variable v_addr   : integer;
    variable v_offset : integer;
  begin
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn = '0' then
        -- Clear registers on reset
        r_chain     <= (others => '0');
        r_mblock    <= (others => '0');  
        r_counter   <= (others => '0');   
        r_numbytes  <= (others => '0');   
        r_dflags    <= (others => '0');   
        r_i_valid   <= '0'; 
        
      elsif r_wready='1' then
        v_addr  := to_integer(unsigned(s_axi_awaddr(C_S_AXI_ADDR_WIDTH-1 downto c_LSB)));
        case v_addr is     
          when 0 to 8-(C_S_AXI_DATA_WIDTH/32) =>
            v_offset := ((v_addr-0)*C_S_AXI_DATA_WIDTH);
            r_chain(v_offset+(C_S_AXI_DATA_WIDTH)-1 downto v_offset)  <= f_APPLY_WSTRB(S_AXI_WDATA);
          when 8 to 24-(C_S_AXI_DATA_WIDTH/32) =>
            v_offset := ((v_addr-8)*C_S_AXI_DATA_WIDTH);
            r_mblock(v_offset+(C_S_AXI_DATA_WIDTH)-1 downto v_offset) <= f_APPLY_WSTRB(S_AXI_WDATA);
          when 24 to 26-(C_S_AXI_DATA_WIDTH/32) =>
            v_offset := ((v_addr-24)*C_S_AXI_DATA_WIDTH);
            r_counter(v_offset+(C_S_AXI_DATA_WIDTH)-1 downto v_offset)<= f_APPLY_WSTRB(S_AXI_WDATA);
          when 26 =>
            r_numbytes  <= f_APPLY_WSTRB(S_AXI_WDATA)(31 downto 0);
          when 27 =>
            r_dflags    <= f_APPLY_WSTRB(S_AXI_WDATA)(31 downto 0);
          when 28 =>
            r_i_valid   <= f_APPLY_WSTRB(S_AXI_WDATA)(0);
          when others => null;
        end case; 
      end if;      
    end if;
  end process;
 
  -- write respond signal
  process (s_axi_aclk)
  begin  
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn='0' then
        r_bvalid <= '0';
      elsif r_wready='1' then
        r_bvalid <= '1';
      elsif s_axi_bready='1' then
        r_bvalid <= '0';
      end if;
    end if;
  end process;
  
  -- read write address ready signa
  process (s_axi_aclk)
  begin  
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn='0' then
        r_rready <= '0';
      else
        -- if not valid read data, assert address ready for new read
        r_rready <= not r_rvalid;
      end if;
    end if;
  end process;
  
  -- read data valid signal
  process (s_axi_aclk)
  begin  
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn='0' then
        r_rvalid <= '0';
      elsif (s_axi_arvalid and r_rready)='1' then
        -- if read address is valid & ready, assert data ready
        r_rvalid <= '1';
      elsif s_axi_rready='1' then
        r_rvalid <= '0';
      end if;
    end if;
  end process;
  
  
  -- read logic
  process (s_axi_aclk)
    variable v_addr   : integer;
    variable v_offset : integer;
  begin  
    if rising_edge(s_axi_aclk) then
      if s_axi_aresetn='0' then
        r_rdata <= (others => '0');
        
      elsif ((not r_rvalid) or s_axi_rready)='1' then
        -- Write to Data Bus whenever allowed
        v_addr  := to_integer(unsigned(s_axi_araddr(C_S_AXI_ADDR_WIDTH-1 downto c_LSB)));
        case v_addr is
          when 29 to 46-(C_S_AXI_DATA_WIDTH/32) =>
            v_offset := ((v_addr-29)*C_S_AXI_DATA_WIDTH);
            r_rdata <= std_logic_vector(r_hash(v_offset+(C_S_AXI_DATA_WIDTH)-1 downto v_offset));
          when 46 =>
            r_rdata <= (0 => r_o_valid, others => '0');
          when others =>
            r_rdata <= (others => '0');
        end case;
      end if;
    end if;
  end process; 
  
end behav;

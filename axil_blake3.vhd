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
    S_AXI_ACLK      : in  std_logic;
    S_AXI_ARESETN   : in  std_logic;
    -- Write Address Channel
    S_AXI_AWADDR    : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    S_AXI_AWVALID   : in  std_logic;
    S_AXI_AWREADY   : out std_logic;
    -- Write Data Channel
    S_AXI_WDATA     : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    S_AXI_WSTRB     : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
    S_AXI_WVALID    : in  std_logic;
    S_AXI_WREADY    : out std_logic;
    -- Read Address Channel
    S_AXI_ARADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    S_AXI_ARVALID   : in std_logic;
    S_AXI_ARREADY   : out  std_logic;
    -- Read Data Channel
    S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    S_AXI_RRESP     : out std_logic_vector(1 downto 0);
    S_AXI_RVALID    : out std_logic;
    S_AXI_RREADY    : in  std_logic;
    -- Write Response Channel
    S_AXI_BRESP     : out std_logic_vector(1 downto 0);
    S_AXI_BVALID    : out std_logic;
    S_AXI_BREADY    : in  std_logic
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
    variable v_TEMP : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
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

  -- Take AXI Reset signal from active low to active high
  w_reset <= not S_AXI_ARESETN;

  -- BLAKE3 Compression Entity
  e_blake3 : blake3 port map (
    i_clk => S_AXI_ACLK,
    i_reset     => w_reset, 
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
  process (S_AXI_ACLK)
  begin
    if rising_edge(S_AXI_ACLK) then
     if S_AXI_ARESETN = '0' then
        r_wready <= '0';
      else
        -- Ready to accept Write Address/Data when Valid signals are asserted.
        -- Only assert if low previous cycle, limits to every other cycle
        -- Check Write Response channel, if Ready was set while BVALID & !BREADY a response would be dropped
        r_wready <= (not r_wready) and (S_AXI_AWVALID and S_AXI_WVALID) and ((not r_bvalid) or S_AXI_BREADY);
      end if;
    end if;
  end process;
  
  -- Write Logic
  process (S_AXI_ACLK)
    variable v_addr   : integer;
    variable v_offset : integer;
  begin
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN = '0' then
        -- Clear registers on reset
        r_chain     <= (others => '0');
        r_mblock    <= (others => '0');  
        r_counter   <= (others => '0');   
        r_numbytes  <= (others => '0');   
        r_dflags    <= (others => '0');   
        r_i_valid   <= '0'; 
        
      elsif r_wready='1' then
        v_addr  := to_integer(unsigned(S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto c_LSB)));
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
 
  -- Write Respond Signal
  process (S_AXI_ACLK)
  begin  
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN='0' then
        r_bvalid <= '0';
      elsif r_wready='1' then
        r_bvalid <= '1';
      elsif S_AXI_BREADY='1' then
        r_bvalid <= '0';
      end if;
    end if;
  end process;
  
  -- Read Write Address Ready Signa
  process (S_AXI_ACLK)
  begin  
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN='0' then
        r_rready <= '0';
      else
        -- If not Valid Read Data, assert Address Ready for new read
        r_rready <= not r_rvalid;
      end if;
    end if;
  end process;
  
  -- Read Data Valid Signal
  process (S_AXI_ACLK)
  begin  
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN='0' then
        r_rvalid <= '0';
      elsif (S_AXI_ARVALID and r_rready)='1' then
        -- If Read Address is Valid & Ready, assert Data Ready
        r_rvalid <= '1';
      elsif S_AXI_RREADY='1' then
        r_rvalid <= '0';
      end if;
    end if;
  end process;
  
  
  -- Read Logic
  process (S_AXI_ACLK)
    variable v_addr   : integer;
    variable v_offset : integer;
  begin  
    if rising_edge(S_AXI_ACLK) then
      if S_AXI_ARESETN='0' then
        r_rdata <= (others => '0');
        
      elsif ((not r_rvalid) or S_AXI_RREADY)='1' then
        -- Write to Data Bus whenever allowed
        v_addr  := to_integer(unsigned(S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH-1 downto c_LSB)));
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_blake3 is
  generic (
		-- Parameters of Axi Slave
		C_S_AXIS_TDATA_WIDTH	: integer	range 32 to 1024 := 32;

		-- Parameters of Axi Master
		C_M_AXIS_TDATA_WIDTH	: integer range 32 to 512	 := 32;
		C_M_AXIS_START_COUNT	: integer	:= 32
	);
  port (
    -- Axi Stream Slave
    s_axis_aclk	    : in std_logic;
    s_axis_aresetn  : in std_logic;
    s_axis_tready : out std_logic;
    s_axis_tdata  : in std_logic_vector(C_S_AXIS_TDATA_WIDTH-1 downto 0);
    s_axis_tstrb	: in std_logic_vector((C_S_AXIS_TDATA_WIDTH/8)-1 downto 0);
    s_axis_tlast	: in std_logic;
    s_axis_tvalid : in std_logic;
  
    -- Axi Stream Master
    m_axis_aclk	    : in std_logic;
    m_axis_aresetn  : in std_logic;
    m_axis_tvalid : out std_logic;
    m_axis_tdata	: out std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
    m_axis_tstrb	: out std_logic_vector((C_M_AXIS_TDATA_WIDTH/8)-1 downto 0);
    m_axis_tlast	: out std_logic;
    m_axis_tready	: in std_logic
  );
end axis_blake3;

architecture behav of axis_blake3 is

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
  
  signal w_i_valid : std_logic := '0';
  signal w_o_valid : std_logic := '0';
  signal w_hash : unsigned(511 downto 0);
    
  --256+512+64+32+32 = 896
  constant c_LAST_INDEX : integer := (256+512+64+32+32)-1;
  signal r_s_buf    : unsigned(1023 downto 0);
  signal r_s_index  : integer := C_S_AXIS_TDATA_WIDTH-1;
  signal r_m_buf    : std_logic_vector(511 downto 0);
  signal r_m_index  : integer := C_S_AXIS_TDATA_WIDTH-1;
  
  type t_state is (
    STATE_INPUT,
    STATE_WAIT,
    STATE_PROCESS,
    STATE_OUTPUT
  );
  signal r_s_state : t_state := STATE_INPUT;
  signal r_m_state : t_state := STATE_PROCESS;
  
begin
  -- BLAKE3 Compression Entity
  e_blake3 : blake3 port map (
    i_clk   => S_AXIS_ACLK,
    i_reset => S_AXIS_ARESETN, 
    i_chain     => r_s_buf(255 downto 0),   --x00 to x1F
    i_mblock    => r_s_buf(767 downto 256), --x20 to x5F
    i_counter   => r_s_buf(831 downto 768), --x60 to x67
    i_numbytes  => r_s_buf(863 downto 832), --x68 to x6B
    i_dflags    => r_s_buf(895 downto 864), --x6C to 6F
    i_valid     => w_i_valid,
    o_hash  => w_hash,
    o_valid => w_o_valid
  );

  -- Input
  -- AXI4 Stream Slave Bus
  process (s_axis_aclk)
  begin
    if rising_edge(s_axis_aclk) then
      if (s_axis_aresetn = '0') then
        r_s_state <= STATE_INPUT;
        s_axis_tready <= '0';
        w_i_valid <= '0';
        
      else  
        case r_s_state is           
          when STATE_INPUT =>
            s_axis_tready <= '1';
            if (s_axis_tvalid = '1') then
              -- Buffer current data
              r_s_buf(r_s_index downto r_s_index-C_S_AXIS_TDATA_WIDTH+1) <= unsigned(s_axis_tdata);
              r_s_index <= r_s_index + C_S_AXIS_TDATA_WIDTH;
              
              -- If buffer full
              if (r_s_index >= c_LAST_INDEX) then
                s_axis_tready <= '0';
                r_s_index <= C_S_AXIS_TDATA_WIDTH-1;
                
                -- Dont issue new write if output not done
                -- TODO Pipeline transfers to allow simultaneous input/hash/output
                if (r_m_state = STATE_PROCESS) then
                  r_s_state <= STATE_PROCESS;
                  w_i_valid <= '1';
                else
                  r_s_state <= STATE_WAIT;
                end if;          
                
              end if;
            end if;
            
          when STATE_WAIT =>
            if (r_m_state = STATE_PROCESS) then
              r_s_state <= STATE_PROCESS;
              w_i_valid <= '1';
            end if;     
                   
          when STATE_PROCESS =>
            w_i_valid <= '0';
            if (w_o_valid = '1' and w_i_valid = '0') then
              r_s_state <= STATE_INPUT;
            end if;
          
          when others => null;
        end case;
      end if;
    end if;
  end process;

  -- Output
  -- AXI4 Stream Master Bus
  m_axis_tstrb  <= (others => '1');
  m_axis_tlast  <= '1' when r_m_index = r_m_buf'high else '0';
  
  process (m_axis_aclk)
  begin
    if rising_edge(m_axis_aclk) then
      if (m_axis_aresetn = '0') then
        r_m_state <= STATE_PROCESS;
        r_m_index <= 0;
        r_m_buf   <= (others => '0');
        m_axis_tdata  <= (others => '0');
        m_axis_tvalid <= '0';
        
      else  
        case r_m_state is           
          when STATE_PROCESS =>
            if (w_o_valid = '1') then
              r_m_state <= STATE_OUTPUT;
              -- Buffer Hash
              r_m_buf <= std_logic_vector(w_hash);
              r_m_index <= C_M_AXIS_TDATA_WIDTH-1;              
            end if;
                 
          when STATE_OUTPUT =>
            m_axis_tvalid <= '1';
            m_axis_tdata <= r_m_buf(r_m_index downto r_m_index-C_M_AXIS_TDATA_WIDTH+1);
            -- If Slave accepted Read, move to next data
            if (m_axis_tready = '1') then
              r_m_index <= r_m_index + C_M_AXIS_TDATA_WIDTH;
            end if;
            
            -- If Write done
            if (r_m_index >= r_m_buf'high) then
              r_m_state <= STATE_WAIT;
            end if;
            
          when STATE_WAIT =>
            m_axis_tvalid <= '0';
            -- Wait until start of next block
            if (w_o_valid = '0') then
              r_m_state <= STATE_PROCESS;
            end if;
                            
          when others => null;
        end case;
      end if;
    end if;
  end process;

end behav;

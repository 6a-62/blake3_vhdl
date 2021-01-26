library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blake3_tb is
end blake3_tb;

architecture behav of blake3_tb is

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
  
  signal w_clk    : std_logic := '0';
  signal w_reset  : std_logic := '1';
  
  -- For standard hash mode, initial chain values are the IV constants
  signal r_chain  : unsigned(255 downto 0) := (
    x"5be0cd19" &
    x"1f83d9ab" &
    x"9b05688c" &
    x"510e527f" &
    x"a54ff53a" &
    x"3c6ef372" &
    x"bb67ae85" &
    x"6a09e667"
  );
  -- "Hello World!"
  -- Little Endian
  signal r_mblock : unsigned(511 downto 0) := (
    to_unsigned(0,12*32) &
    x"0000000a" &
    x"21646c72" &
    x"6f57206f" &
    x"6c6c6548"
  );
  signal r_numbytes : unsigned(31 downto 0) := to_unsigned(13,32);
  signal r_counter  : unsigned(63 downto 0) := to_unsigned(0,64);
  signal r_dflags   : unsigned(31 downto 0) := (
    0 => '1',
    1 => '1',
    3 => '1',
    others => '0'
  );
  signal r_i_valid  : std_logic := '0';
  
  signal r_hash     : unsigned(511 downto 0);
  signal r_o_valid  : std_logic;
  
  -- Expected Hash output
  -- 92dcc6e2e78a357dace30009e4edd612fb3e60c24dc9318724a3c023fd1eb9fe
  -- Little Endian
  constant c_EXPECTED : unsigned(511 downto 0) := (
    x"c5b847a2" &
    x"a79985ee" & 
    x"db01f61a" &
    x"9faa4c9c" &
    x"93e4deb5" &
    x"fe181271" & 
    x"045cc222" &
    x"2dd63f6b" &
    x"feb91efd" &
    x"23c0a324" &
    x"8731c94d" &
    x"c2603efb" &
    x"12d6ede4" &
    x"0900e3ac" &
    x"7d358ae7" &
    x"e2c6dc92"
  ); 
  constant c_PERIOD : time := 10 ns;

begin

  -- Clock process
  process
  begin
    w_clk <= '0';
    wait for c_PERIOD/2;
    w_clk <= '1';
    wait for c_PERIOD/2;
    
    -- When processing done
    if (r_o_valid = '1') then
      -- Check against expected result
      if (r_hash = c_EXPECTED) then
        report "Hash Correct!";
      else
        report "Hash Incorrect!";
      end if;
      
      -- End Simulation
      wait;
    end if;
  end process;
  
  w_reset <= '1', '0' after c_PERIOD;
  r_i_valid <= '1' after c_PERIOD*2; 
  
  dut : blake3
    port map (
      i_clk       => w_clk,
      i_reset     => w_reset,
      i_chain     => r_chain,
      i_mblock    => r_mblock,
      i_counter   => r_counter,
      i_numbytes  => r_numbytes,
      i_dflags    => r_dflags,
      i_valid     => r_i_valid,
      o_hash      => r_hash,
      o_valid     => r_o_valid
    );
  
end behav;
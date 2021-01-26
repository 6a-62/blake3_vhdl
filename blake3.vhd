library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blake3 is
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
end blake3;

architecture behav of blake3 is
  
  type t_state is (
    STATE_IDLE,
    STATE_PREPARE,
    STATE_GCOL,
    STATE_GDIAG,
    STATE_OUTPUT
  );
  signal r_state : t_state := STATE_IDLE;
  
  type t_w32_vec is array(natural range <>) of unsigned(31 downto 0);
  -- Init constants
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
  
  -- 16-word internal state
  signal r_v : t_w32_vec(15 downto 0)  := (others => (others => '0'));
  -- Compression function (g) operation counter
  signal r_gops : integer range 0 to 7  := 0;
  -- Compression round counter
  signal r_round : integer range 0 to 6 := 0;
  
  -- Keymap Schedule
  type t_schedule is array (natural range <>) of integer range 0 to 15;
  constant c_SCHEDULE : t_schedule(0 to 15) := (
    2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8
  ); 
  -- Message block is buffered, shuffled according to keymap each round
  -- Seems to save LUTs over unwrapping full schedule
  signal r_mblock     : unsigned(511 downto 0);
  signal r_mblock_buf : unsigned(511 downto 0);
    
begin

  process (i_clk, i_reset)
  
  begin
    if i_reset = '1' then
      r_state <= STATE_IDLE;
      o_valid <= '0';
      o_hash <= (others => '0');
      
    elsif rising_edge(i_clk) then
      case r_state is
        when STATE_IDLE =>
          -- Wait until inputs are ready
          if i_valid = '1' then
            -- Invalidate output
            o_valid <= '0';
            -- Start
            r_state <= STATE_PREPARE;
          end if;
          
        when STATE_PREPARE =>
          -- Set up initial state
          for ii in 1 to 8 loop
            r_v(ii-1) <= i_chain((ii*32)-1 downto (ii-1)*32);
          end loop;
          r_v(11 downto 8) <= c_IV(3 downto 0);
          r_v(12) <= i_counter(31 downto 0);
          r_v(13) <= i_counter(63 downto 32);
          r_v(14) <= i_numbytes;
          r_v(15) <= i_dflags;
          r_mblock <= i_mblock;
          
          -- Reset counters
          r_round <= 0;
          r_gops <= 0;
          -- Start compression
          r_state  <= STATE_GCOL;  
          
        when STATE_GCOL =>         
          -- Perform quarter-rounds on columns
          -- Each quater-round in parallel, 8 operations each
          case r_gops is
            when 0 =>
              -- Start of new round
              r_v(0) <= r_v(0) + r_v(4) + r_mblock(31 downto 0);
              r_v(1) <= r_v(1) + r_v(5) + r_mblock(95 downto 64);
              r_v(2) <= r_v(2) + r_v(6) + r_mblock(159 downto 128);
              r_v(3) <= r_v(3) + r_v(7) + r_mblock(223 downto 192);
            when 1 =>
              r_v(12) <= (r_v(12) xor r_v(0)) ror 16;
              r_v(13) <= (r_v(13) xor r_v(1)) ror 16;
              r_v(14) <= (r_v(14) xor r_v(2)) ror 16;
              r_v(15) <= (r_v(15) xor r_v(3)) ror 16;
            when 2 | 6 =>  
              r_v(8)  <= r_v(8)  + r_v(12);
              r_v(9)  <= r_v(9)  + r_v(13);
              r_v(10) <= r_v(10) + r_v(14);
              r_v(11) <= r_v(11) + r_v(15);
            when 3 =>  
              r_v(4) <= (r_v(4) xor r_v(8))  ror 12;
              r_v(5) <= (r_v(5) xor r_v(9))  ror 12;
              r_v(6) <= (r_v(6) xor r_v(10)) ror 12;
              r_v(7) <= (r_v(7) xor r_v(11)) ror 12;
            when 4 =>  
              r_v(0) <= r_v(0) + r_v(4) + r_mblock(63 downto 32);
              r_v(1) <= r_v(1) + r_v(5) + r_mblock(127 downto 96);
              r_v(2) <= r_v(2) + r_v(6) + r_mblock(191 downto 160);
              r_v(3) <= r_v(3) + r_v(7) + r_mblock(255 downto 224);
            when 5 =>  
              r_v(12) <= (r_v(12) xor r_v(0)) ror 8;
              r_v(13) <= (r_v(13) xor r_v(1)) ror 8;
              r_v(14) <= (r_v(14) xor r_v(2)) ror 8;
              r_v(15) <= (r_v(15) xor r_v(3)) ror 8;
            when 7 =>
              r_v(4) <= (r_v(4) xor r_v(8))  ror 7;
              r_v(5) <= (r_v(5) xor r_v(9))  ror 7;
              r_v(6) <= (r_v(6) xor r_v(10)) ror 7;
              r_v(7) <= (r_v(7) xor r_v(11)) ror 7;
              -- Done, move to diagonals
              r_state <= STATE_GDIAG;
            when others => null;
          end case;    
          r_gops <= r_gops + 1;
          if r_gops = 7 then
            r_gops <= 0;
          end if;                      
          
        when STATE_GDIAG =>
          -- Perform quarter-rounds on diagonals
          -- Each quater-round in parallel, 8 operations each
          case r_gops is
            when 0 =>
              r_v(0) <= r_v(0) + r_v(5) + r_mblock(287 downto 256);
              r_v(1) <= r_v(1) + r_v(6) + r_mblock(351 downto 320);
              r_v(2) <= r_v(2) + r_v(7) + r_mblock(415 downto 384);
              r_v(3) <= r_v(3) + r_v(4) + r_mblock(479 downto 448);
            when 1 =>
              r_v(15) <= (r_v(15) xor r_v(0)) ror 16;
              r_v(12) <= (r_v(12) xor r_v(1)) ror 16;
              r_v(13) <= (r_v(13) xor r_v(2)) ror 16;
              r_v(14) <= (r_v(14) xor r_v(3)) ror 16;
            when 2 | 6 =>  
              r_v(10) <= r_v(10) + r_v(15);
              r_v(11) <= r_v(11) + r_v(12);
              r_v(8)  <= r_v(8)  + r_v(13);
              r_v(9)  <= r_v(9)  + r_v(14);
            when 3 =>  
              r_v(5) <= (r_v(5) xor r_v(10)) ror 12;
              r_v(6) <= (r_v(6) xor r_v(11)) ror 12;
              r_v(7) <= (r_v(7) xor r_v(8))  ror 12;
              r_v(4) <= (r_v(4) xor r_v(9))  ror 12;
            when 4 =>  
              r_v(0) <= r_v(0) + r_v(5) + r_mblock(319 downto 288);
              r_v(1) <= r_v(1) + r_v(6) + r_mblock(383 downto 352);
              r_v(2) <= r_v(2) + r_v(7) + r_mblock(447 downto 416);
              r_v(3) <= r_v(3) + r_v(4) + r_mblock(511 downto 480);
            when 5 =>  
              r_v(15) <= (r_v(15) xor r_v(0)) ror 8;
              r_v(12) <= (r_v(12) xor r_v(1)) ror 8;
              r_v(13) <= (r_v(13) xor r_v(2)) ror 8;
              r_v(14) <= (r_v(14) xor r_v(3)) ror 8;
              
              -- Buffer message block for next cycle
              r_mblock_buf <= r_mblock;
            when 7 =>
              r_v(5) <= (r_v(5) xor r_v(10))  ror 7;
              r_v(6) <= (r_v(6) xor r_v(11))  ror 7;
              r_v(7) <= (r_v(7) xor r_v(8)) ror 7;
              r_v(4) <= (r_v(4) xor r_v(9)) ror 7;
              -- Done, end of round
              r_round <= r_round + 1;
              -- Start new round or move to next state
              if r_round = 6 then
                r_round <= 0;
                r_state <= STATE_OUTPUT;
              else
                -- Permutate mesg key schedule
                for ii in 1 to 16 loop
                  r_mblock((ii*32)-1 downto (ii-1)*32) <= r_mblock_buf((c_SCHEDULE(ii-1)+1)*32-1 downto c_SCHEDULE(ii-1)*32);
                end loop;
               
                r_state <= STATE_GCOL;
              end if;
            when others => null;
          end case;    
          r_gops <= r_gops + 1;
          if r_gops = 7 then
            r_gops <= 0;
          end if;  
                    
      when STATE_OUTPUT =>
        for ii in 1 to 8 loop
          -- First 8 words (0-255 bits) output
          o_hash((ii*32)-1 downto (ii-1)*32) <= r_v(ii-1) xor r_v(7+ii);
          -- Last 8 words (256-511 bits) output
          o_hash(((8+ii)*32)-1 downto ((8+ii)-1)*32) <= r_v(7+ii) xor i_chain((ii*32)-1 downto (ii-1)*32);
        end loop;
        o_valid <= '1';
        r_state <= STATE_IDLE;
      end case;
    end if;
  
  end process;

end behav;
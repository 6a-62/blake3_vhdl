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
    
  impure function f_A1(
    v_A : in integer;
    v_B : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := r_v(v_A) + r_v(v_B) + r_mblock((32*v_M)-1 downto (v_M-1)*32);
    return v_OUT;
  end;
  
  impure function f_D1(
    v_A : in integer;
    v_B : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := (r_v(v_D) xor f_A1(v_A, v_B, v_M)) ror 16;
    return v_OUT;
  end;
  
  impure function f_C1(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := r_v(v_C) + f_D1(v_A, v_B, v_D, v_M);
    return v_OUT;
  end;
  
  impure function f_B1(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := (r_v(v_B) xor f_C1(v_A, v_B, v_C, v_D, v_M)) ror 12;
    return v_OUT;
  end;
  
  impure function f_A2(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := f_A1(v_A, v_B, v_M) + f_B1(v_A, v_B, v_C, v_D, v_M) + r_mblock((32*v_M)+31 downto (v_M)*32);
    return v_OUT;
  end;
  
  impure function f_D2(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := (f_D1(v_A, v_B, v_D, v_M) xor f_A2(v_A, v_B, v_C, v_D, v_M)) ror 8;
    return v_OUT;
  end;
  
  impure function f_C2(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := f_C1(v_A, v_B, v_C, v_D, v_M) + f_D2(v_A, v_B, v_C, v_D, v_M);
    return v_OUT;
  end;
  
  impure function f_B2(
    v_A : in integer;
    v_B : in integer;
    v_C : in integer;
    v_D : in integer;
    v_M : in integer)
    return unsigned is variable v_OUT : unsigned(31 downto 0);
  begin
    v_OUT := (f_B1(v_A, v_B, v_C, v_D, v_M) xor f_C2(v_A, v_B, v_C, v_D, v_M)) ror 7;
    return v_OUT;
  end;  
  
begin

  process (i_clk, i_reset)
  
  begin
    if i_reset = '0' then
      r_state <= STATE_IDLE;
      o_valid <= '1';
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
          -- Start compression
          r_state  <= STATE_GCOL;  
          
        when STATE_GCOL =>         
          -- Perform quarter-rounds on columns
          -- Each quarter-round in parallel
          r_v(0)  <= f_A2(0, 4, 8,  12, 1);
          r_v(1)  <= f_A2(1, 5, 9,  13, 3);
          r_v(2)  <= f_A2(2, 6, 10, 14, 5);
          r_v(3)  <= f_A2(3, 7, 11, 15, 7);
          
          r_v(12) <= f_D2(0, 4, 8,  12, 1);
          r_v(13) <= f_D2(1, 5, 9,  13, 3);
          r_v(14) <= f_D2(2, 6, 10, 14, 5);
          r_v(15) <= f_D2(3, 7, 11, 15, 7);
          
          r_v(8)  <= f_C2(0, 4, 8,  12, 1);
          r_v(9)  <= f_C2(1, 5, 9,  13, 3);
          r_v(10) <= f_C2(2, 6, 10, 14, 5);
          r_v(11) <= f_C2(3, 7, 11, 15, 7);
          
          r_v(4)  <= f_B2(0, 4, 8,  12, 1);
          r_v(5)  <= f_B2(1, 5, 9,  13, 3);
          r_v(6)  <= f_B2(2, 6, 10, 14, 5);
          r_v(7)  <= f_B2(3, 7, 11, 15, 7);
                   
          -- Done, move to diagonals
          r_state <= STATE_GDIAG;  
          -- Buffer message block for next cycle
          r_mblock_buf <= r_mblock;              
          
        when STATE_GDIAG =>
          -- Perform quarter-rounds on diagonals
          -- Each quater-round in parallel      
          r_v(0)  <= f_A2(0, 5, 10, 15, 9);
          r_v(1)  <= f_A2(1, 6, 11, 12, 11);
          r_v(2)  <= f_A2(2, 7, 8,  13, 13);
          r_v(3)  <= f_A2(3, 4, 9,  14, 15);
          
          r_v(15) <= f_D2(0, 5, 10, 15, 9);
          r_v(12) <= f_D2(1, 6, 11, 12, 11);
          r_v(13) <= f_D2(2, 7, 8,  13, 13);
          r_v(14) <= f_D2(3, 4, 9,  14, 15);
          
          r_v(10) <= f_C2(0, 5, 10, 15, 9);
          r_v(11) <= f_C2(1, 6, 11, 12, 11);
          r_v(8)  <= f_C2(2, 7, 8,  13, 13);
          r_v(9)  <= f_C2(3, 4, 9,  14, 15);
          
          r_v(5) <= f_B2(0, 5, 10, 15, 9);
          r_v(6) <= f_B2(1, 6, 11, 12, 11);
          r_v(7) <= f_B2(2, 7, 8,  13, 13);
          r_v(4) <= f_B2(3, 4, 9,  14, 15);
          
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
            -- New round
            r_state <= STATE_GCOL;
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
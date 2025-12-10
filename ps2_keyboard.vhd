----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09.12.2025 22:57:36
-- Design Name: 
-- Module Name: ps2_keyboard - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;



entity ps2_keyboard is
    Port (
        clk      : in  std_logic;  -- system clock
        rst      : in  std_logic;
        ps2_clk  : in  std_logic;
        ps2_data : in  std_logic;
        key_valid: out std_logic;                      -- 1-cycle pulse on key press
        scan_code: out std_logic_vector(7 downto 0)    -- PS/2 make-code
    );
end ps2_keyboard;

architecture Behavioral of ps2_keyboard is

-- sync + edge detect for ps2_clk
    signal ps2_clk_sync  : std_logic_vector(2 downto 0) := (others => '1');
    signal ps2_clk_fall  : std_logic := '0';

-- frame receiver
    signal bit_count     : integer range 0 to 10 := 0;
    signal shift_reg     : std_logic_vector(10 downto 0) := (others => '1');
    signal byte_ready    : std_logic := '0';
    signal received_byte : std_logic_vector(7 downto 0) := (others => '0');

 -- track break (F0) so we only output MAKE codes
    signal break_pending : std_logic := '0';

begin

-- Synchronize ps2_clk to system clock and detect falling edges
    
    process(clk, rst)
    begin
        if rst = '1' then
            ps2_clk_sync <= (others => '1');
            ps2_clk_fall <= '0';
        elsif rising_edge(clk) then
            ps2_clk_sync <= ps2_clk_sync(1 downto 0) & ps2_clk;
            ps2_clk_fall <= '0';
            if ps2_clk_sync(2 downto 1) = "10" then
                ps2_clk_fall <= '1';
            end if;
        end if;
    end process;

    
-- Shift PS/2 frame in on each falling edge (LSB first)
    
    process(clk, rst)
    begin
        if rst = '1' then
            bit_count     <= 0;
            shift_reg     <= (others => '1');
            byte_ready    <= '0';
            received_byte <= (others => '0');
        elsif rising_edge(clk) then
            byte_ready <= '0';

            if ps2_clk_fall = '1' then
-- shift right, new bit enters MSB (LSB first protocol)
                shift_reg <= ps2_data & shift_reg(10 downto 1);

                if bit_count = 10 then
                    bit_count     <= 0;
                    byte_ready    <= '1';
                    received_byte <= shift_reg(8 downto 1);  -- data bits
                else
                    bit_count <= bit_count + 1;
                end if;
            end if;
        end if;
    end process;

 -- Interpret bytes: ignore BREAK (F0), output only make codes 
 -- Every time a valid key (0-9, A-F, W, S) is pressed and decoded, 
 -- key_valid goes to 1 for one clock cycle, then back to 0
 -- key_activity_led is a register we created that remembers that
 -- activity and toggles its value whenever key_valid = '1'
 
    process(clk, rst)
    begin
        if rst = '1' then
            key_valid     <= '0';
            scan_code     <= (others => '0');
            break_pending <= '0';
        elsif rising_edge(clk) then
            key_valid <= '0';

            if byte_ready = '1' then
                if received_byte = x"F0" then
 -- next byte is the key release code 
                    break_pending <= '1';
                else
                    if break_pending = '1' then
                        -- this is a BREAK code for some key: ignore it
                        break_pending <= '0';
                    else
                        -- this is a MAKE code: output it
                        scan_code <= received_byte;
                        key_valid <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;

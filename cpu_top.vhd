-- what is the process:

-- switches
-- sw3 downto 0 is the hex nibble you are about to enter
-- sw6 downto 4 selects which signature slot you are editing 0 to 7
-- sw8 downto 7 selects the length 00 is 1 byte 01 is 2 bytes 10 is 3 bytes 11 is 4 bytes

-- buttons
-- btnu enters one nibble it shifts current_data left by 4 adds sw3 downto 0 and increases hex_count by 1
-- if hex_count already reached the needed amount for the selected length then btnu does nothing
-- btnl clears the buffer it sets current_data to 0 and sets hex_count to 0
-- btnr writes it pulses cfg_we for one clock so cauid stores cfg_data into the selected cfg_index with the selected cfg_len
-- btnd commits it sets exit_config to 1 and the cpu will leave x0 and start running
-- btnc resets everything same idea as a full restart

-- feedback
-- 7 seg shows nibble on the right then index then length as 1 to 4 then hex_count on the left
-- leds show nibble index length and count plus led13 toggles on every action led15 flashes on write and led14 stays on after commit

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu_top is
    Port(
        clk  : IN std_logic;
        sw   : IN std_logic_vector(15 downto 0);
        led  : OUT std_logic_vector(15 downto 0);
        seg  : OUT std_logic_vector(6 downto 0);
        dp   : OUT std_logic;
        an   : OUT std_logic_vector(3 downto 0);
        btnC, btnU, btnL, btnR, btnD : IN std_logic
    );
end cpu_top;

architecture Behavioral of cpu_top is

    COMPONENT memory is
    PORT (
        clk, rst : IN std_logic;
        addr     : IN std_logic_vector(15 downto 0);
        datawr   : IN std_logic_vector(7 downto 0);
        datard   : OUT std_logic_vector(7 downto 0);
        wr       : IN std_logic;
        sw       : IN std_logic_vector(15 downto 0);
        buttons  : IN std_logic_vector(3 downto 0);
        led      : OUT std_logic_vector(15 downto 0);
        digits   : OUT std_logic_vector(15 downto 0)
    );
    END COMPONENT;

    COMPONENT cpu is
    PORT (
        clk         : IN std_logic;
        rst         : IN std_logic;
        addr        : OUT std_logic_vector(15 downto 0);
        datard      : IN std_logic_vector(7 downto 0);
        datawr      : OUT std_logic_vector(7 downto 0);
        wr          : OUT std_logic;
        stateo      : OUT std_logic_vector(3 downto 0);
        cauid_match : IN std_logic;
        exit_config : IN std_logic
    );
    END COMPONENT;

    COMPONENT interface is
    PORT (
        clk    : IN std_logic;
        rst    : IN std_logic;
        data   : IN std_logic_vector(15 downto 0);
        segm   : OUT std_logic_vector(7 downto 0);
        common : OUT std_logic_vector(3 downto 0);
        butin  : IN std_logic_vector(3 downto 0);
        butout : OUT std_logic_vector(3 downto 0)
    );
    END COMPONENT;

    COMPONENT cauid is
    Port(
        clk      : IN std_logic;
        rst      : IN std_logic;
        datard   : IN std_logic_vector(7 downto 0);
        state    : IN std_logic_vector(3 downto 0);
        match    : OUT std_logic;
        cfg_we   : IN std_logic;
        cfg_index: IN std_logic_vector(2 downto 0);
        cfg_len  : IN std_logic_vector(1 downto 0);
        cfg_data : IN std_logic_vector(31 downto 0)
    );
    END COMPONENT;

    -- these are the modules we plug together
    -- nothing fancy here just the same cpu memory interface and cauid blocks

    SIGNAL addr              : std_logic_vector(15 downto 0);
    SIGNAL datawr, datard    : std_logic_vector(7 downto 0);
    SIGNAL wr                : std_logic;

    SIGNAL led2              : std_logic_vector(15 downto 0);
    SIGNAL digits            : std_logic_vector(15 downto 0);
    SIGNAL buttons_i, buttons: std_logic_vector(3 downto 0);
    SIGNAL segm              : std_logic_vector(7 downto 0);
    SIGNAL creset            : std_logic := '0';
    SIGNAL state             : std_logic_vector(3 downto 0);
    SIGNAL cpu_state         : std_logic_vector(3 downto 0);

    SIGNAL cauid_match       : std_logic;

    SIGNAL current_index     : std_logic_vector(2 downto 0) := (others => '0');
    SIGNAL current_len       : std_logic_vector(1 downto 0) := "11";
    SIGNAL current_data      : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL keyboard_cfg_we   : std_logic := '0';
    SIGNAL exit_config       : std_logic := '0';

    SIGNAL cauid_cfg_we      : std_logic := '0';
    SIGNAL cauid_cfg_index   : std_logic_vector(2 downto 0) := (others => '0');
    SIGNAL cauid_cfg_len     : std_logic_vector(1 downto 0) := "11";
    SIGNAL cauid_cfg_data    : std_logic_vector(31 downto 0) := (others => '0');

    SIGNAL digits_conf       : std_logic_vector(15 downto 0) := (others => '0');
    SIGNAL digits_mux        : std_logic_vector(15 downto 0) := (others => '0');
    SIGNAL led_conf          : std_logic_vector(15 downto 0) := (others => '0');

    SIGNAL buttons_prev      : std_logic_vector(3 downto 0) := (others => '0');
    SIGNAL activity_tog      : std_logic := '0';

    SIGNAL hex_count : integer range 0 to 8 := 0;

    -- these signals are for the config ui
    -- digits_conf and led_conf are what you see in config mode
    -- digits_mux is the little switch that decides what the 7 seg shows
    -- buttons_prev is for click detection so holding a button does not spam input

    function len_to_digit(l : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        case l is
            when "00" => return x"1";
            when "01" => return x"2";
            when "10" => return x"3";
            when others => return x"4";
        end case;
    end function;

    function req_nibbles(l : std_logic_vector(1 downto 0)) return integer is
    begin
        case l is
            when "00" => return 2;
            when "01" => return 4;
            when "10" => return 6;
            when others => return 8;
        end case;
    end function;

    -- these helpers are just for config
    -- len_to_digit makes the display show 1 to 4 for the length
    -- req_nibbles decides how many hex nibbles we accept for that length

begin

    buttons_i <= (btnU, btnL, btnR, btnD);

    digits_mux <= digits_conf when (cpu_state = x"0") else digits;

    seg <= segm(6 downto 0);
    dp  <= NOT cauid_match;

    creset <= btnC;

    cpu_state <= state;

    -- here is wire up of the basys buttons into the interface block
    -- also muxes the 7 seg digits so config mode can show status without touching runtime
    -- dp still shows match just like before

    cauid_cfg_index <= current_index;
    cauid_cfg_len   <= current_len;
    cauid_cfg_data  <= current_data;

    cauid_cfg_we <= keyboard_cfg_we when (cpu_state = x"0") else '0';

    -- connect the config data into cauid
    -- the write enable is only allowed in cpu_state x0 so runtime cannot accidentally rewrite signatures

    ccpu : cpu
        PORT MAP (
            clk         => clk,
            rst         => creset,
            addr        => addr,
            datard      => datard,
            datawr      => datawr,
            wr          => wr,
            stateo      => state,
            cauid_match => cauid_match,
            exit_config => exit_config
        );

    cmem : memory
        PORT MAP (
            clk     => clk,
            rst     => btnC,
            addr    => addr,
            datawr  => datawr,
            datard  => datard,
            wr      => wr,
            sw      => sw,
            buttons => buttons,
            led     => led2,
            digits  => digits
        );

    cint : interface
        PORT MAP (
            clk    => clk,
            rst    => btnC,
            data   => digits_mux,
            segm   => segm,
            common => an,
            butin  => buttons_i,
            butout => buttons
        );

    ccauid : cauid
        PORT MAP (
            clk      => clk,
            rst      => btnC,
            datard   => datard,
            state    => state,
            match    => cauid_match,
            cfg_we   => cauid_cfg_we,
            cfg_index=> cauid_cfg_index,
            cfg_len  => cauid_cfg_len,
            cfg_data => cauid_cfg_data
        );

    -- here we do the normal top level plumbing
    -- cpu talks to memory and reads switches and buttons through memory
    -- interface drives the 7 seg and also gives us a clean 4 bit buttons bus
    -- cauid checks signatures and also has the config ports for writing new ones

    config_ctrl : process(clk, creset)
        variable need : integer;
    begin
        if creset = '1' then
            keyboard_cfg_we <= '0';
            exit_config     <= '0';
            current_index   <= (others => '0');
            current_len     <= "11";
            current_data    <= (others => '0');
            hex_count       <= 0;

            digits_conf     <= (others => '0');
            led_conf        <= (others => '0');
            buttons_prev    <= (others => '0');
            activity_tog    <= '0';

        elsif rising_edge(clk) then
            keyboard_cfg_we <= '0';

            if cpu_state = x"0" then
                current_index <= sw(6 downto 4);
                current_len   <= sw(8 downto 7);

                need := req_nibbles(sw(8 downto 7));

                if (buttons = x"8") and (buttons_prev /= x"8") then
                    if hex_count < need then
                        current_data <= current_data(27 downto 0) & sw(3 downto 0);
                        hex_count    <= hex_count + 1;
                    end if;
                    activity_tog <= not activity_tog;

                elsif (buttons = x"4") and (buttons_prev /= x"4") then
                    current_data <= (others => '0');
                    hex_count    <= 0;
                    activity_tog <= not activity_tog;

                elsif (buttons = x"2") and (buttons_prev /= x"2") then
                    keyboard_cfg_we <= '1';
                    activity_tog    <= not activity_tog;

                elsif (buttons = x"1") and (buttons_prev /= x"1") then
                    exit_config  <= '1';
                    activity_tog <= not activity_tog;
                end if;
            end if;

            digits_conf(3 downto 0)   <= sw(3 downto 0);
            digits_conf(7 downto 4)   <= '0' & current_index;
            digits_conf(11 downto 8)  <= len_to_digit(current_len);
            digits_conf(15 downto 12) <= std_logic_vector(to_unsigned(hex_count, 4));

            led_conf                <= (others => '0');
            led_conf(3 downto 0)    <= sw(3 downto 0);
            led_conf(6 downto 4)    <= current_index;
            led_conf(8 downto 7)    <= current_len;
            led_conf(12 downto 9)   <= std_logic_vector(to_unsigned(hex_count, 4));
            led_conf(13)            <= activity_tog;
            led_conf(14)            <= exit_config;
            led_conf(15)            <= keyboard_cfg_we;

            buttons_prev <= buttons;
        end if;
    end process;

    -- this is the whole config controller
    -- it only does stuff when cpu_state is x0
    -- switches choose index length and nibble
    -- btnu adds a nibble btnl clears btnr writes btnd starts the cpu
    -- digits_conf and led_conf are updated so you get feedback while typing

    led <= led_conf when (cpu_state = x"0") else led2;

    -- this last bit makes leds show config feedback only in config mode
    -- after you start the cpu you get the normal runtime leds from memory again

end Behavioral;
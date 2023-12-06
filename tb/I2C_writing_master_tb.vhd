------------------------
-- IMPORTED LIBRARIES --
------------------------
LIBRARY IEEE;
LIBRARY modelsim_lib;               --INit_SIGNAL_spy() imPORT
USE modelsim_lib.util.ALL;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

---------------------------
-- TB ENTITY DECLARATION --
---------------------------
ENTITY I2C_writing_master_tb IS
END ENTITY I2C_writing_master_tb;

-----------------------------
-- ARCHITECTURE DEFINITION --
-----------------------------
ARCHITECTURE behavioral OF I2C_writing_master_tb IS

    ---------------------------
    -- COMPONENTS DEFINITION --
    ---------------------------
    --Master COMPONENT
    COMPONENT I2C_writing_master
        PORT(
            clock   : IN std_logic;       --clock, reset PORTs
            reset   : IN std_logic;
            addr    : IN std_logic_vector (6 DOWNTO 0);       --INput PORTs
            data    : IN std_logic_vector (7 DOWNTO 0);
            valid   : IN std_logic;
            repeat  : IN std_logic;       --additional
            sda_in  : IN std_logic;
            sda_out : OUT std_logic;      
            scl     : OUT std_logic
        );  
    END COMPONENT I2C_writINg_master;

    ----------------------------
    -- CONSTANTS DECLARATION ---
    ----------------------------
    CONSTANT CLOCK_PERIOD       : time := 1000 ns;
    CONSTANT CLOCK_LAG          : integer := 32;            --times scl IS slower than clock
    CONSTANT WRONG_SLAVE_ADDR   : std_logic_vector := "1001111";
    CONSTANT OK_SLAVE_ADDR      : std_logic_vector := "1011001";        --on 7 bits
    CONSTANT DATA_BYTE_1        : std_logic_vector := "11001010";       --on 8 bits
    CONSTANT DATA_BYTE_2        : std_logic_vector := "01101001";
    CONSTANT ACK_DURATION       : integer RANGE 0 TO 2 * CLOCK_LAG - 1 := 2 * CLOCK_LAG - 1;

    -------------------------
    -- SIGNALS DECLARATION --
    -------------------------
    --Master signals
    SIGNAL clock_ext    : std_logic := '0';
    SIGNAL reset_ext    : std_logic := '0';
    SIGNAL addr_ext     : std_logic_vector (6 DOWNTO 0) := (OTHERS => '0');
    SIGNAL data_ext     : std_logic_vector (7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL valid_ext    : std_logic := '0';
    SIGNAL repeat_ext   : std_logic := '0';
    SIGNAL scl_ext      : std_logic;
    SIGNAL sda_in_ext   : std_logic := '1';
    SIGNAL sda_out_ext  : std_logic;

    --Other signals
    SIGNAL testing          : std_logic := '1';
    SIGNAL current_state    : std_logic_vector (2 DOWNTO 0) := "000";
    SIGNAL iteration        : integer RANGE 0 TO 3 := 0;
    SIGNAL bit_counter      : integer RANGE 0 TO 7 := 0;

BEGIN

    --clock signal generation
    clock_ext <= (NOT(clock_ext) AND testing) AFTER CLOCK_PERIOD / 2;

    -----------------------------
    -- COMPONENTS PORT MAPPING --
    -----------------------------
    DUT: I2C_writing_master
        PORT MAP(
            clock   => clock_ext,
            reset   => reset_ext,
            addr    => addr_ext,
            data    => data_ext,
            valid   => valid_ext,
            repeat  => repeat_ext,
            sda_in  => sda_in_ext,
            sda_out => sda_out_ext,
            scl     => scl_ext
        );


    SPY_PROCESS1: PROCESS
    BEGIN
        init_signal_spy("/I2C_writing_master_tb/DUT/current_state_representation", "/current_state", 1);
        WAIT;
    END PROCESS SPY_PROCESS1;

    SPY_PROCESS2: PROCESS
    BEGIN
        init_signal_spy("/I2C_writing_master_tb/DUT/bit_counter", "/bit_counter", 1);
        WAIT;
    END PROCESS SPY_PROCESS2;
    
    ----------------------
    -- STIMULUS PROCESS --
    ----------------------
    STIMULUS: PROCESS(clock_ext, reset_ext)
        VARIABLE clock_cycle : integer := 0;
    BEGIN
        CASE iteration IS 
            --ITERATION #0:
            --wrong addr is provided, the master reads a NACK, stops and goes back to IDLE
            WHEN 0 =>             
                IF rising_edge(clock_ext) THEN
                    IF clock_cycle = 20 THEN
                        reset_ext <= '1';

                    ELSIF clock_cycle = 21 THEN
                        reset_ext <= '0';
                        data_ext <= DATA_BYTE_1;
                        addr_ext <= WRONG_SLAVE_ADDR;
                        repeat_ext <= '0';

                    ELSIF clock_cycle = 30 THEN
                        valid_ext <= '1';
                    ELSIF clock_cycle = 31 THEN
                        valid_ext <= '0';

                    ELSIF clock_cycle = 800 THEN            --end of first simulation case
                        clock_cycle := 0;
                        iteration <= 1;
                        --testing <= '0';
                    END IF;

                    clock_cycle := clock_cycle + 1;
                END IF;
            
            --ITERATION #1:
            --right addr is provided, a NACK is generated for the data, no repeat is asserted
            --master reads the data NACK, stops and goes back to IDLE
            WHEN 1 =>
                IF rising_edge(clock_ext) THEN
                    IF clock_cycle = 20 THEN
                        data_ext <= DATA_BYTE_1;
                        addr_ext <= OK_SLAVE_ADDR;
                        repeat_ext <= '0';

                    ELSIF clock_cycle = 30 THEN
                        valid_ext <= '1';
                    ELSIF clock_cycle = 31 THEN
                        valid_ext <= '0';

                    ELSIF clock_cycle = 605 THEN            --ADDR ACK
                        sda_in_ext <= '0';
                    ELSIF clock_cycle = 605 + ACK_DURATION THEN
                        sda_in_ext <= '1';

                    ELSIF clock_cycle = 1181 THEN           --DATA NACK
                        sda_in_ext <= '1';
                    ELSIF clock_cycle = 1181 + ACK_DURATION THEN
                        sda_in_ext <= '1';
                
                    ELSIF clock_cycle = 1800 THEN           --end of second simulation phase
                        clock_cycle := 0;
                        iteration <= 2;
                        --testing <= '0';
                    END IF;

                    clock_cycle := clock_cycle + 1;
                END IF;

            --ITERATION #2:
            --right addr is provided, ACK is generated for the data, REPEAT IS ASSERTED
            WHEN 2 =>
                IF rising_edge(clock_ext) THEN
                    IF clock_cycle = 20 THEN
                        data_ext <= DATA_BYTE_1;
                        addr_ext <= OK_SLAVE_ADDR;
                        repeat_ext <= '1';              --repeat assertion

                    ELSIF clock_cycle = 30 THEN
                        valid_ext <= '1';
                    ELSIF clock_cycle = 31 THEN
                        valid_ext <= '0';

                    ELSIF clock_cycle = 605 THEN            --ADDR ACK
                        sda_in_ext <= '0';
                    ELSIF clock_cycle = 605 + ACK_DURATION THEN
                        sda_in_ext <= '1';

                    ELSIF clock_cycle = 1181 THEN           --DATA ACK
                        sda_in_ext <= '0';
                    ELSIF clock_cycle = 1181 + ACK_DURATION THEN
                        sda_in_ext <= '1';
                
                    ELSIF clock_cycle = 1800 THEN           --end of second simulation phase
                        clock_cycle := 0;
                        iteration <= 3;
                        --testing <= '0';
                    END IF;

                    clock_cycle := clock_cycle + 1;
                END IF;

            --ITERATION #3:
            --right addr is provided, ACK is generated for the data, no repeat is asserted
            WHEN 3 =>
                IF rising_edge(clock_ext) THEN
                    IF clock_cycle = 20 THEN
                        data_ext <= DATA_BYTE_2;
                        addr_ext <= OK_SLAVE_ADDR;
                        repeat_ext <= '0';

                    ELSIF clock_cycle = 30 THEN
                        valid_ext <= '1';
                    ELSIF clock_cycle = 31 THEN
                        valid_ext <= '0';

                    ELSIF clock_cycle = 605 THEN            --ADDR ACK
                        sda_in_ext <= '0';
                    ELSIF clock_cycle = 605 + ACK_DURATION THEN
                        sda_in_ext <= '1';

                    ELSIF clock_cycle = 1181 THEN           --DATA ACK
                        sda_in_ext <= '0';
                    ELSIF clock_cycle = 1181 + ACK_DURATION THEN
                        sda_in_ext <= '1';
                
                    ELSIF clock_cycle = 1800 THEN           --end of simulation
                        testing <= '0';
                    END IF;

                    clock_cycle := clock_cycle + 1;
                END IF;

            WHEN OTHERS =>
                NULL;
        END CASE;
    END PROCESS STIMULUS;

END ARCHITECTURE behavioral;

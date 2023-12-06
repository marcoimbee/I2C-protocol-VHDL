------------------------
-- IMPORTED LIBRARIES --
------------------------
LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

------------------------
-- ENTITY DECLARATION --
------------------------
ENTITY I2C_writing_master IS
    PORT (
        clock   : IN std_logic;
        reset   : IN std_logic;
        addr    : IN std_logic_vector (6 DOWNTO 0);
        data    : IN std_logic_vector (7 DOWNTO 0);
        valid   : IN std_logic;
        repeat  : IN std_logic;
        sda_in  : IN std_logic;      --implementation OF the inout features via two uni-directional ports
        sda_out : OUT std_logic;
        scl     : OUT std_logic
    );
END ENTITY;


-----------------------------
-- ARCHITECTURE DEFINITION --
-----------------------------
ARCHITECTURE behavioral OF I2C_writing_master IS

    ----------------------------
    -- CONSTANTS DECLARATION ---
    ----------------------------
    CONSTANT WRITE_BIT  : std_logic := '0';
    CONSTANT STOP_BIT   : std_logic := '1';
    CONSTANT START_BIT  : std_logic := '0';
    CONSTANT ACK        : std_logic := '0';
    CONSTANT NACK       : std_logic := '1';
    CONSTANT CLOCK_LAG  : integer   := 32;          --times SCL is slower than CLOCK

    ----------------------------
    -- FSM STATES DECLARATION --
    ----------------------------
    TYPE state IS (IDLE, START, SEND_BIT, COUNTER_UPDATE, ACK_RECEPTION, REPEATED_START, STOP);
    SIGNAL current_state : state;

    -------------------------
    -- SIGNALS DECLARATION --
    -------------------------
    SIGNAL bit_counter                      : integer RANGE 0 TO 7;                 --used to keep track of which bit has to be sent    
    SIGNAL scl_counter                      : integer RANGE 0 TO CLOCK_LAG - 1;     --used to make SCL slower than CLOCK
    SIGNAL transmitting                     : std_logic;                            --transmission started (START bit has been sent)
    SIGNAL current_state_representation     : std_logic_vector (2 DOWNTO 0);        --used for testing purposes
    SIGNAL transmitted_seq                  : std_logic;                            --tells what we have just transmitted (0 = addr + write bit, 1 = data)
    SIGNAL byte                             : std_logic_vector (7 DOWNTO 0);        --byte that will be sent on SDA serially
    SIGNAL stop_counter                     : integer RANGE 0 TO 2 * CLOCK_LAG - 1;     --used when generating the STOP condition
    SIGNAL scl_enable                       : integer RANGE 0 TO 2 * CLOCK_LAG - 1;     --used when there is the need to restart SCL
    SIGNAL repeating                        : std_logic;                                --tells if we are in a REPEATED START condition

    --Register signals
    SIGNAL addr_internal                    : std_logic_vector (6 DOWNTO 0);
    SIGNAL data_internal                    : std_logic_vector (7 DOWNTO 0);
    SIGNAL valid_internal                   : std_logic;
    SIGNAL repeat_internal                  : std_logic;
    SIGNAL scl_internal                     : std_logic;
    SIGNAL sda_out_internal                 : std_logic;
    SIGNAL sda_in_internal                  : std_logic;


BEGIN

    ---------------------------------------
    -- SCL CLOCK LINE GENERATION PROCESS --
    ---------------------------------------
    SCL_GENERATION_PROCESS : PROCESS(clock, transmitting, reset)
    BEGIN
        IF reset = '1' THEN
            scl_counter <= CLOCK_LAG - 1;
            scl_internal <= '1';
            scl_enable <= 2 * CLOCK_LAG - 1;
        ELSE
            IF rising_edge(clock) THEN
                IF transmitting = '1' AND scl_enable = 0 THEN          --SCL starts only when 'transmitting' is asserted
                    IF scl_counter = 0 THEN                     --half SCL period has passed
                        scl_internal <= NOT scl_internal;       --SCL update
                        scl_counter <= CLOCK_LAG - 1;           --counter reset
                    ELSE
                        scl_counter <= scl_counter - 1;         --counter update
                    END IF;
                ELSE
                    scl_internal <= '1';            --if we are not transmitting SCL is kept at 1
                    scl_counter <= CLOCK_LAG - 1;
                END IF;
            END IF;
    
            IF transmitting = '0' THEN          
                scl_internal <= '1';
                scl_enable <= 2 * CLOCK_LAG - 1;
            ELSE
                IF scl_enable /= 0 THEN
                    scl_enable <= scl_enable - 1;
                END IF;
            END IF;
        END IF; 
    END PROCESS SCL_GENERATION_PROCESS;

    -----------------------------
    -- CONTINUOUS ASSIGNEMENTS --
    -----------------------------
    addr_internal <= addr;
    data_internal <= data;
    repeat_internal <= repeat;
    valid_internal <= valid; 
    scl <= scl_internal;
    sda_in_internal <= sda_in;
    sda_out <= sda_out_internal;

    -----------------
    -- FSM PROCESS --
    -----------------
    I2C_BEHAVIOR : PROCESS(scl_internal, valid, reset, clock)
    BEGIN
        IF reset = '1' THEN             --AT RESET:
            repeating <= '0';               --'repeating' is set to 0 and will be checked in ACK_RECEPTION
            current_state <= IDLE;          --the initial state is IDLE
            transmitting <= '0';            --we aren't transmitting yet, so SCL is kept at 1 
            sda_out_internal <= '1';                 --same as SCL
            transmitted_seq <= '0';         --reset the transmitted sequence, 0 for ADDR
            byte <= "00000000";             --emptying the byte register
        ELSE

            CASE current_state IS 

                WHEN IDLE =>            --000
                    transmitted_seq <= '0';
                    sda_out_internal <= '1'; 
                    byte <= "00000000";   
                    IF repeating = '1' AND rising_edge(scl_internal) THEN  --IF IN REPEATED START mode: wait for an additional half period before locking SCL to 1
                        transmitting <= '0';
                        repeating <= '0';       
                    END IF;
                    IF valid_internal = '1' THEN         --waiting for 'valid' to be asserted
                        transmitting <= '1';        --when 'valid' gets asserted, we start SCL and go to START
                        current_state <= START;
                        byte <= addr & WRITE_BIT;   --byte composition
                    END IF;

                WHEN START =>           --001
                    sda_out_internal <= START_BIT;           --sending START_BIT (= 0)
                    bit_counter <= 7;
                    IF scl_enable = 1 THEN          --If this condition is met, the time is right to start transmitting the bits
                        current_state <= SEND_BIT;
                    END IF;

                WHEN SEND_BIT =>   --010
                    IF falling_edge(scl_internal) THEN      --bits get transmitted at every falling edge of SCL
                        sda_out_internal <= byte(bit_counter);
                        current_state <= COUNTER_UPDATE;    --state to update the bit counter at the right time
                    END IF; 
                
                WHEN COUNTER_UPDATE =>      --011
                    IF falling_edge(scl_internal) AND bit_counter = 0 THEN   --updating state and bit counter in moments that don't interfere with the transmission
                        current_state <= ACK_RECEPTION;
                        bit_counter <= 7;
                    END IF;
                    IF rising_edge(scl_internal) AND bit_counter /= 0 THEN
                        bit_counter <= bit_counter - 1;
                        current_state <= SEND_BIT;
                    END IF;

                WHEN ACK_RECEPTION =>   --100 -> WHEN HERE, THE STATE WILL CHANGE RIGHT AWAY 
                    IF transmitted_seq = '0' THEN       --just transmitted an ADDRESS
                        transmitted_seq <= '1';             --prepare to transmit data
                        IF sda_in_internal = '0' THEN                    --ACK for ADDR, active low
                            byte <= data;                           --prepare data
                            current_state <= SEND_BIT;              --send that data
                        ELSE                                    --NACK for ADDR
                            current_state <= STOP;                  --received a NACK for an ADDR, it has no sense to keep on transmitting, send STOP and go back to IDLE
                        END IF;
                    ELSIF transmitted_seq = '1' THEN    --just transmitted a DATA byte
                        IF sda_in_internal = '0' THEN                --ACK for DATA byte, active low
                            IF repeat_internal = '1' THEN                --REPEATED START CONDITION
                                current_state <= REPEATED_START;    --taking care of the repeated start procedure
                            ELSE
                                current_state <= STOP;              --no repeated start, so STOP
                            END IF;
                        ELSE                                 --NACK for DATA byte
                            current_state <= STOP;              --STOP bit, back to IDLE for new transmission or eventual retransmission
                        END IF;
                    END IF;

                WHEN REPEATED_START =>  --110
                    IF falling_edge(scl_internal) THEN      --wait until the falling edge of SCL to:
                        repeating <= '1';                       --set 'repeating', will be used in IDLE
                        sda_out_internal <= '1';                         --set sda_out to 1 as in every end of transmission
                        current_state <= IDLE;                  --get back to IDLE
                    END IF;

                WHEN STOP =>            --101
                    IF scl_counter = 1 THEN         --wait until an SCL edge to lock it to 1      
                        transmitting <= '0';
                    ELSIF stop_counter = 0 THEN     --the duration of the time to wait before sending the STOP BIT has elapsed
                        sda_out_internal <= STOP_BIT;            --send STOP BIT (= 1 when SCL high)
                        current_state <= IDLE;          --get back to IDLE
                    END IF;


                WHEN OTHERS =>
                    --NULL;
                    byte <= byte;
                    transmitted_seq <= transmitted_seq;

            END CASE;
        END IF;
    END PROCESS;

    ---------------------------------------
    -- STOP CONDITION GENERATION PROCESS --
    ---------------------------------------
    STOP_CONDITION_GENERATION: PROCESS(clock, reset)
    BEGIN   
        IF reset = '1' THEN
            stop_counter <= 2 * CLOCK_LAG - 1;      --at reset, reset the time to be waited before sending the STOP BIT 
        ELSE
            IF rising_edge(clock) THEN
                CASE current_state is
                    WHEN STOP =>
                        IF stop_counter /= 0 THEN
                            stop_counter <= stop_counter - 1;       --waiting the time due
                        END IF;

                    WHEN IDLE =>
                        stop_counter <= 2 * CLOCK_LAG - 1;          --resetting the counter when passing from IDLE

                    WHEN OTHERS =>
                        NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS STOP_CONDITION_GENERATION;

    --setting current_state_representation (for testing purposes)
    WITH current_state SELECT
        current_state_representation <= "000" WHEN IDLE,     
            "001" WHEN START,
            "010" WHEN SEND_BIT,
            "011" WHEN COUNTER_UPDATE,
            "100" WHEN ACK_RECEPTION,
            "101" WHEN STOP,
            "110" WHEN REPEATED_START;

END ARCHITECTURE behavioral;

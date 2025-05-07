library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity FSM_PRINCIPAL is
    Port (
        clk             : in  STD_LOGIC;
        rst             : in  STD_LOGIC;
        -- Entradas de sensores y botones
        sensor_piso     : in  STD_LOGIC_VECTOR(4 downto 0);  -- Sensores de cada piso (1-5)
        btn_subir       : in  STD_LOGIC_VECTOR(4 downto 0);  -- Botones externos para subir
        btn_bajar       : in  STD_LOGIC_VECTOR(4 downto 0);  -- Botones externos para bajar
        btn_piso        : in  STD_LOGIC_VECTOR(4 downto 0);  -- Botones internos para seleccionar piso
        btn_abrir       : in  STD_LOGIC;                     -- Botón para abrir puertas
        btn_cerrar      : in  STD_LOGIC;                     -- Botón para cerrar puertas
        btn_emergencia  : in  STD_LOGIC;                     -- Botón de emergencia
        anomalia_energia: in  STD_LOGIC;                     -- Señal de anomalía de energía
        num_personas    : in  STD_LOGIC_VECTOR(3 downto 0);  -- Número de personas (0-10)
        tiempo_puerta   : in  STD_LOGIC;                     -- Señal de temporizador de puerta
        tiempo_inactivo : in  STD_LOGIC;                     -- Señal de temporizador de inactividad
        tiempo_entre_pisos : in  STD_LOGIC;                  -- Señal de temporizador entre pisos
        
        -- Salidas para controles
        motor_subir     : out STD_LOGIC;                     -- Control motor para subir
        motor_bajar     : out STD_LOGIC;                     -- Control motor para bajar
        abrir_puerta    : out STD_LOGIC;                     -- Control para abrir puerta
        cerrar_puerta   : out STD_LOGIC;                     -- Control para cerrar puerta
        luz_cabina      : out STD_LOGIC;                     -- Control de luz de cabina
        alarma_sonora   : out STD_LOGIC;                     -- Control de alarma sonora
        alarma_visual   : out STD_LOGIC;                     -- Control de alarma visual
        piso_actual     : out STD_LOGIC_VECTOR(2 downto 0);  -- Piso actual (3 bits: 001-101)
        estado_error    : out STD_LOGIC;                     -- Indicador de estado de error
        reset_timer_puerta : out STD_LOGIC;                  -- Reset para timer de puerta
        reset_timer_inactividad : out STD_LOGIC;             -- Reset para timer de inactividad
        reset_timer_entre_pisos : out STD_LOGIC              -- Reset para timer entre pisos
    );
end FSM_PRINCIPAL;

architecture Arch_fsm of FSM_PRINCIPAL is
    -- Definición de estados
    type estado_tipo is (
        IDLE,           -- Ascensor inactivo
        DOOR_OPENING,   -- Puerta abriéndose
        DOOR_OPEN,      -- Puerta abierta
        DOOR_CLOSING,   -- Puerta cerrándose
        MOVING_UP,      -- Ascensor subiendo
        MOVING_DOWN,    -- Ascensor bajando
        ERROR           -- Estado de error
    );
    
    -- Señales internas
    signal estado_actual, estado_siguiente : estado_tipo;
    signal piso_destino : STD_LOGIC_VECTOR(2 downto 0);
    signal piso_reg : STD_LOGIC_VECTOR(2 downto 0) := "001"; -- Iniciar en piso 1
    signal solicitud_pendiente : STD_LOGIC;
    signal direccion : STD_LOGIC; -- '0' para bajar, '1' para subir
    signal hay_solicitud_arriba, hay_solicitud_abajo : STD_LOGIC;
    signal sobrecarga : STD_LOGIC;
    
begin
    -- Verificar sobrecarga (más de 10 personas)
    sobrecarga <= '1' when unsigned(num_personas) > 10 else '0';
    
    -- Verificar si hay solicitudes arriba o abajo del piso actual
    process(btn_subir, btn_bajar, btn_piso, piso_reg)
    begin
        hay_solicitud_arriba <= '0';
        hay_solicitud_abajo <= '0';
        
        for i in 0 to 4 loop
            -- Convertir índice a representación de piso
            if unsigned(piso_reg) < i+1 then
                if btn_subir(i) = '1' or btn_bajar(i) = '1' or btn_piso(i) = '1' then
                    hay_solicitud_arriba <= '1';
                end if;
            elsif unsigned(piso_reg) > i+1 then
                if btn_subir(i) = '1' or btn_bajar(i) = '1' or btn_piso(i) = '1' then
                    hay_solicitud_abajo <= '1';
                end if;
            end if;
        end loop;
    end process;
    
    -- Proceso para señal de solicitud pendiente
    process(btn_subir, btn_bajar, btn_piso)
    begin
        solicitud_pendiente <= '0';
        for i in 0 to 4 loop
            if btn_subir(i) = '1' or btn_bajar(i) = '1' or btn_piso(i) = '1' then
                solicitud_pendiente <= '1';
            end if;
        end loop;
    end process;
    
    -- Registro de estado
    process(clk, rst)
    begin
        if rst = '1' then
            estado_actual <= IDLE;
            piso_reg <= "001"; -- Iniciar en piso 1
        elsif rising_edge(clk) then
            estado_actual <= estado_siguiente;
            
            -- Actualizar piso actual solo cuando haya llegado a un piso
            for i in 0 to 4 loop
                if estado_actual = MOVING_UP or estado_actual = MOVING_DOWN then
                    if sensor_piso(i) = '1' then
                        piso_reg <= std_logic_vector(to_unsigned(i+1, 3));
                    end if;
                end if;
            end loop;
        end if;
    end process;
    
    -- Lógica de próximo estado
    process(estado_actual, solicitud_pendiente, btn_subir, btn_bajar, btn_piso, sensor_piso, 
            btn_abrir, btn_cerrar, btn_emergencia, tiempo_puerta, tiempo_inactivo, tiempo_entre_pisos,
            sobrecarga, anomalia_energia, hay_solicitud_arriba, hay_solicitud_abajo, piso_reg)
    begin
        -- Valor predeterminado para evitar latches
        estado_siguiente <= estado_actual;
        
        case estado_actual is
            when IDLE =>
                -- En estado de inactividad
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif solicitud_pendiente = '1' then
                    estado_siguiente <= DOOR_OPENING;
                elsif tiempo_inactivo = '1' then
                    -- Mantener en IDLE después de cierto tiempo de inactividad
                    estado_siguiente <= IDLE;
                end if;
                
            when DOOR_OPENING =>
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif tiempo_puerta = '1' then
                    estado_siguiente <= DOOR_OPEN;
                end if;
                
            when DOOR_OPEN =>
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif btn_cerrar = '1' then
                    estado_siguiente <= DOOR_CLOSING;
                elsif tiempo_puerta = '1' then
                    -- Después de 45 segundos
                    estado_siguiente <= DOOR_CLOSING;
                end if;
                
            when DOOR_CLOSING =>
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif btn_abrir = '1' then
                    estado_siguiente <= DOOR_OPENING;
                elsif tiempo_puerta = '1' then
                    -- Después de completar el cierre
                    if sobrecarga = '1' then
                        estado_siguiente <= ERROR;
                    elsif solicitud_pendiente = '1' then
                        -- Determinar si debe subir o bajar
                        if hay_solicitud_arriba = '1' then
                            estado_siguiente <= MOVING_UP;
                        elsif hay_solicitud_abajo = '1' then
                            estado_siguiente <= MOVING_DOWN;
                        else
                            -- Si hay solicitud en piso actual, abrir puertas
                            estado_siguiente <= DOOR_OPENING;
                        end if;
                    else
                        estado_siguiente <= IDLE;
                    end if;
                end if;
                
            when MOVING_UP =>
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif tiempo_entre_pisos = '1' then
                    -- Verificar si hemos llegado a un piso
                    if unsigned(piso_reg) <= 5 then
                        -- Verificar si hay solicitud en el piso actual
                        if btn_subir(to_integer(unsigned(piso_reg)-1)) = '1' or 
                           btn_bajar(to_integer(unsigned(piso_reg)-1)) = '1' or 
                           btn_piso(to_integer(unsigned(piso_reg)-1)) = '1' then
                            estado_siguiente <= DOOR_OPENING;
                        elsif hay_solicitud_arriba = '1' then
                            estado_siguiente <= MOVING_UP;
                        else
                            estado_siguiente <= DOOR_OPENING;
                        end if;
                    else
                        estado_siguiente <= DOOR_OPENING;
                    end if;
                end if;
                
            when MOVING_DOWN =>
                if anomalia_energia = '1' or btn_emergencia = '1' then
                    estado_siguiente <= ERROR;
                elsif tiempo_entre_pisos = '1' then
                    -- Verificar si hemos llegado a un piso
                    if unsigned(piso_reg) >= 1 then
                        -- Verificar si hay solicitud en el piso actual
                        if btn_subir(to_integer(unsigned(piso_reg)-1)) = '1' or 
                           btn_bajar(to_integer(unsigned(piso_reg)-1)) = '1' or 
                           btn_piso(to_integer(unsigned(piso_reg)-1)) = '1' then
                            estado_siguiente <= DOOR_OPENING;
                        elsif hay_solicitud_abajo = '1' then
                            estado_siguiente <= MOVING_DOWN;
                        else
                            estado_siguiente <= DOOR_OPENING;
                        end if;
                    else
                        estado_siguiente <= DOOR_OPENING;
                    end if;
                end if;
                
            when ERROR =>
                if btn_emergencia = '0' and anomalia_energia = '0' and sobrecarga = '0' then
                    estado_siguiente <= IDLE;
                end if;
                
        end case;
    end process;
    
    -- Lógica de salidas
    process(estado_actual, piso_reg)
    begin
        -- Valores predeterminados para evitar latches
        motor_subir <= '0';
        motor_bajar <= '0';
        abrir_puerta <= '0';
        cerrar_puerta <= '0';
        luz_cabina <= '0';
        alarma_sonora <= '0';
        alarma_visual <= '0';
        estado_error <= '0';
        reset_timer_puerta <= '0';
        reset_timer_inactividad <= '0';
        reset_timer_entre_pisos <= '0';
        
        -- Siempre mostrar el piso actual
        piso_actual <= piso_reg;
        
        case estado_actual is
            when IDLE =>
                -- Luz apagada en inactividad
                luz_cabina <= '0';
                reset_timer_inactividad <= '1';
                
            when DOOR_OPENING =>
                abrir_puerta <= '1';
                luz_cabina <= '1';
                reset_timer_puerta <= '1';
                alarma_sonora <= '1'; -- Señal sonora de apertura
                alarma_visual <= '1'; -- Señal visual de apertura
                
            when DOOR_OPEN =>
                luz_cabina <= '1';
                reset_timer_puerta <= '1';
                
            when DOOR_CLOSING =>
                cerrar_puerta <= '1';
                luz_cabina <= '1';
                reset_timer_puerta <= '1';
                alarma_sonora <= '1'; -- Señal sonora de cierre
                alarma_visual <= '1'; -- Señal visual de cierre
                
            when MOVING_UP =>
                motor_subir <= '1';
                luz_cabina <= '1';
                reset_timer_entre_pisos <= '1';
                
            when MOVING_DOWN =>
                motor_bajar <= '1';
                luz_cabina <= '1';
                reset_timer_entre_pisos <= '1';
                
            when ERROR =>
                alarma_sonora <= '1';
                alarma_visual <= '1';
                estado_error <= '1';
                -- Puerta cerrada en caso de anomalía de energía
                cerrar_puerta <= '1';
                
        end case;
    end process;

end Arch_fsm;
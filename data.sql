-- =============================================================================
-- ENTREGABLE PARTE A: POBLACIÓN DE DATOS REALES Y SINTÉTICOS DE TELEMETRÍA (data.sql)
-- AUTOR: Juan José
-- INCLUYE: Instrumento UX BANGS oficial, 3 Episodios, 6 Jugadores y +21,000 Tics de Telemetría
-- =============================================================================

BEGIN;

-- LIMPIEZA DE TABLAS (Evita errores de duplicados si se corre más de una vez)
TRUNCATE respuesta_ux, evento_telemetria, participante_partida, partida, jugador, usuario, sector, mapa, item_ux, instrumento_ux, episodio RESTART IDENTITY CASCADE;

-- 1. POBLACIÓN DEL INSTRUMENTO CIENTÍFICO UX: BANGS
INSERT INTO instrumento_ux (id_instrumento, nombre, descripcion) VALUES
(1, 'BANGS', 'Boredom, Anxiety, Nausea, Frustration, and Game-Satisfaction Scale para Videojuegos de Disparos en Primera Persona')
ON CONFLICT (id_instrumento) DO NOTHING;

INSERT INTO item_ux (id_item, texto_pregunta, dimension, id_instrumento) VALUES
(1, '¿Se sintió aburrido durante las secciones de backtracking en el mapa?', 'Boredom', 1),
(2, '¿Sintió que los laberintos del mapa eran monótonos o repetitivos?', 'Boredom', 1),
(3, '¿Experimentó ansiedad alta por la escasez de munición en zonas críticas?', 'Anxiety', 1),
(4, '¿El sonido ambiental o los ataques sorpresa le generaron sobresalto extremo?', 'Anxiety', 1),
(5, '¿Sintió mareo, náuseas o fatiga visual por la velocidad del FOV y movimiento?', 'Nausea', 1),
(6, '¿La tasa de refresco o los cambios bruscos de cámara afectaron su bienestar?', 'Nausea', 1),
(7, '¿Le causó frustración perderse reiteradamente debido al diseño vertical del sector?', 'Frustration', 1),
(8, '¿Sintió frustración injusta por la distribución de daño de los enemigos?', 'Frustration', 1),
(9, '¿Considera satisfactoria la fluidez del control y la respuesta de las armas?', 'Game-Satisfaction', 1),
(10, '¿La experiencia general de completar el nivel cumplió sus expectativas?', 'Game-Satisfaction', 1)
ON CONFLICT (id_item) DO NOTHING;

-- 2. POBLACIÓN DE EPISODIOS (Mínimo 3)
INSERT INTO episodio (id_episodio, nombre_episodio) VALUES
(1, 'Knee-Deep in the Dead'),
(2, 'The Shores of Hell'),
(3, 'Inferno')
ON CONFLICT (id_episodio) DO NOTHING;

-- 3. POBLACIÓN DE MAPAS
INSERT INTO mapa (id_mapa, id_episodio, codigo_mapa, nombre_mapa) VALUES
(1, 1, 'E1M1', 'Hangar'),
(2, 2, 'E2M1', 'Deimos Lab'),
(3, 3, 'E3M1', 'Hell Keep')
ON CONFLICT (id_mapa) DO NOTHING;

-- 4. POBLACIÓN DE SECTORES
INSERT INTO sector (id_sector, id_mapa, codigo_sector, coordenada_x, coordenada_y) VALUES
(1, 1, 'SEC_START', 0.00, 0.00),
(2, 1, 'SEC_COURTYARD', 1500.50, -800.20),
(3, 2, 'SEC_CONTAINMENT', -500.00, 1200.00),
(4, 3, 'SEC_THRONE', 666.00, 666.00)
ON CONFLICT (id_sector) DO NOTHING;

-- 5. POBLACIÓN DE USUARIOS CON CONSENTIMIENTO (Mínimo 6)
INSERT INTO usuario (id_usuario, codigo_anonimo, edad, genero, experiencia, consentimiento, fecha_registro) VALUES
(1, 'USR_HASH_8F3A2B1C', 21, 'Masculino', 'Avanzado', TRUE, '2026-05-01 10:00:00'),
(2, 'USR_HASH_4D9E6F7A', 19, 'Femenino', 'Intermedio', TRUE, '2026-05-01 11:15:00'),
(3, 'USR_HASH_1C2B3A4D', 24, 'Masculino', 'Avanzado', TRUE, '2026-05-02 14:00:00'),
(4, 'USR_HASH_7E8F9A0B', 22, 'No Binario', 'Principiante', TRUE, '2026-05-02 16:30:00'),
(5, 'USR_HASH_5A6B7C8D', 20, 'Femenino', 'Intermedio', TRUE, '2026-05-03 09:00:00'),
(6, 'USR_HASH_3D2E1F0A', 25, 'Masculino', 'Avanzado', TRUE, '2026-05-03 18:45:00')
ON CONFLICT (id_usuario) DO NOTHING;

-- 6. POBLACIÓN DE JUGADORES COMPUESTOS
INSERT INTO jugador (id_jugador, alias, id_usuario) VALUES
(1, 'DoomSlayer_99', 1),
(2, 'Sara_Cyborg', 2),
(3, 'Juanpa_Master', 3),
(4, 'NoobMarine', 4),
(5, 'CyberDemon_Hunter', 5),
(6, 'John_Romero_Fan', 6)
ON CONFLICT (id_jugador) DO NOTHING;

-- 7. POBLACIÓN DE PARTIDAS
INSERT INTO partida (id_partida, id_mapa, fecha_inicio, fecha_fin, configuracion) VALUES
(1, 1, '2026-05-15 20:00:00', '2026-05-15 20:25:00', 'Dificultad: Hurt Me Plenty | Render: OpenGL'),
(2, 2, '2026-05-16 15:00:00', '2026-05-16 15:40:00', 'Dificultad: Ultra-Violence | Render: Vulkan'),
(3, 3, '2026-05-17 21:00:00', '2026-05-17 21:15:00', 'Dificultad: Nightmare | Render: Soft')
ON CONFLICT (id_partida) DO NOTHING;

-- 8. PARTICIPANTES EN PARTIDAS
INSERT INTO participante_partida (id_participante, id_partida, id_jugador, rol) VALUES
(1, 1, 1, 'Player_1'),
(2, 1, 2, 'Player_2'),
(3, 2, 3, 'Player_1'),
(4, 2, 4, 'Player_2'),
(5, 3, 5, 'Player_1'),
(6, 3, 6, 'Player_2')
ON CONFLICT (id_participante) DO NOTHING;

-- 9. INGESTA MASIVA EFICIENTE DE TELEMETRÍA (+21,000 REGISTROS AUTOMÁTICOS)
-- Vinculamos las partidas con sus jugadores reales usando participante_partida (Evita registros huérfanos)
-- Generamos 3,600 registros secuenciales por cada participante activo (3 partidas x 2 jugadores x 3600 tics = 21,600 filas)
INSERT INTO evento_telemetria (
    id_partida, id_jugador, id_sector, tic, 
    pos_x, pos_y, pos_z, angulo, 
    momentum_x, momentum_y, momentum_z, fov, 
    salud, armadura, municion
)
SELECT 
    pp.id_partida,
    pp.id_jugador,
    1, -- SEC_START por defecto
    s.tic,
    -- Simulación matemática de movimiento tridimensional fluido (Seno y Coseno)
    ROUND((100.0 * SIN(s.tic::numeric / 10.0))::numeric, 4) as pos_x,
    ROUND((150.0 * COS(s.tic::numeric / 12.0))::numeric, 4) as pos_y,
    ROUND((10.0 * SIN(s.tic::numeric / 50.0))::numeric, 4) as pos_z,
    ROUND((180.0 + 180.0 * SIN(s.tic::numeric / 100.0))::numeric, 4) as angulo,
    ROUND((5.0 * COS(s.tic::numeric / 5.0))::numeric, 4) as momentum_x,
    ROUND((5.0 * SIN(s.tic::numeric / 5.0))::numeric, 4) as momentum_y,
    0.0000 as momentum_z,
    90.00 as fov,
    -- Simulación dinámica de signos vitales (Salud fluctúa entre 40 y 100)
    (80 + (20 * SIN(s.tic::numeric / 20.0)))::int as salud,
    (50 + (50 * COS(s.tic::numeric / 30.0)))::int as armadura,
    (50 + (40 * SIN(s.tic::numeric / 15.0)))::int as municion
FROM 
    participante_partida pp
CROSS JOIN 
    generate_series(1, 3600) AS s(tic);

-- 10. POBLACIÓN DE RESPUESTAS UX (Viculadas al instrumento BANGS y usuarios)
INSERT INTO respuesta_ux (fecha_respuesta, id_usuario, id_item, id_instrumento, id_partida, valor_respuesta)
SELECT 
    '2026-05-18 12:00:00'::timestamp,
    u.id_usuario,
    i.id_item,
    1, -- Instrumento BANGS
    1, -- Asociado a la partida 1
    ROUND((1.0 + 4.0 * RANDOM())::numeric, 2) -- Respuestas aleatorias en escala Likert (1 a 5)
FROM 
    usuario u
CROSS JOIN 
    item_ux i;

COMMIT;

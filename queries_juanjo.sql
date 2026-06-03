-- ============================================================
-- PART C: QUERIES, VIEWS — PERSONA 2 (Juan José Rocha)
-- Chocolate-Doom Telemetry & UX Database
-- Contiene: Q4, Q5, Q7 + 2 Views + 1 Materialized View
-- Requiere: Sql_Entrega_B.sql + data.sql ejecutados primero
-- ============================================================


-- ============================================================
-- Q4: RESPUESTAS UX PARA JUGADORES CON TRAYECTORIAS
--     POR ENCIMA DEL PROMEDIO
-- ============================================================
-- Idea: calcular la duración de trayectoria de cada jugador
-- (cantidad de tics registrados por jugador por partida),
-- comparar contra el promedio global, y mostrar las respuestas
-- UX de los jugadores que superan ese promedio.
-- ============================================================

-- ANTES de índices (correr esto, tomar screenshot del plan):
EXPLAIN ANALYZE
WITH duracion_por_jugador AS (
    -- Paso 1: cuántos tics tiene cada jugador en cada partida
    SELECT
        id_jugador,
        id_partida,
        COUNT(tic) AS total_tics
    FROM evento_telemetria
    GROUP BY id_jugador, id_partida
),
promedio_global AS (
    -- Paso 2: el promedio de tics de todos los jugadores
    SELECT AVG(total_tics) AS avg_tics
    FROM duracion_por_jugador
),
jugadores_sobre_promedio AS (
    -- Paso 3: solo los jugadores que superan ese promedio
    SELECT d.id_jugador, d.id_partida, d.total_tics
    FROM duracion_por_jugador d, promedio_global p
    WHERE d.total_tics > p.avg_tics
)
-- Paso 4: unir con respuestas UX para ver sus encuestas
SELECT
    j.alias                         AS jugador,
    u.codigo_anonimo                AS usuario_anonimo,
    jsp.total_tics                  AS tics_jugados,
    ROUND(pg.avg_tics, 2)           AS promedio_global_tics,
    i.texto_pregunta                AS pregunta_ux,
    i.dimension                     AS dimension_bangs,
    rx.valor_respuesta              AS puntuacion
FROM jugadores_sobre_promedio jsp
JOIN jugador          j   ON j.id_jugador    = jsp.id_jugador
JOIN usuario          u   ON u.id_usuario    = j.id_usuario
JOIN respuesta_ux     rx  ON rx.id_usuario   = u.id_usuario
                          AND rx.id_partida  = jsp.id_partida
JOIN item_ux          i   ON i.id_item       = rx.id_item
CROSS JOIN promedio_global pg
ORDER BY jsp.total_tics DESC, i.id_item;


-- ============================================================
-- Q5: SECTOR MÁS VISITADO (HOTSPOT) POR EPISODIO Y MAPA
-- ============================================================
-- Idea: agrupar eventos de telemetría por episodio, mapa y
-- sector, contar cuántas veces aparece cada sector, ordenar
-- de mayor a menor para encontrar los hotspots.
-- El sector con más presencia de jugadores es el hotspot.
-- ============================================================

EXPLAIN ANALYZE
SELECT
    e.nombre_episodio                           AS episodio,
    m.codigo_mapa                               AS mapa,
    m.nombre_mapa                               AS nombre_mapa,
    s.codigo_sector                             AS sector,
    s.coordenada_x                              AS coord_x,
    s.coordenada_y                              AS coord_y,
    COUNT(et.id_evento)                         AS total_presencias,
    COUNT(DISTINCT et.id_jugador)               AS jugadores_distintos,
    ROUND(
        COUNT(et.id_evento)::numeric /
        NULLIF(COUNT(DISTINCT et.id_jugador), 0)
    , 2)                                        AS presencias_por_jugador
FROM evento_telemetria et
JOIN sector   s ON s.id_sector   = et.id_sector
JOIN mapa     m ON m.id_mapa     = s.id_mapa
JOIN episodio e ON e.id_episodio = m.id_episodio
GROUP BY
    e.id_episodio, e.nombre_episodio,
    m.id_mapa, m.codigo_mapa, m.nombre_mapa,
    s.id_sector, s.codigo_sector, s.coordenada_x, s.coordenada_y
ORDER BY
    e.id_episodio,
    m.id_mapa,
    total_presencias DESC;


-- ============================================================
-- Q7: SCORE UX PROMEDIO PARA JUGADORES CON LA TRAYECTORIA
--     MÁS CORTA POR EPISODIO
-- ============================================================
-- Idea: para cada episodio, encontrar el jugador con menor
-- cantidad de tics totales (trayectoria más corta), luego
-- calcular su puntaje UX promedio en el instrumento BANGS.
-- Usa window function RANK() para identificar el mínimo
-- por episodio sin perder el detalle de los datos.
-- ============================================================

EXPLAIN ANALYZE
WITH distancia_por_jugador_episodio AS (
    -- Paso 1: total de tics por jugador por episodio
    -- (proxy de duración/longitud de trayectoria)
    SELECT
        et.id_jugador,
        e.id_episodio,
        e.nombre_episodio,
        COUNT(et.tic) AS total_tics
    FROM evento_telemetria et
    JOIN partida  p ON p.id_partida  = et.id_partida
    JOIN mapa     m ON m.id_mapa     = p.id_mapa
    JOIN episodio e ON e.id_episodio = m.id_episodio
    GROUP BY et.id_jugador, e.id_episodio, e.nombre_episodio
),
rankeados AS (
    -- Paso 2: rankear por episodio, menor tics = rank 1
    SELECT
        id_jugador,
        id_episodio,
        nombre_episodio,
        total_tics,
        RANK() OVER (
            PARTITION BY id_episodio
            ORDER BY total_tics ASC
        ) AS rk
    FROM distancia_por_jugador_episodio
),
jugadores_min AS (
    -- Paso 3: solo los que tienen el mínimo (rk = 1)
    SELECT id_jugador, id_episodio, nombre_episodio, total_tics
    FROM rankeados
    WHERE rk = 1
)
-- Paso 4: calcular puntaje UX promedio de esos jugadores
SELECT
    jm.nombre_episodio                      AS episodio,
    jg.alias                                AS jugador,
    u.codigo_anonimo                        AS usuario_anonimo,
    jm.total_tics                           AS tics_trayectoria_corta,
    i.dimension                             AS dimension_bangs,
    ROUND(AVG(rx.valor_respuesta), 2)       AS score_ux_promedio,
    COUNT(rx.id_respuesta)                  AS items_respondidos
FROM jugadores_min jm
JOIN jugador      jg ON jg.id_jugador  = jm.id_jugador
JOIN usuario      u  ON u.id_usuario   = jg.id_usuario
JOIN respuesta_ux rx ON rx.id_usuario  = u.id_usuario
JOIN item_ux      i  ON i.id_item      = rx.id_item
GROUP BY
    jm.nombre_episodio,
    jg.alias,
    u.codigo_anonimo,
    jm.total_tics,
    i.dimension
ORDER BY
    jm.nombre_episodio,
    i.dimension;


-- ============================================================
-- VIEW 1: v_trayectoria_por_jugador
-- ============================================================
-- Vista para análisis frecuente de trayectorias.
-- Precalcula por jugador y partida:
--   - total de tics registrados
--   - posición promedio (centroide del movimiento)
--   - rango de posición (amplitud del área recorrida)
--   - salud y munición promedio durante la sesión
-- Evita reescribir estos cálculos en cada consulta analítica.
-- ============================================================

CREATE OR REPLACE VIEW v_trayectoria_por_jugador AS
SELECT
    et.id_partida,
    et.id_jugador,
    jg.alias,
    u.codigo_anonimo,
    e.nombre_episodio,
    m.codigo_mapa,
    COUNT(et.tic)                           AS total_tics,
    ROUND(AVG(et.pos_x)::numeric, 4)        AS pos_x_promedio,
    ROUND(AVG(et.pos_y)::numeric, 4)        AS pos_y_promedio,
    ROUND(MAX(et.pos_x) - MIN(et.pos_x), 4) AS rango_x,
    ROUND(MAX(et.pos_y) - MIN(et.pos_y), 4) AS rango_y,
    ROUND(AVG(et.salud)::numeric, 2)        AS salud_promedio,
    ROUND(AVG(et.municion)::numeric, 2)     AS municion_promedio,
    MIN(et.tic)                             AS tic_inicio,
    MAX(et.tic)                             AS tic_fin
FROM evento_telemetria et
JOIN jugador  jg ON jg.id_jugador  = et.id_jugador
JOIN usuario  u  ON u.id_usuario   = jg.id_usuario
JOIN partida  p  ON p.id_partida   = et.id_partida
JOIN mapa     m  ON m.id_mapa      = p.id_mapa
JOIN episodio e  ON e.id_episodio  = m.id_episodio
GROUP BY
    et.id_partida, et.id_jugador,
    jg.alias, u.codigo_anonimo,
    e.nombre_episodio, m.codigo_mapa;

-- Verificar la vista:
SELECT * FROM v_trayectoria_por_jugador ORDER BY total_tics DESC;


-- ============================================================
-- VIEW 2: v_copresencia_sectores
-- ============================================================
-- Vista para análisis de co-presencia en sectores.
-- Detecta pares de jugadores que estuvieron en el mismo
-- sector durante el mismo tic en la misma partida.
-- Útil para identificar cooperación o sabotaje.
-- id_jugador_a < id_jugador_b evita contar el par dos veces.
-- ============================================================

CREATE OR REPLACE VIEW v_copresencia_sectores AS
SELECT
    a.id_partida,
    a.id_sector,
    s.codigo_sector,
    e.nombre_episodio,
    m.codigo_mapa,
    a.id_jugador                            AS jugador_a,
    ja.alias                                AS alias_a,
    b.id_jugador                            AS jugador_b,
    jb.alias                                AS alias_b,
    COUNT(DISTINCT a.tic)                   AS tics_compartidos
FROM evento_telemetria a
JOIN evento_telemetria b
    ON  a.id_partida = b.id_partida
    AND a.tic        = b.tic
    AND a.id_sector  = b.id_sector
    AND a.id_jugador < b.id_jugador        -- evita duplicados y self-joins
JOIN sector   s  ON s.id_sector   = a.id_sector
JOIN partida  p  ON p.id_partida  = a.id_partida
JOIN mapa     m  ON m.id_mapa     = p.id_mapa
JOIN episodio e  ON e.id_episodio = m.id_episodio
JOIN jugador  ja ON ja.id_jugador = a.id_jugador
JOIN jugador  jb ON jb.id_jugador = b.id_jugador
GROUP BY
    a.id_partida, a.id_sector,
    s.codigo_sector, e.nombre_episodio, m.codigo_mapa,
    a.id_jugador, ja.alias,
    b.id_jugador, jb.alias
HAVING COUNT(DISTINCT a.tic) > 0
ORDER BY tics_compartidos DESC;

-- Verificar la vista:
SELECT * FROM v_copresencia_sectores;


-- ============================================================
-- MATERIALIZED VIEW: mv_hotspot_sectores
-- ============================================================
-- Es la vista más costosa computacionalmente: agrega TODOS
-- los eventos de telemetría por episodio, mapa y sector,
-- calcula métricas de presencia y las persiste en disco.
-- Al ser materializada, la consulta lee datos precalculados
-- en lugar de reescanear los 21,600 eventos cada vez.
-- Ideal para dashboards y reportes frecuentes de hotspots.
--
-- REFRESH: ejecutar REFRESH MATERIALIZED VIEW mv_hotspot_sectores
-- después de cargar nuevos datos de telemetría.
-- ============================================================

CREATE MATERIALIZED VIEW mv_hotspot_sectores AS
SELECT
    e.id_episodio,
    e.nombre_episodio,
    m.id_mapa,
    m.codigo_mapa,
    m.nombre_mapa,
    s.id_sector,
    s.codigo_sector,
    s.coordenada_x,
    s.coordenada_y,
    COUNT(et.id_evento)                     AS total_eventos,
    COUNT(DISTINCT et.id_jugador)           AS jugadores_unicos,
    COUNT(DISTINCT et.id_partida)           AS partidas_con_presencia,
    ROUND(AVG(et.salud)::numeric, 2)        AS salud_promedio_en_sector,
    ROUND(AVG(et.municion)::numeric, 2)     AS municion_promedio_en_sector,
    ROUND(
        COUNT(et.id_evento)::numeric /
        NULLIF(COUNT(DISTINCT et.id_jugador), 0)
    , 2)                                    AS eventos_por_jugador,
    -- Ranking dentro del mapa: 1 = hotspot principal
    RANK() OVER (
        PARTITION BY m.id_mapa
        ORDER BY COUNT(et.id_evento) DESC
    )                                       AS rank_en_mapa
FROM evento_telemetria et
JOIN sector   s ON s.id_sector   = et.id_sector
JOIN mapa     m ON m.id_mapa     = s.id_mapa
JOIN episodio e ON e.id_episodio = m.id_episodio
GROUP BY
    e.id_episodio, e.nombre_episodio,
    m.id_mapa, m.codigo_mapa, m.nombre_mapa,
    s.id_sector, s.codigo_sector, s.coordenada_x, s.coordenada_y
WITH DATA;

-- Índice sobre la materialized view para acelerar filtros por mapa
CREATE INDEX idx_mv_hotspot_mapa
    ON mv_hotspot_sectores (id_mapa, total_eventos DESC);

-- Verificar la materialized view:
SELECT * FROM mv_hotspot_sectores ORDER BY id_episodio, rank_en_mapa;

-- Comando para refrescar cuando lleguen nuevos datos:
-- REFRESH MATERIALIZED VIEW mv_hotspot_sectores;


-- ============================================================
-- FIN DEL ARCHIVO — queries_juanjo.sql
-- ============================================================

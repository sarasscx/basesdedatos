-- ============================================================
-- PART C: QUERIES ESPACIALES + ÍNDICES — PERSONA 1 (Juan Pablo)
-- Chocolate-Doom Telemetry & UX Database
-- Contiene: Q2, Q3, Q8 + 3 índices con EXPLAIN ANALYZE
-- Requiere: Sql_Entrega_B.sql + data.sql ejecutados primero
-- ============================================================


-- ============================================================
-- SECCIÓN 1: ÍNDICES
-- ============================================================
-- El enunciado sugiere 3 índices específicos. Se crean ANTES
-- de las queries para que el EXPLAIN ANALYZE pueda mostrar
-- el plan CON índices. El plan SIN índices se obtiene
-- corriendo las queries antes de ejecutar este bloque,
-- o usando SET enable_indexscan = OFF temporalmente.
-- ============================================================

-- Índice 1: búsqueda por partida + jugador + tic
-- Soporta Q2 (self-join por partida/tic), Q3 (tics consecutivos)
-- y Q8 (distancia acumulada). Es el índice más importante.
CREATE INDEX IF NOT EXISTS idx_tel_partida_jugador_tic
    ON evento_telemetria (id_partida, id_jugador, tic);

-- Índice 2: búsqueda por sector
-- Soporta Q5 (hotspot) y la view v_copresencia_sectores.
CREATE INDEX IF NOT EXISTS idx_tel_sector
    ON evento_telemetria (id_sector);

-- Índice 3: índice funcional sobre posición (pos_x, pos_y)
-- Soporta Q2 (distancia euclidiana), Q3 y Q8.
-- Se usa expresión POINT para aprovechar operadores geométricos
-- nativos de PostgreSQL sin necesitar PostGIS.
CREATE INDEX IF NOT EXISTS idx_tel_posicion
    ON evento_telemetria USING btree (pos_x, pos_y);

-- Índice auxiliar sobre participante_partida (jugador → partida)
CREATE INDEX IF NOT EXISTS idx_pp_jugador_partida
    ON participante_partida (id_jugador, id_partida);


-- ============================================================
-- EXPLAIN ANALYZE — ANTES y DESPUÉS de índices
-- ============================================================
-- INSTRUCCIONES PARA EL REPORTE:
--   1. Comentar los CREATE INDEX de arriba
--   2. Correr los EXPLAIN ANALYZE de abajo → tomar screenshot (ANTES)
--   3. Descomentar los CREATE INDEX y ejecutarlos
--   4. Correr los EXPLAIN ANALYZE de nuevo → tomar screenshot (DESPUÉS)
--   5. Comparar "Execution Time" en ambos screenshots
-- ============================================================

-- ── EXPLAIN para Q2 (self-join proximidad) ──────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    a.id_partida,
    a.id_jugador                                    AS jugador_a,
    b.id_jugador                                    AS jugador_b,
    a.tic,
    ROUND(
        SQRT(
            POWER(b.pos_x - a.pos_x, 2) +
            POWER(b.pos_y - a.pos_y, 2) +
            POWER(b.pos_z - a.pos_z, 2)
        )::numeric
    , 4)                                            AS distancia_euclidiana
FROM evento_telemetria a
JOIN evento_telemetria b
    ON  a.id_partida = b.id_partida
    AND a.tic        = b.tic
    AND a.id_jugador < b.id_jugador
WHERE
    SQRT(
        POWER(b.pos_x - a.pos_x, 2) +
        POWER(b.pos_y - a.pos_y, 2) +
        POWER(b.pos_z - a.pos_z, 2)
    ) <= 50.0
LIMIT 100;

-- ── EXPLAIN para Q3 (trayectorias con LAG) ──────────────────
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH distancias AS (
    SELECT
        id_jugador,
        id_partida,
        SQRT(
            POWER(pos_x - LAG(pos_x) OVER w, 2) +
            POWER(pos_y - LAG(pos_y) OVER w, 2) +
            POWER(pos_z - LAG(pos_z) OVER w, 2)
        ) AS dist_al_anterior
    FROM evento_telemetria
    WINDOW w AS (PARTITION BY id_jugador, id_partida ORDER BY tic)
)
SELECT
    id_jugador,
    id_partida,
    ROUND(SUM(dist_al_anterior)::numeric, 4) AS distancia_total
FROM distancias
WHERE dist_al_anterior IS NOT NULL
GROUP BY id_jugador, id_partida
ORDER BY distancia_total;


-- ============================================================
-- Q2: PLAYERS CON MAYOR PROXIMIDAD PROMEDIO
-- ============================================================
-- Hace un self-join sobre evento_telemetria igualando
-- id_partida y tic (mismo momento en la misma partida),
-- con id_jugador_a < id_jugador_b para no contar el par
-- dos veces ni hacer self-join de un jugador consigo mismo.
-- Calcula la distancia euclidiana 3D entre ambos jugadores
-- en cada tic, filtra por umbral (<=50 unidades = "cerca"),
-- y promedia esas distancias para rankear los pares más
-- cercanos en promedio durante toda la partida.
-- ============================================================

SELECT
    a.id_partida,
    ja.alias                                        AS jugador_a,
    jb.alias                                        AS jugador_b,
    COUNT(*)                                        AS tics_dentro_umbral,
    ROUND(
        AVG(
            SQRT(
                POWER(b.pos_x - a.pos_x, 2) +
                POWER(b.pos_y - a.pos_y, 2) +
                POWER(b.pos_z - a.pos_z, 2)
            )
        )::numeric
    , 4)                                            AS distancia_promedio,
    ROUND(
        MIN(
            SQRT(
                POWER(b.pos_x - a.pos_x, 2) +
                POWER(b.pos_y - a.pos_y, 2) +
                POWER(b.pos_z - a.pos_z, 2)
            )
        )::numeric
    , 4)                                            AS distancia_minima
FROM evento_telemetria a
JOIN evento_telemetria b
    ON  a.id_partida = b.id_partida
    AND a.tic        = b.tic
    AND a.id_jugador < b.id_jugador
JOIN jugador ja ON ja.id_jugador = a.id_jugador
JOIN jugador jb ON jb.id_jugador = b.id_jugador
WHERE
    SQRT(
        POWER(b.pos_x - a.pos_x, 2) +
        POWER(b.pos_y - a.pos_y, 2) +
        POWER(b.pos_z - a.pos_z, 2)
    ) <= 50.0
GROUP BY
    a.id_partida,
    ja.alias,
    jb.alias
ORDER BY
    distancia_promedio ASC;


-- ============================================================
-- Q3: TRAYECTORIAS MÁS CORTAS Y LARGAS POR JUGADOR
-- ============================================================
-- Usa la window function LAG() para acceder al tic anterior
-- del mismo jugador en la misma partida, calcula la distancia
-- euclidiana entre tic_actual y tic_anterior, suma todas esas
-- distancias para obtener la longitud total de la trayectoria,
-- y finalmente muestra el MIN y MAX por jugador entre todas
-- sus partidas.
--
-- LAG(pos_x) OVER (PARTITION BY id_jugador, id_partida
--                  ORDER BY tic)
-- → devuelve el pos_x del tic inmediatamente anterior.
-- El primer tic de cada jugador/partida devuelve NULL (no tiene
-- tic anterior), por eso se filtra con WHERE IS NOT NULL.
-- ============================================================

WITH distancias_entre_tics AS (
    -- Paso 1: distancia de cada tic al tic anterior
    SELECT
        id_jugador,
        id_partida,
        tic,
        SQRT(
            POWER(pos_x - LAG(pos_x) OVER w, 2) +
            POWER(pos_y - LAG(pos_y) OVER w, 2) +
            POWER(pos_z - LAG(pos_z) OVER w, 2)
        ) AS dist_al_anterior
    FROM evento_telemetria
    WINDOW w AS (
        PARTITION BY id_jugador, id_partida
        ORDER BY tic
    )
),
distancia_total_por_sesion AS (
    -- Paso 2: sumar las distancias de toda la sesión
    SELECT
        id_jugador,
        id_partida,
        ROUND(SUM(dist_al_anterior)::numeric, 4) AS distancia_total
    FROM distancias_entre_tics
    WHERE dist_al_anterior IS NOT NULL
    GROUP BY id_jugador, id_partida
)
-- Paso 3: para cada jugador, mostrar sesión más corta y más larga
SELECT
    j.alias                                         AS jugador,
    u.codigo_anonimo,
    COUNT(DISTINCT d.id_partida)                    AS total_partidas,
    ROUND(MIN(d.distancia_total)::numeric, 4)       AS trayectoria_mas_corta,
    ROUND(MAX(d.distancia_total)::numeric, 4)       AS trayectoria_mas_larga,
    ROUND(AVG(d.distancia_total)::numeric, 4)       AS trayectoria_promedio,
    -- Partida donde tuvo la trayectoria más corta
    (SELECT id_partida FROM distancia_total_por_sesion d2
     WHERE d2.id_jugador = d.id_jugador
     ORDER BY distancia_total ASC LIMIT 1)          AS partida_mas_corta,
    -- Partida donde tuvo la trayectoria más larga
    (SELECT id_partida FROM distancia_total_por_sesion d3
     WHERE d3.id_jugador = d.id_jugador
     ORDER BY distancia_total DESC LIMIT 1)         AS partida_mas_larga
FROM distancia_total_por_sesion d
JOIN jugador j ON j.id_jugador = d.id_jugador
JOIN usuario u ON u.id_usuario = j.id_usuario
GROUP BY
    j.alias,
    u.codigo_anonimo,
    d.id_jugador
ORDER BY trayectoria_promedio ASC;


-- ============================================================
-- Q8: DISTANCIA TOTAL Y VELOCIDAD PROMEDIO POR JUGADOR (CORREGIDO)
-- ============================================================
WITH distancias_entre_tics AS (
    SELECT
        id_jugador,
        id_partida,
        tic,
        SQRT(
            POWER(pos_x - LAG(pos_x) OVER w, 2) +
            POWER(pos_y - LAG(pos_y) OVER w, 2) +
            POWER(pos_z - LAG(pos_z) OVER w, 2)
        ) AS dist_al_anterior
    FROM evento_telemetria
    WINDOW w AS (
        PARTITION BY id_jugador, id_partida
        ORDER BY tic
    )
),
resumen_por_jugador AS (
    SELECT
        et.id_jugador,
        ROUND(
            SUM(dt.dist_al_anterior)::numeric
        , 4)                                        AS distancia_total,
        COUNT(DISTINCT et.id_partida)               AS total_partidas,
        COUNT(et.tic)                               AS total_tics_registrados
    FROM evento_telemetria et
    LEFT JOIN distancias_entre_tics dt
        ON  dt.id_jugador = et.id_jugador
        AND dt.id_partida = et.id_partida
        AND dt.tic        = et.tic
        AND dt.dist_al_anterior IS NOT NULL
    GROUP BY et.id_jugador, et.id_partida
)
SELECT
    j.alias                                         AS jugador,
    u.codigo_anonimo,
    SUM(r.distancia_total)                          AS distancia_total_acumulada,
    SUM(r.total_tics_registrados)                   AS total_tics,
    COUNT(DISTINCT r.id_partida)                    AS partidas_jugadas,
    ROUND(
        SUM(r.distancia_total) /
        NULLIF(SUM(r.total_tics_registrados), 0)
    , 6)                                            AS velocidad_promedio_por_tic,
    ROUND(
        (SUM(r.distancia_total) /
        NULLIF(SUM(r.total_tics_registrados), 0)) * 35
    , 4)                                            AS velocidad_promedio_por_segundo
FROM resumen_por_jugador r
JOIN jugador j ON j.id_jugador = r.id_jugador
JOIN usuario u ON u.id_usuario = j.id_usuario
GROUP BY
    j.alias,
    u.codigo_anonimo,
    r.id_jugador
ORDER BY distancia_total_acumulada DESC;


-- ============================================================
-- DISCUSIÓN DE ÍNDICES — PARA INCLUIR EN EL REPORTE PDF
-- ============================================================
-- Correr estas queries para ver el estado de los índices:

-- Ver todos los índices creados en evento_telemetria:
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'evento_telemetria'
ORDER BY indexname;

-- Tamaño de cada índice en disco:
SELECT
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS tamanio
FROM pg_indexes
WHERE tablename = 'evento_telemetria'
ORDER BY pg_relation_size(indexname::regclass) DESC;

-- ============================================================
-- FIN DEL ARCHIVO — queries_juanpis.sql
-- ============================================================

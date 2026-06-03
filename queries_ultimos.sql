
-- ============================================================
-- Q1: DURACIÓN PROMEDIO DE SESIONES DE JUEGO POR MAPA
-- ============================================================
-- Calcula cuánto duró cada partida (en minutos) a partir de
-- fecha_inicio y fecha_fin de la tabla partida, luego promedia
-- por mapa. Se incluye también el conteo de partidas y los
-- valores mínimo y máximo para dar contexto al promedio.
--
-- Nota sobre los datos: las 3 partidas de data.sql tienen
-- duraciones distintas (25 min, 40 min, 15 min), por lo que
-- cada mapa tiene exactamente una partida. Con más datos,
-- AVG mostraría diferencias reales entre mapas.
-- ============================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    e.nombre_episodio                               AS episodio,
    m.codigo_mapa                                   AS mapa,
    m.nombre_mapa                                   AS nombre_mapa,
    COUNT(p.id_partida)                             AS total_partidas,
    ROUND(
        AVG(
            EXTRACT(EPOCH FROM (p.fecha_fin - p.fecha_inicio)) / 60.0
        )::numeric
    , 2)                                            AS duracion_promedio_min,
    ROUND(
        MIN(
            EXTRACT(EPOCH FROM (p.fecha_fin - p.fecha_inicio)) / 60.0
        )::numeric
    , 2)                                            AS duracion_minima_min,
    ROUND(
        MAX(
            EXTRACT(EPOCH FROM (p.fecha_fin - p.fecha_inicio)) / 60.0
        )::numeric
    , 2)                                            AS duracion_maxima_min
FROM partida p
JOIN mapa     m ON m.id_mapa     = p.id_mapa
JOIN episodio e ON e.id_episodio = m.id_episodio
WHERE p.fecha_fin IS NOT NULL          -- excluye partidas sin terminar
GROUP BY
    e.id_episodio,
    e.nombre_episodio,
    m.id_mapa,
    m.codigo_mapa,
    m.nombre_mapa
ORDER BY
    e.id_episodio,
    duracion_promedio_min DESC;

-- Resultado esperado con data.sql:
-- episodio                 | mapa | nombre_mapa | total | avg_min | min_min | max_min
-- Knee-Deep in the Dead    | E1M1 | Hangar      |   1   |  25.00  |  25.00  |  25.00
-- The Shores of Hell       | E2M1 | Deimos Lab  |   1   |  40.00  |  40.00  |  40.00
-- Inferno                  | E3M1 | Hell Keep   |   1   |  15.00  |  15.00  |  15.00


-- ============================================================
-- Q6: NÚMERO DE TICS DONDE JUGADORES ESTUVIERON JUNTOS
--     EN EL MISMO SECTOR
-- ============================================================
-- Hace un self-join sobre evento_telemetria igualando
-- id_partida + tic + id_sector, con id_jugador_a < id_jugador_b
-- para no contar el par dos veces.
-- COUNT(DISTINCT a.tic) calcula cuántos momentos distintos
-- compartieron ese sector en esa partida.
--
-- Esta query es más ligera que Q2 (no calcula distancia),
-- sirve como señal de cooperación/co-presencia sin requerir
-- la posición exacta (x,y,z), solo el sector compartido.
--
-- Nota sobre los datos: data.sql asigna id_sector = 1 (SEC_START)
-- a todos los eventos, por lo que todos los pares compartirán
-- el mismo sector. Con datos reales de telemetría, los pares
-- variarán por sector y mapa.
-- ============================================================

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    a.id_partida,
    e.nombre_episodio                               AS episodio,
    m.codigo_mapa                                   AS mapa,
    s.codigo_sector                                 AS sector,
    ja.alias                                        AS jugador_a,
    jb.alias                                        AS jugador_b,
    COUNT(DISTINCT a.tic)                           AS tics_compartidos,
    -- Porcentaje del total de tics de la partida en que coincidieron
    ROUND(
        COUNT(DISTINCT a.tic)::numeric /
        NULLIF(
            (SELECT COUNT(DISTINCT tic)
             FROM evento_telemetria
             WHERE id_partida = a.id_partida), 0
        ) * 100.0
    , 2)                                            AS pct_partida_juntos
FROM evento_telemetria a
JOIN evento_telemetria b
    ON  a.id_partida = b.id_partida
    AND a.tic        = b.tic
    AND a.id_sector  = b.id_sector
    AND a.id_jugador < b.id_jugador         -- evita duplicados y self-join
JOIN sector   s  ON s.id_sector   = a.id_sector
JOIN partida  p  ON p.id_partida  = a.id_partida
JOIN mapa     m  ON m.id_mapa     = p.id_mapa
JOIN episodio e  ON e.id_episodio = m.id_episodio
JOIN jugador  ja ON ja.id_jugador = a.id_jugador
JOIN jugador  jb ON jb.id_jugador = b.id_jugador
GROUP BY
    a.id_partida,
    e.nombre_episodio,
    m.codigo_mapa,
    s.codigo_sector,
    ja.alias,
    jb.alias
ORDER BY
    a.id_partida,
    tics_compartidos DESC;


-- ============================================================
-- SCRIPT DE RECREACIÓN — instrucciones para el reporte
-- ============================================================
-- El Makefile al pie de este archivo automatiza la recreación
-- completa del schema y la carga de datos en un solo comando:
--
--   make recreate   →  borra y recrea el schema completo
--   make load       →  carga datos (data.sql) y ETL (etl3.sql)
--   make all        →  recreate + load en secuencia
--   make verify     →  muestra conteos por tabla
--
-- Requisito: variable de entorno DB_URL configurada, o editar
-- el valor por defecto en el Makefile.
-- ============================================================

-- Vista rápida del estado de la base después de cargar:
SELECT
    'evento_telemetria'     AS tabla,  COUNT(*) AS filas FROM evento_telemetria
UNION ALL SELECT 'jugador',            COUNT(*) FROM jugador
UNION ALL SELECT 'usuario',            COUNT(*) FROM usuario
UNION ALL SELECT 'partida',            COUNT(*) FROM partida
UNION ALL SELECT 'sector',             COUNT(*) FROM sector
UNION ALL SELECT 'respuesta_ux',       COUNT(*) FROM respuesta_ux
UNION ALL SELECT 'log_errores_carga',  COUNT(*) FROM log_errores_carga
ORDER BY tabla;


-- ============================================================
-- FIN DEL ARCHIVO — queries_persona3.sql
-- ============================================================


/*
==============================================================
MAKEFILE — guardar como  Makefile  en la raíz del proyecto
==============================================================

DB_URL ?= postgresql://postgres:postgres@localhost:5432/chocolate_doom

.PHONY: all recreate load verify clean

## Recrea schema + carga datos + ETL en un solo paso
all: recreate load verify

## Borra y recrea el schema completo
recreate:
	@echo "→ Recreando schema..."
	psql "$(DB_URL)" -f Sql_Entrega_B.sql
	@echo "✓ Schema creado."

## Carga datos sintéticos y pipeline ETL
load:
	@echo "→ Cargando datos (data.sql)..."
	psql "$(DB_URL)" -f data.sql
	@echo "→ Ejecutando ETL (etl3.sql)..."
	psql "$(DB_URL)" -f etl3.sql
	@echo "✓ Carga completa."

## Verifica conteos básicos por tabla
verify:
	@echo "→ Conteos por tabla:"
	psql "$(DB_URL)" -c "\
	SELECT 'evento_telemetria' AS tabla, COUNT(*) AS filas FROM evento_telemetria \
	UNION ALL SELECT 'jugador',          COUNT(*) FROM jugador \
	UNION ALL SELECT 'usuario',          COUNT(*) FROM usuario \
	UNION ALL SELECT 'partida',          COUNT(*) FROM partida \
	UNION ALL SELECT 'respuesta_ux',     COUNT(*) FROM respuesta_ux \
	UNION ALL SELECT 'log_errores_carga',COUNT(*) FROM log_errores_carga \
	ORDER BY tabla;"

## Elimina todos los objetos (útil para empezar limpio)
clean:
	@echo "→ Eliminando schema chocolate_doom..."
	psql "$(DB_URL)" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	@echo "✓ Schema eliminado."

==============================================================
*/

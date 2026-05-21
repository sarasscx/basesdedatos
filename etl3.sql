-- ============================================================
-- CHOCOLATE-DOOM TELEMETRY DB  |  Part B
-- etl.sql  –  Staging + ETL pipeline + log de errores
-- ============================================================
-- Orden de ejecución:
--   1. Ejecutar schema.sql primero (crea las tablas core)
--   2. Ejecutar este script (crea staging y log)
--   3. Cargar TSV al staging con \copy (Sección 3)
--   4. Ejecutar el bloque BEGIN/COMMIT (Sección 4)
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- SECCIÓN 1: Tabla de staging
-- Todos los campos en TEXT para recibir el TSV crudo sin
-- validación de tipos. Ningún dato se pierde antes de
-- ser inspeccionado (RF11, RNF06).
-- ────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS stg_evento_telemetria;

CREATE TABLE stg_evento_telemetria (
    raw_id_partida      TEXT,
    raw_id_jugador      TEXT,
    raw_tic             TEXT,
    raw_pos_x           TEXT,
    raw_pos_y           TEXT,
    raw_pos_z           TEXT,
    raw_angulo          TEXT,
    raw_momentum_x      TEXT,
    raw_momentum_y      TEXT,
    raw_momentum_z      TEXT,
    raw_fov             TEXT,
    raw_salud           TEXT,
    raw_armadura        TEXT,
    raw_municion        TEXT,
    raw_id_sector       TEXT,
    archivo_origen      TEXT        NOT NULL DEFAULT 'sin_origen',
    cargado_en          TIMESTAMP   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE stg_evento_telemetria IS
'Staging de telemetría cruda emitida por el motor de Chocolate-Doom.
 Todos los campos son TEXT para garantizar que ningún registro
 se pierda antes de la validación.';


-- ────────────────────────────────────────────────────────────
-- SECCIÓN 2: Tabla de log de errores (RF11, RNF06)
-- ────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS log_errores_carga;

CREATE TABLE log_errores_carga (
    id_log          SERIAL       PRIMARY KEY,
    origen          VARCHAR(100) NOT NULL,
    linea_raw       TEXT         NOT NULL,
    motivo          VARCHAR(200) NOT NULL,
    registrado_en   TIMESTAMP    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE log_errores_carga IS
'Trazabilidad de registros rechazados durante el ETL.
 Permite auditoría posterior y recarga de lotes corregidos
 sin riesgo de duplicados (RNF06, RNF07).';


-- ────────────────────────────────────────────────────────────
-- SECCIÓN 3: Carga del TSV al staging
-- El motor emite 15 columnas separadas por TAB.
-- ────────────────────────────────────────────────────────────

-- TRUNCATE stg_evento_telemetria;  -- descomentar para recarga

-- Opción A – psql interactivo (no requiere superusuario):
-- \copy stg_evento_telemetria (
--     raw_id_partida, raw_id_jugador, raw_tic,
--     raw_pos_x, raw_pos_y, raw_pos_z,
--     raw_angulo,
--     raw_momentum_x, raw_momentum_y, raw_momentum_z,
--     raw_fov,
--     raw_salud, raw_armadura, raw_municion,
--     raw_id_sector
-- )
-- FROM '/ruta/absoluta/al/archivo.tsv'
-- WITH (FORMAT text, DELIMITER E'\t', HEADER true);

-- Opción B – servidor PostgreSQL (requiere superusuario):
-- COPY stg_evento_telemetria (
--     raw_id_partida, raw_id_jugador, raw_tic,
--     raw_pos_x, raw_pos_y, raw_pos_z,
--     raw_angulo,
--     raw_momentum_x, raw_momentum_y, raw_momentum_z,
--     raw_fov,
--     raw_salud, raw_armadura, raw_municion,
--     raw_id_sector
-- )
-- FROM '/ruta/absoluta/al/archivo.tsv'
-- WITH (FORMAT text, DELIMITER E'\t', HEADER true);


-- ────────────────────────────────────────────────────────────
-- SECCIÓN 4: ETL – Transformación staging → core
-- Todos los pasos corren dentro de una transacción atómica.
-- ────────────────────────────────────────────────────────────

BEGIN;

-- ── Macro de validación de tipos y rangos ───────────────────
-- La siguiente condición se repite en cada paso para garantizar
-- que un registro rechazado en un paso previo no avance.
-- Condiciones:
--   (a) Campos obligatorios no nulos: id_partida, id_jugador, tic
--   (b) Tipos numéricos obligatorios válidos
--   (c) Campos opcionales (angulo, fov, id_sector) válidos si presentes
--   (d) Rangos: tic >= 0, salud >= 0, armadura >= 0, municion >= 0


-- ── PASO 1: Campos obligatorios nulos o vacíos ──────────────

INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT
    archivo_origen,
    concat_ws(E'\t', raw_id_partida, raw_id_jugador, raw_tic,
        raw_pos_x, raw_pos_y, raw_pos_z, raw_angulo,
        raw_momentum_x, raw_momentum_y, raw_momentum_z,
        raw_fov, raw_salud, raw_armadura, raw_municion, raw_id_sector),
    'Campo obligatorio nulo o vacío: id_partida / id_jugador / tic'
FROM stg_evento_telemetria
WHERE
    raw_id_partida  IS NULL OR TRIM(raw_id_partida)  = ''
    OR raw_id_jugador IS NULL OR TRIM(raw_id_jugador) = ''
    OR raw_tic        IS NULL OR TRIM(raw_tic)        = '';


-- ── PASO 2: Tipos de datos inválidos ────────────────────────
-- raw_tic usa '^-?\d+$' para que negativos lleguen al paso 3
-- clasificados como error de rango (no de tipo).
-- raw_fov, raw_angulo y raw_id_sector son opcionales:
-- solo se validan si vienen con valor.

INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT
    archivo_origen,
    concat_ws(E'\t', raw_id_partida, raw_id_jugador, raw_tic,
        raw_pos_x, raw_pos_y, raw_pos_z, raw_angulo,
        raw_momentum_x, raw_momentum_y, raw_momentum_z,
        raw_fov, raw_salud, raw_armadura, raw_municion, raw_id_sector),
    'Tipo de dato inválido en uno o más campos numéricos'
FROM stg_evento_telemetria
WHERE
    NOT (raw_id_partida IS NULL OR TRIM(raw_id_partida) = ''
         OR raw_id_jugador IS NULL OR TRIM(raw_id_jugador) = ''
         OR raw_tic IS NULL OR TRIM(raw_tic) = '')
    AND (
        raw_id_partida   !~ '^\d+$'
        OR raw_id_jugador  !~ '^\d+$'
        OR raw_tic         !~ '^-?\d+$'
        OR raw_salud       !~ '^-?\d+$'
        OR raw_armadura    !~ '^-?\d+$'
        OR raw_municion    !~ '^-?\d+$'
        OR raw_pos_x       !~ '^-?\d+(\.\d+)?$'
        OR raw_pos_y       !~ '^-?\d+(\.\d+)?$'
        OR raw_pos_z       !~ '^-?\d+(\.\d+)?$'
        OR raw_momentum_x  !~ '^-?\d+(\.\d+)?$'
        OR raw_momentum_y  !~ '^-?\d+(\.\d+)?$'
        OR raw_momentum_z  !~ '^-?\d+(\.\d+)?$'
        OR (raw_fov IS NOT NULL AND TRIM(raw_fov) <> ''
            AND raw_fov !~ '^-?\d+(\.\d+)?$')
        OR (raw_angulo IS NOT NULL AND TRIM(raw_angulo) <> ''
            AND raw_angulo !~ '^-?\d+(\.\d+)?$')
        OR (raw_id_sector IS NOT NULL AND TRIM(raw_id_sector) <> ''
            AND raw_id_sector !~ '^\d+$')
    );


-- ── PASO 3: Valores fuera de rango ──────────────────────────
-- tic < 0 se clasifica aquí (rango), no en el paso 2 (tipo).

INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT
    archivo_origen,
    concat_ws(E'\t', raw_id_partida, raw_id_jugador, raw_tic,
        raw_pos_x, raw_pos_y, raw_pos_z, raw_angulo,
        raw_momentum_x, raw_momentum_y, raw_momentum_z,
        raw_fov, raw_salud, raw_armadura, raw_municion, raw_id_sector),
    'Valor fuera de rango: tic < 0, salud < 0, armadura < 0 o municion < 0'
FROM stg_evento_telemetria
WHERE
    raw_id_partida  ~ '^\d+$' AND raw_id_jugador ~ '^\d+$'
    AND raw_tic        ~ '^-?\d+$'
    AND raw_salud      ~ '^-?\d+$' AND raw_armadura ~ '^-?\d+$'
    AND raw_municion   ~ '^-?\d+$'
    AND raw_pos_x      ~ '^-?\d+(\.\d+)?$' AND raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND raw_pos_z      ~ '^-?\d+(\.\d+)?$'
    AND raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (raw_fov IS NULL OR TRIM(raw_fov)='' OR raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (raw_angulo IS NULL OR TRIM(raw_angulo)='' OR raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (raw_id_sector IS NULL OR TRIM(raw_id_sector)='' OR raw_id_sector ~ '^\d+$')
    AND (
        raw_tic::INT < 0 OR raw_salud::INT < 0
        OR raw_armadura::INT < 0 OR raw_municion::INT < 0
    );


-- ── PASO 4: FK inválidas ────────────────────────────────────
-- Registros con tipos y rangos válidos pero que referencian
-- entidades inexistentes. Sin este paso se perderían silenciosamente.

-- 4a: Jugador inexistente
INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT s.archivo_origen,
    concat_ws(E'\t', s.raw_id_partida, s.raw_id_jugador, s.raw_tic,
        s.raw_pos_x, s.raw_pos_y, s.raw_pos_z, s.raw_angulo,
        s.raw_momentum_x, s.raw_momentum_y, s.raw_momentum_z,
        s.raw_fov, s.raw_salud, s.raw_armadura, s.raw_municion, s.raw_id_sector),
    'FK inválida: id_jugador no existe en la tabla jugador'
FROM stg_evento_telemetria s
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND NOT EXISTS (SELECT 1 FROM jugador j WHERE j.id_jugador = s.raw_id_jugador::INT);

-- 4b: Partida inexistente
INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT s.archivo_origen,
    concat_ws(E'\t', s.raw_id_partida, s.raw_id_jugador, s.raw_tic,
        s.raw_pos_x, s.raw_pos_y, s.raw_pos_z, s.raw_angulo,
        s.raw_momentum_x, s.raw_momentum_y, s.raw_momentum_z,
        s.raw_fov, s.raw_salud, s.raw_armadura, s.raw_municion, s.raw_id_sector),
    'FK inválida: id_partida no existe en la tabla partida'
FROM stg_evento_telemetria s
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND EXISTS (SELECT 1 FROM jugador j WHERE j.id_jugador = s.raw_id_jugador::INT)
    AND NOT EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT);

-- 4c: Sector inexistente o que no pertenece al mapa de la partida
INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT s.archivo_origen,
    concat_ws(E'\t', s.raw_id_partida, s.raw_id_jugador, s.raw_tic,
        s.raw_pos_x, s.raw_pos_y, s.raw_pos_z, s.raw_angulo,
        s.raw_momentum_x, s.raw_momentum_y, s.raw_momentum_z,
        s.raw_fov, s.raw_salud, s.raw_armadura, s.raw_municion, s.raw_id_sector),
    'FK inválida: id_sector no existe o no pertenece al mapa de la partida'
FROM stg_evento_telemetria s
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND s.raw_id_sector ~ '^\d+$'   -- solo si viene informado
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND EXISTS (SELECT 1 FROM jugador j WHERE j.id_jugador = s.raw_id_jugador::INT)
    AND EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT)
    -- Validar que el sector pertenezca al mapa de la partida
    AND NOT EXISTS (
        SELECT 1
        FROM partida p
        JOIN mapa m   ON m.id_mapa   = p.id_mapa
        JOIN sector sec ON sec.id_mapa = m.id_mapa
        WHERE p.id_partida  = s.raw_id_partida::INT
          AND sec.id_sector = s.raw_id_sector::INT
    );


-- ── PASO 5: Usuarios sin consentimiento ─────────────────────

INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT s.archivo_origen,
    concat_ws(E'\t', s.raw_id_partida, s.raw_id_jugador, s.raw_tic,
        s.raw_pos_x, s.raw_pos_y, s.raw_pos_z, s.raw_angulo,
        s.raw_momentum_x, s.raw_momentum_y, s.raw_momentum_z,
        s.raw_fov, s.raw_salud, s.raw_armadura, s.raw_municion, s.raw_id_sector),
    'Usuario sin consentimiento informado'
FROM stg_evento_telemetria s
JOIN jugador j ON j.id_jugador = s.raw_id_jugador::INT
JOIN usuario u ON u.id_usuario = j.id_usuario
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT)
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)=''
         OR EXISTS (
             SELECT 1 FROM partida p
             JOIN mapa m ON m.id_mapa = p.id_mapa
             JOIN sector sec ON sec.id_mapa = m.id_mapa
             WHERE p.id_partida = s.raw_id_partida::INT
               AND sec.id_sector = s.raw_id_sector::INT))
    AND u.consentimiento = FALSE;


-- ── PASO 6: Duplicados internos del staging ─────────────────
-- Detecta filas repetidas dentro del mismo lote TSV.
-- Se conserva la primera por cargado_en; las demás van al log.
-- Sin este paso se perderían silenciosamente con DISTINCT ON.

WITH candidatos AS (
    SELECT
        s.*,
        ROW_NUMBER() OVER (
            PARTITION BY s.raw_id_partida::INT,
                         s.raw_id_jugador::INT,
                         s.raw_tic::INT
            ORDER BY s.cargado_en ASC
        ) AS rn
    FROM stg_evento_telemetria s
    JOIN jugador j ON j.id_jugador = s.raw_id_jugador::INT
    JOIN usuario u ON u.id_usuario = j.id_usuario
    WHERE
        s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
        AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
        AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
        AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
        AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
        AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
        AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
        AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
        AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
        AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
        AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
        AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
        AND u.consentimiento = TRUE
        AND EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT)
        AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)=''
             OR EXISTS (
                 SELECT 1 FROM partida p
                 JOIN mapa m ON m.id_mapa = p.id_mapa
                 JOIN sector sec ON sec.id_mapa = m.id_mapa
                 WHERE p.id_partida = s.raw_id_partida::INT
                   AND sec.id_sector = s.raw_id_sector::INT))
)
INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT
    archivo_origen,
    concat_ws(E'\t', raw_id_partida, raw_id_jugador, raw_tic,
        raw_pos_x, raw_pos_y, raw_pos_z, raw_angulo,
        raw_momentum_x, raw_momentum_y, raw_momentum_z,
        raw_fov, raw_salud, raw_armadura, raw_municion, raw_id_sector),
    'Duplicado dentro del staging: se conserva el primer registro del lote'
FROM candidatos
WHERE rn > 1;


-- ── PASO 7: Duplicados contra el core ───────────────────────
-- Registra filas válidas que ya existen en evento_telemetria.
-- Debe ejecutarse ANTES del INSERT para evitar falsos positivos.

INSERT INTO log_errores_carga (origen, linea_raw, motivo)
SELECT s.archivo_origen,
    concat_ws(E'\t', s.raw_id_partida, s.raw_id_jugador, s.raw_tic,
        s.raw_pos_x, s.raw_pos_y, s.raw_pos_z, s.raw_angulo,
        s.raw_momentum_x, s.raw_momentum_y, s.raw_momentum_z,
        s.raw_fov, s.raw_salud, s.raw_armadura, s.raw_municion, s.raw_id_sector),
    'Duplicado contra core: (id_partida, id_jugador, tic) ya existe en evento_telemetria'
FROM stg_evento_telemetria s
JOIN jugador j ON j.id_jugador = s.raw_id_jugador::INT
JOIN usuario u ON u.id_usuario = j.id_usuario
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND u.consentimiento = TRUE
    AND EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT)
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)=''
         OR EXISTS (
             SELECT 1 FROM partida p
             JOIN mapa m ON m.id_mapa = p.id_mapa
             JOIN sector sec ON sec.id_mapa = m.id_mapa
             WHERE p.id_partida = s.raw_id_partida::INT
               AND sec.id_sector = s.raw_id_sector::INT))
    AND EXISTS (
        SELECT 1 FROM evento_telemetria e
        WHERE e.id_partida  = s.raw_id_partida::INT
          AND e.id_jugador  = s.raw_id_jugador::INT
          AND e.tic         = s.raw_tic::INT
    );


-- ── PASO 8: Insertar registros válidos en evento_telemetria ──
-- Se ejecuta DESPUÉS de los logs de duplicados (pasos 6 y 7).
-- Requiere: UNIQUE (id_partida, id_jugador, tic) en evento_telemetria.
-- ON CONFLICT DO NOTHING actúa como segunda barrera de seguridad.

INSERT INTO evento_telemetria (
    id_partida, id_jugador, id_sector, tic,
    pos_x, pos_y, pos_z, angulo,
    momentum_x, momentum_y, momentum_z,
    fov, salud, armadura, municion
)
SELECT DISTINCT ON (s.raw_id_partida::INT, s.raw_id_jugador::INT, s.raw_tic::INT)
    s.raw_id_partida::INT,
    s.raw_id_jugador::INT,
    NULLIF(TRIM(s.raw_id_sector), '')::INT,
    s.raw_tic::INT,
    s.raw_pos_x::NUMERIC(12,4),
    s.raw_pos_y::NUMERIC(12,4),
    s.raw_pos_z::NUMERIC(12,4),
    NULLIF(TRIM(s.raw_angulo), '')::NUMERIC(8,4),
    s.raw_momentum_x::NUMERIC(10,4),
    s.raw_momentum_y::NUMERIC(10,4),
    s.raw_momentum_z::NUMERIC(10,4),
    NULLIF(TRIM(s.raw_fov), '')::NUMERIC(6,2),
    s.raw_salud::INT,
    s.raw_armadura::INT,
    s.raw_municion::INT
FROM stg_evento_telemetria s
JOIN jugador j ON j.id_jugador = s.raw_id_jugador::INT
JOIN usuario u ON u.id_usuario = j.id_usuario
WHERE
    s.raw_id_partida ~ '^\d+$' AND s.raw_id_jugador ~ '^\d+$'
    AND s.raw_tic ~ '^-?\d+$' AND s.raw_salud ~ '^-?\d+$'
    AND s.raw_armadura ~ '^-?\d+$' AND s.raw_municion ~ '^-?\d+$'
    AND s.raw_pos_x ~ '^-?\d+(\.\d+)?$' AND s.raw_pos_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_pos_z ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_x ~ '^-?\d+(\.\d+)?$' AND s.raw_momentum_y ~ '^-?\d+(\.\d+)?$'
    AND s.raw_momentum_z ~ '^-?\d+(\.\d+)?$'
    AND (s.raw_fov IS NULL OR TRIM(s.raw_fov)='' OR s.raw_fov ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_angulo IS NULL OR TRIM(s.raw_angulo)='' OR s.raw_angulo ~ '^-?\d+(\.\d+)?$')
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)='' OR s.raw_id_sector ~ '^\d+$')
    AND s.raw_tic::INT >= 0 AND s.raw_salud::INT >= 0
    AND s.raw_armadura::INT >= 0 AND s.raw_municion::INT >= 0
    AND u.consentimiento = TRUE
    AND EXISTS (SELECT 1 FROM partida p WHERE p.id_partida = s.raw_id_partida::INT)
    AND (s.raw_id_sector IS NULL OR TRIM(s.raw_id_sector)=''
         OR EXISTS (
             SELECT 1 FROM partida p
             JOIN mapa m ON m.id_mapa = p.id_mapa
             JOIN sector sec ON sec.id_mapa = m.id_mapa
             WHERE p.id_partida = s.raw_id_partida::INT
               AND sec.id_sector = s.raw_id_sector::INT))
ORDER BY
    s.raw_id_partida::INT,
    s.raw_id_jugador::INT,
    s.raw_tic::INT,
    s.cargado_en ASC
ON CONFLICT (id_partida, id_jugador, tic) DO NOTHING;

COMMIT;


-- ────────────────────────────────────────────────────────────
-- SECCIÓN 5: Reporte de resumen post-carga
-- Nota: total_core es acumulado (toda la tabla), no solo
-- el lote actual. Para contar solo lo insertado en este lote,
-- comparar con el valor antes de ejecutar el pipeline.
-- ────────────────────────────────────────────────────────────

SELECT COUNT(*) AS total_staging    FROM stg_evento_telemetria;
SELECT COUNT(*) AS total_core_acumulado FROM evento_telemetria;

SELECT motivo, COUNT(*) AS cantidad
FROM log_errores_carga
GROUP BY motivo
ORDER BY cantidad DESC;

SELECT id_log, origen, motivo, registrado_en
FROM log_errores_carga
ORDER BY registrado_en DESC
LIMIT 10;

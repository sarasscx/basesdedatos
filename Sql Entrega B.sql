DROP TABLE IF EXISTS respuesta_ux          CASCADE;
DROP TABLE IF EXISTS item_ux               CASCADE;
DROP TABLE IF EXISTS instrumento_ux        CASCADE;
DROP TABLE IF EXISTS evento_telemetria     CASCADE;
DROP TABLE IF EXISTS participante_partida  CASCADE;
DROP TABLE IF EXISTS partida               CASCADE;
DROP TABLE IF EXISTS jugador               CASCADE;
DROP TABLE IF EXISTS usuario               CASCADE;
DROP TABLE IF EXISTS sector                CASCADE;
DROP TABLE IF EXISTS mapa                  CASCADE;
DROP TABLE IF EXISTS episodio              CASCADE;

-- 1. Episodio
CREATE TABLE episodio (
    id_episodio     SERIAL      NOT NULL,
    nombre_episodio VARCHAR(80) NOT NULL UNIQUE,
    PRIMARY KEY (id_episodio)
);

-- 2. Mapa
CREATE TABLE mapa (
    id_mapa     SERIAL      NOT NULL,
    id_episodio INT         NOT NULL,
    codigo_mapa VARCHAR(10) NOT NULL,
    nombre_mapa VARCHAR(80),
    PRIMARY KEY (id_mapa),
    UNIQUE (id_episodio, codigo_mapa),
    CONSTRAINT fk_mapa_episodio
        FOREIGN KEY (id_episodio) REFERENCES episodio (id_episodio)
);

-- 3. Sector
CREATE TABLE sector (
    id_sector     SERIAL       NOT NULL,
    id_mapa       INT          NOT NULL,
    codigo_sector VARCHAR(20)  NOT NULL,
    coordenada_x  NUMERIC(10,2),
    coordenada_y  NUMERIC(10,2),
    PRIMARY KEY (id_sector),
    UNIQUE (id_mapa, codigo_sector),
    CONSTRAINT fk_sector_mapa
        FOREIGN KEY (id_mapa) REFERENCES mapa (id_mapa)
);

-- ============================================================
-- ZONA 2: VOLUNTARIOS
-- ============================================================

-- 4. Usuario
CREATE TABLE usuario (
    id_usuario     SERIAL      NOT NULL,
    codigo_anonimo VARCHAR(32) NOT NULL UNIQUE,
    edad           INT         CHECK (edad BETWEEN 10 AND 99),
    genero         VARCHAR(20),
    experiencia    VARCHAR(20),
    consentimiento BOOLEAN     NOT NULL DEFAULT FALSE,
    fecha_registro TIMESTAMP   NOT NULL,
    PRIMARY KEY (id_usuario)
);

-- 5. Jugador

CREATE TABLE jugador (
    id_jugador SERIAL      NOT NULL,
    alias      VARCHAR(50) NOT NULL,
    id_usuario INT         NOT NULL,
    PRIMARY KEY (id_jugador),
    UNIQUE (id_usuario, alias),
    CONSTRAINT fk_jugador_usuario
        FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
);

-- 6. Partida
CREATE TABLE partida (
    id_partida    SERIAL    NOT NULL,
    id_mapa       INT       NOT NULL,
    fecha_inicio  TIMESTAMP NOT NULL,
    fecha_fin     TIMESTAMP,          -- NULL si la partida está en curso
    configuracion TEXT,
    PRIMARY KEY (id_partida),
    CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
    CONSTRAINT fk_partida_mapa
        FOREIGN KEY (id_mapa) REFERENCES mapa (id_mapa)
);

-- 7. Participante_partida

CREATE TABLE participante_partida (
    id_participante SERIAL      NOT NULL,
    id_partida      INT         NOT NULL,
    id_jugador      INT         NOT NULL,
    rol             VARCHAR(30),
    PRIMARY KEY (id_participante),
    UNIQUE (id_partida, id_jugador),  -- un jugador no puede estar dos veces en la misma partida
    CONSTRAINT fk_pp_partida
        FOREIGN KEY (id_partida) REFERENCES partida (id_partida),
    CONSTRAINT fk_pp_jugador
        FOREIGN KEY (id_jugador) REFERENCES jugador (id_jugador)
);

-- 8. Evento_telemetria

CREATE TABLE evento_telemetria (
    id_evento  BIGSERIAL     NOT NULL,
    id_partida INT           NOT NULL,
    id_jugador INT           NOT NULL,
    id_sector  INT,                   -- nullable: puede no registrarse el sector
    tic        INT           NOT NULL CHECK (tic >= 0),
    pos_x      NUMERIC(12,4),
    pos_y      NUMERIC(12,4),
    pos_z      NUMERIC(12,4),
    angulo     NUMERIC(8,4),
    momentum_x NUMERIC(10,4),         -- puede ser negativo (movimiento inverso)
    momentum_y NUMERIC(10,4),
    momentum_z NUMERIC(10,4),
    fov        NUMERIC(6,2),
    salud      INT           CHECK (salud >= 0),
    armadura   INT           CHECK (armadura >= 0),
    municion   INT           CHECK (municion >= 0),
    PRIMARY KEY (id_evento),
    UNIQUE (id_partida, id_jugador, tic),
    CONSTRAINT fk_et_partida
        FOREIGN KEY (id_partida) REFERENCES partida (id_partida),
    CONSTRAINT fk_et_jugador
        FOREIGN KEY (id_jugador) REFERENCES jugador (id_jugador),
    CONSTRAINT fk_et_sector
        FOREIGN KEY (id_sector)  REFERENCES sector (id_sector)
);

-- 9. Instrumento_ux

CREATE TABLE instrumento_ux (
    id_instrumento SERIAL      NOT NULL,
    nombre         VARCHAR(50) NOT NULL UNIQUE,
    descripcion    TEXT,
    PRIMARY KEY (id_instrumento)
);

-- 10. Item_ux

CREATE TABLE item_ux (
    id_item        SERIAL       NOT NULL,
    texto_pregunta VARCHAR(255) NOT NULL,
    dimension      VARCHAR(40),
    id_instrumento INT          NOT NULL,
    PRIMARY KEY (id_item),
    CONSTRAINT fk_item_instrumento
        FOREIGN KEY (id_instrumento) REFERENCES instrumento_ux (id_instrumento)
);

-- 11. Respuesta_ux

CREATE TABLE respuesta_ux (
    id_respuesta    SERIAL       NOT NULL,
    fecha_respuesta TIMESTAMP    NOT NULL,
    id_usuario      INT          NOT NULL,
    id_item         INT          NOT NULL,
    id_instrumento  INT          NOT NULL,
    id_partida      INT,
    valor_respuesta NUMERIC(5,2) NOT NULL,
    PRIMARY KEY (id_respuesta),
    CONSTRAINT fk_rux_usuario
        FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario),
    CONSTRAINT fk_rux_item
        FOREIGN KEY (id_item)
        REFERENCES item_ux (id_item),
    CONSTRAINT fk_rux_instrumento
        FOREIGN KEY (id_instrumento)
        REFERENCES instrumento_ux (id_instrumento),
    CONSTRAINT fk_rux_partida
        FOREIGN KEY (id_partida)
        REFERENCES partida (id_partida)
);

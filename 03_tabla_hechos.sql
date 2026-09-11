-- =============================================
-- SCRIPT 3 (v2): TABLAS DE HECHOS
-- Corrige respecto a v1:
--   - Las FK ahora apuntan a las dimensiones reales creadas en 02_dimensiones.sql
--     (en v1 apuntaban a tablas que nunca se llegaban a crear con ese nombre/esquema)
--   - Se quita producto_id de fact_cliente_snapshot: la tenencia de producto no
--     tiene un único "producto principal" por cliente, son 45 indicadores
--     independientes -> se modela aparte, en hechos.fact_producto_cliente
--     (tabla puente/factless, una fila por cliente x producto tenido)
--   - Se quitan score_rentabilidad / probabilidad_fuga / valor_vida_cliente:
--     en v1 nunca se calculaban (probabilidad_fuga y valor_vida_cliente quedaban
--     siempre NULL) o se calculaban con una fórmula sin justificar
--     (score_rentabilidad). No se inventan aquí; ver 00_VALIDACION_Y_HALLAZGOS.md
--     punto 3.7. Las métricas de rentabilidad se calculan de forma transparente
--     en 04_vistas_kpi.sql a partir de columnas reales.
--   - Restricción UNIQUE(cliente_sk, tiempo_id) para que un mismo cliente no
--     pueda duplicarse dentro del mismo snapshot (en v1 esto solo lo evitaba
--     un NOT EXISTS en el procedimiento, no una restricción real en la tabla)
-- =============================================

USE BancoSabadellDW;
GO

-- =============================================
-- 1. TABLA DE HECHOS PRINCIPAL: fact_cliente_snapshot
--    Grano: una fila por cliente y por fecha de carga (snapshot)
-- =============================================
CREATE TABLE hechos.fact_cliente_snapshot (
    fact_id                  BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Claves foráneas a dimensiones
    cliente_sk                INT NOT NULL,
    tiempo_id                  INT NOT NULL,

    -- Medidas descriptivas (cambian en cada snapshot, por eso viven en hechos)
    edad                       TINYINT,
    antiguedad_meses           INT,                        -- columna 'antig'

    -- Medidas financieras (todas en EUR)
    total_patrimonio           DECIMAL(15,2),               -- 'totalpasta'
    importe_posicion_deudora   DECIMAL(15,2),               -- 'impoped'
    importe_posicion_acreedora DECIMAL(15,2),               -- 'impopeh'
    renta_final                DECIMAL(15,2),
    gastos_totales             DECIMAL(15,2),               -- 'gastos_tot' ya limpiado a numérico en el ETL
    margen_comercial           DECIMAL(15,2),               -- 'margecomercialut' (puede ser negativo)
    credito_utilizado          DECIMAL(15,2),                -- 'credit'
    revolving_utilizado        DECIMAL(15,2),
    total_hipoteca             DECIMAL(15,2),                -- 'tothipo'
    nomina_importe             DECIMAL(15,2),                -- 'nominaimp'
    rdom                       INT,                           -- nº de recibos domiciliados
    tpv                        BIT,
    total_proteccion           TINYINT,                       -- 'total_proteccio'

    -- Scores de propensión/vinculación (SIO), escala 0-1
    sio_accionabilidad         DECIMAL(6,3),
    sio_ahorro                 DECIMAL(6,3),
    sio_aldia                  DECIMAL(6,3),
    sio_captacion               DECIMAL(6,3),
    sio_desvinculacion          DECIMAL(6,3),
    sio_financiacion            DECIMAL(6,3),
    sio_mediospago               DECIMAL(6,3),
    sio_noaccionable             DECIMAL(6,3),
    sio_proteccion                DECIMAL(6,3),
    sio_transaccionalidad         DECIMAL(6,3),
    sio_vinculacion               DECIMAL(6,3),

    -- Métrica derivada calculada en el ETL (suma simple de los 45 indicadores; no es una fórmula de negocio inventada)
    total_productos_activos    TINYINT,

    fecha_carga                 DATETIME DEFAULT GETDATE(),

    CONSTRAINT uq_fact_cliente_snapshot UNIQUE (cliente_sk, tiempo_id),
    CONSTRAINT fk_factcliente_cliente FOREIGN KEY (cliente_sk)
        REFERENCES dimensiones.dim_cliente(cliente_sk),
    CONSTRAINT fk_factcliente_tiempo FOREIGN KEY (tiempo_id)
        REFERENCES dimensiones.dim_tiempo(tiempo_id)
);
GO

CREATE INDEX idx_fact_cliente_tiempo ON hechos.fact_cliente_snapshot(tiempo_id);
CREATE INDEX idx_fact_cliente_patrimonio ON hechos.fact_cliente_snapshot(total_patrimonio);
CREATE INDEX idx_fact_cliente_renta ON hechos.fact_cliente_snapshot(renta_final);
CREATE INDEX idx_fact_cliente_margen ON hechos.fact_cliente_snapshot(margen_comercial);
GO

-- =============================================
-- 2. TABLA PUENTE: fact_producto_cliente
--    Grano: una fila por cliente x producto que tiene contratado, por snapshot
--    (factless fact table: solo existe la fila si el indicador ind_* = 1;
--     así la penetración de producto es un simple GROUP BY, sin 45 UNION ALL)
-- =============================================
CREATE TABLE hechos.fact_producto_cliente (
    fact_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    cliente_sk          INT NOT NULL,
    producto_sk          INT NOT NULL,
    tiempo_id             INT NOT NULL,

    CONSTRAINT uq_fact_producto_cliente UNIQUE (cliente_sk, producto_sk, tiempo_id),
    CONSTRAINT fk_factproducto_cliente FOREIGN KEY (cliente_sk)
        REFERENCES dimensiones.dim_cliente(cliente_sk),
    CONSTRAINT fk_factproducto_producto FOREIGN KEY (producto_sk)
        REFERENCES dimensiones.dim_producto(producto_sk),
    CONSTRAINT fk_factproducto_tiempo FOREIGN KEY (tiempo_id)
        REFERENCES dimensiones.dim_tiempo(tiempo_id)
);
GO

CREATE INDEX idx_factproducto_producto_tiempo ON hechos.fact_producto_cliente(producto_sk, tiempo_id);
CREATE INDEX idx_factproducto_cliente_tiempo ON hechos.fact_producto_cliente(cliente_sk, tiempo_id);
GO

PRINT 'Tablas de hechos (v2) creadas correctamente';
GO

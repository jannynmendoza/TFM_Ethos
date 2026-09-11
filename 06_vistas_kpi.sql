-- =============================================
-- SCRIPT 6 (v2): VISTAS DE KPI
-- Implementa el catálogo de 05_KPIS_definicion.md.
-- Todas las vistas toman el ÚLTIMO snapshot cargado (MAX(tiempo_id)) salvo
-- que se indique lo contrario, para que sigan funcionando igual aunque en el
-- futuro se carguen varios snapshots en fact_cliente_snapshot.
-- =============================================

USE BancoSabadellDW;
GO

CREATE OR ALTER VIEW analitica.vw_ultimo_snapshot AS
SELECT MAX(tiempo_id) AS tiempo_id FROM hechos.fact_cliente_snapshot;
GO

-- =============================================
-- 1. RESUMEN DE CARTERA (KPI de portada / vista ejecutiva)
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_resumen_cartera AS
SELECT
    COUNT(*)                                                        AS total_clientes,
    SUM(fc.total_patrimonio)                                        AS patrimonio_total,
    AVG(fc.total_patrimonio)                                        AS patrimonio_medio,
    AVG(fc.renta_final)                                             AS renta_media,
    SUM(fc.margen_comercial)                                        AS margen_total,
    AVG(fc.margen_comercial)                                        AS margen_medio,
    CAST(SUM(CASE WHEN fc.margen_comercial < 0 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100                                            AS pct_clientes_margen_negativo,
    AVG(CAST(fc.total_productos_activos AS FLOAT))                  AS productos_medios_por_cliente,
    CAST(SUM(CASE WHEN fc.total_hipoteca > 0 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100                                            AS pct_clientes_con_hipoteca,
    CAST(SUM(CASE WHEN fc.revolving_utilizado > 0 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100                                            AS pct_clientes_con_revolving
FROM hechos.fact_cliente_snapshot fc
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id;
GO

-- =============================================
-- 2. KPI POR SEGMENTO (tipo_inversion)
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_por_segmento AS
SELECT
    ds.tipo_inversion,
    ds.orden_perfil,
    COUNT(*)                                                        AS total_clientes,
    AVG(fc.total_patrimonio)                                        AS patrimonio_medio,
    AVG(fc.renta_final)                                             AS renta_media,
    AVG(fc.margen_comercial)                                        AS margen_medio,
    CAST(SUM(CASE WHEN fc.margen_comercial < 0 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100                                            AS pct_clientes_margen_negativo,
    AVG(CAST(fc.total_productos_activos AS FLOAT))                  AS productos_medios,
    AVG(fc.total_patrimonio / NULLIF(fc.renta_final, 0))            AS ratio_patrimonio_renta,
    AVG(fc.sio_vinculacion)                                         AS sio_vinculacion_media,
    AVG(fc.sio_transaccionalidad)                                   AS sio_transaccionalidad_media,
    AVG(fc.sio_accionabilidad)                                      AS sio_accionabilidad_media
FROM hechos.fact_cliente_snapshot fc
INNER JOIN dimensiones.dim_cliente dc ON dc.cliente_sk = fc.cliente_sk
INNER JOIN dimensiones.dim_segmento ds ON ds.segmento_sk = dc.segmento_sk
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id
GROUP BY ds.tipo_inversion, ds.orden_perfil;
GO

-- =============================================
-- 3. KPI POR NIVEL DE RENTA
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_por_nivel_renta AS
SELECT
    dc.nivel_renta,
    COUNT(*)                                    AS total_clientes,
    AVG(fc.total_patrimonio)                    AS patrimonio_medio,
    AVG(fc.margen_comercial)                    AS margen_medio,
    AVG(CAST(fc.total_productos_activos AS FLOAT)) AS productos_medios
FROM hechos.fact_cliente_snapshot fc
INNER JOIN dimensiones.dim_cliente dc ON dc.cliente_sk = fc.cliente_sk
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id
GROUP BY dc.nivel_renta;
GO

-- =============================================
-- 4. PENETRACIÓN DE PRODUCTO (vía tabla puente, sin UNION ALL)
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_penetracion_producto AS
SELECT
    dp.categoria,
    dp.nombre_producto,
    dp.codigo_indicador,
    COUNT(fp.cliente_sk)                                            AS clientes_con_producto,
    CAST(COUNT(fp.cliente_sk) AS FLOAT) / NULLIF(t.total_clientes, 0) * 100 AS pct_penetracion
FROM dimensiones.dim_producto dp
CROSS JOIN (SELECT COUNT(*) AS total_clientes FROM dimensiones.dim_cliente) t
LEFT JOIN hechos.fact_producto_cliente fp
    ON fp.producto_sk = dp.producto_sk
    AND fp.tiempo_id = (SELECT tiempo_id FROM analitica.vw_ultimo_snapshot)
GROUP BY dp.categoria, dp.nombre_producto, dp.codigo_indicador, t.total_clientes;
GO

-- =============================================
-- 5. DISTRIBUCIÓN DE CLIENTES POR Nº DE PRODUCTOS
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_distribucion_productos AS
SELECT
    fc.total_productos_activos                  AS numero_productos,
    COUNT(*)                                     AS total_clientes,
    AVG(fc.total_patrimonio)                     AS patrimonio_medio,
    AVG(fc.margen_comercial)                     AS margen_medio
FROM hechos.fact_cliente_snapshot fc
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id
GROUP BY fc.total_productos_activos;
GO

-- =============================================
-- 6. ENDEUDAMIENTO
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_endeudamiento AS
SELECT
    dc.cliente_sk,
    dc.id_cliente,
    ds.tipo_inversion,
    fc.total_patrimonio,
    fc.credito_utilizado,
    fc.revolving_utilizado,
    fc.total_hipoteca,
    (ISNULL(fc.credito_utilizado,0) + ISNULL(fc.revolving_utilizado,0) + ISNULL(fc.total_hipoteca,0))
        / NULLIF(fc.total_patrimonio, 0)                            AS ratio_endeudamiento
FROM hechos.fact_cliente_snapshot fc
INNER JOIN dimensiones.dim_cliente dc ON dc.cliente_sk = fc.cliente_sk
INNER JOIN dimensiones.dim_segmento ds ON ds.segmento_sk = dc.segmento_sk
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id;
GO

-- =============================================
-- 7. DISTRIBUCIÓN GEOGRÁFICA (por provincia)
-- =============================================
CREATE OR ALTER VIEW analitica.vw_kpi_por_provincia AS
SELECT
    dg.provincia_nombre,
    dg.es_extranjero,
    COUNT(*)                                     AS total_clientes,
    SUM(fc.total_patrimonio)                     AS patrimonio_total,
    AVG(fc.total_patrimonio)                     AS patrimonio_medio
FROM hechos.fact_cliente_snapshot fc
INNER JOIN dimensiones.dim_cliente dc ON dc.cliente_sk = fc.cliente_sk
INNER JOIN dimensiones.dim_geografia dg ON dg.geografia_sk = dc.geografia_sk
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id
GROUP BY dg.provincia_nombre, dg.es_extranjero;
GO

-- =============================================
-- 8. TOP CLIENTES POR PATRIMONIO (para revisión manual / gestores)
-- =============================================
CREATE OR ALTER VIEW analitica.vw_top_clientes_patrimonio AS
SELECT TOP 100
    dc.id_cliente,
    ds.tipo_inversion,
    dc.nivel_renta,
    dg.provincia_nombre,
    fc.total_patrimonio,
    fc.renta_final,
    fc.margen_comercial,
    fc.total_productos_activos
FROM hechos.fact_cliente_snapshot fc
INNER JOIN dimensiones.dim_cliente dc ON dc.cliente_sk = fc.cliente_sk
INNER JOIN dimensiones.dim_segmento ds ON ds.segmento_sk = dc.segmento_sk
INNER JOIN dimensiones.dim_geografia dg ON dg.geografia_sk = dc.geografia_sk
CROSS JOIN analitica.vw_ultimo_snapshot u
WHERE fc.tiempo_id = u.tiempo_id
ORDER BY fc.total_patrimonio DESC;
GO

PRINT 'Vistas de KPI (v2) creadas correctamente';
GO

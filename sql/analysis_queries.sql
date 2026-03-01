-- =============================================================================
-- analysis_queries.sql
-- Progetto: Sales & Product Performance Analytics
--
-- Query SQL su database DrScharAnalytics.
-- Strutturate in 5 sezioni: Revenue, Time Intelligence, Product Performance,
-- Customer Segmentation (RFM), Advanced Analytics.
-- =============================================================================

USE DrScharAnalytics;

-- =============================================================================
-- SEZIONE 1: REVENUE ANALYSIS
-- =============================================================================

-- Q1.1 - Fatturato totale per anno
SELECT
    YEAR(s.sale_date)               AS anno,
    COUNT(s.sale_id)                AS numero_ordini,
    SUM(s.total_amount)             AS fatturato_totale,
    AVG(s.total_amount)             AS valore_medio_ordine,
    SUM(s.quantity)                 AS unita_vendute
FROM Sales s
GROUP BY YEAR(s.sale_date)
ORDER BY anno;


-- Q1.2 - Ranking prodotti per fatturato
-- RANK() assegna lo stesso rango a prodotti con fatturato uguale (1,2,2,4).
SELECT
    p.product_name,
    p.category,
    p.brand,
    SUM(s.total_amount)             AS fatturato_totale,
    SUM(s.quantity)                 AS unita_vendute,
    RANK() OVER (
        ORDER BY SUM(s.total_amount) DESC
    )                               AS rank_fatturato
FROM Sales s
JOIN Products p ON s.product_id = p.product_id
GROUP BY p.product_name, p.category, p.brand
ORDER BY rank_fatturato;


-- Q1.3 - Top 10 prodotti con percentuale sul totale
-- SUM() OVER () senza PARTITION BY restituisce il totale generale,
-- usato come denominatore per la percentuale senza subquery separata.
SELECT TOP 10
    p.product_name,
    p.category,
    SUM(s.total_amount)                                         AS fatturato_prodotto,
    ROUND(
        SUM(s.total_amount) * 100.0 /
        SUM(SUM(s.total_amount)) OVER ()
    , 2)                                                        AS perc_sul_totale
FROM Sales s
JOIN Products p ON s.product_id = p.product_id
GROUP BY p.product_name, p.category
ORDER BY fatturato_prodotto DESC;


-- =============================================================================
-- SEZIONE 2: TIME INTELLIGENCE
-- =============================================================================

-- Q2.1 - Fatturato mensile con confronto mese precedente
-- LAG() accede al valore del mese precedente senza self-join.
-- NULLIF al denominatore evita la divisione per zero.
WITH monthly_revenue AS (
    SELECT
        c.year                          AS anno,
        c.month                         AS mese,
        c.month_name                    AS nome_mese,
        SUM(s.total_amount)             AS fatturato_mensile
    FROM Sales s
    JOIN Calendar c ON s.sale_date = c.full_date
    GROUP BY c.year, c.month, c.month_name
)
SELECT
    anno,
    mese,
    nome_mese,
    fatturato_mensile,
    LAG(fatturato_mensile, 1) OVER (
        ORDER BY anno, mese
    )                                   AS fatturato_mese_precedente,
    ROUND(
        (fatturato_mensile - LAG(fatturato_mensile, 1) OVER (ORDER BY anno, mese))
        * 100.0
        / NULLIF(LAG(fatturato_mensile, 1) OVER (ORDER BY anno, mese), 0)
    , 2)                                AS variazione_pct_mom
FROM monthly_revenue
ORDER BY anno, mese;


-- Q2.2 - Fatturato cumulativo per mese
-- PARTITION BY anno fa ripartire il totale da zero ogni anno.
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW definisce
-- la finestra dalla prima riga fino a quella corrente.
WITH monthly_revenue AS (
    SELECT
        c.year                          AS anno,
        c.month                         AS mese,
        c.month_name                    AS nome_mese,
        SUM(s.total_amount)             AS fatturato_mensile
    FROM Sales s
    JOIN Calendar c ON s.sale_date = c.full_date
    GROUP BY c.year, c.month, c.month_name
)
SELECT
    anno,
    mese,
    nome_mese,
    fatturato_mensile,
    SUM(fatturato_mensile) OVER (
        PARTITION BY anno
        ORDER BY mese
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                   AS fatturato_cumulativo_ytd
FROM monthly_revenue
ORDER BY anno, mese;


-- Q2.3 - Confronto anno su anno per trimestre
-- Pivot manuale con CASE WHEN: estrae il valore per anno specifico,
-- somma zero per gli altri, poi GROUP BY trimestre collassa tutto.
WITH quarterly_revenue AS (
    SELECT
        c.year                          AS anno,
        c.quarter                       AS trimestre,
        SUM(s.total_amount)             AS fatturato
    FROM Sales s
    JOIN Calendar c ON s.sale_date = c.full_date
    GROUP BY c.year, c.quarter
)
SELECT
    trimestre,
    SUM(CASE WHEN anno = 2023 THEN fatturato ELSE 0 END)    AS fatturato_2023,
    SUM(CASE WHEN anno = 2024 THEN fatturato ELSE 0 END)    AS fatturato_2024,
    SUM(CASE WHEN anno = 2024 THEN fatturato ELSE 0 END) -
    SUM(CASE WHEN anno = 2023 THEN fatturato ELSE 0 END)    AS variazione_assoluta,
    ROUND(
        (SUM(CASE WHEN anno = 2024 THEN fatturato ELSE 0 END) -
         SUM(CASE WHEN anno = 2023 THEN fatturato ELSE 0 END))
        * 100.0
        / NULLIF(SUM(CASE WHEN anno = 2023 THEN fatturato ELSE 0 END), 0)
    , 2)                                                    AS variazione_pct_yoy
FROM quarterly_revenue
GROUP BY trimestre
ORDER BY trimestre;


-- =============================================================================
-- SEZIONE 3: PRODUCT PERFORMANCE
-- =============================================================================

-- Q3.1 - Ranking per categoria
-- PARTITION BY category genera un ranking separato per ogni categoria.
SELECT
    p.category,
    p.product_name,
    p.brand,
    COUNT(s.sale_id)                AS numero_ordini,
    SUM(s.total_amount)             AS fatturato,
    AVG(s.discount_pct)             AS sconto_medio_pct,
    RANK() OVER (
        PARTITION BY p.category
        ORDER BY SUM(s.total_amount) DESC
    )                               AS rank_in_categoria
FROM Sales s
JOIN Products p ON s.product_id = p.product_id
GROUP BY p.category, p.product_name, p.brand
ORDER BY p.category, rank_in_categoria;


-- Q3.2 - Organico vs convenzionale
-- LEFT JOIN per includere anche i prodotti senza vendite nel conteggio.
-- CASE WHEN converte il flag is_organic (0/1) in testo leggibile.
SELECT
    CASE WHEN p.is_organic = 1 THEN 'Organico' ELSE 'Convenzionale' END
                                    AS tipo_prodotto,
    COUNT(DISTINCT p.product_id)    AS numero_prodotti,
    COUNT(s.sale_id)                AS numero_vendite,
    SUM(s.total_amount)             AS fatturato_totale,
    AVG(s.total_amount)             AS valore_medio_ordine,
    AVG(p.unit_price)               AS prezzo_medio_listino,
    AVG(s.discount_pct)             AS sconto_medio_pct
FROM Products p
LEFT JOIN Sales s ON p.product_id = s.product_id
GROUP BY p.is_organic
ORDER BY fatturato_totale DESC;


-- Q3.3 - Prodotti senza vendite
-- LEFT JOIN + WHERE IS NULL per trovare prodotti mai venduti.
SELECT
    p.product_id,
    p.product_name,
    p.brand,
    p.category,
    p.unit_price,
    p.launch_date
FROM Products p
LEFT JOIN Sales s ON p.product_id = s.product_id
WHERE s.sale_id IS NULL
ORDER BY p.category, p.product_name;


-- =============================================================================
-- SEZIONE 4: CUSTOMER SEGMENTATION - RFM
-- =============================================================================

-- Q4.1 - Segmentazione RFM per cliente
-- Due CTE: la prima calcola le metriche grezze, la seconda assegna
-- i punteggi con NTILE(4) che divide i clienti in 4 gruppi uguali.
-- Recency è ordinata ASC perché meno giorni = cliente più recente = meglio.
WITH rfm_base AS (
    SELECT
        c.customer_id,
        c.customer_name,
        c.customer_type,
        c.region,
        DATEDIFF(DAY, MAX(s.sale_date), '2024-12-31')   AS recency_giorni,
        COUNT(s.sale_id)                                 AS frequency,
        SUM(s.total_amount)                              AS monetary
    FROM Customers c
    JOIN Sales s ON c.customer_id = s.customer_id
    GROUP BY c.customer_id, c.customer_name, c.customer_type, c.region
),
rfm_scores AS (
    SELECT
        customer_id,
        customer_name,
        customer_type,
        region,
        recency_giorni,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY recency_giorni ASC)     AS r_score,
        NTILE(4) OVER (ORDER BY frequency DESC)         AS f_score,
        NTILE(4) OVER (ORDER BY monetary DESC)          AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    customer_name,
    customer_type,
    region,
    recency_giorni,
    frequency,
    ROUND(monetary, 2)              AS monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score)   AS rfm_score_totale,
    CASE
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Champions'
        WHEN (r_score + f_score + m_score) >= 8  THEN 'Loyal Customers'
        WHEN (r_score + f_score + m_score) >= 6  THEN 'Potential Loyalists'
        WHEN (r_score + f_score + m_score) >= 4  THEN 'At Risk'
        ELSE                                           'Lost'
    END                             AS segmento_cliente
FROM rfm_scores
ORDER BY rfm_score_totale DESC;


-- Q4.2 - Distribuzione clienti per segmento
WITH rfm_base AS (
    SELECT
        c.customer_id,
        DATEDIFF(DAY, MAX(s.sale_date), '2024-12-31')   AS recency_giorni,
        COUNT(s.sale_id)                                 AS frequency,
        SUM(s.total_amount)                              AS monetary
    FROM Customers c
    JOIN Sales s ON c.customer_id = s.customer_id
    GROUP BY c.customer_id
),
rfm_scores AS (
    SELECT
        customer_id,
        NTILE(4) OVER (ORDER BY recency_giorni ASC)     AS r_score,
        NTILE(4) OVER (ORDER BY frequency DESC)         AS f_score,
        NTILE(4) OVER (ORDER BY monetary DESC)          AS m_score,
        monetary
    FROM rfm_base
),
rfm_segmented AS (
    SELECT
        customer_id,
        ROUND(monetary, 2) AS monetary,
        CASE
            WHEN (r_score + f_score + m_score) >= 10 THEN 'Champions'
            WHEN (r_score + f_score + m_score) >= 8  THEN 'Loyal Customers'
            WHEN (r_score + f_score + m_score) >= 6  THEN 'Potential Loyalists'
            WHEN (r_score + f_score + m_score) >= 4  THEN 'At Risk'
            ELSE                                           'Lost'
        END AS segmento_cliente
    FROM rfm_scores
)
SELECT
    segmento_cliente,
    COUNT(customer_id)              AS numero_clienti,
    ROUND(AVG(monetary), 2)         AS fatturato_medio,
    ROUND(SUM(monetary), 2)         AS fatturato_totale,
    ROUND(COUNT(customer_id) * 100.0 / SUM(COUNT(customer_id)) OVER (), 1)
                                    AS perc_clienti
FROM rfm_segmented
GROUP BY segmento_cliente
ORDER BY fatturato_totale DESC;


-- =============================================================================
-- SEZIONE 5: ADVANCED ANALYTICS
-- =============================================================================

-- Q5.1 - Top 3 prodotti per categoria
-- ROW_NUMBER() garantisce esattamente 3 righe per categoria.
-- Con RANK() in caso di parità potrebbero essere di più.
WITH product_revenue AS (
    SELECT
        p.category,
        p.product_name,
        p.brand,
        SUM(s.total_amount)         AS fatturato,
        ROW_NUMBER() OVER (
            PARTITION BY p.category
            ORDER BY SUM(s.total_amount) DESC
        )                           AS rn
    FROM Sales s
    JOIN Products p ON s.product_id = p.product_id
    GROUP BY p.category, p.product_name, p.brand
)
SELECT
    category,
    product_name,
    brand,
    ROUND(fatturato, 2)             AS fatturato,
    rn                              AS posizione_in_categoria
FROM product_revenue
WHERE rn <= 3
ORDER BY category, rn;


-- Q5.2 - Impatto sconti per regione
-- Fatturato potenziale = effettivo + sconti concessi (listino pieno).
SELECT
    cu.region,
    COUNT(s.sale_id)                            AS numero_ordini,
    ROUND(SUM(s.total_amount), 2)               AS fatturato_effettivo,
    ROUND(SUM(s.discount_amount), 2)            AS totale_sconti_concessi,
    ROUND(SUM(s.total_amount) + SUM(s.discount_amount), 2)
                                                AS fatturato_potenziale,
    ROUND(
        SUM(s.discount_amount) * 100.0 /
        NULLIF(SUM(s.total_amount) + SUM(s.discount_amount), 0)
    , 2)                                        AS perc_fatturato_perso,
    ROUND(AVG(s.discount_pct), 2)               AS sconto_medio_pct
FROM Sales s
JOIN Customers cu ON s.customer_id = cu.customer_id
GROUP BY cu.region
ORDER BY fatturato_effettivo DESC;


-- Q5.3 - Media mobile a 3 mesi
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW: riga corrente + 2 precedenti.
-- Senza ROWS SQL Server usa RANGE di default, che può dare risultati diversi.
WITH monthly_revenue AS (
    SELECT
        c.year                      AS anno,
        c.month                     AS mese,
        c.month_name                AS nome_mese,
        SUM(s.total_amount)         AS fatturato_mensile
    FROM Sales s
    JOIN Calendar c ON s.sale_date = c.full_date
    GROUP BY c.year, c.month, c.month_name
)
SELECT
    anno,
    mese,
    nome_mese,
    ROUND(fatturato_mensile, 2)     AS fatturato_mensile,
    ROUND(
        AVG(fatturato_mensile) OVER (
            ORDER BY anno, mese
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )
    , 2)                            AS media_mobile_3m
FROM monthly_revenue
ORDER BY anno, mese;


-- Q5.4 - KPI sintetici con UNION ALL
-- UNION ALL impila metriche diverse in un unico result set verticale.
SELECT 'Fatturato Totale 2024'      AS kpi,
       ROUND(SUM(s.total_amount), 2) AS valore,
       '€'                           AS unita
FROM Sales s WHERE YEAR(s.sale_date) = 2024

UNION ALL

SELECT 'Ordini Totali 2024',
       COUNT(s.sale_id),
       'n.'
FROM Sales s WHERE YEAR(s.sale_date) = 2024

UNION ALL

SELECT 'Clienti Attivi 2024',
       COUNT(DISTINCT s.customer_id),
       'n.'
FROM Sales s WHERE YEAR(s.sale_date) = 2024

UNION ALL

SELECT 'Sconto Medio 2024',
       ROUND(AVG(s.discount_pct), 2),
       '%'
FROM Sales s WHERE YEAR(s.sale_date) = 2024

UNION ALL

SELECT 'Prodotti Venduti 2024',
       COUNT(DISTINCT s.product_id),
       'n.'
FROM Sales s WHERE YEAR(s.sale_date) = 2024;

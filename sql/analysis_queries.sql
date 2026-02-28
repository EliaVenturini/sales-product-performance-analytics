-- =============================================================================
-- analysis_queries.sql
-- Progetto: Sales & Product Performance Analytics - DR Schär Portfolio
-- Autore:   Elia Venturini
-- Scopo:    Query SQL avanzate su database DrScharAnalytics
--           Ho strutturato le analisi in 5 sezioni tematiche per coprire
--           le tecniche più rilevanti: JOIN, CTE, Window Functions,
--           CASE WHEN, Subquery
-- =============================================================================

USE DrScharAnalytics;

-- =============================================================================
-- SEZIONE 1: REVENUE ANALYSIS
-- Voglio capire quanto fattura l'azienda, per prodotto e per periodo.
-- Parto sempre da aggregazioni semplici prima di aumentare la complessità.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q1.1 - Fatturato totale e numero ordini per anno
-- Ho usato GROUP BY su YEAR(sale_date) per aggregare per anno senza
-- dover creare una colonna aggiuntiva. È la mia query di partenza
-- per avere un quadro generale del business.
-- ----------------------------------------------------------------------------
SELECT
    YEAR(s.sale_date)               AS anno,
    COUNT(s.sale_id)                AS numero_ordini,
    SUM(s.total_amount)             AS fatturato_totale,
    AVG(s.total_amount)             AS valore_medio_ordine,
    SUM(s.quantity)                 AS unita_vendute
FROM Sales s
GROUP BY YEAR(s.sale_date)
ORDER BY anno;


-- ----------------------------------------------------------------------------
-- Q1.2 - Ranking prodotti per fatturato
-- Ho scelto RANK() invece di ROW_NUMBER() perché voglio che prodotti
-- con lo stesso fatturato condividano lo stesso rango (es: 1,2,2,4).
-- ROW_NUMBER() sarebbe sempre univoco ma meno "onesto" in caso di parità.
-- DENSE_RANK() avrebbe fatto 1,2,2,3 — ho preferito RANK() per chiarezza.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q1.3 - Top 10 prodotti con percentuale sul fatturato totale
-- Il trucco che uso qui è SUM() OVER () senza PARTITION BY: questo mi
-- restituisce il totale generale su tutte le righe, che uso come
-- denominatore per calcolare la percentuale in una sola passata,
-- senza dover scrivere una subquery separata.
-- ----------------------------------------------------------------------------
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
-- Voglio analizzare l'andamento delle vendite nel tempo.
-- Ho costruito una tabella Calendar appositamente per rendere queste
-- analisi più semplici ed efficienti.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q2.1 - Fatturato mensile con confronto mese precedente
-- Uso LAG(colonna, 1) per accedere al valore del mese precedente
-- direttamente nella stessa query, senza self-join.
-- Ho usato NULLIF al denominatore per evitare divisioni per zero
-- nel caso in cui il mese precedente non abbia dati.
-- ----------------------------------------------------------------------------
WITH monthly_revenue AS (
    -- Preparo i dati mensili in una CTE per tenere la query finale pulita
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


-- ----------------------------------------------------------------------------
-- Q2.2 - Fatturato cumulativo (running total) per mese
-- Ho usato SUM() OVER con ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- per costruire una somma progressiva. Il PARTITION BY anno fa sì che
-- il contatore riparta da zero ogni anno, che è quello che voglio
-- per monitorare l'avanzamento verso l'obiettivo annuale.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q2.3 - Confronto Year-over-Year per trimestre
-- Invece di usare il PIVOT di SQL Server (che trovo meno leggibile),
-- ho preferito un "pivot manuale" con CASE WHEN: estraggo il valore
-- solo per l'anno che mi interessa e sommo tutto il resto a zero.
-- Questo approccio è più portabile e più facile da modificare.
-- ----------------------------------------------------------------------------
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
-- Voglio analizzare le performance nel dettaglio per prodotto e categoria,
-- inclusi i prodotti che non stanno vendendo — spesso i più informativi.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q3.1 - Ranking interno per categoria
-- Ho aggiunto PARTITION BY category alla window function per ottenere
-- un ranking separato per ogni categoria. Senza PARTITION BY avrei
-- un ranking globale, che non mi dice nulla sulla posizione relativa
-- di un prodotto nel suo segmento.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q3.2 - Prodotti organici vs convenzionali
-- Ho usato LEFT JOIN invece di INNER JOIN per includere anche i prodotti
-- senza vendite nel conteggio. Questo mi dà un quadro più onesto
-- del catalogo. Il CASE WHEN trasforma il flag BIT (0/1) in
-- un'etichetta leggibile nel risultato.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q3.3 - Prodotti senza vendite
-- Ho usato il pattern LEFT JOIN + WHERE IS NULL invece di NOT IN
-- con una subquery, perché su dataset grandi è più efficiente:
-- SQL Server può usare un index seek sul JOIN invece di scansionare
-- tutta la subquery per ogni riga. I prodotti senza vendite sono
-- segnali di possibili problemi di catalogo o distribuzione.
-- ----------------------------------------------------------------------------
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
-- SEZIONE 4: CUSTOMER SEGMENTATION - RFM ANALYSIS
-- Ho implementato l'analisi RFM (Recency, Frequency, Monetary) per
-- segmentare i clienti in base al loro comportamento d'acquisto.
-- È uno dei framework più usati nel retail e nel B2B food.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q4.1 - Segmentazione RFM completa per cliente
-- Ho strutturato la query con due CTE annidate:
-- - rfm_base: calcola le metriche grezze (giorni, conteggio, somma)
-- - rfm_scores: trasforma le metriche in punteggi 1-4 con NTILE(4)
-- NTILE(4) divide i clienti in 4 quartili uguali — è più robusto
-- di soglie fisse perché si adatta automaticamente alla distribuzione.
-- Per Recency ho ordinato ASC perché meno giorni = cliente più recente = meglio.
-- ----------------------------------------------------------------------------
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
        -- Per Recency ordino ASC: chi ha comprato più di recente
        -- (giorni bassi) ottiene il punteggio più alto (4)
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
    -- Converto il punteggio numerico in segmenti di business
    -- con soglie definite manualmente in base alla scala 3-12
    CASE
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Champions'
        WHEN (r_score + f_score + m_score) >= 8  THEN 'Loyal Customers'
        WHEN (r_score + f_score + m_score) >= 6  THEN 'Potential Loyalists'
        WHEN (r_score + f_score + m_score) >= 4  THEN 'At Risk'
        ELSE                                           'Lost'
    END                             AS segmento_cliente
FROM rfm_scores
ORDER BY rfm_score_totale DESC;


-- ----------------------------------------------------------------------------
-- Q4.2 - Distribuzione clienti per segmento RFM
-- Riuso la stessa logica RFM della query precedente in una CTE
-- e ci aggrego sopra per vedere quanti clienti ci sono in ogni
-- segmento e quanto fatturano in media. Questo è il dato che
-- porterei in una riunione commerciale.
-- ----------------------------------------------------------------------------
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
-- Query più complesse che combinano più tecniche insieme.
-- Queste sono quelle che mi piace di più mostrare nel portfolio
-- perché dimostrano che so ragionare su problemi analitici reali.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Q5.1 - Top 3 prodotti per fatturato in ogni categoria
-- Questo è il classico problema "Top N per gruppo" che si risolve
-- con ROW_NUMBER() OVER (PARTITION BY ...).
-- Ho scelto ROW_NUMBER() invece di RANK() perché voglio esattamente
-- 3 righe per categoria — con RANK() potrei averne di più in caso
-- di parità, il che complicherebbe la lettura del risultato.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q5.2 - Impatto degli sconti per regione
-- Voglio capire quante revenue "perdo" per via degli sconti
-- e se ci sono regioni dove si sconta di più.
-- Il fatturato potenziale lo calcolo come: effettivo + sconti concessi,
-- cioè quello che avrei fatturato a listino pieno.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q5.3 - Media mobile a 3 mesi del fatturato
-- La media mobile serve a "lisciare" i picchi stagionali e vedere
-- il trend sottostante. Ho usato ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
-- per definire una finestra di 3 righe (mese corrente + 2 precedenti).
-- Senza la clausola ROWS SQL Server userebbe RANGE, che può dare
-- risultati diversi in presenza di valori duplicati.
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- Q5.4 - KPI executive sintetici
-- Ho usato UNION ALL per impilare verticalmente metriche diverse
-- in un unico result set. Questo formato è comodo per alimentare
-- le card KPI in Power BI senza dover fare trasformazioni aggiuntive.
-- Uso UNION ALL (non UNION) perché non ci sono duplicati da rimuovere
-- e UNION ALL è più veloce perché non fa il controllo dei duplicati.
-- ----------------------------------------------------------------------------
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

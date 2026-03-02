# Sales & Product Performance Analytics

Progetto personale di analisi delle vendite su un catalogo di prodotti, costruito per fare pratica con SQL avanzato, modellazione dati e Power BI.

I dati dei prodotti sono reali e provengono dall'API di Open Food Facts (243 prodotti), mentre clienti e vendite sono simulati con Faker per creare un dataset B2B realistico (150 clienti, 5.000 transazioni 2023-2024).

---

## Stack

- **Python 3.13** — generazione dataset (pandas, Faker) e caricamento su SQL Server (SQLAlchemy, pyodbc)
- **SQL Server 2025** — database relazionale con modello a stella (star schema)
- **Power BI** — dashboard interattiva su 4 pagine *(in sviluppo)*

---

## Struttura

La cartella `scripts/` contiene due file Python: `generate_data.py` che scarica i prodotti dall'API e genera clienti e vendite simulati, e `load_to_sqlserver.py` che crea il database, le tabelle e carica i CSV. In `sql/` c'è `analysis_queries.sql` con le 12 query avanzate. La cartella `data/` contiene i tre CSV generati: products, customers e sales.

---

## Database

Ho progettato un modello a stella con 4 tabelle:

- **Products** — dati reali da Open Food Facts (nome, brand, categoria, prezzo, is_organic)
- **Customers** — clienti B2B con tipo, regione e paese
- **Sales** — transazioni con quantità, prezzo, sconto e totale
- **Calendar** — tabella data generata via Python, usata per le analisi temporali in SQL e Power BI

Le relazioni principali sono Sales → Products, Sales → Customers e Sales → Calendar.

---

## Query SQL

Le 12 query in `sql/analysis_queries.sql` sono organizzate in 5 sezioni:

- **Revenue Analysis** — aggregazioni, `RANK()`, percentuale sul totale con `SUM() OVER()`
- **Time Intelligence** — trend mensile con `LAG()`, fatturato cumulativo, confronto YoY con `CASE WHEN`
- **Product Performance** — ranking per categoria con `RANK() OVER (PARTITION BY)`, prodotti senza vendite con `LEFT JOIN + IS NULL`
- **Customer Segmentation** — analisi RFM con CTE multiple e `NTILE(4)`
- **Advanced Analytics** — Top N per gruppo con `ROW_NUMBER()`, media mobile a 3 mesi, KPI con `UNION ALL`

---

## Dashboard Power BI *(in sviluppo)*

La dashboard è strutturata su 4 pagine: Executive Overview, Product Performance, Customer Analysis e una pagina di dettaglio prodotto con drill-through. Verrà pubblicata su NovyPro al completamento.

---



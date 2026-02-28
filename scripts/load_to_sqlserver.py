# =============================================================================
# load_to_sqlserver.py
# Scopo: Carica i dati CSV nel database SQL Server DrScharAnalytics
#        e genera la tabella Calendar automaticamente.
# =============================================================================

import pandas as pd
from sqlalchemy import create_engine, text
from datetime import date
import urllib

# =============================================================================
# CONFIGURAZIONE CONNESSIONE
# Usiamo Windows Authentication (Trusted_Connection=yes) come nel tuo setup
# =============================================================================

SERVER = "localhost"
DATABASE = "DrScharAnalytics"

# Costruiamo la connection string per SQLAlchemy tramite pyodbc
# urllib.parse.quote_plus serve per "urlare" i parametri speciali
params = urllib.parse.quote_plus(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE=master;"          # Ci connettiamo a master PRIMA di creare il nostro DB
    f"Trusted_Connection=yes;"
)

engine_master = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")

# =============================================================================
# STEP 1: CREAZIONE DATABASE
# Usiamo "autocommit=True" perché CREATE DATABASE non può stare dentro
# una transazione in SQL Server (darebbe errore).
# =============================================================================

print(">>> STEP 1: Creazione database DrScharAnalytics...")

create_db_sql = """
IF NOT EXISTS (
    SELECT name FROM sys.databases WHERE name = 'DrScharAnalytics'
)
CREATE DATABASE DrScharAnalytics;
"""

# "with engine_master.connect() as conn" apre la connessione e la chiude
# automaticamente al termine del blocco (context manager)
with engine_master.connect() as conn:
    conn.execution_options(isolation_level="AUTOCOMMIT")
    conn.execute(text(create_db_sql))
    print("    Database creato (o già esistente).")

# =============================================================================
# STEP 2: NUOVO ENGINE sul database DrScharAnalytics
# Ora che il DB esiste, ricreiamo l'engine puntando al database corretto
# =============================================================================

params_db = urllib.parse.quote_plus(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    f"Trusted_Connection=yes;"
)

engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params_db}")

# =============================================================================
# STEP 3: CREAZIONE TABELLE
# Usiamo IF NOT EXISTS per rendere lo script rieseguibile senza errori.
# I tipi di dato sono scelti per ottimizzare spazio e semantica:
#   - NVARCHAR per testo (supporta Unicode, utile per nomi internazionali)
#   - DECIMAL(10,2) per prezzi (evita errori di arrotondamento del float)
#   - BIT per booleani (0/1, occupa 1 bit invece di un intero)
#   - DATE per date senza orario, DATETIME2 se servisse il timestamp
# =============================================================================

print(">>> STEP 3: Creazione tabelle...")

tables_sql = """
-- -------------------------------------------------------
-- PRODUCTS: dati reali da Open Food Facts API
-- -------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Products')
CREATE TABLE Products (
    product_id      INT             PRIMARY KEY,
    product_name    NVARCHAR(300)   NOT NULL,
    brand           NVARCHAR(150),
    category        NVARCHAR(100),
    calories_per_100g DECIMAL(8,2),
    is_organic      BIT             DEFAULT 0,
    unit_price      DECIMAL(10,2)   NOT NULL,
    launch_date     DATE
);

-- -------------------------------------------------------
-- CUSTOMERS: clienti B2B simulati con Faker
-- -------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Customers')
CREATE TABLE Customers (
    customer_id         INT             PRIMARY KEY,
    customer_name       NVARCHAR(200)   NOT NULL,
    customer_type       NVARCHAR(50),
    region              NVARCHAR(100),
    country             NVARCHAR(100),
    registration_date   DATE,
    is_active           BIT             DEFAULT 1
);

-- -------------------------------------------------------
-- SALES: 5000 transazioni simulate 2023-2024
-- Le FK (FOREIGN KEY) garantiscono integrità referenziale:
-- non puoi inserire una vendita con un product_id inesistente
-- -------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Sales')
CREATE TABLE Sales (
    sale_id         INT             PRIMARY KEY,
    product_id      INT             NOT NULL,
    customer_id     INT             NOT NULL,
    sale_date       DATE            NOT NULL,
    quantity        INT             NOT NULL,
    unit_price      DECIMAL(10,2)   NOT NULL,
    discount_pct    DECIMAL(5,2)    DEFAULT 0,
    discount_amount DECIMAL(10,2)   DEFAULT 0,
    total_amount    DECIMAL(10,2)   NOT NULL,
    CONSTRAINT FK_Sales_Products  FOREIGN KEY (product_id)  REFERENCES Products(product_id),
    CONSTRAINT FK_Sales_Customers FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
);

-- -------------------------------------------------------
-- CALENDAR: tabella dimensione data (generata via Python)
-- Fondamentale nei modelli Power BI per le time intelligence
-- -------------------------------------------------------
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Calendar')
CREATE TABLE Calendar (
    date_key        INT             PRIMARY KEY,  -- formato YYYYMMDD, es: 20230115
    full_date       DATE            NOT NULL,
    year            SMALLINT        NOT NULL,
    quarter         TINYINT         NOT NULL,     -- 1-4
    month           TINYINT         NOT NULL,     -- 1-12
    month_name      NVARCHAR(20)    NOT NULL,
    week            TINYINT         NOT NULL,     -- settimana ISO dell'anno
    day_of_week     TINYINT         NOT NULL      -- 1=Lunedì ... 7=Domenica (ISO)
);
"""

with engine.connect() as conn:
    conn.execution_options(isolation_level="AUTOCOMMIT")
    conn.execute(text(tables_sql))
    print("    Tabelle create (o già esistenti).")

# =============================================================================
# STEP 4: CARICAMENTO CSV → SQL SERVER
# Usiamo pandas + SQLAlchemy: to_sql() scrive il DataFrame direttamente
# nella tabella specificata.
# if_exists="append": aggiunge righe senza eliminare la tabella
# if_exists="replace": eliminerebbe e ricreerebbe la tabella (evitiamo,
#                      perché perderemmo tipi di dato e FK definiti sopra)
# index=False: non scrivere l'indice di pandas come colonna extra
# =============================================================================

print(">>> STEP 4: Caricamento dati CSV...")

# --- Products ---
print("    Caricamento Products...")
df_products = pd.read_csv("data/products.csv")
# Convertiamo la colonna data: pandas la legge come stringa, SQL Server vuole un tipo date
df_products["launch_date"] = pd.to_datetime(df_products["launch_date"], errors="coerce")
# errors="coerce": se trova un valore non parsabile lo trasforma in NaT (null) invece di crashare

with engine.begin() as conn:  # engine.begin() apre una transazione; fa auto-commit se tutto va bene
    df_products.to_sql("Products", conn, if_exists="append", index=False)
print(f"    {len(df_products)} prodotti caricati.")

# --- Customers ---
print("    Caricamento Customers...")
df_customers = pd.read_csv("data/customers.csv")
df_customers["registration_date"] = pd.to_datetime(df_customers["registration_date"], errors="coerce")

with engine.begin() as conn:
    df_customers.to_sql("Customers", conn, if_exists="append", index=False)
print(f"    {len(df_customers)} clienti caricati.")

# --- Sales ---
# Le Sales vanno caricate DOPO Products e Customers (vincolo FK)
print("    Caricamento Sales...")
df_sales = pd.read_csv("data/sales.csv")
df_sales["sale_date"] = pd.to_datetime(df_sales["sale_date"], errors="coerce")

with engine.begin() as conn:
    df_sales.to_sql("Sales", conn, if_exists="append", index=False)
print(f"    {len(df_sales)} vendite caricate.")

# =============================================================================
# STEP 5: GENERAZIONE E CARICAMENTO TABELLA CALENDAR
# Copre l'intero range temporale delle vendite (2023-2024) + margine
# =============================================================================

print(">>> STEP 5: Generazione Calendar...")

# Definiamo il range: dal 01/01/2023 al 31/12/2024
date_range = pd.date_range(start="2023-01-01", end="2024-12-31", freq="D")

# Costruiamo il DataFrame con tutte le colonne necessarie
calendar_df = pd.DataFrame({
    # date_key come intero YYYYMMDD: comodo per i JOIN e leggibile
    "date_key"    : date_range.strftime("%Y%m%d").astype(int),
    "full_date"   : date_range.date,                          # oggetto Python date
    "year"        : date_range.year,
    "quarter"     : date_range.quarter,
    "month"       : date_range.month,
    # strftime("%B") restituisce il nome del mese in inglese (January, February...)
    "month_name"  : date_range.strftime("%B"),
    # isocalendar().week restituisce la settimana ISO (1-53)
    "week"        : date_range.isocalendar().week.astype(int),
    # isocalendar().day: 1=Lunedì, 7=Domenica (standard ISO 8601)
    "day_of_week" : date_range.isocalendar().day.astype(int),
})

print(f"    Generati {len(calendar_df)} giorni ({calendar_df['full_date'].min()} → {calendar_df['full_date'].max()})")

with engine.begin() as conn:
    calendar_df.to_sql("Calendar", conn, if_exists="append", index=False)
print(f"    Calendar caricata.")

# =============================================================================
# STEP 6: VERIFICA FINALE
# Stampiamo il conteggio righe di ogni tabella come sanity check
# =============================================================================

print("\n>>> STEP 6: Verifica conteggio righe...")

tables = ["Products", "Customers", "Sales", "Calendar"]

with engine.connect() as conn:
    for table in tables:
        # text() è necessario per eseguire SQL raw con SQLAlchemy 2.x
        result = conn.execute(text(f"SELECT COUNT(*) FROM {table}"))
        count = result.scalar()  # scalar() prende il singolo valore restituito
        print(f"    {table}: {count} righe")

print("\n Caricamento completato con successo!")
print(f"   Database '{DATABASE}' su server '{SERVER}' pronto per le query SQL.")
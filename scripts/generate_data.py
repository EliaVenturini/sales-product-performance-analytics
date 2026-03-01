"""
=============================================================
Script 1: Data Generation
=============================================================
Questo script fa due cose:
1. Scarica prodotti gluten-free reali da Open Food Facts API
2. Genera dati simulati di vendite e clienti
=============================================================
"""

import requests          # per chiamare API esterne
import pandas as pd      # per lavorare con tabelle di dati
import random            # per generare numeri casuali
from faker import Faker  # per generare nomi/indirizzi falsi realistici
from datetime import date, timedelta
import json

# Inizializza Faker in italiano
fake = Faker('it_IT')

# Imposta un seed per riproducibilità (stesso seed = stessi dati ogni volta)
random.seed(42)
Faker.seed(42)

print("=" * 60)
print("DR SCHAR - Data Generation Script")
print("=" * 60)


# =============================================================
# PARTE 1: PRODOTTI DA OPEN FOOD FACTS API
# =============================================================
print("\n[1/3] Scaricamento prodotti da Open Food Facts...")

def get_gluten_free_products(n_pages=5):
    """
    Scarica prodotti dall'API Open Food Facts.
    L'API è pubblica e gratuita, non serve autenticazione.
    Restituisce una lista di dizionari con i dati dei prodotti.
    """
    products = []
    
    for page in range(1, n_pages + 1):
        url = "https://world.openfoodfacts.org/cgi/search.pl"
        params = {
            "action": "process",
            "tagtype_0": "labels",
            "tag_contains_0": "contains",
            "tag_0": "gluten-free",
            "json": 1,
            "page_size": 50,
            "page": page,
            "fields": "id,product_name,brands,categories,quantity,nutriments,labels"
        }
        
        try:
            response = requests.get(url, params=params, timeout=30)
            data = response.json()
            products.extend(data.get("products", []))
            print(f"  Pagina {page}/5 scaricata - {len(products)} prodotti totali")
        except Exception as e:
            print(f"  Errore pagina {page}: {e}")
    
    return products

# Scarica i prodotti
raw_products = get_gluten_free_products(n_pages=5)

# Pulisce e struttura i dati in una tabella
def clean_products(raw_products):
    """
    Prende i dati grezzi dell'API e li trasforma in una tabella pulita.
    Filtra i prodotti senza nome e normalizza i campi.
    """
    cleaned = []
    product_id = 1
    
    # Categorie DR Schär reali per assegnare una categoria a ogni prodotto
    schar_categories = [
        'Bread & Bakery', 'Pasta & Grains', 'Snacks & Crackers',
        'Pizza & Savory', 'Biscuits & Sweet', 'Flour & Mixes'
    ]
    
    for p in raw_products:
        name = p.get("product_name", "").strip()
        
        # Salta prodotti senza nome o con nome troppo corto
        if not name or len(name) < 3:
            continue
        
        brand = p.get("brands", "Unknown").split(",")[0].strip()
        if not brand:
            brand = "Unknown"
        
        # Prende il primo valore di energia dai dati nutrizionali
        nutriments = p.get("nutriments", {})
        calories = nutriments.get("energy-kcal_100g", None)
        
        cleaned.append({
            "product_id": product_id,
            "product_name": name[:100],  # tronca a 100 caratteri
            "brand": brand[:50],
            "category": random.choice(schar_categories),  # assegna categoria casuale
            "calories_per_100g": round(float(calories), 1) if calories else None,
            "is_organic": random.choice([True, False, False, False]),  # 25% organici
            "unit_price": round(random.uniform(1.50, 8.99), 2),  # prezzo simulato
            "launch_date": fake.date_between(start_date=date(2020, 1, 1), end_date=date(2023, 12, 31))
        })
        
        product_id += 1
        
        # Ci fermiamo a 300 prodotti
        if product_id > 300:
            break
    
    return pd.DataFrame(cleaned)

df_products = clean_products(raw_products)
print(f"  Prodotti puliti e pronti: {len(df_products)}")


# =============================================================
# PARTE 2: CLIENTI SIMULATI
# =============================================================
print("\n[2/3] Generazione clienti simulati...")

def generate_customers(n=150):
    """
    Genera clienti B2B simulati (supermercati, negozi bio, farmacie, ecc.)
    tipici del mercato DR Schär.
    """
    customer_types = ['Supermarket', 'Health Food Store', 'Pharmacy', 'Online Retailer', 'Restaurant']
    regions = ['Nord Italia', 'Centro Italia', 'Sud Italia', 'Germania', 'Austria', 'Francia', 'UK']
    
    customers = []
    for i in range(1, n + 1):
        reg_date = fake.date_between(start_date=date(2020, 1, 1), end_date=date(2022, 12, 31))
        customers.append({
            "customer_id": i,
            "customer_name": fake.company(),
            "customer_type": random.choice(customer_types),
            "region": random.choice(regions),
            "country": fake.country(),
            "registration_date": reg_date,
            "is_active": random.choice([True, True, True, False])  # 75% attivi
        })
    
    return pd.DataFrame(customers)

df_customers = generate_customers(150)
print(f"  Clienti generati: {len(df_customers)}")


# =============================================================
# PARTE 3: VENDITE SIMULATE
# =============================================================
print("\n[3/3] Generazione vendite simulate (2023-2024)...")

def generate_sales(df_products, df_customers, n_sales=5000):
    """
    Genera transazioni di vendita simulate per il periodo 2023-2024.
    Ogni vendita collega un cliente a un prodotto con quantità e prezzo.
    """
    product_ids = df_products["product_id"].tolist()
    customer_ids = df_customers["customer_id"].tolist()
    
    # Crea un dizionario prezzo per ogni prodotto
    price_map = dict(zip(df_products["product_id"], df_products["unit_price"]))
    
    sales = []
    start_date = date(2023, 1, 1)
    end_date = date(2024, 12, 31)
    delta = (end_date - start_date).days
    
    for i in range(1, n_sales + 1):
        product_id = random.choice(product_ids)
        customer_id = random.choice(customer_ids)
        quantity = random.randint(1, 50)
        unit_price = price_map[product_id]
        
        # Applica uno sconto casuale (0-20%)
        discount_pct = random.choice([0, 0, 0, 5, 10, 15, 20])
        discount_amount = round(unit_price * quantity * discount_pct / 100, 2)
        total_amount = round(unit_price * quantity - discount_amount, 2)
        
        sale_date = start_date + timedelta(days=random.randint(0, delta))
        
        sales.append({
            "sale_id": i,
            "product_id": product_id,
            "customer_id": customer_id,
            "sale_date": sale_date,
            "quantity": quantity,
            "unit_price": unit_price,
            "discount_pct": discount_pct,
            "discount_amount": discount_amount,
            "total_amount": total_amount
        })
    
    return pd.DataFrame(sales)

df_sales = generate_sales(df_products, df_customers, n_sales=5000)
print(f"  Vendite generate: {len(df_sales)}")


# =============================================================
# SALVATAGGIO CSV (backup)
# =============================================================
print("\n Salvataggio file CSV nella cartella data/...")

df_products.to_csv("../data/products.csv", index=False)
df_customers.to_csv("../data/customers.csv", index=False)
df_sales.to_csv("../data/sales.csv", index=False)

print("\n" + "=" * 60)
print("RIEPILOGO DATI GENERATI:")
print(f"  Prodotti:  {len(df_products)}")
print(f"  Clienti:   {len(df_customers)}")
print(f"  Vendite:   {len(df_sales)}")
print("=" * 60)
print("\nProssimo step: eseguire load_to_sqlserver.py per caricare i dati nel database.")

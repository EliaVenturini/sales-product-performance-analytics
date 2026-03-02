-- analysis_queries.sql
-- Progetto: Sales & Product Performance Analytics

use DrScharAnalytics;

-- SEZIONE 1: REVENUE ANALYSIS

-- Q1.1 - Fatturato totale per anno
select
	year(s.sale_date) Anno,
	count(s.sale_id) Numero_ordini,
	sum(s.total_amount) Fatturato_totale,
	avg(s.total_amount) Valore_medio_ordine,
	sum(s.quantity) Unita_vendute
from Sales s
group by year(s.sale_date)
order by Anno;


-- Q1.2 - Ranking prodotti per fatturato
-- RANK() assegna lo stesso rango a prodotti con fatturato uguale (1,2,2,4).
select
	p.product_name, p.category, p.brand,
	sum(s.total_amount) Fatturato_totale,
	sum(s.quantity) Quantità_vendute,
	rank() over(order by sum(s.total_amount) desc) Rank
from Products p
	join Sales s on p.product_id = s.product_id
group by p.product_name, p.category, p.brand;


-- Q1.3 - Top 10 prodotti con percentuale sul totale
-- SUM() OVER () senza PARTITION BY restituisce il totale generale,
-- usato come denominatore per la percentuale senza subquery separata.
select top 10
	p.product_name,
	p.category,
	sum(s.total_amount) Fatturato_prodotto,
	round(
		sum(s.total_amount) * 100.0 /
		sum(sum(s.total_amount)) over()
	, 2) Perc_sul_totale
from Sales s
	join Products p on s.product_id = p.product_id
group by p.product_name, p.category
order by Fatturato_prodotto desc;


-- SEZIONE 2: TIME INTELLIGENCE

-- Q2.1 - Fatturato mensile con confronto mese precedente
-- LAG() accede al valore del mese precedente senza self-join.
-- NULLIF al denominatore evita la divisione per zero.
with monthly_revenue as (
	select
		c.year Anno,
		c.month Mese,
		c.month_name Nome_mese,
		sum(s.total_amount) Fatturato_mensile
	from Sales s
		join Calendar c on s.sale_date = c.full_date
	group by c.year, c.month, c.month_name
)
select
	Anno,
	Mese,
	Nome_mese,
	Fatturato_mensile,
	lag(Fatturato_mensile, 1) over(order by Anno, Mese) Fatturato_mese_precedente,
	round(
		(Fatturato_mensile - lag(Fatturato_mensile, 1) over(order by Anno, Mese))
		* 100.0
		/ nullif(lag(Fatturato_mensile, 1) over(order by Anno, Mese), 0)
	, 2) Variazione_pct_mom
from monthly_revenue
order by Anno, Mese;


-- Q2.2 - Fatturato cumulativo per mese
-- PARTITION BY anno fa ripartire il totale da zero ogni anno.
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW definisce
-- la finestra dalla prima riga fino a quella corrente.
with monthly_revenue as (
	select
		c.year Anno,
		c.month Mese,
		c.month_name Nome_mese,
		sum(s.total_amount) Fatturato_mensile
	from Sales s
		join Calendar c on s.sale_date = c.full_date
	group by c.year, c.month, c.month_name
)
select
	Anno,
	Mese,
	Nome_mese,
	Fatturato_mensile,
	sum(Fatturato_mensile) over(
		partition by Anno
		order by Mese
		rows between unbounded preceding and current row
	) Fatturato_cumulativo_ytd
from monthly_revenue
order by Anno, Mese;


-- Q2.3 - Confronto anno su anno per trimestre
-- Pivot manuale con CASE WHEN: estrae il valore per anno specifico,
-- somma zero per gli altri, poi GROUP BY trimestre collassa tutto.
with quarterly_revenue as (
	select
		c.year Anno,
		c.quarter Trimestre,
		sum(s.total_amount) Fatturato
	from Sales s
		join Calendar c on s.sale_date = c.full_date
	group by c.year, c.quarter
)
select
	Trimestre,
	sum(case when Anno = 2023 then Fatturato else 0 end) Fatturato_2023,
	sum(case when Anno = 2024 then Fatturato else 0 end) Fatturato_2024,
	sum(case when Anno = 2024 then Fatturato else 0 end) -
	sum(case when Anno = 2023 then Fatturato else 0 end) Variazione_assoluta,
	round(
		(sum(case when Anno = 2024 then Fatturato else 0 end) -
		 sum(case when Anno = 2023 then Fatturato else 0 end))
		* 100.0
		/ nullif(sum(case when Anno = 2023 then Fatturato else 0 end), 0)
	, 2) Variazione_pct_yoy
from quarterly_revenue
group by Trimestre
order by Trimestre;

-- SEZIONE 3: PRODUCT PERFORMANCE

-- Q3.1 - Ranking per categoria
-- PARTITION BY category genera un ranking separato per ogni categoria.
select
	p.category,
	p.product_name,
	p.brand,
	count(s.sale_id) Numero_ordini,
	sum(s.total_amount) Fatturato,
	avg(s.discount_pct) Sconto_medio_pct,
	rank() over(
		partition by p.category
		order by sum(s.total_amount) desc
	) Rank_in_categoria
from Sales s
	join Products p on s.product_id = p.product_id
group by p.category, p.product_name, p.brand
order by p.category, Rank_in_categoria;


-- Q3.2 - Organico vs convenzionale
-- LEFT JOIN per includere anche i prodotti senza vendite nel conteggio.
-- CASE WHEN converte il flag is_organic (0/1) in testo leggibile.
select
	case when p.is_organic = 1 then 'Organico' else 'Convenzionale' end Tipo_prodotto,
	count(distinct p.product_id) Numero_prodotti,
	count(s.sale_id) Numero_vendite,
	sum(s.total_amount) Fatturato_totale,
	avg(s.total_amount) Valore_medio_ordine,
	avg(p.unit_price) Prezzo_medio_listino,
	avg(s.discount_pct) Sconto_medio_pct
from Products p
	left join Sales s on p.product_id = s.product_id
group by p.is_organic
order by Fatturato_totale desc;


-- Q3.3 - Prodotti senza vendite
-- LEFT JOIN + WHERE IS NULL per trovare prodotti mai venduti.
select
	p.product_id,
	p.product_name,
	p.brand,
	p.category,
	p.unit_price,
	p.launch_date
from Products p
	left join Sales s on p.product_id = s.product_id
where s.sale_id is null
order by p.category, p.product_name;

-- SEZIONE 4: CUSTOMER SEGMENTATION - RFM

-- Q4.1 - Segmentazione RFM per cliente
-- Due CTE: la prima calcola le metriche grezze, la seconda assegna
-- i punteggi con NTILE(4) che divide i clienti in 4 gruppi uguali.
-- Recency è ordinata ASC perché meno giorni = cliente più recente = meglio.
with rfm_base as (
	select
		c.customer_id,
		c.customer_name,
		c.customer_type,
		c.region,
		datediff(day, max(s.sale_date), '2024-12-31') Recency_giorni,
		count(s.sale_id) Frequency,
		sum(s.total_amount) Monetary
	from Customers c
		join Sales s on c.customer_id = s.customer_id
	group by c.customer_id, c.customer_name, c.customer_type, c.region
),
rfm_scores as (
	select
		customer_id,
		customer_name,
		customer_type,
		region,
		Recency_giorni,
		Frequency,
		Monetary,
		ntile(4) over(order by Recency_giorni asc) R_score,
		ntile(4) over(order by Frequency desc) F_score,
		ntile(4) over(order by Monetary desc) M_score
	from rfm_base
)
select
	customer_id,
	customer_name,
	customer_type,
	region,
	Recency_giorni,
	Frequency,
	round(Monetary, 2) Monetary,
	R_score,
	F_score,
	M_score,
	(R_score + F_score + M_score) Rfm_score_totale,
	case
		when (R_score + F_score + M_score) >= 10 then 'Champions'
		when (R_score + F_score + M_score) >= 8  then 'Loyal Customers'
		when (R_score + F_score + M_score) >= 6  then 'Potential Loyalists'
		when (R_score + F_score + M_score) >= 4  then 'At Risk'
		else                                          'Lost'
	end Segmento_cliente
from rfm_scores
order by Rfm_score_totale desc;


-- Q4.2 - Distribuzione clienti per segmento
with rfm_base as (
	select
		c.customer_id,
		datediff(day, max(s.sale_date), '2024-12-31') Recency_giorni,
		count(s.sale_id) Frequency,
		sum(s.total_amount) Monetary
	from Customers c
		join Sales s on c.customer_id = s.customer_id
	group by c.customer_id
),
rfm_scores as (
	select
		customer_id,
		ntile(4) over(order by Recency_giorni asc) R_score,
		ntile(4) over(order by Frequency desc) F_score,
		ntile(4) over(order by Monetary desc) M_score,
		Monetary
	from rfm_base
),
rfm_segmented as (
	select
		customer_id,
		round(Monetary, 2) Monetary,
		case
			when (R_score + F_score + M_score) >= 10 then 'Champions'
			when (R_score + F_score + M_score) >= 8  then 'Loyal Customers'
			when (R_score + F_score + M_score) >= 6  then 'Potential Loyalists'
			when (R_score + F_score + M_score) >= 4  then 'At Risk'
			else                                          'Lost'
		end Segmento_cliente
	from rfm_scores
)
select
	Segmento_cliente,
	count(customer_id) Numero_clienti,
	round(avg(Monetary), 2) Fatturato_medio,
	round(sum(Monetary), 2) Fatturato_totale,
	round(count(customer_id) * 100.0 / sum(count(customer_id)) over(), 1) Perc_clienti
from rfm_segmented
group by Segmento_cliente
order by Fatturato_totale desc;

-- SEZIONE 5: ADVANCED ANALYTICS
-- Q5.1 - Top 3 prodotti per categoria
-- ROW_NUMBER() garantisce esattamente 3 righe per categoria.
-- Con RANK() in caso di parità potrebbero essere di più.
with product_revenue as (
	select
		p.category,
		p.product_name,
		p.brand,
		sum(s.total_amount) Fatturato,
		row_number() over(
			partition by p.category
			order by sum(s.total_amount) desc
		) Rn
	from Sales s
		join Products p on s.product_id = p.product_id
	group by p.category, p.product_name, p.brand
)
select
	category,
	product_name,
	brand,
	round(Fatturato, 2) Fatturato,
	Rn Posizione_in_categoria
from product_revenue
where Rn <= 3
order by category, Rn;


-- Q5.2 - Impatto sconti per regione
-- Fatturato potenziale = effettivo + sconti concessi (listino pieno).
select
	cu.region,
	count(s.sale_id) Numero_ordini,
	round(sum(s.total_amount), 2) Fatturato_effettivo,
	round(sum(s.discount_amount), 2) Totale_sconti_concessi,
	round(sum(s.total_amount) + sum(s.discount_amount), 2) Fatturato_potenziale,
	round(
		sum(s.discount_amount) * 100.0 /
		nullif(sum(s.total_amount) + sum(s.discount_amount), 0)
	, 2) Perc_fatturato_perso,
	round(avg(s.discount_pct), 2) Sconto_medio_pct
from Sales s
	join Customers cu on s.customer_id = cu.customer_id
group by cu.region
order by Fatturato_effettivo desc;


-- Q5.3 - Media mobile a 3 mesi
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW: riga corrente + 2 precedenti.
-- Senza ROWS SQL Server usa RANGE di default, che può dare risultati diversi.
with monthly_revenue as (
	select
		c.year Anno,
		c.month Mese,
		c.month_name Nome_mese,
		sum(s.total_amount) Fatturato_mensile
	from Sales s
		join Calendar c on s.sale_date = c.full_date
	group by c.year, c.month, c.month_name
)
select
	Anno,
	Mese,
	Nome_mese,
	round(Fatturato_mensile, 2) Fatturato_mensile,
	round(
		avg(Fatturato_mensile) over(
			order by Anno, Mese
			rows between 2 preceding and current row
		)
	, 2) Media_mobile_3m
from monthly_revenue
order by Anno, Mese;


-- Q5.4 - KPI sintetici con UNION ALL
-- UNION ALL impila metriche diverse in un unico result set verticale.
select 'Fatturato Totale 2024' Kpi,
	round(sum(s.total_amount), 2) Valore,
	'€' Unita
from Sales s where year(s.sale_date) = 2024

union all

select 'Ordini Totali 2024',
	count(s.sale_id),
	'n.'
from Sales s where year(s.sale_date) = 2024

union all

select 'Clienti Attivi 2024',
	count(distinct s.customer_id),
	'n.'
from Sales s where year(s.sale_date) = 2024

union all

select 'Sconto Medio 2024',
	round(avg(s.discount_pct), 2),
	'%'
from Sales s where year(s.sale_date) = 2024

union all

select 'Prodotti Venduti 2024',
	count(distinct s.product_id),
	'n.'
from Sales s where year(s.sale_date) = 2024;

with ffirst_purchase as (
-- Формируем таблицу с первой покупкой каждого клиента
	select
		client_uuid,
		min(date_trunc('month', trans_date::date)::date) as cohort_month
	from raw_transactions
group by client_uuid
),
-- Собираем жизненный цикл (все покупки клиентов)
client_lifecycle as (
	select
		fp.cohort_month,
		rt.client_uuid,
		rt.trans_date :: date as trans_date,
		nullif(amount,'error'):: numeric as amount,
		(extract(year from rt.trans_date :: date) * 12 + extract(month from rt.trans_date :: date)) -
		(extract(year from fp.cohort_month) * 12 + extract(month from fp.cohort_month)) as month_life
	from raw_transactions rt
	inner join ffirst_purchase fp on fp.client_uuid  = rt.client_uuid 
),
-- Создаём таблицу с агрегированными данными по каждой когорте
cohort_aggregated as (
	select
		cohort_month,
		month_life,
		sum(amount) as total_amount,
		count(distinct(client_uuid)) as number_of_users
	from client_lifecycle
	group by cohort_month, month_life
)
-- Формируем финальную таблицу для когортного анализа добавляя метрики (retention,ltv)
select
	cohort_month,
	month_life,
	total_amount,
	number_of_users,
	round(number_of_users * 100.0 
	/
	first_value(number_of_users) over (partition by cohort_month order by month_life),2
	) as retention,
	round(sum(total_amount) over (partition by cohort_month order by month_life) 
	/
	first_value(number_of_users) over (partition by cohort_month order by month_life),0
	) as ltv
from cohort_aggregated


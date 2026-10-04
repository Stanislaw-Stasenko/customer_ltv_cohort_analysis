-- Формируем таблицу с датой регистрацией
with reg_dt_client as (
	select
		client_uuid,
		min(reg_date::date) as data_reg
	from public.raw_clients
	where reg_date is not null -- отсекаем клиентов без даты регистрации
	group by client_uuid -- группируем по ID клиента для того чтобы вытащить первую дату регистрации
),
-- Добавляем дату каждой покупки и сумму покупки по каждому клиенту
client_transactions as (
	select
		r.client_uuid,
		r.data_reg,
		rt.trans_date::date as trans_date,
		nullif(amount, 'error')::numeric as amount
		from reg_dt_client r
		left join public.raw_transactions rt on r.client_uuid = rt.client_uuid
),
-- Формируем таблицу "жизненного цикла"
client_lifecycle as (
	select
		client_uuid,
		date_trunc('month',data_reg):: date as cohort_month, -- Определяем когорту каждого клиента
		coalesce(
		(extract(year from trans_date)*12 + extract(month from trans_date)) -
		(extract(year from data_reg)*12 + extract(month from data_reg)),
		0) as month_life, -- Определяем жизненный цикл
		amount
	from client_transactions
),
-- Создаём таблицу с агрегированными данными по каждой когорте
cohort_aggregated as (
	select
		cohort_month,
		month_life,
		sum(amount) as total_amount,
		count(distinct(client_uuid)) as number_of_users
		from client_lifecycle
		group by cohort_month,month_life
 )
 -- Формируем финальную таблицу для когортного анализа добавляя метрики (retention,ltv)
select
	cohort_month,
	month_life,
	total_amount,
	number_of_users,
	round(number_of_users * 100.0 / first_value(number_of_users) over (partition by cohort_month order by month_life asc),2) as retention,
	round(sum(total_amount) over (partition by cohort_month order by month_life asc) / first_value(number_of_users) over (partition by cohort_month order by month_life asc),0) as ltv
from cohort_aggregated
order by cohort_month


from sqlalchemy import create_engine,text
from dotenv import load_dotenv
import os

load_dotenv()
db_url = os.getenv("DATABASE_URL_SB")
engine = create_engine(db_url)


def load_dim_users(engine):
    with engine.begin() as conn:
        qwery = """truncate table dwh.dim_users"""
        conn.execute(text(qwery))

        qwery = """
        insert into dwh.dim_users (client_uuid,cohort_month)
            select
            client_uuid::uuid,
            min(date_trunc('month',trans_date :: date))::date as cohort_month
            from raw.raw_transactions
            group by client_uuid
        """
        conn.execute(text(qwery))

def load_dim_products(engine):
    with engine.begin() as conn:
        qwery = """truncate table dwh.dim_products"""
        conn.execute(text(qwery))

        qwery = """
        insert into dwh.dim_products (product_name)
            select
            string_to_table(product_list,',') as product
            from raw.raw_transactions
            group by string_to_table(product_list,',')
        """
        conn.execute(text(qwery))


def load_order_items(engine):
    with engine.begin() as conn:
        qwery = """truncate table dwh.f_order_items"""
        conn.execute(text(qwery))

        qwery = """
        insert into dwh.f_order_items (order_id,user_id,product_id,transaction_type_id,allocated_amount,trans_date,promo_code,channel)
        with parsed_products as (
            select
                dense_rank() over (order by client_uuid, trans_date) as order_id,
                client_uuid::uuid,
                trans_date::timestamp as trans_date,
                nullif(amount,'error')::numeric as amount,
                string_to_table(product_list,',') as product,
                promo_code,
                channel
            from raw.raw_transactions
        ),
        prepared_transactions as (
            select
                order_id,
                client_uuid,
                trans_date,
                amount / count(*) over (partition by order_id) as allocated_amount,
                product,
                promo_code,
                channel
            from parsed_products	
        ) 
            select
            pt.order_id,
            du.user_id,
            di.product_id,
            case when allocated_amount < 0 then 2 else 1 end as transaction_type_id,
            pt.allocated_amount,
            pt.trans_date,
            pt.promo_code,
            pt.channel
        from prepared_transactions pt
        inner join dwh.dim_users du on du.client_uuid = pt.client_uuid
        inner join dwh.dim_products di on di.product_name = pt.product
        """
        conn.execute(text(qwery))

def load_sessions(engine):
    with engine.begin() as conn:
        qwery = """truncate table dwh.f_sessions"""
        conn.execute(text(qwery))

        qwery = """
        insert into dwh.f_sessions (user_id,session_start,session_length,pages_viewed,cart_added)
        select
            du.user_id,
            rs.session_start::timestamp,
            extract(epoch from (session_end::timestamp - session_start::timestamp)) as session_length,
            coalesce(rs.pages_viewed::integer,0),
            coalesce(rs.cart_added::integer,0)
        from raw.raw_sessions rs
        inner join 	dwh.dim_users du on du.client_uuid = rs.client_uuid::uuid
        """
        conn.execute(text(qwery))


if __name__ == "__main__":
    print("Запуск ETL пайплайна...")
    load_dim_users(engine)
    print("✅ Справочник пользователей обновлен.")
    load_dim_products(engine)
    print("✅ Справочник продуктов обновлен.")
    load_sessions(engine)
    print("✅ Справочник сессий обновлен.")
    load_order_items(engine)
    print("✅ Справочник транзакций обновлен.")

    print("✅ DWH полностью обновлено!")

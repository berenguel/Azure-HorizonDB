-- Seed the storefront. Scale is controlled by psql variables, e.g.:
--   psql ... -v customers=50000 -v products=1000 -v orders=500000 -f sql/seed.sql
-- Defaults below apply if a variable isn't passed.

\set ON_ERROR_STOP on
\if :{?customers} \else \set customers 50000 \endif
\if :{?products}  \else \set products  1000  \endif
\if :{?orders}    \else \set orders    500000 \endif

\echo Seeding customers= :customers products= :products orders= :orders

-- Products
INSERT INTO products (sku, name, category, unit_price)
SELECT
    'SKU-' || lpad(g::text, 6, '0'),
    (ARRAY['Aurora','Comet','Nimbus','Vertex','Quartz','Solace','Drift','Ember','Halcyon','Onyx'])[1 + (g % 10)]
        || ' ' ||
    (ARRAY['Mug','Lamp','Chair','Bottle','Notebook','Backpack','Speaker','Mat','Bowl','Clock'])[1 + ((g/10) % 10)],
    (ARRAY['Home','Outdoor','Office','Kitchen','Audio'])[1 + (g % 5)],
    round((random() * 180 + 5)::numeric, 2)
FROM generate_series(1, :products) AS g;

-- Customers
INSERT INTO customers (full_name, email, country, created_at)
SELECT
    'Customer ' || g,
    'customer' || g || '@example.com',
    (ARRAY['US','UK','Brazil','Germany','India','Japan','Canada','Australia'])[1 + (g % 8)],
    now() - ((random() * 730)::int || ' days')::interval
FROM generate_series(1, :customers) AS g;

-- Orders (last 365 days)
INSERT INTO orders (customer_id, order_ts, status)
SELECT
    1 + floor(random() * :customers)::int,
    now() - ((random() * 365)::int || ' days')::interval - (random() * interval '24 hours'),
    (ARRAY['paid','shipped','delivered','refunded','cancelled'])[1 + floor(random() * 5)::int]
FROM generate_series(1, :orders) AS g;

-- Order items (1-4 per order), priced from the product catalog.
-- NOTE: the per-order item count is derived deterministically from order_id
-- ( 1 + order_id % 4 ) rather than from random() inside generate_series().
-- A random() bound here collapsed to exactly one item per order on HorizonDB
-- (the engine folded the volatile argument), so we keep the COUNT deterministic
-- and use random() only for product/quantity selection, which expands reliably
-- on both stock PostgreSQL and HorizonDB.
INSERT INTO order_items (order_id, product_id, quantity, line_price)
SELECT t.order_id, t.product_id, t.quantity, t.quantity * pr.unit_price
FROM (
    SELECT o.order_id,
           1 + floor(random() * :products)::int AS product_id,
           1 + floor(random() * 5)::int          AS quantity
    FROM orders o
    CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 4)) AS gs
) t
JOIN products pr ON pr.product_id = t.product_id;

ANALYZE;

\echo Row counts:
SELECT 'customers' AS table, count(*) FROM customers
UNION ALL SELECT 'products', count(*) FROM products
UNION ALL SELECT 'orders', count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items;

\echo Items-per-order distribution (should span 1-4, not collapse to 1):
SELECT items, count(*) AS orders_with_this_many
FROM (SELECT order_id, count(*) AS items FROM order_items GROUP BY order_id) s
GROUP BY items ORDER BY items;

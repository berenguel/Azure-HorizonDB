-- Read-heavy analytics. Run these against the READER endpoint to show read scale-out.

\timing on

\echo == Top 10 products by revenue ==
SELECT p.name, p.category,
       sum(oi.line_price)  AS revenue,
       sum(oi.quantity)    AS units
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.name, p.category
ORDER BY revenue DESC
LIMIT 10;

\echo == Daily revenue, last 30 days ==
SELECT date_trunc('day', o.order_ts)::date AS day,
       count(DISTINCT o.order_id)          AS orders,
       sum(oi.line_price)                  AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_ts >= now() - interval '30 days'
GROUP BY day
ORDER BY day;

\echo == Revenue by country ==
SELECT c.country,
       count(DISTINCT o.order_id) AS orders,
       sum(oi.line_price)         AS revenue
FROM customers c
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id  = o.order_id
GROUP BY c.country
ORDER BY revenue DESC;

\echo == Which server am I connected to? ==
SELECT inet_server_addr() AS server_ip, pg_is_in_recovery() AS is_replica, now();

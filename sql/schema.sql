-- Horizon Goods: a synthetic storefront used for the intro demo.
-- Small, self-contained, no external downloads. Generated entirely in-database.

DROP TABLE IF EXISTS order_items, orders, products, customers CASCADE;

CREATE TABLE customers (
    customer_id  serial PRIMARY KEY,
    full_name    text NOT NULL,
    email        text NOT NULL,
    country      text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE products (
    product_id   serial PRIMARY KEY,
    sku          text NOT NULL,
    name         text NOT NULL,
    category     text NOT NULL,
    unit_price   numeric(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id     bigserial PRIMARY KEY,
    customer_id  int NOT NULL REFERENCES customers(customer_id),
    order_ts     timestamptz NOT NULL,
    status       text NOT NULL
);

CREATE TABLE order_items (
    order_item_id bigserial PRIMARY KEY,
    order_id      bigint NOT NULL REFERENCES orders(order_id),
    product_id    int NOT NULL REFERENCES products(product_id),
    quantity      int NOT NULL,
    line_price    numeric(12,2) NOT NULL
);

CREATE INDEX idx_orders_ts        ON orders (order_ts);
CREATE INDEX idx_orders_customer  ON orders (customer_id);
CREATE INDEX idx_items_order      ON order_items (order_id);
CREATE INDEX idx_items_product    ON order_items (product_id);

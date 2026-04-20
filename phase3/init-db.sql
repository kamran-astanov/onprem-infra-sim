CREATE TABLE IF NOT EXISTS orders (
    id          SERIAL PRIMARY KEY,
    customer    VARCHAR(100) NOT NULL,
    product     VARCHAR(100) NOT NULL,
    quantity    INT NOT NULL,
    status      VARCHAR(50) DEFAULT 'PENDING',
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS outbox (
    id          SERIAL PRIMARY KEY,
    topic       VARCHAR(100) NOT NULL,
    payload     TEXT NOT NULL,
    published   BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP DEFAULT NOW()
);

INSERT INTO orders (customer, product, quantity, status) VALUES
    ('Alice', 'Laptop', 1, 'PENDING'),
    ('Bob',   'Phone',  2, 'SHIPPED');

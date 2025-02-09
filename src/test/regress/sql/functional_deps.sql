-- from http://www.depesz.com/index.php/2010/04/19/getting-unique-elements/

CREATE TEMP TABLE articles (
    id int CONSTRAINT articles_pkey PRIMARY KEY,
    keywords text,
    -- GPDB doesn't support having a PRIMARY KEY and UNIQUE constraints on the
    -- same table. Hence leave out the UNIQUE constraints.
    title text /* UNIQUE */ NOT NULL,
    body text /* UNIQUE */,
    created date
);

CREATE TEMP TABLE articles_in_category (
    article_id int,
    category_id int,
    changed date,
    PRIMARY KEY (article_id, category_id)
);

-- test functional dependencies based on primary keys/unique constraints

-- base tables

-- group by primary key (OK)
SELECT id, keywords, title, body, created
FROM articles
GROUP BY id;

-- group by unique not null (fail/todo)
SELECT id, keywords, title, body, created
FROM articles
GROUP BY title;

-- group by unique nullable (fail)
SELECT id, keywords, title, body, created
FROM articles
GROUP BY body;

-- group by something else (fail)
SELECT id, keywords, title, body, created
FROM articles
GROUP BY keywords;

-- multiple tables

-- group by primary key (OK)
SELECT a.id, a.keywords, a.title, a.body, a.created
FROM articles AS a, articles_in_category AS aic
WHERE a.id = aic.article_id AND aic.category_id in (14,62,70,53,138)
GROUP BY a.id;

-- group by something else (fail)
SELECT a.id, a.keywords, a.title, a.body, a.created
FROM articles AS a, articles_in_category AS aic
WHERE a.id = aic.article_id AND aic.category_id in (14,62,70,53,138)
GROUP BY aic.article_id, aic.category_id;

-- JOIN syntax

-- group by left table's primary key (OK)
SELECT a.id, a.keywords, a.title, a.body, a.created
FROM articles AS a JOIN articles_in_category AS aic ON a.id = aic.article_id
WHERE aic.category_id in (14,62,70,53,138)
GROUP BY a.id;

-- group by something else (fail)
SELECT a.id, a.keywords, a.title, a.body, a.created
FROM articles AS a JOIN articles_in_category AS aic ON a.id = aic.article_id
WHERE aic.category_id in (14,62,70,53,138)
GROUP BY aic.article_id, aic.category_id;

-- group by right table's (composite) primary key (OK)
SELECT aic.changed
FROM articles AS a JOIN articles_in_category AS aic ON a.id = aic.article_id
WHERE aic.category_id in (14,62,70,53,138)
GROUP BY aic.category_id, aic.article_id;

-- group by right table's partial primary key (fail)
SELECT aic.changed
FROM articles AS a JOIN articles_in_category AS aic ON a.id = aic.article_id
WHERE aic.category_id in (14,62,70,53,138)
GROUP BY aic.article_id;


-- example from documentation

CREATE TEMP TABLE products (product_id int, name text, price numeric);
CREATE TEMP TABLE sales (product_id int, units int);

-- OK
SELECT product_id, p.name, (sum(s.units) * p.price) AS sales
    FROM products p LEFT JOIN sales s USING (product_id)
    GROUP BY product_id, p.name, p.price;

-- fail
SELECT product_id, p.name, (sum(s.units) * p.price) AS sales
    FROM products p LEFT JOIN sales s USING (product_id)
    GROUP BY product_id;

ALTER TABLE products ADD PRIMARY KEY (product_id);

-- OK now
SELECT product_id, p.name, (sum(s.units) * p.price) AS sales
    FROM products p LEFT JOIN sales s USING (product_id)
    GROUP BY product_id;

-- OK, test GPDB case
set enable_groupagg = off;
set gp_eager_two_phase_agg = on;
SELECT count(distinct name), price FROM products GROUP BY product_id;

create table funcdep1(a int primary key, b int, c int, d int);
create table funcdep2(a int, b int, c int, d int);

insert into funcdep1 values(1,1,1,1);
insert into funcdep1 values(2,1,1,1);
insert into funcdep1 values(3,1,1,1);
insert into funcdep2 values(1,1,1,1);

explain (costs off) select sum(t2.a), t1.a, t1.b, t1.c from funcdep1 t1 join funcdep2 t2 on t1.b = t2.b group by t1.a;
select sum(t2.a), t1.a, t1.b, t1.c from funcdep1 t1 join funcdep2 t2 on t1.b = t2.b group by t1.a;

explain (costs off) select sum(b), c, d, grouping(a) from funcdep1 group by grouping sets((a), ());
select sum(b), c, d, grouping(a) from funcdep1 group by grouping sets((a), ());
explain (costs off) select sum(b), c, d, grouping(a) from funcdep1 group by rollup(a);
select sum(b), c, d, grouping(a) from funcdep1 group by rollup(a);
explain (costs off) select sum(b), c, d, grouping(a) from funcdep1 group by cube(a);
select sum(b), c, d, grouping(a) from funcdep1 group by cube(a);

explain (costs off) select count(distinct b), c, d from funcdep1 group by a;
select count(distinct b), c, d from funcdep1 group by a;
explain (costs off) select count(distinct b), sum(b), c from funcdep1 group by a;
select count(distinct b), sum(b), c from funcdep1 group by a;
explain (costs off) select count(distinct b), count(distinct c) from funcdep1 group by a;
select count(distinct b), count(distinct c) from funcdep1 group by a;

reset enable_groupagg;
reset gp_eager_two_phase_agg;
drop table funcdep1;
drop table funcdep2;

-- Drupal example, http://drupal.org/node/555530

CREATE TEMP TABLE node (
    nid SERIAL,
    vid integer NOT NULL default '0',
    type varchar(32) NOT NULL default '',
    title varchar(128) NOT NULL default '',
    uid integer NOT NULL default '0',
    status integer NOT NULL default '1',
    created integer NOT NULL default '0',
    -- snip
    PRIMARY KEY (nid, vid)
);

CREATE TEMP TABLE users (
    uid integer NOT NULL default '0',
    name varchar(60) NOT NULL default '',
    pass varchar(32) NOT NULL default '',
    -- snip
    PRIMARY KEY (uid)
    /* , UNIQUE (name) */
);

-- OK
SELECT u.uid, u.name FROM node n
INNER JOIN users u ON u.uid = n.uid
WHERE n.type = 'blog' AND n.status = 1
GROUP BY u.uid, u.name;

-- OK
SELECT u.uid, u.name FROM node n
INNER JOIN users u ON u.uid = n.uid
WHERE n.type = 'blog' AND n.status = 1
GROUP BY u.uid;


-- Check views and dependencies

-- fail
CREATE TEMP VIEW fdv1 AS
SELECT id, keywords, title, body, created
FROM articles
GROUP BY body;

-- OK
CREATE TEMP VIEW fdv1 AS
SELECT id, keywords, title, body, created
FROM articles
GROUP BY id;

-- fail
ALTER TABLE articles DROP CONSTRAINT articles_pkey RESTRICT;

DROP VIEW fdv1;


-- multiple dependencies
CREATE TEMP VIEW fdv2 AS
SELECT a.id, a.keywords, a.title, aic.category_id, aic.changed
FROM articles AS a JOIN articles_in_category AS aic ON a.id = aic.article_id
WHERE aic.category_id in (14,62,70,53,138)
GROUP BY a.id, aic.category_id, aic.article_id;

ALTER TABLE articles DROP CONSTRAINT articles_pkey RESTRICT; -- fail
ALTER TABLE articles_in_category DROP CONSTRAINT articles_in_category_pkey RESTRICT; --fail

DROP VIEW fdv2;


-- nested queries

CREATE TEMP VIEW fdv3 AS
SELECT id, keywords, title, body, created
FROM articles
GROUP BY id
UNION
SELECT id, keywords, title, body, created
FROM articles
GROUP BY id;

ALTER TABLE articles DROP CONSTRAINT articles_pkey RESTRICT; -- fail

DROP VIEW fdv3;


CREATE TEMP VIEW fdv4 AS
SELECT * FROM articles WHERE title IN (SELECT title FROM articles GROUP BY id);

ALTER TABLE articles DROP CONSTRAINT articles_pkey RESTRICT; -- fail

DROP VIEW fdv4;


-- prepared query plans: this results in failure on reuse

PREPARE foo AS
  SELECT id, keywords, title, body, created
  FROM articles
  GROUP BY id;

EXECUTE foo;

ALTER TABLE articles DROP CONSTRAINT articles_pkey RESTRICT;

EXECUTE foo;  -- fail

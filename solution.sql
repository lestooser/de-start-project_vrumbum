-- Этап 1. Создание и заполнение БД

create schema if not exists raw_data;

create table if not exists raw_data.sales (
	id int primary key,
	auto text not null,
	gasoline_consumption numeric(3,1),
	price numeric (9,2),
	date date,
	person text not null,
	phone text not null,
	discount int2,
	brand_origin text
);

-- выполняется не тут, а в psql (SQL SHELL)
\copy raw_data.sales from 'D:\python\Dev\cars.csv' with csv HEADER NULL 'null';

--------------------------------------------------------
create schema if not exists car_shop;
create table if not exists car_shop.brands(
	brand_id serial primary key,
	name text not null unique,
	brand_origin text
);

insert into car_shop.brands (name, brand_origin)
select distinct
	split_part(s.auto, ' ', 1),
	s.brand_origin
from raw_data.sales s
on conflict (name) do nothing;


create table if not exists car_shop.models (
	model_id serial primary key,
	brand_id int references car_shop.brands,
	name text not null,
	gasoline_consumption numeric (3,1),
	unique (brand_id, name)
);
insert into car_shop.models (brand_id, name, gasoline_consumption)
select distinct
	b.brand_id
	, rtrim(substring(split_part(s.auto, ',', 1), position (' ' in s.auto)), ' ')
	, s.gasoline_consumption
from raw_data.sales s
join car_shop.brands b on b.name = split_part(s.auto, ' ', 1)
on conflict (brand_id, name) do nothing;


create table if not exists car_shop.colors (
	color_id serial primary key,
	name text not null unique
);
insert into car_shop.colors (name)
select distinct
	ltrim(split_part(s.auto, ',', 2), ' ')
from raw_data.sales s
on conflict (name) do nothing;

create table if not exists car_shop.model_with_colors (
	model_color_id serial primary key,
	model_id int references car_shop.models,
	color_id int references car_shop.colors,
	unique (model_id, color_id)
);
insert into car_shop.model_with_colors (model_id, color_id)
select
	m.model_id
	, c.color_id
from raw_data.sales s
join car_shop.brands b on b.name = split_part(s.auto, ' ', 1)
join car_shop.models m on
	m.brand_id = b.brand_id
	and m.name = rtrim(substring(split_part(s.auto, ',', 1), position (' ' in s.auto)), ' ')
join car_shop.colors c on c.name = ltrim(split_part(s.auto, ',', 2), ' ')
on conflict (model_id, color_id) do nothing;

create table if not exists car_shop.buyers (
	buyer_id serial primary key,
	name text not null,
	phone text not null,
	unique (name, phone)
);
insert into car_shop.buyers (name, phone)
select distinct
	person, phone
from raw_data.sales s
on conflict (name, phone) do nothing;

create table if not exists car_shop.sales (
	id serial primary key,
	model_color_id int references car_shop.model_with_colors,
	buyer_id int references car_shop.buyers,
	price numeric (9,2) not null,
	discount int2 default 0,
	purchase_date date default current_date
);
insert into car_shop.sales (model_color_id, buyer_id, price, discount, purchase_date)
select
	mwc.model_color_id,
	b2.buyer_id,
	s.price,
	s.discount,
	s.date
from raw_data.sales s
join car_shop.brands b on b.name = split_part(s.auto, ' ', 1)
join car_shop.models m on
	m.brand_id = b.brand_id
	and m.name = rtrim(substring(split_part(s.auto, ',', 1), position (' ' in s.auto)), ' ')
join car_shop.colors c on c.name = ltrim(split_part(s.auto, ',', 2), ' ')
join car_shop.model_with_colors mwc on
	mwc.model_id = m.model_id
	and mwc.color_id = c.color_id
join car_shop.buyers b2 on
	b2.name = s.person
	and s.phone = b2.phone;

-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.

select
	(1-count(gasoline_consumption)/count(*)::decimal)*100  nulls_percentage_gasoline_consumption
from car_shop.models m ;

---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.

select
	b.name brand_name,
	date_part ('year', s.purchase_date) as year,
	round(avg(price),2)
from car_shop.sales s
join car_shop.model_with_colors mwc using (model_color_id)
join car_shop.models m using (model_id)
join car_shop.brands b using (brand_id)
group by brand_name, year
order by brand_name, year;

---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.

select
	date_part ('month', s.purchase_date) as month,
	date_part ('year', s.purchase_date) as year,
	round(avg(price),2)
from car_shop.sales s
where date_part ('year', s.purchase_date) = 2022
group by month, year
order by month, year;


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.

select
	b."name" person,
	STRING_AGG(t.auto, ', ') as cars
from (
	select
		s.buyer_id,
		(b2."name" || ' ' || m."name") auto
	from car_shop.sales s
	join car_shop.model_with_colors mwc using (model_color_id)
	join car_shop.models m using (model_id)
	join car_shop.brands b2 using (brand_id)
	) as t
join car_shop.buyers b using (buyer_id)
group by person;

---- Задание 5. Напишите запрос, который покажет количество всех пользователей из США.

select
	b.brand_origin,
	max(s.price_without_discount) price_max,
	min(s.price_without_discount ) price_min
from (
	select
		s.model_color_id,
		case
		when s.discount > 0 then round((s.price*100) / (100-s.discount),2)
		else s.price
		end price_without_discount
	from car_shop.sales s
		) s
join car_shop.model_with_colors mwc using (model_color_id)
join car_shop.models m using (model_id)
join car_shop.brands b using (brand_id)
group by b.brand_origin
order by b.brand_origin;


---- Задание 6. Напишите запрос, который покажет количество всех пользователей из США. Это пользователи, у которых номер телефона начинается на +1.
select
	count(b.name) persons_from_usa_count
from car_shop.buyers b
where substr(b.phone, 1, 2) = '+1';

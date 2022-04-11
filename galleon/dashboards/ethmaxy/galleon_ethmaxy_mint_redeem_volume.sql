--https://dune.xyz/queries/575623/1077460
with
issuance as (
select * 
from dune_user_generated.galleon_issuance_daily
)

, pricefeed as (
select date_trunc('day',hour) as day, product, avg(usd_price) as usd_price, avg(eth_price) as eth_price
from  dune_user_generated.galleon_ethmaxy_pricefeed 
group by 1,2
)

select 
i.day,
issued_amount,
- redeemed_amount as redeemed_amount,
net_amount,
gross_amount,
usd_price * issued_amount as issue_amount_usd,
- usd_price * redeemed_amount as redeemed_amount_usd,
usd_price * net_amount as net_amount_usd,
usd_price * gross_amount as gross_amount_usd,
supply
usd_price , eth_price,
avg(- redeemed_amount + issued_amount) over (order by i.day rows between 7 preceding and current row) as av,
avg((- redeemed_amount + issued_amount) * usd_price) over (order by i.day rows between 7 preceding and current row) as av_usd
from issuance i
inner join pricefeed p on i.day = p.day

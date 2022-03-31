-- for the purposes of TVL, I am pricing aSTETH and wETH to both be 1 ETH


with daily_supply as (
  select day
    , supply
  from dune_user_generated.set_protocol_daily_unit_supply 
  where set_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
)
, positions as (
  select day
    , sum(real_units_per_set_token) as position_in_eth -- only works because we assume all prices to be 1 ETH
  from dune_user_generated.set_protocol_daily_positions
  where set_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
  group by 1
)
, daily_eth_price_usd as (
  select minute::date as date
    , avg(price) as eth_price
  from prices.layer1_usd p
  where p.minute >= '2022-03-01' -- first day in positions
  and symbol = 'ETH'
  group by 1
)
select ds.day
  , ds.supply
  , p.position_in_eth
  , dep.eth_price
  , ds.supply * p.position_in_eth * dep.eth_price as tvl_usd
from daily_supply ds
inner join positions p on ds.day = p.day
inner join daily_eth_price_usd dep on ds.day = dep.date
order by ds.day desc
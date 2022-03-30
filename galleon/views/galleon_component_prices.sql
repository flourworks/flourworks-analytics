-- ETHMAXY address: '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'

create view dune_user_generated.galleon_component_prices as 
with initial_components as (
  -- Get the initial components from the create function
  select output_0 as set_address
    , unnest(_components) as component_address
    , unnest(_units) as unit
    , call_block_time as timestamp
    , call_block_time::date as day
  from setprotocol_v2."SetTokenCreator_call_create"
  where output_0 = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
)
, all_components as (
  select distinct component_address
  from initial_components
  union
  select distinct _component as component_address
  from setprotocol_v2."SetToken_evt_ComponentAdded"
  where contract_address = '\x0FE20E0Fa9C78278702B05c333Cc000034bb69E2'
)
, daily_component_prices_usd as (
  select p.contract_address
    , p.symbol
    , p.minute::date as date
    , avg(price) as avg_price_usd
  from all_components ac
  inner join prices.usd p on ac.component_address = p.contract_address
  where p.minute >= '2022-03-6'::date -- ETHMAXY contract deployed
  group by 1,2,3
)
, daily_eth_price_usd as (
  select minute::date as date
    , avg(price) as eth_price
  from prices.layer1_usd p
  where p.minute >= '2022-03-6'::date -- ETHMAXY contract deployed
  group by 1
)
, paprika_price_feed as (
  select p.contract_address
    , p.symbol
    , p.date
    , 'prices.usd' as data_source
    , p.avg_price_usd
    , e.eth_price
    , p.avg_price_usd / e.eth_price as avg_price_eth
  from daily_component_prices_usd p
  inner join daily_eth_price_usd e on p.date = e.date
)
select * from paprika_price_feed
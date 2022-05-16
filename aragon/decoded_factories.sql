-- Ethereum: https://dune.xyz/queries/545830
-- Optimism: 

with initial_factories as (
    select unnest(_factories) as _factory
    from setprotocol_v2."Controller_call_initialize"
)
, factories_added as (
    select _factory
    from setprotocol_v2."Controller_evt_FactoryAdded"
),
controller_factories as (
    select _factory from initial_factories
    union
    select _factory from factories_added
)

select f._factory as factory
    , coalesce(e.namespace, 'NOT DECODED') as namespace
    , coalesce(e.name, 'NOT DECODED') as name
from controller_factories f
left join ethereum.contracts e
    on f._factory = e.address
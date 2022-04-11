-- https://dune.xyz/queries/575381
CREATE TABLE if not exists dune_user_generated.galleon_tokens
    (
      symbol varchar,        
      name varchar,                               
      index_type varchar,             
      issuance_model varchar, 
      issuance_chain varchar, 
      token_address bytea
      )
;

truncate table dune_user_generated.galleon_tokens;

insert into dune_user_generated.galleon_tokens 
(symbol,        name,                               index_type,             issuance_model,    issuance_chain,              token_address                          ) values
('ETHMAXY',       'ETH Max Yield Index',            'Leverage',                 'Debt',         'Ethereum',     '\x0fe20e0fa9c78278702b05c333cc000034bb69e2'::bytea)
;

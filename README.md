## Jump Consistent Hash for luajit (Modified for Apache Traffic Server)
A simple implementation of [this paper](http://arxiv.org/pdf/1406.2294.pdf).  
Based on code from [ruoshan/lua-resty-jump-consistent-hash](https://github.com/ruoshan/lua-resty-jump-consistent-hash).  
Made to work in Apache Traffic Server by replacing nginx crc32 dependency with [luapower/crc32](https://github.com/luapower/crc32).  

## Features
- small memory footprint and fast
- consistence is maintained through servers' updating

## Installation
```
git clone https://github.com/guzzijason/lua-trafficserver-jump-consistent-hash.git
cd lua-trafficserver-jump-consistent-hash/
git submodule init
git submodule update
make
make PREFIX=/opt/trafficserver install
```

## Usage

**you can use the basic jchash module to do consistent-hash**
```
local jchash = require "chash.jchash"

local buckets = 8
local id = jchash.hash_short_str("random key", buckets)
```

**or you can use the wrapping module `chash.server` to consistent-hash a list of servers**  
**(Apache Traffic Server example)**
```
ts.add_package_cpath('/opt/trafficserver/lualib/?.so')
ts.add_package_path('/opt/trafficserver/lualib/?.lua')

local jchash_server = require "chash.server"

-- Define 2 origin servers, split traffic 10%/90% for A/B testing
-- {addr, port, weight} weight can be left out if it's 1
local my_servers = {
    { "origin1.example.com", 80, 90},
    { "origin2.example.com", 80, 10}
}

function do_remap()
    local cs, err = jchash_server.new(my_servers)
    local ip, port, family = ts.client_request.client_addr.get_addr()
    local svr = cs:lookup(ip)
    local origin = svr[1]
    ts.client_request.set_url_host(origin)
    return TS_LUA_REMAP_DID_REMAP
end

```

## Further examples

```
...

-- you can even update the servers list, and still maintain the consistence, eg.
local my_new_servers = {
    { "origin1.example.com", 80 },
    { "origin2.example.com", 80 },
    { "origin3.examaple.com", 80 }
}
cs:update_servers(my_new_servers)
svr = cs:lookup(ip)   -- if the server was origin2, then it stays the same,
                       -- as we only update origin3.

-- what's more, consistence is maintained even the number of servers changes! eg.
local my_less_servers = {
    { "origin1.example.com", 80 },
    { "origin3.example.com", 80 }
}
cs:update_servers(my_less_servers)
svr = cs:lookup(ip)   -- if the server was origin1, then it stays the same,
                       -- if the server was origin2, then it has 50% chance to be
                       -- origin1 or origin3

cs:update_servers(my_new_servers)
svr = cs:lookup(ip)   -- if the server was origin1, then it has 66% chance to stay the same

```

## Todo
- better crc32? Original relied on nginx libraries

## Test

```
make test
```

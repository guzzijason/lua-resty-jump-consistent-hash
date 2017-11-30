local jchash = require "chash.jchash"

local ok, new_table = pcall(require, "table.new")
if not ok then
    new_table = function (narr, nrec) return {} end
end

local function stname(string)
    -- @string: {string, weight}
    return string.format("%s#%s", tostring(string[1]), tostring(string[2]))
end

local function init_name2index(strings)
    -- map string name to index
    local map = {}
    for index, s in ipairs(strings) do
        -- name is just the concat of string and inner id
        map[ stname(s) ] = index
    end
    return map
end

local function expand_strings(strings)  --> list<{str, id}>, err
    -- expand strings list of {str, weight} into a list of {str, id}
    local total_weight = 0
    for _, s in ipairs(strings) do
        local weight = s[2] or 1
        if weight < 1 then
            return nil, "invalid weight found"
        end
        total_weight = total_weight + weight
    end

    local expanded_strings = new_table(total_weight, 0)
    for _, s in ipairs(strings) do
        local addr = s[1]
        if type(addr) ~= "string" then
            return nil, "invalid type of addr"
        end
        local weight = s[2] or 1
        for id = 1, weight do
            expanded_strings[#expanded_strings + 1] = {addr, id}
        end
    end
    if #expanded_strings ~= total_weight then
        return nil, "expanded strings' size mismatch"
    end
    return expanded_strings, nil
end

local function update_name2index(old_strings, new_strings)  --> dict[stname]:idx
    -- new strings may have some strings of the same name in the old ones.
    -- we could assign the same index(if in range) to the string of same name,
    -- and as to new strings whose name are new will be assigned to indexes that're
    -- not occupied

    local old_name2index = init_name2index(old_strings)
    local new_name2index = init_name2index(new_strings)
    local new_size = #new_strings  -- new_size is also the maxmuim index
    local old_size = #old_strings

    local unused_indexes = {}

    for old_index, old_sv in ipairs(old_strings) do
        if old_index <= new_size then
            local old_sv_name = stname(old_sv)
            if new_name2index[ old_sv_name ] then
                -- restore the old_index
                new_name2index[ old_sv_name ] = old_index
            else
                -- old_index can be recycled
                unused_indexes[#unused_indexes + 1] = old_index
            end
        else
            -- index that exceed maxmium index is of no use, we should mark it nil.
            -- the next next loop (assigning unused_indexes) will make use of this mark
            old_name2index[ stname(old_sv) ] = nil
        end
    end

    for i = old_size + 1, new_size do  -- only loop when old_size < new_size
        unused_indexes[#unused_indexes + 1] = i
    end

    -- assign the unused_indexes to the real new strings
    local index = 1
    for _, new_sv in ipairs(new_strings) do
        local new_sv_name = stname(new_sv)
        if not old_name2index[ new_sv_name ] then
            -- it's a new string, or an old string whose old index is too big
            assert(unused_indexes[index] ~= nil, "invalid index")
            new_name2index[ new_sv_name ] = unused_indexes[index]
            index = index + 1
        end
    end

    return new_name2index
end


local _M = {}
local mt = { __index = _M }

function _M.new(strings)  --> instance/nil, err
    if not strings then
        return nil, "nil strings"
    end

    local expanded_strings, err = expand_strings(strings)
    if err then
        return nil, err
    end
    return setmetatable({strings = expanded_strings}, mt)
end

-- instance methods

function _M.size(self)  --> num
    return #self.strings
end

function _M.lookup(self, key)  --> string/nil
    -- @key: user defined string, eg. uri
    -- @return: {addr, id}
    -- the `id` is a number in [1, weight], to identify string of same addr,
    if #self.strings == 0 or not key then
        return nil
    end
    local index = jchash.hash_str(key, #self.strings)
    return self.strings[index]
end

function _M.update_strings(self, new_strings)  --> ok, err
    -- @new_strings: remove all old strings, and use the new strings
    --               but we would keep the string whose name is not changed
    --               in the same `id` slot, so consistence is maintained.
    if not new_strings then
        return false, "nil strings"
    end
    local old_strings = self.strings
    local new_strings, err = expand_strings(new_strings)
    if err then
        return false, err
    end
    local name2index = update_name2index(old_strings, new_strings)
    self.strings = new_table(#new_strings, 0)

    for _, s in ipairs(new_strings) do
        self.strings[name2index[ stname(s) ]] = s
    end
    return true, nil
end

function _M.dump(self)  --> list<{addr, port, id}>
    -- @return: deepcopy a self.strings
    -- this can be use to save the string list to a file or something
    -- and restore it back some time later. eg. nginx restart/reload
    --
    -- please NOTE: the data being dumped is not the same as the data we
    -- use to do _M.new or _M.update_strings, though it looks the same, the third
    -- field in the {addr, port, id} is an `id`, NOT a `weight`
    local strings = {}
    for index, sv in ipairs(self.strings) do
        strings[index] = {sv[1], sv[2]} -- {addr, id}
    end
    return strings
end

function _M.restore(self, strings)
    if not strings then
        return
    end
    -- restore strings from dump (deepcopy the strings)
    self.strings = {}
    for index, sv in ipairs(strings) do
        self.strings[index] = {sv[1], sv[2]}
    end
end

_M._VERSION = "0.1.4"

return _M

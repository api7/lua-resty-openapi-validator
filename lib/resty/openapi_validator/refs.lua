--- Internal $ref resolution for OpenAPI specs.
-- Resolves all $ref pointers within the same document, replacing them inline.
-- Supports circular references via a schema registry + lazy proxy.

local _M = {}

local type = type
local pairs = pairs
local ipairs = ipairs
local sub = string.sub
local gsub = string.gsub
local find = string.find

--- Resolve a JSON Pointer (RFC 6901) against a root document.
-- @param root table   the root spec
-- @param pointer string  e.g. "/components/schemas/Pet"
-- @return any|nil  resolved value
-- @return string|nil  error
local function resolve_pointer(root, pointer)
    local current = root
    -- split by "/" and unescape ~ sequences
    for token in pointer:gmatch("[^/]+") do
        token = gsub(token, "~1", "/")
        token = gsub(token, "~0", "~")
        if type(current) ~= "table" then
            return nil, "cannot traverse non-table at '" .. token .. "'"
        end
        -- try numeric index (1-based) for arrays
        local num = tonumber(token)
        if num and current[num + 1] ~= nil then
            current = current[num + 1]
        elseif current[token] ~= nil then
            current = current[token]
        else
            return nil, "key not found: '" .. token .. "'"
        end
    end
    return current, nil
end

--- Deep copy a table, handling nested tables.
local function deep_copy(orig, copies)
    copies = copies or {}
    if type(orig) ~= "table" then
        return orig
    end
    if copies[orig] then
        return copies[orig]
    end
    local copy = {}
    copies[orig] = copy
    for k, v in pairs(orig) do
        copy[deep_copy(k, copies)] = deep_copy(v, copies)
    end
    return copy
end

--- Walk the spec tree and resolve all $ref nodes.
-- Uses a registry to handle circular refs: each unique $ref target is
-- resolved once and stored; subsequent refs to the same target reuse it.
--
-- For OAS 3.1, $ref can have sibling keywords. In that case we wrap in allOf:
--   { "$ref": "...", "maxLength": 5 }
--   → { "allOf": [ resolved_target, { "maxLength": 5 } ] }
--
-- @param spec table  the root OpenAPI spec (mutated in place)
-- @return boolean
-- @return string|nil error
function _M.resolve(spec)
    local registry = {}  -- pointer → resolved table
    local resolving = {} -- pointer → true (cycle detection during first resolution)

    local function do_resolve(node, root, path)
        if type(node) ~= "table" then
            return node, nil
        end

        local ref = node["$ref"]
        if ref then
            -- reject external refs
            if type(ref) ~= "string" then
                return nil, "invalid $ref type at " .. path
            end
            if sub(ref, 1, 1) ~= "#" then
                return nil, "external $ref not supported: " .. ref .. " at " .. path
            end

            local pointer = sub(ref, 2) -- strip leading "#"
            if pointer == "" then
                pointer = "/"
            end

            -- collect sibling keys (OAS 3.1 allows $ref + siblings)
            local siblings = {}
            local has_siblings = false
            for k, v in pairs(node) do
                if k ~= "$ref" then
                    siblings[k] = v
                    has_siblings = true
                end
            end

            -- check registry first
            if registry[pointer] then
                if has_siblings then
                    return { allOf = { registry[pointer], siblings } }, nil
                end
                return registry[pointer], nil
            end

            -- cycle detection
            if resolving[pointer] then
                -- circular ref: create a placeholder that will be filled in
                -- For now, we store an empty table as placeholder and let
                -- the caller handle recursion at validation time.
                local placeholder = {}
                registry[pointer] = placeholder
                if has_siblings then
                    return { allOf = { placeholder, siblings } }, nil
                end
                return placeholder, nil
            end

            resolving[pointer] = true

            -- resolve the pointer
            local target, err = resolve_pointer(root, pointer)
            if not target then
                return nil, "cannot resolve $ref '" .. ref .. "': " .. err
            end

            -- deep copy to avoid mutation of shared nodes
            local resolved = deep_copy(target)

            -- recursively resolve refs within the resolved target
            resolved, err = do_resolve(resolved, root, ref)
            if err then
                return nil, err
            end

            registry[pointer] = resolved
            resolving[pointer] = nil

            if has_siblings then
                return { allOf = { resolved, siblings } }, nil
            end
            return resolved, nil
        end

        -- no $ref — recurse into children
        for k, v in pairs(node) do
            if type(v) == "table" then
                local resolved, err = do_resolve(v, root, path .. "/" .. k)
                if err then
                    return nil, err
                end
                node[k] = resolved
            end
        end

        return node, nil
    end

    local _, err = do_resolve(spec, spec, "#")
    if err then
        return false, err
    end

    return true, nil
end

return _M

-- Schema normalization: convert OpenAPI 3.0/3.1 schemas to JSON Schema Draft 7.
-- This module walks all schema objects in a parsed OpenAPI spec and transforms
-- them so that api7/jsonschema (Draft 4/6/7) can validate them.

local _M = {}

local type       = type
local pairs      = pairs
local ipairs     = ipairs
local tab_insert = table.insert

-- Keywords that are Draft 2020-12 only and have no Draft 7 equivalent
local UNSUPPORTED_31_KEYWORDS = {
    ["$dynamicRef"] = true,
    ["$dynamicAnchor"] = true,
    ["unevaluatedProperties"] = true,
    ["unevaluatedItems"] = true,
}

-- Normalize a single schema node (3.0 → Draft 7).
local function normalize_30_schema(schema, warnings)
    if type(schema) ~= "table" then
        return
    end

    -- nullable: true → type becomes [original, "null"]
    -- also inject null into enum/const if present
    if schema.nullable == true then
        schema.nullable = nil

        -- For nullable schemas with enum or const, we cannot simply inject
        -- cjson.null into enum (jsonschema can't handle userdata in enum).
        -- Use anyOf: [original_schema_without_nullable, {type: "null"}]
        if schema.enum or schema["const"] then
            -- save and remove nullable-related fields, wrap in anyOf
            local original = {}
            for k, v in pairs(schema) do
                if k ~= "nullable" then
                    original[k] = v
                end
            end
            -- clear schema and replace with anyOf
            for k in pairs(schema) do
                schema[k] = nil
            end
            schema.anyOf = { original, { type = "null" } }
        elseif schema.type then
            if type(schema.type) == "string" then
                schema.type = { schema.type, "null" }
            elseif type(schema.type) == "table" then
                local has_null = false
                for _, t in ipairs(schema.type) do
                    if t == "null" then
                        has_null = true
                        break
                    end
                end
                if not has_null then
                    tab_insert(schema.type, "null")
                end
            end
        end
    end

    -- exclusiveMinimum (boolean) + minimum → exclusiveMinimum (numeric)
    if schema.exclusiveMinimum == true then
        if schema.minimum ~= nil then
            schema.exclusiveMinimum = schema.minimum
            schema.minimum = nil
        else
            -- exclusiveMinimum: true without minimum is invalid, remove it
            schema.exclusiveMinimum = nil
            tab_insert(warnings, "exclusiveMinimum: true without minimum, ignored")
        end
    elseif schema.exclusiveMinimum == false then
        schema.exclusiveMinimum = nil
    end

    -- exclusiveMaximum (boolean) + maximum → exclusiveMaximum (numeric)
    if schema.exclusiveMaximum == true then
        if schema.maximum ~= nil then
            schema.exclusiveMaximum = schema.maximum
            schema.maximum = nil
        else
            schema.exclusiveMaximum = nil
            tab_insert(warnings, "exclusiveMaximum: true without maximum, ignored")
        end
    elseif schema.exclusiveMaximum == false then
        schema.exclusiveMaximum = nil
    end

    -- drop non-validation fields
    schema.example = nil
end

-- Normalize a single schema node (3.1 → Draft 7).
local function normalize_31_schema(schema, warnings, strict)
    if type(schema) ~= "table" then
        return nil
    end

    -- Check for unsupported 2020-12 keywords
    for kw in pairs(UNSUPPORTED_31_KEYWORDS) do
        if schema[kw] ~= nil then
            if strict then
                return "unsupported OpenAPI 3.1 keyword: " .. kw
            end
            tab_insert(warnings, "unsupported keyword ignored: " .. kw)
            schema[kw] = nil
        end
    end

    -- prefixItems (2020-12) → items (Draft 7 tuple form)
    -- new items (2020-12, schema after prefix) → additionalItems (Draft 7)
    if schema.prefixItems then
        local old_items = schema.items
        schema.items = schema.prefixItems
        schema.prefixItems = nil
        if old_items and type(old_items) == "table" then
            schema.additionalItems = old_items
        end
    end

    -- $defs → definitions
    if schema["$defs"] then
        schema.definitions = schema["$defs"]
        schema["$defs"] = nil
    end

    -- dependentRequired → dependencies (Draft 7)
    if schema.dependentRequired then
        schema.dependencies = schema.dependencies or {}
        for prop, required_list in pairs(schema.dependentRequired) do
            schema.dependencies[prop] = required_list
        end
        schema.dependentRequired = nil
    end

    -- dependentSchemas → dependencies (Draft 7)
    if schema.dependentSchemas then
        schema.dependencies = schema.dependencies or {}
        for prop, dep_schema in pairs(schema.dependentSchemas) do
            schema.dependencies[prop] = dep_schema
        end
        schema.dependentSchemas = nil
    end

    -- minContains / maxContains → warn/error (no Draft 7 equivalent)
    if schema.minContains ~= nil or schema.maxContains ~= nil then
        if strict then
            return "unsupported keyword: minContains/maxContains"
        end
        tab_insert(warnings, "minContains/maxContains ignored (no Draft 7 equivalent)")
        schema.minContains = nil
        schema.maxContains = nil
    end

    -- $anchor → drop (we use inline resolution, no need for anchors)
    if schema["$anchor"] then
        schema["$anchor"] = nil
    end

    -- contentMediaType / contentEncoding / contentSchema → drop
    schema.contentMediaType = nil
    schema.contentEncoding = nil
    schema.contentSchema = nil

    -- examples (array, 3.1) / $comment → drop
    schema.examples = nil
    schema["$comment"] = nil

    return nil
end

-- Recursively walk all schema-like objects in the spec and normalize them.
local function walk_and_normalize(node, version, warnings, strict, visited)
    if type(node) ~= "table" then
        return nil
    end

    if visited[node] then
        return nil
    end
    visited[node] = true

    -- Detect if this node looks like a schema (has type, properties, items, etc.)
    local is_schema = node.type or node.properties or node.items
                       or node.allOf or node.anyOf or node.oneOf
                       or node.enum or node["$ref"]

    if is_schema then
        local err
        if version == "3.0" then
            normalize_30_schema(node, warnings)
        else
            err = normalize_31_schema(node, warnings, strict)
            if err then
                return err
            end
        end
    end

    -- Recurse into all sub-tables
    for _, v in pairs(node) do
        if type(v) == "table" then
            local err = walk_and_normalize(v, version, warnings, strict, visited)
            if err then
                return err
            end
        end
    end

    return nil
end

-- Normalize all schemas in an OpenAPI spec.

function _M.normalize_spec(spec, version, opts)
    local warnings = {}
    local strict = opts and opts.strict or false
    local visited = {}

    local err = walk_and_normalize(spec, version, warnings, strict, visited)
    if err then
        return warnings, err
    end

    return warnings, nil
end

return _M

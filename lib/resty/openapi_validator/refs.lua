-- Internal $ref resolution for OpenAPI specs.
-- Resolves all $ref pointers within the same document, replacing them inline.
-- Uses in-place sharing: every $ref to the same pointer is replaced by the
-- *same* Lua table, so resolution is O(spec size) regardless of how many
-- times a schema is referenced. Cycles terminate naturally because each
-- target is registered *before* its children are walked.

local _M = {}

local type       = type
local pairs      = pairs
local sub_str    = string.sub
local str_gsub   = string.gsub
local str_gmatch = string.gmatch


-- Resolve a JSON Pointer (RFC 6901) against a root document.
local function resolve_pointer(root, pointer)
    local current = root
    for token in str_gmatch(pointer, "[^/]+") do
        token = str_gsub(token, "~1", "/")
        token = str_gsub(token, "~0", "~")
        if type(current) ~= "table" then
            return nil, "cannot traverse non-table at '" .. token .. "'"
        end
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


-- Collect all $dynamicAnchor targets from a spec tree.
-- Returns a map from anchor name to the table containing the anchor.
local function collect_dynamic_anchors(node, anchors, visited)
    if type(node) ~= "table" or visited[node] then
        return
    end
    visited[node] = true

    local anchor = node["$dynamicAnchor"]
    if anchor then
        anchors[anchor] = node
    end

    for _, v in pairs(node) do
        collect_dynamic_anchors(v, anchors, visited)
    end
end


-- Walk the spec tree and resolve every $ref node in place.
--
-- Strategy:
--   * `registry[ref]` maps a $ref string to its resolved Lua table. The first
--     time we see a $ref we look up the target, register it BEFORE recursing
--     into its children, then walk the target so any nested $refs inside it
--     get replaced. All subsequent occurrences of the same $ref reuse the
--     registered object. This keeps total work linear in the spec size.
--   * `walked` tracks every table we have already walked (regardless of how
--     we reached it). Without it the post-resolution graph contains cycles
--     and direct descent into `components.schemas.*` would re-walk targets
--     that were already resolved via $ref.
--   * For OAS 3.1, $ref + sibling keys (e.g. {$ref: "...", maxLength: 5})
--     are translated to {allOf: [resolved, siblings]}; siblings get walked
--     too in case they contain $refs of their own. This wrapping never
--     mutates the registered target, so sibling-bearing references stay
--     local while plain references stay shared.
function _M.resolve(spec)
    local registry = {}
    local walked = {}

    -- Collect $dynamicAnchor targets for $dynamicRef resolution
    local dynamic_anchors = {}
    collect_dynamic_anchors(spec, dynamic_anchors, {})

    local walk

    local function resolve_ref(ref)
        local resolved = registry[ref]
        if resolved then
            return resolved
        end
        if sub_str(ref, 1, 1) ~= "#" then
            error("external $ref not supported: " .. ref, 0)
        end
        local pointer = sub_str(ref, 2)
        if pointer == "" then
            pointer = "/"
        end
        local target, perr = resolve_pointer(spec, pointer)
        if not target then
            error("cannot resolve $ref '" .. ref .. "': " .. perr, 0)
        end
        -- register BEFORE walking, so cycles A -> B -> A terminate by
        -- returning the in-progress target the second time we hit it.
        registry[ref] = target
        if type(target) == "table" then
            target._ref = ref
            walk(target)
        end
        return target
    end

    walk = function(node)
        if type(node) ~= "table" or walked[node] then
            return
        end
        walked[node] = true

        for k, v in pairs(node) do
            if type(v) == "table" then
                local ref = v["$ref"]
                if ref then
                    if type(ref) ~= "string" then
                        error("invalid $ref type", 0)
                    end
                    local resolved = resolve_ref(ref)

                    -- collect sibling keys (OAS 3.1 allows $ref + siblings)
                    local siblings, has_siblings
                    for sk, sv in pairs(v) do
                        if sk ~= "$ref" then
                            siblings = siblings or {}
                            siblings[sk] = sv
                            has_siblings = true
                        end
                    end

                    if has_siblings then
                        walk(siblings)
                        node[k] = { allOf = { resolved, siblings } }
                    else
                        node[k] = resolved
                    end
                elseif v["$dynamicRef"] then
                    -- Resolve $dynamicRef by looking up the anchor
                    local dyn_ref = v["$dynamicRef"]
                    local anchor_name = dyn_ref:match("^#(.+)$")
                    if anchor_name and dynamic_anchors[anchor_name] then
                        local target = dynamic_anchors[anchor_name]
                        walk(target)

                        -- collect sibling keys
                        local siblings, has_siblings
                        for sk, sv in pairs(v) do
                            if sk ~= "$dynamicRef" then
                                siblings = siblings or {}
                                siblings[sk] = sv
                                has_siblings = true
                            end
                        end

                        if has_siblings then
                            walk(siblings)
                            node[k] = { allOf = { target, siblings } }
                        else
                            node[k] = target
                        end
                    end
                    -- unresolved $dynamicRef: leave for normalize to warn/error
                else
                    walk(v)
                end
            end
        end
    end

    local ok, err = pcall(walk, spec)
    if not ok then
        return false, err
    end

    return true, nil
end

return _M

--- Minimal test helper for running outside OpenResty.
local _M = {}

local pass_count = 0
local fail_count = 0
local test_name = ""

function _M.plan(n)
    print("1.." .. n)
end

function _M.describe(name, fn)
    test_name = name
    fn()
end

function _M.ok(cond, msg)
    if cond then
        pass_count = pass_count + 1
        print("ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
    else
        fail_count = fail_count + 1
        print("not ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
    end
end

function _M.is(got, expected, msg)
    if got == expected then
        pass_count = pass_count + 1
        print("ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
    else
        fail_count = fail_count + 1
        print("not ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
        print("#   got: " .. tostring(got))
        print("#   expected: " .. tostring(expected))
    end
end

function _M.isnt(got, unexpected, msg)
    _M.ok(got ~= unexpected, msg)
end

function _M.like(got, pattern, msg)
    if type(got) == "string" and got:find(pattern) then
        pass_count = pass_count + 1
        print("ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
    else
        fail_count = fail_count + 1
        print("not ok " .. (pass_count + fail_count) .. " - " .. (msg or test_name))
        print("#   got: " .. tostring(got))
        print("#   pattern: " .. pattern)
    end
end

function _M.done()
    print("# passed: " .. pass_count .. ", failed: " .. fail_count)
    if fail_count > 0 then
        os.exit(1)
    end
end

return _M

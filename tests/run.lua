-- Runs the regression tests: compiles every file the .toc ships, then runs each suite in its own
-- interpreter so their stubs can't leak into each other. Exits with 1 if anything failed.
--
-- From anywhere: lua5.1 tests/run.lua
-- One suite:     lua5.1 tests/test_parser.lua

-- Add new suites here.
local SUITES = { "test_parser.lua", "test_coefficients.lua", "test_notes.lua", "test_macro.lua", "test_stat_values.lua",
    "test_secrets.lua" }

local dir = arg[0]:match("^(.*)[/\\]") or "."
local addon = dir .. "/../ResourceEfficiencyTooltips"
local lua = arg[-1] or "lua5.1"
local failed = 0
io.stdout:setvbuf("no") -- keep our lines in order with the suites' output

-- Syntax check of the shipped files, in .toc order.
local toc = assert(io.open(addon .. "/ResourceEfficiencyTooltips.toc"))
for line in toc:lines() do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then
        local ok, err = loadfile(addon .. "/" .. file)
        if ok then
            print("compiles  " .. file)
        else
            print("FAIL      " .. err)
            failed = failed + 1
        end
    end
end
toc:close()

for _, suite in ipairs(SUITES) do
    print("\n== " .. suite)
    -- cmd.exe drops the outer pair of quotes, so wrap the quoted command in one more.
    local status = os.execute(string.format('""%s" "%s/%s""', lua, dir, suite))
    if status ~= 0 then failed = failed + 1 end
end

print(failed == 0 and "\nAll tests passed." or string.format("\n%d check(s) or suite(s) failed.", failed))
os.exit(failed == 0 and 0 or 1)

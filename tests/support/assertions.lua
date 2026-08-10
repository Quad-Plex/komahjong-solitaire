-- Small shared assertion helpers. Feature suites may add domain-specific
-- helpers, but failure formatting and accounting live in one place.
local M = {}

function M.newSuite(name)
    local suite = { name = name, failures = 0 }

    function suite:expect(condition, message)
        if condition then
            print("PASS: " .. message)
        else
            self.failures = self.failures + 1
            print("FAIL: " .. message)
        end
    end

    function suite:finish()
        if self.failures == 0 then
            print("\nALL " .. self.name .. " CHECKS PASSED")
        else
            print("\n" .. self.failures .. " FAILURES in " .. self.name)
            os.exit(1)
        end
    end

    return suite
end

return M

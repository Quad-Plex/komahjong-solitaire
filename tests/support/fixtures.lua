-- Feature-suite fixtures. These preserve real interaction paths instead of
-- mutating widget state or dealing boards behind the UI.
local M = {}

function M.pickLayout(ctx, id)
    local picker = ctx.window_stack[#ctx.window_stack].widget
    while picker do
        for _, card in ipairs(picker._card_rects or {}) do
            if card.id == id then
                picker:onTapSelect(nil, {
                    pos = { x = card.x + card.w / 2, y = card.y + card.h / 2 },
                })
                ctx.runScheduled()
                return true
            end
        end
        if not picker._page_right or picker._page_right.enabled == false then break end
        picker._page_right.callback()
        picker = ctx.window_stack[#ctx.window_stack].widget
    end
    return false
end

function M.pickTurtle(ctx)
    return M.pickLayout(ctx, "turtle")
end

function M.mapCount(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

return M

local clock = module.require("modules/clock.lua")

local function same(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label,
            tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    if not value then error(label, 2) end
end

local THIN = "\226\128\134"

return {
    ["formats the time in both clocks"] = function()
        same(clock.timeText(0, 0, true), "00:00", "midnight 24h")
        same(clock.timeText(23, 49, true), "23:49", "late 24h")
        same(clock.timeText(9, 5, true), "09:05", "padded 24h")
        same(clock.timeText(0, 5, false), "12:05", "midnight 12h")
        same(clock.timeText(13, 5, false), "1:05", "afternoon 12h")
        same(clock.timeText(12, 0, false), "12:00", "noon 12h")
        same(clock.timeText(99, 99, true), "03:39", "wraps out-of-range input")
    end,

    ["formats weekday in both languages"] = function()
        same(clock.weekdayText(1, true), "周日", "sunday zh")
        same(clock.weekdayText(6, true), "周五", "friday zh")
        same(clock.weekdayText(1, false), "SUN", "sunday en")
        same(clock.weekdayText(7, false), "SAT", "saturday en")
        same(clock.weekdayText(9, false), "", "invalid weekday")
    end,

    ["formats the date with thin spaces"] = function()
        same(clock.dateText(11, 15), "11" .. THIN .. "." .. THIN .. "15",
            "thin spaces around the dot")
        same(clock.dateText(1, 2, true), "1.2", "tight form")
    end,

    ["measures the time ink box, not the advance box"] = function()
        local left, width = clock.timeInk("00:00")
        truthy(math.abs(left - 0.033) < 1e-6, "left bearing " .. left)
        truthy(math.abs(width - 1.722) < 1e-6, "ink width " .. width)
        truthy(width < clock.timeAdvanceEm("00:00"), "ink sits inside advance")
        -- "1" carries a wider left bearing than "0"; the ink box must follow.
        local left1, width1 = clock.timeInk("1:05")
        truthy(math.abs(left1 - 0.080) < 1e-6, "left bearing of 1:05 " .. left1)
        truthy(math.abs(width1 - 1.274) < 1e-6, "ink width of 1:05 " .. width1)
        local unknownLeft, unknownWidth = clock.timeInk("x")
        truthy(math.abs(unknownLeft - 0.033) < 1e-6, "unknown glyph falls back")
        truthy(math.abs(unknownWidth - 0.334) < 1e-6, "fallback ink width")
        local emptyLeft, emptyWidth = clock.timeInk("")
        same(emptyLeft, 0, "empty left")
        same(emptyWidth, 0, "empty width")
    end,

    ["keeps the time inside its row on a wide card"] = function()
        -- 3x2 is the wide case: height, not width, caps the time there.
        local size = math.min(288 * 0.80 / clock.timeAdvanceEm("00:00"),
            240 * 0.38 * 0.98 / clock.timeMetrics.inkHeight)
        local _, inkWidth = clock.timeInk("00:00")
        truthy(inkWidth * size <= 288 * 0.90, "ink fits the card")
        truthy(clock.timeMetrics.inkHeight * size <= 240 * 0.38,
            "ink fits the row")
    end,

    ["places ticks evenly around the rounded outline"] = function()
        local ticks, thickness = clock.dialTicks(400, 400)
        truthy(#ticks > 60 and #ticks < 100, "tick count " .. #ticks)
        truthy(thickness >= 1, "thickness")
        for index = 1, #ticks do
            local tick = ticks[index]
            for field = 1, 4 do
                truthy(type(tick[field]) == "number", "numeric endpoint")
                truthy(tick[field] == tick[field], "not NaN")
            end
            truthy(tick[1] >= 0 and tick[1] <= 400, "x1 inside")
            truthy(tick[2] >= 0 and tick[2] <= 400, "y1 inside")
            truthy(tick[3] >= 0 and tick[3] <= 400, "x2 inside")
            truthy(tick[4] >= 0 and tick[4] <= 400, "y2 inside")
            local dx, dy = tick[3] - tick[1], tick[4] - tick[2]
            local length = math.sqrt(dx * dx + dy * dy)
            truthy(math.abs(length - 12) < 0.6, "tick length " .. length)
        end
    end,

    ["skips the ring on a card too small to show it"] = function()
        local ticks = clock.dialTicks(80, 80)
        same(#ticks, 0, "no ticks below the minimum side")
    end,

    ["keeps the ring inside a wide card"] = function()
        local ticks, thickness = clock.dialTicks(600, 300)
        truthy(#ticks > 40, "ticks on a wide card")
        truthy(thickness >= 1, "thickness")
        for index = 1, #ticks do
            local tick = ticks[index]
            truthy(tick[1] >= 0 and tick[1] <= 600, "x inside")
            truthy(tick[2] >= 0 and tick[2] <= 300, "y inside")
        end
    end,

    ["concentric corners follow the card radius"] = function()
        -- first tick sits on the top edge, right of the corner arc
        local round = clock.dialTicks(400, 400, { cardRadius = 28 })
        local flat = clock.dialTicks(400, 400, { cardRadius = 0 })
        local inset = 400 * 0.041
        truthy(math.abs(round[1][1] - (inset + (28 - inset))) < 0.01,
            "rounded start x " .. round[1][1])
        truthy(math.abs(flat[1][1] - inset) < 0.01,
            "square start x " .. flat[1][1])
        truthy(math.abs(round[1][2] - inset) < 0.01, "top edge y")
        truthy(#round < #flat, "a rounded outline has fewer ticks")
    end,

    ["survives a degenerate corner radius"] = function()
        local ticks = clock.dialTicks(300, 300, { cardRadius = 500 })
        truthy(#ticks > 0, "ticks still generated")
        for index = 1, #ticks do
            local tick = ticks[index]
            truthy(tick[1] == tick[1] and tick[2] == tick[2], "not NaN")
        end
        local nanTicks = clock.dialTicks(300, 300, { cardRadius = 0 / 0 })
        truthy(#nanTicks > 0, "NaN radius falls back to square corners")
        for index = 1, #nanTicks do
            local tick = nanTicks[index]
            truthy(tick[1] == tick[1] and tick[2] == tick[2], "not NaN")
        end
    end,

    ["caps the ring and ignores non-string time input"] = function()
        local ticks = clock.dialTicks(4000, 4000)
        truthy(#ticks <= 400, "tick cap " .. #ticks)
        same(clock.timeAdvanceEm(nil), 0, "nil advance")
        same(clock.timeAdvanceEm(42), 0, "number advance")
        local left, width = clock.timeInk(42)
        same(left, 0, "number left")
        same(width, 0, "number width")
    end,

    ["rejects non-finite clock input"] = function()
        local nan = 0 / 0
        same(clock.timeText(nan, nan, true), "00:00", "NaN hour/minute")
        same(clock.timeText(math.huge, 5, true), "00:05", "infinite hour")
        same(clock.timeText(-1, -5, true), "23:55", "negative wraps")
        same(clock.weekdayText(nan, true), "", "NaN weekday")
        same(clock.dateText(nan, nan), "1" .. THIN .. "." .. THIN .. "1",
            "NaN date")
        same(clock.dateText(0, 0), "1" .. THIN .. "." .. THIN .. "1",
            "zero clamps")
        same(clock.dateText(99, 99), "12" .. THIN .. "." .. THIN .. "31",
            "overflow clamps")
        same(clock.dateText(1e308, -1e308), "12" .. THIN .. "." .. THIN .. "1",
            "huge values clamp")
    end,
}

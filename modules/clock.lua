-- modules/clock.lua - pure clock text and dial geometry.
--
-- Kept free of host APIs so `snowwidget test` can exercise it: the dial is the
-- same arc-length parameterisation the reference card uses (equal spacing along
-- the rounded-rect outline, ticks aimed at the centre), and the labels follow
-- the reference's formats.

local clock = {}

local WEEK_EN = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
local WEEK_ZH = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

-- Six-per-em space (U+2006): a plain space at 58 px pulls "10" and "." apart
-- almost twice as far as the reference card.
local THIN = "\226\128\134"

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge
        or value == -math.huge then
        return fallback
    end
    return value
end

function clock.timeText(hour, minute, hour24)
    hour = math.floor(finite(hour, 0)) % 24
    minute = math.floor(finite(minute, 0)) % 60
    if hour24 then
        return string.format("%02d:%02d", hour, minute)
    end
    local displayed = hour % 12
    if displayed == 0 then displayed = 12 end
    return string.format("%d:%02d", displayed, minute)
end

function clock.weekdayText(wday, zh)
    local list = zh and WEEK_ZH or WEEK_EN
    return list[math.floor(finite(wday, 0))] or ""
end

function clock.dateText(month, day, tight)
    month = math.floor(finite(month, 1))
    day = math.floor(finite(day, 1))
    if tight then return string.format("%d.%d", month, day) end
    return string.format("%d%s.%s%d", month, THIN, THIN, day)
end

-- One point on the outline, parameterised by arc length from the top-left
-- corner: top edge -> top-right arc -> right edge -> bottom-right arc -> bottom
-- edge -> bottom-left arc -> left edge -> top-left arc.
local function sample(s, left, top, right, bottom, radius, edgeX, edgeY, arc)
    local cursor = s
    if cursor < edgeX then
        return left + radius + cursor, top
    end
    cursor = cursor - edgeX

    if arc > 0 and cursor < arc then
        local angle = -math.pi / 2 + cursor / radius
        return right - radius + math.cos(angle) * radius,
            top + radius + math.sin(angle) * radius
    end
    cursor = cursor - arc

    if cursor < edgeY then
        return right, top + radius + cursor
    end
    cursor = cursor - edgeY

    if arc > 0 and cursor < arc then
        local angle = cursor / radius
        return right - radius + math.cos(angle) * radius,
            bottom - radius + math.sin(angle) * radius
    end
    cursor = cursor - arc

    if cursor < edgeX then
        return right - radius - cursor, bottom
    end
    cursor = cursor - edgeX

    if arc > 0 and cursor < arc then
        local angle = math.pi / 2 + cursor / radius
        return left + radius + math.cos(angle) * radius,
            bottom - radius + math.sin(angle) * radius
    end
    cursor = cursor - arc

    if cursor < edgeY then
        return left, bottom - radius - cursor
    end
    cursor = cursor - edgeY

    if arc > 0 then
        local angle = math.pi + math.min(cursor / radius, math.pi / 2)
        return left + radius + math.cos(angle) * radius,
            top + radius + math.sin(angle) * radius
    end
    return left + radius, top
end

-- dialTicks(width, height, options) -> ticks, thickness
-- Each tick is { x1, y1, x2, y2 }: the outer end sits on the outline, the inner
-- end points at the card centre.
--
-- The outline is the card border offset inward by `inset`, so its corner radius
-- is the card's own radius minus that inset (concentric rounded rects). The
-- host does not expose its card radius to widgets, so `cardRadius` is the
-- SnowDesktop personalization value in DIP; CornerRatio stays as an override
-- for tests and non-standard hosts.
function clock.dialTicks(width, height, options)
    options = options or {}
    if type(width) ~= "number" or type(height) ~= "number" then return {}, 0 end
    local short = math.min(width, height)
    -- A one-cell card turns the ring into a grey smear; the reference card has
    -- no such size either.
    if short < (options.minSide or 92) then return {}, 0 end

    local inset = short * (options.insetRatio or 0.041)
    local left, top = inset, inset
    local right, bottom = width - inset, height - inset
    if right <= left or bottom <= top then return {}, 0 end

    local cardCorner
    if options.cardRadius ~= nil then
        cardCorner = options.cardRadius
    elseif options.cornerRatio ~= nil then
        cardCorner = short * options.cornerRatio
    else
        cardCorner = options.defaultCardRadius or 28
    end
    cardCorner = tonumber(cardCorner) or 0
    if cardCorner ~= cardCorner or cardCorner == math.huge
        or cardCorner == -math.huge then
        cardCorner = 0
    end
    local radius = math.min(math.max(0, cardCorner - inset),
        (right - left) / 2, (bottom - top) / 2)

    local edgeX = math.max(0, (right - left) - 2 * radius)
    local edgeY = math.max(0, (bottom - top) - 2 * radius)
    local arc = math.pi * radius / 2
    local perimeter = 2 * edgeX + 2 * edgeY + 4 * arc
    if perimeter <= 1 then return {}, 0 end

    local spacing = math.max(6, short * (options.spacingRatio or 0.046))
    local count = math.max(8, math.floor(perimeter / spacing + 0.5))
    local step = perimeter / count
    local tickLength = short * (options.tickLengthRatio or 0.030)
    local thickness = math.max(1, short * 0.0062)
    local centerX, centerY = width / 2, height / 2

    local ticks = {}
    for index = 0, count - 1 do
        local x, y = sample(index * step, left, top, right, bottom, radius,
            edgeX, edgeY, arc)
        local dx, dy = centerX - x, centerY - y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.001 then
            ticks[#ticks + 1] = {
                x, y,
                x + dx / length * tickLength,
                y + dy / length * tickLength,
            }
        end
    end
    return ticks, thickness
end

-- Bebas Neue metrics, in em units (unitsPerEm 1000), read from the bundled
-- TTF: { advance, ink xMin, ink xMax }. The bundled font is fixed, so the time
-- is fitted and centred from these instead of measureText -- measuring with a
-- font handle crashes the 1.0.16 host (0xC0000409). Digits sit 0.010 em below
-- the baseline (yMin) and 0.710 em above it (yMax).
local GLYPH_EM = {
    ["0"] = { 0.4000, 0.0330, 0.3670 },
    ["1"] = { 0.4000, 0.0800, 0.3050 },
    ["2"] = { 0.4000, 0.0390, 0.3670 },
    ["3"] = { 0.4000, 0.0330, 0.3610 },
    ["4"] = { 0.4000, 0.0150, 0.3870 },
    ["5"] = { 0.4000, 0.0380, 0.3660 },
    ["6"] = { 0.4000, 0.0360, 0.3700 },
    ["7"] = { 0.4000, 0.0340, 0.3640 },
    ["8"] = { 0.4000, 0.0280, 0.3720 },
    ["9"] = { 0.4000, 0.0300, 0.3640 },
    [":"] = { 0.1880, 0.0410, 0.1470 },
}
-- Vertical ink box of a digit, measured on 1.0.16: the host puts the baseline
-- 0.933 em under the y passed to draw.text, so the top of the digits lands at
-- 0.223 em and the box is 0.720 em tall. Both are constants of the face, not
-- of the string -- digits are the tallest glyphs in a clock.
clock.timeMetrics = { inkTop = 0.223, inkHeight = 0.720 }

local function glyph(ch)
    return GLYPH_EM[ch] or GLYPH_EM["0"]
end

function clock.timeAdvanceEm(text)
    local total = 0
    for index = 1, #text do
        total = total + glyph(text:sub(index, index))[1]
    end
    return total
end

-- timeInk(text) -> left, width in em, relative to the draw origin. Side
-- bearings differ per digit ("1" carries 0.080 em, "4" 0.015 em), so the ink
-- box -- not the advance width -- is what gets centred.
function clock.timeInk(text)
    local pen, left, right = 0, nil, nil
    for index = 1, #text do
        local metrics = glyph(text:sub(index, index))
        local xMin, xMax = pen + metrics[2], pen + metrics[3]
        if left == nil or xMin < left then left = xMin end
        if right == nil or xMax > right then right = xMax end
        pen = pen + metrics[1]
    end
    if left == nil then return 0, 0 end
    return left, right - left
end

return clock

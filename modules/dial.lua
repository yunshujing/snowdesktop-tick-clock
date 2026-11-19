-- modules/dial.lua - pure clock text and dial geometry.
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
    -- Keep %d on an integer-representable number and inside a real date even
    -- if a corrupted time snapshot arrives.
    month = math.max(1, math.min(12, month))
    day = math.max(1, math.min(31, day))
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
-- end points at the card centre. `options.count` pins the ring to 60 positions;
-- `options.clockTicks` varies tick length/thickness for an analog dial.
--
-- The outline is the card border offset inward by `inset`, so its corner radius
-- is the card's own radius minus that inset (concentric rounded rects). The
-- host does not expose its card radius to widgets, so `cardRadius` is the
-- SnowDesktop personalization value in DIP; CornerRatio stays as an override
-- for tests and non-standard hosts.
function clock.dialTicks(width, height, options)
    options = options or {}
    if type(width) ~= "number" or type(height) ~= "number"
        or width ~= width or height ~= height
        or width <= 0 or height <= 0 then return {}, 0 end
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
    local count
    if options.count ~= nil then
        count = math.floor(finite(options.count, 0))
    else
        count = math.floor(perimeter / spacing + 0.5)
    end
    -- Cap the ring at 400 ticks: a pathological surface should not spend the
    -- frame budget on decorative lines.
    count = math.min(400, math.max(8, count))
    local step = perimeter / count
    local baseLength = short * (options.tickLengthRatio or 0.030)
    local thicknessScale = math.max(0.3, math.min(4,
        finite(options.thicknessScale, 1)))
    local baseThickness = math.max(1, short * 0.0062) * thicknessScale
    local minorLengthRatio = options.minorLengthRatio or 0.045
    local cardinalLengthRatio = options.cardinalLengthRatio or 0.120
    local cornerLengthRatio = options.cornerLengthRatio or 0.140
    local centerX, centerY = width / 2, height / 2
    -- Twelve major positions keep the class angles fixed at 30 degrees. The
    -- caller snaps the count to a multiple of 12 for clock faces.
    local clockClasses = options.clockTicks and count % 12 == 0 or false
    local majorEvery = clockClasses and count / 12 or 1
    local quarterEvery = clockClasses and majorEvery * 3 or 1
    -- A time-driven ring starts at 12 o'clock (the middle of the top edge);
    -- purely decorative callers keep the original top-left start.
    local start = options.alignTop and edgeX / 2 or 0

    local ticks = {}
    for index = 0, count - 1 do
        local x, y = sample((start + index * step) % perimeter,
            left, top, right, bottom, radius, edgeX, edgeY, arc)
        local dx, dy = centerX - x, centerY - y
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > 0.001 then
            local major = clockClasses and index % majorEvery == 0 or false
            local quarter = clockClasses and index % quarterEvery == 0 or false
            local corner = clockClasses and major
                and (index % quarterEvery == majorEvery
                    or index % quarterEvery == majorEvery * 2) or false
            local length = baseLength
            local thickness = baseThickness
            if options.clockTicks then
                if corner then
                    length = short * cornerLengthRatio
                    thickness = math.max(2.5, short * 0.010)
                        * thicknessScale
                elseif quarter then
                    length = short * cardinalLengthRatio
                    thickness = math.max(2.5, short * 0.012)
                        * thicknessScale
                elseif major then
                    length = short * 0.090
                    thickness = math.max(1.4, short * 0.007)
                        * thicknessScale
                else
                    length = short * minorLengthRatio
                    thickness = math.max(0.8, short * 0.0035)
                        * thicknessScale
                end
            end
            ticks[#ticks + 1] = {
                x, y,
                x + dx / distance * length,
                y + dy / distance * length,
                major = major,
                quarter = quarter,
                corner = corner,
                length = length,
                thickness = thickness,
            }
        end
    end
    return ticks, baseThickness
end

-- Time fractions for a 12-hour dial. All three values are in [0, 1); the hour
-- fraction includes the minute and second so the hour hand creeps continuously.
function clock.timeFractions(hour, minute, second)
    hour = finite(hour, 0) % 12
    minute = finite(minute, 0) % 60
    second = finite(second, 0) % 60
    return (hour + minute / 60 + second / 3600) / 12,
        (minute + second / 60) / 60,
        second / 60
end

-- Degrees clockwise from 12 o'clock. The minute hand advances between tick
-- marks, matching a real analog clock instead of snapping once a minute.
function clock.handDegrees(hour, minute, second)
    local hourFraction, minuteFraction, secondFraction =
        clock.timeFractions(hour, minute, second)
    return hourFraction * 360, minuteFraction * 360, secondFraction * 360
end

-- Tick containing a time fraction on a ring with `count` evenly spaced
-- positions. Returned indices are 1-based; nil means an impossible ring.
function clock.tickIndex(count, fraction)
    count = math.floor(finite(count, 0))
    if count < 1 then return nil end
    local wrapped = finite(fraction, 0) % 1
    return math.floor(wrapped * count) + 1
end

-- Fade factor for a tick relative to one or more highlighted anchors. `range`
-- (a quarter to the whole ring, default three quarters) is the portion kept
-- visible: inside it alpha is untouched, outside it drops to `minimum`. A short
-- edge band blends the boundary. With no anchors it leaves alpha untouched.
function clock.fadeFactor(index, count, anchors, minimum, range)
    count = math.floor(finite(count, 0))
    index = math.floor(finite(index, 1))
    if count < 1 then return 1 end
    if type(anchors) ~= "table" or #anchors == 0 then return 1 end
    local nearest = count / 2
    for anchorIndex = 1, #anchors do
        local anchor = math.floor(finite(anchors[anchorIndex], 0))
        if anchor >= 1 and anchor <= count then
            local distance = math.abs(index - anchor)
            distance = math.min(distance, count - distance)
            if distance < nearest then nearest = distance end
        end
    end
    range = math.max(0.25, math.min(1, finite(range, 0.75)))
    if range >= 1 then return 1 end
    local visible = count * range / 2
    local edge = math.max(1, visible * 0.15)
    local factor
    if nearest <= visible - edge then
        factor = 1
    elseif nearest >= visible then
        factor = 0
    else
        factor = (visible - nearest) / edge
    end
    minimum = math.max(0, math.min(1, finite(minimum, 0)))
    return minimum + (1 - minimum) * factor
end

-- Bebas Neue metrics, in em units (unitsPerEm 1000), read from the bundled
-- TTF: { advance, ink xMin, ink xMax }. main.lua normally measures the real
-- glyph box at render time; this table is the fallback for hosts that omit
-- `ink` from measureText, and it also feeds the width fit. Digits sit 0.010 em
-- below the baseline (yMin) and 0.710 em above it (yMax).
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
    if type(text) ~= "string" then return 0 end
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
    if type(text) ~= "string" or text == "" then return 0, 0 end
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

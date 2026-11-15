-- main.lua - Tick Clock, a SnowDesktop API v2 clock card.
--
-- A ring of ticks hugging the card edge, the weekday in the reference red, the
-- time at the largest size that still fits 80% of the width, and the date under
-- it. Row proportions are measured off the reference card:
--
--   12.5% top white / 13% weekday / 6% gap / 38% time / 7% gap / 11% date / 12.5% bottom
--
-- The host owns the card material; this file draws content only.

local clock = module.require("modules/clock.lua")

-- Package fonts load during the entry phase; calling resource.font from setup
-- raises loadPhaseRequired (and takes the preview host down).
local DISPLAY_FONT = nil
do
    local ok, handle = pcall(resource.font, "display")
    if ok then DISPLAY_FONT = handle end
end

-- The reference card's fixed accent (also the model's AccentColor).
local ACCENT = 0xEE3B33
local TICK_ALPHA = 0.62
-- SnowDesktop card corner radius in DIP (personalization). The host does not
-- expose it through widget.context()/info()/ui.metrics(), so the ring is made
-- concentric with this value: outer radius = card radius - inset.
local CARD_RADIUS = 28
local WEEKDAY_ROW = 2
local TIME_ROW = 4
local DATE_ROW = 6
local ROWS = { 0.125, 0.13, 0.06, 0.38, 0.07, 0.11, 0.125 }

local settings = {
    presets = {
        {
            id = "frosted",
            label = l10n.tr("lua_widget.tick_clock.preset_frosted"),
            default = true,
            values = {
                bg = 0x0E0E12,
                border = 0xFFFFFF,
                alpha = 0.24,
                borderAlpha = 0.10,
                gradientEndA = 0.24,
            },
        },
        {
            id = "solid",
            label = l10n.tr("lua_widget.tick_clock.preset_solid"),
            values = {
                bg = 0x1C1C1E,
                border = 0xFFFFFF,
                alpha = 0.97,
                borderAlpha = 0.08,
                gradientEndA = 0.40,
            },
        },
        {
            id = "clear",
            label = l10n.tr("lua_widget.tick_clock.preset_clear"),
            values = {
                bg = 0x000000,
                border = 0x000000,
                alpha = 0,
                borderAlpha = 0,
                gradientEndA = 0,
            },
        },
    },
    fields = {
        {
            key = "weekday",
            label = l10n.tr("lua_widget.tick_clock.settings_weekday"),
            type = "bool",
            default = true,
        },
        {
            key = "date",
            label = l10n.tr("lua_widget.tick_clock.settings_date"),
            type = "bool",
            default = true,
        },
        {
            key = "hour24",
            label = l10n.tr("lua_widget.tick_clock.settings_hour24"),
            type = "bool",
            default = true,
        },
    },
}

local function isOn(key)
    local value = storage.get(key)
    if value == nil then return true end
    if type(value) ~= "string" then return value ~= false end
    value = value:lower()
    return value ~= "false" and value ~= "0"
end

local function config()
    return {
        weekday = isOn("weekday"),
        date = isOn("date"),
        hour24 = isOn("hour24"),
    }
end

local function isZh()
    return (l10n.language() or ""):sub(1, 2) == "zh"
end

-- Ink follows the host's resolved foreground, not the theme name: a dark glass
-- material can report mode "light" while the foreground is white.
local function palette()
    local snapshot = widget.theme()
    if snapshot ~= nil and snapshot.contentTheme == 1 then
        return { ink = 0x1C1C1E }
    end
    return { ink = 0xF5F5F7 }
end

local function measure(text, size, bold)
    return draw.measureText(text, size, 0, bold or false)
end

-- Host faces carry generous side bearings, so the line box is not the glyph
-- box: centring by width/height leaves CJK and digits visibly off. The 1.0.16
-- host reports the ink box from measureText (draw.textInkMetrics); use it when
-- present and fall back to the line box on hosts that omit it.
local function textCentered(text, size, color, centerX, centerY, bold)
    local box = measure(text, size, bold)
    local ink = box and box.ink
    if ink and ink.left and ink.top and ink.width and ink.width > 0
        and ink.height and ink.height > 0 then
        draw.text(centerX - ink.left - ink.width / 2,
            centerY - ink.top - ink.height / 2, text, size, color, 0,
            bold or false, true, 0, 1)
        return
    end
    draw.text(centerX - box.width / 2, centerY - box.height / 2,
        text, size, color, 0, bold or false, true, 0, 1)
end

-- measureText works with the package font inside render (a font handle in
-- setup fails, and bold reports the same box as regular). The reported ink box
-- is exact, so the time is fitted and centred from it; the TTF em table in
-- modules/clock.lua is the fallback for a host that omits ink.
local function timeInkBox(text, font)
    if not font then return nil end
    local ok, box = pcall(draw.measureText, text, 100, 0, true, font)
    if not ok or type(box) ~= "table" then return nil end
    local ink = box.ink
    if ink and ink.left and ink.top and ink.width and ink.width > 0
        and ink.height and ink.height > 0 then
        return ink
    end
    return nil
end

-- Ink-fit the time from the bundled font's metrics (see modules/clock.lua):
-- width = advance em, height = cap em. Without the resource (rare host) it
-- falls back to the host face and measureText.
local function timeFit(timeText, width, rowHeight, font)
    if font then
        return math.min(width * 0.80 / clock.timeAdvanceEm(timeText),
            rowHeight * 0.98 / clock.timeMetrics.inkHeight)
    end
    local probe = measure(timeText, 100, true)
    local byWidth = width * 0.80 / math.max(1, probe.width)
    local byHeight = rowHeight * 0.98 / math.max(1, probe.height)
    return math.min(byWidth, byHeight) * 100
end

local function fitTimeInk(ink, width, rowHeight)
    return math.min(width * 0.80 / (ink.width / 100),
        rowHeight * 0.98 / (ink.height / 100))
end

-- The em table stays as the fallback for hosts that withhold ink. Digits
-- differ in side bearing, so the ink box -- not advance/2 -- is what gets
-- centred.
local function drawTime(text, size, color, centerX, centerY, font, ink)
    if font and ink then
        draw.text(centerX - (ink.left + ink.width / 2) * size / 100,
            centerY - (ink.top + ink.height / 2) * size / 100,
            text, size, color, 0, true, true, 0, 1, font)
        return
    end
    if font then
        local metrics = clock.timeMetrics
        local left, width = clock.timeInk(text)
        draw.text(centerX - (left + width / 2) * size,
            centerY - (metrics.inkTop + metrics.inkHeight / 2) * size,
            text, size, color, 0, true, true, 0, 1, font)
        return
    end
    textCentered(text, size, color, centerX, centerY, true)
end

local function buildFrame(model)
    local width = layout.contentWidth()
    local height = layout.contentHeight()
    if width < 24 or height < 24 then return nil end

    local font = (model and model.displayFont) or DISPLAY_FONT
    local cfg = config()
    local parts = time.parts(time.now())
    -- With both labels hidden the fixed rows would park the time high on an
    -- otherwise empty card, so the time takes the whole content box instead.
    -- Otherwise the text block keeps the 2x2 aspect (height = 1.25 x width) and
    -- is centred vertically, so a tall card does not stretch the rows apart.
    local rows = ROWS
    local blockTop, blockHeight = 0, height
    if not cfg.weekday and not cfg.date then
        rows = { 0, 0, 0, 1, 0, 0, 0 }
    else
        blockHeight = math.min(height, width * 1.25)
        blockTop = (height - blockHeight) / 2
    end
    local bounds, cursor = {}, 0
    for index = 1, #rows do
        bounds[index] = {
            top = blockTop + cursor * blockHeight,
            height = rows[index] * blockHeight,
        }
        cursor = cursor + rows[index]
    end

    local ticks, thickness = clock.dialTicks(width, height,
        { cardRadius = CARD_RADIUS })
    local timeText = clock.timeText(parts.hour, parts.min, cfg.hour24)
    local timeInk = timeInkBox(timeText, font)

    local weekday = nil
    if cfg.weekday then
        weekday = clock.weekdayText(parts.wday, isZh())
    end
    local date = nil
    if cfg.date then
        date = clock.dateText(parts.month, parts.day)
    end

    return {
        width = width, height = height,
        c = palette(),
        ticks = ticks, thickness = thickness,
        weekday = weekday,
        date = date,
        timeText = timeText,
        timeInk = timeInk,
        weekdayFont = math.min(bounds[WEEKDAY_ROW].height * 0.86, width * 0.16),
        timeFont = timeInk and fitTimeInk(timeInk, width,
            bounds[TIME_ROW].height) or timeFit(timeText, width,
            bounds[TIME_ROW].height, font),
        dateFont = math.min(bounds[DATE_ROW].height * 0.95, width * 0.14),
        font = font,
        bounds = bounds,
    }
end

local function render(_context, model)
    local f = buildFrame(model)
    if not f then return end

    local ink = f.c.ink
    for index = 1, #f.ticks do
        local tick = f.ticks[index]
        draw.line(tick[1], tick[2], tick[3], tick[4], f.thickness, ink, TICK_ALPHA)
    end

    if f.weekday and f.weekday ~= "" then
        local row = f.bounds[WEEKDAY_ROW]
        textCentered(f.weekday, f.weekdayFont, ACCENT, f.width / 2,
            row.top + row.height / 2, true)
    end

    local timeRow = f.bounds[TIME_ROW]
    drawTime(f.timeText, f.timeFont, ink, f.width / 2,
        timeRow.top + timeRow.height / 2, f.font, f.timeInk)

    if f.date and f.date ~= "" then
        local row = f.bounds[DATE_ROW]
        textCentered(f.date, f.dateFont, ink, f.width / 2,
            row.top + row.height / 2, true)
    end
end

local function setup(_context)
    local model = { minute = -1 }
    model.displayFont = DISPLAY_FONT
    -- The host timer is cheap; the redraw only happens when the minute flips,
    -- so a suspended machine catches up on the next tick.
    schedule.every("tick", 1000, { whenHidden = "pause" })
    return model
end

local function event(_context, model, value)
    if type(value) ~= "table" then return end
    if value.kind == "schedule" and value.id == "tick" then
        local parts = time.parts(time.now())
        local minute = (parts.hour or 0) * 60 + (parts.min or 0)
        if minute ~= model.minute then
            model.minute = minute
            widget.invalidate()
        end
        return
    end
    if value.kind == "settings.changed" then
        widget.invalidate()
    end
end

return widget.define({
    name = l10n.tr("lua_widget.tick_clock.name"),
    useCustomStyle = true,
    followPersonalizationDefault = true,
    bg = 0x0E0E12,
    border = 0xFFFFFF,
    alpha = 0.24,
    borderAlpha = 0.10,
    gradientEndA = 0.24,
    settings = settings,
    setup = setup,
    render = render,
    event = event,
})

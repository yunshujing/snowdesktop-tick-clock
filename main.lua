-- main.lua - Tick Clock, a SnowDesktop API v2 clock card.
--
-- A ring of ticks hugging the card edge, the weekday in the reference red, the
-- time at the largest size that still fits 80% of the width, and the date under
-- it. Row proportions are measured off the reference card:
--
--   12.5% top white / 13% weekday / 6% gap / 38% time / 7% gap / 11% date / 12.5% bottom
--
-- The host owns the card material; this file draws content only.

local clock = module.require("modules/dial.lua")

-- Package fonts load during the entry phase; calling resource.font from setup
-- raises loadPhaseRequired (and takes the preview host down).
local DISPLAY_FONT = nil
do
    local ok, handle = pcall(resource.font, "display")
    if ok then DISPLAY_FONT = handle end
end

-- The reference card's fixed accent (also the model's AccentColor).
local ACCENT = 0xEE3B33
local SECOND_COLOR = 0xF0A030
local HUB_CENTER = 0x1C1C1E
local HOUR_MARK_ALPHA = 0.72
local MINUTE_MARK_ALPHA = 0.92
local SECOND_MARK_ALPHA = 1.0
-- SnowDesktop card corner radius in DIP (personalization). The host does not
-- expose it through widget.context()/info()/ui.metrics(), so the ring is made
-- concentric with this value: outer radius = card radius - inset.
local CARD_RADIUS = 28
local WEEKDAY_ROW = 2
local TIME_ROW = 4
local DATE_ROW = 6
local ROWS = { 0.125, 0.13, 0.06, 0.38, 0.07, 0.11, 0.125 }

local DIGITAL_ONLY = { key = "analog", operator = "falsy" }
local POINTER_ONLY = { key = "analog", operator = "truthy" }
local FADE_ON = { key = "fadeTicks", operator = "truthy" }
local FADE_OFF = { key = "fadeTicks", operator = "falsy" }

-- The host caches the manifest locale table per process. A key added to
-- widget.json after the instance loaded resolves to the key itself until the
-- widget is recreated. Return the Chinese fallback directly: calling
-- l10n.language() while the settings schema is evaluated breaks the host's
-- settings route.
local function text(key, fallback)
    local value = l10n.tr(key)
    if value == nil or value == "" or value == key then return fallback end
    return value
end

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
            key = "analog",
            label = text("lua_widget.tick_clock.settings_analog", "指针模式"),
            description = text("lua_widget.tick_clock.settings_analog_desc",
                "隐藏数字时间、星期和日期，改用贴边表盘与时针、分针和秒针。"),
            type = "bool",
            default = false,
        },
        {
            key = "weekday",
            label = text("lua_widget.tick_clock.settings_weekday", "显示星期"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
        },
        {
            key = "date",
            label = text("lua_widget.tick_clock.settings_date", "显示日期"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
        },
        {
            key = "hour24",
            label = text("lua_widget.tick_clock.settings_hour24", "24 小时制"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
        },
        {
            key = "fadeTicks",
            label = text("lua_widget.tick_clock.settings_fade", "刻度渐隐"),
            description = text("lua_widget.tick_clock.settings_fade_desc",
                "未高亮的刻度按距离时间标记的远近逐渐变淡。"),
            type = "bool",
            default = false,
            showWhen = DIGITAL_ONLY,
        },
        {
            key = "fadeOpacity",
            label = text("lua_widget.tick_clock.settings_fade_opacity",
                "渐隐最低透明度"),
            description = text(
                "lua_widget.tick_clock.settings_fade_opacity_desc",
                "渐隐开启时，最远处刻度的最低不透明度；0 表示完全消失（0–100）。"),
            type = "int",
            default = 0,
            min = 0,
            max = 100,
            showWhen = DIGITAL_ONLY,
            enabledWhen = FADE_ON,
        },
        {
            key = "fadeSpan",
            label = text("lua_widget.tick_clock.settings_fade_span", "渐隐范围"),
            description = text("lua_widget.tick_clock.settings_fade_span_desc",
                "以当前秒为头部，刻度保持显示的范围（25–100%），默认 60%；随秒针移动，尾部渐隐到最低透明度。"),
            type = "int",
            default = 60,
            min = 25,
            max = 100,
            showWhen = DIGITAL_ONLY,
            enabledWhen = FADE_ON,
        },
        {
            key = "highlightHour",
            label = text("lua_widget.tick_clock.settings_hour_tick",
                "时针刻度高亮"),
            description = text("lua_widget.tick_clock.settings_hour_tick_desc",
                "在时针当前对应的刻度位置显示红色标记。"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
            enabledWhen = FADE_OFF,
        },
        {
            key = "highlightMinute",
            label = text("lua_widget.tick_clock.settings_minute_tick",
                "分针刻度高亮"),
            description = text("lua_widget.tick_clock.settings_minute_tick_desc",
                "在分针当前对应的刻度位置显示红色标记。"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
            enabledWhen = FADE_OFF,
        },
        {
            key = "highlightSecond",
            label = text("lua_widget.tick_clock.settings_second", "秒针刻度高亮"),
            description = text("lua_widget.tick_clock.settings_second_desc",
                "在当前秒对应的刻度位置显示红色标记。"),
            type = "bool",
            default = true,
            showWhen = DIGITAL_ONLY,
            enabledWhen = FADE_OFF,
        },
        {
            key = "tickDensity",
            label = text("lua_widget.tick_clock.settings_tick_density", "刻度密度"),
            description = text("lua_widget.tick_clock.settings_tick_density_desc",
                "全盘刻度数量相对默认值的百分比（50–200）；指针模式按 12 根对齐。"),
            type = "int",
            default = 70,
            min = 50,
            max = 200,
        },
        {
            key = "tickBrightness",
            label = text("lua_widget.tick_clock.settings_tick_brightness",
                "刻度亮度"),
            description = text(
                "lua_widget.tick_clock.settings_tick_brightness_desc",
                "未高亮刻度的基础亮度，默认 70（5–100）。"),
            type = "int",
            default = 70,
            min = 5,
            max = 100,
        },
        {
            key = "tickRadius",
            label = text("lua_widget.tick_clock.settings_tick_radius",
                "刻度圆角半径"),
            description = text("lua_widget.tick_clock.settings_tick_radius_desc",
                "刻度环圆角半径，单位 DIP（0–64）。"),
            type = "int",
            default = 28,
            min = 0,
            max = 64,
        },
        {
            key = "tickLength",
            label = text("lua_widget.tick_clock.settings_tick_length", "刻度长度"),
            description = text("lua_widget.tick_clock.settings_tick_length_desc",
                "刻度长度占短边的百分比（1–8）。"),
            type = "int",
            default = 5,
            min = 1,
            max = 8,
        },
        {
            key = "tickThickness",
            label = text("lua_widget.tick_clock.settings_tick_thickness",
                "刻度线粗细"),
            description = text(
                "lua_widget.tick_clock.settings_tick_thickness_desc",
                "刻度线宽相对默认值的百分比（30–300）。"),
            type = "int",
            default = 100,
            min = 30,
            max = 300,
        },
        {
            key = "cornerTickLength",
            label = text("lua_widget.tick_clock.settings_corner_length",
                "角落高亮刻度长度"),
            description = text(
                "lua_widget.tick_clock.settings_corner_length_desc",
                "每个圆角处两根高亮刻度的长度，占短边百分比（5–24）。"),
            type = "int",
            default = 14,
            min = 5,
            max = 24,
            showWhen = POINTER_ONLY,
        },
        {
            key = "cardinalTickLength",
            label = text("lua_widget.tick_clock.settings_cardinal_length",
                "上下左右刻度长度"),
            description = text(
                "lua_widget.tick_clock.settings_cardinal_length_desc",
                "12、3、6、9 点方向四根刻度的长度，占短边百分比（5–24）。"),
            type = "int",
            default = 12,
            min = 5,
            max = 24,
            showWhen = POINTER_ONLY,
        },
        {
            key = "hourHandLength",
            label = text("lua_widget.tick_clock.settings_hour_length",
                "时针长度"),
            description = text("lua_widget.tick_clock.settings_hour_length_desc",
                "时针长度占短边的百分比（10–60）。"),
            type = "int",
            default = 30,
            min = 10,
            max = 60,
            showWhen = POINTER_ONLY,
        },
        {
            key = "minuteHandLength",
            label = text("lua_widget.tick_clock.settings_minute_length",
                "分针长度"),
            description = text(
                "lua_widget.tick_clock.settings_minute_length_desc",
                "分针长度占短边的百分比（10–65）。"),
            type = "int",
            default = 42,
            min = 10,
            max = 65,
            showWhen = POINTER_ONLY,
        },
        {
            key = "secondHandLength",
            label = text("lua_widget.tick_clock.settings_second_length",
                "秒针长度"),
            description = text(
                "lua_widget.tick_clock.settings_second_length_desc",
                "秒针长度占短边的百分比（10–70）。"),
            type = "int",
            default = 48,
            min = 10,
            max = 70,
            showWhen = POINTER_ONLY,
        },
    },
}

local function isOn(key, fallback)
    local value = storage.get(key)
    if value == nil then
        if fallback ~= nil then return fallback end
        return true
    end
    if type(value) ~= "string" then return value ~= false end
    value = value:lower()
    return value ~= "false" and value ~= "0"
end

local function numberSetting(key, fallback, minimum, maximum)
    local value = tonumber(storage.get(key))
    if value == nil or value ~= value then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

-- 50 is the old reference brightness. Above it the class alpha moves toward
-- opaque instead of multiplying, so corner/major/minor hierarchy survives.
local function brightnessAlpha(base, brightness)
    brightness = math.max(0, math.min(100, brightness))
    if brightness <= 50 then return base * brightness / 50 end
    return base + (1 - base) * (brightness - 50) / 50
end

-- Kept here rather than in modules/dial.lua so a hot reload of main.lua always
-- picks up the fade-range curve; module.require survives hot reload on some
-- host builds.
local function fadeFactor(index, count, anchors, minimum, range)
    count = math.floor(tonumber(count) or 0)
    index = math.floor(tonumber(index) or 1)
    if count < 1 then return 1 end
    if type(anchors) ~= "table" or #anchors == 0 then return 1 end
    -- Distance behind the moving head, clockwise-positive index order.
    local behind = count
    for anchorIndex = 1, #anchors do
        local anchor = math.floor(tonumber(anchors[anchorIndex]) or 0)
        if anchor >= 1 and anchor <= count then
            local distance = (anchor - index) % count
            if distance < behind then behind = distance end
        end
    end
    range = math.max(0.25, math.min(1, tonumber(range) or 0.6))
    if range >= 1 then return 1 end
    local tail = count * range
    local factor = math.max(0, 1 - behind / tail)
    minimum = math.max(0, math.min(1, tonumber(minimum) or 0))
    return minimum + (1 - minimum) * factor
end

local function config()
    local cfg = {
        weekday = isOn("weekday"),
        date = isOn("date"),
        hour24 = isOn("hour24"),
        analog = isOn("analog", false),
        fadeTicks = isOn("fadeTicks", false),
        fadeOpacity = numberSetting("fadeOpacity", 0, 0, 100),
        fadeRange = numberSetting("fadeSpan", 60, 25, 100),
        highlightHour = isOn("highlightHour", true),
        highlightMinute = isOn("highlightMinute", true),
        highlightSecond = isOn("highlightSecond", true),
        tickDensity = numberSetting("tickDensity", 70, 50, 200),
        tickBrightness = numberSetting("tickBrightness", 70, 5, 100),
        tickRadius = numberSetting("tickRadius", CARD_RADIUS, 0, 64),
        tickLength = numberSetting("tickLength", 5, 1, 8),
        tickThickness = numberSetting("tickThickness", 100, 30, 300),
        cornerTickLength = numberSetting("cornerTickLength", 14, 5, 24),
        cardinalTickLength = numberSetting("cardinalTickLength", 12, 5, 24),
        hourHandLength = numberSetting("hourHandLength", 30, 10, 60),
        minuteHandLength = numberSetting("minuteHandLength", 42, 10, 65),
        secondHandLength = numberSetting("secondHandLength", 48, 10, 70),
        hourHandThickness = numberSetting("hourHandThickness", 100, 30, 300),
        minuteHandThickness = numberSetting("minuteHandThickness", 100, 30, 300),
        secondHandThickness = numberSetting("secondHandThickness", 100, 30, 300),
    }
    -- Fade and tick highlight are mutually exclusive; fade wins if both are on.
    if cfg.fadeTicks then
        cfg.highlightHour = false
        cfg.highlightMinute = false
        cfg.highlightSecond = false
    end
    return cfg
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
    local box = draw.measureText(text, size, 0, bold or false)
    if type(box) ~= "table" then return { width = 0, height = 0 } end
    return box
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
-- modules/dial.lua is the fallback for a host that omits ink.
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

-- Ink-fit the time from the bundled font's metrics (see modules/dial.lua):
-- width = advance em, height = cap em. Without the resource (rare host) it
-- falls back to the host face and measureText.
local function timeFit(timeText, width, rowHeight, font)
    if font then
        return math.min(width * 0.80 / clock.timeAdvanceEm(timeText),
            rowHeight * 0.98 / clock.timeMetrics.inkHeight)
    end
    local probe = measure(timeText, 100, true)
    local probeWidth = tonumber(probe.width) or 0
    local probeHeight = tonumber(probe.height) or 0
    if probeWidth <= 0 or probeHeight <= 0 then
        return rowHeight * 0.98 / clock.timeMetrics.inkHeight
    end
    local byWidth = width * 0.80 / probeWidth
    local byHeight = rowHeight * 0.98 / probeHeight
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
    local colors = palette()
    if cfg.analog then
        -- A clock face reads best with twelve major positions; the density
        -- slider snaps the count to a multiple of 12 so the corner/quarter
        -- classes stay on the same angles.
        local analogCount = math.floor(60 * cfg.tickDensity / 100 / 12 + 0.5) * 12
        analogCount = math.max(12, math.min(240, analogCount))
        local ticks, thickness = clock.dialTicks(width, height, {
            cardRadius = cfg.tickRadius, alignTop = true,
            count = analogCount, clockTicks = true,
            insetRatio = 0.030,
            minorLengthRatio = cfg.tickLength / 100,
            thicknessScale = cfg.tickThickness / 100,
            cornerLengthRatio = cfg.cornerTickLength / 100,
            cardinalLengthRatio = cfg.cardinalTickLength / 100,
        })
        if #ticks < analogCount then return nil end
        return {
            width = width, height = height, c = colors, cfg = cfg,
            parts = parts, ticks = ticks, thickness = thickness,
            font = font, analog = true,
            face = math.min(width, height),
        }
    end

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

    local ticks, thickness = clock.dialTicks(width, height, {
        cardRadius = cfg.tickRadius, alignTop = true,
        tickLengthRatio = cfg.tickLength / 100,
        thicknessScale = cfg.tickThickness / 100,
        spacingRatio = 0.046 * 100 / cfg.tickDensity,
    })
    local hourFraction, minuteFraction, secondFraction =
        clock.timeFractions(parts.hour, parts.min, parts.sec)
    local tickCount = #ticks
    local hourTick = clock.tickIndex(tickCount, hourFraction)
    local minuteTick = clock.tickIndex(tickCount, minuteFraction)
    local secondTick = clock.tickIndex(tickCount, secondFraction)
    -- Fade mode is a moving head at the current second: the visible band
    -- follows the second tick and the tail left behind fades away.
    local fadeAnchors = { secondTick }
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
        c = colors,
        cfg = cfg,
        parts = parts,
        ticks = ticks, thickness = thickness, tickCount = tickCount,
        hourTick = hourTick,
        minuteTick = minuteTick,
        secondTick = secondTick,
        fadeAnchors = fadeAnchors,
        fadeMinimum = cfg.fadeOpacity / 100,
        fadeRange = cfg.fadeRange / 100,
        tickBaseAlpha = brightnessAlpha(0.5, cfg.tickBrightness),
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

local function drawDigitalTicks(f)
    local ink = f.c.ink
    for index = 1, #f.ticks do
        local tick = f.ticks[index]
        local alpha = f.tickBaseAlpha
        if f.cfg.fadeTicks then
            alpha = alpha * fadeFactor(index, f.tickCount, f.fadeAnchors,
                f.fadeMinimum, f.fadeRange)
        end
        local color, thickness = ink, f.thickness
        local grow = 1
        if f.cfg.highlightHour and index == f.hourTick then
            color, alpha, thickness, grow = ACCENT, HOUR_MARK_ALPHA,
                f.thickness * 1.25, 1.4
        end
        if f.cfg.highlightMinute and index == f.minuteTick then
            color, alpha, thickness, grow = ACCENT, MINUTE_MARK_ALPHA,
                f.thickness * 1.45, 1.7
        end
        if f.cfg.highlightSecond and index == f.secondTick then
            color, alpha, thickness, grow = ACCENT, SECOND_MARK_ALPHA,
                f.thickness * 1.7, 2.2
        end
        local x2, y2 = tick[3], tick[4]
        if grow ~= 1 then
            x2 = tick[1] + (tick[3] - tick[1]) * grow
            y2 = tick[2] + (tick[4] - tick[2]) * grow
        end
        draw.line(tick[1], tick[2], x2, y2, thickness, color, alpha)
    end
    local second = f.cfg.highlightSecond and f.ticks[f.secondTick] or nil
    if second then
        draw.circle(second[1], second[2], math.max(1.4, f.thickness * 1.25),
            ACCENT, 0.96)
    end
    -- Fade mode's moving head: a plain ink dot at the current second.
    if f.cfg.fadeTicks then
        local head = f.ticks[f.secondTick]
        if head then
            draw.circle(head[1], head[2], math.max(1.6, f.thickness * 1.3),
                ink, 1)
        end
    end
end

local function drawAnalog(f)
    local ink = f.c.ink
    local face = f.face
    local cx, cy = f.width / 2, f.height / 2

    -- Brightness 50 reproduces the reference alphas; above it each class moves
    -- toward opaque, so the corner/quarter/major/minor hierarchy stays visible.
    for index = 1, #f.ticks do
        local tick = f.ticks[index]
        local base = tick.corner and 1.0
            or (tick.quarter and 0.94 or (tick.major and 0.78 or 0.55))
        draw.line(tick[1], tick[2], tick[3], tick[4],
            tick.thickness, ink, brightnessAlpha(base, f.cfg.tickBrightness))
    end

    -- The four cardinal labels are the whole dial: no outer rim or extra
    -- numbers, matching the reference card's sparse square face.
    local longTick = f.ticks[1].length or face * 0.065
    local inset = f.ticks[1][2]
    local numberSize = face * 0.17
    local gap = numberSize * 0.7
    textCentered("12", numberSize, ink, cx,
        inset + longTick + gap, true)
    textCentered("3", numberSize, ink,
        f.width - inset - longTick - gap, cy, true)
    textCentered("6", numberSize, ink,
        cx, f.height - inset - longTick - gap, true)
    textCentered("9", numberSize, ink,
        inset + longTick + gap, cy, true)

    local function point(degrees, distance)
        local angle = math.rad(degrees - 90)
        return cx + math.cos(angle) * distance,
            cy + math.sin(angle) * distance
    end

    -- Clamp a hand to the content box along its own angle, so a 60-70% hand on
    -- a portrait card stops at the edge instead of drawing past the widget.
    local function frontLength(degrees, requested)
        local angle = math.rad(degrees - 90)
        local dx, dy = math.cos(angle), math.sin(angle)
        local limitX = dx > 1e-6 and (f.width - cx) / dx
            or (dx < -1e-6 and cx / -dx or math.huge)
        local limitY = dy > 1e-6 and (f.height - cy) / dy
            or (dy < -1e-6 and cy / -dy or math.huge)
        return math.min(requested, math.min(limitX, limitY) * 0.96)
    end

    local function hand(degrees, front, back, width, alpha, color)
        local x1, y1 = point(degrees + 180, back)
        local x2, y2 = point(degrees, front)
        draw.line(x1, y1, x2, y2, width, color, alpha)
        draw.circle(x2, y2, width / 2, color, alpha)
    end

    local hourAngle, minuteAngle, secondAngle = clock.handDegrees(
        f.parts.hour, f.parts.min, f.parts.sec)
    local hourWidth = math.max(0.8,
        face * 0.024 * f.cfg.hourHandThickness / 100)
    local minuteWidth = math.max(0.6,
        face * 0.018 * f.cfg.minuteHandThickness / 100)
    local secondWidth = math.max(0.3,
        face * 0.006 * f.cfg.secondHandThickness / 100)
    hand(hourAngle, frontLength(hourAngle, face * f.cfg.hourHandLength / 100),
        face * 0.04, hourWidth, 0.97, ink)
    hand(minuteAngle,
        frontLength(minuteAngle, face * f.cfg.minuteHandLength / 100),
        face * 0.05, minuteWidth, 0.97, ink)
    hand(secondAngle,
        frontLength(secondAngle, face * f.cfg.secondHandLength / 100),
        face * 0.08, secondWidth, 0.95, SECOND_COLOR)

    -- Orange hub: same reference ring with a dark centre.
    local hubOuter = math.max(2.2, face * 0.042)
    local hubInner = math.max(1.1, hubOuter * 0.42)
    draw.circle(cx, cy, hubOuter, SECOND_COLOR, 1)
    draw.circle(cx, cy, hubInner, HUB_CENTER, 1)
end

local function render(_context, model)
    local f = buildFrame(model)
    if not f then return end
    if f.analog then
        drawAnalog(f)
        return
    end

    drawDigitalTicks(f)
    local ink = f.c.ink

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

local function clockStamp(parts)
    return (parts.hour or 0) * 3600 + (parts.min or 0) * 60
        + (parts.sec or 0)
end

local function setup(_context)
    local model = { stamp = clockStamp(time.parts(time.now())) }
    model.displayFont = DISPLAY_FONT
    -- The tick ring highlights hour/minute/second positions and the pointer
    -- mode has a second hand, so the card advances once per second. Hidden
    -- cards pause the timer and catch up on the next visible tick.
    schedule.every("tick", 1000, { whenHidden = "pause" })
    return model
end

local function event(_context, model, value)
    if type(value) ~= "table" then return end
    if value.kind == "schedule" and value.id == "tick" then
        local stamp = clockStamp(time.parts(time.now()))
        if stamp ~= model.stamp then
            model.stamp = stamp
            widget.invalidate()
        end
        return
    end
    if value.kind == "settings.changed" then
        -- Fade and tick highlight are mutually exclusive. Turning fade on
        -- closes the three highlight switches; turning any highlight on
        -- closes fade. storage.set does not emit another settings.changed.
        local fadeChanged, highlightChanged = false, false
        if type(value.keys) == "table" then
            for index = 1, #value.keys do
                local key = value.keys[index]
                if key == "fadeTicks" then
                    fadeChanged = true
                elseif key == "highlightHour" or key == "highlightMinute"
                    or key == "highlightSecond" then
                    highlightChanged = true
                end
            end
        end
        if fadeChanged and isOn("fadeTicks", false) then
            if isOn("highlightHour", true) then
                storage.set("highlightHour", "false")
            end
            if isOn("highlightMinute", true) then
                storage.set("highlightMinute", "false")
            end
            if isOn("highlightSecond", true) then
                storage.set("highlightSecond", "false")
            end
        elseif highlightChanged
            and (isOn("highlightHour", true) or isOn("highlightMinute", true)
                or isOn("highlightSecond", true)) then
            storage.set("fadeTicks", "false")
        end
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

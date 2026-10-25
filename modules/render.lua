-- modified from https://github.com/rkscv/danmaku/blob/main/danmaku.lua
local msg = require('mp.msg')
local utils = require("mp.utils")
local unpack = unpack or table.unpack

local osd_width, osd_height, pause = 0, 0, true
local time_pos_observer_active = false
local overlay_low = mp.create_osd_overlay('ass-events')
local overlay_high = mp.create_osd_overlay('ass-events')

local function realtime_position_text(event, pos, displayarea)
    if not event.move then
        local _, current_y = unpack(event.pos)
        if not current_y or tonumber(current_y) > displayarea then return end
        if event.style ~= "SP" and event.style ~= "MSG" then
            return string.format("{\\an8}%s", event.text)
        else
            return string.format("{\\an7}%s", event.text)
        end
    end

    local x1, y1, x2, y2 = unpack(event.move)
    -- 计算移动的时间范围
    local duration = event.end_time - event.start_time  --mean: options.scrolltime
    local progress = (pos - event.start_time) / duration  -- 移动进度 [0, 1]

    -- 计算当前坐标
    local current_x = tonumber(x1 + (x2 - x1) * progress)
    local current_y = tonumber(y1 + (y2 - y1) * progress)

    -- 移除 \move 标签并应用当前坐标
    local clean_text = event.text:gsub("\\move%(.-%)", "")
    if current_y > displayarea then return end
    if event.style ~= "SP" and event.style ~= "MSG" then
        return string.format("{\\pos(%.1f,%.1f)\\an8}%s", current_x, current_y, clean_text)
    else
        return string.format("{\\pos(%.1f,%.1f)\\an7}%s", current_x, current_y, clean_text)
    end
end

function render(pos_arg)
    if COMMENTS == nil then return end

    local pos, err
    if pos_arg == nil then
        pos, err = mp.get_property_number('time-pos')
        if err ~= nil then
            return msg.error(err)
        end
    else
        pos = pos_arg
    end

    if not pos then
        overlay_low:remove()
        overlay_high:remove()
        return
    end

    local fontname = options.fontname
    local fontsize = options.fontsize
    local opacity = tonumber(options.opacity)
    local alpha = string.format("%02X", (1 - (opacity or 0)) * 255)

    local width, height = 1920, 1080
    local ratio = osd_width / osd_height
    if width / height < ratio then
        height = width / ratio
        fontsize = options.fontsize - ratio * 2
    end

    local ass_events_low = {}
    local ass_events_high = {}
    local max_display = math.max(options.scrolltime, options.fixtime)
    local window_start = pos - max_display

    -- 跳过已结束的弹幕
    local lo = binary_search(COMMENTS, window_start, function(item) return item.start_time end)

    local re_entity = "&#%d+;"
    local re_fs = "\\fs(%d+)"
    local ass_prefix = string.format("{\\rDefault\\fn%s\\fs%d\\c&HFFFFFF&\\alpha&H%s\\bord%s\\shad%s\\b%s\\q2}",
        fontname, fontsize, alpha, options.outline, options.shadow, options.bold and "1" or "0")

    for i = lo, #COMMENTS do
        local event = COMMENTS[i]
        if not event then break end

        if event.start_time > pos then break end  -- 后续弹幕提前退出
        if event.end_time >= pos then
            local text = realtime_position_text(event, pos, height * options.displayarea)
            if text then
                text = text:gsub(re_entity, "")
            end

            if text and text:match(re_fs) then
                text = text:gsub(re_fs, function(size)
                    local n = tonumber(size) or 0
                    return string.format("\\fs%d", math.floor(n * 1.5))
                end)
            end

            -- 构建 ASS 字符串
            local event_font_prefix = ""
            if event.font_size then
                local configured_size = tonumber(options.fontsize) or fontsize
                local adjusted_size = math.max(1, math.floor(event.font_size + fontsize - configured_size))
                event_font_prefix = string.format("{\\fs%d}", adjusted_size)
            end
            local ass_text = text and (ass_prefix .. event_font_prefix .. text)
            if ass_text then
                if event.layer == nil or tonumber(event.layer) == 0 then
                    table.insert(ass_events_low, ass_text)
                else
                    table.insert(ass_events_high, ass_text)
                end
            end
        end
    end

    -- 写入低层（滚动）和高层（顶/底）overlay，并设置 z 值以控制堆叠
    overlay_low.res_x = width
    overlay_low.res_y = height
    overlay_low.z = 0
    overlay_low.data = table.concat(ass_events_low, '\n')
    overlay_low:update()

    overlay_high.res_x = width
    overlay_high.res_y = height
    overlay_high.z = 1
    overlay_high.data = table.concat(ass_events_high, '\n')
    overlay_high:update()
end

local function time_pos_callback(_, time_pos)
    if time_pos then
        render(time_pos)
    else
        overlay_low:remove()
        overlay_high:remove()
    end
end

local function start_time_observer()
    if not time_pos_observer_active then
        mp.observe_property('time-pos', 'number', time_pos_callback)
        time_pos_observer_active = true
    end
end

local function stop_time_observer()
    if time_pos_observer_active then
        mp.unobserve_property(time_pos_callback)
        time_pos_observer_active = false
    end
end

function render_danmaku(from_menu, no_osd)
    if ENABLED and (from_menu or get_danmaku_visibility()) then
        if not no_osd then
            show_loaded(true)
        end
        toggle_danmaku_switch("on")
        show_danmaku_func()
    else
        show_message("")
        hide_danmaku_func()
    end
end

local function filter_state(label, name)
    local filters = mp.get_property_native("vf")
    for _, filter in pairs(filters) do
        if filter.label == label or filter.name == name
        or filter.params[name] ~= nil then
            return true
        end
    end
    return false
end

function show_danmaku_func()
    mp.set_property_bool(HAS_DANMAKU, true)
    set_danmaku_visibility(true)
    render()
    if not pause then
        start_time_observer()
    end
    if options.vf_fps then
        local display_fps = mp.get_property_number('display-fps')
        local video_fps = mp.get_property_number('estimated-vf-fps')
        if (display_fps and display_fps < 58) or (video_fps and video_fps > 58) then
            return
        end
        if not filter_state("danmaku", "fps") then
            mp.commandv("vf", "append", string.format("@danmaku:fps=fps=%s", options.fps))
        end
    end
end

function hide_danmaku_func()
    stop_time_observer()
    mp.set_property_bool(HAS_DANMAKU, false)
    set_danmaku_visibility(false)
    overlay_low:remove()
    overlay_high:remove()
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end
end


local message_overlay = mp.create_osd_overlay('ass-events')
-- 前向声明两个定时器：函数体要引用它们，必须让 local 声明先于函数定义（作用域要求）
local message_timer
local message_anim_timer
-- 唯一的共享状态表：仅存定时器回调无法通过参数获得的跨帧数据
local msg_state = {
    anim = nil,       -- "in" / "out" / nil
    t0 = 0,           -- 当前动画起始时刻
    text = "",        -- 显示内容
    shown = false,    -- 是否有可见内容
    an = 7,           -- 对齐方式
    dir = -1,         -- -1 从左进，1 从右进（右对齐配置镜像）
    x = 0, y = 0,     -- 目标定位
    cx = 0, ca = 0,   -- 当前帧位置/不透明度（0~255）
    fx = 0, fa = 255  -- 出场起点（中途取消的平滑衔接）
}
local SLIDE = 90

-- 渲染一帧：位置、透明度、文本、对齐全部由参数传入
local function render_message(x, y, alpha, text, an)
    -- （ASS 的 \alpha 语义与直觉相反，0 不透明 / 255 全透明，故 255-v 换算）
    local b = math.max(0, math.min(255, math.floor(alpha + 0.5)))
    local a = math.max(0, math.min(255, math.floor(255 - b + 0.5)))
    message_overlay.data = string.format("{\\an%d\\pos(%d,%d)\\alpha&H%02X&}%s",
        an, math.floor(x + 0.5), math.floor(y + 0.5), a, text)
    message_overlay:update()
end

-- 逐帧动画：进度、位置、透明度均为函数内局部量，最后经参数传给渲染
local function anim_tick()
    if not msg_state.anim then
        message_anim_timer:kill()
        return
    end

    local ANIM_IN, ANIM_OUT = 0.28, 0.32
    local dur = (msg_state.anim == "in") and ANIM_IN or ANIM_OUT
    local t = (mp.get_time() - msg_state.t0) / dur
    local x, alpha
    if t >= 1 then
        if msg_state.anim == "in" then
            msg_state.anim, msg_state.shown = nil, true
            msg_state.cx, msg_state.ca = msg_state.x, 255
            render_message(msg_state.x, msg_state.y, 255, msg_state.text, msg_state.an)
            message_anim_timer:kill()
            message_timer:resume() -- 进入停留
        else
            msg_state.anim, msg_state.shown = nil, false
            message_anim_timer:kill()
            message_overlay:remove()
        end
        return
    end

    if msg_state.anim == "in" then
        -- 缓动曲线：入场先快后慢
        local p = 1 - (1 - t) ^ 3
        x = msg_state.x + msg_state.dir * SLIDE * (1 - p) -- 从左侧向右滑入
        alpha = 255 * p                                   -- 透明度 0 → 255
    else
        -- 缓动曲线：出场先慢后快
        local p = t ^ 3
        x = msg_state.fx + msg_state.dir * SLIDE * p      -- 向左滑出（从右往左消失）
        alpha = msg_state.fa * (1 - p)                    -- 透明度 → 0
    end
    msg_state.cx, msg_state.ca = x, alpha
    render_message(x, msg_state.y, alpha, msg_state.text, msg_state.an)
end

-- 出场：从当前帧位置平滑衔接（入场中途取消也不瞬移）
local function start_message_out()
    message_timer:kill()
    if msg_state.anim == "out" then return end

    if not msg_state.shown and msg_state.anim ~= "in" then
        -- 无可见内容：直接清除
        message_anim_timer:kill()
        msg_state.anim = nil
        message_overlay:remove()
        return
    end
    msg_state.fx = (msg_state.anim == "in") and msg_state.cx or msg_state.x
    msg_state.fa = (msg_state.anim == "in") and msg_state.ca or 255
    msg_state.anim, msg_state.t0 = "out", mp.get_time()
    message_anim_timer:kill()
    message_anim_timer:resume()
end

-- 创建定时器
message_timer = mp.add_timeout(3, start_message_out, true)
message_anim_timer = mp.add_periodic_timer(0.016, anim_tick, true)

function show_message(text, time)
    text = tostring(text or "")
    -- 清除类调用：空文本，或明确传入 <=0 的时间 → 出场动画
    if text == "" or (time and time <= 0) then
        start_message_out()
        return
    end

    message_timer.timeout = time or 3
    message_timer:kill()
    msg_state.an = math.floor(tonumber(options.message_anlignment) or 7)
    msg_state.x = math.floor(tonumber(options.message_x) or 0)
    msg_state.y = math.floor(tonumber(options.message_y) or 0)
    msg_state.dir = (msg_state.an == 3 or msg_state.an == 6 or msg_state.an == 9) and 1 or -1
    msg_state.text = text
    msg_state.shown = false

    local width, height = 1920, 1080
    local ratio = (osd_width and osd_height and osd_height > 0) and (osd_width / osd_height) or (16 / 9)
    if width / height < ratio then height = width / ratio end
    message_overlay.res_x = width
    message_overlay.res_y = height
    msg_state.cx, msg_state.ca = msg_state.x + msg_state.dir * SLIDE, 0
    render_message(msg_state.cx, msg_state.y, 0, msg_state.text, msg_state.an)
    msg_state.anim, msg_state.t0 = "in", mp.get_time()
    message_anim_timer:kill()
    message_anim_timer:resume()
end

mp.observe_property('osd-width', 'number', function(_, value) osd_width = value or osd_width end)
mp.observe_property('osd-height', 'number', function(_, value) osd_height = value or osd_height end)
mp.observe_property('pause', 'bool', function(_, value)
    if value ~= nil then
        pause = value
    end
    if ENABLED then
        if pause then
            stop_time_observer()
        elseif COMMENTS ~= nil then
            start_time_observer()
        end
    end
end)

mp.register_event('playback-restart', function(event)
    if event.error then
        return msg.error(event.error)
    end
    if ENABLED and COMMENTS ~= nil then
        render()
    end
end)

mp.add_hook("on_unload", 50, function()
    FALLBACK_TRIGGER, COMMENTS, DELAY = false, nil, 0
    stop_time_observer()
    overlay_low:remove()
    overlay_high:remove()
    mp.set_property_native(DELAY_PROPERTY, 0)
    if filter_state("danmaku") then
        mp.commandv("vf", "remove", "@danmaku")
    end

    local files_to_remove = {
        file1 = utils.join_path(DANMAKU_PATH, "temp-" .. PID .. ".mp4"),
    }

    if options.save_danmaku then
        save_danmaku(true)
    end

    for _, file in pairs(files_to_remove) do
        if file_exists(file) then
            os.remove(file)
        end
    end

    DANMAKU = {sources = {}, count = 1}
    mp.set_property_native(DANMAKU_COUNT, 0)
    mp.set_property_bool(HAS_DANMAKU, false)
end)

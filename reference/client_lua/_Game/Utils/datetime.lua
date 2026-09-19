local Database = require("_Game.Utils.Database")
local M = {}

-- 返回秒数，如东八区=3600*8=28800
function M.get_client_timezone(now)
    -- local now = os.time()
    local utc_date = os.date("!*t", now)
    local local_date = os.date("*t", now)
    -- 因本地没有夏令时，有反而会差一小时
    local_date.isdst = false
    local client_timezone = math.floor(os.difftime(os.time(local_date), os.time(utc_date)))
    return client_timezone
end

-- delay示例，如凌晨4点=3600*4=14400
function M.get_week(time, delay)
    local weeks = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
    time = time -- or os.time()
    delay = delay or 0
    local week = os.date("%a", time - delay)
    for i, v in ipairs(weeks) do
        if v == week then
            return i
        end
    end
    return 0
end

function M.str_to_time(str, date_format_for_match)
    date_format_for_match = date_format_for_match or "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = string.match(str, date_format_for_match)
    return os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
end

-- 是否已经通过时间戳
function M.pass_time(date, epoch_time)
    local epoch_time = epoch_time or os.time(os.date("!*t"))

    local date_time = date
    if type(date) == "string" then
        date_time = M.str_to_time(date)
    end

    return epoch_time > date_time
end

local FormatString = {
    [86400] = Database.L10n(293),
    [3600] = Database.L10n(476),
    [0] = Database.L10n(477),
}

function M.format_time(timeLength)
    local d = math.floor(timeLength / 86400)
    local h = math.floor((timeLength % 86400) / 3600)
    local m = math.floor((timeLength % 3600) / 60)

    if timeLength >= 86400 then
        return string.format(Database.L10n(293), d, h, m)
    elseif timeLength >= 3600 then
        return string.format(Database.L10n(476), h, m)
    else
        return string.format(Database.L10n(477), m)
    end
end

--只格式化月日
function M.formate_date(timestamp)
    local time = os.date("*t", timestamp)
    return string.format(Database.L10n(294), time.month, time.day)
end

return M

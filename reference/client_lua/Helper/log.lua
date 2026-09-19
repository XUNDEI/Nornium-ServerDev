local LuaFileLogger = require("Helper.LuaFileLogger")

LOG_LEVEL = 0
LOG_TO_FILE = true

local old_print = print
print = function(...)
    if LOG_LEVEL == 0 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[DEBUG] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
    end
end

function LOG_DEBUG(...)
    if LOG_LEVEL == 0 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[DEBUG] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
        end
    end
end

function LOG_DEBUG_TRACKBACK(...)
    if LOG_LEVEL == 0 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[DEBUG] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_VERBOSE(...)
    if LOG_LEVEL <= 1 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[VERBOSE] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
        end
    end
end

function LOG_VERBOSE_TRACKBACK(...)
    if LOG_LEVEL <= 1 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[VERBOSE] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_INFO(...)
    if LOG_LEVEL <= 2 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[INFO] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
        end
    end
end

function LOG_INFO_TRACKBACK(...)
    if LOG_LEVEL <= 2 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[INFO] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.Log(prefix, ...)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(prefix, ...)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_WARN(...)
    if LOG_LEVEL <= 3 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[WARNING] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogWarn(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogWarn(prefix, ...)
        end
    end
end

function LOG_WARN_TRACKBACK(...)
    if LOG_LEVEL <= 3 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[WARNING] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogWarn(prefix, ...)
        UnLua.LogWarn(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogWarn(prefix, ...)
            LuaFileLogger:GetInstance():LogWarn(debug.traceback())
        end
    end
end

function LOG_ERROR(...)
    if LOG_LEVEL <= 4 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[ERROR] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogError(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogError(prefix, ...)
        end
    end
end

function LOG_ERROR_TRACKBACK(...)
    if LOG_LEVEL <= 4 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[ERROR] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogError(prefix, ...)
        UnLua.LogError(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogError(prefix, ...)
            LuaFileLogger:GetInstance():LogError(debug.traceback())
        end
    end
end

function LOG_FATAL(...)
    if LOG_LEVEL <= 5 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[FATAL] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogError(prefix, ...)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogFatal(prefix, ...)
        end
    end
end

function LOG_FATAL_TRACKBACK(...)
    if LOG_LEVEL <= 5 then
        local info = debug.getinfo(2)
        local prefix = info and string.format("[FATAL] [%s:%d]", info.short_src, info.currentline) or ""
        UnLua.LogError(prefix, ...)
        UnLua.LogError(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogFatal(prefix, ...)
            LuaFileLogger:GetInstance():LogFatal(debug.traceback())
        end
    end
end

function LOG_FORMAT_DEBUG(fmt, ...)
    if LOG_LEVEL == 0 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[DEBUG] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
        end
    end
end

function LOG_FORMAT_DEBUG_TRACKBACK(fmt, ...)
    if LOG_LEVEL == 0 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[DEBUG] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_FORMAT_VERBOSE(fmt, ...)
    if LOG_LEVEL <= 1 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[VERBOSE] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
        end
    end
end

function LOG_FORMAT_VERBOSE_TRACKBACK(fmt, ...)
    if LOG_LEVEL <= 1 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[VERBOSE] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_FORMAT_INFO(fmt, ...)
    if LOG_LEVEL <= 2 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[INFO] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
        end
    end
end

function LOG_FORMAT_INFO_TRACKBACK(fmt, ...)
    if LOG_LEVEL <= 2 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[INFO] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.Log(msg)
        UnLua.Log(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():Log(msg)
            LuaFileLogger:GetInstance():Log(debug.traceback())
        end
    end
end

function LOG_FORMAT_WARN(fmt, ...)
    if LOG_LEVEL <= 3 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[WARNING] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogWarn(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogWarn(msg)
        end
    end
end

function LOG_FORMAT_WARN_TRACKBACK(fmt, ...)
    if LOG_LEVEL <= 3 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[WARNING] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogWarn(msg)
        UnLua.LogWarn(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogWarn(msg)
            LuaFileLogger:GetInstance():LogWarn(debug.traceback())
        end
    end
end

function LOG_FORMAT_ERROR(fmt, ...)
    if LOG_LEVEL <= 4 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[ERROR] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogError(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogError(msg)
        end
    end
end

function LOG_FORMAT_ERROR_TRACKBACK(fmt, ...)
    if LOG_LEVEL <= 4 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[ERROR] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogError(msg)
        UnLua.LogError(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogError(msg)
            LuaFileLogger:GetInstance():LogError(debug.traceback())
        end
    end
end

function LOG_FORMAT_FATAL(fmt, ...)
    if LOG_LEVEL <= 5 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[FATAL] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogError(msg)
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogFatal(msg)
        end
    end
end

function LOG_FORMAT_FATAL_TRACKBACK(fmt, ...)
    if LOG_LEVEL <= 5 then
        local msg = string.format(fmt, ...)
        local info = debug.getinfo(2)
        if info then
            msg = string.format("[FATAL] [%s:%d] %s", info.short_src, info.currentline, msg)
        end
        UnLua.LogError(msg)
        UnLua.LogError(debug.traceback())
        if LOG_TO_FILE then
            LuaFileLogger:GetInstance():LogFatal(msg)
            LuaFileLogger:GetInstance():LogFatal(debug.traceback())
        end
    end
end

---@class LuaFileLogger : Singleton
---@field GetInstance  fun():LuaFileLogger
local LuaFileLogger = BaseClass("LuaFileLogger", Singleton)

function LuaFileLogger:__init()
    local saveDir = UE.UBlueprintPathsLibrary.ProjectSavedDir()
    local saveFilePath = UE.UBlueprintPathsLibrary.Combine({ saveDir, "lua.log" })

    UnLua.Log("open", saveFilePath)

    self.logFile = io.open(saveFilePath, "w+")

    self.warningAndErrors = ""
end

function LuaFileLogger:__delete()
    io.close(self.logFile)
end

-- 这玩意是个变长的 我好像没办法写个参数把warning和log合一起
function LuaFileLogger:LogWarn(...)
    local log = SafePack(...)

    for i = 1, log.n do
        log[i] = tostring(log[i])
        self.warningAndErrors = self.warningAndErrors .. log[i]
    end
    self.warningAndErrors = self.warningAndErrors .. "\n"

    self.logFile:write(SafeUnpack(log))
    self.logFile:write("\n")
end

LuaFileLogger.LogError = LuaFileLogger.LogWarn
LuaFileLogger.LogFatal = LuaFileLogger.LogWarn

function LuaFileLogger:Log(...)
    local log = SafePack(...)

    for i = 1, log.n do
        log[i] = tostring(log[i])
    end

    self.logFile:write(SafeUnpack(log))
    self.logFile:write("\n")
end

return LuaFileLogger

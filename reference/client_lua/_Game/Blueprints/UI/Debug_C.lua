local SrpgController = require("Module.Srpg.SrpgController")
local LuaFileLogger = require("Helper.LuaFileLogger")
local Client = require "Network.Client"

---@type Debug_C
local M = UnLua.Class()

function M:SetUp()
    self.Run.OnClicked:Add(self, function()
        self:RunCommand()
    end)
    self.Command.OnTextCommitted:Add(self, function()
        self:RunCommand()
    end)
    self.ShowError.OnClicked:Add(self, function()
        self.Output:SetText(LuaFileLogger:GetInstance().warningAndErrors)
    end)

    self.Exit.OnClicked:Add(self, function()
        UIManager:GetInstance():RemoveUI(self)
    end)

    self.Output:SetText(LuaFileLogger:GetInstance().warningAndErrors)
end

function M:ShowSrpgEvents()
    return table.dump(SrpgController:GetInstance().model.pendingEvents, false, 10)
end

function M:ShowNetInfo()
    return table.dump(Client.debug())
end

M.Commands = {
    ["show events"] = M.ShowSrpgEvents,
    ["show sendcache"] = M.ShowNetInfo,
}

function M:RunCommand()
    local command = self.Command:GetText()
    LOG_INFO(command, M.Commands[command])
    if M.Commands[command] then
        local log = M.Commands[command](self)

        self.Output:SetText(log)
        LOG_INFO(log)
    end
end

return M

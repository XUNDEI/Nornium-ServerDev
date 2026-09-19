--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_Reconnect_C
local M = UnLua.Class()

function M:Construct()
    self.HideCursor = true
end

function M:StartReconnect(DefaultTip, ReconnectTip)
    self.Overridden.StartReconnect(self, DefaultTip, ReconnectTip)
    local Client = require "Network.Client"
    Client.tick_for_reconnect = function()
        if UE.UKismetSystemLibrary.IsValid(self) then
            self:Reconnect()
        else
            Client.tick_for_reconnect = nil
            Client.tick_for_reconnect_elapsed = nil
        end
    end
end

return M

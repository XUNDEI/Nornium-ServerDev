local Database = require("_Game.Utils.Database")
local PlayerSystem = require("Module.Player.PlayerSystem")
local datetime = require("_Game.Utils.datetime")

---@type UI_Activity_Base
local M = UnLua.Class()

function M:RefreshUI()
    local config = Database.Query("d_activity", self.activityId)
    local startTime = datetime.str_to_time(config.showTime)
    local endTime = datetime.str_to_time(config.closeTime)
    local timeLeft = endTime - PlayerSystem:GetInstance():GetServerTime()

    if self.TimeLeft then
        self.TimeLeft:SetText(datetime.format_time(timeLeft))
    end

    if self.Date then
        self.Date:SetText(string.format("%s - %s", datetime.formate_date(startTime - 14401), datetime.formate_date(endTime - 14401)))
    end
end

return M

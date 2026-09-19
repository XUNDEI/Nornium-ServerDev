local UIUtils = require("_Game.Utils.UIUtils")
local Database = require('_Game.Utils.Database')
local datetime = require("_Game.Utils.datetime")
local PlayerSystem = require("Module.Player.PlayerSystem")

---@type UI_Activity_CharTrain_C
local M = UnLua.Class()

local ITEMS = {
    9001,
    1200002,
    1202025,
    1202031,
    1202037
}

function M:RefreshUI()
    self.Btn_Fight.OnClicked:Add(self, self.Open)

    local config = Database.Query("d_activity", 2)
    local endTime = datetime.str_to_time(config.closeTime)
    local timeLeft = endTime - PlayerSystem:GetInstance():GetServerTime()

    self.TimeLeft:SetText(datetime.format_time(timeLeft))

    self.Reward:ClearChildren()
    for _, id in ipairs(ITEMS) do
        local item = UIUtils.CreateItem(self, id)
        self.Reward:AddChild(item)
    end
end

function M:Open()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9010, '')
end

--end

return M

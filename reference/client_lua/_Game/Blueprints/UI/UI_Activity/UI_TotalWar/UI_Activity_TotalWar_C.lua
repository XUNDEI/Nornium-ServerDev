local Database = require('_Game.Utils.Database')
local datetime = require("_Game.Utils.datetime")
local PlayerSystem = require("Module.Player.PlayerSystem")

---@type UI_Activity_TotalWar_C
local M = UnLua.Class()

function M:Initialize()
    if not M.UI_BossRush_Main then
        M.UI_BossRush_Main = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_Main.UI_BossRush_Main_C')
        M.UI_BossRush_MainRef = UnLua.Ref(M.UI_BossRush_Main)
    end
end

function M:RefreshUI(activityId)
    self.Btn_Fight.OnClicked:Add(self, self.Open)

    local config = Database.Query("d_activity", activityId)
    LOG_INFO(activityId)
    local startTime = datetime.str_to_time(config.showTime)
    local endTime = datetime.str_to_time(config.closeTime)
    local timeLeft = endTime - PlayerSystem:GetInstance():GetServerTime()

    self.TimeLeft:SetText(datetime.format_time(timeLeft))
    self.Date:SetText(string.format("%s - %s", datetime.formate_date(startTime - 14401), datetime.formate_date(endTime - 14401)))
end

function M:Open()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9027) then
        local bossRushUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_Main)
    
        UIManager:GetInstance():AddUI(bossRushUI)
    
        bossRushUI:Setup()
    end 
end

--end

return M

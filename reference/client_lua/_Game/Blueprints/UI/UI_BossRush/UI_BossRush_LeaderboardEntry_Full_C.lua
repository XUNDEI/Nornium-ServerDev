local BossRushController = require("Module.BossRush.BossRushController")
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local UIUtils = require("_Game.Utils.UIUtils")
local Database = require("_Game.Utils.Database")

---@type UI_BossRush_LeaderboardEntry_Full_C
local M = UnLua.Class()

function M:Construct()
    M.UI_BossRush_LeaderboardEntry_BossInfo = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_LeaderboardEntry_BossInfo.UI_BossRush_LeaderboardEntry_BossInfo_C')
    M.UI_BossRush_LeaderboardEntry_BossInfoRef = UnLua.Ref(M.UI_BossRush_LeaderboardEntry_BossInfo)
end

---@param data LeaderboardEntryData_C
function M:OnListItemObjectSet(data)
    self.data = data

    local mainLeaderboardEntry = BossRushController:GetInstance():GetLeaderboard()[data.Rank]
    local recordIds = mainLeaderboardEntry.record_ids
    -- 先随便拿一个拿来拿用户信息，因为出分了所以一定至少有一条记录
    local record = BossRushController:GetInstance():GetRecord(recordIds[1])

    self.Name:SetText(record.player_name)
    self.UID:SetText(record.player_id)
    self.Score:SetText(BossRushUtils.FormatRichText(mainLeaderboardEntry.score))
    self.Rank:SetText(string.format(Database.L10n(450), data.Rank))

    -- 按顺序
    local bossIds = BossRushController:GetInstance():GetBoss()
    self.BossInfo:ClearChildren()
    for _, id in ipairs(bossIds) do
        if id ~= 0 then
            local bossRecord
            for _, recordId in ipairs(recordIds) do
                local record = BossRushController:GetInstance():GetRecord(recordId)
                if record.boss_id == id then
                    bossRecord = record
                    break
                end
            end

            if bossRecord then
                ---@type UI_BossRush_LeaderboardEntry_BossInfo_C
                local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_LeaderboardEntry_BossInfo)

                self.BossInfo:AddChild(entry)

                entry:Setup(bossRecord)
            end
        end
    end

    self.ToggleInfo.OnCheckStateChanged:Add(self, function(self, isOn)
        self.BossInfo:SetVisibility(isOn and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
        UE.UUserListEntryLibrary.GetOwningListView(self):BP_ScrollItemIntoView(self.data)
    end)

    self.ToggleInfo:SetIsCheckedAndFireEvent(false)
end

return M

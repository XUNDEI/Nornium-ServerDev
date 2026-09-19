local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
---@type UI_BossRush_Reward_C
local M = UnLua.Class()

local RANK_ICON_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/Icon_Reward_%d_png.Icon_Reward_%d_png'

function M:Setup(rankInfo)
    local rankIcon = LoadObject(string.format(RANK_ICON_PATH, rankInfo.id, rankInfo.id))

    self.Icon:SetBrush(UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(rankIcon, 0, 0))
    if rankInfo.endRank ~= 0 then
        self.Rank:SetText(string.format(Database.L10n(450), string.format("%s-%s", rankInfo.startRank, rankInfo.endRank)))
    else
        self.Rank:SetText(string.format(Database.L10n(450), string.format("%s+", rankInfo.startRank)))
    end

    for i = 1, #rankInfo.Reward, 3 do
        local id = rankInfo.Reward[i]
        local count = rankInfo.Reward[i + 2]

        ---@type UI_Get_Item_C
        local item = UIUtils.CreateItem(self, id, count, false)

        self.Reward:AddChild(item)
    end
end

return M

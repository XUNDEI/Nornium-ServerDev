local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local BossRushController = require("Module.BossRush.BossRushController")
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local d_bossrush_ranking = require "ClientDatas.d_bossrush_ranking"

---@type UI_GetItem_BossRush_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
    return UE.UWidgetBlueprintLibrary.Handled()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.Close)

local RANK_ICON_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/Icon_Reward_%d_png.Icon_Reward_%d_png'

---@param items ChangedItemInfo[]
function M:Setup(items)
    self.ImageBG.OnMouseButtonDownEvent:Bind(self, self.Close)

    local rank = BossRushController:GetInstance():GetRewardRank() or 0
    local score = BossRushController:GetInstance():GetRewardScore() or 0
    local rankId = 0

    for _, rankInfo in pairs(d_bossrush_ranking) do
        if rank >= rankInfo.startRank and (rankInfo.endRank == 0 or rank <= rankInfo.endRank) then
            rankId = rankInfo.id
        end
    end

    local rankIcon = LoadObject(string.format(RANK_ICON_PATH, rankId, rankId))
    self.RankIcon:SetBrush(UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(rankIcon, 0, 0))
    self.Rank:SetText(string.format("第%d名", rank))
    self.PlayerScore:SetText(BossRushUtils.FormatRichText(score))

    for _, itemInfo in ipairs(items) do
        local item = UIUtils.CreateItem(self, itemInfo.item_id, itemInfo.count, false)

        self.ItemBox:AddChild(item)
    end
    
    self:PlayAnimationForward(self.start, 1, false)
    self:PlayItemAnim()
end

return M

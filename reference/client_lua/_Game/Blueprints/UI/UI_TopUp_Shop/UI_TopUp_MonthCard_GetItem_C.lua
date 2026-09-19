--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local MallSystem = require "Module.ShopSystem.MallSystem"
local PlayerSystem = require "Module.Player.PlayerSystem"

---@type UI_TopUp_MonthCard_GetItem_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Close()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxquit, 1, false)
    self.ImageBG:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.Close)

function M:On_ImageBG_MouseButtonDown()
    self:Close()
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:RefreshUI(ItemList, callback)
    if ItemList then
        for _, item_info in pairs(ItemList) do
            local itemConfig = UIUtils.GetItemConfigById(item_info.item_id)
            if itemConfig then
                local item_ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
                item_ui.TextName:SetText(Database.L10n(itemConfig.itemName))
                item_ui.TextNum:SetText(item_info.count)
                --手动设置一下RenderOpacity 避免ui改动ItemPanel的RenderOpacity 导致出现获得物品又会先显示最后一个，然后再从第一个显示一遍
                item_ui.ItemPanel:SetRenderOpacity(0)
                --稀有度背景图片
                if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                    local strArr = string.split(itemConfig.rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        item_ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
    
                --icon
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        item_ui.icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                item_ui.Img_bg.OnMouseButtonDownEvent:Unbind()
                item_ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
                    if callback then
                        callback(item_info)
                    else
                        UIUtils.ShowItemInfo(item_info.config.id, item_info.count, item_info.arm_info)
                    end
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)

                local mall_infos = MallSystem:GetInstance().MallInfo
                local time = mall_infos.month_card_info.expire_seconds - PlayerSystem:GetInstance():GetServerTime()
                local day = math.floor(time / 24 / 60 / 60)
                local monthly_config = Database.Query("d_gacha_monthly_pass", 1007)
                if day > monthly_config.maxLasting then day = monthly_config.maxLasting end
                if day < 0 then day = 0 end
                self.TextDayCount:SetText(day)

                self.ItemBox:AddChild(item_ui)
                self:PlayAnimationForward(self.vfxin, 1, false)
                self:PlayItemAnim()
            end
        end
    end
end

return M

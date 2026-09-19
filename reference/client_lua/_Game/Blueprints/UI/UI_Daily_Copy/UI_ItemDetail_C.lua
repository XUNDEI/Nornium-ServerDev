--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_ItemDetail_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Construct()
    self:InitUI()
end

function M:InitUI()
    self.CloseBtn.OnClicked:Add(self, self.OnClicked_Image_Bg)
    --生成器
    self.List_GetWay.BP_OnEntryInitialized:Clear()
    self.List_GetWay.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.List_GetWay.BP_OnItemClicked:Clear()
    self.List_GetWay.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    --判断是在战斗创建
    local lvName = UE.UGameplayStatics.GetCurrentLevelName(self, true)
    
    self.title_getway:SetVisibility(lvName == 'FightMap' and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_GetWay:SetVisibility(lvName == 'FightMap' and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)

    self:PlayAnimationForward(self.vfxIn)
end

function M:RefreshUI(itemData, extrInfo)
    -- self.BackUI = beforeUI
    self.ExtrInfo = extrInfo --额外数据
    self.UI_Com_ItemBox:RefreshUI(itemData, false)
    self.UI_Com_ItemBox.GHSButtonLock:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.ListView_Attr:SetVisibility(UE.ESlateVisibility.Hidden)
    if itemData.config and itemData.config.itemType == UIUtils.ItemMainType.Weapon then
        local weaponSkillDesc = UIUtils.GetWeaponSkillDesc(itemData.item_id, 0)
        self.Text_Desc:SetText(weaponSkillDesc)
    else
        self.Text_Desc:SetText(itemData and Database.L10n(itemData.config.effectDesc) or "")
    end
    --来源处理
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --队列中排序(简单)
    self.ItemDataSource = {}

    self.List_GetWay:ClearListItems()
    

    local idx = 1
    self.List_GetWay:ClearListItems()
    if itemData.config.useLink and itemData.config.useLink ~= '' then
        local arrList = string.split(itemData.config.useLink, ',')
        for _, str in ipairs(arrList) do
            local linkId = tonumber(str)
            if linkId and linkId > 0 then
                local d_bag_item_link = require('ClientDatas.d_bag_item_link')
                local config = d_bag_item_link[linkId]
                if config then
                    local ItemData = NewObject(ItemClass)
                    ItemData.Index = idx
                    ItemData.ItemId = linkId
                    table.insert(self.ItemDataSource, ItemData)
                    idx = idx + 1
                end
            end
        end
    end
    self.List_GetWay:BP_SetListItems(self.ItemDataSource)
end

function M:OnClicked_Image_Bg()
    self:BindToAnimationFinished(self.vfxExit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxExit)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Image_Bg)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Image_Bg)

function M:BP_OnEntryInitialized(item, widget)
    local data = self.ItemDataSource[item.Index]
    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
    local config = d_bag_item_link[data.ItemId]

    widget.Text_Des:SetText(config and Database.L10n(config.desc) or '')
end

function M:BP_OnItemClicked(item)
    local data = self.ItemDataSource[item.Index]
    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
    local config = d_bag_item_link[tonumber(data.ItemId)]
    -- if config then
    --     if config.UI and config.UI ~= '' and self.BackUI then
    --         local className = string.lower(self.BackUI:GetClass():GetName())
    --         if string.endswith(className, "_c") then
    --             className = string.sub(className, 1, -3)
    --         end
    --         if string.lower(config.UI) == className then
    --             self:RemoveFromParent()
    --         end
    --     end
    -- end

    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- gameInstance:OpenLink(data.ItemId, '')
    -- self:RemoveFromParent()
end

return M

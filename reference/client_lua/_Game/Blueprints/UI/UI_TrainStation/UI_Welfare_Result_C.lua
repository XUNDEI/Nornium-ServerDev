require "UnLua"
require "Common.TableUtil"

local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local GachaSystem = require('Module.Gacha.GachaSystem')
local UIUtils = require('_Game.Utils.UIUtils')
local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')

---@type UI_Welfare_Result_C
local M = Class()


M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Construct()
    self:InitData()
    self:InitUI()
    NetworkMessageManager:GetInstance():AddListener('res_gacha_confirm', self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener('res_gacha_confirm', self)
end

function M:res_gacha_confirm(result, msgId, parsed_msg)
    -- print('--->res_gacha_confirm:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then
        UIManager:GetInstance():RemoveUI(self)
    end
end

function M:InitData()

end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Confirm.OnGHSClicked:Add(self, self.OnClicked_Btn_Confirm)

    --生成器
    self.ItemList.BP_OnEntryInitialized:Clear()
    self.ItemList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ItemList.BP_OnItemClicked:Clear()
    self.ItemList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
    self:PlayAnimationForward(self.vfxin)
end

function M:RefreshUI(gachaId, gachaInfo)
    -- print('---------gachaInfo:' .. tostring(table.dump(gachaInfo, nil, 10)))
    self.GachaId = gachaId

    local allCount = 0 
    if gachaInfo and gachaInfo.gacha_pending_record_infos then
        allCount = #gachaInfo.gacha_pending_record_infos
    end 
    self.Btn_Confirm:SetIsEnabled(allCount > 0)
    self.ItemList:ClearListItems()
    if allCount >= 10 then
        local startIndex = math.max(allCount - 9, 0)
        self.GachaItemList = {}
        for i = startIndex, allCount do
            table.insert(self.GachaItemList, gachaInfo.gacha_pending_record_infos[i])
        end
        --排序
        if #self.GachaItemList > 1 then
            table.sort(self.GachaItemList, function(a, b) 
                if a.gacha_item_type ~= b.gacha_item_type then
                    return a.gacha_item_rarity > b.gacha_item_rarity
                end
                if a.gacha_item_rarity ~= b.gacha_item_rarity then
                    return a.gacha_item_rarity > b.gacha_item_rarity
                end
                return false 
            end)
        end

        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        --队列中排序(简单)
        self.ItemDataSource = {}

        for i = 1, #self.GachaItemList do
            local ItemData = NewObject(ItemClass)
            ItemData.Index = i
            ItemData.ItemId = self.GachaItemList[i].gacha_item_id
            table.insert(self.ItemDataSource, ItemData)
        end
    
        self.ItemList:BP_SetListItems(self.ItemDataSource)
    end
end


function M:RefreshItemUI(itemUI, itemId, itemType)
    if itemUI then
        itemUI.ItemPanel:SetRenderOpacity(1)
       
        local itemConfig = UIUtils.GetItemConfigById(itemId)
        if itemConfig then
            --稀有度背景图片
            if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                local strArr = string.split(itemConfig.rarityPath, '/')
                local littePath = strArr[#strArr]
                local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
                local itemRarityPic = LoadObject(rarityPath)
                if itemRarityPic then
                    itemUI.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end

            if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                local strArr = string.split(itemConfig.iconPath, '/')
                local littePath = strArr[#strArr]
                local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    itemUI.icon_res:SetBrushFromAtlasInterface(iconRes)
                end
            end

            if itemConfig.rarity <= 6 then
                itemUI.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
            else
                itemUI.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            end

            local itemCount = 0
            if itemType == 1 then
                local charId = itemConfig.subParam[1]
                if charId and charId > 0 then
                    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
                    if charInfo then
                        itemCount = 1
                    else
                        itemCount = 0
                    end
                end
                
            else
                itemCount = UIUtils.GetItemCount(itemId)
            end
            
            if itemCount == 0 then
                itemUI.Img_New:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            else
                itemUI.Img_New:SetVisibility(UE.ESlateVisibility.Hidden)
            end
            
            itemUI.TextNum:SetText('')
            --道具名字
            itemUI.TextName:SetText(Database.L10n(itemConfig.itemName))
        end
    end
end

-------------------------------------------------------
--- UI Event
function M:OnClicked_Btn_Close()
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxquit)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)

function M:OnClicked_Btn_Confirm()
    GachaSystem:GetInstance():ReqGachaConfirm(self.GachaId, 10)
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.ItemId = item.ItemId
    local data = self.GachaItemList[item.Index]
    -- print('-----BP_OnEntryInitialized:' .. tostring(data.gacha_item_id))
    local gachaItemConfig = Database.Query('d_gacha_item', data.gacha_item_id)
    if gachaItemConfig and gachaItemConfig.itemid then
        self:RefreshItemUI(widget, gachaItemConfig.itemid, gachaItemConfig.itemType)
    end
end

function M:BP_OnItemClicked(item)
    local data = self.GachaItemList[item.Index]
    -- print('-----BP_OnItemClicked:' .. tostring(data.gacha_item_id))
    local gachaItemConfig = Database.Query('d_gacha_item', data.gacha_item_id)
    if gachaItemConfig and gachaItemConfig.itemid then
        UIUtils.ShowItemInfo(gachaItemConfig.itemid, 1, 20)
    end
end


return M

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
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    self.ShowInteractOptions = false
    self.HideCursor = false
end

function M:Destruct()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
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

function M:RefreshUI(gachaId, gachaInfo, gachaTypeInfo)
    -- print('---------gachaInfo:' .. tostring(table.dump(gachaInfo, nil, 10)))
    self.GachaId = gachaId
    self.GachaTypeInfo = gachaTypeInfo

    local paramsConfig2 = GachaSystem:GetInstance():GetGachaParamsById(2)
    self.GachaItemList = paramsConfig2.value

    self.Btn_Confirm:SetIsEnabled(false)

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --队列中排序(简单)
    self.ItemDataSource = {}

    for i = 1, #self.GachaItemList do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        ItemData.ItemId = self.GachaItemList[i]
        table.insert(self.ItemDataSource, ItemData)
    end
    self.ItemList:ClearListItems()
    self.ItemList:BP_SetListItems(self.ItemDataSource)
end

function M:RefreshItemUI(itemUI, itemId)
    if itemUI then
        local itemConfig = UIUtils.GetItemConfigById(itemId)
        if itemConfig then
            local charId = itemConfig.subParam[1]
            if charId and charId > 0 then
                local charConfig = Database.Query('d_character', charId)
                --元素类型
                if charConfig and charConfig.element then
                    local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/element_%s_s_png.element_%s_s_png",
                        charConfig.element, charConfig.element)
                    local iconObj = LoadObject(iconPath)
                    if iconObj then
                        -- ui.Image_Icon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                        itemUI.element:SetBrushFromAtlasInterface(iconObj)
                    end

                    --头像
                    if charConfig.headRes and charConfig.headRes ~= '' then
                        local HeadPath = UIUtils.GetCharacterHeadIcon(charConfig.id, charConfig.headRes)
                        local iconRes = LoadObject(HeadPath)
                        if iconRes then
                            itemUI.Head:SetBrushFromAtlasInterface(iconRes)
                        end
                    end
                end
            end
            
            -- if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            --     local strArr = string.split(itemConfig.rarityPath, '/')
            --     local littePath = strArr[#strArr]
            --     local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            --     local itemRarityPic = LoadObject(rarityPath)
            --     if itemRarityPic then
            --         itemUI.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            --     end
            -- end
         

            --道具名字
            itemUI.Text_Name:SetText(Database.L10n(itemConfig.itemName))

            --是否已拥有
            if itemConfig.subParam[1] then
                local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
                local bHave = charInfo and true or false
                itemUI.Have:SetVisibility(bHave and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            else
                itemUI.Have:SetVisibility(UE.ESlateVisibility.Hidden)
            end
            itemUI.On:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
end

function M:RefreshItemSelected(ui, bIsSelected)
    ui.On:SetVisibility(bIsSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

-------------------------------------------------------
--- UI Event
function M:OnClicked_Btn_Close()
    self:BindToAnimationFinished(self.vfxout, function()
        UIManager:GetInstance():RemoveUI(self)
    end)
    self:PlayAnimationForward(self.vfxout)
   
end

function M:OnClicked_Btn_Confirm()
    if not self.Btn_Confirm.bIsEnabled then return end
    if self.SelectedItemIndex and self.SelectedItemIndex > 0 then
        GachaSystem:GetInstance():ReqGachaChooseCard(self.GachaId, self.SelectedItemIndex)
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Confirm)

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    widget.RoleId = item.ItemId
    local gacha_item_id = self.GachaItemList[item.Index]
    -- print('-----BP_OnEntryInitialized:' .. tostring(gacha_item_id))
    local gachaItemConfig = Database.Query('d_gacha_item', gacha_item_id)
    if gachaItemConfig and gachaItemConfig.itemid then
        self:RefreshItemUI(widget, gachaItemConfig.itemid)
    end
end

function M:BP_OnItemClicked(item)
    local gacha_item_id = self.GachaItemList[item.Index]
    -- print('-----BP_OnItemClicked:' .. tostring(gacha_item_id))
    if self.SelectedItemId ~= gacha_item_id then
        local widgets = self.ItemList:GetDisplayedEntryWidgets()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.RoleId == self.SelectedItemId then
                self:RefreshItemSelected(widget, false)
            end
            if widget.RoleId == gacha_item_id then
                self:RefreshItemSelected(widget, true)
            end
        end
        self.SelectedItemId = gacha_item_id
        self.SelectedItemIndex = item.Index
        --判定次数是否够
        local paramsConfig1 = GachaSystem:GetInstance():GetGachaParamsById(1)
        self.Btn_Confirm:SetIsEnabled(self.GachaTypeInfo.choose_times == 0 and self.GachaTypeInfo.total_times >= paramsConfig1.value2)
    else
        local gachaItemConfig = Database.Query('d_gacha_item', gacha_item_id)
        if gachaItemConfig and gachaItemConfig.itemid then
            UIUtils.ShowItemInfo(gachaItemConfig.itemid, 1, 20)
        end
    end
end

return M

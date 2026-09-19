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

---@type UI_GetEquip_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}
function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.Close)

function M:Construct()
    self.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized(item, widget)
    end)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:RefreshUI(equipData)
    if equipData then
        local d_bag_item_equip = require("ClientDatas.d_bag_item_equip")
        local item_info = d_bag_item_equip[equipData.item_id]
        self.name:SetText(Database.L10n(item_info.itemName))
        if item_info.rarityPath and item_info.rarityPath ~= '' then
            local strArr = string.split(item_info.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                self.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if item_info.iconPath and item_info.iconPath ~= '' then
            local strArr = string.split(item_info.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', item_info.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                self.icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end

        --星级
        local star = item_info.rarity
        if star <= 6 then
            for i = 1, 6 do
                if i <= star then
                    self["Rarity" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                else
                    self["Rarity" .. i]:SetVisibility(UE.ESlateVisibility.Hidden)
                end
            end
            -- self.Effect:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            for i = 1, 6 do
                self["Rarity" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
            end
            -- self.Effect:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        local baseAttr = UIUtils.GetEquipAttr(equipData)
        local ItemDataSource = {}
        local d_attributes = require("ClientDatas.d_attributes")
        self.CurItemDataList = {}
        for id, value in pairs(baseAttr) do
            local attr = {
                attrId = id,
                attrValue = value,
                attrUp = 0,
                config = d_attributes[id]
            }
            table.insert(self.CurItemDataList, attr)
        end

        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        for i = 1, #self.CurItemDataList do
            local ItemData = UE.UWidgetBlueprintLibrary.Create(self, ItemClass)
            ItemData.Index = i
            ItemData.ItemId = self.CurItemDataList[i].item_id
            table.insert(ItemDataSource, ItemData)
        end

        self.ListView_Attr:ClearListItems()
        self.ListView_Attr:BP_SetListItems(ItemDataSource)

        self.Rune:ClearChildren()
        local d_equip_rune = require("ClientDatas.d_equip_rune")
        for index, arm_rune_info in ipairs(equipData.arm_info.arm_rune_infos) do
            local rune_id = arm_rune_info.rune_id
            local ui = UE.UWidgetBlueprintLibrary.Create(self,
                UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Equip/UI_Attr_Rune_Item.UI_Attr_Rune_Item_C"))
            local rune_info = d_equip_rune[rune_id]

            ui.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
                self:BP_OnEntryInitialized_Rune(item, widget)
            end)
            ui.GHSButton:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            -- ui.GHSButton.OnGHSClicked:Add(self, function()
            --     local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Rune_Overview')
            --     ui:InitUI()
            -- end)
            if rune_info then
                local runeAttrs = UIUtils.GetRuneAttr(rune_id, equipData, index)
                ui.Index_Text:SetText(index .. '#')
                ui.Name_Text:SetText(Database.L10n(rune_info.runeName))
                local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
                local ItemDataSource = {}
                for i = 1, #runeAttrs do
                    local ItemClass = UE.UClass.Load(ItemSourcePath)
                    local AttrItem = UE.UWidgetBlueprintLibrary.Create(self, ItemClass)
                    AttrItem.Item_data = runeAttrs[i]
                    AttrItem.Index = i
                    table.insert(ItemDataSource, AttrItem)
                end

                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    ui.RuneImage:SetBrushFromAtlasInterface(itemRarityPic)
                end
                ui.ListView_Attr:ClearListItems()
                ui.ListView_Attr:BP_SetListItems(ItemDataSource)
            end
            self.Rune:AddChild(ui)
        end
    end
    self:PlayAnimationForward(self.Start, 1, false)
end

function M:BP_OnEntryInitialized(item, widget)
    local attrInfo = self.CurItemDataList[item.Index]
    --背景图片
    widget.Img_Bg:SetVisibility((item.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        widget.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    widget.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))
    if attrInfo.config.types == UIUtils.AttributeType.AbsoluteValue then
        local attrValue = math.floor((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
        widget.Text_NextValue:SetText(attrValue)
    else
        local attrValue = string.format("%.1f", (attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        widget.Text_NextValue:SetText(string.format('%s%%', attrValue))
    end
end

function M:BP_OnEntryInitialized_Rune(item, widget)
    local attrInfo = item.Item_data
    --背景图片
    widget.Img_Bg:SetVisibility((item.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        widget.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end

    widget.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))
    if attrInfo.config.types == UIUtils.AttributeType.AbsoluteValue then
        local attrValue = math.floor((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
        widget.Text_NextValue:SetText(attrValue)
    else
        local attrValue = string.format("%.1f", (attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        widget.Text_NextValue:SetText(string.format('%s%%', attrValue))
    end
end

return M

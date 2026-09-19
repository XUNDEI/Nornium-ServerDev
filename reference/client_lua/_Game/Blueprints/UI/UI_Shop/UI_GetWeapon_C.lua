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

---@type UI_GetWeapon_C
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

function M:RefreshUI(weaponDatas)
    local count = #weaponDatas
    if count > 0 then
        local weaponData = weaponDatas[1]
        local item_info = weaponData.config
        self.name:SetText(Database.L10n(item_info.itemName))
        local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/weapons_%s_png.weapons_%s_png", item_info.subType, item_info.subType)
        local iconObj = LoadObject(iconPath)
        if iconObj then
            self.ImageIcon:SetVisibility(UE.ESlateVisibility.Visible)
            self.ImageIcon:SetBrushFromAtlasInterface(iconObj)
        end

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
                self["Rarity" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
            end
            -- self.Effect:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            for i = 1, 6 do
                self["Rarity" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
            end
            -- self.Effect:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        local lv, _ = UIUtils.GetWeaponLevel(weaponData.item_id, weaponData.weapon_info.break_times,
            weaponData.weapon_info.exp)
        local baseAttr = UIUtils.GetWeaponAttr(weaponData.item_id, lv, weaponData.weapon_info.break_times)
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

        local weaponSkillDesc = UIUtils.GetWeaponSkillDesc(weaponData.item_id, weaponData.weapon_info.refine_level)
        self.WeaponSkillDes:SetText(weaponSkillDesc)

        self.ListView_Attr:ClearListItems()
        self.ListView_Attr:BP_SetListItems(ItemDataSource)
    end
    self:PlayAnimationForward(self.start, 1, false)
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
        local attrValue = math.floor((attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        widget.Text_NextValue:SetText(string.format('%d%%', attrValue))
    end
end

return M

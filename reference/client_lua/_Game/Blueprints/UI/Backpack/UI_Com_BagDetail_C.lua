require "UnLua"
require "Common.TableUtil"
local Database = require "_Game.Utils.Database"
local UIUtils = require "_Game.Utils.UIUtils"

---@type UI_Com_BagDetail_C
local M = Class()

--构造函数
function M:Construct()
    self:InitData()
    self:InitUI()
end

function M:Destruct()
   
end

function M:InitData()

end

function M:InitUI()
    self.mainType = 0
    self.Btn_Use.OnGHSClicked:Add(self, self.OnClicked_Btn_Use)
    self.Btn_Replace.OnGHSClicked:Add(self, self.OnClicked_Btn_Replace)
    self.Btn_Refine.OnGHSClicked:Add(self, self.OnClicked_Btn_Refine)
    self.Btn_Level.OnGHSClicked:Add(self, self.OnClicked_Btn_Level)
    --self.Btn_Break.OnGHSClicked:Add(self, self.OnClicked_Btn_Break)

    --生成器
    self.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.ListView_Attr.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
end

function M:RefreshUI(data, isBackpack, parentUI)
    self.BackUI = parentUI
    self.ItemData = data
    --品牌
    if not data.config then
        data.config = UIUtils.GetItemConfigById(data.item_id)
    end

    self.mainType = data.config.itemType
    self.subType = data.config.subType
    local isWeapon = self.mainType == UIUtils.ItemMainType.Weapon
    local isEquip = self.mainType == UIUtils.ItemMainType.Equip
    local canUse = self.mainType == UIUtils.ItemMainType.TempProp and (self.subType == UIUtils.ItemTempPropType.Consume or self.subType == UIUtils.ItemTempPropType.CharCard or self.subType == UIUtils.ItemTempPropType.BluePrint or self.subType == UIUtils.ItemTempPropType.ForgeBP)
    canUse = canUse or (self.mainType == UIUtils.ItemMainType.Skin) 

    self.Btn_Use:SetVisibility(canUse and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.Btn_Replace:SetVisibility((not isBackpack and (isWeapon or isEquip)) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    self.Btn_Refine:SetVisibility(isWeapon and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.Btn_Discharge:SetVisibility(UE.ESlateVisibility.Hidden)
    --self.Btn_Level:SetVisibility((isWeapon or isEquip) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    local levelupStr = Database.L10n(320)
    self.Text_Level:SetText(levelupStr)
    self.Text_Level_short:SetText(levelupStr)
    self.ListView_Attr:ClearListItems()
   
    --强化
    if isWeapon or isEquip then
        if isWeapon then
            self.CurItemDataList = {}
            local lv, _ = UIUtils.GetWeaponLevel(data.item_id, data.weapon_info.break_times, data.weapon_info.exp)
            local baseAttr = UIUtils.GetWeaponAttr(data.item_id, lv, data.weapon_info.break_times)
            --队列中排序(简单)
            self.ItemDataSource = {}
            local d_attributes = require("ClientDatas.d_attributes")
            for id, value in pairs(baseAttr) do 
                local attr = {
                    attrId = id,
                    attrValue = value,
                    attrUp = 0,
                    config = d_attributes[id]
                }
                table.insert(self.CurItemDataList, attr)
            end

            --武器功能按钮
            local isFullBreak = false
            local isFullLevel = false
            local isFullRefine = false
            local maxLv = UIUtils.GetWeaponMaxLevel(data.item_id, data.weapon_info.break_times)
            if lv == maxLv then
                isFullLevel = true
            end
            isFullRefine = data.weapon_info.refine_level == UIUtils.GetWeaponMaxRefineLevel(data.item_id)
            isFullBreak = data.weapon_info.break_times == UIUtils.GetWeaponMaxBreakTimes(data.item_id)

            self.btn_short:SetVisibility(UE.ESlateVisibility.Visible)
            self.Btn_Level:SetVisibility(UE.ESlateVisibility.Visible)
            self.Btn_Refine:SetVisibility(UE.ESlateVisibility.Visible)
            if isFullRefine and isFullBreak and isFullLevel then
                self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
                self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
                self.Btn_Refine:SetVisibility(UE.ESlateVisibility.Collapsed)
            elseif isFullRefine then
                self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
                self.Btn_Refine:SetVisibility(UE.ESlateVisibility.Collapsed)
            elseif isFullBreak and isFullLevel then
                self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
                self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
            else
                self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
                self.Btn_Refine:SetVisibility(UE.ESlateVisibility.Collapsed)
            end
            --未满突破且满级了，该突破一下
            if not isFullBreak and isFullLevel then
                self.Text_Level_short:SetVisibility(UE.ESlateVisibility.Hidden)
                self.Text_Level_short_break:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            else
                self.Text_Level_short:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                self.Text_Level_short_break:SetVisibility(UE.ESlateVisibility.Hidden)
            end

            --描述
            local weaponSkillDesc = UIUtils.GetWeaponSkillDesc(data.item_id, data.weapon_info.refine_level)
            self.WeaponSkillDes:SetText(weaponSkillDesc)
            self.WeaponSkillDes:SetVisibility(UE.ESlateVisibility.Visible)
            self.RunePanel:SetVisibility(UE.ESlateVisibility.Collapsed)
        else
            self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
            self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
            self.CurItemDataList = {}
            local baseAttr = UIUtils.GetEquipAttr(data)
            --队列中排序(简单)
            self.ItemDataSource = {}
            local d_attributes = require("ClientDatas.d_attributes")

            for id, value in pairs(baseAttr) do 
                local attr = {
                    attrId = id,
                    attrValue = value,
                    attrUp = 0,
                    config = d_attributes[id]
                }
                table.insert(self.CurItemDataList, attr)
            end

            if #self.CurItemDataList > 2 then
                table.sort(self.CurItemDataList, function(a, b)
                    if a.config.showOrder == 0 and b.config.showOrder == 0 then
                        return a.config.id < b.config.id
                    elseif a.config.showOrder == 0 then
                        return false
                    elseif b.config.showOrder == 0 then
                        return true
                    else
                        return a.config.showOrder < b.config.showOrder
                    end
                end)
            end

            --符文属性
            self.Rune:ClearChildren()
            local d_equip_rune = require("ClientDatas.d_equip_rune")
            for index, arm_rune_info in ipairs(data.arm_info.arm_rune_infos) do
                local rune_id = arm_rune_info.rune_id
                local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Equip/UI_Attr_Rune_Item.UI_Attr_Rune_Item_C"))
                local rune_info = d_equip_rune[rune_id]

                ui.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
                    self:BP_OnEntryInitialized_Attr(item, widget)
                end)
                ui.GHSButton.OnGHSClicked:Add(self, function() 
                    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Rune_Overview')
                    ui:InitUI(rune_id)
                end)
                if rune_info then
                    local runeAttrs = UIUtils.GetRuneAttr(rune_id, data, index)
                    ui.Index_Text:SetText(index .. '#')
                    ui.Name_Text:SetText(Database.L10n(rune_info.runeName))
                    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
                    local ItemDataSource = {}

                    if #runeAttrs > 2 then
                        table.sort(runeAttrs, function(a, b)
                            if a.config.showOrder == 0 and b.config.showOrder == 0 then
                                return a.config.id < b.config.id
                            elseif a.config.showOrder == 0 then
                                return true
                            elseif b.config.showOrder == 0 then
                                return false
                            else
                                return a.config.showOrder < b.config.showOrder
                            end
                        end)
                    end

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
            self.WeaponSkillDes:SetVisibility(UE.ESlateVisibility.Collapsed)
            self.RunePanel:SetVisibility(UE.ESlateVisibility.Visible)
        end

        local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
        local ItemClass = UE.UClass.Load(ItemSourcePath)
        for i = 1, #self.CurItemDataList do
            local ItemData = UE.UWidgetBlueprintLibrary.Create(self, ItemClass)
            ItemData.Index = i
            ItemData.ItemId = self.CurItemDataList[i].item_id
            table.insert(self.ItemDataSource, ItemData)
        end
        self.ListView_Attr:BP_SetListItems(self.ItemDataSource)
    else
        self.WeaponSkillDes:SetText(data.config and Database.L10n(data.config.effectDesc) or "")
        self.WeaponSkillDes:SetVisibility(UE.ESlateVisibility.Visible)
        self.RunePanel:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    --来源 9003,9005
    self.VBox_Source:ClearChildren()
    print('----来源:' .. tostring(data.config.useLink))
    if data.config.useLink and data.config.useLink ~= '' then
        local arrList = string.split(data.config.useLink, ',')
        for _, str in ipairs(arrList) do
            local linkId = tonumber(str)
            if linkId and linkId > 0 then
                local d_bag_item_link = require('ClientDatas.d_bag_item_link')
                local config = d_bag_item_link[linkId]
                if config then
                    local itemUI = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Backpack/UI_SourceItem.UI_SourceItem_C"))
                    itemUI.Text_Des:SetText(Database.L10n(config.desc))
                    itemUI.Btn_Normal.OnClicked:Add(self, function()
                        -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                        -- gameInstance:OpenLink(linkId, '')
                    end)
                    self.VBox_Source:AddChild(itemUI)
                end
            end
        end
    end

    self:RebuildButtonList()
end

function M:RefreshTag(index)
    self.WidgetSwitcher:SetActiveWidgetIndex(index)
end

function M:RefreshCompareState(is_old)
    if is_old then
        self.btn_short:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.Btn_Replace:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.Btn_Refine:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.Btn_Level:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:RefreshReplacePanel(is_equip)
    if is_equip then
        self.Text_Replace:SetText(Database.L10n(321))
        self.Btn_Replace:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
    else
        self.Text_Replace:SetText(Database.L10n(322))
        self.Btn_Replace:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:RefreshDischargePanel(is_equip)
    if is_equip then
        self.Btn_Discharge:SetVisibility(UE.ESlateVisibility.Visible)
        self.Btn_Replace:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Btn_Discharge:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Btn_Replace:SetVisibility(UE.ESlateVisibility.Visible)
    end
    self:RebuildButtonList()
end

function M:RebuildButtonList()
    local index = 0 
    local childs = self.Panel_Op:GetAllChildren()
    for i = childs:Length(), 1, -1 do 
        local widget = childs:Get(i)
        if widget:IsVisible() then
            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget):SetPosition(UE.FVector2D(10, 100 - index * 90))
            index = index + 1
        end
    end
end

function M:OnShowLevelUpEnd()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    --获取控制器组件
    if controller and controller.BP_PlayerController_City_UniverseBridge then
        if controller.BP_PlayerController_City_UniverseBridge.OnShowLevelUpEnd then
            controller.BP_PlayerController_City_UniverseBridge.OnShowLevelUpEnd:Clear()
        end
    end

    local isWeapon = self.mainType == UIUtils.ItemMainType.Weapon
    local isEquip = self.mainType == UIUtils.ItemMainType.Equip

    local uiTag = isWeapon and "Weapon" or "Equip"
    local gameInstance = UE4.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9016) then
        local itemInfo = isWeapon and self.ItemData.weapon_info or self.ItemData.arm_info
        local ui = gameInstance:GetUMG('UI_Panel_LevelUp')
        ui:SetIsFromBackpack(true)
        ui:SetBackUI(self.BackUI, uiTag, self.ItemData.item_uuid, self.ItemData.item_id, itemInfo.break_times, itemInfo.exp)
    end
end

function M:CanUseItem()
    if self.mainType == UIUtils.ItemMainType.Skin then
        if self.subType == UIUtils.ESkinSubType.Char then
            local charSkinId = self.ItemData.config.subParam[1]
            local citySkinId = self.ItemData.config.subParam[2]
            if not charSkinId or not citySkinId then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ',subParam个数不是2!' .. ',需要charSkinId:' .. tostring(charSkinId) .. ",citySkinId:" .. tostring(citySkinId))
                return false
            end
            local d_char_clothes = require('ClientDatas.d_char_clothes')
            local charSkinConfig = d_char_clothes[charSkinId]
            local citySkinConfig = d_char_clothes[citySkinId]
            if not charSkinConfig or not citySkinConfig then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ',no charSkinId:' .. tostring(charSkinId) .. " or citySkinId:" .. tostring(citySkinId))
                return false
            end
            if charSkinConfig.charBelong ~= citySkinConfig.charBelong then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ',charSkinId.charBelong:' .. tostring(charSkinConfig.charBelong) .. " ~= citySkinId.charBelong:" .. tostring(citySkinConfig.charBelong))
                return false
            end
            -- if charSkinConfig.dressInitial == 1 or citySkinConfig.dressInitial == 1 then
            --     UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ',charSkinId.dressInitial:' .. tostring(charSkinConfig.dressInitial) .. " ~= citySkinId.dressInitial:" .. tostring(citySkinConfig.dressInitial))
            --     return false
            -- end
            local CharacterSystem = require('Module.CharacterSystem.CharacterSystem')
            local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charSkinConfig.charBelong)
            if not charInfo then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ', 你还未拥有角色:' .. tostring(charSkinConfig.charBelong))
                return false 
            end
            local bFind = false
            for _, dressId in pairs(charInfo.own_character_skin_ids) do
                if dressId == charSkinId then
                    bFind = true
                    break
                end
            end
            if bFind then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ', 角色已解锁此战斗皮肤:' .. tostring(charSkinId))
                return false 
            end
            bFind = false
            for _, dressId in pairs(charInfo.own_city_skin_ids) do
                if dressId == charSkinId then
                    bFind = true
                    break
                end
            end
            if bFind then
                UIUtils.ShowNotify(self, '--道具:' .. tostring(self.ItemData.config.id) .. ', 角色已解锁此主城皮肤:' .. tostring(citySkinId))
                return false 
            end

            --判断角色是否已经解锁过了
        elseif self.subType == UIUtils.ESkinSubType.Mecha then

        end
    end
    return true
end

----------------------------------------------------------------------
---ui event
function M:OnClicked_Btn_Use()
    --检测道具能否使用
    if self:CanUseItem() then
        local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Com_UseWindow')
        ui:RefreshUI(self.ItemData)
    end
end

function M:OnClicked_Btn_Replace()
    
end

function M:OnClicked_Btn_Refine()

end

function M:OnClicked_Btn_Level()

end

function M:OnClicked_Btn_Break()

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
    local isHundred = false
    if attrInfo.config.types == UIUtils.AttributeType.OverAHundred or 
        attrInfo.config.types == UIUtils.AttributeType.InAHundred then
        isHundred = true
    end
    local attrValue = isHundred and string.format("%.1f", attrInfo.attrValue * 100) or string.format("%d", math.modf(attrInfo.attrValue))
    widget.Text_NextValue:SetText((isHundred and (attrValue .. '%') or attrValue))
end

function M:BP_OnEntryInitialized_Attr(item, widget)
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
    local isHundred = false
    if attrInfo.config.types == UIUtils.AttributeType.OverAHundred or 
        attrInfo.config.types == UIUtils.AttributeType.InAHundred then
        isHundred = true
    end
    local attrValue = isHundred and string.format("%.1f", attrInfo.attrValue * 100) or string.format("%d", math.modf(attrInfo.attrValue))
    widget.Text_NextValue:SetText((isHundred and (attrValue .. '%') or attrValue))
end

function M:BP_OnItemClicked(wbp, item)

end

return M

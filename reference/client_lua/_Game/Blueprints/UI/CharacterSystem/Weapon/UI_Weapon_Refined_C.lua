--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local Protos = require("Helper.Protos")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local PlayerSystem = require("Module.Player.PlayerSystem")

---@type UI_weapon_refined_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_WEAPON_REFINE, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_WEAPON_REFINE, self)
end

M[Protos.RES_WEAPON_REFINE] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitRefineData()
    self.AllRefineWeapon = {}
    self.characterInfos = {}
    self.SelectItems = {}
    local CurRoleWeaponType = 0
    local role_weapon_data = UIUtils.GetItemConfigById(self.WeaponInfo.item_id)
    CurRoleWeaponType = role_weapon_data.subType
    local character_configList = CharacterSystem:GetInstance().CharacterInfo
    -- get equipped weapon info
    for _, character_info in ipairs(character_configList) do
        local weapon_config = UIUtils.GetItemConfigById(character_info.weapon_info.item_id)
        if not character_info.config then
            local charConfig = require "ClientDatas.d_character"
            character_info.config = charConfig[character_info.character_id]
        end
        if character_info.weapon_info.item_id == self.WeaponInfo.item_id then
            character_info.weapon_info.config = weapon_config
            table.insert(self.AllRefineWeapon, character_info.weapon_info)
            table.insert(self.characterInfos, character_info)
        end
    end
    -- get bag weapon
    local bag_infos = BackpackSystem:GetInstance():GetAllItemByType(UIUtils.ItemMainType.Weapon, CurRoleWeaponType)
    local weapon_info = Database.Query('d_weapon', self.WeaponInfo.item_id)
    for _, weaponData in pairs(bag_infos) do
        for _, weapon_id in ipairs(weapon_info.refinedWeapon) do
            if weaponData.item_id == weapon_id then
                table.insert(self.AllRefineWeapon, weaponData)
            end
        end
    end
    table.sort(self.AllRefineWeapon, function(a, b)
        if a.config.bagSort ~= b.config.bagSort then
            return a.config.bagSort < b.config.bagSort
        else
            return a.item_uuid < b.item_uuid
        end
    end)
    print('-----------self.AllRefineWeapon:' .. tostring(#self.AllRefineWeapon))
    local max_refine_level = UIUtils.GetWeaponMaxRefineLevel(self.WeaponInfo.item_id)
    self.max_item_count = max_refine_level - self.WeaponInfo.weapon_info.refine_level
end

function M:InitUI()
    --退出按钮
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)
    --精炼按钮
    self.refinedStartBtn.OnGHSClicked:Add(self, self.OnClicked_Refine)

    --武器列表
    self.weaponList.BP_OnEntryInitialized:Clear()
    self.weaponList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)

    --武器列表点击事件
    self.weaponList.BP_OnItemClicked:Clear()
    self.weaponList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    self.BG:SetVisibility(UE.ESlateVisibility.Visible)
    self:RefreshUI()
end

function M:RefreshUI()
    self.ItemDataSource = {}
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Data/BP_BreakWeaponData.BP_BreakWeaponData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    if #self.AllRefineWeapon > 0 then
        for i = 1, #self.AllRefineWeapon do
            local WeaponData = NewObject(ItemClass)
            WeaponData.Index = i
            WeaponData.CanSelect = true
            table.insert(self.ItemDataSource, WeaponData)
        end
        self.weaponList:ClearListItems()
        self.weaponList:BP_SetListItems(self.ItemDataSource)
    end

    local weaponNum = #self.AllRefineWeapon
    local equippedNum = #self.characterInfos
    self.Text_Count:SetText(string.format("%d/%d", weaponNum - equippedNum, weaponNum))
    self.UI_Com_ItemBox:RefreshUI(self.WeaponInfo, false)
    self.Text_Title:SetText(string.format(Database.L10n(5014003), self.WeaponInfo.weapon_info.refine_level) or "")
    self.Img_Arrow:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Text_NextValue:SetVisibility(UE.ESlateVisibility.Hidden)

    UIUtils.RefreshUIItem(self.UI_Item, self.WeaponInfo, false)
    local weapon_name = Database.L10n(self.WeaponInfo.config.itemName)
    self.TextName:SetText(weapon_name)

    --物资消耗
    local hasGold = UIUtils.GetGold()
    self.Text_HaveGold:SetText("/" .. hasGold)
    self.Text_NeedGold:SetText(0)
    local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
    self.refinedStartBtn:SetColorAndOpacity(opacity)
    self.refinedStartBtn:SetVisibility(UE.ESlateVisibility.HitTestInvisible)

    local SkillDesc, SkillName = UIUtils.GetWeaponSkillDesc(self.WeaponInfo.item_id, self.WeaponInfo.weapon_info.refine_level)
    self.TextSkillBefore:SetText(SkillDesc)
    self.TextSkillName:SetText(SkillName)
    self.TextSkill:SetText(SkillDesc)
end

function M:RefreshRefineInfo()
    local hasGold = UIUtils.GetGold()
    local init_lv = self.WeaponInfo.weapon_info.refine_level
    local add_lv = 0
    for _, value in pairs(self.SelectItems) do
        --武器数量加上武器光淬等级
        local itemInfo = self.AllRefineWeapon[value]
        add_lv = add_lv + 1 + itemInfo.weapon_info.refine_level
    end
    local refine_lv = init_lv + add_lv
    local max_refine_level = UIUtils.GetWeaponMaxRefineLevel(self.WeaponInfo.item_id)
    refine_lv = refine_lv > max_refine_level and max_refine_level or refine_lv
    local needGold = UIUtils.GetWeaponRefineMat(self.WeaponInfo.item_id, init_lv, refine_lv)
    if refine_lv > init_lv then
        if hasGold >= needGold then
            local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
            self.refinedStartBtn:SetColorAndOpacity(opacity)
            self.refinedStartBtn:SetVisibility(UE.ESlateVisibility.Visible)
            self.Img_Arrow:SetVisibility(UE.ESlateVisibility.Visible)
            self.Text_NextValue:SetVisibility(UE.ESlateVisibility.Visible)
            self.Text_NextValue:SetText(string.format(Database.L10n(5014003), refine_lv) or "")
        else
            local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
            self.refinedStartBtn:SetColorAndOpacity(opacity)
            self.refinedStartBtn:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            self.Img_Arrow:SetVisibility(UE.ESlateVisibility.Visible)
            self.Text_NextValue:SetVisibility(UE.ESlateVisibility.Visible)
            self.Text_NextValue:SetText(string.format(Database.L10n(5014003), refine_lv) or "")
        end
        local SkillDescBefore = UIUtils.GetWeaponSkillDesc(self.WeaponInfo.item_id, init_lv)
        local SkillDesc = UIUtils.GetWeaponSkillDesc(self.WeaponInfo.item_id, refine_lv)
        self.TextSkillBefore:SetText(SkillDescBefore)
        self.TextSkill:SetText(SkillDesc)
    else
        local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
        self.refinedStartBtn:SetColorAndOpacity(opacity)
        self.refinedStartBtn:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        self.Img_Arrow:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Text_NextValue:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    self.Text_HaveGold:SetText("/" .. hasGold)
    self.Text_NeedGold:SetText(needGold)

    self:PlayAnimationForward(self.switch, 1, false)
end

function M:BP_OnEntryInitialized(item, widget)
    widget.Index = item.Index
    local item_data = self.AllRefineWeapon[item.Index]
    widget.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
    local lv, _ = UIUtils.GetWeaponLevel(item_data.item_id, item_data.weapon_info.break_times, item_data.weapon_info.exp)
    widget.Text_Lv:SetText(Database.L10n(5014001) .. lv)
    widget.CannotSeleted:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ImageUnlock:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.ImageLock:SetVisibility(UE.ESlateVisibility.Hidden)
    --光淬等级
    if item_data.weapon_info.refine_level > 0 then
        widget.weapon_refined:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        widget.refined_num:SetText('+' .. item_data.weapon_info.refine_level)
    else
        widget.weapon_refined:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    --已装备的武器
    for _, character_info in ipairs(self.characterInfos) do
        if character_info.weapon_info.item_uuid == item_data.item_uuid then
            widget.HorseLanterns:SetVisibility(UE.ESlateVisibility.Visible)
            item.CanSelect = false
            local sprite_name = character_info.config.idolProfile
            local sprite_path = string.format('/Game/_Game/TP_New/IdolProfile_res/Frames/%s_png.%s_png', sprite_name,
                sprite_name)
            local sprite_object = UE.UObject.Load(sprite_path)
            if sprite_object then
                local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
                widget.avatar_res:SetBrush(icon_sprite)
            end
            widget.CannotSeleted:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    end

    --稀有度背景图片
    if item_data.config.rarityPath and item_data.config.rarityPath ~= '' then
        local strArr = string.split(item_data.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    --icon
    if item_data.config.iconPath and item_data.config.iconPath ~= '' then
        local strArr = string.split(item_data.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', item_data.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        local sprite_object = UE.UObject.Load(iconResPath)
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
        if iconRes then
            widget.wp_icon_res:SetBrush(icon_sprite)
        end
    end

    if item_data.config.rarity <= 6 then
        widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        widget.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end

    --精炼武器
    if self.WeaponInfo.item_uuid == item_data.item_uuid then
        widget.HorseLanterns:SetVisibility(UE.ESlateVisibility.Visible)
        widget.CannotSeleted:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.TextBlock_103:SetText(Database.L10n(281))
        item.CanSelect = false
    else
        widget.HorseLanterns:SetVisibility(UE.ESlateVisibility.Hidden)
        if item_data.weapon_info.locked then
            widget.CannotSeleted:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            widget.ImageLock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            item.CanSelect = false
        end
    end

    widget.wp_Selected:SetVisibility(self.SelectItems[item.Index] and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnItemClicked(item)
    if item.CanSelect then
        if self.SelectItems[item.Index] then
            self.SelectItems[item.Index] = nil
            local widgets = self.weaponList:GetDisplayedEntryWidgets()
            for _, widget in pairs(widgets) do
                if widget.index == item.index then
                    widget.wp_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
                    break
                end
            end
        else
            local count = 0
            for key, value in pairs(self.SelectItems) do
                count = count + 1
            end
            if count < self.max_item_count then
                self.SelectItems[item.Index] = item.index
                local widgets = self.weaponList:GetDisplayedEntryWidgets()
                for _, widget in pairs(widgets) do
                    if widget.index == item.index then
                        widget.wp_Selected:SetVisibility(UE.ESlateVisibility.Visible)
                        break
                    end
                end
            end
        end
        self:RefreshRefineInfo()
    else
        --弹出二级界面
    end
end

function M:GetWeaponRefineAttr(weaponId)
    local attrTable = {}
    local weaponConfig = require("ClientDatas.d_weapon")[weaponId]
    if weaponConfig then
        local baseAttr = weaponConfig.refinedAttr
        local baseValue = weaponConfig.refinedValue
        for i, attr in ipairs(baseAttr) do
            attrTable[attr] = baseValue[i]
        end
    end
    return attrTable
end

function M:SetBackUI(beforeUI, weaponInfo, bFromBackpack)
    self.BackUI = beforeUI
    self.WeaponInfo = weaponInfo
    self.bBackpack = bFromBackpack
    self:InitRefineData()
    self:InitUI()
end

function M:OnClicked_Refine()
    local now = PlayerSystem:GetInstance():GetServerTime()
    if not self.lastClickedRefineTime then 
        self.lastClickedRefineTime = now - 1
    end
    if now - self.lastClickedRefineTime < 0.5 then
        print('----------点击间隔')
        return 
    end
    self.lastClickedRefineTime = now

    if not self.waiting then
        self.waiting = true

        local itemInfos = {}
        for _, v in pairs(self.SelectItems) do
            local itemInfo = self.AllRefineWeapon[v]
            if itemInfo then
                table.insert(itemInfos, itemInfo.item_uuid)
            end
        end

        --缓存精炼武器信息
        BackpackSystem:GetInstance():CacheRefineWeapons(self.WeaponInfo.item_id, self.WeaponInfo.item_uuid, itemInfos)
        self.InitRefineLevel = self.WeaponInfo.weapon_info.refine_level
        local msg = {
            item_uuid = self.WeaponInfo.item_uuid,
            stuff_item_uuid = itemInfos
        }
        print("======req_weapon_refine:" .. tostring(table.dump(msg, false, 10)))
        Client.send('req_weapon_refine', msg)
        self.msg = msg
    end
end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        if not self.bBackpack then
            self.BackUI:SetRoleVisibility(false)
        end
        self.BackUI = nil
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)

function M:OnMsg_Req_Strengthen_Weapon_Success()
    --弹出成功ui
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_levelup_success')
    local ItemInfo = BackpackSystem:GetInstance():GetItemByUUID(self.WeaponInfo.item_uuid) 
    if ItemInfo then  
        self.WeaponInfo.weapon_info = ItemInfo.weapon_info
    end
    local initLv = self.InitRefineLevel
    local curLv = self.WeaponInfo.weapon_info.refine_level
    local weaponSkill = UIUtils.GetWeaponRefineSkill(self.WeaponInfo.item_id, self.WeaponInfo.weapon_info.refine_level)
    ui:RefreshUI(3, initLv, curLv, weaponSkill)
    self.msg = nil
    self:InitRefineData()
    self:InitUI()
end

return M

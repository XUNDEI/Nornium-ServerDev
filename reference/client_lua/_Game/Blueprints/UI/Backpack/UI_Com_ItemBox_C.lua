require "UnLua"
require "Common.TableUtil"

local Client = require("Network.Client")
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"

---@type UI_Com_ItemBox_C
local M = Class()

local SideUI_State = {
    Compare = 1,
    Equipped = 2,
    Equipped_Now = 3,
    Close = 4,
    Hidden = 5,
}

local DescBoxPng = 
{
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_white_png.edging_equip_white_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_white_png.edging_equip_white_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_green_png.edging_equip_green_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_yellow_png.edging_equip_yellow_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_orange_png.edging_equip_orange_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_red_png.edging_equip_red_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/edging_equip_red_png.edging_equip_red_png',
}

local EquipPng = 
{
    '/Game/_Game/TP_New/Element_res/Frames/weapons_1_png.weapons_1_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_2_png.weapons_2_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_3_png.weapons_3_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_4_png.weapons_4_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_5_png.weapons_5_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_6_png.weapons_6_png',
    '/Game/_Game/TP_New/Element_res/Frames/weapons_7_png.weapons_7_png',
}

--构造函数
function M:Construct()
    self:InitData()
    self:InitUI()
    self.GHSButtonLock.OnGHSClicked:Add(self, self.OnClick_Lock)
    MessageManager:GetInstance():AddListener("OnMsg_Item_Lock", self)
    MessageManager:GetInstance():AddListener("OnMsg_Item_Unlock", self)
    self.DESCBOX_Red_plus4:ActivateSystem(true)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Item_Lock", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Item_Unlock", self)
end

function M:InitData()
    self.is_selected = false
end

function M:InitUI()
end

function M:RefreshUI(data, isBackpack)
    if not data.config then
        
    end
    self.data = data
    local typeId = tonumber("5013" .. tostring(data.config.itemType) .. string.format("%02d", data.config.subType))
    --物品类型会改为icon提示 icon未定
    --self.Text_ItemType:SetText(data and Database.L10n(typeId) or "")
    self.Text_ItemName:SetText(data and Database.L10n(data.config.itemName) or "")
    --self.Text_ItemDes:SetText(data and Database.L10n(data.config.effectDesc) or "")
    local isWeapon = data.config.itemType == UIUtils.ItemMainType.Weapon
    local isEquip = data.config.itemType == UIUtils.ItemMainType.Equip
    self.Text_RefineLevel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.RuneHorizontalBox:SetVisibility(UE.ESlateVisibility.Hidden)
    self.ImageIcon:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.TextType:SetVisibility(UE.ESlateVisibility.Collapsed)
    local lv, needExp = 0, 0 

    if isWeapon then
        local weapon_breakTimes = data.weapon_info and data.weapon_info.break_times or 1
        local weapon_exp = data.weapon_info and data.weapon_info.exp or 1
        local weapon_refineLv = data.weapon_info and data.weapon_info.refine_level or 0

        lv, needExp = UIUtils.GetWeaponLevel(data.item_id, weapon_breakTimes, weapon_exp)
        local maxLv = UIUtils.GetWeaponMaxLevel(data.item_id, weapon_breakTimes)
        local lv = string.format('Lv.%d/%d', lv or 1, maxLv)
        self.Text_ItemLevel:SetText(lv)
        self.Text_ItemLevel:SetVisibility(UE.ESlateVisibility.Visible)
        self.Text_ItemCount:SetVisibility(UE.ESlateVisibility.Hidden)

        if weapon_refineLv > 0 then
            local refineLv = string.format(Database.L10n(5014003), weapon_refineLv) or ""
            self.Text_RefineLevel:SetText(refineLv)
            self.Text_RefineLevel:SetVisibility(UE.ESlateVisibility.Visible)
        end

        local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/weapons_%s_png.weapons_%s_png", data.config.subType, data.config.subType)
        local iconObj = LoadObject(iconPath)
        if iconObj then
            self.ImageIcon:SetVisibility(UE.ESlateVisibility.Visible)
            self.ImageIcon:SetBrushFromAtlasInterface(iconObj)
            self.TextType:SetVisibility(UE.ESlateVisibility.Visible)
            self.TextType:SetText(Database.L10n(UIUtils.WordWeaponType[data.config.subType]))
        end

        self.GHSButtonLock:SetVisibility(UE.ESlateVisibility.Visible)
        if data.weapon_info and data.weapon_info.locked then
            self.ImageLock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.ImageLock:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    elseif isEquip then
        local equip_breakTimes = data.arm_info and data.arm_info.break_times or 1
        local equip_exp = data.arm_info and data.arm_info.exp or 1
        lv, needExp = UIUtils.GetEquipLevel(data.item_id, equip_breakTimes, equip_exp)

        self.Text_ItemLevel:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Text_ItemCount:SetVisibility(UE.ESlateVisibility.Hidden)
        self.RuneHorizontalBox:SetVisibility(UE.ESlateVisibility.Visible)
        -- local iconObj = LoadObject(EquipPng[data.config.subType])
        -- if iconObj then
        --     self.ImageIcon:SetVisibility(UE.ESlateVisibility.Visible)
        --     self.ImageIcon:SetBrushFromAtlasInterface(iconObj)
        -- end

        for index = 1, 2 do
            if data.arm_info and data.arm_info.arm_rune_infos then
                self["ImageRune_" .. index]:SetVisibility(index <= #data.arm_info.arm_rune_infos and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            else
                self["ImageRune_" .. index]:SetVisibility(UE.ESlateVisibility.Collapsed)
            end
        end

        if data.arm_info and data.arm_info.arm_rune_infos then
            for index, arm_rune_info in ipairs(data.arm_info.arm_rune_infos) do
                local rune_id = arm_rune_info.rune_id
                local rune_info = Database.Query("d_equip_rune", rune_id)
                if rune_info then
                    local strArr = string.split(rune_info.runeIcon, '/')
                    local littePath = strArr[#strArr]
                    local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                    if itemRarityPic then
                        self["ImageRune_" .. index]:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
            end
        end

        self.GHSButtonLock:SetVisibility(UE.ESlateVisibility.Visible)
        if data.arm_info and data.arm_info.locked then
            self.ImageLock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.ImageLock:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    else
        local lv = Database.L10n(5014002) .. (data and data.count or 1)
        self.Text_ItemCount:SetText(lv)
        self.Text_ItemLevel:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Text_ItemCount:SetVisibility(UE.ESlateVisibility.Visible)
        self.GHSButtonLock:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    --物品图片
    if data.config.displayPath and data.config.displayPath ~= '' then
        local strArr = string.split(data.config.displayPath, '/')
        local littePath = strArr[#strArr]
        local sprite_path = string.format('/Game/_Game/%s.%s', data.config.displayPath, littePath)
        local sprite_object = LoadObject(sprite_path)
        if sprite_object then
            self.item_img:SetBrushFromAtlasInterface(sprite_object)
        end
    end

    --星级
    local star = data.config.rarity
    if star <= 5 then
        for i = 1, 6 do
            local bShow = i <= star and (isWeapon or isEquip)
            self["Rarity" .. i]:SetVisibility(bShow and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden) 
        end
        self.Rarity:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.Effect_2:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus2:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus3:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus4:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif star == 6 then
        for i = 1, 6 do
            local bShow = (isWeapon or isEquip)
            self["Rarity" .. i]:SetVisibility(bShow and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden) 
        end
        self.Rarity:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.Effect_2:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.DESCBOX_Red_plus:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus2:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus3:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus4:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif star == 7 then
        self.Rarity:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Effect_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.DESCBOX_Red:SetVisibility(UE.ESlateVisibility.Hidden)
        self.DESCBOX_Red_plus:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.DESCBOX_Red_plus2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.DESCBOX_Red_plus3:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.DESCBOX_Red_plus4:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end
    self.DESCBOX:SetBrushFromAtlasInterface(UE.UObject.Load(DescBoxPng[star]))
    --UIUtils.RefreshUIItem(self.UI_Item, data, false)
end

function M:OnClick_Lock()
    if self.data[self.data.item_extra] and self.data[self.data.item_extra].locked then
        local msg = {}
        msg.item_uuid = self.data.item_uuid
        Client.send("req_item_unlock", msg)
    else
        local msg = {}
        msg.item_uuid = self.data.item_uuid
        Client.send("req_item_lock", msg)
    end
end

function M:RefreshSelectState(is_selected)
    self.is_selected = is_selected
    if is_selected then
        self.Selected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    else
        self.Selected:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshRoleIcon(sprite_name)
    local sprite_path = string.format('/Game/_Game/TP_New/IdolProfile_res/Frames/%s_png.%s_png', sprite_name, sprite_name)
    local sprite_object = UE.UObject.Load(sprite_path)
    if sprite_object then
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
        self.profile_res:SetBrush(icon_sprite)
    end 
end

function M:OnMsg_Item_Lock()
    self:UpdateLockButton()
end

function M:OnMsg_Item_Unlock()
    self:UpdateLockButton()
end

function M:UpdateLockButton()
    if self.data then
        if self.data[self.data.item_extra] and self.data[self.data.item_extra].locked then
            self.ImageLock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.ImageLock:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImageUnlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    end
end

function M:RefreshSideUI(state)
    self.FuncButton:SetVisibility(UE.ESlateVisibility.Visible)
    if state == SideUI_State.Compare then
        self.Compare:SetVisibility(UE.ESlateVisibility.Visible)
        self.Equiped:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Equiped_Now:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Close:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif state == SideUI_State.Equipped then
        self.Equiped:SetVisibility(UE.ESlateVisibility.Visible)
        self.Equiped_Now:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Compare:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Close:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif state == SideUI_State.Equipped_Now then
        self.Equiped_Now:SetVisibility(UE.ESlateVisibility.Visible)
        self.Equiped:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Compare:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Close:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif state == SideUI_State.Close then
        self.Close:SetVisibility(UE.ESlateVisibility.Visible)
        self.Equiped:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Equiped_Now:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Compare:SetVisibility(UE.ESlateVisibility.Hidden)
    elseif state == SideUI_State.Hidden then
        self.FuncButton:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

----------------------------------------------------------------------
---ui event


return M

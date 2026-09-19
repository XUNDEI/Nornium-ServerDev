--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require("_Game.Utils.Database")
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Levelup_weapon_C
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

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:Construct()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Weapon_Success", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Weapon_Success", self)
end

function M:InitUI()
    --退出按钮
    self.UI_Panel_Levelup.Btn_BackButton.OnGHSClicked:Add(self, self.OnClicked_Exit)

    self:RefreshWeaponUI()
    self.UI_Panel_LevelUp:SetBackUI(self.BackUI, "Weapon", self.WeaponInfo.item_uuid, self.WeaponInfo.item_id, self.WeaponInfo.weapon_info.break_times, self.WeaponInfo.weapon_info.exp)
end

function M:RefreshWeaponUI()
    UIUtils.RefreshUIItem(self.UI_Item, self.WeaponInfo, false)
    local weapon_name = Database.L10n(self.WeaponInfo.config.itemName)
    self.TextName:SetText(weapon_name)
    if not self.bBackpack then
        self.BackUI:SetRoleVisibility(true)
    end
end

function M:OnMsg_Req_Strengthen_Weapon_Success()
    self:RefreshWeaponUI()
    self.RefreshParentUI = true
end

function M:SetBackUI(beforeUI, weaponInfo, bBackpack)
    self.BackUI = beforeUI
    self.WeaponInfo = weaponInfo
    self.bBackpack = bBackpack
    self:InitUI()
    
end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        if not self.bBackpack then
            self.BackUI:SetRoleVisibility(false)
        else
            if self.RefreshParentUI then
                self.BackUI:OnMsg_Req_Strengthen_Weapon_Success()
            end
        end
        self.BackUI = nil
    end
end

function M:OnClicked_SpaceBar()
    self.UI_Panel_LevelUp:IA_Confirm()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_SpaceBar)

return M

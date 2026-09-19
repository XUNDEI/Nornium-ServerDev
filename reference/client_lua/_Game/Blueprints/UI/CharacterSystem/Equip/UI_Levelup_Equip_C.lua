--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require("_Game.Utils.Database")
local UIUtils = require "_Game.Utils.UIUtils"

---@type UI_Levelup_Equip_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:Construct()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Equip_Success", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Equip_Success", self)
end

function M:InitUI()
    --退出按钮
    self.UI_Panel_Levelup.Btn_BackButton.OnGHSClicked:Add(self, self.OnClicked_Exit)

    self:RefreshEquipUI()
    self.UI_Panel_LevelUp:SetBackUI(self.BackUI, "Equip", self.ItemInfo.item_uuid, self.ItemInfo.item_id, self.ItemInfo.arm_info.break_times, self.ItemInfo.arm_info.exp)
end

function M:RefreshEquipUI()
    self.UI_Panel_LevelUp.Text_LevelUp:SetText('纯化')
    self.UI_Panel_LevelUp.TextBtnLevelUp:SetText('纯化')
    UIUtils.RefreshUIItem(self.UI_Item, self.ItemInfo, false)
    local item_name = Database.L10n(self.ItemInfo.config.itemName)
    self.TextName:SetText(item_name)
    if not self.bBackpack then
        self.BackUI:SetRoleVisibility(true)
        self.BackUI:SetEquipEffectVisibility(false)
    end
    for i = 1, 5 do
        self['Rune_' .. i]:SetVisibility(UE.ESlateVisibility.Hidden)
        --self['Rune_' .. i]:SetVisibility(i <= #self.ItemInfo.arm_info.arm_rune_infos and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    end
end

function M:OnMsg_Req_Strengthen_Equip_Success()
    self:RefreshEquipUI()
end

function M:SetBackUI(beforeUI, itemInfo, bBackpack)
    self.BackUI = beforeUI
    self.ItemInfo = itemInfo
    self.bBackpack = bBackpack
    self:InitUI()
end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        if not self.bBackpack then
            self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.BackUI:SetEquipEffectVisibility(true)
            self.BackUI:SetRoleVisibility(false)
            self.BackUI:RefreshEquipPanel()
        end
        self.BackUI = nil
    end
end

return M

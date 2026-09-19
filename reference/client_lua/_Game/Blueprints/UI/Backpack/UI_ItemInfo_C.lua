require "UnLua"
require "Common.TableUtil"

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"

local SideUI_State = {
    Compare = 1,
    Equipped = 2,
    Equipped_Now = 3,
    Close = 4,
    Hidden = 5,
}

---@type UI_ItemInfo_C
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
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Detail.OnGHSClicked:Add(self, self.OnClicked_Btn_Detail)
    self.Btn_Tag.OnGHSClicked:Add(self, self.OnClicked_Btn_Tag)
    --self.Btn_Use.OnGHSClicked:Add(self, self.OnClicked_Btn_Use)
    self.selected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.default:SetVisibility(UE.ESlateVisibility.Hidden)
    self.selected_1:SetVisibility(UE.ESlateVisibility.Hidden)
    self.default_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    
end

function M:RefreshUI(data, isBackpack, parentUI)
    if not data.config then
        data.config = UIUtils.GetItemConfigById(data.item_id)
    end
    self.UI_Com_ItemBox:RefreshUI(data, isBackpack)
    self.UI_Com_BagDetail:RefreshUI(data, isBackpack, parentUI)
    self:OnClicked_Btn_Detail()
end

----------------------------------------------------------------------
---ui event
function M:OnClicked_Btn_Close()
    --self:RemoveFromViewport()
end

function M:OnClicked_Btn_Detail()
    self.UI_Com_BagDetail:RefreshTag(0)
    self.selected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.default:SetVisibility(UE.ESlateVisibility.Hidden)
    self.selected_1:SetVisibility(UE.ESlateVisibility.Hidden)
    self.default_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

function M:OnClicked_Btn_Tag()
    self.UI_Com_BagDetail:RefreshTag(1)
    self.selected:SetVisibility(UE.ESlateVisibility.Hidden)
    self.default:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.selected_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.default_1:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:RefreshCompareState(is_old)
    if is_old then
        self.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
    else
        self.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Close)
    end
    self.UI_Com_BagDetail:RefreshCompareState(is_old)
end

return M

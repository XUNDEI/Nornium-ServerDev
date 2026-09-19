local Widget = require("Framework.UI.Widget")
local Database = require("_Game.Utils.Database")

---@class UI_Com_SideBarItemList : UI_Com_SideBarItemList_C
local M = Widget.Class()
M.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Com_SideBar/UI_Com_SideBarItemList.UI_Com_SideBarItemList_C')

function M:Construct()
    self.isFolded = false

    self.fold:SetVisibility(UE.ESlateVisibility.Hidden)
    self.unfold:SetVisibility(UE.ESlateVisibility.Visible)
    self.item_list:SetVisibility(UE.ESlateVisibility.Visible)

    local toggleFold = function()
        self.isFolded = not self.isFolded
        self.fold:SetVisibility(self.isFolded and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        self.unfold:SetVisibility(self.isFolded and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
        self.item_list:SetVisibility(self.isFolded and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.Visible)
    end

    self.title_button.OnClicked:Add(self, toggleFold)
end

function M:SetTitle(SlotNameKey)
    self.title_text:SetText(Database.L10n(SlotNameKey))
end

function M:AddItem(Item)
    self.item_list:AddChild(Item)
end

return M

local Widget = require("Framework.UI.Widget")
local Database = require("_Game.Utils.Database")

---@class UI_Com_SiderBar_OKButton : UI_Com_SiderBar_OKButton_C
local M = Widget.Class()
M.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Com_SideBar/UI_Com_SiderBar_OKButton.UI_Com_SiderBar_OKButton_C')

function M:SetButtonName(ButtonNameKey)
    self.button_name:SetText(Database.L10n(ButtonNameKey))
end

function M:AddOnClickedCallback(Callback)
    self.button.OnClicked:Add(self, Callback)
end

return M

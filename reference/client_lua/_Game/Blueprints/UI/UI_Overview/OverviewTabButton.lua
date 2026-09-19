local BaseWidget = require "Framework.UI.BaseWidget"

---@class OverviewTabButton
---@field widget UI_Overview_TabButton_C
local OverviewTabButton = BaseClass("OverviewTabButton", BaseWidget)

OverviewTabButton.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Overview/UI_Overview_TabButton.UI_Overview_TabButton_C')

function OverviewTabButton:__init()
end

function OverviewTabButton:__delete()
end

return OverviewTabButton

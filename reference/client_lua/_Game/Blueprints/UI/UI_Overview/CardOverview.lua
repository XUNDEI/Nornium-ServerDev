local BaseWidget = require "Framework.UI.BaseWidget"

---@class CardOverview
local CardOverview = BaseClass("CardOverview", BaseWidget)

CardOverview.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Overview/UI_Overview_Card.UI_Overview_Card_C')

function CardOverview:__init()
end

function CardOverview:__delete()
end

return CardOverview

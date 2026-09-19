local BaseWidget = require "Framework.UI.BaseWidget"
local BaseInfoEntry = require("_Game.Blueprints.UI.UI_Overview.BaseInfoEntry")

---@class BaseInfo
---@field widget UI_Overview_BaseInfo_C
local BaseInfo = BaseClass("BaseInfo", BaseWidget)

BaseInfo.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Overview/UI_Overview_BaseInfo.UI_Overview_BaseInfo_C')

function BaseInfo:__init(BaseInfos)
    ---@type table<integer, MainPosInfo>
    self.baseInfos = BaseInfos
end

function BaseInfo:SetUp()
    self.baseInfoEntries = {}
    for _, mainPosInfo in pairs(self.baseInfos) do
        local baseInfoEntry = BaseInfoEntry.New(mainPosInfo)

        self.widget.Content:AddChild(baseInfoEntry.widget)

        baseInfoEntry:SetUp()

        table.insert(self.baseInfoEntries, baseInfoEntry)
    end
end

return BaseInfo

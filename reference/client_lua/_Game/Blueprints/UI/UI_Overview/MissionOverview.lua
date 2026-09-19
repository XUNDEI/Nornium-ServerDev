local BaseWidget = require "Framework.UI.BaseWidget"
local MissionInfoEntry = require("_Game.Blueprints.UI.UI_Overview.MissionInfoEntry")

---@class MissionOverview
---@field widget UI_Overview_MissionInfo_C
local MissionOverview = BaseClass("MissionOverview", BaseWidget)

MissionOverview.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Overview/UI_Overview_MissionInfo.UI_Overview_MissionInfo_C')

function MissionOverview:__init(MissionInfos)
    ---@type MissionInfo[]
    self.missionInfos = MissionInfos
end

function MissionOverview:SetUp()
    for _, missionInfo in pairs(self.missionInfos) do
        local missionInfoEntry = MissionInfoEntry.New(missionInfo)

        self.widget.Content:AddChild(missionInfoEntry.widget)

        missionInfoEntry:SetUp()
    end
end

return MissionOverview

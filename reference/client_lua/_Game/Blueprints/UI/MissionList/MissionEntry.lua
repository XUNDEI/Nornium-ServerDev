local BaseWidget = require "Framework.UI.BaseWidget"
local Database = require("_Game.Utils.Database")

---@class MissionEntry @任务列表
---@field widget UI_Mission_C
local MissionEntry = BaseClass("MissionEntry", BaseWidget)

MissionEntry.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Task/UI_Mission.UI_Mission_C')


function MissionEntry:__init(MissionInfo)
    self.missionInfo = MissionInfo
end

function MissionEntry:SetUp()
    local nameId = Database.Query("d_srpg_mission", self.missionInfo.mission_id).nameId
    self.widget.Title:SetText(Database.L10n(nameId))
end

return MissionEntry

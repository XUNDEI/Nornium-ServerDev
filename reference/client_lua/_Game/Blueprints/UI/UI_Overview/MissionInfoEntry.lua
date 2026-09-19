local BaseWidget = require "Framework.UI.BaseWidget"
local Database = require("_Game.Utils.Database")

---@class MissionInfoEntry
---@field widget UI_srpg_panel_mission_C
local MissionInfoEntry = BaseClass("MissionInfoEntry", BaseWidget)

MissionInfoEntry.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_srpg_panel_mission.UI_srpg_panel_mission_C')

---@param MissionInfo MissionInfo
function MissionInfoEntry:__init(MissionInfo)
    self.missionInfo = MissionInfo
end

function MissionInfoEntry:SetUp()
    local missionConfig = Database.Query("d_srpg_mission", self.missionInfo.mission_id)
    self.widget.Description:SetText(Database.L10n(missionConfig.descrId))
    self.widget.Name:SetText(Database.L10n(missionConfig.nameId))

    local completed = self.missionInfo.mission_result == 1
    self.widget.Status:SetVisibility(completed and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    self.widget.StatusText:SetVisibility(completed and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    if self.missionInfo.mission_result == 1 then
    end
end

return MissionInfoEntry

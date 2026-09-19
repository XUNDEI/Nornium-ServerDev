local BaseWidget = require "Framework.UI.BaseWidget"

---@class MissionList @任务列表
---@field widget UI_TaskTemplate_C
local MissionList = BaseClass("MissionList", BaseWidget)

MissionList.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Task/UI_TaskTemplate.UI_TaskTemplate_C')

return MissionList

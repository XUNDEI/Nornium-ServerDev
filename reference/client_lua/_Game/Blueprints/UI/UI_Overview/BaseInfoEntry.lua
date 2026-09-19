local BaseWidget = require "Framework.UI.BaseWidget"
local Database = require("_Game.Utils.Database")

---@class BaseInfoEntry
---@field widget UI_Overview_BaseInfoEntry_C
local BaseInfoEntry = BaseClass("BaseInfoEntry", BaseWidget)

BaseInfoEntry.__widget_class = LoadClass('/Game/_Game/Blueprints/UI/UI_Overview/UI_Overview_BaseInfoEntry.UI_Overview_BaseInfoEntry_C')

function BaseInfoEntry:__init(MainPosInfo)
    ---@type MainPosInfo
    self.mainPosInfo = MainPosInfo

    self.items = { 
        self.widget.Item1,
        self.widget.Item2,
        self.widget.Item3,
        self.widget.Item4,
    }
end

function BaseInfoEntry:SetUp()
    local nameId = Database.Query("d_srpg_main_pos_base", self.mainPosInfo.main_pos_id).nameId

    self.widget.BaseName:SetText(Database.L10n(nameId))

    -- 基地上的牌先鸽了
end

return BaseInfoEntry

local Database = require("_Game.Utils.Database")

---@type UI_Card_Race_C
local M = UnLua.Class()

local RACE_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/card_race_icon/%s.%s'
local LEVEL_PATH = '/Game/_Game/Blueprints/UI/UI_Menu/UI_Level%d.UI_Level%d_C'

function M:ShowRaceInfo(raceId, count)
    local raceInfo = Database.Query("d_srpg_card_race", raceId)

    self.name:SetText(Database.L10n(raceInfo.nameId))

    for i = 1, #raceInfo.effectsArea do
        local levelBase = raceInfo.effectsArea[i - 1] or 0
        local levelCount = raceInfo.effectsArea[i] - levelBase
        ---@type UI_Level3_C
        local levelWidget = UE.UWidgetBlueprintLibrary.Create(self.level, LoadClass(string.format(LEVEL_PATH, levelCount, levelCount)))
        self.level:AddChild(levelWidget)

        levelWidget.Slot.HorizontalAlignment = UE.EHorizontalAlignment.HAlign_Center
        levelWidget.Slot.VerticalAlignment = UE.EVerticalAlignment.VAlign_Center

        local margin = UE.FMargin()
        margin.Left = 3
        margin.Right = 3
        levelWidget:SetPadding(margin)

        for j = 1, levelCount do
            if count - levelBase >= j then
                levelWidget[tostring(j)]:SetVisibility(UE.ESlateVisibility.Visible)
                levelWidget[string.format("%d_locked", j)]:SetVisibility(UE.ESlateVisibility.Collapsed)
            else
                levelWidget[tostring(j)]:SetVisibility(UE.ESlateVisibility.Collapsed)
                levelWidget[string.format("%d_locked", j)]:SetVisibility(UE.ESlateVisibility.Visible)
            end
        end
    end
end

return M

local Database = require "_Game.Utils.Database"
local UIUtils = require("_Game.Utils.UIUtils")
---@type UI_SRPG_Event_1_C
local M = UnLua.Class("_Game.Blueprints.UI.UI_SRPG_Event.UI_Srpg_SpecialEventBase_C")

---@param eventInfo EventInfo
function M:InitEventUI(eventInfo)
    self.Super.InitEventUI(self, eventInfo)

    local optionConfig = Database.Query("d_srpg_event_option", eventInfo.options[1].option_id)
    local effects = optionConfig.effectTriggerID

    for _, effectId in pairs(effects) do
        local effectConfig = Database.Query("d_srpg_effect_trigger", effectId)

        if effectConfig.effectType ~= 1 and effectConfig.effectType ~= 60 then
            return
        end

        if effectConfig.effectType == 1 then
            self.Items:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

            for i = 1, 3 do
                if effectConfig.effectConfig[i] > 0 then
                    local item = UIUtils.CreateUniverseResourceItem(self, i, effectConfig.effectConfig[i])
                    self.ItemList:AddChild(item)
                    item:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                end
            end
        elseif effectConfig.effectType == 60 then
            self.Items:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            for i = 1, #effectConfig.effectConfig, 3 do
                local id = effectConfig.effectConfig[i]
                local type = effectConfig.effectConfig[i + 1]
                local count = effectConfig.effectConfig[i + 2]

                local item = UIUtils.CreateItem(self, id, count)
                self.ItemList:AddChild(item)
            end
        end
    end
end

return M

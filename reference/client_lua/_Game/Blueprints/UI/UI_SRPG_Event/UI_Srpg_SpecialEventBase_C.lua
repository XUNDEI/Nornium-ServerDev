local Database = require "_Game.Utils.Database"
local Protos = require("Helper.Protos")
local Client = require "Network.Client"
local SrpgController = require "Module.Srpg.SrpgController"
local SrpgModel = require("Module.Srpg.SrpgModel")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Srpg_SpecialEventBase_C
local M = UnLua.Class()

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHOOSE_EVENT_OPTION, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHOOSE_EVENT_OPTION, self)
end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

---@param eventInfo EventInfo
function M:InitEventUI(eventInfo)
    if self.Overview then
        self.Overview.OnClicked:Add(self.Overview, function()
            ---@type UI_OverView_C
            local overview = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_OverView.UI_OverView_C'))

            UIManager:GetInstance():AddUI(overview)

            overview:SetUp()
        end)
    end
    if eventInfo then
        self.eventUUID = eventInfo.event_uuid
        local eventConfig = Database.Query("d_srpg_event_base", eventInfo.event_id)
        local eventName = Database.L10n(eventConfig.nameId)
        local eventDesc = Database.L10n(eventConfig.descrId)

        if self.Name then
            self.Name:SetText(eventName)
        end
        if self.Desc then
            self.Desc:SetText(eventDesc)
        end

        if eventConfig.img ~= "" then
            local bgPath = string.format('/Game/_Game/TP_New/SRPG_Event/Event_BG/%s.%s', eventConfig.img, eventConfig.img)
            local bg_texture = UE.UObject.Load(bgPath)
            if bg_texture and self.Background then
                self.Background:SetBrushFromTexture(bg_texture)
            end
        end

        local num = #eventInfo.options
        for index, option in ipairs(eventInfo.options) do
            option.index = index
        end
        table.sort(eventInfo.options, function(a, b)
            if a.option_id < b.option_id then
                return true
            end
        end)

        for i = 1, num do
            local optionId = eventInfo.options[i].option_id
            local enabled = eventInfo.options[i].enabled

            local option = self['Option' .. tostring(i)]

            local optionConfig = Database.Query("d_srpg_event_option", optionId)

            if option then
                if option.Name then
                    option.Name:SetText(Database.L10n(optionConfig.nameId))
                end
                if option.Desc then
                    option.Desc:SetText(Database.L10n(optionConfig.descrId))
                end
                if option.Extra then
                    option.Extra:SetText(Database.L10n(optionConfig.extraDescrId))
                end

                if option.Requirement then
                    option.Requirement:SetVisibility(optionConfig.conditionDescId ~= 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                end
                if option.RequirementText then
                    if optionConfig.conditionDescId ~= 0 then
                        option.RequirementText:SetText(Database.L10n(optionConfig.conditionDescId))
                    end
                end
            end

            ---@type UButton
            local button = option.Button
            button.OnClicked:Clear()
            button.OnClicked:Add(self, function()
                if enabled then
                    Client.send(Protos.REQ_CHOOSE_EVENT_OPTION, {
                        event_uuid = self.eventUUID,
                        index = i - 1,
                    })
                end
            end)
            button:SetIsEnabled(enabled)
        end
    end

    if self.In then
        self:PlayAnimation(self.In, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
    end
end

M[Protos.RES_CHOOSE_EVENT_OPTION] = function(self, result, msgId, parsed_msg)
    if result == 0 or result == 1 then
        UIManager:GetInstance():RemoveUI(self)

        SrpgController:GetInstance():RemoveUniverseEvent(self.eventUUID)
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.Event)
    end
end

return M

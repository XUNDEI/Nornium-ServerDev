require "UnLua"
require "Common.TableUtil"
local Database = require "_Game.Utils.Database"
local SrpgController = require "Module.Srpg.SrpgController"
local SrpgModel = require "Module.Srpg.SrpgModel"
local Protos = require("Helper.Protos")

---@type UI_SRPG_Event_C
local M = Class()

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHOOSE_EVENT_OPTION, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHOOSE_EVENT_OPTION, self)
end

local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:IA_Back()
    self.BackButton.OnClicked:Broadcast()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)

local COORDS = {
    { 0, 0 },
    { 0, 1 },
    { 1, 0 },
    { 1, 1 },
    { 0, 2 },
    { 1, 2 },
}

---@param event_info EventInfo
function M:InitEventUI(event_info)
    if event_info then
        self.eventUUID = event_info.event_uuid
        local bg_path = '/Game/_Game/TP_New/SRPG_Event/Event_BG/%s.%s'
        local eventInfo = Database.Query("d_srpg_event_base", event_info.event_id)
        local event_name = Database.L10n(eventInfo.nameId)
        local event_desc = Database.L10n(eventInfo.descrId)
        bg_path = string.format(bg_path, eventInfo.img, eventInfo.img)
        self.TextName:SetText(event_name)
        self.TextDesc:SetText(event_desc)
        local bg_texture = UE.UObject.Load(bg_path)
        if bg_texture then
            self.Img_BG:SetBrushFromTexture(bg_texture)
        end

        local num = #event_info.options
        for index, option in ipairs(event_info.options) do
            option.index = index
        end
        table.sort(event_info.options, function(a, b)
            if a.option_id < b.option_id then
                return true
            end
        end)
        self.UI_SRPG_EventOption_List.Content:ClearChildren()
        for i = 1, num do
            local option_id = event_info.options[i].option_id
            local is_enable = event_info.options[i].enabled
            local item = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_SRPG_EventOption.UI_SRPG_EventOption_C"))
            self.UI_SRPG_EventOption_List.Content:AddChild(item)
            item.Slot:SetRow(COORDS[i][1])
            item.Slot:SetColumn(COORDS[i][2])
            if num == 1 then
                item.Slot:SetHorizontalAlignment(UE.EHorizontalAlignment.HAlign_Center)
            end
            local itemInfo = {}
            itemInfo.option_id = option_id
            itemInfo.is_enable = is_enable
            itemInfo.is_random = event_info.is_random
            itemInfo.event_uuid = event_info.event_uuid
            itemInfo.option_index = event_info.options[i].index - 1
            item:Setup(itemInfo)
        end

        if num <= 4 then
            self.option_slide_icon_left:SetVisibility(UE.ESlateVisibility.Hidden)
            self.option_slide_icon_right:SetVisibility(UE.ESlateVisibility.Hidden)
            self.page1:SetVisibility(UE.ESlateVisibility.Hidden)
            self.page2:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.UI_SRPG_EventOption_List.ScrollBox.OnUserScrolled:Add(self, self.UpdateScroll)
            self:UpdateScroll(0)
        end

        if self.In then
            self:PlayAnimation(self.In, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
        end
    end
end

local MAX_OFFSET = 931
local THRESHOLD = 200

function M:UpdateScroll(offset)
    if offset < MAX_OFFSET / 2 then
        if offset > THRESHOLD then
            offset = MAX_OFFSET
        end
    else
        if offset < MAX_OFFSET - THRESHOLD then
            offset = 0
        end
    end
    self.UI_SRPG_EventOption_List.ScrollBox:SetScrollOffset(offset)
    self.option_slide_icon_left:SetVisibility(offset < MAX_OFFSET / 2 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.option_slide_icon_right:SetVisibility(offset > MAX_OFFSET / 2 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.page1:SetVisibility(offset > MAX_OFFSET / 2 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.page2:SetVisibility(offset < MAX_OFFSET / 2 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
end

M[Protos.RES_CHOOSE_EVENT_OPTION] = function(self, result, msgId, parsed_msg)
    if result == 0 or result == 1 then
        UIManager:GetInstance():RemoveUI(self)

        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

        SrpgController:GetInstance():RemoveUniverseEvent(self.eventUUID)
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.Event)
    end
end

return M

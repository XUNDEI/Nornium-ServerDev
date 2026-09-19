require "UnLua"
require "Global"
require "Common.TableUtil"
local Database = require "_Game.Utils.Database"
local Client = require "Network.Client"

---@type UI_SRPG_EventOption_C
local UI_SRPG_EventOption_C = Class()

function UI_SRPG_EventOption_C:Initialize()
    self.event_uuid = 0
    self.option_index = 0
    self.option_id = 0
    self.is_enable = true

    if not UI_SRPG_EventOption_C.bg_spritesRef then
        UI_SRPG_EventOption_C.bg_sprites = {
            LoadObject('/Game/_Game/TP_New/SRPG_Event/Frames/Option_Requirement_Base_NotMeetCondition_png.Option_Requirement_Base_NotMeetCondition_png'),
            LoadObject('/Game/_Game/TP_New/SRPG_Event/Frames/Option_Requirement_Base_MeetCondition_png.Option_Requirement_Base_MeetCondition_png'),
        }
        UI_SRPG_EventOption_C.bg_spritesRef = {
            UnLua.Ref(UI_SRPG_EventOption_C.bg_sprites[1]),
            UnLua.Ref(UI_SRPG_EventOption_C.bg_sprites[2]),
        }
    end
end

function UI_SRPG_EventOption_C:Construct()
    self.BtnSelect.OnPressed:Add(self, UI_SRPG_EventOption_C.OnButtonPressed)
    self.BtnSelect.OnReleased:Add(self, UI_SRPG_EventOption_C.OnButtonReleased)
end

function UI_SRPG_EventOption_C:Setup(itemInfo)
    self.event_uuid = itemInfo.event_uuid
    self.is_enable = itemInfo.is_enable
    self.option_index = itemInfo.option_index
    self.option_id = itemInfo.option_id
    local option_info = Database.Query("d_srpg_event_option", self.option_id)

    if self.option_id ~= 0 then
        self.BtnSelect:SetVisibility(UE.ESlateVisibility.Visible)
        self.features:SetVisibility(UE.ESlateVisibility.Visible)
        self.TxtOptionName:SetVisibility(UE.ESlateVisibility.Visible)
        --self.TxtOptionDesc:SetVisibility(UE.ESlateVisibility.Visible)
        self:SetRicchTextVisible(true)
        self.TxtOptionAddDesc:SetVisibility(UE.ESlateVisibility.Visible)
        if self.is_enable == false then
            self.ImgEventBG_Normal:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImgEventBG_BanChoose:SetVisibility(UE.ESlateVisibility.Visible)
            self.ImgEventBG_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImgEventBG_NoChoose:SetVisibility(UE.ESlateVisibility.Hidden)
            self.BtnSelect:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
            self.BtnSelect:SetColorAndOpacity(opacity)
            if UI_SRPG_EventOption_C.bg_sprites[1] then
                local bg_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(UI_SRPG_EventOption_C.bg_sprites[1], 0, 0)
                self.condition_bg:SetBrush(bg_sprite)
                self.condition_bg.Brush.DrawAs = UE.ESlateBrushDrawType.RoundedBox
                self.condition_bg.Brush.OutlineSettings.Width = 12
            end
        else
            self.ImgEventBG_Normal:SetVisibility(UE.ESlateVisibility.Visible)
            self.ImgEventBG_BanChoose:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImgEventBG_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
            self.ImgEventBG_NoChoose:SetVisibility(UE.ESlateVisibility.Hidden)
            self.BtnSelect:SetVisibility(UE.ESlateVisibility.Visible)
            if UI_SRPG_EventOption_C.bg_sprites[2] then
                local bg_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(UI_SRPG_EventOption_C.bg_sprites[2], 0, 0)
                self.condition_bg:SetBrush(bg_sprite)
                self.condition_bg.Brush.DrawAs = UE.ESlateBrushDrawType.RoundedBox
                self.condition_bg.Brush.OutlineSettings.Width = 12
            end
        end
    else
        self.ImgEventBG_Normal:SetVisibility(UE.ESlateVisibility.Hidden)
        self.ImgEventBG_BanChoose:SetVisibility(UE.ESlateVisibility.Hidden)
        self.ImgEventBG_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
        self.ImgEventBG_NoChoose:SetVisibility(UE.ESlateVisibility.Visible)
        self.BtnSelect:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        self.features:SetVisibility(UE.ESlateVisibility.Hidden)
        self.TxtOptionName:SetVisibility(UE.ESlateVisibility.Hidden)
        --self.TxtOptionDesc:SetVisibility(UE.ESlateVisibility.Hidden)
        self:SetRicchTextVisible(false)
        self.TxtOptionAddDesc:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    if option_info then
        local name = Database.L10n(option_info.nameId)
        local desc = Database.L10n(option_info.descrId)
        local extra_desc = Database.L10n(option_info.extraDescrId)
        self.TxtOptionName:SetText(name)
        --self.TxtOptionDesc:SetText(desc)
        self:SetRichText(desc)
        self.TxtOptionAddDesc:SetText(extra_desc)
        if #extra_desc == 0 then
            self.TxtOptionAddDesc:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
        if option_info.conditionDescId ~= 0 then
            local condition = Database.L10n(option_info.conditionDescId)
            self.TxtCondition:SetText(condition)
        else
            self.features:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
end

function UI_SRPG_EventOption_C:OnButtonPressed()
    if self.is_enable then
        self.ImgEventBG_Selected:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function UI_SRPG_EventOption_C:OnButtonReleased()
    if self.is_enable then
        self.ImgEventBG_Selected:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function UI_SRPG_EventOption_C:ChooseOption()
    if self.is_enable then
        local msg = {}
        msg.event_uuid = self.event_uuid
        msg.index = self.option_index
        Client.send('req_choose_event_option', msg)
    end
end

return UI_SRPG_EventOption_C

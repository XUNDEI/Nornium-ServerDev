local Database = require "_Game.Utils.Database"
local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_ShowReward_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    if not M.BP_Card then
        M.BP_Card = LoadClass("/Game/_Game/Blueprints/UI/UI_Menu/UI_MenuCardBtn.UI_MenuCardBtn_C")
        M.BP_CardRef = UnLua.Ref(M.BP_Card)
        
        M.BP_Curio = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_Curio.UI_Curio_C')
        M.BP_CurioRef = UnLua.Ref(M.BP_Curio)

        M.UI_DescText = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C')
        M.UI_DescTextRef = UnLua.Ref(M.UI_DescText)
    end
end

local COLOR_NORMAL = "#687083"
function M:ShowCard(cardId)
    self.Title:SetText(Database.L10n(99100010))
    ---@type UI_MenuCardBtn_C
    local card = UE.UWidgetBlueprintLibrary.Create(self.Reward, M.BP_Card)

    self.Reward:AddChild(card)

    local margin = UE.FMargin()
    margin.Left = 20
    margin.Right = 20
    card:SetPadding(margin)
    local card_info = {}
    card_info.card_id = cardId
    card_info.upgrade_times = 0
    card_info.index = 0
    card:InitCardUI(card_info)

    ---@type UVerticalBox
    local info = NewObject(UE.UVerticalBox)
    self.Reward:AddChild(info)
    ---@type UHorizontalBoxSlot
    local slot = info.Slot
    ---@type FMargin
    local margin = UE.FMargin()
    margin.Top = 20
    slot:SetPadding(margin)

    local cardInfo = Database.Query("d_srpg_card_base", cardId)
    local desc = {}
    for _, keyword in pairs(cardInfo.keywords) do
        local keywordInfo = Database.Query("d_srpg_card_keyword", keyword)

        ---@type UI_DescText_C
        local keywordInfoWidget = UE.UWidgetBlueprintLibrary.Create(self.Reward, M.UI_DescText)
        info:AddChild(keywordInfoWidget)

        keywordInfoWidget.name:SetText(Database.L10n(keywordInfo.nameId))
        keywordInfoWidget.desc:SetText(Database.L10n(keywordInfo.descrId))
        keywordInfoWidget:vfx_In()

        table.insert(desc, keywordInfoWidget)
    end

    card.OnDissolveEnd:Add(card, function()
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.ShowCard)
        UIManager:GetInstance():RemoveUI(self)
    end)

    self.Modal.OnClicked:Clear()
    self.Modal.OnClicked:Add(self, function()
        if not self.closing then
            self.closing = true
            card:vfx_CardOut()
            for _, v in ipairs(desc) do
                v:vfx_Out()
            end
            self:vfx_Out()
        end
    end)

    card:vfx_CardIn()

    self:vfx_In()
end

function M:ShowCurio(curioId)
    self.Title:SetText(Database.L10n(99100011))
    ---@type UI_Curio_C
    local curio = UE.UWidgetBlueprintLibrary.Create(self.Reward, M.BP_Curio)
    local margin = UE.FMargin()

    self.Reward:AddChild(curio)

    margin.Left = 20
    margin.Right = 20
    curio:SetPadding(margin)
    curio:InitCurioUI(curioId, 0)

    local info = NewObject(UE.UVerticalBox)

    self.Reward:AddChild(info)

    local curioInfo = Database.Query("d_srpg_curio_base", curioId)
    for _, keyword in pairs(curioInfo.keywords) do
        local keywordInfo = Database.Query("d_srpg_card_keyword", keyword)

        local keywordInfoWidget = UE.UWidgetBlueprintLibrary.Create(self.Reward, M.UI_DescText)
        info:AddChild(keywordInfoWidget)

        keywordInfoWidget.name:SetText(Database.L10n(keywordInfo.nameId))
        keywordInfoWidget.desc:SetText(Database.L10n(keywordInfo.descrId))
    end

    self.Modal.OnClicked:Clear()
    self.Modal.OnClicked:Add(self, function()
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.ShowCurio)
        UIManager:GetInstance():RemoveUI(self)
    end)
    
    self:vfx_In()
end

return M

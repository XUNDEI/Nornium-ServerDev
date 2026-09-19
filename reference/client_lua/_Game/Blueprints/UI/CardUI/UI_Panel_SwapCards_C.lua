local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local Database = require "_Game.Utils.Database"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_SwapCards_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    M.BP_Card = LoadClass("/Game/_Game/Blueprints/UI/UI_Menu/UI_MenuCardBtn.UI_MenuCardBtn_C")
    M.BP_CardRef = UnLua.Ref(M.BP_Card)

    self.waitResponse = false
end

---@param Card UI_MenuCardBtn_C
local function ResetCard(Card)
    local offset = Card.Slot:GetOffsets()
    offset.Top = 0
    Card.Slot:SetOffsets(offset)
end

---@param Card UI_MenuCardBtn_C
local function SelectCard(Card)
    local offset = Card.Slot:GetOffsets()
    offset.Top = -40
    Card.Slot:SetOffsets(offset)
end

---@param Card UI_MenuCardBtn_C
function M:OnClickCard(Card)
    if self.selectedCard == Card then
        ResetCard(self.selectedCard)

        self.ReplaceCard:SetVisibility(UE.ESlateVisibility.Hidden)

        self.selectedCard = nil
    else
        if self.selectedCard then
            ResetCard(self.selectedCard)
        end
        
        SelectCard(Card)

        self.ReplaceCard:InitCardUI({
            card_id = Card.CardId,
            upgrade_times = 0,
            index = 0,
        })
        self.ReplaceCard:SetVisibility(UE.ESlateVisibility.Visible)

        self.selectedCard = Card
    end
end

function M:SetUp(cardId)
    self.exceededCardIndex = table.indexof(SrpgController:GetInstance():GetExceededCards(), cardId)

    if self.exceededCardIndex ~= 1 then
        LOG_WARN("replace index not 1")
    end

    self.NewCard:InitCardUI({
        card_id = cardId,
        upgrade_times = 0,
        index = 0,
    })

    self.ReplaceCard:SetVisibility(UE.ESlateVisibility.Hidden)

    local cardsInHand = SrpgController:GetInstance():GetCardsInHand()
    self.cards = {}
    local offsetX = 0
    local zOrder = 0
    for index, cardId in pairs(cardsInHand) do
        ---@type UI_MenuCardBtn_C
        local card = UE.UWidgetBlueprintLibrary.Create(self, M.BP_Card)
        self.Content:AddChild(card)
        table.insert(self.cards, card)
        local card_info = {}
        card_info.card_id = cardId
        card_info.upgrade_times = 0
        card_info.index = index
        card:InitCardUI(card_info)

        local offset = UE.FMargin()
        offset.Left = offsetX
        card.Slot:SetOffsets(offset)
        card.Slot:SetZOrder(zOrder)
        offsetX = offsetX + 150
        zOrder = zOrder + 1

        card.GHSButton_56.OnClicked:Add(card, function()
            self:OnClickCard(card)
        end)
    end

    self.Refresh.OnClicked:Add(self.Refresh, function()
        UIManager:GetInstance():ShowConfirm({
            notice = Database.L10n(99200012),
            confirm = function()
                if not UE.UKismetSystemLibrary.IsValid(self) then return end
                if self.waitResponse then
                    return
                end
    
                Client.send(Protos.REQ_REPLACE_CARD, {
                    index = -1,
                    replace_index = self.exceededCardIndex - 1,
                    replace = false,
                })
    
                self.waitResponse = true
    
                NetworkMessageManager:GetInstance():AddListener(Protos.RES_REPLACE_CARD, self)
            end,
            showCancel = true,
        })
    end)

    self.Certain.OnClicked:Add(self.Certain, function()
        if self.selectedCard then
            if self.waitResponse then
                return
            end
    
            self.waitResponse = true
            Client.send(Protos.REQ_REPLACE_CARD, {
                index = self.selectedCard.Index - 1,
                replace_index = self.exceededCardIndex - 1,
                replace = true,
            })

            NetworkMessageManager:GetInstance():AddListener(Protos.RES_REPLACE_CARD, self)
        end
    end)
end

---@param self UI_Panel_SwapCards_C
---@param parsed_msg ResReplaceCardMessage
M[Protos.RES_REPLACE_CARD] = function(self, result, msgId, parsed_msg)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_REPLACE_CARD, self)

    self.waitResponse = false

    if result == 0 then
        if parsed_msg.req_data.replace then
            SrpgController:GetInstance():ReplaceExceededCard(parsed_msg.req_data.index + 1, parsed_msg.req_data.replace_index + 1)
        else
            SrpgController:GetInstance():RemoveExceededCard(parsed_msg.req_data.replace_index + 1)
        end

        UIManager:GetInstance():RemoveUI(self)

        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.ReplaceCard)
    end
end

return M

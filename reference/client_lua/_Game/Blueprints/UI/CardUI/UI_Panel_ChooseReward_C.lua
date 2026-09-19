local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local Database = require "_Game.Utils.Database"
local SrpgController = require("Module.Srpg.SrpgController")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_ChooseReward_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    if not M.BP_CardRef then
        M.BP_Card = LoadClass("/Game/_Game/Blueprints/UI/UI_Menu/UI_MenuCardBtn.UI_MenuCardBtn_C")
        M.BP_CardRef = UnLua.Ref(M.BP_Card)
    end
end

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CREATE_CHOOSE_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHOOSE_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_REFRESH_CHOOSE_CARD, self)

    MessageManager:GetInstance():AddListener(SrpgController.UpdateCardSelection, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CREATE_CHOOSE_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHOOSE_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_REFRESH_CHOOSE_CARD, self)

    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateCardSelection, self)
end

function M:Setup(UUID)
    self.UUID = UUID

    self.Title:SetText(Database.L10n(99100008))

    self.Certain.OnClicked:Add(self, function()
        if not self.SelectCard then
            return
        end
        if self.waitingResponse then
            return
        end

        self.waitingResponse = true
        Client.send(Protos.REQ_CHOOSE_CARD, {
            select_uuid = self.UUID,
            index = self.SelectCard.Index - 1,
        })
    end)
    self.Refresh.OnClicked:Add(self, function()
        if self.waitingResponse then
            return
        end

        self.waitingResponse = true
        Client.send(Protos.REQ_REFRESH_CHOOSE_CARD, {
            select_uuid = self.UUID,
        })
    end)
    self.Overview.OnClicked:Add(self, function()
        ---@type UI_OverView_C
        local overview = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_OverView.UI_OverView_C'))

        UIManager:GetInstance():AddUI(overview)
 
        overview:SetUp()
    end)

    --免费刷新次数和费用降低
    self.freeRefreshTime = SrpgController:GetInstance():GetFreeCardRefreshTime()
    self.refreshCostModifier = SrpgController:GetInstance():GetCardRefreshCostModifier()

    LOG_INFO("refresh", self.freeRefreshTime, self.refreshCostModifier)
    
    self:UpdatePanel()
end

function M:ReqCreateCardsForSelect()
    self.waitingResponse = true
    Client.send(Protos.REQ_CREATE_CHOOSE_CARD, {
        select_uuid = self.UUID
    })
end

---@param self UI_Panel_ChooseReward_C
---@param parsed_msg ResCreateChooseCardMessage
M[Protos.RES_CREATE_CHOOSE_CARD] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        SrpgController:GetInstance():CreateCardsForSelect(parsed_msg.res_create_choose_card, self.UUID)
    end
end

---@param self UI_Panel_ChooseReward_C
---@param parsed_msg ResRefreshChooseCardMessage
M[Protos.RES_REFRESH_CHOOSE_CARD] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        self:Close(function()
            SrpgController:GetInstance():RefreshCardsForSelect(parsed_msg.res_refresh_choose_card, self.UUID)
        end)
    end
end


---@param self UI_Panel_ChooseReward_C
---@param parsed_msg ResChooseCardMessage
M[Protos.RES_CHOOSE_CARD] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        self:Close(function()
            SrpgController:GetInstance():ChooseCard(self.UUID)
        end)
    end
end

---@param self UI_Panel_ChooseReward_C
M[SrpgController.UpdateCardSelection] = function(self)
    self:UpdatePanel()
end

function M:UpdatePanel()
    local cardSelectionInfo = SrpgController:GetInstance():GetCardsForSelect(self.UUID)
    if not cardSelectionInfo then
        LOG_WARN("Card selection UUID not exist", self.UUID)
    end

    local cards = cardSelectionInfo.card_ids
    if not cards or #cards == 0 then
        self:ReqCreateCardsForSelect()
        return
    end

    self.selectedCard = nil

    self.CardArray:Clear()
    self.Reward:ClearChildren()

    self.poolInfo = Database.Query("d_srpg_card_pool", cardSelectionInfo.pool_id)

    local price = self.poolInfo.refreshCost[2]

    local refreshTimeLimit = self.poolInfo.refreshTime

    if self.freeRefreshTime > cardSelectionInfo.refresh_times then
        price = 0
    else
        price = math.max(0, price + self.refreshCostModifier)
    end

    local currency = SrpgController:GetInstance():GetResource(self.poolInfo.refreshCost[1])
    local cost_info = string.format('%d/%d', price, currency)
    self.num_need:SetText(cost_info)
    self.refreshTime:SetText(tostring(refreshTimeLimit - cardSelectionInfo.refresh_times))
    if currency < price or cardSelectionInfo.refresh_times >= refreshTimeLimit then
        self.Refresh:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Refresh:SetVisibility(UE.ESlateVisibility.Visible)
    end

    for i = 1, #cards do
        ---@type UI_MenuCardBtn_C
        local card = UE.UWidgetBlueprintLibrary.Create(self, M.BP_Card)
        local margin = UE.FMargin()
        margin.Left = 50
        margin.Right = 50
        card:SetPadding(margin)
        local card_info = {}
        card_info.card_id = cards[i]
        card_info.upgrade_times = 0
        card_info.index = i
        card:InitCardUI(card_info)
        self.Reward:AddChild(card)
        self.CardArray:Add(card)
        card.OnBtnClicked:Add(self, self.OnClickCard)
        card.CanvasPanel_0:SetRenderOpacity(0)
    end

    self:PlayCardAnim()
end

function M:Close(callback)
    if not self.closing then
        self.closing = true
        self:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
        self.CardArray[1].OnDissolveEnd:Add(self.CardArray[1], function()
            if callback then
                callback()
            end
            UIManager:GetInstance():RemoveUI(self)
        end)

        local select_card_num = self.CardArray:Length()
        for i = 1, select_card_num do
            self.CardArray[i]:vfx_CardOut()
        end
    end
end

function M:OnClickCard(card)
    if card == self.SelectCard then
        self.SelectCard:SelectCard(false)
        self.SelectCard = nil
    else
        local select_card_num = self.CardArray:Length()
        for i = 1, select_card_num do
            self.CardArray[i]:SelectCard(card == self.CardArray[i])
        end
        self.SelectCard = card
    end
end

return M

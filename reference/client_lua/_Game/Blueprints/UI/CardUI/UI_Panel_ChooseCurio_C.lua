local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local Database = require "_Game.Utils.Database"
local SrpgController = require("Module.Srpg.SrpgController")
local SrpgModel = require("Module.Srpg.SrpgModel")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_ChooseCurio_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    if not M.BP_Card_PanelRef then
        M.BP_Card = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_Curio.UI_Curio_C')
        M.BP_CardRef = UnLua.Ref(M.BP_Card)
        M.BP_Card_Panel = LoadClass("/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_Panel_ChooseCurio.UI_Panel_ChooseCurio_C")
        M.BP_Card_PanelRef = UnLua.Ref(M.BP_Card_Panel)
    end
end

function M:Construct()
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CREATE_CHOOSE_CURIO, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHOOSE_CURIO, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_REFRESH_CHOOSE_CURIO, self)

    MessageManager:GetInstance():AddListener(SrpgController.UpdateCurioSelection, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CREATE_CHOOSE_CURIO, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHOOSE_CURIO, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_REFRESH_CHOOSE_CURIO, self)
    
    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateCurioSelection, self)
end

function M:Setup(UUID)
    self.UUID = UUID

    self.Title:SetText(Database.L10n(99100009))

    self.Certain.OnClicked:Add(self, function()
        if self.SelectCard then
            if self.waitingResponse then
                return
            end

            self.waitingResponse = true
            Client.send(Protos.REQ_CHOOSE_CURIO, {
                select_uuid = self.UUID,
                index = self.SelectCard.Index - 1,
            })
        end
    end)
    self.Refresh.OnClicked:Add(self, function()
        if self.waitingResponse then
            return
        end

        self.waitingResponse = true
        Client.send(Protos.REQ_REFRESH_CHOOSE_CURIO, {
            select_uuid = self.UUID,
        })
    end)
    self.Overview.OnClicked:Add(self, function()
        ---@type UI_OverView_C
        local overview = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_OverView.UI_OverView_C'))

        UIManager:GetInstance():AddUI(overview)
 
        overview:SetUp()
    end)

    self:UpdatePanel()
end

function M:ReqCreateCuriosForSelect()
    self.waitingResponse = true
    Client.send(Protos.REQ_CREATE_CHOOSE_CURIO, {
        select_uuid = self.UUID
    })
end

---@param self M
---@param parsed_msg ResCreateChooseCurioMessage
M[Protos.RES_CREATE_CHOOSE_CURIO] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        SrpgController:GetInstance():CreateCuriosForSelect(parsed_msg.res_create_choose_curio, self.UUID)
    end
end

---@param self SelectCardController
---@param parsed_msg ResRefreshChooseCurioMessage
M[Protos.RES_REFRESH_CHOOSE_CURIO] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        SrpgController:GetInstance():RefreshCuriosForSelect(parsed_msg.res_refresh_choose_curio, self.UUID)

        self:Close()
    end
end

---@param self M
---@param parsed_msg ResChooseCurioMessage
M[Protos.RES_CHOOSE_CURIO] = function(self, result, msgId, parsed_msg)
    self.waitingResponse = false
    if result == 0 then
        local curioIndex = 0
        if self.SelectCard then
            curioIndex = self.SelectCard.Index
        end

        self:Close()

        SrpgController:GetInstance():ChooseCurio(self.UUID, curioIndex)
    end
end

M[SrpgController.UpdateCurioSelection] = function(self)
    self:UpdatePanel()
end

function M:UpdatePanel()
    local curioSelectionInfo = SrpgController:GetInstance():GetCuriosForSelect(self.UUID)
    if not curioSelectionInfo then
        LOG_WARN("Curios selection UUID not exist", self.UUID)
    end

    local curios = curioSelectionInfo.curio_ids
    if not curios or #curios == 0 then
        self:ReqCreateCuriosForSelect()
        return
    end

    self.poolInfo = Database.Query("d_srpg_curio_pool", curioSelectionInfo.pool_id)

    local price = self.poolInfo.refreshCost[2]

    local refreshTimeLimit = self.poolInfo.refreshTime

    local currency = SrpgController:GetInstance():GetResource(self.poolInfo.refreshCost[1])

    local cost_info = string.format('%d/%d', price, currency)

    self.num_need:SetText(cost_info)
    self.refreshTime:SetText(tostring(refreshTimeLimit - curioSelectionInfo.refresh_times))

    if currency < price or curioSelectionInfo.refresh_times >= refreshTimeLimit then
        self.Refresh:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Refresh:SetVisibility(UE.ESlateVisibility.Visible)
    end

    self.CardArray:Clear()
    self.Reward:ClearChildren()

    for i = 1, #curios do
        ---@type UI_Curio_C
        local card = UE.UWidgetBlueprintLibrary.Create(self, M.BP_Card)
        local margin = UE.FMargin()
        margin.Left = 50
        margin.Right = 50
        card:SetPadding(margin)
        card:InitCurioUI(curios[i], i)
        self.Reward:AddChild(card)
        self.CardArray:Add(card)
        card.OnBtnClicked:Add(self, self.OnClickCard)
    end
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
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

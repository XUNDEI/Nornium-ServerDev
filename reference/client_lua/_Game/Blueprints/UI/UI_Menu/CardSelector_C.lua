local Database = require("_Game.Utils.Database")
local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local hex_grid = require "Helper.hex_grid"
local QuestSystem = require "Module.Quest.QuestSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type CardSelector_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    if not M.UI_DescTextRef then
        M.UI_MenuCardBtn = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_MenuCardBtn.UI_MenuCardBtn_C')
        M.UI_MenuCardBtnRef = UnLua.Ref(M.UI_MenuCardBtn)
        M.UI_DescText = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C')
        M.UI_DescTextRef = UnLua.Ref(M.UI_DescText)
        M.MainPosCheckbox = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/MainPosCheckbox.MainPosCheckbox_C')
        M.MainPosCheckboxRef = UnLua.Ref(M.MainPosCheckbox)
        M.RareTexture = {
            [1] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_1_png.card_1_png'),
            [2] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_2_png.card_2_png'),
            [3] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_3_png.card_3_png'),
            [4] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_4_png.card_4_png'),
            [5] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_5_png.card_5_png'),
            [6] = UE.UObject.Load('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/card_6_png.card_6_png'),
        }
        M.FrameTextureRef = {
            UnLua.Ref(M.RareTexture[1]),
            UnLua.Ref(M.RareTexture[2]),
            UnLua.Ref(M.RareTexture[3]),
            UnLua.Ref(M.RareTexture[4]),
            UnLua.Ref(M.RareTexture[5]),
            UnLua.Ref(M.RareTexture[6]),
        }
    end

    NetworkMessageManager:GetInstance():AddListener(Protos.RES_PLACE_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_DEMOLITION_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_UPGRADE_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_RECALL_CARD, self)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_PLACE_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_DEMOLITION_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_UPGRADE_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_RECALL_CARD, self)
end

function M:InitUI()
    ---@type UI_MenuCardBtn_C[]
    self.cards = {}
    ---@type UI_MenuCardBtn_C[]
    self.selectedCards = {}
    self.upgradeCardId = 0
    self.mainPosHex = nil
    ---@type MainPosCardPosInfo
    self.cardPosInfo = nil
    self.cardPosIndex = 0

    self.Exit.OnClicked:Add(self, self.PlayCloseAnimation)

    self.Btn_Play.OnClicked:Add(self, self.PlaceCard)

    self.Btn_Delete.OnClicked:Add(self, self.RemoveCard)

    self.Btn_Upgrade.OnClicked:Add(self, self.UpgradeCard)

    self.Btn_Recall.OnClicked:Add(self, self.RecallCard)

    self.mainPosButtons = {}
end

function M:Show(mainPosHex)
    self:SetUpSwitcher(mainPosHex)

    self:SwitchTo(mainPosHex)

    self:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

    self:vfx_In()
end

function M:SetUpSwitcher(mainPosHex)
    self.MainPosList:ClearChildren()
    local mainPosInfo = SrpgController:GetInstance():GetMainPosInfo()
    self.MainPosGroup:ResetToggleState()

    for _, info in pairs(mainPosInfo) do
        for _, attachInfo in ipairs(info.main_pos_attach_infos) do
            if attachInfo.main_pos_attach_extra == SrpgModel.AttachType.Card then
                ---@type MainPosCheckbox_C
                local mainPosCheckbox = UE.UWidgetBlueprintLibrary.Create(self.MainPosList, M.MainPosCheckbox)

                self.MainPosList:AddChild(mainPosCheckbox)
                mainPosCheckbox.MainPosCheckBox.CheckBoxGroup = self.MainPosGroup

                local cardId = attachInfo.main_pos_card_pos_info.card_id
                if cardId ~= 0 then
                    local cardInfo = Database.Query("d_srpg_card_base", cardId)

                    local iconPath = "Texture2D'/Game/_Game/TP_New/SRPG_OverView/card_img/%s.%s'"
                    iconPath = string.format(iconPath, cardInfo.img, cardInfo.img)
                    local icon = UE.UObject.Load(iconPath)
                    if icon then
                        mainPosCheckbox.CardIcon:SetBrushFromTexture(icon)
                    end
                    mainPosCheckbox.rare:SetBrushFromAtlasInterface(M.RareTexture[cardInfo.rarity])
                end
                mainPosCheckbox.CardIcon:SetVisibility(cardId ~= 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
                mainPosCheckbox.rare:SetVisibility(cardId ~= 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

                if hex_grid.equal(mainPosHex, info.hex) then
                    mainPosCheckbox.MainPosCheckBox:SetIsCheckedAndFireEvent(true)
                end

                mainPosCheckbox.MainPosCheckBox.OnCheckStateChanged:Add(self, function(_, isOn)
                    if isOn then
                        self:SwitchTo(info.hex)
                    end
                end)
            end
        end
    end
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

function M:PlayCloseAnimation()
    if not self.closing then
        self.closing = true
        self:vfx_Out()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.PlayCloseAnimation)

function M:SwitchTo(mainPosHex)
    self.mainPosHex = mainPosHex
    local cardsInHand = SrpgController:GetInstance():GetCardsInHand()

    local mainPosInfo = SrpgController:GetInstance():GetMainPosByHex(self.mainPosHex)

    self.selectedCards = {}
    self.upgradeCardId = 0

    self.cards = {}
    self.Content:ClearChildren()
    local offsetX = 0
    local zOrder = 0
    for index, cardId in pairs(cardsInHand) do
        ---@type UI_MenuCardBtn_C
        local card = UE.UWidgetBlueprintLibrary.Create(self.Content, M.UI_MenuCardBtn)
        self.Content:AddChild(card)
        table.insert(self.cards, card)
        local card_info = {}
        card_info.card_id = cardId
        card_info.upgrade_times = 0
        card_info.index = index - 1
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

    for i, info in ipairs(mainPosInfo.main_pos_attach_infos) do
        if info.main_pos_attach_extra == SrpgModel.AttachType.Card then
            self.cardPosInfo = info.main_pos_card_pos_info
            self.cardPosIndex = i
        end
    end

    if self.cardPosInfo.card_id ~= 0 then
        self.upgradeCardId = self.cardPosInfo.card_id
        self:UpdateCardSlot(self.upgradeCardId)
    else
        self:UpdateCardSlot()
    end
    self.CardSlot:SetVisibility(self.cardPosInfo.card_id ~= 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    self.CardOptions:SetVisibility(self.cardPosInfo.card_id ~= 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    self.NoCardOptions:SetVisibility(self.cardPosInfo.card_id == 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)

    local upgradeCost = Database.Query("d_srpg_card_pos", self.cardPosInfo.card_pos_id).upgradeCost

    local upgradeAffordable = upgradeCost[2] <= SrpgController:GetInstance():GetResource(upgradeCost[1])

    local upgradeAvailable = false
    if self.cardPosInfo.card_id > 0 then
        local cardConfig = Database.Query("d_srpg_card_base", self.cardPosInfo.card_id)
        upgradeAvailable = cardConfig.id ~= cardConfig.upgradeCard and table.countBy(self.cards, function(card)
            return card.CardId == self.cardPosInfo.card_id
        end) >= 2
    end

    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = upgradeAffordable and UE.UKismetMathLibrary.LinearColor_White() or UE.UKismetMathLibrary.LinearColor_Red()
    self.res_value:SetColorAndOpacity(textColor)

    self.res_value:SetText(tostring(-upgradeCost[2]))
    self.Btn_Upgrade:SetIsEnabled(upgradeAffordable and upgradeAvailable)

    local demolitionAvailable = not QuestSystem:GetInstance():IsDemolitionBlocked()

    self.Btn_Delete:SetIsEnabled(demolitionAvailable)

    local recallCost = Database.Query("d_srpg_card_pos", self.cardPosInfo.card_pos_id).recallCost
    local recallAffordable = recallCost[2] <= SrpgController:GetInstance():GetResource(recallCost[1])
    local recallAvailable = #SrpgController:GetInstance():GetCardsInHand() < 10
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = recallAffordable and UE.UKismetMathLibrary.LinearColor_White() or UE.UKismetMathLibrary.LinearColor_Red()
    self.res_value_1:SetColorAndOpacity(textColor)
    self.res_value_1:SetText(tostring(-recallCost[2]))

    self.Btn_Recall:SetIsEnabled(recallAffordable and recallAvailable)

    self:UpdateCardInfo()
end

function M:Refresh(mainPosHex)
    self:SetUpSwitcher(mainPosHex)
    self:SwitchTo(mainPosHex)
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

function M:UpdateCardSlot(cardId)
    if cardId then
        self.CardSlot:InitCardUI({ card_id = cardId })
    end
    self.CardSlot:SetVisibility(cardId and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
end

function M:UpdateCardInfo(cardId)
    if cardId then
        self.CardInfo:InitCardUI({ card_id = cardId })

        local cardConfig = Database.Query("d_srpg_card_base", cardId)

        local keywords = cardConfig.keywords

        self.RaceList:ClearChildren()
        for _, keywordId in pairs(keywords) do
            local keywordInfo = Database.Query("d_srpg_card_keyword", keywordId)
            local desc = Database.L10n(keywordInfo.descrId)

            ---@type UI_DescText_C
            local keywordDesc = NewObject(M.UI_DescText, self.RaceList)
            self.RaceList:AddChild(keywordDesc)
            
            keywordDesc.name:SetText(Database.L10n(keywordInfo.nameId))
            keywordDesc.desc:SetText(desc)

            keywordDesc:vfx_In()
        end

        self.CardInfo:vfx_CardIn()
    end
    self.CardInfo:SetVisibility(cardId and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    self.RaceList:SetVisibility(cardId and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
end

---@param Card UI_MenuCardBtn_C
function M:OnClickCard(Card)
    if #self.selectedCards > 0 then
        if table.indexof(self.selectedCards, Card) then
            table.removebyvalue(self.selectedCards, Card)
            table.removebyvalue(self.selectedCards, Card)
            if #self.selectedCards == 0 then
                self:UpdateCardInfo()
            end
            ResetCard(Card)
        else
            ResetCard(self.selectedCards[1])
            self.selectedCards = { Card }
            self:UpdateCardInfo(Card.CardId)
            SelectCard(Card)
        end
    elseif #self.selectedCards == 0 then
        table.insert(self.selectedCards, Card)
        self:UpdateCardInfo(Card.CardId)
        SelectCard(Card)
    end
end

function M:PlaceCard()
    if #self.selectedCards == 1 then
        LOG_INFO("Place Card")
        Client.send(Protos.REQ_PLACE_CARD, {
            hex = self.mainPosHex,
            attach_index = self.cardPosIndex - 1,
            index_in_hand = self.selectedCards[1].Index,
        })
    end
end

function M:RemoveCard()
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(99200011),
        confirm = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            Client.send(Protos.REQ_DEMOLITION_CARD, {
                hex = self.mainPosHex,
                attach_index = self.cardPosIndex - 1,
            })
        end,
        showCancel = true,
    })
end

function M:UpgradeCard()
    if self.cardPosInfo.card_id > 0 then
        local indexInHand = {}
        for _, value in pairs(self.cards) do
            if self.cardPosInfo.card_id == value.CardId then
                table.insert(indexInHand, value.Index)

                if #indexInHand == 2 then
                    table.sort(indexInHand, function(a, b)
                        if a > b then
                            return true
                        end
                    end)

                    self.upgradeCards = indexInHand

                    Client.send(Protos.REQ_UPGRADE_CARD, {
                        hex = self.mainPosHex,
                        attach_index = self.cardPosIndex - 1,
                        index_in_hand = indexInHand,
                    })
                    return
                end
            end
        end
    end
end

function M:RecallCard()
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(99200013),
        confirm = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            Client.send(Protos.REQ_RECALL_CARD, {
                hex = self.mainPosHex,
                attach_index = self.cardPosIndex - 1,
            })
        end,
        showCancel = true,
    })
end

---@param self CardSelector_C
M[Protos.RES_PLACE_CARD] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():PlaceCard(self.mainPosHex, self.cardPosIndex, self.selectedCards[1].Index)
        
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:UpdateMainPos(self.mainPosHex)

        self.CardInfo.OnDissolveEnd:Clear()
        self.CardInfo.OnDissolveEnd:Add(self, function()
            self:Refresh(self.mainPosHex)
        end)
        self.CardInfo:vfx_CardOut()
    else
        self:Refresh(self.mainPosHex)
    end
end

---@param self CardSelector_C
M[Protos.RES_DEMOLITION_CARD] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():RemoveCard(self.mainPosHex, self.cardPosIndex)
        
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:UpdateMainPos(self.mainPosHex)
    end

    self:Refresh(self.mainPosHex)
    MessageManager:GetInstance():Broadcast('OnMsg_Demolition_Card')
end

---@param self CardSelector_C
M[Protos.RES_UPGRADE_CARD] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():UpgradeCard(self.mainPosHex, self.cardPosIndex, self.upgradeCards)
    end

    self:Refresh(self.mainPosHex)
end

---@param self CardSelector_C
M[Protos.RES_RECALL_CARD] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():RemoveCard(self.mainPosHex, self.cardPosIndex)
        
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController:UpdateMainPos(self.mainPosHex)
    end

    self:Refresh(self.mainPosHex)
    MessageManager:GetInstance():Broadcast('OnMsg_Recall_Card')
end

return M

local SrpgController = require("Module.Srpg.SrpgController")
local Database = require("_Game.Utils.Database")
local UIUtils = require "_Game.Utils.UIUtils"
local PlayerSystem = require "Module.Player.PlayerSystem"
local SrpgModel = require("Module.Srpg.SrpgModel")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_OverView_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

local CARDS_PER_LINE = 7
local CURIOS_PER_LINE = 6
local RACE_PER_LINE = 3

function M:Initialize()
    if not M.UI_Overview_BossIcon then
        M.Font = LoadObject('/Game/_Game/Fonts/ZiHunBingYuYaSong_Font.ZiHunBingYuYaSong_Font')
        M.FontRef = UnLua.Ref(M.Font)
        M.UI_Overview_BossIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_Overview_BossIcon.UI_Overview_BossIcon_C')
        M.UI_Overview_BossIconRef = UnLua.Ref(M.UI_Overview_BossIcon)
        M.UI_DescText = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C')
        M.UI_DescTextRef = UnLua.Ref(M.UI_DescText)

        M.UI_CardIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_CardIcon.UI_CardIcon_C')
        M.UI_CardIconRef = UnLua.Ref(M.UI_CardIcon)

        M.UI_Upgrade = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_Upgrade.UI_Upgrade_C')
        M.UI_UpgradeRef = UnLua.Ref(M.UI_Upgrade)

        M.UI_Card_Race = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_Card_Race.UI_Card_Race_C')
        M.UI_Card_RaceRef = UnLua.Ref(M.UI_Card_Race)

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

        M.RARITY_ICON = {
            [1] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_1_png.upgrade_rarity_1_png'),
            [2] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_1_png.upgrade_rarity_1_png'),
            [3] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_2_png.upgrade_rarity_2_png'),
            [4] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_2_png.upgrade_rarity_2_png'),
            [5] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_3_png.upgrade_rarity_3_png'),
            [6] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_3_png.upgrade_rarity_3_png'),
            [7] = LoadObject('/Game/_Game/TP_New/Universe_CardShow/Frames/upgrade_rarity_4_png.upgrade_rarity_4_png'),
        }
        M.RARITY_ICONRef = {
            UnLua.Ref(M.RARITY_ICON[1]),
            UnLua.Ref(M.RARITY_ICON[2]),
            UnLua.Ref(M.RARITY_ICON[3]),
            UnLua.Ref(M.RARITY_ICON[4]),
            UnLua.Ref(M.RARITY_ICON[5]),
            UnLua.Ref(M.RARITY_ICON[6]),
            UnLua.Ref(M.RARITY_ICON[7]),
        }
    end
end

local RESOURCE_NAME = {
    99200001,
    99200003,
    99200005,
    99200007,
    99200009,
}
local RESOURCE_DESC = {
    99200002,
    99200004,
    99200006,
    99200008,
    99200010,
}

function M:ShowResourceInfo(type)
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())

    UIManager:GetInstance():ShowDesc(screenPos, Database.L10n(RESOURCE_NAME[type]), Database.L10n(RESOURCE_DESC[type]))
end

function M:Close()
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    if playerController.BP_PlayerController_UniverseMenu.UI_Menu then
        playerController.BP_PlayerController_UniverseMenu.UI_Menu:Show()
    end

    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

function M:SetUp()
    self.Back.OnClicked:Add(self.Back, function()
        self:Close()
    end)

    self.Modal.OnClicked:Add(self.Modal, function()
        self:CloseInfo()
    end)

    self.BtnHp.OnClicked:Add(self.BtnHp, function()
        self:ShowResourceInfo(4)
    end)

    self.BtnEnergy.OnClicked:Add(self.BtnEnergy, function()
        self:ShowResourceInfo(5)
    end)

    self.BtnRes_2.OnClicked:Add(self.BtnRes_2, function()
        self:ShowResourceInfo(2)
    end)

    self:UpdateResource()
    self:UpdateBossProgress()
    self:UpdateCharacters()
    self:UpdateTempleBuff()
    self:UpdateGrowthInfo()
    self:UpdateCardPos()
    self:UpdateCardInHand()
    self:UpdateCurios()
    self:UpdateRaceInfo()

    self:PlayAnimation(self.In, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
end

function M:UpdateResource()
    self.HP:SetText(SrpgController:GetInstance():GetCurHp())
    self.Res:SetText(SrpgController:GetInstance():GetResource(2))
    self.Energy:SetText(SrpgController:GetInstance():GetBoatEnergy())
end

function M:UpdateBossProgress()
    local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
    local bossConfig = Database.Query("d_srpg_level_boss", bossConfigId)
    local maxStep = bossConfig.appearTime[#(bossConfig.appearTime)] + 3

    local step = SrpgController:GetInstance():GetStep()

    self.BossProgress:SetPercent(step / maxStep)
    self.Step:SetText(step)

    for _, wave in pairs(bossConfig.appearTime) do
        local percent = wave / maxStep
        ---@type UI_Overview_BossIcon_C
        local bossIcon = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Overview_BossIcon)

        self.BossIcon:AddChild(bossIcon)

        local anchors = UE.FAnchors()
        local offsets = UE.FMargin()
    
        anchors.Maximum = UE.FVector2D(percent, 0.5)
        anchors.Minimum = UE.FVector2D(percent, 0.5)

        bossIcon.Slot:SetAlignment(UE.FVector2D(0.5, 0.5))
        bossIcon.Slot:SetAutoSize(true)
        bossIcon.Slot:SetAnchors(anchors)
        bossIcon.Slot:SetOffsets(offsets)

        bossIcon.Step:SetText(wave)
    end
end

function M:UpdateCharacters()
    local characterFightData = SrpgController:GetInstance():GetCharacterFightData()

    for index, data in ipairs(characterFightData) do
        if index > 3 then
            break
        end

        self["character_text" .. index]:SetVisibility(data.character_id == 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        self["character_" .. index]:SetVisibility(data.character_id ~= 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

        if data.character_id > 0 then
            local characterInfo = Database.Query("d_character", data.character_id)

            local headPath = UIUtils.GetCharacterIdolIcon(data.character_id, characterInfo.headRes)
            local iconTexture = LoadObject(headPath)
            if iconTexture then
                self["character_icon" .. index]:SetBrushFromAtlasInterface(iconTexture)
            end

            local hpMax = UIUtils.GetCharacterAllAttr(data.character_id)[1001]
            local currentHp = data.cur_hp or hpMax

            self["character_HP" .. index]:SetPercent(currentHp / hpMax)
        end
    end
end

local TEMP_BUFF_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/temp_buff_icon/%s.%s'

function M:UpdateTempleBuff()
    local tempBuff = SrpgController:GetInstance().model.definiteBuffs[1]

    self.TempBuff:SetVisibility(tempBuff and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    if tempBuff then
        local buffInfo = Database.Query("d_srpg_temp_buff", tempBuff.buff_id)

        self.TempBuffIcon:SetBrushFromTexture(LoadObject(string.format(TEMP_BUFF_ICON_PATH, buffInfo.icon, buffInfo.icon)))
        self.TempBuffName:SetText(Database.L10n(buffInfo.nameId))
    end
end

function M:UpdateGrowthInfo()
    ---@type PlayerUniverseGrowthNodeInfo[]
    local growthNodes = PlayerSystem:GetInstance().PlayerInfo.player_universe_growth_node_infos

    for _, node in pairs(growthNodes) do
        ---@type UTextBlock
        local text = NewObject(UE.UTextBlock)

        self.GrowEffectList:AddChild(text)

        local margin = UE.FMargin()
        margin.Left = 20
        margin.Top = 20

        text.Slot:SetPadding(margin)

        local fontInfo = text.Font
        fontInfo.FontObject = M.Font

        text:SetFont(fontInfo)

        local itemInfo = Database.Query("d_srpg_growth", node.node_id)
        local itemNameFormat = Database.L10n(itemInfo.nameId)
        local arg = itemInfo.display[node.node_rank]

        local itemName = string.format(itemNameFormat, arg)

        text:SetText(itemName)
    end
end

function M:UpdateCardPos()
    local mainPosInfo = SrpgController:GetInstance():GetMainPosInfo()

    local cardSlotCount = 0
    for _, info in pairs(mainPosInfo) do
        for _, attachInfo in ipairs(info.main_pos_attach_infos) do
            if attachInfo.main_pos_attach_extra == SrpgModel.AttachType.Card then
                ---@type UI_CardIcon_C
                local cardSlot = UE.UWidgetBlueprintLibrary.Create(self, M.UI_CardIcon)

                self.CardPos:AddChild(cardSlot)

                cardSlot.Slot:SetRow(math.floor(cardSlotCount / CARDS_PER_LINE))
                cardSlot.Slot:SetColumn(math.floor(cardSlotCount % CARDS_PER_LINE))

                local cardId = attachInfo.main_pos_card_pos_info.card_id
                if cardId ~= 0 then
                    local cardInfo = Database.Query("d_srpg_card_base", cardId)

                    local iconPath = "Texture2D'/Game/_Game/TP_New/SRPG_OverView/card_img/%s.%s'"
                    iconPath = string.format(iconPath, cardInfo.img, cardInfo.img)
                    local icon = UE.UObject.Load(iconPath)
                    if icon then
                        cardSlot.card:SetBrushFromTexture(icon)
                        cardSlot.rare:SetBrushFromAtlasInterface(M.RareTexture[cardInfo.rarity])
                    end
                end
                cardSlot.card:SetVisibility(cardId ~= 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
                cardSlot.rare:SetVisibility(cardId ~= 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)

                cardSlot.button.OnClicked:Add(cardSlot, function()
                    self:ShowCardInfo(cardId)
                end)

                cardSlotCount = cardSlotCount + 1
            end
        end
    end
end

function M:UpdateCardInHand()
    local cardsInHand = SrpgController:GetInstance():GetCardsInHand()

    local cardCount = 0
    for _, cardId in pairs(cardsInHand) do
        ---@type UI_CardIcon_C
        local cardIcon = UE.UWidgetBlueprintLibrary.Create(self, M.UI_CardIcon)

        self.CardInHand:AddChild(cardIcon)

        cardIcon.Slot:SetRow(math.floor(cardCount / CARDS_PER_LINE))
        cardIcon.Slot:SetColumn(math.floor(cardCount % CARDS_PER_LINE))

        local cardInfo = Database.Query("d_srpg_card_base", cardId)

        local iconPath = "Texture2D'/Game/_Game/TP_New/SRPG_OverView/card_img/%s.%s'"
        iconPath = string.format(iconPath, cardInfo.img, cardInfo.img)
        local icon = UE.UObject.Load(iconPath)
        if icon then
            cardIcon.card:SetBrushFromTexture(icon)
            cardIcon.rare:SetBrushFromAtlasInterface(M.RareTexture[cardInfo.rarity])
        end

        cardIcon.button.OnClicked:Add(cardIcon, function()
            self:ShowCardInfo(cardId)
        end)

        cardCount = cardCount + 1
    end
end

local UPGRADE_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/upgrade_icon/%s.%s'

function M:UpdateCurios()
    local curios = SrpgController:GetInstance():GetCurios()

    local curioCount = 0
    for _, curioId in ipairs(curios) do
        ---@type UI_Upgrade_C
        local curio = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Upgrade)
        self.Curios:AddChild(curio)

        curio.Slot:SetRow(math.floor(curioCount / CURIOS_PER_LINE))
        curio.Slot:SetColumn(math.floor(curioCount % CURIOS_PER_LINE))

        local upgradeInfo = Database.Query("d_srpg_curio_base", curioId)

        curio.rarity:SetBrushFromAtlasInterface(M.RARITY_ICON[upgradeInfo.rarity])
        curio.icon:SetBrushFromTexture(LoadObject(string.format(UPGRADE_ICON_PATH, upgradeInfo.icon, upgradeInfo.icon)))

        curio.BtnUpgrade.OnClicked:Add(curio, function()
            self:ShowCurioInfo(curioId)
        end)

        curioCount = curioCount + 1
    end
end

local RACE_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/card_race_icon/%s.%s'
local LEVEL_PATH = '/Game/_Game/Blueprints/UI/UI_Menu/UI_Level%d.UI_Level%d_C'
function M:UpdateRaceInfo()
    local races = SrpgController:GetInstance():GetActivatedRaces()

    local raceCount = 0
    for raceId, count in pairs(races) do
        if count > 0 then
            ---@type UI_Card_Race_C
            local raceInfoWidget = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Card_Race)

            self.CardRace:AddChild(raceInfoWidget)

            raceInfoWidget.Slot:SetRow(math.floor(raceCount / RACE_PER_LINE))
            raceInfoWidget.Slot:SetColumn(math.floor(raceCount % RACE_PER_LINE))

            raceInfoWidget:ShowRaceInfo(raceId, count)

            raceInfoWidget.BtnRace.OnClicked:Add(raceInfoWidget.BtnRace, function()
                self:ShowRaceInfo(raceId, count)
            end)

            raceCount = raceCount + 1
        end
    end
end

function M:CloseInfo()
    self.InfoPanel:SetVisibility(UE.ESlateVisibility.Hidden)

    self.CardInfo:SetVisibility(UE.ESlateVisibility.Hidden)
    self.RaceList:SetVisibility(UE.ESlateVisibility.Hidden)

    self.CurioInfo:SetVisibility(UE.ESlateVisibility.Hidden)

    self.RaceInfo:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:ShowCardInfo(cardId)
    self:CloseInfo()

    if cardId ~= 0 then
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
        end

        self.InfoPanel:SetVisibility(UE.ESlateVisibility.Visible)
    
        self.CardInfo:SetVisibility(UE.ESlateVisibility.Visible)
        self.RaceList:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:ShowCurioInfo(curioId)
    self:CloseInfo()

    if curioId ~= 0 then
        self.CurioInfo:InitCurioUI(curioId, 0)

        self.InfoPanel:SetVisibility(UE.ESlateVisibility.Visible)
    
        self.CurioInfo:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

local COLOR_ACTIVATED = "#D5541C"
local COLOR_NORMAL = "#687083"
function M:ShowRaceInfo(raceId, raceCount)
    self:CloseInfo()

    local raceInfo = Database.Query("d_srpg_card_race", raceId)
    local descFormat = Database.L10n(raceInfo.descrId)

    local activateIndex = 0
    local descColor = {}

    for index, value in ipairs(raceInfo.effectsArea) do
        table.insert(descColor, COLOR_NORMAL)
        if raceCount >= value then
            activateIndex = index
        end
    end

    if activateIndex > 0 then
        descColor[activateIndex] = COLOR_ACTIVATED
    end

    local desc = string.format(descFormat, table.unpack(descColor))

    self.RaceInfo.name:SetText(Database.L10n(raceInfo.nameId))
    self.RaceInfo.desc:SetText(desc)

    self.InfoPanel:SetVisibility(UE.ESlateVisibility.Visible)

    self.RaceInfo:SetVisibility(UE.ESlateVisibility.Visible)
end

return M

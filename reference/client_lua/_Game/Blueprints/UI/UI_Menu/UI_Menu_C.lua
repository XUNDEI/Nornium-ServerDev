local Database = require("_Game.Utils.Database")
local UIUtils = require "_Game.Utils.UIUtils"
local Client = require "Network.Client"
local hex_grid = require "Helper.hex_grid"
local UniverseUtils = require "_Game.Utils.UniverseUtils"
local QuestSystem = require "Module.Quest.QuestSystem"

local SrpgController = require("Module.Srpg.SrpgController")
local SrpgModel = require("Module.Srpg.SrpgModel")
local Protos = require("Helper.Protos")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Menu_C
local M = UnLua.Class()

M.EnableMove = true

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
    InputAssets.IMC_UI_SystemEntry,
}

InputUtils.RegisterMouseEvent(M)

function M:IA_Menu()
    self.Btn_MainMenu.OnClicked:Broadcast()
end

function M:IA_Switch()
    self.Btn_ToShip.OnClicked:Broadcast()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Menu, UE.ETriggerEvent.Completed, M.IA_Menu)
InputUtils.RegisterUIAction(M, InputAssets.IA_Switch, UE.ETriggerEvent.Completed, M.IA_Switch)

function M:Initialize()
    if not M.BP_GHSFunctionLibraryRef then
        ---@type BP_GHSFunctionLibrary_C
        M.BP_GHSFunctionLibrary = LoadClass("/Game/_Game/Blueprints/Game/BP_GHSFunctionLibrary.BP_GHSFunctionLibrary_C")
        M.BP_GHSFunctionLibraryRef = UnLua.Ref(M.BP_GHSFunctionLibrary)

        M.UI_Upgrade = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_Upgrade.UI_Upgrade_C')
        M.UI_UpgradeRef = UnLua.Ref(M.UI_Upgrade)
        M.UI_Card_Race = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_Card_Race.UI_Card_Race_C')
        M.UI_Card_RaceRef = UnLua.Ref(M.UI_Card_Race)
        M.UI_DescText = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C')
        M.UI_DescTextRef = UnLua.Ref(M.UI_DescText)
        M.UI_SRPG_Event = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Event.UI_SRPG_Event_C')
        M.UI_SRPG_EventRef = UnLua.Ref(M.UI_SRPG_Event)
        M.UI_SRPG_Event1 = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Event1.UI_SRPG_Event1_C')
        M.UI_SRPG_Event1Ref = UnLua.Ref(M.UI_SRPG_Event1)
        M.UI_SRPG_Option_Item = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Option_Item.UI_SRPG_Option_Item_C')
        M.UI_SRPG_Option_ItemRef = UnLua.Ref(M.UI_SRPG_Option_Item)

        M.UI_SRPG_Shop = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Shop/UI_SRPG_Shop.UI_SRPG_Shop_C')
        M.UI_SRPG_ShopRef = UnLua.Ref(M.UI_SRPG_Shop)

        M.UI_OverView = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_OverView/UI_OverView.UI_OverView_C')
        M.UI_OverViewRef = UnLua.Ref(M.UI_OverView)

        M.UI_mission_panel = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_mission_panel.UI_mission_panel_C')
        M.UI_mission_panelRef = UnLua.Ref(M.UI_mission_panel)

        M.CardSelector = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/CardSelector.CardSelector_C')
        M.CardSelectorRef = UnLua.Ref(M.CardSelector)

        M.UI_SRPG_Fight = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Fight/UI_SRPG_Fight.UI_SRPG_Fight_C')
        M.UI_SRPG_FightRef = UnLua.Ref(M.UI_SRPG_Fight)

        M.UI_Panel_SwapCards = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_Panel_SwapCards.UI_Panel_SwapCards_C')
        M.UI_Panel_SwapCardsRef = UnLua.Ref(M.UI_Panel_SwapCards)
        M.UI_Panel_ShowReward_C = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_Panel_ShowReward.UI_Panel_ShowReward_C')
        M.UI_Panel_ShowReward_CRef = UnLua.Ref(M.UI_Panel_ShowReward_C)
        M.UI_Panel_ChooseReward_C = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_Panel_ChooseReward.UI_Panel_ChooseReward_C')
        M.UI_Panel_ChooseReward_CRef = UnLua.Ref(M.UI_Panel_ChooseReward_C)
        M.UI_Panel_ChooseCurio_C = LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_Panel_ChooseCurio.UI_Panel_ChooseCurio_C')
        M.UI_Panel_ChooseCurio_CRef = UnLua.Ref(M.UI_Panel_ChooseCurio_C)

        M.UI_ShipIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_ShipIcon.UI_ShipIcon_C')
        M.UI_ShipIconRef = UnLua.Ref(M.UI_ShipIcon)
        M.UI_BaseIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_BaseIcon.UI_BaseIcon_C')
        M.UI_BaseIconRef = UnLua.Ref(M.UI_BaseIcon)
        M.UI_BossIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_Menu/UI_BossIcon.UI_BossIcon_C')
        M.UI_BossIconRef = UnLua.Ref(M.UI_BossIcon)

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
    
    self.SelectCurioController = nil
end

function M:Construct()
    self.updateResource = function()
        self:UpdateResource()
    end
    MessageManager:GetInstance():AddListener(SrpgModel.ResourceChanged, self.updateResource)
    MessageManager:GetInstance():AddListener(SrpgModel.BoatEnergyChanged, self.updateResource)
    MessageManager:GetInstance():AddListener(SrpgController.EventUpdated, self)
    MessageManager:GetInstance():AddListener(SrpgController.NormalFight, self)
    MessageManager:GetInstance():AddListener(SrpgController.BossFight, self)
    MessageManager:GetInstance():AddListener(SrpgController.StartSelectCard, self)
    MessageManager:GetInstance():AddListener(SrpgController.StartSelectCurio, self)
    MessageManager:GetInstance():AddListener(SrpgController.UpdateUI, self)
    MessageManager:GetInstance():AddListener(SrpgController.UniverseEvent, self)
    MessageManager:GetInstance():AddListener(SrpgController.ReplaceCard, self)
    MessageManager:GetInstance():AddListener(SrpgController.ShowCard, self)
    MessageManager:GetInstance():AddListener(SrpgController.ShowCurio, self)
    MessageManager:GetInstance():AddListener(SrpgController.ShowStory, self)
    MessageManager:GetInstance():AddListener(SrpgController.OpenShop, self)

    self.updateCurios = function()
        self:UpdateCurios()
    end
    MessageManager:GetInstance():AddListener(SrpgController.CuriosUpdated, self.updateCurios)

    self.closeConfirmFightUI = function()
        self:CloseConfirmFightUI()
    end

    -- NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_MAIN_POS_FIGHT, self.closeConfirmFightUI)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_BOSS_FIGHT, self.closeConfirmFightUI)
    -- NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_EVENT_FIGHT, self.closeConfirmFightUI)

    -- NetworkMessageManager:GetInstance():AddListener(Protos.RES_CARD_POS_UNLOCK_CARD, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_EXPLORE, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_UNIVERSE_FIGHT, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_BOSS_FIGHT, self)
end

function M:OpenMenu()
    if self:IsVisible() then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:ShowTopUI(false)
        local ui = gameInstance:AddUMG('UI_CityMenu')
        if ui then
            ui.Team:SetIsEnabled(false)
        end
    end
end

function M:SwitchToBridge()
    if self:IsVisible() then
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController.BP_PlayerController_UniverseMenu:SetUIMenuVisibility(false)
        
        ---@type BP_Character_Menu_C
        local ship = playerController:K2_GetPawn()
        ship.SceneCaptureComponent2D:CaptureScene()
        playerController:Unload3DUI(false)
        playerController:OnOpenBridge()
    end
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener(SrpgModel.ResourceChanged, self.updateResource)
    MessageManager:GetInstance():RemoveListener(SrpgModel.BoatEnergyChanged, self.updateResource)
    MessageManager:GetInstance():RemoveListener(SrpgController.EventUpdated, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.NormalFight, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.BossFight, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.StartSelectCard, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.StartSelectCurio, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.UniverseEvent, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ReplaceCard, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ShowCard, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ShowCurio, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ShowStory, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.OpenShop, self)

    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateUI, self)

    MessageManager:GetInstance():RemoveListener(SrpgController.CuriosUpdated, self.updateCurios)

    -- NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_MAIN_POS_FIGHT, self.closeConfirmFightUI)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_BOSS_FIGHT, self.closeConfirmFightUI)
    -- NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_EVENT_FIGHT, self.closeConfirmFightUI)

    -- NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CARD_POS_UNLOCK_CARD, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_EXPLORE, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_UNIVERSE_FIGHT, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_BOSS_FIGHT, self)

    if self.SelectCurioController then
        self.SelectCurioController:Delete()
    end
end

function M:Tick(MyGeometry, InDeltaTime)
    self:UpdateAllIcon()
end

function M:InitUI()
    self.OnVisibilityChanged:Add(self, function(ui, visible)
        print('----visible:' .. tostring(visible))
        --隐藏
        if visible == 1 or visible == 2 then
        else
            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        end
    end)

    self.UI_temp_buff.temp_buff_icon.OnClicked:Add(self.UI_temp_buff.temp_buff_icon, function()
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())
        self:ShowBuffInfo(SrpgController:GetInstance().model.definiteBuffs[1].buff_id, screenPos)
    end)

    self.showUI = true
    self.CheckBox_ShowAndHide.OnCheckStateChanged:Add(self.CheckBox_ShowAndHide, function(_, show)
        self:ToggleUI(show)
    end)

    self.UI_mission.Btn_OpenList.OnClicked:Add(self.UI_mission, function()
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController.BP_PlayerController_UniverseMenu.CanTracePlanet = false
        self:ShowMissionList()
    end)

    self.UI_mission_List.Exit.OnClicked:Add(self.UI_mission, function()
        self.UI_mission_List:SetVisibility(UE.ESlateVisibility.Collapsed)
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController.BP_PlayerController_UniverseMenu.CanTracePlanet = true
    end)

    self.UI_SRPG_Option.Modal.OnClicked:Add(self.UI_SRPG_Option.Modal, function()
        self:HideOptions()
    end)

    local RESOURCE_BUTTON_NAME = "BtnRes_%d"
    local showResource = function(i)
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())
        self:ShowResourceInfo(i, screenPos)
    end

    for i = 1, 3 do
        ---@type UButton
        local resourceButton = self.UI_Res[string.format(RESOURCE_BUTTON_NAME, i)]
        resourceButton.OnClicked:Add(resourceButton, function()
            showResource(i)
        end)
    end
    self.UI_Res.BtnHp.OnClicked:Add(self.UI_Res.BtnHp, function()
        showResource(4)
    end)
    self.UI_Res.BtnEnergy.OnClicked:Add(self.UI_Res.BtnEnergy, function()
        showResource(5)
    end)

    ---@type FSlateColor
    self.costColor = UE.FSlateColor()
    self.costColor.SpecifiedColor = M.BP_GHSFunctionLibrary.HexToColor("#FFFFFFFF")
    ---@type FSlateColor
    self.recycleColor = UE.FSlateColor()
    self.recycleColor.SpecifiedColor = M.BP_GHSFunctionLibrary.HexToColor("#00FF00FF")

    if SrpgController:GetInstance():HideOverview() then
        self.Btn_Overview:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
    
    if SrpgController:GetInstance():HideResources() then
        self.UI_Res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

-- function M:OpenOverview()
--     self.overviewController = OverviewController.New(self.RootCanvas)

--     self.overviewController:SetUp()
-- end

function M:ToggleUI(show)
    self.showUI = show

    self.UI_Res:SetVisibility(self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.UI_character:SetVisibility(self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.Upgrade_List:SetVisibility(self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.CardRace_List:SetVisibility(self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.UI_BOSS:SetVisibility(self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.UI_rotateBtn:SetVisibility(not self.showUI and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    local buffs = SrpgController:GetInstance().model.definiteBuffs
    self.UI_temp_buff:SetVisibility((#buffs > 0 and self.showUI) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    local missionInfos = SrpgController:GetInstance():GetMissionInfo()
    self.UI_mission:SetVisibility((self.showUI and missionInfos and #missionInfos > 0) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    ---@type BP_Character_1_Universe_C
    local ship = playerController:K2_GetPawn()

    ship.Camera:AddOrUpdateBlendable(LoadObject('/Game/_Game/3DRES/Material/Universe1Map/M_PP_UI_MenuBg.M_PP_UI_MenuBg'), self.showUI and 1.0 or 0.0)

    if SrpgController:GetInstance():HideOverview() then
        self.Btn_Overview:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
    
    if SrpgController:GetInstance():HideResources() then
        self.UI_Res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:ShowConfirmFightUI(callback)
    ---@type UI_SRPG_Fight_C
    self.confirmUI = NewObject(M.UI_SRPG_Fight)

    self.RootCanvas:AddChild(self.confirmUI)

    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()
    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)
    self.confirmUI.Slot:SetAnchors(anchors)
    self.confirmUI.Slot:SetOffsets(offsets)
    self.confirmUI.Slot:SetZOrder(10)

    self.confirmUI.Btn_Fight.OnClicked:Add(self.confirmUI.Btn_Fight, function()
        self:CloseConfirmFightUI()

        callback()
    end)
end

function M:CloseConfirmFightUI()
    if self.confirmUI then
        self.RootCanvas:RemoveChild(self.confirmUI)
        self.confirmUI = nil
    end
end

---@param self UI_Menu_C
M[SrpgController.EventUpdated] = function(self)
    self.RootCanvas:SetVisibility(SrpgController:GetInstance():HasPendingEvent() and UE.ESlateVisibility.HitTestInvisible or UE.ESlateVisibility.SelfHitTestInvisible)
end

---@param self UI_Menu_C
M[SrpgController.BossFight] = function(self, bossIndex)
    self.requestedBossIndex = bossIndex

    -- self:ShowConfirmFightUI(function()
    Client.send(Protos.REQ_BOSS_FIGHT, {
        boss_index = bossIndex
    })
    -- end)
end

---@param self UI_Menu_C
M[SrpgController.NormalFight] = function(self, fightUUID)
    local currentFightInfo = SrpgController:GetInstance():GetCurrentFightInfo()

    if currentFightInfo then
        LOG_WARN("Start fight ", fightUUID, " while fight ", currentFightInfo.fight_uuid, " already started")
    end 

    self.requestedFightUUID = fightUUID

    -- self:ShowConfirmFightUI(function()
    Client.send(Protos.REQ_UNIVERSE_FIGHT, {
        fight_uuid = fightUUID
    })
    -- end)
end

---@param self UI_Menu_C
M[SrpgController.StartSelectCard] = function(self, UUID)
    self:ShowCardSelection(UUID)
end

---@param self UI_Menu_C
M[SrpgController.StartSelectCurio] = function(self, UUID)
    self:ShowCurioSelection(UUID)
end

local SPECIAL_EVENT_UI_PATH = '/Game/_Game/Blueprints/UI/UI_SRPG_Event/%s.%s_C' 

---@param self UI_Menu_C
M[SrpgController.UniverseEvent] = function(self, eventUUID)
    local eventInfo = SrpgController:GetInstance():GetUniverseEventInfoByUUID(eventUUID)

    if eventInfo then
        LOG_INFO("show event")
        local optionCount = #eventInfo.options
        local eventConfig = Database.Query("d_srpg_event_base", eventInfo.event_id)

        local eventUI
        if eventConfig.special and #eventConfig.special > 0 then
            eventUI = UE.UWidgetBlueprintLibrary.Create(self, LoadClass(string.format(SPECIAL_EVENT_UI_PATH, eventConfig.special, eventConfig.special)))
        else
            if optionCount > 1 then
                eventUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SRPG_Event)
            else
                eventUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SRPG_Event1)
            end
        end
        UIManager:GetInstance():AddUI(eventUI)
        eventUI:InitEventUI(eventInfo)
    end
end

M[SrpgController.ReplaceCard] = function(self, cardId)
    ---@type UI_Panel_SwapCards_C
    local swapUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Panel_SwapCards)

    UIManager:GetInstance():AddUI(swapUI)

    swapUI:SetUp(cardId)
end

M[SrpgController.ShowCard] = function(self, cardId)
    ---@type UI_Panel_ShowReward_C
    local rewardUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Panel_ShowReward_C)

    UIManager:GetInstance():AddUI(rewardUI)

    rewardUI:ShowCard(cardId)
end

M[SrpgController.ShowCurio] = function(self, curioId)
    ---@type UI_Panel_ShowReward_C
    local rewardUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Panel_ShowReward_C)

    UIManager:GetInstance():AddUI(rewardUI)

    rewardUI:ShowCurio(curioId)
end

---@param self BP_PlayerController_Universe_C
M[SrpgController.ShowStory] = function(self, story)
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if story.type == 1 then
        gameInstance:OpenPlot(story.id, true)
    elseif story.type == 2 then
        gameInstance:ShowTutorial(story.id, false)
    elseif story.type == 3 then
        gameInstance:ShowTalkUI(story.id)
    end
    SrpgController:GetInstance():PlayStory(story)
end

M[SrpgController.OpenShop] = function(self, attachInfo)
    self:ShowShop(attachInfo)

    SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.OpenShop)
end

---@param self UI_Menu_C
M[SrpgController.UpdateUI] = function(self)
    self:RefreshUI()
end

---@param self UI_Menu_C
M[Protos.RES_EXPLORE] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        SrpgController:GetInstance():ExploreTo(self.MainPosHex)
    else
        if result == 7 then
            UIManager:GetInstance():Notify("不可到达")
        elseif result == 2 then
            UIManager:GetInstance():Notify("燃料不足")
        end
        LOG_WARN('Req Explore Error Code:', result)
    end
end

local LEVEL_CONFIG_PATH = '/Game/_Game/Blueprints/Levels/SRPG/Level%d/TestLevel%d.TestLevel%d_C'

---@param self UI_Menu_C
M[Protos.RES_UNIVERSE_FIGHT] = function(self, result, msgId, parsed_msg)
    SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.NormalFight)

    if result == 0 then
        local fightInfo = SrpgController:GetInstance():GetFightInfoByUUID(self.requestedFightUUID)

        fightInfo.fight_state = 1
        
        local fightLevelId = fightInfo.fight_level_id
        local levelPath = Database.Query("d_srpg_level_base", fightLevelId).levelPath
        if not string.endswith(levelPath, "_C'") and not string.endswith(levelPath, "_C") then
            if string.endswith(levelPath, "'") then
                levelPath = string.sub(levelPath, 1, -2) .. "_C'"
            else
                levelPath = levelPath .. "_C"
            end
        end

        LOG_INFO("Fight Level", levelPath)
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local universeInfo = SrpgController:GetInstance():GetUniverseInfo()
        if universeInfo and universeInfo.universe_fight_data and universeInfo.universe_fight_data.character_fight_datas then
            local characterFightData = universeInfo.universe_fight_data.character_fight_datas
            local teamList = gameInstance:LoadTeamList()

            for i = 1, teamList.SpecialTeamInfo:Length() do
                ---@type FST_TeamInfo
                local teamInfo = teamList.SpecialTeamInfo:Get(i)
                -- if teamInfo.bIsSelected then
                    for j = 1, teamInfo.RoleList:Length() do
                        if characterFightData[j].character_id ~= 0 then
                            teamInfo.RoleList:Set(j, characterFightData[j].character_id)
                        else
                            teamInfo.RoleList:Set(j, 0)
                        end
                    end
                -- end
                teamList.SpecialTeamInfo:Set(i, teamInfo)
                break
            end
    
            gameInstance:SaveTeamList()
        end
        
        ---@type FightLevel_C
        local fightLevelClass = LoadClass(levelPath)
       
        gameInstance.fightType = gameInstance.FIGHT_STATE.UNIVERSE
        gameInstance.LevelClass = fightLevelClass
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        if playerController then
            playerController:LoadFight()
        end
    end
end

---@param self UI_Menu_C
---@param parsed_msg ResBossFightMessage
M[Protos.RES_BOSS_FIGHT] = function(self, result, msgId, parsed_msg)
    SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.BossFight)
    
    if result == 0 then
        SrpgController:GetInstance():AddBossFightInfo(self.requestedBossIndex, parsed_msg.res_boss_fight.fight_info)
        local fightInfo = SrpgController:GetInstance():GetBossFightInfoByBossIndex(self.requestedBossIndex)

        fightInfo.fight_state = 1
        
        local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
        local bossInfo = Database.Query("d_srpg_level_boss", bossConfigId)
        local fightLevelId = bossInfo.path[self.requestedBossIndex + 1]
        local levelPath = Database.Query("d_srpg_level_base", fightLevelId).levelPath
        if not string.endswith(levelPath, "_C'") and not string.endswith(levelPath, "_C") then
            if string.endswith(levelPath, "'") then
                levelPath = string.sub(levelPath, 1, -2) .. "_C'"
            else
                levelPath = levelPath .. "_C"
            end
        end

        LOG_INFO("Fight Level", levelPath)
        
        ---@type FightLevel_C
        local fightLevelClass = LoadClass(levelPath)
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.UNIVERSE
        gameInstance.LevelClass = fightLevelClass
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        if playerController then
            playerController:LoadFight()
        end
    end
end

function M:RefreshUI()
    self:UpdateHp()
    self:UpdateMission()
    self:UpdateResource()
    self:UpdateRaceInfo()
    self:UpdateCurios()
    self:UpdateTempBuff()
    self:UpdateBossInfo()
    self:UpdateBossWarning()
    self:UpdateAllIcon()
end

local CHARACTER_WIDGET_NAME = "character_%d"
local CHARACTER_ICON_NAME = "character%d_icon"
local CHARACTER_HP_NAME = "character%d_HP"
local CHARACTER_BUTTON_NAME = "character%d_Btn"
function M:UpdateHp()
    local characterFightData = SrpgController:GetInstance():GetCharacterFightData()
    for index, characterFightData in ipairs(characterFightData) do
        if index > 3 then
            break
        end
        local iconWidget = self.UI_character[string.format(CHARACTER_ICON_NAME, index)]
        iconWidget:SetVisibility(characterFightData.character_id > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        local hpWidget = self.UI_character[string.format(CHARACTER_HP_NAME, index)]
        hpWidget:SetPercent(0)
        if characterFightData.character_id > 0 then
            local characterInfo = Database.Query("d_character", characterFightData.character_id)

            --头像
            ---@type UImage
            local iconWidget = self.UI_character[string.format(CHARACTER_ICON_NAME, index)]
            LOG_INFO(characterFightData.character_id, characterInfo.headRes)
            local HeadPath = UIUtils.GetCharacterIdolIcon(characterFightData.character_id, characterInfo.headRes)
            local iconTexture = LoadObject(HeadPath)
            if iconTexture then
                iconWidget:SetBrushFromAtlasInterface(iconTexture)
            end
            local hpMax = UIUtils.GetCharacterAllAttr(characterFightData.character_id)[1001]
            local currentHp = characterFightData.cur_hp or hpMax
            ---@type UGHSProgressBar
            local hpWidget = self.UI_character[string.format(CHARACTER_HP_NAME, index)]
            hpWidget:SetPercent(currentHp / hpMax)
        end
        ---@type UUserWidget
        local characterWidget = self.UI_character[string.format(CHARACTER_WIDGET_NAME, index)]

        characterWidget:SetVisibility(UE.ESlateVisibility.Visible)

        ---@type UGHSCheckBox
        local characterButton = self.UI_character[string.format(CHARACTER_BUTTON_NAME, index)]
        characterButton.OnCheckStateChanged:Clear()
        characterButton.OnCheckStateChanged:Add(self, function(_, isOn)
            if isOn then
                self.selectedCharacterIndex = index
                self.UI_character_exchange:Show()
            end
        end)
    end

    for i = #characterFightData + 1, 3 do
        ---@type UUserWidget
        local characterWidget = self.UI_character[string.format(CHARACTER_WIDGET_NAME, i)]

        characterWidget:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:CloseChangeCharacter()
    self.UI_character_exchange:SetVisibility(UE.ESlateVisibility.Collapsed)

    for i = 1, 3 do
        ---@type UGHSCheckBox
        local characterButton = self.UI_character[string.format(CHARACTER_BUTTON_NAME, i)]
        characterButton:SetIsCheckedAndFireEvent(false)
    end
end

function M:UpdateMission()
    ---@type MissionInfo[]
    local missionInfos = SrpgController:GetInstance():GetMissionInfo()

    if not self.showUI or not missionInfos or #missionInfos == 0 then
        self.UI_mission:SetVisibility(UE.ESlateVisibility.Collapsed)
    else
        local missionConfig = Database.Query("d_srpg_mission", missionInfos[1].mission_id)
        self.UI_mission.desc:SetText(Database.L10n(missionConfig.descrId))
        self.UI_mission.name:SetText(Database.L10n(missionConfig.nameId))
        self.UI_mission:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

---@param missionInfo MissionInfo
function M:CreateMissionInfoEntry(missionInfo)
    local missionConfig = Database.Query("d_srpg_mission", missionInfo.mission_id)

    ---@type UI_mission_panel_C
    local widget = UE.UWidgetBlueprintLibrary.Create(self, M.UI_mission_panel, nil)

    self.UI_mission_List.MissionList:AddChild(widget)

    widget.Description:SetText(Database.L10n(missionConfig.descrId))
    widget.name:SetText(Database.L10n(missionConfig.nameId))
end

function M:RefreshMissionList()
    ---@type MissionInfo[]
    local missionInfo = SrpgController:GetInstance():GetMissionInfo()

    table.sort(missionInfo, function(a, b)
        return a.mission_result <= b.mission_result
    end)

    self.UI_mission_List.MissionList:ClearChildren()

    for _, missionInfo in pairs(missionInfo) do
        self:CreateMissionInfoEntry(missionInfo)
    end
end

function M:ShowMissionList()
    self:RefreshMissionList()
    self.UI_mission_List:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

local RESOURCE_TEXT_NAME = "Res%d_value"
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

function M:ShowResourceInfo(type, screenPos)
    UIManager:GetInstance():ShowDesc(screenPos, Database.L10n(RESOURCE_NAME[type]), Database.L10n(RESOURCE_DESC[type]), UE.FVector2D(1, 0))
end

function M:UpdateResource()
    for i = 1, 3 do
        ---@type UTextBlock
        local resourceName = self.UI_Res[string.format(RESOURCE_TEXT_NAME, i)]
        resourceName:SetText(tostring(SrpgController:GetInstance():GetResource(i)))
    end
    self.UI_Res.CurHp:SetText(tostring(SrpgController:GetInstance():GetCurHp()))
    self.UI_Res.Energy_value:SetText(tostring(SrpgController:GetInstance():GetBoatEnergy()))
end

function M:ShowBuffInfo(buffId, screenPos)
    local buffInfo = Database.Query("d_srpg_temp_buff", buffId)
    
    UIManager:GetInstance():ShowDesc(screenPos, "", Database.L10n(buffInfo.descrId))
end

local TEMP_BUFF_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/temp_buff_icon/%s.%s'

function M:UpdateTempBuff()
    local buffs = SrpgController:GetInstance().model.definiteBuffs

    if #buffs > 0 then
        LOG_INFO(buffs[1].buff_id)
        local buffInfo = Database.Query("d_srpg_temp_buff", buffs[1].buff_id)

        self.UI_temp_buff.temp_buff_image:SetBrushFromTexture(LoadObject(string.format(TEMP_BUFF_ICON_PATH, buffInfo.icon, buffInfo.icon)))
    end

    self.UI_temp_buff:SetVisibility((#buffs > 0 and self.showUI) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:UpdateBossInfo()
    local bossWaveCount = SrpgController:GetInstance():GetBossWaveCount()
    local bossCount = SrpgController:GetInstance():GetBossCount()

    self.UI_BOSS.Progress:SetText(string.format("%d/%d", bossCount, bossWaveCount))
end

function M:UpdateBossWarning()
    local bossInfo = SrpgController:GetInstance().model.bossInfo

    self.UI_boss_scroll.TextBlock_96:SetText(Database.L10n(99300002))
    self.UI_boss_scroll.ButtonTitle:SetText(Database.L10n(99300003))

    if #bossInfo > 0 then
        local bossInfo = bossInfo[1]

        self.UI_boss_scroll.BackBtn.OnClicked:Clear()
        local once = false
        self.UI_boss_scroll.BackBtn.OnClicked:Add(self.UI_boss_scroll.BackBtn, function()
            if once then
                return
            else
                once = true
            end
            SrpgController:GetInstance():AddEvent({
                type = SrpgModel.TurnEvents.ShipMove,
                info = {
                    from = SrpgController:GetInstance():GetPlayerHex(),
                    to = bossInfo.hex
                }
            })

            SrpgController:GetInstance():AddEvent({
                type = SrpgModel.TurnEvents.BossFight,
                info = {
                    bossId = bossInfo.boss_index
                }
            })
        end)
    end

    self.UI_boss_scroll:SetVisibility(#bossInfo > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

local ICON_OFFSET = 100

---@param mainPos BP_Map_Planet_C
---@param indicator UI_BossIcon_C | UI_ShipIcon_C | UI_BaseIcon_C
function M:UpdateIndicator(mainPos, mainPosHex, indicator)
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local viewportPosition = UE.FVector2D()
    
    playerController:ProjectWorldLocationToScreen(mainPos:K2_GetActorLocation(), viewportPosition)
    local viewportSize = UE.UWidgetLayoutLibrary.GetViewportSize(self)

    local mainPosVisible = 0 < viewportPosition.X and viewportPosition.X < viewportSize.X and
        0 < viewportPosition.Y and viewportPosition.Y < viewportSize.Y

    indicator:SetVisibility(mainPosVisible and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.SelfHitTestInvisible)

    indicator.Button.OnClicked:Clear()
    indicator.Button.OnClicked:Add(indicator.Button, function()
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

        local targetMainPosLocation = mainPos:K2_GetActorLocation()
        local cameraLocation = playerController:K2_GetPawn():K2_GetActorLocation()
        cameraLocation.X = targetMainPosLocation.X
        cameraLocation.Y = targetMainPosLocation.Y + 2000
        playerController:K2_GetPawn():K2_SetActorLocation(cameraLocation, false, nil, true)

        self:UpdateAllIcon()
    end)

    if not mainPosVisible then
        local iconCount
        for _, hex in ipairs(table.keys(self.indicatorCount)) do
            if hex_grid.equal(mainPosHex, hex) then
                self.indicatorCount[hex] = self.indicatorCount[hex] + 1
                iconCount = self.indicatorCount[hex]
            end
        end
        if not iconCount then
            self.indicatorCount[mainPosHex] = 1
            iconCount = 1
        end
        local x = viewportPosition.X - viewportSize.X / 2
        local y = viewportPosition.Y - viewportSize.Y / 2

        local sign = x > 0 and -1 or 1

        local clampedX
        local clampedY

        local borderSize = UE.USlateBlueprintLibrary.GetLocalSize(self.Border:GetCachedGeometry())

        if math.abs(x / y) > math.abs(borderSize.X / borderSize.Y) then
            clampedX = x * math.abs(borderSize.X / 2 / x)
            clampedY = y * math.abs(borderSize.X / 2 / x)
        else
            clampedX = x * math.abs(borderSize.Y / 2 / y)
            clampedY = y * math.abs(borderSize.Y / 2 / y)
        end

        local offset = UE.FMargin()
        offset.Left = clampedX + borderSize.X / 2 + (iconCount - 1) * ICON_OFFSET * sign
        offset.Top = clampedY + borderSize.Y / 2

        indicator.Slot:SetOffsets(offset)

        local angle = math.deg(math.atan(clampedY, clampedX))
        indicator.Direction:SetRenderTransformAngle(angle + 180)
    end
end

function M:UpdateBaseIcon()
    -- local bossInfos = SrpgController:GetInstance():GetBossInfo()
    local baseHex = SrpgController:GetInstance():GetBaseHex()

    -- local blocked = table.any(bossInfos, function(bossInfo)
    --     return hex_grid.equal(bossInfo.hex, baseHex)
    -- end)

    -- if blocked then
    --     return
    -- end

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local baseMainPos = playerController.MapPlanets:FindRef(hex_grid.to_string(baseHex))

    if not baseMainPos then
        return
    end

    if not self.baseIcon then
        self.baseIcon = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BaseIcon)

        self.Border:AddChild(self.baseIcon)
    end

    self:UpdateIndicator(baseMainPos, baseHex, self.baseIcon)
end

function M:UpdateShipIcon()
    -- local bossInfos = SrpgController:GetInstance():GetBossInfo()
    -- local baseHex = SrpgController:GetInstance():GetBaseHex()
    local shipHex = SrpgController:GetInstance():GetPlayerHex()

    -- local blocked = table.any(bossInfos, function(bossInfo)
    --     return hex_grid.equal(bossInfo.hex, shipHex)
    -- end) or hex_grid.equal(shipHex, baseHex)

    -- if blocked then
    --     return
    -- end

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local shipMainPos = playerController.MapPlanets:FindRef(hex_grid.to_string(shipHex))

    if not shipMainPos then
        return
    end

    if not self.shipIcon then
        self.shipIcon = UE.UWidgetBlueprintLibrary.Create(self, M.UI_ShipIcon)

        self.Border:AddChild(self.shipIcon)
    end

    self:UpdateIndicator(shipMainPos, shipHex, self.shipIcon)
end

function M:UpdateBossIcon()
    local bossInfo = SrpgController:GetInstance():GetBossInfo()

    if not self.bossIcon then
        self.bossIcon = {}
    end

    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    for index, boss in ipairs(bossInfo) do
        local bossMainPos = playerController.MapPlanets:FindRef(hex_grid.to_string(boss.hex))

        if not bossMainPos then
            return
        end

        if not self.bossIcon[index] then
            self.bossIcon[index] = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossIcon)
    
            self.Border:AddChild(self.bossIcon[index])
        end

        self:UpdateIndicator(bossMainPos, boss.hex, self.bossIcon[index])
    end

    for i = #bossInfo + 1, #self.bossIcon do
        self.bossIcon[i]:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:UpdateAllIcon()
    self.indicatorCount = {}
    
    self:UpdateBossIcon()
    self:UpdateBaseIcon()
    self:UpdateShipIcon()
end

local UPGRADE_ICON_COUNT = 5

local UPGRADE_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/upgrade_icon/%s.%s'
---@param upgrade UI_Upgrade_C
function M:SetupUpgrade(upgrade, upgradeId)
    local upgradeInfo = Database.Query("d_srpg_curio_base", upgradeId)
    
    upgrade.BtnUpgrade.OnClicked:Add(upgrade.BtnUpgrade, function()
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())

        self:ShowUpgradeInfo(upgradeId, screenPos)
    end)

    upgrade.rarity:SetBrushFromAtlasInterface(M.RARITY_ICON[upgradeInfo.rarity])
    upgrade.icon:SetBrushFromTexture(LoadObject(string.format(UPGRADE_ICON_PATH, upgradeInfo.icon, upgradeInfo.icon)))
end

function M:ShowUpgradeInfo(upgradeId, screenPos)
    local upgradeInfo = Database.Query("d_srpg_curio_base", upgradeId)

    UIManager:GetInstance():ShowDesc(screenPos, Database.L10n(upgradeInfo.nameId), Database.L10n(upgradeInfo.effectsDescrId))
end

function M:UpdateCurios()
    local curios = SrpgController:GetInstance():GetCurios()

    self.Upgrade_List:ClearChildren()

    local curioCount = 0
    for _, curioId in ipairs(curios) do
        ---@type UI_Upgrade_C
        local curio = NewObject(M.UI_Upgrade, self.Upgrade_List)
        self.Upgrade_List:AddChild(curio)

        curio.Slot:SetRow(math.floor(curioCount / UPGRADE_ICON_COUNT))
        curio.Slot:SetColumn(math.floor(curioCount % UPGRADE_ICON_COUNT))

        curioCount = curioCount + 1
        
        self:SetupUpgrade(curio, curioId)
    end
end

local RACE_ICON_COUNT = 3
local RACE_ICON_PATH = '/Game/_Game/TP_New/SRPG_res/card_race_icon/%s.%s'
local LEVEL_PATH = '/Game/_Game/Blueprints/UI/UI_Menu/UI_Level%d.UI_Level%d_C'
---@param raceInfoWidget UI_Card_Race_C
function M:SetupRaceInfo(raceInfoWidget, raceInfo, raceCount)
    raceInfoWidget.BtnRace.OnClicked:Add(raceInfoWidget.BtnRace, function()
        ---@type BP_PlayerController_Universe_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())

        self:ShowRaceInfo(raceInfo, raceCount, screenPos)
    end)

    raceInfoWidget:ShowRaceInfo(raceInfo.id, raceCount)
end

local COLOR_ACTIVATED = "#D5541C"
local COLOR_NORMAL = "#687083"
function M:ShowRaceInfo(raceInfo, raceCount, screenPos)
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

    UIManager:GetInstance():ShowDesc(screenPos, Database.L10n(raceInfo.nameId), desc)
end

function M:UpdateRaceInfo()
    local cardPosInfo = SrpgController:GetInstance():GetAllPlacedCards()

    local racesCount = {}
    local raceInfo = require("ClientDatas.d_srpg_card_race")
    local races = table.keys(raceInfo)

    for _, value in ipairs(races) do
        racesCount[value] = 0
    end

    for _, info in pairs(cardPosInfo) do
        if info.card_id ~= 0 then
            local cardInfo = Database.Query("d_srpg_card_base", info.card_id)

            for _, race in pairs(cardInfo.race) do
                racesCount[race] = racesCount[race] + 1
            end
        end
    end

    table.sort(races, function(a, b)
        if racesCount[a] == racesCount[b] then
            return a < b
        else
            return racesCount[a] > racesCount[b]
        end
    end)

    self.CardRace_List:ClearChildren()
    for i, raceId in ipairs(races) do
        if racesCount[raceId] > 0 then
            ---@type UI_Card_Race_C
            local raceInfoWidget = NewObject(M.UI_Card_Race, self.CardRace_List)
            self.CardRace_List:AddChild(raceInfoWidget)

            raceInfoWidget.Slot:SetRow(math.floor((i - 1) / RACE_ICON_COUNT))
            raceInfoWidget.Slot:SetColumn(math.floor((i - 1) % RACE_ICON_COUNT))

            self:SetupRaceInfo(raceInfoWidget, raceInfo[raceId], racesCount[raceId])
        end
    end
end

local OPTIONS = {
    WRAP = 1,
    EXPLORE = 2,
    UNLOCK = 3,
    MANAGE = SrpgModel.AttachType.Card,
    BOSS = 5,
    SHOP = SrpgModel.AttachType.Shop,
}

M.OPTION_ICONS = {
    [OPTIONS.WRAP] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Transition_png.OptionIcon_Transition_png'),
    [OPTIONS.EXPLORE] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Explore_png.OptionIcon_Explore_png'),
    [OPTIONS.UNLOCK] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Unlock_png.OptionIcon_Unlock_png'),
    [OPTIONS.BOSS] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Fight_png.OptionIcon_Fight_png'),
    [OPTIONS.MANAGE] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Card_png.OptionIcon_Card_png'),
    [OPTIONS.SHOP] = LoadObject('/Game/_Game/TP_New/SRPG_starpoint_res/Frames/OptionIcon_Card_png.OptionIcon_Card_png'),
}
M.OPTION_ICONSRef = {
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.WRAP]),
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.EXPLORE]),
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.UNLOCK]),
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.BOSS]),
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.MANAGE]),
    UnLua.Ref(M.OPTION_ICONS[OPTIONS.SHOP]),
}

M.RES_ICONS = {
    [1] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_1_png.Icon_res_1_png'),
    [2] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_2_png.Icon_res_2_png'),
    [3] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_3_png.Icon_res_3_png'),
    [4] = LoadObject('/Game/_Game/TP_New/Common/Frames/Icon_res_4_png.Icon_res_4_png'),
}
M.RES_ICONSRef = {
    UnLua.Ref(M.RES_ICONS[1]),
    UnLua.Ref(M.RES_ICONS[2]),
    UnLua.Ref(M.RES_ICONS[3]),
    UnLua.Ref(M.RES_ICONS[4]),
}

---@param self UI_Menu_C
local function AddWrapOption(self)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.WRAP])
    option.option_name:SetText(Database.L10n(99100001))

    option.res_type:SetVisibility(UE.ESlateVisibility.Hidden)
    option.res_value:SetVisibility(UE.ESlateVisibility.Hidden)

    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        SrpgController:GetInstance():AddEvent({
            type = SrpgModel.TurnEvents.ShipMove,
            info = {
                from = SrpgController:GetInstance():GetPlayerHex(),
                to = self.MainPosHex
            }
        })

        self:HideOptions()
    end)
end

---@param self UI_Menu_C
local function AddExploreOption(self)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.EXPLORE])
    option.option_name:SetText(Database.L10n(99100002))

    option.res_type:SetVisibility(UE.ESlateVisibility.Hidden)
    option.res_value:SetVisibility(UE.ESlateVisibility.Hidden)

    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        if not QuestSystem:GetInstance():IsExploreBlocked() then
            Client.send(Protos.REQ_EXPLORE, { hex = self.MainPosHex })
        else
            UIManager:GetInstance():Notify(Database.L10n(519))
        end

        self:HideOptions()
    end)
end

---@param self UI_Menu_C
local function AddUnlockOption(self, selectedMainPosHex)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.UNLOCK])
    option.option_name:SetText(Database.L10n(99100003))

    ---@type MainPosInfo
    local mainPosInfo = UE.UGameplayStatics.GetGameInstance(self).mainPosInfos[selectedMainPosHex]
    
    local price = Database.Query("d_srpg_main_pos_config", mainPosInfo.main_pos_config_id).effect[1]

    option.res_type:SetBrushFromAtlasInterface(M.RES_ICONS[2])
    option.res_value:SetText(tostring(-price))
    option.res_value:SetColorAndOpacity(self.costColor)

    option:SetRedStyle()

    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        ---@type ReqCardPosUnlockCard
        local msg = {}
        local hex = string.split(selectedMainPosHex, ",")
        msg.hex = {
            q = tonumber(hex[2]),
            r = tonumber(hex[1]),
        }
        -- 只有一个卡位
        msg.index_in_main_pos = 0

        Client.send(Protos.REQ_CARD_POS_UNLOCK_CARD, msg)

        self:HideOptions()
    end)
end

---@param self UI_Menu_C
---@param bossInfo BossInfo
local function AddBossOption(self, selectedMainPosHex, bossInfo)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.BOSS])

    local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
    local bossConfig = Database.Query("d_srpg_level_boss", bossConfigId)

    option.option_name:SetText(Database.L10n(bossConfig.nameId))

    option.res_type:SetVisibility(UE.ESlateVisibility.Hidden)
    option.res_value:SetVisibility(UE.ESlateVisibility.Hidden)
    
    option:SetRedStyle()

    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        SrpgController:GetInstance():AddEvent({
            type = SrpgModel.TurnEvents.ShipMove,
            info = {
                from = SrpgController:GetInstance():GetPlayerHex(),
                to = selectedMainPosHex,
            }
        })

        SrpgController:GetInstance():SetPlayerHex(selectedMainPosHex)

        SrpgController:GetInstance():AddEvent({
            type = SrpgModel.TurnEvents.BossFight,
            info = {
                bossId = bossInfo.boss_index
            }
        })

        self:HideOptions()
    end)
end

---@param self UI_Menu_C
local function AddManageOption(self, selectedMainPosHex)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.MANAGE])

    option.option_name:SetText(Database.L10n(99100005))

    option.res_type:SetVisibility(UE.ESlateVisibility.Hidden)
    option.res_value:SetVisibility(UE.ESlateVisibility.Hidden)
    
    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        ---@type CardSelector_C
        local ui = UE.UWidgetBlueprintLibrary.Create(self, M.CardSelector)
        UIManager:GetInstance():AddUI(ui)
        ui:InitUI()
        ui:Show(selectedMainPosHex)
        self:HideOptions()
    end)
end

---@param self UI_Menu_C
---@param attachInfo MainPosShopInfo
local function AddShopOption(self, selectedMainPosHex, attachInfo)
    ---@type UI_SRPG_Option_Item_C
    local option = NewObject(M.UI_SRPG_Option_Item)
    self.UI_SRPG_Option.Options:AddChild(option)

    option.option_icon:SetBrushFromAtlasInterface(M.OPTION_ICONS[OPTIONS.SHOP])

    option.option_name:SetText(Database.L10n(141))

    option.res_type:SetVisibility(UE.ESlateVisibility.Hidden)
    option.res_value:SetVisibility(UE.ESlateVisibility.Hidden)
    
    LOG_INFO(table.dump(attachInfo))
    option.GHSButton_Option.OnClicked:Add(option.GHSButton_Option, function()
        self:ShowShop(attachInfo)

        self:HideOptions()
    end)
end

local OptionCreaterMap = {
    [OPTIONS.WRAP] = AddWrapOption,
    [OPTIONS.EXPLORE] = AddExploreOption,
    [OPTIONS.UNLOCK] = AddUnlockOption,
    [OPTIONS.BOSS] = AddBossOption,
    [OPTIONS.MANAGE] = AddManageOption,
    [OPTIONS.SHOP] = AddShopOption,
}

---@param parsed_msg ResCardPosUnlockCardMessage
-- M[Protos.RES_CARD_POS_UNLOCK_CARD] = function(self, result, msgId, parsed_msg)
--     if result == 0 then
--         ---@type MainPosInfo
--         local mainPosInfo = UE.UGameplayStatics.GetGameInstance(self).mainPosInfos[self.MainPosHexId]
--         if mainPosInfo.main_pos_card_pos_info then
--             local price = Database.Query("d_srpg_main_pos_config", mainPosInfo.main_pos_config_id).effect[1]

--             SrpgController:GetInstance():ChangeResource(2, -price)

--             mainPosInfo.main_pos_card_pos_info.card_locked_index = {}

--             ---@type BP_PlayerController_Universe_C
--             local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

--             playerController:UpdateMap()
--         else
--             LOG_WARN("RES_CARD_POS_UNLOCK_CARD Wrong response")
--         end
--     else
--         LOG_WARN("RES_CARD_POS_UNLOCK_CARD", result)
--     end
-- end

---@param shopInfo MainPosShopInfo
function M:ShowShop(shopInfo)
    ---@type UI_SRPG_Shop_C
    local shopUI = UE.UWidgetBlueprintLibrary.Create(self, M.UI_SRPG_Shop)

    UIManager:GetInstance():AddUI(shopUI)

    shopUI:Show(shopInfo)
end

---@param mainPosInfo MainPosInfo
function M:ShowOptions(mainPosInfo, screenPos)
    self.UI_SRPG_Option.Options:ClearChildren()
    self.MainPosHex = mainPosInfo.hex
    
    local options = {}

    if UniverseUtils.IsReachable(mainPosInfo) and not UniverseUtils.IsExplored(mainPosInfo) then
        table.insert(options, { option = OPTIONS.EXPLORE })
    else
        for _, info in pairs(mainPosInfo.main_pos_attach_infos) do
            table.insert(options, { option = info.main_pos_attach_extra, extra = info.main_pos_shop_info })
        end
        
        local bossInfos = SrpgController:GetInstance():GetBossInfo()

        for index, bossInfo in ipairs(bossInfos) do
            if hex_grid.equal(bossInfo.hex, mainPosInfo.hex) then
                table.insert(options, { option = OPTIONS.BOSS, extra = bossInfo })
            end
        end
    
        if not hex_grid.equal(SrpgController:GetInstance():GetPlayerHex(), self.MainPosHex) and UniverseUtils.IsReachable(mainPosInfo) then
            table.insert(options, { option = OPTIONS.WRAP })
        end
    end

    self.UI_SRPG_Option:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    for _, optionInfo in ipairs(options) do
        OptionCreaterMap[optionInfo.option](self, self.MainPosHex, optionInfo.extra)
    end

    self.UI_SRPG_Option.Options.Slot:SetPosition(screenPos)

    local mainPosConfig = Database.Query('d_srpg_main_pos_base', mainPosInfo.main_pos_id)

    self.UI_SRPG_Option.name:SetText(Database.L10n(mainPosConfig.nameId))
    self.UI_SRPG_Option.desc:SetText(Database.L10n(mainPosConfig.txtId))

    self.UI_SRPG_Option.Info.Slot:SetPosition(screenPos)
end

---@param mainPosInfo MainPosInfo
function M:RefreshInfoBoard(mainPosInfo)
    self.MainPosHex = mainPosInfo.hex
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local screenPos = UE.UKismetMathLibrary.Conv_VectorToVector2D(playerController.BP_FingerPosRecorder:GetPointerPos())

    self:ShowOptions(mainPosInfo, screenPos)
end

function M:ShowCardSelection(UUID)
    ---@type UI_Panel_ChooseReward_C
    local selectCardPanel = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Panel_ChooseReward_C)

    UIManager:GetInstance():AddUI(selectCardPanel)

    selectCardPanel:Setup(UUID)
end

function M:ShowCurioSelection(UUID)
    ---@type UI_Panel_ChooseCurio_C
    local selectCurioPanel = UE.UWidgetBlueprintLibrary.Create(self, M.UI_Panel_ChooseCurio_C)

    UIManager:GetInstance():AddUI(selectCurioPanel)

    selectCurioPanel:Setup(UUID)
end

function M:OverviewImplement()
    ---@type UI_OverView_C
    local overview = UE.UWidgetBlueprintLibrary.Create(self, M.UI_OverView)

    UIManager:GetInstance():AddUI(overview)

    overview:SetUp()
end

return M

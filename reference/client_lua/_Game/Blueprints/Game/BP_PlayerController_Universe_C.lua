--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Global"
require "Common.Main"
local Client = require "Network.Client"
local hex_grid = require "Helper.hex_grid"
local Database = require "_Game.Utils.Database"
local GlobalConfig = require("GlobalConfig")
local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local Protos = require "Helper.Protos"
local UniverseUtils = require "_Game.Utils.UniverseUtils"
local UIUtils = require "_Game.Utils.UIUtils"

local InputAssets = require "_Game.Utils.Input.InputAssets"

local UI_Dialog_Story_C = require "_Game.Blueprints.UI.UI_Dialog_Story_C"

---@type BP_PlayerController_Universe_C
local M = Class()

UnLua.EnhancedInput.BindActionValue(M, InputAssets.IA_Move)

function M:IA_Click_Started()
    if UIManager:GetInstance():GetTopUI() == self.BP_PlayerController_UniverseMenu.UI_Menu then
        local _, x, y = self:GetMousePosition()
        local position = UE.FVector(x, y, 0)
        self.BP_PlayerController_UniverseMenu:InputTouchPressed(position, 0)
    end
end

function M:IA_Click_Triggered()
    if UIManager:GetInstance():GetTopUI() == self.BP_PlayerController_UniverseMenu.UI_Menu then
        local _, x, y = self:GetMousePosition()
        local position = UE.FVector(x, y, 0)
        self.BP_PlayerController_UniverseMenu:InputTouchMove(position, 0)
    end
end

function M:IA_Click_Completed()
    if UIManager:GetInstance():GetTopUI() == self.BP_PlayerController_UniverseMenu.UI_Menu then
        local _, x, y = self:GetMousePosition()
        local position = UE.FVector(x, y, 0)
        self.BP_PlayerController_UniverseMenu:InputTouchReleased(position, 0)
    end
end

UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Click, UE.ETriggerEvent.Started, M.IA_Click_Started)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Click, UE.ETriggerEvent.Triggered, M.IA_Click_Triggered)
UnLua.EnhancedInput.BindAction(M, InputAssets.IA_Click, UE.ETriggerEvent.Completed, M.IA_Click_Completed)

---{{{ 覆盖蓝图
function M:Initialize()
    self.event_tip = nil
    self.pawn_location = UE.FVector(0, 0, 0)
    self.detailedBosses = {}
    self.detailedShip = nil
    self.mapLines = {}
    self.levelSequenceCoroutines = {}

    ---@type ULevelSequencePlayer
    self.WrapLevelSequencePlayer = nil
    ---@type ALevelSequenceActor
    self.WrapLevelSequenceActor = nil
    ---@type UNiagaraComponent
    self.niagaraComponent = nil

    if not M.BP_UniverseMainPos_CommonRef then
        M.BP_UniverseMainPos_Common = LoadClass("/Game/_Game/Blueprints/Levels/BP_UniverseMainPos_Common.BP_UniverseMainPos_Common_C")
        M.BP_UniverseMainPos_CommonRef = UnLua.Ref(M.BP_UniverseMainPos_Common)
        M.BP_Character_1_Universe = LoadClass("/Game/_Game/Blueprints/Players/BP_Character_1_Universe.BP_Character_1_Universe_C")
        M.BP_Character_1_UniverseRef = UnLua.Ref(M.BP_Character_1_Universe)

        ---@type UAnimSequence
        M.boat_jumpstart = LoadObject('/Game/_Game/Characters/perform/boat_jumpstart.boat_jumpstart')
        M.boat_jumpstartRef = UnLua.Ref(M.boat_jumpstart)
        M.boat_jumpend = LoadObject('/Game/_Game/Characters/perform/boat_jumpend.boat_jumpend')
        M.boat_jumpendRef = UnLua.Ref(M.boat_jumpend)

        M.boss_jumpstart = LoadObject('/Game/_Game/Characters/perform/boss_jumpstart.boss_jumpstart')
        M.boss_jumpstartRef = UnLua.Ref(M.boss_jumpstart)
        M.boss_jumpend = LoadObject('/Game/_Game/Characters/perform/boss_jumpend.boss_jumpend')
        M.boss_jumpendRef = UnLua.Ref(M.boss_jumpend)

        M.bossjump = LoadObject('/Game/_Game/Characters/perform/bossjump.bossjump')
        M.bossjumpRef = UnLua.Ref(M.bossjump)

        M.atkwin = LoadObject('/Game/_Game/Characters/perform/atkwin.atkwin')
        M.atkwinRef = UnLua.Ref(M.atkwin)

        M.bossatk = LoadObject('/Game/_Game/Characters/perform/bossatk.bossatk')
        M.bossatkRef = UnLua.Ref(M.bossatk)

        M.SkipButton = LoadObject('/Game/_Game/Blueprints/UI/UI_Menu/SkipBtn.SkipBtn_C')
        M.SkipButtonRef = UnLua.Ref(M.SkipButton)
    end
end

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)

    NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_UNIVERSE_FIGHT, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_BOSS_FIGHT, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.NTF_ITEM_INFO, self)

    MessageManager:GetInstance():AddListener(SrpgController.FightEnd, self)
    MessageManager:GetInstance():AddListener(SrpgController.ShowItems, self)
    MessageManager:GetInstance():AddListener(SrpgController.BossMove, self)
    MessageManager:GetInstance():AddListener(SrpgController.BossShowUp, self)
    MessageManager:GetInstance():AddListener(SrpgController.BossArrived, self)
    MessageManager:GetInstance():AddListener(SrpgController.ShipMove, self)
    MessageManager:GetInstance():AddListener(SrpgController.GameEnd, self)
    MessageManager:GetInstance():AddListener(SrpgController.AddMapItem, self)
    MessageManager:GetInstance():AddListener(SrpgController.UpdateMapItems, self)
    MessageManager:GetInstance():AddListener(SrpgController.UpdateMapLines, self)
    MessageManager:GetInstance():AddListener(SrpgController.UpdateMapBounds, self)
    MessageManager:GetInstance():AddListener(SrpgModel.GetDefiniteBuff, self)
    MessageManager:GetInstance():AddListener(SrpgModel.BuffExpired, self)
    MessageManager:GetInstance():AddListener(UI_Dialog_Story_C.DialogEnd, self)


    self.Radius = self.DefaultRadius + math.max(GlobalConfig.RandomOffestX, GlobalConfig.RandomOffestY, GlobalConfig.RandomOffestZ) * GlobalConfig.UniverseScale
end

function M:ReceiveEndPlay()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_UNIVERSE_FIGHT, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_BOSS_FIGHT, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.NTF_ITEM_INFO, self)

    MessageManager:GetInstance():RemoveListener(SrpgController.FightEnd, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ShowItems, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.BossMove, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.BossShowUp, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.BossArrived, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.ShipMove, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.GameEnd, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.AddMapItem, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateMapItems, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateMapLines, self)
    MessageManager:GetInstance():RemoveListener(SrpgController.UpdateMapBounds, self)
    MessageManager:GetInstance():RemoveListener(SrpgModel.GetDefiniteBuff, self)
    MessageManager:GetInstance():RemoveListener(SrpgModel.BuffExpired, self)
    MessageManager:GetInstance():RemoveListener(UI_Dialog_Story_C.DialogEnd, self)

    --UIManager:GetInstance():OnEndPlay()
end

function M:ReceiveTick(DeltaTime)
    self.Overridden.ReceiveTick(self, DeltaTime)

    for i = #self.levelSequenceCoroutines, 1, -1 do
        local co = self.levelSequenceCoroutines[i]
        local res, message = coroutine.resume(co, DeltaTime)
        if not res then
            LOG_ERROR(message)
        end

        if coroutine.status(co) == "dead" then
            table.remove(self.levelSequenceCoroutines, i)
        end
    end
end

function M:OnShowUISettings()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    ---@type UI_SetSystem_C
    local ui = gameInstance:AddUMG("UI_SetSystem")
    ui:ChangeTab(0)
    ui:PlayAnimation(ui.In, 0, 1, UE.EUMGSequencePlayMode.Forward, 1, false)
end

function M:OpenLevelSequence()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    print("===OpenLevelSequence")
    -- self.UILoading = gameInstance:AddUMG("UI_Loading", nil, 1)
    -- self.UILoading2 = gameInstance:AddUMG("UI_Loading2")
    gameInstance:GetOrAddUMG('UI_Loading2')
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.2)
        -- 这段会调用gameMode.BP_Preload:PreloadAssets()
        -- self:OpenCurrentLevel()
        local cur_level_name = UE.UGameplayStatics.GetCurrentLevelName(self, true)
        if cur_level_name == "Speak_Universe" then
            self.StateTree_Universe:StartLogic()
        elseif cur_level_name == "Prologue_UniversePast" then
            self.StateTree_UniversePast:StartLogic()
        end
        UE.UKismetSystemLibrary.Delay(self, 0.2)
        self:OnCurrentLevelOpenFinished()
    end))
end

function M:OnCurrentLevelOpenFinished()
    LOG_INFO("==>>openfinished")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:CloseTalkUI()
    coroutine.resume(coroutine.create(function()
        gameInstance.LoadStreamLevelCoroutine(self, "UniverseBridge", true, false)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        if gameInstance.IsEnterBridge then
            gameMode:SpawnPlayerInBridge()
            self:InitUI()
            -- self.BP_ScreenFade:FadeOut(false)
            self:OnBridgeShown()
            -- gameInstance:RemoveUMG("UI_Loading")
            self.UILoading = nil
        else
            gameInstance.LoadStreamLevelCoroutine(self, gameMode.LevelName, true, false)
            self:InitUI()
            -- self.BP_ScreenFade:FadeOut(false)
            self:OnLevelShown()
            -- gameInstance:RemoveUMG("UI_Loading")
            self.UILoading = nil
        end
    end))
end

function M:OnLevelShown()
    self:Load3DUI()
    self:FinishFight()
    SrpgController:GetInstance():UpdateEvent()
    if self.UI_Bridge then
        UIManager:GetInstance():RemoveUI(self.UI_Bridge)
        self.UI_Bridge = nil
        self.BP_PlayerController_City_UniverseBridge.UI_City = nil
    end
end

---}}}

function M:FinishFight()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:UpdateFightState()
end

function M:RecordFightState()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:UpdateFightState()
end

function M:SetUpMap()
    self:SetUpMapItem()
    self:UpdateMapLine()
    self:UpdateTempleEffect()

    self.BP_PlayerController_UniverseMenu:UpdateMapBounds()
    self.BP_PlayerController_UniverseMenu.UI_Menu:RefreshUI()
end

M["Destroy Map Item"] = function(self)
    for _, key in pairs(self.MapPlanets:Keys()) do
        self.MapPlanets:Find(key):K2_DestroyActor()
    end
    self.MapPlanets:Clear()

    for _, mapLine in pairs(self.mapLines) do
        mapLine:K2_DestroyActor()
    end
    self.mapLines = {}

    for _, detailedBoss in pairs(self.detailedBosses) do
        detailedBoss:K2_DestroyActor()
    end
    self.detailedBosses = {}

    if self.detailedShip then
        self.detailedShip:K2_DestroyActor()
        self.detailedShip = nil
    end
end

local BOSS_MODEL_PATH = '/Game/_Game/3DRES/scene/SRPG/Boss/%s.%s_C'
local BOSS_MODEL_SCALE = 0.005
local MAINPOS_MODEL_PATH = '/Game/_Game/3DRES/scene/SRPG/mainPos/%s.%s_C'

--- 添加一个主坐标模型，顺便播动画
function M:AddMainPos(hex)

end

--- 强制更新主坐标模型，初始化和打牌后更新模型用
function M:UpdateMainPos(hex)
    local hexId = hex_grid.to_string(hex)
    local mainPosInfo = SrpgController:GetInstance():GetMainPosByHex(hex)
    local postprocess_volumes = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.APostProcessVolume)
    local volume_num = postprocess_volumes:Length()
    local levelMap_postProcess = nil
    if volume_num > 0 then
        for i = 1, volume_num do
            if postprocess_volumes[i]:ActorHasTag("MainPosVolume") then
                levelMap_postProcess = postprocess_volumes[i]
                break
            end
        end
    end
    
    local oldMainPos = self.MapPlanets:FindRef(hexId)
    if oldMainPos then
        self.MapPlanets:Remove(hexId)
        oldMainPos:K2_DestroyActor()
    end

    ---@type BP_GameMode_Universe_C
    local gameMode = UE.UGameplayStatics.GetGameMode(self)

    local center_location = levelMap_postProcess:K2_GetActorLocation()

    local offset = gameMode:GetSavedOffset(mainPosInfo.hex)
    local pos = center_location + offset

    local mainPosConfig = Database.Query('d_srpg_main_pos_base', mainPosInfo.main_pos_id)
    local model_name

    local placedCards = SrpgController:GetInstance():GetPlacedCards(hex)

    if #placedCards > 0 then
        local cardConfig = Database.Query('d_srpg_card_base', placedCards[1].card_id)
        model_name = cardConfig.cardModel
    else
        model_name = mainPosConfig.posModel
    end

    local model = LoadClass(string.format(MAINPOS_MODEL_PATH, model_name, model_name))

    local transform = UE.UKismetMathLibrary.MakeTransform(pos, UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))

    ---@type BP_Map_Planet_C
    local mapPlanetItem = self:GetWorld():SpawnActor(model,
        transform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    mapPlanetItem:UpdateMapPlanet(mainPosInfo)

    local rotation = gameMode:GetSavedRotation(mainPosInfo.hex)
    mapPlanetItem.Rotatable:K2_SetRelativeRotation(UE.FRotator(0, rotation, 0), false, nil, true)

    self.MapPlanets:Add(hexId, mapPlanetItem)

    return mapPlanetItem
end

function M:SetUpMapItem()
    local postprocess_volumes = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.APostProcessVolume)
    local volume_num = postprocess_volumes:Length()
    local levelMap_postProcess = nil
    if volume_num > 0 then
        for i = 1, volume_num do
            if postprocess_volumes[i]:ActorHasTag("MainPosVolume") then
                levelMap_postProcess = postprocess_volumes[i]
                break
            end
        end
    end
    if levelMap_postProcess then
        ---@type BP_GameMode_Universe_C
        local gameMode = UE.UGameplayStatics.GetGameMode(self)

        gameMode:LoadSaveGame()

        local center_location = levelMap_postProcess:K2_GetActorLocation()

        local mainPosInfo = SrpgController:GetInstance():GetMainPosInfo()
        local mainPosCount = #mainPosInfo

        -- 星图和主坐标模型
        if mainPosCount > 0 then
            for i = 1, mainPosCount do
                ---@type MainPosInfo
                local info = mainPosInfo[i]
                local hexId = hex_grid.to_string(info.hex)

                if self.MapPlanets:FindRef(hexId) then
                    self.MapPlanets:FindRef(hexId):UpdateMapPlanet(info)
                else
                    local offset = gameMode:GetSavedOffset(info.hex)
                    local pos = center_location + offset

                    local mainPosConfig = Database.Query('d_srpg_main_pos_base', info.main_pos_id)
                    local model_name

                    local placedCards = SrpgController:GetInstance():GetPlacedCards(info.hex)

                    if #placedCards > 0 then
                        local cardConfig = Database.Query('d_srpg_card_base', placedCards[1].card_id)
                        model_name = cardConfig.cardModel
                    else
                        model_name = mainPosConfig.posModel
                    end

                    local model = LoadClass(string.format(MAINPOS_MODEL_PATH, model_name, model_name))
                    LOG_INFO(string.format(MAINPOS_MODEL_PATH, model_name, model_name))

                    local transform = UE.UKismetMathLibrary.MakeTransform(pos, UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))

                    ---@type BP_Map_Planet_C
                    local mapPlanetItem = self:GetWorld():SpawnActor(model,
                        transform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
                    if mapPlanetItem.UpdateMapPlanet then
                        mapPlanetItem:UpdateMapPlanet(info)
                        local rotation = gameMode:GetSavedRotation(info.hex)
                        mapPlanetItem.Rotatable:K2_SetRelativeRotation(UE.FRotator(0, rotation, 0), false, nil, true)
                        mapPlanetItem:SetActorEnableCollision(mainPosConfig.isClickable == 1)
                        self.MapPlanets:Add(hexId, mapPlanetItem)
                    else
                        LOG_ERROR('------>model:' .. tostring(model) .. ' 没有UpdateMapPlanet接口')
                    end
                end

                local pos_data = Database.Query('d_srpg_main_pos_base', info.main_pos_id)
                if pos_data.mainPosType == 1 then
                    self.baseMainPos = self.MapPlanets:FindRef(hexId)
                end
            end
            gameMode:SaveSaveGame()
        end

        ---@type BossInfo[]
        local bossInfos = SrpgController:GetInstance():GetBossInfo()

        local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
        local bossConfig = Database.Query("d_srpg_level_boss", bossConfigId)

        -- 暂时同一个主坐标只刷新一个boss模型
        for index, bossInfo in ipairs(bossInfos) do
            if not self.detailedBosses[bossInfo.boss_index] then
                local hex = hex_grid.to_string(bossInfo.hex)
                local mapPlanet = self.MapPlanets:Find(hex)
                local bossPosition = mapPlanet.Boss:K2_GetComponentLocation()
                local bossTransform = UE.UKismetMathLibrary.MakeTransform(bossPosition, UE.FRotator(), UE.FVector(1, 1, 1))
                ---@type BP_Character_1_Universe_C
                local bossObject = self:GetWorld():SpawnActor(LoadClass(string.format(BOSS_MODEL_PATH, bossConfig.bossModel, bossConfig.bossModel)),
                    bossTransform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
                bossObject:SetActorScale3D(UE.FVector(BOSS_MODEL_SCALE, BOSS_MODEL_SCALE, BOSS_MODEL_SCALE))
                self.detailedBosses[bossInfo.boss_index] = bossObject
            end
        end

        if not self.detailedShip then
            local mapPlanet = self.MapPlanets:Find(hex_grid.to_string(SrpgController:GetInstance():GetPlayerHex()))
            if not mapPlanet then
                mapPlanet = self.MapPlanets:Find("0,0")
            end
            if mapPlanet then
                local shipPosition = mapPlanet.Ship:K2_GetComponentLocation()
                local shipTransform = UE.UKismetMathLibrary.MakeTransform(shipPosition, UE.FRotator(), UE.FVector(1, 1, 1))
                ---@type BP_Character_1_Universe_C
                local shipObject = self:GetWorld():SpawnActor(M.BP_Character_1_Universe,
                    shipTransform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
                shipObject:SetActorScale3D(UE.FVector(GlobalConfig.MapShipScale, GlobalConfig.MapShipScale, GlobalConfig.MapShipScale))
                shipObject.EF_univer_glow:SetHiddenInGame(false)
                self.detailedShip = shipObject
            else
                LOG_WARN("No Main Pos")
            end
        end
    end

    self.BP_PlayerController_UniverseMenu:UpdateDetailsVisibility()
end

function M:UpdateMapLine(arrivedHex)
    -- green  r 0 g 1 b 0
    -- blue   r 0 g 0.827 b 5
    -- red    r 5 g 0 b 0
    local lines = SrpgController:GetInstance():GetLines()
    local bossLines = SrpgController:GetInstance():GetBossLines()
    for _, line in ipairs(lines) do
        local pos_info1 = SrpgController:GetInstance():GetMainPosByHex(line[1])
        local pos_info2 = SrpgController:GetInstance():GetMainPosByHex(line[2])
        if pos_info1 and pos_info2 then
            local activated = UniverseUtils.IsExplored(pos_info1) and UniverseUtils.IsExplored(pos_info2)

            local mainPosColor1 = Database.Query('d_srpg_main_pos_base', pos_info1.main_pos_id).lineColor
            local mainPosColor2 = Database.Query('d_srpg_main_pos_base', pos_info2.main_pos_id).lineColor
            local start_color = UE.UGHSFunctionLibrary.HexToColor(mainPosColor1)
            local end_color = UE.UGHSFunctionLibrary.HexToColor(mainPosColor2)
            
            local bossLineIndex = table.indexof(bossLines, line, nil, UniverseUtils.LineEqual)
            local isBossLine = bossLineIndex ~= false

            if not self.mapLines[line] then
                local map_planet1 = self.MapPlanets:Find(hex_grid.to_string(line[1]))
                local map_planet2 = self.MapPlanets:Find(hex_grid.to_string(line[2]))
                if map_planet1 and map_planet2 then
                    local location1 = map_planet1:K2_GetActorLocation()
                    local location2 = map_planet2:K2_GetActorLocation()
                    local line_pos = UE.FVector((location1.X + location2.X) / 2, (location1.Y + location2.Y) / 2,
                        (location1.Z + location2.Z) / 2)
                    local line_rotation = UE.UKismetMathLibrary.FindLookAtRotation(location1, location2)
                    local line_scale = UE.FVector(1, 1, (UE.UKismetMathLibrary.Vector_Distance(location1, location2) - 240) / 90)
                    local transform = UE.UKismetMathLibrary.MakeTransform(line_pos, line_rotation, line_scale)
                    ---@type BP_Planet_line_C
                    local mapLineItem = self:GetWorld():SpawnActor(UE.UClass.Load("/Game/_Game/Blueprints/Character/BP_Planet_Line.BP_Planet_Line_C"), transform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)

                    self.mapLines[line] = mapLineItem
                    mapLineItem:SetActorScale3D(line_scale)
                    
                    mapLineItem:Init(activated, location1, location2, start_color, end_color)
                end
            end
            if self.mapLines[line] then
                ---@type BP_Planet_line_C
                local mapLine = self.mapLines[line]
                
                if activated then
                    mapLine:InitMaterial(start_color, end_color)
                else
                    mapLine:InitMaterial(UE.UKismetMathLibrary.LinearColor_White(), UE.UKismetMathLibrary.LinearColor_White())
                end

                if activated and not mapLine.IsActive then
                    if arrivedHex then
                        mapLine:active(not hex_grid.equal(arrivedHex, line[2]))
                    end
                end
                
                mapLine.Cylinder1:SetVisibility(isBossLine)
                mapLine.Cylinder2:SetVisibility(isBossLine)

                if bossLineIndex then
                    local direction = UniverseUtils.LineSameDirection(line, bossLines[bossLineIndex]) and -1 or 1

                    mapLine.Cylinder1:GetMaterial(0):SetScalarParameterValue("U", direction)
                end
            end
        end
    end
end

function M:UpdateTempleEffect()
    local buffs = SrpgController:GetInstance().model.definiteBuffs
    if #buffs > 0 then
        self:SetBuffEffect(buffs[1].buff_id)
    end
end

function M:ShowPlaceCardPos(card_id)
    local card_info = Database.Query("d_srpg_card_base", card_id)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if card_info.type == 1 then
        for _, value in pairs(self.MapPlanets) do
            local main_pos_info = gameInstance.mainPosInfos[value.PosId]
            local main_pos_data = Database.Query('d_srpg_main_pos_base', value.PlanetId)
            if main_pos_data.mainPosType == 1 or main_pos_data.mainPosType == 26 then
                local place_card_num = #main_pos_info.card_in_place
                local find_same_id = false
                for _, place_card in ipairs(main_pos_info.card_in_place) do
                    if place_card.card_info.card_id == card_id then
                        find_same_id = true
                    end
                end
                if not find_same_id then
                    if main_pos_info.explored == true and place_card_num < main_pos_info.card_count then
                        value:UpdateDroppableEffect(true)
                    end
                end
            end
        end
    elseif card_info.type == 3 then
        for _, value in pairs(self.MapPlanets) do
            local main_pos_info = gameInstance.mainPosInfos[value.PosId]
            local main_pos_data = Database.Query('d_srpg_main_pos_base', value.PlanetId)
            if main_pos_data.posType == 1 then
                local place_card_num = #main_pos_info.card_in_place
                local find_same_id = false
                for _, place_card in ipairs(main_pos_info.card_in_place) do
                    if place_card.card_info.card_id == card_id then
                        find_same_id = true
                    end
                end
                if not find_same_id then
                    if main_pos_info.explored == true and place_card_num < main_pos_info.card_count then
                        value:UpdateDroppableEffect(true)
                    end
                end
            end
        end
    end
end

function M:ClearCardPosEffect()
    for _, value in pairs(self.MapPlanets) do
        value:UpdateDroppableEffect(false)
    end
end

function M:SpawnBoss()
end

function M:OutOfBoundWarning()
    ---@type BP_GameMode_Universe_C
    local gameMode = UE.UGameplayStatics.GetGameMode(self)

    local player = self:K2_GetPawn()
    if not player then
        return
    end
    local playerLocation = player:K2_GetActorLocation()

    ---@type BP_UniverseMainPos_C
    local closestMainPos = self.CurMainPos
    local closestDistance = UE.UKismetMathLibrary.Vector_Distance(closestMainPos:K2_GetActorLocation(), playerLocation)
    for _, mainPos in pairs(gameMode.MainPoses) do
        local distance = UE.UKismetMathLibrary.Vector_Distance(mainPos:K2_GetActorLocation(), playerLocation)
        if distance < closestDistance then
            closestMainPos = mainPos
            closestDistance = distance
        end
    end

    if closestMainPos ~= self.CurMainPos then
        self.nextMainPos = closestMainPos
    else
    end

    LOG_INFO(closestMainPos, self.CurMainPos)
end

function M:Load3DUI()
    UIManager:GetInstance():ClearNotifications()

    self.Overridden.Load3DUI(self)
end

function M:Unload3DUI(show_ui)
    UIManager:GetInstance():ClearNotifications()

    self["Destroy Map Item"](self)

    self.Overridden.Unload3DUI(self, show_ui)
end

function M:OnLoad3DUIFinished()
    self.map_set_up = true
    self:SetUpMap()
    -- if self.UILoading2 then
    --     if UE.UKismetSystemLibrary.IsValid(self.UILoading2) then
    --         UIManager:GetInstance():RemoveLoadingUI(self.UILoading2)
    --     end
    --     self.UILoading2 = nil
    -- end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Loading2')
    if ui then
        ui:DelayDestroy()
    end

    ---@type UUserWidget
    local topUI = UIManager:GetInstance():GetTopUI()

    if UE.UGameplayStatics.ObjectIsA(topUI, LoadClass('/Game/_Game/Blueprints/UI/UI_CityMenu.UI_CityMenu_C')) then
        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
end

function M:OnBackCity()
    ---@type BP_GameMode_Universe_C
    local gameMode = UE.UGameplayStatics.GetGameMode(self)

    gameMode:LoadSaveGame()

    if gameMode.SaveGame.AbortLastGame then
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.resUniverse = {}
    end

    self.Overridden.OnBackCity(self)
end

function M:CreateLevelSequenceCoroutine(levelSequence, bindings, settings, transformOrigin, showSkipButton)
    return coroutine.create(function()
        local bindings = bindings or {}
        local settings = settings or {}
        
        local playbackSettings = UE.FMovieSceneSequencePlaybackSettings()
        for key, value in pairs(settings) do
            playbackSettings[key] = value
        end

        self.levelSequencePlayer, self.levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, playbackSettings)

        self.levelSequenceActor.LevelSequenceAsset = levelSequence

        for key, value in pairs(bindings) do
            self.levelSequenceActor:SetBindingByTag(key, value, false)
        end

        if transformOrigin then
            self.levelSequenceActor.bOverrideInstanceData = true
            self.levelSequenceActor.DefaultInstanceData.TransformOrigin = transformOrigin
        end
        self.levelSequencePlayer:Play()

        ---@type SkipBtn_C
        local skipButton
        if showSkipButton then
            skipButton = UE.UWidgetBlueprintLibrary.Create(self, LoadObject('/Game/_Game/Blueprints/UI/UI_Menu/UI_Skip.UI_Skip_C'))
            UIManager:GetInstance():AddUI(skipButton)

            skipButton.SkipBtn.Text:SetText(Database.L10n(99300001))

            skipButton.SkipBtn.SKIP.OnClicked:Add(skipButton.SkipBtn.SKIP, function()
                self.levelSequencePlayer:Stop()
            end)
        end

        while self.levelSequencePlayer:IsPlaying() do
            coroutine.yield()
        end

        if showSkipButton then
            UIManager:GetInstance():RemoveUI(skipButton)
        end

        self.levelSequenceActor:K2_DestroyActor()
        self.levelSequencePlayer = nil
        self.levelSequenceActor = nil
    end)
end

---@param mainPosInfos MainPosInfo[]
function M:AddMapItemCoroutine(mainPosInfos)
    return coroutine.create(function()
        ---@type BP_Map_Planet_C[]
        local newMapItems = {}
        local baseHex = SrpgController:GetInstance():GetBaseHex()
        local centerLocation
        if baseHex and self.MapPlanets:FindRef(hex_grid.to_string(baseHex)) then
            centerLocation = self.MapPlanets:FindRef(hex_grid.to_string(baseHex)):K2_GetActorLocation()
        else
            centerLocation = UE.FVector()
        end
        for _, mainPosInfo in ipairs(mainPosInfos) do
            local mapPlanet = self:UpdateMainPos(mainPosInfo.hex)

            mapPlanet:Dissolve(centerLocation)

            table.insert(newMapItems, mapPlanet)
        end

        ---@type BP_Character_Menu_C
        local character = self:K2_GetPawn()

        character.Capture_FOW.bCaptureEveryFrame = true

        local finished = false

        while not finished do
            coroutine.yield()
            finished = true
            for _, mapPlanet in ipairs(newMapItems) do
                if mapPlanet:IsDissolving() then
                    finished = false
                    break
                end
            end
        end

        character.Capture_FOW.bCaptureEveryFrame = false
    end)
end

local STOP_DISTANCE = 4000 * GlobalConfig.MapShipScale

---@param from string
---@param to string
function M:WrapCoroutine(from, to)
    return coroutine.create(function()
        ---@type BP_Map_Planet_C
        local targetMainPos = self.MapPlanets:FindRef(hex_grid.to_string(to))

        local targetMainPosLocation = targetMainPos:K2_GetActorLocation()
        -- local cameraLocation = self:K2_GetPawn():K2_GetActorLocation()
        -- cameraLocation.X = targetMainPosLocation.X
        -- cameraLocation.Y = targetMainPosLocation.Y + 2000
        -- self:K2_GetPawn():K2_SetActorLocation(cameraLocation, false, nil, true)

        local targetPos = targetMainPos.Ship:K2_GetComponentLocation()
        --转向
        local shipPos = self.detailedShip:K2_GetActorLocation()
        local lookRotation = UE.UKismetMathLibrary.FindLookAtRotation(shipPos, targetPos)
        self.detailedShip:K2_SetActorRotation(lookRotation, true)
        local moveDirection = UE.UKismetMathLibrary.Normal(targetPos - shipPos, 0.0001)
        local stopPos = targetPos - moveDirection * STOP_DISTANCE

        local co = self:CreateLevelSequenceCoroutine(M.boat_jumpstart, { Ship = { self.detailedShip } }, nil, self.detailedShip:GetTransform())

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        --减速
        self.detailedShip:K2_SetActorLocation(stopPos, false, nil, true)

        co = self:CreateLevelSequenceCoroutine(M.boat_jumpend, { Ship = { self.detailedShip } }, nil, self.detailedShip:GetTransform())

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        SrpgController:GetInstance():SetPlayerHex(to)

        MessageManager:GetInstance():Broadcast(SrpgController.UpdateMapItems)

        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.ShipMove)
    end)
end

---@param from Hex
---@param to Hex
function M:BossMoveCoroutine(bossIndex, from, to)
    return coroutine.create(function()
        ---@type BP_Map_Planet_C
        local targetMainPos = self.MapPlanets:FindRef(hex_grid.to_string(to))

        -- local targetMainPosLocation = targetMainPos:K2_GetActorLocation()
        -- local cameraLocation = self:K2_GetPawn():K2_GetActorLocation()
        -- cameraLocation.X = targetMainPosLocation.X
        -- cameraLocation.Y = targetMainPosLocation.Y + 2000
        -- self:K2_GetPawn():K2_SetActorLocation(cameraLocation, false, nil, true)

        local targetPos = targetMainPos.Boss:K2_GetComponentLocation()
        --转向
        local bossPos = self.detailedBosses[bossIndex]:K2_GetActorLocation()
        local lookRotation = UE.UKismetMathLibrary.FindLookAtRotation(bossPos, targetPos)
        self.detailedBosses[bossIndex]:K2_SetActorRotation(lookRotation, true)
        local moveDirection = UE.UKismetMathLibrary.Normal(targetPos - bossPos, 0.0001)
        local stopPos = targetPos - moveDirection * STOP_DISTANCE

        local co = self:CreateLevelSequenceCoroutine(M.boss_jumpstart, { Ship = { self.detailedBosses[bossIndex] } }, nil, self.detailedBosses[bossIndex]:GetTransform())

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        --减速
        self.detailedBosses[bossIndex]:K2_SetActorLocation(stopPos, false, nil, true)
        
        co = self:CreateLevelSequenceCoroutine(M.boss_jumpend, { Ship = { self.detailedBosses[bossIndex] } }, nil, self.detailedBosses[bossIndex]:GetTransform())

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.BossMoved)
    end)
end

---@param pos Hex
function M:BossShowUpCoroutine(bossIndex, pos)
    return coroutine.create(function()
        ---@type BP_Map_Planet_C
        local showUpMainPos = self.MapPlanets:FindRef(hex_grid.to_string(pos))

        local targetMainPosLocation = showUpMainPos:K2_GetActorLocation()
        local cameraLocation = self:K2_GetPawn():K2_GetActorLocation()
        cameraLocation.X = targetMainPosLocation.X
        cameraLocation.Y = targetMainPosLocation.Y + 2000
        self:K2_GetPawn():K2_SetActorLocation(cameraLocation, false, nil, true)

        local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
        local bossConfig = Database.Query("d_srpg_level_boss", bossConfigId)

        local bossPosition = showUpMainPos.Boss:K2_GetComponentLocation()
        local bossTransform = UE.UKismetMathLibrary.MakeTransform(bossPosition, UE.FRotator(), UE.FVector(1, 1, 1))
        ---@type BP_Character_1_Universe_C
        local bossObject = self:GetWorld():SpawnActor(LoadClass(string.format(BOSS_MODEL_PATH, bossConfig.bossModel, bossConfig.bossModel)),
            bossTransform, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
        bossObject:SetActorScale3D(UE.FVector(BOSS_MODEL_SCALE, BOSS_MODEL_SCALE, BOSS_MODEL_SCALE))
        self.detailedBosses[bossIndex] = bossObject

        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.Hidden)

        local co = self:CreateLevelSequenceCoroutine(M.bossjump, nil, { bRestoreState = true }, nil, true)

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.BossShowUp)
    end)
end

function M:GameEndCoroutine()
    return coroutine.create(function()
        ---@type BP_GameInstance_C
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        
        if SrpgController:GetInstance():GetEndReason() == SrpgModel.EndReason.Clear then
            self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.Hidden)

            local co = self:CreateLevelSequenceCoroutine(M.atkwin, nil, { bRestoreState = true }, nil, true)

            while coroutine.status(co) ~= "dead" do
                self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.Hidden)
                coroutine.yield(coroutine.resume(co))
            end

            self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end

        --     local random = math.random()

        --     -- gameInstance:OpenStory(random > 0.5 and 20101001 or 20101005)
        --     gameInstance:OpenStory(20101001)
        if SrpgController:GetInstance():GetEndReason() == SrpgModel.EndReason.Lose then
            SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.GameEnd)
            gameInstance:OpenStory(20101009)
        else
            SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.GameEnd)

            SrpgController:GetInstance():EndRun()
        end
    end)
end

---@param pos Hex
function M:BossArrivedCoroutine(bossIndex, pos)
    return coroutine.create(function()
        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.Hidden)

        local co = self:CreateLevelSequenceCoroutine(M.bossatk, nil, { bRestoreState = true }, nil, true)

        while coroutine.status(co) ~= "dead" do
            coroutine.yield(coroutine.resume(co))
        end

        self.BP_PlayerController_UniverseMenu.UI_Menu:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.BossArrived)
    end)
end

---@param self BP_PlayerController_Universe_C
M[Protos.RES_COMPLETE_UNIVERSE_FIGHT] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if self.fightEndMsg.result then
            SrpgController:GetInstance():CompleteCurrentFight()
        else
            SrpgController:GetInstance():StopCurrentFight()
        end

        SrpgController:GetInstance():UpdateFightData(self.fightEndMsg.universe_fight_data)

        self.fightEndMsg = nil
    end
end

---@param self BP_PlayerController_Universe_C
M[Protos.RES_COMPLETE_BOSS_FIGHT] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if self.fightEndMsg.result then
            SrpgController:GetInstance():CompleteCurrentBossFight()
        else
            SrpgController:GetInstance():StopCurrentFight()
        end

        SrpgController:GetInstance():UpdateFightData(self.fightEndMsg.universe_fight_data)

        self.fightEndMsg = nil
    end
end

---@param self BP_PlayerController_Universe_C
M[Protos.NTF_ITEM_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        local triggerId = SrpgController:GetInstance():GetTriggerId()
        if triggerId ~= 0 then
            SrpgController:GetInstance():AddEvent({
                type = SrpgModel.TurnEvents.ShowItems,
                info = {
                    items = parsed_msg.ntf_item_info.changed_item_infos,
                    triggerId = triggerId,
                }
            })
        end
    end
end

---@param self BP_PlayerController_Universe_C
---@param universeFightData UniverseFightData
M[SrpgController.FightEnd] = function(self, result, universeFightData)
    if self.fightEndMsg then
        return
    end

    local currentFightInfo = SrpgController:GetInstance():GetCurrentFightInfo()

    if not currentFightInfo then
        LOG_WARN("Missing fight level")

        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.FightEnd)

        return
    end

    local fightData = SrpgController:GetInstance():GetCharacterFightData()

    local data = {}
    for k, oldFightData in pairs(fightData) do
        local id = oldFightData.character_id
        local hp = 0
        for i, v in ipairs(universeFightData.character_fight_datas) do
            if v.character_id == id then
                hp = v.cur_hp
            end
        end
        data[k] = {
            character_id = id,
            cur_hp = hp,
        }
    end

    universeFightData.character_fight_datas = data

    if not SrpgController:GetInstance():IsBossFight(currentFightInfo) then
        ---@type ReqCompleteUniverseFight
        self.fightEndMsg = {
            fight_uuid = currentFightInfo.fight_uuid,
            result = result == SrpgController.FightResult.Win,
            universe_fight_data = universeFightData,
        }
        Client.send(Protos.REQ_COMPLETE_UNIVERSE_FIGHT, self.fightEndMsg)
    else
        local bossInfo = SrpgController:GetInstance():GetBossInfoByUUID(currentFightInfo.fight_uuid)
        ---@type ReqCompleteBossFight
        self.fightEndMsg = {
            boss_index = bossInfo.boss_index,
            result = result == SrpgController.FightResult.Win,
            universe_fight_data = universeFightData,
        }
        Client.send(Protos.REQ_COMPLETE_BOSS_FIGHT, self.fightEndMsg)
    end

    SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.FightEnd)
end



---@param self BP_PlayerController_Universe_C
---@param itemInfo ChangedItemInfo[]
M[SrpgController.ShowItems] = function(self, itemInfo, triggerId)
    local rewardList = {}
    for _, item in pairs(itemInfo) do
        table.insert(rewardList, {
            itemId = item.item_id,
            count = item.count,
        })
    end

    local config = Database.Query("d_srpg_effect_trigger", triggerId)
    local effectDisplay = config and config.effectDisplay or {}

    local normal = true
    local win = true

    if #effectDisplay > 0 then
        if table.indexof(effectDisplay, SrpgController.SpecialDisplay.GameEnd) then
            normal = false
            win = SrpgController:GetInstance():GetCurHp() > 0 and (SrpgController:GetInstance():GetBossWaveCount() == SrpgController:GetInstance():GetTurn())
        end
    end

    ---@type UI_GetItem_Notice_C
    local rewardUI = UIUtils.ShowGetRewardCommonUI(self, rewardList)
    rewardUI.win:SetVisibility((not normal and win) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
    rewardUI.lose:SetVisibility((not normal and not win) and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)

    rewardUI.callback = function()
        SrpgController:GetInstance():CheckAndRemoveEvent(SrpgModel.TurnEvents.ShowItems)
    end
end

---@param self BP_PlayerController_Universe_C
---@param bossIndex number
---@param hex Hex
M[SrpgController.BossShowUp] = function(self, bossIndex, hex)
    table.insert(self.levelSequenceCoroutines, self:BossShowUpCoroutine(bossIndex, hex))
end

---@param self BP_PlayerController_Universe_C
---@param bossIndex number
---@param from Hex
---@param to Hex
M[SrpgController.BossMove] = function(self, bossIndex, from, to)
    table.insert(self.levelSequenceCoroutines, self:BossMoveCoroutine(bossIndex, from, to))
end

---@param self BP_PlayerController_Universe_C
---@param bossIndex number
---@param hex Hex
M[SrpgController.BossArrived] = function(self, bossIndex, hex)
    table.insert(self.levelSequenceCoroutines, self:BossArrivedCoroutine(bossIndex, hex))
end

---@param self BP_PlayerController_Universe_C
---@param from string
---@param to string
M[SrpgController.ShipMove] = function(self, from, to)
    table.insert(self.levelSequenceCoroutines, self:WrapCoroutine(from, to))
end

M[SrpgController.GameEnd] = function(self, from, to)
    table.insert(self.levelSequenceCoroutines, self:GameEndCoroutine())
end

---@param self BP_PlayerController_Universe_C
---@param mainPosInfo MainPosInfo[]
M[SrpgController.AddMapItem] = function(self, mainPosInfos)
    if not self.map_set_up then return end
    table.insert(self.levelSequenceCoroutines, self:AddMapItemCoroutine(mainPosInfos))
end

---@param self BP_PlayerController_Universe_C
M[SrpgController.UpdateMapItems] = function(self)
    for _, mapItem in pairs(self.MapPlanets) do
        mapItem:UpdateEffects()
    end
end

---@param self BP_PlayerController_Universe_C
M[SrpgController.UpdateMapLines] = function(self, arrivedHex)
    self:UpdateMapLine(arrivedHex)
end

---@param self BP_PlayerController_Universe_C
M[SrpgController.UpdateMapBounds] = function(self)
    self.BP_PlayerController_UniverseMenu:UpdateMapBounds()
end

M[UI_Dialog_Story_C.DialogEnd] = function(self, originDialogId, dialogId)
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if table.indexof(SrpgController.SRPG_END_DIALOG_IDS, dialogId) then
        SrpgController:GetInstance():EndRun()
    elseif dialogId == 20101014 then
        local SaveGameSpeak = gameInstance:LoadSaveGameSpeak()
        if gameInstance.SRPGBackLevel ~= "None" then
            --1-宇宙行动 2-SpecialSPRG
            if gameInstance.SpecialUniverse == 1 then
            elseif gameInstance.SpecialUniverse == 2 then
            end
            gameInstance:LoadLevel(gameInstance.SRPGBackLevel)
            --gameInstance.SRPGBackLevel = "None"
        else
            gameInstance:LoadLevel("CityMap")
        end
    elseif dialogId == 20101018 then
        gameInstance:Abort()
    end
end

local NIAGARA_PATH = '/Game/_Game/3DRES/Effect/NiagaraSystem/UI/GodAni/%s.%s'

function M:SetBuffEffect(buffId)
    local buffInfo = Database.Query("d_srpg_temp_buff", buffId)

    ---@type BP_Character_Menu_C
    local cameraActor = self:K2_GetPawn()
    if cameraActor then
        self.niagaraComponent = cameraActor.BuffNiagara
        if self.niagaraComponent then
            self.tempBuffId = buffId
            self.niagaraComponent:SetAsset(LoadObject(string.format(NIAGARA_PATH, buffInfo.effect, buffInfo.effect)))
        end
    end
end

---@param self BP_PlayerController_Universe_C
M[SrpgModel.GetDefiniteBuff] = function(self, buffId)
    self:SetBuffEffect(buffId)

    self.BP_PlayerController_UniverseMenu.UI_Menu:UpdateTempBuff()
end

M[SrpgModel.BuffExpired] = function(self, buffId)
    if self.tempBuffId == buffId then
        self.niagaraComponent:SetAsset(nil)
    end
end

function M:OnLoadBuildRegion()
    
end

function M:OnUnLoadBuildRegion()
    --获取场景中所有的actor
    local buildActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "Buildable")
    for i = 1, buildActors:Length() do
        local actor = buildActors:Get(i)
        actor:K2_DestroyActor()
    end
end


function M:ShowUI(prevUI)
    if not self.UI_Bridge then
        self.UI_Bridge = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_City')
    end
    if not prevUI then
        self.BP_PlayerController_City_UniverseBridge.UI_City = self.UI_Bridge
    end
    if not prevUI or (self.UI_Bridge == prevUI) then
        self.UI_Bridge:OnShowUI()
        self.UI_Bridge:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    end
end
    

function M:HideUI(prevUI)
    if not self.UI_Bridge then
        self.UI_Bridge = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_City')
    end
    if not prevUI then
        self.BP_PlayerController_City_UniverseBridge.UI_City = self.UI_Bridge
    end
    if not prevUI or (self.UI_Bridge == prevUI) then
        self.UI_Bridge:OnHideUI()
    end
end

function M:OnBridgeToWorldFinished()
    self.Overridden.OnBridgeToWorldFinished(self)
    if self.UI_Bridge then
        UIManager:GetInstance():RemoveUI(self.UI_Bridge)
        self.UI_Bridge = nil
    end
end

return M

--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
local Client = require "Network.Client"
local hex_grid = require "Helper.hex_grid"
local Database = require "_Game.Utils.Database"
local GlobalConfig = require("GlobalConfig")
local SrpgController = require("Module.Srpg.SrpgController")
---@type BP_GameMode_Universe_C
local BP_GameMode_Universe_C = Class()

function BP_GameMode_Universe_C:Initialize(Initializer)
    self.planetNum = 0
    self.planetId = 0
end

function BP_GameMode_Universe_C:ReceiveBeginPlay()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.BackFromFight = false

    -- if not gameInstance.BoatClass then
    --     local boadId = 1
    --     local path = string.format("'/Game/_Game/Blueprints/Players/BP_Actor_Boat_%d.BP_Actor_Boat_%d_C'", boadId, boadId) 
    --     local boatClass = UE.UClass.Load(path)
    --     if boatClass then
    --         gameInstance.BoatClass = boatClass
    --     end
    -- end

    self.Overridden.ReceiveBeginPlay(self)

    local planetId = SrpgController:GetInstance():GetPlanetId()
    if planetId == 110 then
        self.LevelName = "Universe1Map"
        gameInstance:ClearAllSubLevelName()
        gameInstance:AddSubLevelName("Universe1Map")
    elseif planetId == 102 then
        self.LevelName = "Universe_Mercury"
        gameInstance:ClearAllSubLevelName()
        gameInstance:AddSubLevelName("Universe_Mercury")
    end
end

--function BP_GameMode_Universe_C:UserConstructionScript()
--end

--function BP_GameMode_Universe_C:ReceiveEndPlay()
--	self.Overridden.ReceiveEndPlay(self)
--end

-- function BP_GameMode_Universe_C:ReceiveTick(DeltaSeconds)
--	self.Overridden.ReceiveTick(self,DeltaSeconds)
-- end

--function BP_GameMode_Universe_C:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
--end

--function BP_GameMode_Universe_C:ReceiveActorBeginOverlap(OtherActor)
--end

--function BP_GameMode_Universe_C:ReceiveActorEndOverlap(OtherActor)
--end

function BP_GameMode_Universe_C:GetPlanetNum()
    return self.planetNum
end

function BP_GameMode_Universe_C:GetPlanetId()
    return self.planetId
end

function BP_GameMode_Universe_C:GetMainPosStateInfo(posId)
    local typeId = 0
    local visible = true
    local explored = false
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local resUniverse = gameInstance:GetUniverseInfo()
    local index = 0
    if resUniverse ~= nil then
        local info = gameInstance.mainPosInfos[posId]
        if info ~= nil then
            visible = info["visible"]
            explored = info["explored"]
            typeId = info["main_pos_id"]
            index = info["index"] - 1
        end
    end
    return typeId, visible, explored, index
end

function BP_GameMode_Universe_C:GetCardsInPlace(posId)
    local cardsInPlace = { 0 }
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.mainPosInfos[posId] then
        local cards = gameInstance.mainPosInfos[posId]["card_in_place"]
        if #cards > 0 then
            cardsInPlace = { cards[1].card_info.card_id }
        end
    end
    return cardsInPlace
end

function BP_GameMode_Universe_C:GetSavedOffset(hex)
    local hexId = hex_grid.to_string(hex)
    local savedPosition = self.SaveGame.MainPosOffset:Find(hexId)

    if not savedPosition then
        local hex_offset = hex_grid.hex_to_pixel(hex, GlobalConfig.MapItemDistance / 2)
        local random_x = math.random(-GlobalConfig.RandomOffestX, GlobalConfig.RandomOffestX)
        local random_y = math.random(-GlobalConfig.RandomOffestY, GlobalConfig.RandomOffestY)
        local random_z = math.random(-GlobalConfig.RandomOffestZ, GlobalConfig.RandomOffestZ)
        savedPosition = UE.FVector(hex_offset.x + random_x, hex_offset.y + random_y, random_z)

        self.SaveGame.MainPosOffset:Add(hexId, savedPosition)

        self:SaveSaveGame()
    end

    return savedPosition
end

function BP_GameMode_Universe_C:GetSavedRotation(hex)
    local hexId = hex_grid.to_string(hex)
    local savedRotation = self.SaveGame.MainPosRotation:Find(hexId)

    if not savedRotation then
        savedRotation = math.random(360)

        self.SaveGame.MainPosRotation:Add(hexId, savedRotation)

        self:SaveSaveGame()
    end

    return savedRotation
end

function BP_GameMode_Universe_C:ResetPlanetsTransform()
    local postprocess_volumes = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.APostProcessVolume)
    local volume_num = postprocess_volumes:Length()
    local universe_postProcess = nil
    if volume_num > 0 then
        for i = 1, volume_num do
            local name = UE.UKismetSystemLibrary.GetDisplayName(postprocess_volumes[i])
            if name == "UniversePostProcessVolume" then
                universe_postProcess = postprocess_volumes[i]
                break
            end
        end
    end
    if universe_postProcess then
        local center_location = universe_postProcess:K2_GetActorLocation()
        local volume_height = universe_postProcess:GetActorScale3D().Z * 200
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local mainPos_num = self.MainPoses:Length()
        if mainPos_num > 0 then
            for i = 1, mainPos_num do
                local main_pos_info = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos[i]
                local offset = self:GetSavedOffset(main_pos_info.hex) * GlobalConfig.UniverseScale
                local planet_id = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].planet_id
                local z_offset = volume_height * (Database.Query("d_srpg_universe", planet_id).mapZOffset - 0.5)
                local pos = center_location + offset + UE.FVector(0, 0, z_offset)
                local mainPos = self.MainPoses[i]
                self.MainPoses[i]:K2_SetActorLocation(pos, false, nil, false)
                local hex_id = string.format("%d,%d", main_pos_info.hex.r, main_pos_info.hex.q)
                mainPos:Init(i - 1, main_pos_info.main_pos_id, hex_id)
            end
        end
    end
end

---------------------------Cmd---------------------------

local NET_COMMANDS = {
    'add_card',
    'add_curio',
    'add_res',
    'add_explore_times',
    'finish_universe',
}

function BP_GameMode_Universe_C:OnGHSCMD(msg)
    local array = string.split(msg, ' ')
    if array[1] == 'restart' then
        self:Restart_Game()
    elseif array[1] == 'add_item' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'fight' then
        if array[2] then
            self:SpawnTestFight(array[2])
        end
    elseif table.indexof(NET_COMMANDS, array[1]) then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'openstory' then
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        playerController.BP_PlayerController_UniverseMenu:HidePlanetUI()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:OpenStory(array[2])
    elseif array[1] == 'add_character' then
        Client.send("req_gm_cmd", { cmd = msg })
    elseif array[1] == 'debugui' then
        UIManager:GetInstance():DebugUI()
    elseif array[1] == 'debug' then
        if array[2] == 'event' then
            LOG_INFO(table.dump(SrpgController:GetInstance().model.pendingEvents, false, 10))
        end
    else
        local type = array[1]
        table.remove(array, 1)
        UE.UGameplayStatics.GetGameInstance(self):OnMessage(type, array)
    end
end

function BP_GameMode_Universe_C:Restart_Game()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local playercontroller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if gameInstance.resUniverse == nil then
        LOG_WARN("请账号登录")
        return
    end
    gameInstance.LoggedIn = true
    playercontroller:OnBackCityFinished()
end

function BP_GameMode_Universe_C:SpawnTestFight(levelId)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.testLevelId = tonumber(levelId)
    local level_path = '/Game/_Game/Blueprints/Levels/SRPG/Level%s/TestLevel%s.TestLevel%s_C'
    level_path = string.format(level_path, levelId, levelId, levelId)
    local fightLevelClass = UE.LoadClass(level_path)
    gameInstance.LevelClass = fightLevelClass
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        playerController:LoadFight()
    end
end

function BP_GameMode_Universe_C:AddCmdCard(cards_id)
    local card_info = {}
    local pos_hex = {}
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.resUniverse then
        for _, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos) do
            local pos_data = Database.Query('d_srpg_main_pos_base', value.main_pos_id)
            if pos_data.mainPosType == 1 then
                pos_hex = value.hex
            end
        end
        for _, value in ipairs(cards_id) do
            local repeat_result = false
            for _, card_pos_info in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos) do
                if card_pos_info.card_info.card_id == tonumber(value) then
                    repeat_result = true
                    LOG_WARN('card repeat', value)
                    break
                end
            end
            if not repeat_result then
                card_info = {}
                card_info.card_info = {}
                card_info.card_info.card_id = tonumber(value)
                card_info.index = 0
                card_info.upgrade_times = 0
                card_info.card_upgrade_for_select = {}
                card_info.apex_card_infos = {}
                card_info.hex = pos_hex
                card_info.cmd_test = true
                table.insert(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos, card_info)
            end
        end
    end
    -- 临时刷新一下ui
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Menu')
    if ui then
        ui:UpdateRaceInfo()
    end
end

function BP_GameMode_Universe_C:RemoveCmdCard(cards_id)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.resUniverse then
        for _, card_id in ipairs(cards_id) do
            for index, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos) do
                if value.cmd_test and value.card_info.card_id == tonumber(card_id) then
                    table.remove(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos, index)
                end
            end
        end
    end
end

function BP_GameMode_Universe_C:AddCmdUpgrade(upgrade_ids)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local pos_hex = {}
    if gameInstance.resUniverse then
        local find_result = false
        for _, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos) do
            local pos_data = Database.Query('d_srpg_main_pos_base', value.main_pos_id)
            if pos_data.mainPosType == 1 then
                pos_hex = value.hex
            end
        end
        local card_upgrade_infos = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_upgrade_infos
        if not card_upgrade_infos.cmd_upgrade_ids then
            card_upgrade_infos.cmd_upgrade_ids = {}
        end
        for _, card_upgrade_info in ipairs(card_upgrade_infos) do
            if card_upgrade_info.hex.r == pos_hex.r and
                card_upgrade_info.hex.q == pos_hex.q then
                for __, effect_id in ipairs(upgrade_ids) do
                    table.insert(card_upgrade_info.upgrade_ids, tonumber(effect_id))
                    table.insert(card_upgrade_infos.cmd_upgrade_ids, tonumber(effect_id))
                end
                find_result = true
                break
            end
        end
        if find_result == false then
            local upgrade_info = {}
            upgrade_info.hex = pos_hex
            upgrade_info.upgrade_ids = {}
            upgrade_info.cmd_upgrade_ids = {}
            for _, effect_id in ipairs(upgrade_ids) do
                table.insert(upgrade_info.upgrade_ids, tonumber(effect_id))
                table.insert(card_upgrade_infos.cmd_upgrade_ids, tonumber(effect_id))
            end
            table.insert(card_upgrade_infos, upgrade_info)
        end
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Menu')
    if ui then
        ui:UpdateCurios()
    end
end

function BP_GameMode_Universe_C:RemoveCmdUpgrade(upgrade_ids)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local pos_hex = {}
    local upgrade_info = {}
    if gameInstance.resUniverse then
        local card_upgrade_infos = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_upgrade_infos
        for _, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos) do
            local pos_data = Database.Query('d_srpg_main_pos_base', value.main_pos_id)
            if pos_data.mainPosType == 1 then
                pos_hex = value.hex
            end
        end
        for _, value in ipairs(card_upgrade_infos) do
            if value.hex.r == pos_hex.r and value.hex.q == pos_hex.q then
                upgrade_info = value
                break
            end
        end
        if upgrade_info and card_upgrade_infos.cmd_upgrade_ids then
            for i = 1, #upgrade_ids do
                local find_result = false
                for index, cmd_upgrade_id in ipairs(card_upgrade_infos.cmd_upgrade_ids) do
                    if cmd_upgrade_id == tonumber(upgrade_ids[i]) then
                        table.remove(card_upgrade_infos.cmd_upgrade_ids, index)
                        find_result = true
                        break
                    end
                end
                if find_result then
                    for index, upgrade_id in ipairs(upgrade_info.upgrade_ids) do
                        if upgrade_id == tonumber(upgrade_ids[i]) then
                            table.remove(upgrade_info.upgrade_ids, index)
                            break
                        end
                    end
                end
            end
        end
    end
end

function BP_GameMode_Universe_C:RemoveAllCmdCard()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local pos_hex = {}
    local upgrade_info = {}
    if gameInstance.resUniverse then
        for _, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos) do
            local pos_data = Database.Query('d_srpg_main_pos_base', value.main_pos_id)
            if pos_data.mainPosType == 1 then
                pos_hex = value.hex
            end
        end
        for index, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos) do
            if value.cmd_test then
                table.remove(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos, index)
            end
        end
        local card_upgrade_infos = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_upgrade_infos
        for _, value in ipairs(card_upgrade_infos) do
            if value.hex.r == pos_hex.r and value.hex.q == pos_hex.q then
                upgrade_info = value
                break
            end
        end
        if card_upgrade_infos.cmd_upgrade_ids then
            for _, cmd_upgrade_id in ipairs(card_upgrade_infos.cmd_upgrade_ids) do
                for index, upgrade_id in ipairs(upgrade_info.upgrade_ids) do
                    if cmd_upgrade_id == upgrade_id then
                        table.remove(upgrade_info.upgrade_ids, index)
                        break
                    end
                end
            end
        end
    end
end

function BP_GameMode_Universe_C:ShowCmdCardInfo()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.resUniverse then
        for _, value in ipairs(gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos) do
            if value.cmd_test then
                LOG_WARN('cmd card', value.card_info.card_id)
            end
        end
        local card_upgrade_infos = gameInstance.resUniverse.res_universe.universe_info.planet_infos[1].card_upgrade_infos
        if card_upgrade_infos.cmd_upgrade_ids then
            for __, cmd_upgrade_id in ipairs(card_upgrade_infos.cmd_upgrade_ids) do
                LOG_WARN('cmd upgrade effect', cmd_upgrade_id)
            end
        end
    end
end

function BP_GameMode_Universe_C:SetSkipWrapAnimation()
    local playercontroller = UE.UGameplayStatics.GetPlayerController(self, 0)

    playercontroller.SkipWrapAnimation = not playercontroller.SkipWrapAnimation

    if playercontroller.SkipWrapAnimation then
        LOG_WARN('SkipWrapAnimation On')
    else
        LOG_WARN('SkipWrapAnimation Off')
    end
end

---------------------------------------------------------

function BP_GameMode_Universe_C:LoadSaveGame()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    ---@type SG_SaveGame_Universe_C
    local gameSave
    if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Universe_" .. gameInstance.account_id, 0) then
        gameSave = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_Universe_" .. gameInstance.account_id, 0)
    else
        gameSave = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load("/Game/_Game/Blueprints/Game/SG_SaveGame_Universe.SG_SaveGame_Universe_C"))
    end

    self.SaveGame = gameSave

    return gameSave
end

function BP_GameMode_Universe_C:SaveSaveGame()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if self.SaveGame then
        UE.UGameplayStatics.SaveGameToSlot(self.SaveGame, "SG_SaveGame_Universe_" .. gameInstance.account_id, 0)
    end
end

return BP_GameMode_Universe_C

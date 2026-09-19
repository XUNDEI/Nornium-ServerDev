--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "Global"
require "UnLua"
local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local hex_grid = require "Helper.hex_grid"
local Database = require "_Game.Utils.Database"
local d_srpg_card_base = require "ClientDatas.d_srpg_card_base"
local d_srpg_effect_fight = require "ClientDatas.d_srpg_effect_fight"
local d_srpg_curio_base = require "ClientDatas.d_srpg_curio_base"
local d_srpg_universe = require "ClientDatas.d_srpg_universe"
local d_srpg_effect_buff = require "ClientDatas.d_srpg_effect_buff"
local d_srpg_temp_buff = require "ClientDatas.d_srpg_temp_buff"
local d_srpg_mission = require("ClientDatas.d_srpg_mission")
local FightTestConfig = require("_Game.FightTestConfig")
local UIUtils = require "_Game.Utils.UIUtils"
local QuestSystem = require "Module.Quest.QuestSystem"
local HardLevelSystem = require 'Module.HardLevel.HardLevelSystem'
local BackpackSystem = require 'Module.Backpack.BackpackSystem'
local SrpgController = require("Module.Srpg.SrpgController")
local MessageManager = require "Framework.Updater.MessageManager"
local BossRushController = require("Module.BossRush.BossRushController")
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"

---@type BP_GameMode_Fight_C
local M = UnLua.Class()

function M:Initialize()
    if not M.EnemyIndicatorClassRef then
        M.EnemyIndicatorClass = LoadClass('/Game/_Game/Blueprints/Game/BP_Enemy_Indicator.BP_Enemy_Indicator_C')
        M.EnemyIndicatorClassRef = UnLua.Ref(M.EnemyIndicatorClass)
    end
end

function M:ReceiveBeginPlay()
    self.bLuaGameIsOver = false
    local characterConfig = require "ClientDatas.d_character"
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.PlayerIds = {}
    if gameInstance.SaveGameTeamList then
        local teamInfo
        local ids = {}
        
        if SrpgController:GetInstance():IsUniverseExist() and
            SrpgController:GetInstance():GetCurrentFightInfo() and
            gameInstance.fightType ~= gameInstance.FIGHT_STATE.TempCopy then
            for _, entry in ipairs(SrpgController:GetInstance():GetCharacterFightData()) do
                table.insert(ids, entry.character_id)
            end
        elseif BossRushController:GetInstance():HasPendingFight() and 
            BossRushController:GetInstance():GetCurrentFightRecord() and 
            BossRushController:GetInstance():GetCurrentFightRecord().character_ids then
            for _, entry in ipairs(BossRushController:GetInstance():GetCurrentFightRecord().character_ids) do
                table.insert(ids, entry)
            end
        else
            if gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or
                gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
                teamInfo = gameInstance:GetTrainCopyTeamList()
            else
                teamInfo = gameInstance:GetSelectedTeamList()
            end
            for i = 1, teamInfo.RoleList:Length() do
                table.insert(ids, teamInfo.RoleList:Get(i))
            end
        end

        gameInstance.PlayerClass:Clear()
        gameInstance.PlayerHeads:Clear()
        for i = 1, #ids do
            local roleId = ids[i]
            local charConfig = characterConfig[roleId]
            if charConfig then
                if charConfig.fightModelPath and charConfig.fightModelPath ~= "" then
                    --解析 1001/BP_Character_1001
                    local strArr = string.split(charConfig.fightModelPath, '/')
                    local path = string.format("'/Game/_Game/Blueprints/Players/%s.%s_C'", charConfig.fightModelPath,
                        strArr[2])
                    local playerClass = UE.UClass.Load(path)
                    if playerClass then
                        print("-------playerClass:" .. tostring(playerClass))
                        gameInstance.PlayerClass:Add(playerClass)
                        table.insert(self.PlayerIds, roleId)
                    end
                end

                local HeadPath = string.format("Texture2D'/Game/_Game/TP_New/Fight/HeadTP/%s.%s'",
                    charConfig.fightHead, charConfig.fightHead)
                local iconTexture = LoadObject(HeadPath)
                if iconTexture then
                    gameInstance.PlayerHeads:Add(iconTexture)
                end
            end
            self.PlayerIndex:Set(i, roleId)
        end
    end
    LOG_INFO("load")
    if gameInstance.PlayerClass:Length() == 0 then
        LOG_ERROR('-----------错误的角色：')
        local roleIds = { 10501}
        for i = 1, #roleIds do
            local roleId = roleIds[i]
            local charConfig = characterConfig[roleId]
            if charConfig then
                if charConfig.fightModelPath and charConfig.fightModelPath ~= "" then
                    --解析 1001/BP_Character_1001
                    local strArr = string.split(charConfig.fightModelPath, '/')
                    local path = string.format("'/Game/_Game/Blueprints/Players/%s.%s_C'", charConfig.fightModelPath,
                        strArr[2])
                    local playerClass = UE.UClass.Load(path)
                    LOG_INFO("player", path, playerClass)
                    if playerClass then
                        gameInstance.PlayerClass:Add(playerClass)
                        table.insert(self.PlayerIds, roleId)
                    end
                end

                local HeadPath = string.format("Texture2D'/Game/_Game/TP_New/Fight/HeadTP/%s.%s'", charConfig.fightHead,
                    charConfig.fightHead)
                local iconTexture = LoadObject(HeadPath)
                if iconTexture then
                    gameInstance.PlayerHeads:Add(iconTexture)
                end
            end
        end
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if nil == gameInstance.LevelClass and gameInstance.LevelClassPath ~= '' then
        local classPath = gameInstance.LevelClassPath
        if not string.endswith(classPath, "_C'") then
            local sub = string.sub(classPath, 1, -2) .. "_C'"
            classPath = sub
        end
        print("--------------------->LevelClassPath:" .. tostring(classPath))
        gameInstance.LevelClass = LoadClass(classPath)
        gameInstance.LevelClassPath = ''
    end

    if UE.UGHSFunctionLibrary.WithEditor() and not gameInstance.LevelClass then
        local levelId = 33003
        local level_path = '/Game/_Game/Blueprints/Levels/LevelTest%d/FightLevel%d.FightLevel%d_C'
        level_path = string.format(level_path, levelId, levelId, levelId)
        local fightLevelClass = UE.LoadClass(level_path)
        LOG_INFO("level", level_path, fightLevelClass)
        gameInstance.LevelClass = fightLevelClass
    end
    if not gameInstance.BoatClass then
        local boadId = 1
        local path = string.format("'/Game/_Game/Blueprints/Players/BP_Actor_Boat_%d.BP_Actor_Boat_%d_C'", boadId, boadId)
        local boatClass = UE.UClass.Load(path)
        LOG_INFO("boat", path, boatClass)
        if boatClass then
            gameInstance.BoatClass = boatClass
        end
    end

    self.Overridden.ReceiveBeginPlay(self)
end

function M:ReceiveEndPlay()
    NetworkMessageManager:GetInstance():RemoveListener("res_complete_hard_level_fight", self)
    -- NetworkMessageManager:GetInstance():RemoveListener("res_complete_daily_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
end

function M:SpawnActors()
    self.Overridden.SpawnActors(self)
    print("------SpawnActors")
    for i = 1, self.Players:Length() do
        local player = self.Players:Get(i)
        local character_id = self.PlayerIds[i]
        if player and character_id and character_id > 0 then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local savedIdolId, savedCharId, _, defaultIdolId, defaultCharId, _ = UIUtils.GetIdolAndCharMeshByCharacterId(character_id)
            print("====savedIdolId:" .. tostring(savedIdolId) .. ",savedCharId:" .. tostring(savedCharId) .. ",defautIdol:" .. tostring(defaultIdolId) .. ",defautChar:" .. tostring(defaultCharId))
            if savedIdolId > 0 and (savedIdolId ~= defaultIdolId) then
                local config = Database.Query("d_char_clothes", savedIdolId)
                if config and config.modelF ~= '' then
                    local newMesh = LoadObject(config.modelF)
                    if newMesh then
                        player.Mesh:SetSkeletalMeshAsset(newMesh)
                    end
                end
            end
            if player.InitFightIdol then
                print('------------>initfightidle:' .. tostring(savedIdolId > 0 and savedIdolId or defaultIdolId))
                player:InitFightIdol(savedIdolId > 0 and savedIdolId or defaultIdolId)
            end
            if savedCharId > 0 and (savedCharId ~= defaultCharId) then
                local config = Database.Query("d_char_clothes", savedCharId)
                --身体
                if config and config.modelF ~= '' then
                    local newMesh = LoadObject(config.modelF)
                    if newMesh then
                        player.SkeletalMesh:SetSkinnedAssetAndUpdate(newMesh, true)
                        player.SkeletalMesh:SetSimulatePhysics(true)
                    end
                end
                --头发
                if config and config.modelHair ~= '' then
                    local newMesh = LoadObject(config.modelHair)
                    if newMesh then
                        player.Hair:SetSkinnedAssetAndUpdate(newMesh, true)
                    end
                end
                --脸
                if config and config.modelFace ~= '' then
                    local newMesh = LoadObject(config.modelFace)
                    if newMesh then
                        player.face:SetSkinnedAssetAndUpdate(newMesh, true)
                    end
                end
            end
        end
    end
end

function M:StartGame()
    ---@type table<BP_EnemyCharacter_Fight_C, BP_Enemy_Indicator_C>
    self.enemyIndicators = {}

    self.Overridden.StartGame(self)
end

---------------------------Cmd---------------------------
function M:OnGHSCMD(msg)
    LOG_INFO("===请求GM命令:" .. tostring(msg))
    local array = string.split(msg, ' ')
    local type = array[1]
    table.remove(array, 1)
    UE.UGameplayStatics.GetGameInstance(self):OnMessage(type, array)
end

function M:GetMonsterHpPortion(id)
    local id = tostring(id)
    local enemies = table.keys(self.enemyIndicators)

    ---@param enemy BP_EnemyCharacter_Fight_C
    for _, enemy in ipairs(enemies) do
        local name = enemy:GetClass():GetName()
        if string.match(name, id) then
            return 1.0 - enemy:GetHealth() / enemy:GetMaxHealth()
        end
    end
end

-- 战斗结束后要丢给服务器的信息，目前是角色血量
function M:GetUniverseFightData(win)
    local d_character = require "ClientDatas.d_character"

    local characterData = {}

    for i = 1, self.Players:Length() do
        local player = self.Players:Get(i)
        ---@type string
        local class_name = player:GetClass():GetName()
        class_name = string.sub(class_name, 1, -3)
        local character_id
        for i, v in pairs(d_character) do
            if string.endswith(v.fightModelPath, class_name) then
                character_id = i
            end
        end
        local data = {
            character_id = character_id,
            cur_hp = win and math.floor(player:GetHealth()) or math.floor(player:GetMaxHealth()),
        }

        table.insert(characterData, data)
    end

    for i = self.Players:Length() + 1, 3 do 
        table.insert(characterData, {
            character_id = 0,
            cur_hp = 0,
        })
    end
    
    ---@param player BP_PlayerCharacter_Fight_C
    for _, player in pairs(self.Players) do
        
    end

    ---@type UniverseFightData
    local res = {
        character_fight_datas = characterData,
        boat_energy = math.floor(self.Boat.AttributeSet.CurrentSP.CurrentValue),
    }

    return res
end

function M:GameOver()
    LOG_INFO("Over")
    if self.bLuaGameIsOver then return end 
    self.bLuaGameIsOver = true
    -- 通知lua部分战斗结束了
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:CloseTalkUI()
    gameInstance:HideTutorial()

    local ui = gameInstance:GetUMG('UI_Fight')
    if ui then
        ui:ClearUI()
    end
   
    gameInstance.BackFromFight = true
    if gameInstance.fightType == gameInstance.FIGHT_STATE.BOSS then
        gameInstance.bossFightLose = true
    end

    local universeFightData = self:GetUniverseFightData(false)
    -- don't comment, should call parent to do clear all character's init GE
    self.Overridden.GameOver(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:HideUI()
    playerController:DestroyUI()

    if gameInstance.fightType == gameInstance.FIGHT_STATE.DailyCopy then
        self.fightResult = false
        UIManager:GetInstance():RemoveAll()
        UE.UGameplayStatics.SetGamePaused(self, true)
        -- NetworkMessageManager:GetInstance():AddListener("res_complete_daily_level_fight", self)
        -- NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
        -- local msg = { result = false }
        -- Client.send("req_complete_daily_level_fight", msg)
        local ui_settlement = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Daily_Settlement')
        ui_settlement:RefreshUI(self.fightResult, self.changedItemInfos)
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.ChallengeCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy then
        self.fightResult = false
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)
        NetworkMessageManager:GetInstance():AddListener("res_complete_hard_level_fight", self)
        NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
        --获取fightlevel
        local starTab = {}
        for i = 1, 3 do
            --local bStar, _ = self.FightLevel:GetStarIndex(i - 1)
            starTab[i] = true
        end
        local msg = {
            result = false,
            stars = starTab
        }
        HardLevelSystem:GetInstance():ReqCompleteHardLevelFight(msg)
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.BOSSRUSH then
        self.fightResult = false
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)

        local bossId = BossRushController:GetInstance():GetPendingBossFight()
        local difficulty = BossRushController:GetInstance():GetPlayerDifficulty(bossId)
        local levelConfig = BossRushUtils.GetBossConfig(bossId, difficulty)
        local bossName = levelConfig.monsterId

        local hpPortion = self:GetMonsterHpPortion(bossName)

        Client.send(Protos.REQ_COMPLETE_TOTAL_WAR_FIGHT, {
            result = false,
            damage = math.floor(hpPortion * 10000),
            time_remain = 0,
        })
        
        NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_TOTAL_WAR_FIGHT, self)
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.UNIVERSE then
        UIManager:GetInstance():RemoveAll()
        ---@type UI_Fail_Settlement_C
        local failUi = UE.UWidgetBlueprintLibrary.Create(self,
            UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_Daily_Copy/UI_Fail_Settlement.UI_Fail_Settlement_C'))
        UIManager:GetInstance():AddUI(failUi)

        UE.UGameplayStatics.SetGamePaused(self, true)
        failUi:PlayAnimationForward(failUi.vfxIn, 1, false)
        failUi.Btn_Start:SetIsEnabled(false)
        failUi.cost_3:SetVisibility(UE.ESlateVisibility.Hidden)
        failUi.cost_2:SetVisibility(UE.ESlateVisibility.Hidden)
        failUi.Btn_Purchase_1.OnClicked:Add(failUi, function()
            failUi:PlayAnimationForward(failUi.vfxExit, 1, false)
            gameInstance:LoadBackLevel()
        end)
        MessageManager:GetInstance():Broadcast(SrpgController.FightOver, SrpgController.FightResult.Lose, universeFightData)
    else
        local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
        if gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            gameInstance.fightType = nil
            gameInstance.BackFromFight = true
            if saveGameSpeak.FightStart then
                saveGameSpeak.FightStart = false
                saveGameSpeak.FightFinished = true
                saveGameSpeak.FightResult = false
                gameInstance:SaveSaveGameSpeak()
                UIManager:GetInstance():RemoveAll()
                UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Fail_L')
                UE.UGameplayStatics.SetGamePaused(self, true)
            end
        else
            gameInstance:LoadBackLevel()
        end
    end
end

function M:GamePass()
    LOG_INFO("Pass")
    if self.bLuaGameIsOver then return end 
    self.bLuaGameIsOver = true

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:CloseTalkUI()
    gameInstance:HideTutorial()
  
    
    local ui = gameInstance:GetUMG('UI_Fight')
    if ui then
        ui:ClearUI()
    end

    gameInstance.BackFromFight = true
    if gameInstance.fightType == gameInstance.FIGHT_STATE.BOSS then
        gameInstance.bossFightLose = false
    end

    local universeFightData = self:GetUniverseFightData(true)
    if gameInstance.fightType == gameInstance.FIGHT_STATE.UNIVERSE then
        MessageManager:GetInstance():Broadcast(SrpgController.FightOver, SrpgController.FightResult.Win, universeFightData)
    end
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    if gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        gameInstance.fightType = nil
        gameInstance.BackFromFight = true
        if saveGameSpeak.FightStart then
            saveGameSpeak.FightStart = false
            saveGameSpeak.FightFinished = true
            saveGameSpeak.FightResult = true
            gameInstance:SaveSaveGameSpeak()
            if gameInstance.fightMsg and gameInstance.fightMsg.fight_level_id then
                MessageManager:GetInstance():Broadcast("OnMsg_Complete_TempFight", gameInstance.fightMsg.fight_level_id)
            end
        end
    end
    self.Overridden.GamePass(self)
end

function M:OnGamePassFinished()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if gameInstance.fightType == gameInstance.FIGHT_STATE.DailyCopy then
        self.fightResult = true
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)
        NetworkMessageManager:GetInstance():AddListener("res_complete_daily_level_fight", self)
        NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
        local msg = { result = true }
        Client.send("req_complete_daily_level_fight", msg)
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.ChallengeCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy then
        self.fightResult = true
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)
        NetworkMessageManager:GetInstance():AddListener("res_complete_hard_level_fight", self)
        NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
        --获取fightlevel
        local starTab = {}
        if self.FightLevel then
            for i = 1, 3 do
                local bStar, _ = self.FightLevel:GetStarIndex(i - 1)
                starTab[i] = bStar
            end
        end
        local msg = {
            result = true,
            stars = starTab
        }
        HardLevelSystem:GetInstance():ReqCompleteHardLevelFight(msg)
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.BOSSRUSH then
        self.fightResult = true
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)
        Client.send(Protos.REQ_COMPLETE_TOTAL_WAR_FIGHT, {
            result = true,
            damage = 10000,
            time_remain = math.floor((self.FightTime / 300) * 10000),
        })

        local bossId = BossRushController:GetInstance():GetPendingBossFight()
        local difficulty, lastTimePassed = BossRushUtils.GetScoreDifficulty(BossRushController:GetInstance():GetBossScore(bossId))
        local maxDifficulty = BossRushController:GetInstance():GetBossMaxDifficulty(bossId)
        NetworkMessageManager:GetInstance():AddListener(Protos.RES_COMPLETE_TOTAL_WAR_FIGHT, self)
        -- 如果上次没通关最高难度 这次有首通奖励
        if difficulty < maxDifficulty or not lastTimePassed then
            NetworkMessageManager:GetInstance():AddListener("ntf_item_info", self)
        end
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        ---@type UI_Success_C
        local ui = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_Daily_Copy/UI_Success.UI_Success_C'))
        UIManager:GetInstance():AddUI(ui)

        ui.AnimationEnd:Add(ui, function()
            gameInstance:LoadBackLevel()
        end)

        ui:PlayAnimationForward(ui.start, 1, false)
    else
        if gameInstance.fightType == gameInstance.FIGHT_STATE.UNIVERSE and not SrpgController:GetInstance():IsSpecificMap() then
            QuestSystem:GetInstance():AddMissionRecord(UIUtils.EOpenNeedType.FightCountInUniverse)
        end
        gameInstance:LoadBackLevel()
    end
end

function M:ntf_item_info(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg and parsed_msg.ntf_item_info and parsed_msg.ntf_item_info.changed_item_infos then
            self.changedItemInfos = {}
            self.changedItemInfos = parsed_msg.ntf_item_info.changed_item_infos
        end
    end
end

---@param parsed_msg ResCompleteTotalWarFightMessage
M[Protos.RES_COMPLETE_TOTAL_WAR_FIGHT] = function(self, result, msgId, parsed_msg)
    local bossId = BossRushController:GetInstance():GetPendingBossFight()
    local lastScore = BossRushController:GetInstance():GetBossScore(bossId)
    local difficulty, lastTimePassed = BossRushUtils.GetScoreDifficulty(lastScore)
    local maxDifficulty = BossRushController:GetInstance():GetBossMaxDifficulty(bossId)
    local gotItem = difficulty < maxDifficulty or not lastTimePassed

    BossRushController:GetInstance():OnCompleteTotalWarFight(result, msgId, parsed_msg)

    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_COMPLETE_TOTAL_WAR_FIGHT, self)

    if gotItem then
        NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    end

    if not self.fightResult then
        ---@type UI_Fail_BossRush_C
        local ui = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_Fail_BossRush.UI_Fail_BossRush_C'))
        UIManager:GetInstance():AddUI(ui)

        local score = parsed_msg.res_complete_total_war_fight.new_score
        ui.Score:SetText(BossRushUtils.FormatRichText(score))
        ui.NewRecord:SetVisibility(score > lastScore and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)

        ui.Exit.OnClicked:Add(ui.Exit, function()
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:LoadBackLevel()
        end)
    else
        ---@type UI_Success_BossRush_C
        local ui = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_Success_BossRush.UI_Success_BossRush_C'))
        UIManager:GetInstance():AddUI(ui)

        local score = parsed_msg.res_complete_total_war_fight.new_score
        ui.Score:SetText(BossRushUtils.FormatRichText(score))
        ui.NewRecord:SetVisibility(score > lastScore and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)

        if gotItem then
            if self.changedItemInfos then
                for _, itemInfo in ipairs(self.changedItemInfos) do
                    local item = UIUtils.CreateItem(self, itemInfo.item_id, itemInfo.count)

                    ui.ItemList:AddChild(item)
                end
            else
                gotItem = false
            end
        end

        ui.Item:SetVisibility(gotItem and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Collapsed)
        ui.Exit.OnClicked:Add(ui.Exit, function()
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:LoadBackLevel()
        end)

        ui:PlayAnimationForward(ui.start, 1, false)
    end
end

function M:res_complete_daily_level_fight(result, msgId, parsed_msg)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance then
        local ui = gameInstance:GetUMG('UI_StreamLoading')
        if ui then
            UIManager:GetInstance():RemoveUI(ui)
        end
    end

    NetworkMessageManager:GetInstance():RemoveListener("res_complete_daily_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    if result == 0 then
        UIManager:GetInstance():RemoveAll()
        UE.UGameplayStatics.SetGamePaused(self, true)
        local ui_settlement = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Daily_Settlement')
        ui_settlement:RefreshUI(self.fightResult, self.changedItemInfos)
        if self.fightResult then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            table.insert(BackpackSystem:GetInstance().PlayerInfo.daily_level_id_passed, gameInstance.fightMsg.fight_level_id)
        end
        QuestSystem:GetInstance():AddMissionRecord(UIUtils.EOpenNeedType.DailyCopyCount)
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
        gameInstance.fightCanBack = false
        gameInstance:LoadBackLevel()
    end
end

function M:res_complete_hard_level_fight(result, msgId, parsed_msg)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance then
        local ui = gameInstance:GetUMG('UI_StreamLoading')
        if ui then
            UIManager:GetInstance():RemoveUI(ui)
        end
    end
   
    NetworkMessageManager:GetInstance():RemoveListener("res_complete_hard_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener("ntf_item_info", self)
    if result == 0 then
        -- local widget_class = UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_Challenge_Copy/UI_ChallengeFightResult.UI_ChallengeFightResult_C')
        -- local umg = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local umg = gameInstance:AddUMG('UI_ChallengeFightResult')
        if umg then
            umg:RefreshUI(self.fightResult, self.changedItemInfos)
            -- umg:AddToViewport()
        end
        if gameInstance.fightMsg and gameInstance.fightMsg.fight_level_id then
            if self.fightResult then
                MessageManager:GetInstance():Broadcast("OnMsg_Complete_TempFight", gameInstance.fightMsg.fight_level_id)
            end
        end
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.fightType = gameInstance.FIGHT_STATE.WAITING
        gameInstance.BackFromFight = true
        gameInstance.ToCityFromFightArgString = 'UI_Challenge_Copy'
        gameInstance.fightCanBack = false
        gameInstance:LoadBackLevel()
    end
end

function M:OnEnemySpawned(Enemy)
    if not Enemy then
        LOG_ERROR_TRACKBACK("Enemy is nil")
        return
    end
    ---@type BP_Enemy_Indicator_C
    local enemyIndicator = self:GetWorld():SpawnActor(M.EnemyIndicatorClass,
        self.Player:GetTransform(),
        UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
        self, self)

    enemyIndicator:SetUp(self.Player, Enemy)

    self.enemyIndicators[Enemy] = enemyIndicator
end

function M:OnEnemyDead(Enemy)
    local enemyIndicator = self.enemyIndicators[Enemy]
    if enemyIndicator then
        self.enemyIndicators[Enemy] = nil
        enemyIndicator:K2_DestroyActor()
    end
end

function M:ToggleEnemyIndicators(IsOn)
    for _, indicator in pairs(self.enemyIndicators) do
        indicator:SetHidden(not IsOn)
    end
end

function M:OnPlayerChanged()
    for _, enemyIndicator in pairs(self.enemyIndicators) do
        enemyIndicator.player = self.Player

        enemyIndicator:K2_AttachToActor(self.player, "",
            UE.EAttachmentRule.KeepRelative,
            UE.EAttachmentRule.KeepRelative,
            UE.EAttachmentRule.KeepRelative,
            false)
    end
end

function M:GetUniverseMainPos()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if not gameInstance.account_id then
        return nil
    end
    if not UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Universe_" .. gameInstance.account_id, 0) then
        return nil
    end
    ---@type SG_SaveGame_Universe_C
    local gameSave = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_Universe_" .. gameInstance.account_id, 0)
    return gameSave.MainPosId
end

function M:SpawnMainPos()
    local DEBUG_OFFSET_Z = 300000
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    LOG_INFO("fight state", gameInstance.fightType)
    if not (gameInstance.fightType == gameInstance.FIGHT_STATE.EXPLORE or
            gameInstance.fightType == gameInstance.FIGHT_STATE.BOSS or
            gameInstance.fightType == gameInstance.FIGHT_STATE.EVENT or
            gameInstance.fightType == gameInstance.FIGHT_STATE.MAINPOS) then
        self.KillZoneOffset = UE.FVector(0, 0, DEBUG_OFFSET_Z)
        return
    end

    local main_pos_id_str = self:GetUniverseMainPos()
    if not main_pos_id_str then
        LOG_WARN("main_pos_id_str not found")
        self.KillZoneOffset = UE.FVector(0, 0, DEBUG_OFFSET_Z)
        return
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local mainPosInfos = gameInstance.mainPosInfos
    if not mainPosInfos then
        LOG_WARN("mainPosInfos not found")
        self.KillZoneOffset = UE.FVector(0, 0, DEBUG_OFFSET_Z)
        return
    end
    local main_pos_info = mainPosInfos[main_pos_id_str]
    if not main_pos_info then
        LOG_WARN("main_pos_info not found, main_pos_id_str=" .. main_pos_id_str)
        self.KillZoneOffset = UE.FVector(0, 0, DEBUG_OFFSET_Z)
        return
    end
    local postprocess_volumes = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.APostProcessVolume)
    local volume_num = postprocess_volumes:Length()
    local universe_postProcess = nil
    if volume_num > 0 then
        for i = 1, volume_num do
            local name = UE.UKismetSystemLibrary.GetDisplayName(postprocess_volumes[i])
            if name == "PostProcessVolume" then
                universe_postProcess = postprocess_volumes[i]
                break
            end
        end
    end
    if not universe_postProcess then
        LOG_WARN("universe_postProcess not found")
        self.KillZoneOffset = UE.FVector(0, 0, DEBUG_OFFSET_Z)
        return
    end
    local center_location = universe_postProcess:K2_GetActorLocation()
    local volume_height = universe_postProcess:GetActorScale3D().Z * 200

    local offset = hex_grid.hex_to_pixel(main_pos_info.hex, 100000)
    local planet_id = SrpgController:GetInstance():GetPlanetId()
    local z_offset = volume_height * (Database.Query("d_srpg_universe", planet_id).mapZOffset - 0.5)
    local pos = UE.FVector(center_location.X + offset.x, center_location.Y + offset.y, center_location.Z + z_offset)
    local BP_MainPos = UE.UClass.Load(
        "/Game/_Game/Blueprints/Levels/BP_UniverseMainPos_Common.BP_UniverseMainPos_Common_C")
    local trans = UE.UKismetMathLibrary.MakeTransform(pos, UE.FRotator(0, 0, 0), UE.FVector(1, 1, 1))
    local mainPos = self:GetWorld():SpawnActor(BP_MainPos, trans, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self,
        self)
    local hex_id = string.format("%d,%d", main_pos_info.hex.r, main_pos_info.hex.q)
    mainPos:Init(main_pos_info.index - 1, main_pos_info.main_pos_id, hex_id, true)
    local new_fight_kill_zone_location = mainPos.ViceMode.Fight1Map_KillZone:K2_GetComponentLocation()

    local SO_FightKillZone = UE.UClass.Load("/Game/_Game/Blueprints/SceneObjects/SO_FightKillZone.SO_FightKillZone_C")
    local fight_kill_zone = UE.UGameplayStatics.GetActorOfClass(self, SO_FightKillZone)
    local kill_zone_offset = new_fight_kill_zone_location - fight_kill_zone:K2_GetActorLocation()
    if LOG_LEVEL == 0 then
        LOG_DEBUG("kill_zone_offset", tostring(kill_zone_offset))
    end
    self.KillZoneOffset = kill_zone_offset
    self.KillZoneOffset.Z = self.KillZoneOffset.Z + DEBUG_OFFSET_Z

    local BP_PlayerStart = UE.UClass.Load("/Game/_Game/Blueprints/Game/BP_PlayerStart.BP_PlayerStart_C")
    UE.UGameplayStatics.GetActorOfClass(self, BP_PlayerStart):K2_AddActorWorldOffset(kill_zone_offset, false, nil, false)
    fight_kill_zone:K2_AddActorWorldOffset(kill_zone_offset, false, nil, false)
    -- UE.UGameplayStatics.GetActorOfClass(self, UE.APostProcessVolume):K2_AddActorWorldOffset(kill_zone_offset, false, nil, false)
end

local func_context = {}

local function clear_func_context()
    tableex.clear(func_context)
end

local function traceback(err)
    LOG_ERROR(err .. "\n" .. debug.traceback())
end

function M:call_func(str, condition_index, card_id, card_upgrade_id, card_upgrade_times, ...)
    if not SrpgController:GetInstance():GetCurrentFightInfo() then
        return {}
    end
    local universe_info = SrpgController:GetInstance():GetUniverseInfo()
    clear_func_context()
    func_context.self = self
    local func_str = string.format([[
    return function(
        extra_args,
        universe_info,
        d_srpg_card_base,
        d_srpg_curio_base,
        condition_index,
        card_id,
        card_upgrade_id,
        card_upgrade_times,
        random
    )
        %s
    end
]], str)
    if LOG_LEVEL == 0 then
        LOG_DEBUG("func call args condition_index=%s, card_id=%s, card_upgrade_id=%s, card_upgrade_times=%s",
        tostring(condition_index), tostring(card_id), tostring(card_upgrade_id), tostring(card_upgrade_times))
        LOG_DEBUG(func_str)
    end
    local func, err = load(func_str)
    if not func then
        LOG_ERROR("load func error: %s, err: %s", str, err)
        return false
    end
    local ret, func = xpcall(func, traceback)
    if not ret then
        LOG_ERROR("get func error: %s", str)
        return false
    end
    local extra_args = table.pack(...)
    local args = {
        extra_args,
        tableex.read_only(universe_info),
        tableex.read_only(d_srpg_card_base),
        tableex.read_only(d_srpg_curio_base),
        condition_index,
        card_id,
        card_upgrade_id,
        card_upgrade_times,
        M.func_random
    }
    local rets = table.pack(xpcall(func, traceback, table.unpack(args)))
    if not rets[1] then
        LOG_ERROR("call func error: %s", str)
        return false
    end
    if LOG_LEVEL == 0 then
        LOG_DEBUG("func call ret = %s", table.dump(rets))
    end
    return table.unpack(rets)
end

M.func_random = function(...)
    return math.random(...)
end

function M:GetSrpgFightLevelId()
    if SrpgController:GetInstance():IsUniverseExist() then
        local fightInfo = SrpgController:GetInstance():GetCurrentFightInfo()

        if fightInfo then
            return fightInfo.fight_level_id
        end
    end

    return -1
end

function M:GetSrpgMonsterLevel()
    local difficultyConfig = Database.Query("d_srpg_map_level", SrpgController:GetInstance():GetDifficulty())

    return difficultyConfig.baseLevel + SrpgController:GetInstance():GetStep() * difficultyConfig.levelUp
end

function M:get_fight_level_id()
    local currentFightInfo = SrpgController:GetInstance():GetCurrentFightInfo()
    if currentFightInfo then
        return currentFightInfo.fight_level_id
    else
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        return gameInstance.testLevelId
    end
end

function M:CheckCardEffectCondition(ConditionIndex)
    if not SrpgController:GetInstance():GetCurrentFightInfo() then
        return {}
    end
    local card_effects = {}
    self.card_effects = card_effects
    local cards = SrpgController:GetInstance():GetAllPlacedCards()
    for _, card in ipairs(cards) do
        local card_id = card.card_id
        local card_upgrade_times = card.upgrade_times
        local card_data = d_srpg_card_base[card_id]
        local card_effect_ids = card_data.effectsId
        for _, card_effect_id in ipairs(card_effect_ids) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, card_id, nil,
                card_upgrade_times)
            if isok and ret then
                local card_effect = {}
                card_effect.card_effect_id = card_effect_id
                card_effect.card_id = card_id
                table.insert(card_effects, card_effect)
            end
        end
    end
    local curios = SrpgController:GetInstance():GetCurios()
    for _, curio in ipairs(curios) do
        local curioData = d_srpg_curio_base[curio]
        local card_effect_ids = curioData.effectsId
        for _, card_effect_id in ipairs(card_effect_ids) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, nil, curio)
            if isok and ret then
                local card_effect = {}
                card_effect.card_effect_id = card_effect_id
                card_effect.card_upgrade_id = curio
                table.insert(card_effects, card_effect)
            end
        end
    end
    local universe_data = d_srpg_universe[SrpgController:GetInstance():GetPlanetId()]
    for _, card_effect_id in ipairs(universe_data.effectFightId) do
        local card_effect_data = d_srpg_effect_fight[card_effect_id]
        local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, 0, nil, 0)
        if isok and ret then
            local card_effect = {}
            card_effect.card_effect_id = card_effect_id
            card_effect.card_id = 0
            table.insert(card_effects, card_effect)
        end
    end
    local fight_level_id = self:get_fight_level_id()
    local level_data = Database.Query("d_srpg_level_base", fight_level_id)
    if level_data then
        for _, card_effect_id in ipairs(level_data.effectFightId) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, 0, nil, 0)
            if isok and ret then
                local card_effect = {}
                card_effect.card_effect_id = card_effect_id
                card_effect.card_id = 0
                table.insert(card_effects, card_effect)
            end
        end
    end
    
    -- for _, forever_buff_info in ipairs(universe_info.forever_buff_infos) do
    --     local buff_data = d_srpg_effect_buff[forever_buff_info.buff_id]
    --     for _, card_effect_id in ipairs(buff_data.baseBattleEffect) do
    --         local card_effect_data = d_srpg_effect_fight[card_effect_id]
    --         local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, 0, nil, 0)
    --         if isok and ret then
    --             local card_effect = {}
    --             card_effect.card_effect_id = card_effect_id
    --             card_effect.card_id = 0
    --             table.insert(card_effects, card_effect)
    --         end
    --     end
    -- end
    -- for _, realtime_buff_info in ipairs(universe_info.realtime_buff_infos) do
    --     local temp_buff_data = d_srpg_temp_buff[realtime_buff_info.buff_id]
    --     for _, buff_id in ipairs(temp_buff_data.effectFightID) do
    --         local card_effect_data = d_srpg_effect_fight[buff_id]
    --         local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, 0, nil, 0)
    --         if isok and ret then
    --             local card_effect = {}
    --             card_effect.card_effect_id = buff_id
    --             card_effect.card_id = 0
    --             table.insert(card_effects, card_effect)
    --         end
    --     end
    -- end
    -- for _, mission_info in ipairs(universe_info.mission_infos) do
    --     local temp_buff_data = d_srpg_mission[mission_info.mission_id]
    --     for _, buff_id in ipairs(temp_buff_data.effectFightID) do
    --         local card_effect_data = d_srpg_effect_fight[buff_id]
    --         local isok, ret = self:call_func(card_effect_data.triggerScript, ConditionIndex, 0, nil, 0)
    --         if isok and ret then
    --             local card_effect = {}
    --             card_effect.card_effect_id = buff_id
    --             card_effect.card_id = 0
    --             table.insert(card_effects, card_effect)
    --         end
    --     end
    -- end

    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.testFightMap then
        for key, value in pairs(FightTestConfig.extraEffects) do
            table.insert(card_effects, value)
        end
    end

    table.sort(card_effects, function(a, b)
        local card_effect_data_a = d_srpg_effect_fight[a.card_effect_id]
        local card_effect_data_b = d_srpg_effect_fight[b.card_effect_id]
        return card_effect_data_a.order < card_effect_data_b.order
    end)
    local ret = {}
    for _, v in ipairs(card_effects) do
        table.insert(ret, v.card_effect_id)
    end
    return ret
end

function M:GetCardEffectArguments(ConditionIndex, CardEffectIndex)
    if not SrpgController:GetInstance():GetCurrentFightInfo() then
        return {}, {}
    end
    local card_effect = self.card_effects[CardEffectIndex + 1]
    if card_effect then
        local card_effect_id = card_effect.card_effect_id
        local card_effect_data = d_srpg_effect_fight[card_effect_id]
        local card_id = card_effect.card_id
        local card_upgrade_times
        if card_id then
            card_upgrade_times = SrpgController:GetInstance():GetCardUpgradeTimes(card_id)
        end
        local rets = table.pack(self:call_func(card_effect_data.effectsScript, ConditionIndex, card_id,
            card_effect.card_effect_id, card_upgrade_times))
        if rets[1] then
            table.remove(rets, 1)
            if #rets ~= 2 then
                LOG_ERROR("invalid rets", card_effect_data.effectsScript, ConditionIndex, card_id,
                card_effect.card_effect_id, card_upgrade_times)
            else
                local fine = true
                for _, v in ipairs(rets) do
                    if type(v) ~= "table" then
                        LOG_ERROR("arg is not table", card_effect_data.effectsScript, ConditionIndex, card_id,
                        card_effect.card_effect_id, card_upgrade_times)
                        fine = false
                        break
                    end
                    for _, vv in ipairs(v) do
                        local n = tonumber(vv)
                        if not n then
                            LOG_ERROR("arg is not number", card_effect_data.effectsScript, ConditionIndex, card_id,
                            card_effect.card_effect_id, card_upgrade_times)
                            fine = false
                            break
                        end
                    end
                    if not fine then
                        break
                    end
                end
                if fine then
                    return table.unpack(rets)
                end
            end
        end
    end
   
    return {}, {}
end

function M:GetUniverseTurn()
    return SrpgController:GetInstance():GetTurn() or 0
end

function M:IsDanDanVisible()
    if not SrpgController:GetInstance():GetCurrentFightInfo() then
        return false
    end
    local card_effects = {}
    self.card_effects = card_effects
    local cards = SrpgController:GetInstance():GetAllPlacedCards()
    for _, card in ipairs(cards) do
        local card_data = d_srpg_card_base[card.card_id]
        local card_effect_ids = card_data.effectsId
        for _, card_effect_id in ipairs(card_effect_ids) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            if card_effect_data.showModel == 1 then
                return true
            end
        end
    end
    local curios = SrpgController:GetInstance():GetCurios()
    for _, curio in ipairs(curios) do
        local curioData = d_srpg_curio_base[curio]
        local card_effect_ids = curioData.effectsId
        for _, card_effect_id in ipairs(card_effect_ids) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            if card_effect_data.showModel == 1 then
                return true
            end
        end
    end
    local universe_data = d_srpg_universe[SrpgController:GetInstance():GetPlanetId()]
    for _, card_effect_id in ipairs(universe_data.effectFightId) do
        local card_effect_data = d_srpg_effect_fight[card_effect_id]
        if card_effect_data.showModel == 1 then
            return true
        end
    end
    local fight_level_id = self:get_fight_level_id()
    local level_data = Database.Query("d_srpg_level_base", fight_level_id)
    if level_data then
        for _, card_effect_id in ipairs(level_data.effectFightId) do
            local card_effect_data = d_srpg_effect_fight[card_effect_id]
            if card_effect_data.showModel == 1 then
                return true
            end
        end
    end
    
    return false
end

function M:GetPlayerByTeamIndex(index)
    local playerId = self.PlayerIndex:Get(index)
    if playerId > 0 then
        for idx, newId in ipairs(self.PlayerIds) do 
            if playerId == newId then
                return self.Players[idx]
            end 
        end
    end
    return nil
end

return M

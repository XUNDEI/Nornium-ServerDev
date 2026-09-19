local Database = require("_Game.Utils.Database")
local hex_grid = require "Helper.hex_grid"
local UniverseUtils = require "_Game.Utils.UniverseUtils"
local astar = require("Helper.astar")

---@class SrpgModel
---@field resources table<number, number>
local SrpgModel = BaseClass("SrpgModel")

local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()

SrpgModel.ResourceChanged = "SrpgController.ResourceChanged"
SrpgModel.HpChanged = "SrpgController.HpChanged"
SrpgModel.HpDepleted = "SrpgModel.HpDepleted"
SrpgModel.BoatEnergyChanged = "SrpgModel.BoatEnergyChanged"

SrpgModel.BossMoved = "SrpgModel.BossMoved"
SrpgModel.BossShowUp = "SrpgModel.BossShowUp"

SrpgModel.GetDefiniteBuff = "SrpgModel.GetDefiniteBuff"
SrpgModel.BuffExpired = "SrpgModel.BuffExpired"

SrpgModel.TurnEvents = {
    FightEnd = 1,
    ShowItems = 2,
    GameEnd = 3,
    BossShowUp = 4,
    BossMoved = 5,
    BossArrived = 6,
    ShipMove = 7,
    ResourceChange = 8,
    ShowStory = 9,
    ShowCard = 10,
    ShowCurio = 11,
    ReplaceCard = 12,
    SelectCard = 13,
    SelectCurio = 14,
    Event = 15,
    NormalFight = 16,
    BossFight = 17,
    OpenShop = 18,
}

SrpgModel.AttachType = {
    Shop = "main_pos_shop_info",
    Card = "main_pos_card_pos_info",
    Option = "main_pos_option_info",
}

SrpgModel.EndReason = {
    Lose = 1,
    Clear = 2,
    Abort = 3,
}

---@class Event
---@field type number @同时也是优先级
---@field info talbe

function SrpgModel:__init()
    self.resources = {}
    ---@type number
    ---实际上是击破了几个boss
    self.turn = 0
    ---@type number
    ---实际上是探索了几步
    self.step = 0
    self.curHp = 0

    self.difficulty = 0
    self.mainPlanetId = 0
    self.mapId = 0
    self.mapType = 0

    ---@type MainPosInfo[]
    self.mainPosInfo = {}
    self.lines = {}

    self.aStarNodes = {}
    self.bossLines = {}

    self.bossConfigId = 0
    ---@type BossInfo[]
    self.bossInfo = {}
    ---@type FightInfo[]
    self.fightInfo = {}

    ---@type RealtimeUniverseBuffInfo[]
    self.definiteBuffs = {}
    self.infiniteBuffs = {}
    self.infiniteFightBuffs = {}

    ---@type uint32[]
    self.cards = {}
    ---@type uint32[]
    self.exceededCards = {}

    ---@type number[]
    self.curios = {}
    ---@type CardsForSelect[]
    self.cardsForSelect = {}
    ---@type CuriosForSelect[]
    self.curiosForSelect = {}

    ---@type EventInfo[]
    ---服务器的事件
    self.eventInfo = {}

    ---@type MissionInfo[]
    self.missionInfo = {}

    ---@type CharacterFightData[]
    self.characterFightData = {}
    self.boatEnergy = 0
    self.characterChangeTimes = 0

    ---@type Event[]
    ---本地的事件
    self.pendingEvents = {}

    ---@type Hex
    self.baseHex = nil
    ---@type Hex
    self.playerHex = nil

    self.running = false
    self.endReason = nil

    self.triggerId = 0
end

---@param resUniverse ResUniverse | ResNewUniverse | ResNewUniverseSpecific
---@param isNewUniverse boolean
function SrpgModel:Init(resUniverse, isNewUniverse)
    if resUniverse and resUniverse.universe_info then
        self.universeInfo = resUniverse.universe_info
        self.resources = resUniverse.universe_info.res_value
        self.turn = resUniverse.universe_info.turn
        self.step = resUniverse.universe_info.step
        self.curHp = resUniverse.universe_info.cur_hp

        self.difficulty = resUniverse.universe_info.difficulty_value
        self.mainPlanetId = resUniverse.universe_info.main_planet_id
        self.mapId = resUniverse.universe_info.map_id
        self.specificId = resUniverse.universe_info.specific_id

        self.mapConfig  = Database.Query("d_srpg_map_base", self.mapId)
        self.mapType = self.mapConfig.mapType

        self.mainPosInfo = resUniverse.universe_info.main_pos_infos

        self.bossConfigId = resUniverse.universe_info.boss_id
        self.bossInfo = resUniverse.universe_info.boss_infos

        self.fightInfo = resUniverse.universe_info.fight_infos

        self.infiniteBuffs = resUniverse.universe_info.forever_buff_ids
        self.infiniteFightBuffs = resUniverse.universe_info.forever_fight_buff_ids
        self.definiteBuffs = resUniverse.universe_info.realtime_buff_infos
        
        self.cards = resUniverse.universe_info.card_ids
        self.exceededCards = resUniverse.universe_info.missed_card_ids
        self.curios = resUniverse.universe_info.curio_ids
        self.cardsForSelect = resUniverse.universe_info.cards_for_selects
        self.curiosForSelect = resUniverse.universe_info.curios_for_selects

        self.eventInfo = resUniverse.universe_info.event_infos

        self.missionInfo = resUniverse.universe_info.mission_infos

        self.characterFightData = resUniverse.universe_info.universe_fight_data.character_fight_datas
        self.boatEnergy = resUniverse.universe_info.universe_fight_data.boat_energy
        self.characterChangeTimes = resUniverse.universe_info.universe_fight_data.character_changed_times

        self.pendingEvents = {}

        self.baseHex = resUniverse.universe_info.base_hex

        self.running = true
        self.endReason = nil

        if isNewUniverse then
            self.saveGame.RecordPlayer = false
            self.saveGame.RecordPlayerInBridge = false
            self.saveGame.MainPosOffset:Clear()

            self.playerHex = self.baseHex
            self.saveGame.MainPosId = hex_grid.to_string(self.playerHex)
        else
            self.playerHex = hex_grid.from_string(self.saveGame.MainPosId)
        end
        
        self:InitLines()
        self:UpdateBossLines()
    end
end


local rOffsets = {
    { q = 1, r = -1 },
    { q = 1, r = 0 },
    { q = 0, r = 1 },
}

local lOffsets = {
    { q = -1, r = 1 },
    { q = -1, r = 0 },
    { q = 0, r = -1 },
}

---后续新增坐标
function SrpgModel:UpdateLines(mainPosInfo)
    for _, rOffset in pairs(rOffsets) do
        local neighbourHex = hex_grid.hex_add(mainPosInfo.hex, rOffset)
        local neighbourMainPosInfo = self:GetMainPos(neighbourHex)
        local line = { mainPosInfo.hex, neighbourHex }

        if neighbourMainPosInfo then
            if UniverseUtils.IsReachable(mainPosInfo) and UniverseUtils.IsReachable(neighbourMainPosInfo) then
                if not table.indexof(self.lines, line, nil, UniverseUtils.LineEqual) then
                    table.insert(self.lines, line)
                end
            else
                local index = table.indexof(self.lines, line, nil, UniverseUtils.LineEqual)
                if index then
                    table.remove(self.lines, index)
                end
            end
        end
    end
    for _, lOffset in pairs(lOffsets) do
        local neighbourHex = hex_grid.hex_add(mainPosInfo.hex, lOffset)
        local neighbourMainPosInfo = self:GetMainPos(neighbourHex)
        local line = { neighbourHex, mainPosInfo.hex }

        if neighbourMainPosInfo then
            if UniverseUtils.IsReachable(mainPosInfo) and UniverseUtils.IsReachable(neighbourMainPosInfo) then
                if not table.indexof(self.lines, line, nil, UniverseUtils.LineEqual) then
                    table.insert(self.lines, line)
                end
            else
                local index = table.indexof(self.lines, line, nil, UniverseUtils.LineEqual)
                if index then
                    table.remove(self.lines, index)
                end
            end
        end
    end
end

function SrpgModel:InitAStarNodes()
    self.aStarNodes = {}
    for i, mainPosInfo in ipairs(self.mainPosInfo) do
        if UniverseUtils.IsReachable(mainPosInfo) then
            table.insert(self.aStarNodes, mainPosInfo.hex)
        end
    end
end

function SrpgModel:InitLines()
    for _, mainPosInfo in pairs(self.mainPosInfo) do
        self:UpdateLines(mainPosInfo)
    end
end

function SrpgModel:GetBaseHex()
    return self.baseHex
end

---@param mainPosInfo MainPosInfo
function SrpgModel:AddMainPos(mainPosInfo)
    table.insert(self.mainPosInfo, mainPosInfo)

    self:UpdateLines(mainPosInfo)
end

function SrpgModel:UpdateMainPos(hex, state)
    local mainPosInfo = self:GetMainPos(hex)
    mainPosInfo.state = state

    self:UpdateLines(mainPosInfo)
end

function SrpgModel:GetMainPos(hex)
    for _, mainPosInfo in pairs(self.mainPosInfo) do
        if hex_grid.equal(mainPosInfo.hex, hex) then
            return mainPosInfo
        end
    end
end

---@param saveGame SG_SaveGame_Universe_C
function SrpgModel:LoadSaveGame(saveGame)
    self.saveGame = saveGame
    self.saveGameRef = UnLua.Ref(saveGame)
    self.playerHex = hex_grid.from_string(saveGame.MainPosId)
end

function SrpgModel:ChangeHp(value)
    self.curHp = self.curHp + value

    MessageManager:Broadcast(SrpgModel.HpChanged, value)

    if self.curHp <= 0 then
        MessageManager:Broadcast(SrpgModel.HpDepleted, value)
    end
end

function SrpgModel:SetBoatEnergy(boatEnergy)
    self.boatEnergy = boatEnergy

    MessageManager:Broadcast(SrpgModel.BoatEnergyChanged)
end

function SrpgModel:ChangeBoatEnergy(boatEnergy)
    self.boatEnergy = self.boatEnergy + boatEnergy

    MessageManager:Broadcast(SrpgModel.BoatEnergyChanged, boatEnergy)
end

function SrpgModel:GetUniverseEventInfoByUUID(eventUUID)
    for _, info in pairs(self.eventInfo) do
        if info.event_uuid == eventUUID then
            return info
        end
    end
end

function SrpgModel:RemoveUniverseEvent(eventUUID)
    for i, info in ipairs(self.eventInfo) do
        if info.event_uuid == eventUUID then
            table.remove(self.eventInfo, i)
            return
        end
    end
end

---@param universeFightData UniverseFightData
function SrpgModel:UpdateFightData(universeFightData)
    for _, newData in pairs(universeFightData.character_fight_datas) do
        for _, oldData in pairs(self.characterFightData) do
            if oldData.character_id == newData.character_id then
                oldData.cur_hp = newData.cur_hp
                break
            end
        end
    end

    self:SetBoatEnergy(universeFightData.boat_energy)
end

function SrpgModel:AddOrUpdateFightInfo(newFightInfo)
    for _, fightInfo in pairs(self.fightInfo) do
        if fightInfo.fight_uuid == newFightInfo.fight_uuid then
            fightInfo.fight_state = newFightInfo.fight_state
            fightInfo.fight_level_id = newFightInfo.fight_level_id
            return
        end
    end

    table.insert(self.fightInfo, newFightInfo)
end

---状态为FIGHTING的战斗同时应该只会存在一个
function SrpgModel:GetCurrentFightInfo()
    for _, fightInfo in pairs(self.fightInfo) do
        if fightInfo.fight_state == 1 then
            return fightInfo
        end
    end
end

function SrpgModel:CompleteCurrentFight()
    for i, fightInfo in ipairs(self.fightInfo) do
        if fightInfo.fight_state == 1 then
            table.remove(self.fightInfo, i)
            break
        end
    end
end

function SrpgModel:CompleteCurrentBossFight()
    local fightInfo
    for i, info in ipairs(self.fightInfo) do
        if info.fight_state == 1 then
            fightInfo = info
            table.remove(self.fightInfo, i)
            break
        end
    end

    if fightInfo then
        for i, info in ipairs(self.bossInfo) do
            if info.fight_uuid == fightInfo.fight_uuid then
                table.remove(self.bossInfo, i)
                break
            end
        end
    end

    self:UpdateBossLines()

    self.turn = self.turn + 1
end

function SrpgModel:StopCurrentFight()
    for i, fightInfo in pairs(self.fightInfo) do
        if fightInfo.fight_state == 1 then
            table.remove(self.fightInfo, i)
            break
        end
    end
end

function SrpgModel:GetFightInfoByUUID(fightUUID)
    for _, fightInfo in pairs(self.fightInfo) do
        if fightInfo.fight_uuid == fightUUID then
            return fightInfo
        end
    end
end

---@param fightInfo FightInfo
function SrpgModel:IsBossFight(fightInfo)
    for _, bossInfo in ipairs(self.bossInfo) do
        if bossInfo.fight_uuid == fightInfo.fight_uuid then
            return true
        end
    end

    return false
end

function SrpgModel:AddBossFightInfo(bossIndex, newFightInfo)
    self:AddOrUpdateFightInfo(newFightInfo)

    for _, bossInfo in ipairs(self.bossInfo) do
        if bossInfo.boss_index == bossIndex then
            bossInfo.fight_uuid = newFightInfo.fight_uuid
        end
    end
end

local function IsNeighbour(hexA, hexB)
    return hex_grid.hex_distance(hexA, hexB) == 1
end

---boss行动路径，也就是需要显示特效的路径
function SrpgModel:UpdateBossLines()
    self:InitAStarNodes()
    self.bossLines = {}
    local goal
    for _, hex in ipairs(self.aStarNodes) do
        if hex_grid.equal(self.baseHex, hex) then
            goal = hex
        end
    end
    for _, bossInfo in ipairs(self.bossInfo) do
        local start
        for _, hex in ipairs(self.aStarNodes) do
            if hex_grid.equal(bossInfo.hex, hex) then
                start = hex
            end
        end
        local path = astar.path(start, goal, self.aStarNodes, false, IsNeighbour, function()
            return 1
        end, hex_grid.hex_distance)

        if path then
            for i = 1, #path - 1 do
                local line = { path[i], path[i+1] }
                if not table.indexof(self.bossLines, line, nil, UniverseUtils.LineEqual) then
                    table.insert(self.bossLines, line)
                end
            end
        else
            LOG_WARN("boss ", bossInfo.boss_index, " doesn't have a valid path")
        end
    end
end

---@param bossInfo BossInfo[]
function SrpgModel:UpdateBossInfo(bossInfo)
    local bossConfig = Database.Query("d_srpg_level_boss", self.bossConfigId)
    for i = 1, #bossConfig.path do
        local oldBossInfo
        for _, oldInfo in ipairs(self.bossInfo) do
            if oldInfo.boss_index == i - 1 then
                oldBossInfo = oldInfo
            end
        end

        local newBossInfo
        for _, newInfo in ipairs(bossInfo) do
            if newInfo.boss_index == i - 1 then
                newBossInfo = newInfo
            end
        end

        -- boss出现
        if not oldBossInfo and newBossInfo then
            MessageManager:Broadcast(SrpgModel.BossShowUp, newBossInfo)
        end

        -- boss移动
        if oldBossInfo and newBossInfo then
            MessageManager:Broadcast(SrpgModel.BossMoved, oldBossInfo, newBossInfo)
        end

        -- boss消失
        if oldBossInfo and not newBossInfo then
        end
    end

    self.bossInfo = bossInfo

    self:UpdateBossLines()
end

function SrpgModel:GetBossInfoByUUID(fightUUID)
    for _, bossInfo in pairs(self.bossInfo) do
        if bossInfo.fight_uuid == fightUUID then
            return bossInfo
        end
    end
end

function SrpgModel:GetBossFightInfoByBossIndex(bossIndex)
    local bossInfo
    for _, info in pairs(self.bossInfo) do
        if info.boss_index == bossIndex then
            bossInfo = info
        end
    end

    if bossInfo then
        return self:GetFightInfoByUUID(bossInfo.fight_uuid)
    end
end

---总波次
function SrpgModel:GetBossWaveCount()
    local bossConfig = Database.Query("d_srpg_level_boss", self.bossConfigId)
    return #bossConfig.path
end

---已经刷新的波次数量
function SrpgModel:GetBossCount()
    return self.turn + #self.bossInfo
end

function SrpgModel:AddInfiniteBuff(buffId)
    table.insert(self.infiniteBuffs, { buff_id = buffId })
end

function SrpgModel:AddDefiniteBuff(buffId)
    -- 同类buff只会存在一个
    local newBuff = { buff_id = buffId, elapsed = 0 }

    local newBuffType = Database.Query("d_srpg_temp_buff", buffId).type

    local replaced = false
    for i, buff in ipairs(self.definiteBuffs) do
        local buffType = Database.Query("d_srpg_temp_buff", buff.buff_id).type

        if buffType == newBuffType then
            self.definiteBuffs[i] = newBuff
            replaced = true
            break
        end
    end
    if not replaced then
        table.insert(self.definiteBuffs, newBuff)
    end

    MessageManager:Broadcast(SrpgModel.GetDefiniteBuff, buffId)
end

function SrpgModel:TickBuffs(tickType)
    for _, buff in ipairs(self.definiteBuffs) do
        local buffInfo = Database.Query("d_srpg_temp_buff", buff.buff_id)
        if buffInfo.duration[1] == tickType then
            buff.elapsed = buff.elapsed + 1
        end
    end
end

function SrpgModel:RemoveExpiredBuff()
    for i = #self.definiteBuffs, 1, -1 do
        local buff = Database.Query("d_srpg_temp_buff", self.definiteBuffs[i].buff_id)

        if buff.duration[1] ~= 0 then
            if buff.duration[2] == self.definiteBuffs[i].elapsed then
                MessageManager:Broadcast(SrpgModel.BuffExpired, self.definiteBuffs[i].buff_id)
                table.remove(self.definiteBuffs, i)
            end
        end
    end
end

function SrpgModel:TickTurn()
    self:TickBuffs(1)

    self:RemoveExpiredBuff()

    self.step = self.step + 1
end

function SrpgModel:SetResource(index, value)
    self.resources[index] = value
end

function SrpgModel:ChangeResource(index, value, showNotify)
    self.resources[index] = self.resources[index] + value

    MessageManager:Broadcast(SrpgModel.ResourceChanged, index, value, showNotify)
end

function SrpgModel:GetCardsForSelect(UUID)
    for _, info in pairs(self.cardsForSelect) do
        if info.select_uuid == UUID then
            return info
        end
    end
end

function SrpgModel:GetCuriosForSelect(UUID)
    for _, info in pairs(self.curiosForSelect) do
        if info.select_uuid == UUID then
            return info
        end
    end
end

--单srpg_effect_buff表内的buff的免费刷新次数
function SrpgModel:GetBuffFreeCardRefreshTime(buffId)
    local buffInfo = Database.Query("d_srpg_effect_buff", buffId)
    if buffInfo.buffType == 1 then
        return buffInfo.buffValue[1]
    else
        return 0
    end
end

function SrpgModel:GetFreeCardRefreshTime()
    local res = 0
    for _, buff in ipairs(self.infiniteBuffs) do
        res = res + self:GetBuffFreeCardRefreshTime(buff.buff_id)
    end
    for _, buff in ipairs(self.definiteBuffs) do
        local buffInfo = Database.Query("d_srpg_temp_buff", buff.buff_id)
        for _, buffId in ipairs(buffInfo.effectBuffID) do
            res = res + self:GetBuffFreeCardRefreshTime(buffId)
        end
    end

    return res
end

--单srpg_effect_buff表内的buff的刷新资源变更
function SrpgModel:GetBuffCardRefreshCostModifier(buffId)
    local buffInfo = Database.Query("d_srpg_effect_buff", buffId)
    if buffInfo.buffType == 1 then
        return buffInfo.buffValue[2]
    else
        return 0
    end
end

function SrpgModel:GetCardRefreshCostModifier()
    local res = 0
    for _, buff in ipairs(self.infiniteBuffs) do
        res = res + self:GetBuffCardRefreshCostModifier(buff.buff_id)
    end
    for _, buff in ipairs(self.definiteBuffs) do
        local buffInfo = Database.Query("d_srpg_temp_buff", buff.buff_id)
        for _, buffId in ipairs(buffInfo.effectBuffID) do
            res = res + self:GetBuffCardRefreshCostModifier(buffId)
        end
    end

    return res
end

---@param msg NtfAddCardsForSelect
function SrpgModel:AddCardsForSelect(msg)
    table.insert(self.cardsForSelect, msg.cards_for_select)
end

---@param msg ResCreateChooseCard | ResRefreshChooseCard
function SrpgModel:UpdateCardsForSelect(msg, UUID, isRefresh)
    for key, info in pairs(self.cardsForSelect) do
        if info.select_uuid == UUID then
            self.cardsForSelect[key].card_ids = msg.card_ids
            if isRefresh then
                self.cardsForSelect[key].refresh_times = self.cardsForSelect[key].refresh_times + 1
            end
        end
    end
end

function SrpgModel:AddCard(cardId)
    table.insert(self.cards, cardId)
end

function SrpgModel:AddExceededCard(cardId)
    table.insert(self.exceededCards, cardId)
end

function SrpgModel:AddCards(cardIds)
    for _, id in pairs(cardIds) do
        table.insert(self.cards, id)
    end
end

function SrpgModel:ChooseCard(UUID)
    for i = #self.cardsForSelect, 1, -1 do
        if self.cardsForSelect[i].select_uuid == UUID then
            table.remove(self.cardsForSelect, i)
        end
    end
end

function SrpgModel:AddCurio(curioId)
    table.insert(self.curios, curioId)
end

function SrpgModel:AddCurios(curioIds)
    for _, id in pairs(curioIds) do
        table.insert(self.curios, id)
    end
end

---@param msg NtfAddCuriosForSelect
function SrpgModel:AddCuriosForSelect(msg)
    table.insert(self.curiosForSelect, msg.curios_for_select)
end

---@param msg ResCreateChooseCurio | ResRefreshChooseCurio
function SrpgModel:UpdateCuriosForSelect(msg, UUID, isRefresh)
    for key, info in pairs(self.curiosForSelect) do
        if info.select_uuid == UUID then
            self.curiosForSelect[key].curio_ids = msg.curio_ids
            if isRefresh then
                self.curiosForSelect[key].refresh_times = self.curiosForSelect[key].refresh_times + 1
            end
        end
    end
end

function SrpgModel:ChooseCurio(UUID, curio)
    for i = #self.curiosForSelect, 1, -1 do
        if self.curiosForSelect[i].select_uuid == UUID then
            local curioId = self.curiosForSelect[i].curio_ids[curio]

            table.insert(self.curios, curioId)

            table.remove(self.curiosForSelect, i)

            return curioId
        end
    end
end

---@param event Event
function SrpgModel:AddEvent(event)
    if #self.pendingEvents == 0 then
        table.insert(self.pendingEvents, event)
    else
        local insertPos = #self.pendingEvents + 1
        for i = 1, #self.pendingEvents do
            if self.pendingEvents[i].type > event.type then
                insertPos = i
                break
            end
        end
        table.insert(self.pendingEvents, insertPos, event)
    end
end

function SrpgModel:PopEvent()
    if #self.pendingEvents > 0 then
        local event = table.remove(self.pendingEvents, 1)
        return event
    end
end

function SrpgModel:RemoveEvent(event)
    table.removebyvalue(self.pendingEvents, event)
end

function SrpgModel:PeekEvent()
    if #self.pendingEvents > 0 then
        return self.pendingEvents[1]
    end
end

return SrpgModel

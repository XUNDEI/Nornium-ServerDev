local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local NetworkMessageListener = require("Module.NetworkMessageListener")
local Database = require("_Game.Utils.Database")
local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()
local hex_grid = require "Helper.hex_grid"
local UIUtils = require "_Game.Utils.UIUtils"
local UniverseUtils = require "_Game.Utils.UniverseUtils"

local SrpgModel = require("Module.Srpg.SrpgModel")

local UI_Dialog_Story_C = require "_Game.Blueprints.UI.UI_Dialog_Story_C"
local UI_Tutorial_C = require("_Game.Blueprints.UI.UI_Tutorial.UI_Tutorial_C")
local UI_Dialog_Talk_C = require("_Game.Blueprints.UI.UI_Dialog_Talk_C")

---@class SrpgController : NetworkMessageListener
---@field model SrpgModel
---@field GetInstance fun():SrpgController
local SrpgController = BaseClass("SrpgController", NetworkMessageListener)

SrpgController.FightResult = {
    Lose = 0,
    Win = 1,
    Abort = 2,
}

SrpgController.SpecialDisplay = {
    GameEnd = 1,
    SetAbort = 10,
    SetClear = 11,
    SetLose = 12,
}

SrpgController.EventUpdated = "SrpgController.EventUpdated"

SrpgController.ShipMove = "SrpgController.ShipMove"
SrpgController.ResourceChange = "SrpgController.ResourceChange"
SrpgController.FightEnd = "SrpgController.FightEnd"
SrpgController.BossMove = "SrpgController.BossMove"
SrpgController.BossShowUp = "SrpgController.BossShowUp"
SrpgController.BossArrived = "SrpgController.BossArrived"
SrpgController.UniverseEvent = "SrpgController.UniverseEvent"
SrpgController.NormalFight = "SrpgController.NormalFight"
SrpgController.BossFight = "SrpgController.BossFight"
SrpgController.GameEnd = "SrpgController.GameEnd"
SrpgController.ShowItems = "SrpgController.ShowItems"
SrpgController.StartSelectCard = "SrpgController.StartSelectCard"
SrpgController.UpdateCardSelection = "SrpgController.UpdateCardSelection"
SrpgController.StartSelectCurio = "SrpgController.StartSelectCurio"
SrpgController.UpdateCurioSelection = "SrpgController.UpdateCurioSelection"
SrpgController.CuriosUpdated = "SrpgController.CuriosUpdated"
SrpgController.ReplaceCard = "SrpgController.ReplaceCard"
SrpgController.ShowCard = "SrpgController.ShowCard"
SrpgController.ShowCurio = "SrpgController.ShowCurio"
SrpgController.ShowStory = "SrpgController.ShowStory"
SrpgController.OpenShop = "SrpgController.OpenShop"

SrpgController.AddMapItem = "SrpgController.AddMapItem"
SrpgController.UpdateMapItems = "SrpgController.UpdateMapItems"
SrpgController.UpdateMapLines = "SrpgController.UpdateMapLines"
SrpgController.UpdateMapBounds = "SrpgController.UpdateMapBounds"
SrpgController.TickTurn = "SrpgController.TickTurn"
SrpgController.UpdateUI = "SrpgController.UpdateUI"
SrpgController.GameEnded = "SrpgController.GameEnded"
SrpgController.FightOver = "SrpgController.FightOver"

---{{{protos
SrpgController.__listened_network_messages = {
    Protos.RES_UNIVERSE,
    Protos.RES_NEW_UNIVERSE,
    Protos.RES_NEW_UNIVERSE_SPECIFIC,
    Protos.RES_COMPLETE_UNIVERSE,
    Protos.NTF_UNIVERSE_BOAT_ENERGY,
    Protos.NTF_ADD_FOREVER_BUFF,
    Protos.NTF_ADD_REALTIME_BUFF,
    Protos.NTF_ADD_CARDS_FOR_SELECT,
    Protos.NTF_ADD_CURIOS_FOR_SELECT,
    Protos.NTF_UNIVERSE_INFO,
    Protos.NTF_MAIN_POS_INFO,
    Protos.NTF_MAIN_POS_STATE_CHANGE,
    Protos.NTF_BOSS_INFO,
    Protos.NTF_EVENT_INFO,
    Protos.NTF_MAIN_POS_ADD_ATTACH,
    Protos.NTF_FIGHT_INFO,
    Protos.NTF_UNIVERSE_CLEAR,
    Protos.NTF_ADD_CARD,
    Protos.NTF_ADD_CURIO,
    Protos.NTF_EFFECT_TRIGGER_BEGIN,
    Protos.NTF_EFFECT_TRIGGER_END,
}

---@param self SrpgController
---@param parsed_msg ResUniverseMessage
SrpgController[Protos.RES_UNIVERSE] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.runningEvent = nil

        self.model:Init(parsed_msg.res_universe, false)

        self:UpdatePendingUniverseEvents()
    end
end

---@param self SrpgController
---@param parsed_msg ResNewUniverseMessage
SrpgController[Protos.RES_NEW_UNIVERSE] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.runningEvent = nil

        self.model:Init(parsed_msg.res_new_universe, true)

        self:Save()

        MessageManager:Broadcast(Protos.RES_NEW_UNIVERSE, result, msgId, parsed_msg)
    end
end

---@param self SrpgController
---@param parsed_msg ResNewUniverseSpecificMessage
SrpgController[Protos.RES_NEW_UNIVERSE_SPECIFIC] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.runningEvent = nil

        self.model:Init(parsed_msg.res_new_universe_specific, true)

        self:Save()

        MessageManager:Broadcast(Protos.RES_NEW_UNIVERSE_SPECIFIC, result, msgId, parsed_msg)
    end
end

---@param self SrpgController
---@param parsed_msg ResCompleteUniverseMessage
---可能没用了，因为一定有ntf_universe_clear
SrpgController[Protos.RES_COMPLETE_UNIVERSE] = function(self, result, msgId, parsed_msg)
end

---@param self SrpgController
---@param parsed_msg NtfUniverseBoatEnergyMessage
SrpgController[Protos.NTF_UNIVERSE_BOAT_ENERGY] = function(self, result, msgId, parsed_msg)
    self.model:ChangeBoatEnergy(parsed_msg.ntf_universe_boat_energy.boat_energy)
end

---@param self SrpgController
---@param parsed_msg NtfAddForeverBuffMessage
SrpgController[Protos.NTF_ADD_FOREVER_BUFF] = function(self, result, msgId, parsed_msg)
    for _, buffId in ipairs(parsed_msg.ntf_add_forever_buff.buff_ids) do
        self.model:AddInfiniteBuff(buffId)
    end
end

---@param self SrpgController
---@param parsed_msg NtfAddRealtimeBuffMessage
SrpgController[Protos.NTF_ADD_REALTIME_BUFF] = function(self, result, msgId, parsed_msg)
    for _, buffId in ipairs(parsed_msg.ntf_add_realtime_buff.buff_ids) do
        self.model:AddDefiniteBuff(buffId)
    end
end

---@param self SrpgController
---@param parsed_msg NtfAddCardsForSelectMessage
SrpgController[Protos.NTF_ADD_CARDS_FOR_SELECT] = function(self, result, msgId, parsed_msg)
    self.model:AddCardsForSelect(parsed_msg.ntf_add_cards_for_select)

    self:AddEvent({
        type = SrpgModel.TurnEvents.SelectCard,
        info = {
            UUID = parsed_msg.ntf_add_cards_for_select.cards_for_select.select_uuid
        }
    })
end

---@param self SrpgController
---@param parsed_msg NtfAddCuriosForSelectMessage
SrpgController[Protos.NTF_ADD_CURIOS_FOR_SELECT] = function(self, result, msgId, parsed_msg)
    self.model:AddCuriosForSelect(parsed_msg.ntf_add_curios_for_select)

    self:AddEvent({
        type = SrpgModel.TurnEvents.SelectCurio,
        info = {
            UUID = parsed_msg.ntf_add_curios_for_select.curios_for_select.select_uuid
        }
    })
end

---@param self SrpgController
---@param parsed_msg NtfUniverseInfoMessage
SrpgController[Protos.NTF_UNIVERSE_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        local event = {
            type = SrpgModel.TurnEvents.ResourceChange,
            info = {},
        }

        event.info.hpChange = parsed_msg.ntf_universe_info.cur_hp

        event.info.resourceChange = {}
        for key, value in pairs(parsed_msg.ntf_universe_info.res_value) do
            event.info.resourceChange[key] = value
        end

        self:AddEvent(event)
    end
end

---@param self SrpgController
---@param parsed_msg NtfMainPosInfoMessage
SrpgController[Protos.NTF_MAIN_POS_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        for _, mainPosInfo in pairs(parsed_msg.ntf_main_pos_info.main_pos_infos) do
            self.model:AddMainPos(mainPosInfo)
        end
    end

    MessageManager:Broadcast(SrpgController.AddMapItem, parsed_msg.ntf_main_pos_info.main_pos_infos)
    MessageManager:Broadcast(SrpgController.UpdateMapLines)
    MessageManager:Broadcast(SrpgController.UpdateMapBounds)
end

---@param self SrpgController
---@param parsed_msg NtfMainPosStateChangeMessage
SrpgController[Protos.NTF_MAIN_POS_STATE_CHANGE] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        for _, change in pairs(parsed_msg.ntf_main_pos_state_change.main_pos_state_changes) do
            self.model:UpdateMainPos(change.hex, change.state)
        end

        MessageManager:Broadcast(SrpgController.UpdateMapItems)
        MessageManager:Broadcast(SrpgController.UpdateMapLines)
        MessageManager:Broadcast(SrpgController.UpdateMapBounds)
    end
end

---@param self SrpgController
---@param parsed_msg NtfBossInfoMessage
SrpgController[Protos.NTF_BOSS_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg.ntf_boss_info then
            self:UpdateBossInfo(parsed_msg.ntf_boss_info.boss_infos)

            MessageManager:Broadcast(SrpgController.UpdateUI)
        end
    end
end

---@param self SrpgController
---@param parsed_msg NtfEventInfoMessage
SrpgController[Protos.NTF_EVENT_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg.ntf_event_info then
            self:AddUniverseEventInfo(parsed_msg.ntf_event_info.event_info)

            self:AddEvent({
                type = SrpgModel.TurnEvents.Event,
                info = {
                    eventUUID = parsed_msg.ntf_event_info.event_info.event_uuid
                }
            })
        end
    end
end

---@param self SrpgController
---@param parsed_msg NtfFightInfoMessage
SrpgController[Protos.NTF_FIGHT_INFO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.model:AddOrUpdateFightInfo(parsed_msg.ntf_fight_info.fight_info)

        self:AddEvent({
            type = SrpgModel.TurnEvents.NormalFight,
            info = {
                fightUUID = parsed_msg.ntf_fight_info.fight_info.fight_uuid
            }
        })
    end
end

---@param self SrpgController
---@param parsed_msg NtfMainPosAddAttachMessage
SrpgController[Protos.NTF_MAIN_POS_ADD_ATTACH] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        local mainPos = self:GetMainPosByHex(parsed_msg.ntf_main_pos_add_attach.hex)
        for index, info in pairs(parsed_msg.ntf_main_pos_add_attach.main_pos_attach_infos) do
            table.insert(mainPos.main_pos_attach_infos, info)

            if info.main_pos_attach_extra == SrpgModel.AttachType.Shop then
                self:AddEvent({
                    type = SrpgModel.TurnEvents.OpenShop,
                    info = {
                        attachInfo = info.main_pos_shop_info
                    }
                })
            end
        end
    end
end

---@param self SrpgController
SrpgController[Protos.NTF_UNIVERSE_CLEAR] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        if self:GetEndReason() ~= SrpgModel.EndReason.Abort then
            -- if self:GetBossWaveCount() == self.model.turn then
            if parsed_msg.ntf_universe_clear.result then
                self:SetEndReason(SrpgModel.EndReason.Clear)
            else
                self:SetEndReason(SrpgModel.EndReason.Lose)
            end
        end

        local triggerId = self:GetTriggerId()
        local config = Database.Query("d_srpg_effect_trigger", triggerId)
        local effectDisplay = config and config.effectDisplay or {}

        if table.indexof(effectDisplay, SrpgController.SpecialDisplay.SetAbort) then
            self:SetEndReason(SrpgModel.EndReason.Abort)
        elseif table.indexof(effectDisplay, SrpgController.SpecialDisplay.SetClear) then
            self:SetEndReason(SrpgModel.EndReason.Clear)
        elseif table.indexof(effectDisplay, SrpgController.SpecialDisplay.SetLose) then
            self:SetEndReason(SrpgModel.EndReason.Lose)
        end

        self:AddEvent({
            type = SrpgModel.TurnEvents.GameEnd
        })
    end
end

---@param self SrpgController
---@param parsed_msg NtfAddCardMessage
SrpgController[Protos.NTF_ADD_CARD] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        for _, cardId in ipairs(parsed_msg.ntf_add_card.card_ids) do
            self.model:AddCard(cardId)
            self:AddEvent({
                type = SrpgModel.TurnEvents.ShowCard,
                info = {
                    cardId = cardId
                }
            })
        end
        for _, cardId in ipairs(parsed_msg.ntf_add_card.missed_card_ids) do
            self.model:AddExceededCard(cardId)
            self:AddEvent({
                type = SrpgModel.TurnEvents.ReplaceCard,
                info = {
                    cardId = cardId
                }
            })
        end
    end
end

---@param self SrpgController
---@param parsed_msg NtfAddCurioMessage
SrpgController[Protos.NTF_ADD_CURIO] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        for _, curioId in ipairs(parsed_msg.ntf_add_curio.curio_ids) do
            self.model:AddCurio(curioId)
            self:AddEvent({
                type = SrpgModel.TurnEvents.ShowCurio,
                info = {
                    curioId = curioId
                }
            })
        end
    
        MessageManager:Broadcast(SrpgController.CuriosUpdated)
        
    end
end

---@param self SrpgController
---@param parsed_msg NtfEffectTriggerBeginMessage
SrpgController[Protos.NTF_EFFECT_TRIGGER_BEGIN] = function(self, result, msgId, parsed_msg)
    if self.model.triggerId ~= 0 then
        LOG_WARN("trigger not enclosed!")
    end
    self.model.triggerId = parsed_msg.ntf_effect_trigger_begin.trigger_id

    local config = Database.Query("d_srpg_effect_trigger", self.model.triggerId)

    if config.effectType == 201 then
        self:AddShowStoryEvents(config.effectConfig)
    end
end

---@param self SrpgController
---@param parsed_msg NtfEffectTriggerBeginMessage
SrpgController[Protos.NTF_EFFECT_TRIGGER_END] = function(self, result, msgId, parsed_msg)
    self.model.triggerId = 0
end
---}}}

SrpgController.__listened_messages = {
    SrpgModel.BossMoved,
    SrpgModel.BossShowUp,
    UI_Dialog_Story_C.DialogEnd,
    UI_Tutorial_C.TutorialEnd,
    UI_Dialog_Talk_C.TalkEnd,
    SrpgController.FightOver,
}

---@param oldBossInfo BossInfo
---@param newBossInfo BossInfo
SrpgController[SrpgModel.BossMoved] = function(self, oldBossInfo, newBossInfo)
    if oldBossInfo.hex.q ~= newBossInfo.hex.q or oldBossInfo.hex.r ~= newBossInfo.hex.r then 
        self:AddEvent({
            type = SrpgModel.TurnEvents.BossMoved,
            info = {
                bossIndex = oldBossInfo.boss_index,
                from = oldBossInfo.hex,
                to = newBossInfo.hex,
            }
        })

        if newBossInfo.hex.q == self.model.baseHex.q and newBossInfo.hex.r == self.model.baseHex.r then
            self:AddEvent({
                type = SrpgModel.TurnEvents.BossArrived,
                info = {
                    bossIndex = oldBossInfo.boss_index,
                    hex = newBossInfo.hex,
                }
            })
        end
    end
end

---@param newBossInfo BossInfo
SrpgController[SrpgModel.BossShowUp] = function(self, newBossInfo)
    self:AddEvent({
        type = SrpgModel.TurnEvents.BossShowUp,
        info = {
            bossIndex = newBossInfo.boss_index,
            hex = newBossInfo.hex,
        }
    })
end

---@param newBossInfo BossInfo
---@param universeFightData UniverseFightData
SrpgController[SrpgController.FightOver] = function(self, result, universeFightData)
    self:AddEvent({
        type = SrpgModel.TurnEvents.FightEnd,
        info = {
            result = result,
            universeFightData = universeFightData,
        }
    })
end

function SrpgController:CheckAndRemoveEvent(type)
    if self.runningEvent and self.runningEvent.type == type then
        self.model:RemoveEvent(self.runningEvent)
        self.runningEvent = nil
        self:UpdateEvent()
    end
end

SrpgController.SRPG_END_DIALOG_IDS = {
    20101004,
    20101008,
    20101012,
}

function SrpgController:PlayStory(story)
    self.storyPlaying = story
end

function SrpgController:StoryEnd(storyId, storyType)
    if not self.storyPlaying then
        return
    end
    LOG_INFO(self.storyPlaying.id, storyId, self.storyPlaying.type, storyType)
    if self.storyPlaying.id == storyId and self.storyPlaying.type == storyType then
        self:CheckAndRemoveEvent(SrpgModel.TurnEvents.ShowStory)
        self.storyPlaying = nil
    end
end

SrpgController[UI_Dialog_Story_C.DialogEnd] = function(self, originDialogId, dialogId, type)
    if table.indexof(SrpgController.SRPG_END_DIALOG_IDS, dialogId) then
        self:CheckAndRemoveEvent(SrpgModel.TurnEvents.GameEnd)
    else
        self:StoryEnd(originDialogId, type)
    end
end

SrpgController[UI_Tutorial_C.TutorialEnd] = function(self, id, type)
    self:StoryEnd(id, type)
end

SrpgController[UI_Dialog_Talk_C.TalkEnd] = function(self, id, type)
    self:StoryEnd(id, type)
end

function SrpgController:UpdatePendingUniverseEvents()
    for _, cardId in ipairs(self.model.exceededCards) do
        self:AddEvent({
            type = SrpgModel.TurnEvents.ReplaceCard,
            info = {
                cardId = cardId
            }
        })
    end
    for _, info in pairs(self.model.fightInfo) do
        if not self:IsBossFight(info) then
            self:AddEvent({
                type = SrpgModel.TurnEvents.NormalFight,
                info = {
                    fightUUID = info.fight_uuid
                }
            })
        else
            local bossInfo = self:GetBossInfoByUUID(info.fight_uuid)
            if bossInfo then
                self:AddEvent({
                    type = SrpgModel.TurnEvents.BossFight,
                    info = {
                        bossId = bossInfo.boss_index
                    }
                })
            end
        end
    end

    for _, info in pairs(self.model.eventInfo) do
        self:AddEvent({
            type = SrpgModel.TurnEvents.Event,
            info = {
                eventUUID = info.event_uuid
            }
        }, true)
    end

    for _, info in ipairs(self.model.cardsForSelect) do
        self:AddEvent({
            type = SrpgModel.TurnEvents.SelectCard,
            info = {
                UUID = info.select_uuid
            }
        }, true)
    end

    for _, info in ipairs(self.model.curiosForSelect) do
        self:AddEvent({
            type = SrpgModel.TurnEvents.SelectCurio,
            info = {
                UUID = info.select_uuid
            }
        }, true)
    end

    self:UpdateEvent()
end

function SrpgController:UpdateFightData(universeFightData)
    self.model:UpdateFightData(universeFightData)

    MessageManager:Broadcast(SrpgController.UpdateUI)
end

function SrpgController:GetUniverseInfo()
    return self.model.universeInfo
end

function SrpgController:GetBaseHex()
    return self.model:GetBaseHex()
end

function SrpgController:GetCurrentFightInfo()
    return self.model:GetCurrentFightInfo()
end

function SrpgController:CompleteCurrentFight()
    self.model:CompleteCurrentFight()
end

function SrpgController:CompleteCurrentBossFight()
    self.model:CompleteCurrentBossFight()

    MessageManager:Broadcast(SrpgController.UpdateUI)
    MessageManager:Broadcast(SrpgController.UpdateMapItems)
    MessageManager:Broadcast(SrpgController.UpdateMapLines)
end

function SrpgController:StopCurrentFight()
    self.model:StopCurrentFight()
end

function SrpgController:GetFightInfoByUUID(fightUUID)
    return self.model:GetFightInfoByUUID(fightUUID)
end

function SrpgController:IsBossFight(fightInfo)
    return self.model:IsBossFight(fightInfo)
end

function SrpgController:AddBossFightInfo(bossIndex, fightInfo)
    self.model:AddBossFightInfo(bossIndex, fightInfo)
end

function SrpgController:UpdateBossInfo(bossInfo)
    self.model:UpdateBossInfo(bossInfo)

    MessageManager:Broadcast(SrpgController.UpdateUI)
    MessageManager:Broadcast(SrpgController.UpdateMapItems)
    MessageManager:Broadcast(SrpgController.UpdateMapLines)
end

function SrpgController:GetBossInfoByUUID(fightUUID)
    return self.model:GetBossInfoByUUID(fightUUID)
end

function SrpgController:GetBossFightInfoByBossIndex(bossIndex)
    return self.model:GetBossFightInfoByBossIndex(bossIndex)
end

function SrpgController:AddInfiniteBuff(buffId)
    self.model:AddInfiniteBuff(buffId)
end

function SrpgController:AddDefiniteBuff(buffId)
    self.model:AddDefiniteBuff(buffId)
end

function SrpgController:IsUniverseExist()
    return self.model.running
end

function SrpgController:IsSpecificMap()
    return not self.model.mapType or self.model.mapType == 0
end

function SrpgController:GetDifficulty()
    return self.model.difficulty
end

function SrpgController:GetStep()
    return self.model.step
end

function SrpgController:GetTurn()
    return self.model.turn
end

function SrpgController:GetPlanetId()
    return self.model.mainPlanetId
end

function SrpgController:GetCharacterFightData()
    return self.model.characterFightData
end

function SrpgController:GetMainPosInfo()
    return self.model.mainPosInfo
end

function SrpgController:GetMainPosByHex(hex)
    return self.model:GetMainPos(hex)
end

function SrpgController:GetLines()
    return self.model.lines
end

function SrpgController:GetBossLines()
    return self.model.bossLines
end

function SrpgController:GetBossWaveCount()
    return self.model:GetBossWaveCount()
end

function SrpgController:GetBossCount()
    return self.model:GetBossCount()
end

function SrpgController:GetBossInfo()
    return self.model.bossInfo
end

function SrpgController:GetBossConfigId()
    return self.model.bossConfigId
end

function SrpgController:GetMissionInfo()
    return self.model.missionInfo
end

---@param eventInfo EventInfo
function SrpgController:AddUniverseEventInfo(eventInfo)
    table.insert(self.model.eventInfo, eventInfo)
end

function SrpgController:GetUniverseEventInfo()
    return self.model.eventInfo
end

function SrpgController:GetUniverseEventInfoByUUID(eventUUID)
    return self.model:GetUniverseEventInfoByUUID(eventUUID)
end

function SrpgController:RemoveUniverseEvent(eventUUID)
    return self.model:RemoveUniverseEvent(eventUUID)
end

function SrpgController:GetCardsInHand()
    return self.model.cards
end

function SrpgController:GetExceededCards()
    return self.model.exceededCards
end

function SrpgController:GetCardsForSelect(UUID)
    return self.model:GetCardsForSelect(UUID)
end

function SrpgController:GetCuriosForSelect(UUID)
    return self.model:GetCuriosForSelect(UUID)
end

---@param msg ResCreateChooseCard
function SrpgController:CreateCardsForSelect(msg, UUID)
    self.model:UpdateCardsForSelect(msg, UUID)
    
    MessageManager:Broadcast(SrpgController.UpdateCardSelection)
end

---@param msg ResRefreshChooseCard
function SrpgController:RefreshCardsForSelect(msg, UUID)
    self.model:UpdateCardsForSelect(msg, UUID, true)

    self:RerunEvents()
end

---@param msg ResCreateChooseCurio
function SrpgController:CreateCuriosForSelect(msg, UUID)
    self.model:UpdateCuriosForSelect(msg, UUID)
    
    MessageManager:Broadcast(SrpgController.UpdateCurioSelection)
end

---@param msg ResRefreshChooseCurio
function SrpgController:RefreshCuriosForSelect(msg, UUID)
    self.model:UpdateCuriosForSelect(msg, UUID, true)
    
    self:RerunEvents()
end

function SrpgController:RemoveExceededCard(exceededCardIndex)
    table.remove(self.model.exceededCards, exceededCardIndex)
end

function SrpgController:ReplaceExceededCard(index, exceededCardIndex)
    local newCardId = self.model.exceededCards[exceededCardIndex]
    self.model.cards[index] = newCardId

    self:AddEvent({
        type = SrpgModel.TurnEvents.ShowCard,
        info = {
            cardId = newCardId
        }
    })

    self:RemoveExceededCard(exceededCardIndex)
end

function SrpgController:ChooseCard(UUID)
    self.model:ChooseCard(UUID)

    if self.runningEvent.info.UUID ~= UUID then
        LOG_WARN("UUID not match")
    end

    self:CheckAndRemoveEvent(SrpgModel.TurnEvents.SelectCard)
end

function SrpgController:ChooseCurio(UUID, curioIndex)
    local curioId = self.model:ChooseCurio(UUID, curioIndex)

    if self.runningEvent.info.UUID ~= UUID then
        LOG_WARN("UUID not match")
    end

    self:AddEvent({
        type = SrpgModel.TurnEvents.ShowCurio,
        info = {
            curioId = curioId
        }
    })

    MessageManager:Broadcast(SrpgController.CuriosUpdated)

    self:CheckAndRemoveEvent(SrpgModel.TurnEvents.SelectCurio)
end

function SrpgController:GetCurios()
    return self.model.curios
end

function SrpgController:PlaceCard(hex, attachIndex, cardIndex)
    local mainPosInfo = self:GetMainPosByHex(hex)
    local attachInfo = mainPosInfo.main_pos_attach_infos[attachIndex].main_pos_card_pos_info

    local cardId = self.model.cards[cardIndex + 1]

    attachInfo.card_id = cardId

    table.remove(self.model.cards, cardIndex + 1)

    MessageManager:Broadcast(SrpgController.UpdateUI)

    MessageManager:Broadcast('OnMsg_Place_Card', cardId)
end

function SrpgController:RemoveCard(hex, attachIndex)
    local mainPosInfo = self:GetMainPosByHex(hex)
    local attachInfo = mainPosInfo.main_pos_attach_infos[attachIndex].main_pos_card_pos_info

    attachInfo.card_id = 0
    attachInfo.upgrade_times = 0

    MessageManager:Broadcast(SrpgController.UpdateUI)
end

function SrpgController:UpgradeCard(hex, attachIndex, upgradeCards)
    local mainPosInfo = self:GetMainPosByHex(hex)
    local attachInfo = mainPosInfo.main_pos_attach_infos[attachIndex].main_pos_card_pos_info

    local cardInfo = Database.Query("d_srpg_card_base", attachInfo.card_id)

    attachInfo.card_id = cardInfo.upgradeCard

    for _, cardIndex in pairs(upgradeCards) do
        table.remove(self.model.cards, cardIndex + 1)
    end

    MessageManager:Broadcast(SrpgController.UpdateUI)

    MessageManager:Broadcast('OnMsg_Upgrade_Card')

    attachInfo.upgrade_times = attachInfo.upgrade_times + 1
end

function SrpgController:GetCardUpgradeTimes(cardId)
    for _, mainPos in ipairs(self.model.mainPosInfo) do
        for i, info in ipairs(mainPos.main_pos_attach_infos) do
            if info.main_pos_attach_extra == SrpgModel.AttachType.Card then
                if info.main_pos_card_pos_info.card_id == cardId then
                    return info.main_pos_card_pos_info.upgrade_times
                end
            end
        end
    end
end

function SrpgController:GetPlacedCards(hex)
    ---@type MainPosCardPosInfo[]
    local cards = {}

    local mainPosInfo = self:GetMainPosByHex(hex)

    for _, info in ipairs(mainPosInfo.main_pos_attach_infos) do
        if info.main_pos_attach_extra == SrpgModel.AttachType.Card then
            if info.main_pos_card_pos_info.card_id ~= 0 then
                table.insert(cards, info.main_pos_card_pos_info)
            end
        end
    end

    return cards
end

function SrpgController:GetAllPlacedCards()
    ---@type MainPosCardPosInfo[]
    local cards = {}

    for _, mainPos in ipairs(self.model.mainPosInfo) do
        for i, info in ipairs(mainPos.main_pos_attach_infos) do
            if info.main_pos_attach_extra == SrpgModel.AttachType.Card then
                if info.main_pos_card_pos_info.card_id ~= 0 then
                    table.insert(cards, info.main_pos_card_pos_info)
                end
            end
        end
    end

    return cards
end

function SrpgController:GetActivatedRaces()
    local cardPosInfo = self:GetAllPlacedCards()

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

    return racesCount
end

function SrpgController:GetFreeCardRefreshTime()
    return self.model:GetFreeCardRefreshTime()
end

function SrpgController:GetCardRefreshCostModifier()
    return self.model:GetCardRefreshCostModifier()
end

function SrpgController:HideOverview()
    if self.model.specificId == 0 then
        return false
    else
        local config = Database.Query("d_srpg_map_specific", self.model.specificId)
        return config.HideOverview == 1
    end
end

function SrpgController:HideResources()
    if self.model.specificId == 0 then
        return false
    else
        local config = Database.Query("d_srpg_map_specific", self.model.specificId)
        return config.HideResources == 1
    end
end

function SrpgController:BuyItem(hex, attachIndex, itemIndex)
    local mainPos = self.model:GetMainPos(hex)

    mainPos.main_pos_attach_infos[attachIndex].main_pos_shop_info.item_infos[itemIndex].sold = true
end

function SrpgController:RefreshShop(hex, attachIndex, itemInfo)
    local mainPos = self.model:GetMainPos(hex)

    mainPos.main_pos_attach_infos[attachIndex].main_pos_shop_info.item_infos = itemInfo
end

function SrpgController:GetResource(index)
    return self.model.resources[index]
end

function SrpgController:GetHp()
    return self.model.curHp
end

function SrpgController:GetBoatEnergy()
    return self.model.boatEnergy
end

function SrpgController:SetPlayerHex(hex)
    self.model.playerHex = hex
    self.model.saveGame.MainPosId = hex_grid.to_string(hex)

    self:Save()
end

function SrpgController:GetPlayerHex()
    return self.model.playerHex
end

function SrpgController:ChangeResource(index, value, showNotify)
    self.model:ChangeResource(index, value, showNotify)
end

function SrpgController:GetCurHp()
    return self.model.curHp
end

function SrpgController:ChangeHp(value)
    self.model:ChangeHp(value)
end

function SrpgController:ChangeCharacter(index, characterId)
    local characterFightData = self.model.characterFightData

    characterFightData[index].character_id = characterId

    local hpMax = UIUtils.GetCharacterAllAttr(characterId)[1001]

    characterFightData[index].cur_hp = hpMax
end

function SrpgController:TickTurn()
    MessageManager:Broadcast("OnMsg_SRPG_NextTurn")
    self.model:TickTurn()
end

-- 保证每段剧情都播完，分开播放
function SrpgController:AddShowStoryEvents(storyConfig)
    for i = 1, #storyConfig - 1, 2 do
        self:AddEvent({
            type = SrpgModel.TurnEvents.ShowStory,
            info = {
                story = { 
                    id = storyConfig[i],
                    type = storyConfig[i + 1]
                }
            }
        })
    end
end

function SrpgController:ExploreTo(targetHex)
    self:TickTurn()

    if self:GetHp() > 0 then
        self:AddEvent({
            type = SrpgModel.TurnEvents.ShipMove,
            info = {
                from = self:GetPlayerHex(),
                to = targetHex,
            }
        })

        local mainPosInfo = self:GetMainPosByHex(targetHex)
        mainPosInfo.state = 3

        MessageManager:Broadcast(SrpgController.UpdateMapLines, mainPosInfo.hex)

        local mainPosConfig = Database.Query("d_srpg_main_pos_base", mainPosInfo.main_pos_id)

        if #mainPosConfig.StoryDisplay > 0 then
            self:AddShowStoryEvents(mainPosConfig.StoryDisplay)
        end
    end

    -- self:SetPlayerHex(targetHex)
end

function SrpgController:GetTriggerId()
    return self.model.triggerId
end

function SrpgController:SetEndReason(value)
    self.model.endReason = value
end

function SrpgController:GetEndReason()
    return self.model.endReason
end

function SrpgController:EndRun()
    self.model.running = false
    return MessageManager:Broadcast(SrpgController.GameEnded, self.model.endReason, self.model.difficulty, self.model.mapType, self.model.mapId)
end

---@param event Event
function SrpgController:AddEvent(event, delay)
    self.model:AddEvent(event)

    if not delay then
        self:UpdateEvent()
    end
end

--重新处理事件
--选牌期间点刷新会有资源变更需要处理
function SrpgController:RerunEvents()
    self.runningEvent = nil
    self:UpdateEvent()
end

function SrpgController:HasPendingEvent()
    return #self.model.pendingEvents > 0
end

function SrpgController:HasPendingFight()
    return #self.model.fightInfo > 0
end

--尽可能处理事件
--事件被处理与否由消息是否绑定了回调决定
--
--主要问题是战斗场景中可能已经确定游戏结束了，但是动画需要在星图那边播放
function SrpgController:UpdateEvent()
    MessageManager:Broadcast(SrpgController.EventUpdated)
    
    if self.runningEvent then
        return
    end

    if self:HasPendingEvent() then
        local nextEvent = self.model:PeekEvent()
        self:HandleEvent(nextEvent)
    end
end

---@param event Event
function SrpgController:NotifyShipMove(event)
    return MessageManager:Broadcast(SrpgController.ShipMove, event.info.from, event.info.to)
end

function SrpgController:HandleResourceChange(event)
    if event.info.hpChange then
        self:ChangeHp(event.info.hpChange)
    end

    if event.info.resourceChange then
        for key, value in pairs(event.info.resourceChange) do
            self:ChangeResource(key, value)
        end
    end

    MessageManager:Broadcast(SrpgController.UpdateUI)

    self:CheckAndRemoveEvent(SrpgModel.TurnEvents.ResourceChange)

    return true
end

function SrpgController:NotifyFightEnd(event)
    return MessageManager:Broadcast(SrpgController.FightEnd, event.info.result, event.info.universeFightData)
end

function SrpgController:NotifyShowItems(event)
    return MessageManager:Broadcast(SrpgController.ShowItems, event.info.items, event.info.triggerId)
end

function SrpgController:NotifyBossMove(event)
    return MessageManager:Broadcast(SrpgController.BossMove, event.info.bossIndex, event.info.from, event.info.to)
end

function SrpgController:NotifyBossShowUp(event)
    return MessageManager:Broadcast(SrpgController.BossShowUp, event.info.bossIndex, event.info.hex)
end

function SrpgController:NotifyBossArrived(event)
    return MessageManager:Broadcast(SrpgController.BossArrived, event.info.bossIndex, event.info.hex)
end

function SrpgController:NotifyUniverseEvent(event)
    return MessageManager:Broadcast(SrpgController.UniverseEvent, event.info.eventUUID)
end

function SrpgController:NotifyNormalFight(event)
    return MessageManager:Broadcast(SrpgController.NormalFight, event.info.fightUUID)
end

function SrpgController:NotifyBossFight(event)
    return MessageManager:Broadcast(SrpgController.BossFight, event.info.bossId)
end

function SrpgController:NotifyGameEnd(event)
    return MessageManager:Broadcast(SrpgController.GameEnd)
end

function SrpgController:NotifySelectCard(event)
    return MessageManager:Broadcast(SrpgController.StartSelectCard, event.info.UUID)
end

function SrpgController:NotifySelectCurio(event)
    return MessageManager:Broadcast(SrpgController.StartSelectCurio, event.info.UUID)
end

function SrpgController:NotifyReplaceCard(event)
    return MessageManager:Broadcast(SrpgController.ReplaceCard, event.info.cardId)
end

function SrpgController:NotifyShowCard(event)
    return MessageManager:Broadcast(SrpgController.ShowCard, event.info.cardId)
end

function SrpgController:NotifyShowCurio(event)
    return MessageManager:Broadcast(SrpgController.ShowCurio, event.info.curioId)
end

function SrpgController:NotifyShowStory(event)
    return MessageManager:Broadcast(SrpgController.ShowStory, event.info.story)
end

function SrpgController:NotifyOpenShop(event)
    return MessageManager:Broadcast(SrpgController.OpenShop, event.info.attachInfo)
end

SrpgController.EventHandlers = {
    [SrpgModel.TurnEvents.FightEnd] = SrpgController.NotifyFightEnd,
    [SrpgModel.TurnEvents.ShowItems] = SrpgController.NotifyShowItems,
    [SrpgModel.TurnEvents.ShipMove] = SrpgController.NotifyShipMove,
    [SrpgModel.TurnEvents.ResourceChange] = SrpgController.HandleResourceChange,
    [SrpgModel.TurnEvents.BossMoved] = SrpgController.NotifyBossMove,
    [SrpgModel.TurnEvents.BossShowUp] = SrpgController.NotifyBossShowUp,
    [SrpgModel.TurnEvents.BossArrived] = SrpgController.NotifyBossArrived,
    [SrpgModel.TurnEvents.Event] = SrpgController.NotifyUniverseEvent,
    [SrpgModel.TurnEvents.NormalFight] = SrpgController.NotifyNormalFight,
    [SrpgModel.TurnEvents.BossFight] = SrpgController.NotifyBossFight,
    [SrpgModel.TurnEvents.GameEnd] = SrpgController.NotifyGameEnd,
    [SrpgModel.TurnEvents.SelectCard] = SrpgController.NotifySelectCard,
    [SrpgModel.TurnEvents.SelectCurio] = SrpgController.NotifySelectCurio,
    [SrpgModel.TurnEvents.ReplaceCard] = SrpgController.NotifyReplaceCard,
    [SrpgModel.TurnEvents.ShowCard] = SrpgController.NotifyShowCard,
    [SrpgModel.TurnEvents.ShowCurio] = SrpgController.NotifyShowCurio,
    [SrpgModel.TurnEvents.ShowStory] = SrpgController.NotifyShowStory,
    [SrpgModel.TurnEvents.OpenShop] = SrpgController.NotifyOpenShop,
}

---@param event Event
function SrpgController:HandleEvent(event)
    self.runningEvent = event

    if event then
        if not SrpgController.EventHandlers[event.type](self, event) then
            self.runningEvent = nil
        end
    end
end

function SrpgController:Load(account_id)
    ---@type SG_SaveGame_Universe_C
    local saveGame
    if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Universe_" .. account_id, 0) then
        saveGame = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_Universe_" .. account_id, 0)
    else
        saveGame = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load("/Game/_Game/Blueprints/Game/SG_SaveGame_Universe.SG_SaveGame_Universe_C"))
    end

    self.model:LoadSaveGame(saveGame)

    self.lastUsedAccountId = account_id
end

function SrpgController:Save(account_id)
    --理论上应该找账号之类的system去拿，但是现在存在gameinstance里，lua不绑uobject拿不到
    account_id = account_id or self.lastUsedAccountId
    if self.model.saveGame then
        UE.UGameplayStatics.SaveGameToSlot(self.model.saveGame, "SG_SaveGame_Universe_" .. account_id, 0)
    end
end

function SrpgController:__init()
    self.model = SrpgModel.New()
end

return SrpgController

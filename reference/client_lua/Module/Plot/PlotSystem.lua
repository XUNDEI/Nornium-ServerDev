local NetCmdController = require "Framework.Common.NetCmdController"
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local UIUtils = require '_Game.Utils.UIUtils'
local Database = require '_Game.Utils.Database'
local d_story_node = require "ClientDatas.d_story_node"
local PlotSystem = BaseClass("PlotSystem", NetCmdController)
local QuestSystem = require "Module.Quest.QuestSystem"
local PlayerSystem = require('Module.Player.PlayerSystem')
local SrpgController = require("Module.Srpg.SrpgController")

PlotSystem.PlotInfo = {}
PlotSystem.CachedUnlockStoryLinesInfo = {}

function PlotSystem:IsHasKey(key)
    if self.PlotInfo and self.PlotInfo.taskKey_ids then
        for _, v in pairs(self.PlotInfo.taskKey_ids) do
            if v == key then
                return true
            end
        end
    end
    return false
end

function PlotSystem:ReqUnlockStoryLines(storyLineId)
    if not storyLineId or '' == storyLineId then return false end
    storyLineId = tonumber(storyLineId)
    print("---storyLineId:" .. tostring(storyLineId))
    if storyLineId <= 0 then return false end
    -- print("---当前解锁了的:" .. tostring(table.dump(self.PlotInfo.unlocked_story_line_ids or {}, nil, false)))
    if self.PlotInfo and self.PlotInfo.unlocked_story_line_ids then
        local isUnlocked = false
        for _, lineId in ipairs(self.PlotInfo.unlocked_story_line_ids) do
            if lineId == storyLineId then
                isUnlocked = true
                break
            end
        end

        local bIsRequest = false
        for _, v in pairs(self.CachedUnlockStoryLinesInfo) do 
            if v == storyLineId then
                bIsRequest = true
                break
            end
        end
       
        if not isUnlocked and not bIsRequest then
            table.insert(self.CachedUnlockStoryLinesInfo, storyLineId)
            local msg = { 
                story_line_ids = {
                    storyLineId
                } 
            }
            Client.send("req_unlock_story_line", msg)
        else
            -- print("-----已经解锁过了:" .. tostring(storyLineId))
            return true
        end
    end
    return false
end

function PlotSystem:OnNetCmd_Res_Plot(result, msgId, parsed_msg)
    if result == 0 then
        if parsed_msg.res_plot.plot_info.plot_tree_id == 0 and parsed_msg.res_plot.plot_info.plot_node_id == 0 then
            print('----------->新号')
            UE.UGameplayStatics.DeleteGameInSlot('SG_SaveGame_Speak_' .. self.GameInstance.account_id, 0)
            UE.UGameplayStatics.DeleteGameInSlot('SG_SaveGame_Char_' .. self.GameInstance.account_id, 0)
            UE.UGameplayStatics.DeleteGameInSlot('SG_SaveGame_TeamList_' .. self.GameInstance.account_id, 0)
            UE.UGameplayStatics.DeleteGameInSlot('SG_SaveGame_Backpack_' .. self.GameInstance.account_id, 0)
            UE.UGameplayStatics.DeleteGameInSlot('SG_SaveGame_Universe_' .. self.GameInstance.account_id, 0)
        end
        local d_task_story = require('ClientDatas.d_task_story')
        for id, config in pairs(d_task_story) do
            config.isSub = false
        end

        for id, config in pairs(d_task_story) do
            for key, value in pairs(config.subTaskid) do
                if d_task_story[value] then
                    d_task_story[value].isSub = true
                else
                    LOG_ERROR(value .. "is not find in d_task_story")
                end
            end
        end

        for id, config in pairs(d_task_story) do
            if config.isSub then
                local mission_id = config.id
                while #d_task_story[mission_id].nextTaskid > 0 do
                    local next_task_id = d_task_story[mission_id].nextTaskid[1]
                    d_task_story[next_task_id].isSub = true
                    mission_id = next_task_id
                end
            end
        end

        self.PlotInfo = parsed_msg.res_plot.plot_info
        self.PlotInfo.taskKey_ids = {}
        self.PlotInfo.story_node_infos = {}
        self.PlotInfo.new_completed_mission_ids = {}
        for _, mission_id in ipairs(self.PlotInfo.completed_mission_ids) do
            local task_info = Database.Query("d_task_story", mission_id)
            for __, key in ipairs(task_info.key) do
                table.insert(self.PlotInfo.taskKey_ids, key)
            end
        end

        local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        if saveGameSpeak and saveGameSpeak.MissionInfos then
            saveGameSpeak.MissionInfos:Clear()
        end
        self.GameInstance:SaveSaveGameSpeak()
        self:RefreshQuestInfo()

        --找到所有可以解锁的node
        local sortTree = {}
        local d_story_tree = require "ClientDatas.d_story_tree"
        for story_tree_id, story_tree_info in pairs(d_story_tree) do
            self.PlotInfo.story_node_infos[story_tree_id] = {}
            local array = {}
            table.insert(sortTree, story_tree_id)
            table.insert(array, story_tree_id)
            local length = #array
            while #array > 0 do
                for i = 1, length do
                    local node_id = array[i]
                    local node_info = d_story_node[node_id]
                    if node_info then
                        --后续优化 self.PlotInfo.story_node_infos改为有序table 写个拿tree info的接口
                        self.PlotInfo.story_node_infos[story_tree_id][node_id] = node_info
                        self.PlotInfo.story_node_infos[story_tree_id][node_id].unlocked = false
                        self.PlotInfo.story_node_infos[story_tree_id][node_id].completed = true
                        if #node_info.key > 0 then
                            local bSatisfy = true
                            for _, need_keys in ipairs(node_info.key) do
                                local bMatch = false
                                for _, key in ipairs(self.PlotInfo.taskKey_ids) do
                                    if key == need_keys then
                                        bMatch = true
                                    end
                                end
                                if not bMatch then
                                    bSatisfy = false
                                    break
                                end
                            end
            
                            --去掉已经解锁的
                            -- for _, unlocked_story_line_id in ipairs(self.PlotInfo.unlocked_story_line_ids) do
                            --     if unlocked_story_line_id == node_id then
                            --         bSatisfy = false
                            --         self.PlotInfo.story_node_infos[story_tree_id][node_id].unlocked = true
                            --     end
                            -- end
            
                            if bSatisfy then
                                self.PlotInfo.story_node_infos[story_tree_id][node_id].unlocked = true
                            end
                        else
                            self.PlotInfo.story_node_infos[story_tree_id][node_id].unlocked = true
                        end
            
                        for _, task_key_id in ipairs(node_info.taskkey) do
                            local find = false
                            for _, get_task_key_id in ipairs(self.PlotInfo.taskKey_ids) do
                                if task_key_id == get_task_key_id then
                                    find = true
                                    break
                                end
                            end
                            if not find then
                                self.PlotInfo.story_node_infos[story_tree_id][node_id].completed = false
                                break
                            end
                        end
                        for _, son_id in ipairs(node_info.sonid) do
                            local findId = false
                            for _, tid in pairs(array) do
                                if tid == son_id then
                                    findId = true
                                    break
                                end
                            end
                            if not findId then
                                table.insert(array, son_id)
                            end
                        end
                    end
                end
                for i = length, 1, -1 do
                    table.remove(array, i)
                end
                length = #array
            end
        end

        table.sort(sortTree, function(a, b)
            return a < b
        end)

        --找到当前播放节点
        if self.PlotInfo.plot_tree_id == 0 and self.PlotInfo.plot_node_id == 0 then
            --当前没有在播放的剧情 找到第一颗树的第一个节点
            local msg = {}
            msg.plot_tree_id = sortTree[1]
            msg.plot_node_id = sortTree[1]
            Client.send("req_play_plot_node", msg)
        else
            --继续播放当前剧情
            if self.GameInstance then
                local d_story_node = require("ClientDatas.d_story_node")
                local config = d_story_node[self.PlotInfo.plot_node_id]
                local stateTree = UE.UObject.Load(config.state)
                local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
                if playerController.BP_StateTree and playerController.BP_StateTree:IsRunning() then
                    playerController.BP_StateTree:StopLogic("Finish")
                end
                playerController.BP_StateTree:SetStateTree(stateTree)
                self.GameInstance.PlotStateTree = stateTree
                MessageManager:GetInstance():Broadcast("UnFinished_Fight")
                print('---------------------------------------------------------')
                print("-------zzzplot播放剧情节点 Tree:" .. tostring(self.PlotInfo.plot_tree_id) .. " node:" .. tostring(self.PlotInfo.plot_node_id))
                print('---------------------------------------------------------')
            end
        end
    end
end

function PlotSystem:SetGameInstance(gameInstance)
    self.GameInstance = gameInstance
end

function PlotSystem:RefreshCompletedMissionInfo()
    for _, completed_mission_id in ipairs(self.PlotInfo.new_completed_mission_ids) do
        table.insert(self.PlotInfo.completed_mission_ids, completed_mission_id)
    end
    self.PlotInfo.new_completed_mission_ids = {}
end

function PlotSystem:OnNetCmd_Res_Play_Plot_Node(result, msgId, parsed_msg)
    if result == 0 then
        if self.GameInstance and parsed_msg.req_data then
            local bNew = false
            if not self.GameInstance.PlotStateTree then
                --新号
                bNew = true
            end
            self.PlotInfo.plot_tree_id = parsed_msg.req_data.plot_tree_id
            self.PlotInfo.plot_node_id = parsed_msg.req_data.plot_node_id
            self.PlotInfo.plot_mission_infos = {}
            self.PlotInfo.node_completed_mission_ids = {}
            local d_story_node = require("ClientDatas.d_story_node")
            local config = d_story_node[self.PlotInfo.plot_node_id]
            local stateTree = UE.UObject.Load(config.state)
            local levelName = UE.UGameplayStatics.GetCurrentLevelName(self.GameInstance, true)
            if levelName == "CityMap" then
                local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
                if playerController.BP_StateTree:IsRunning() then
                    playerController.BP_StateTree:StopLogic("Finish")
                end
                playerController.BP_StateTree:SetStateTree(stateTree)
            end
            self.GameInstance.PlotStateTree = stateTree
            local SaveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            SaveGameSpeak.PlotIndex = 0
            --SaveGameSpeak.StoryFinished = false
            self.GameInstance.PlayPlotInCity = true
            self.GameInstance:SaveSaveGameSpeak()
            QuestSystem:GetInstance():FinishAllStoryMission()
            MessageManager:GetInstance():Broadcast("Play_Plot")
            if bNew then
                MessageManager:GetInstance():Broadcast("UnFinished_Fight")
            end
            self:RefreshQuestInfo()
        end
        --清除宇宙信息
        if self.GameInstance:GetUniverseExists() then
            self.GameInstance:AbortAndStopRunning()
        end
        print('---------------------------------------------------------')
        print("-------zzzplot播放剧情节点 Tree:" .. tostring(self.PlotInfo.plot_tree_id) .. " node:" .. tostring(self.PlotInfo.plot_node_id))
        print('---------------------------------------------------------')
    end
end

function PlotSystem:RefreshQuestInfo()
    local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
    saveGameSpeak.MissionIds:Clear()
    saveGameSpeak.SubMissionIds:Clear()
    --传递给StateTree的任务进度为当前任务链的根taskid
    --不在任何task的子任务的任务链里的任务就是根taskid
    if saveGameSpeak then
        for index, value in ipairs(self.PlotInfo.plot_mission_infos) do
            local mission_info = Database.Query("d_task_story", value.mission_id)
            if mission_info then
                if not mission_info.isSub then
                    saveGameSpeak.MissionIds:Add(value.mission_id)
                else
                    saveGameSpeak.SubMissionIds:Add(value.mission_id)
                end
            end
        end
    end
    self.GameInstance:SaveSaveGameSpeak()
    --根据父子关系找到当前执行的任务 
    for _, v in ipairs(self.PlotInfo.plot_mission_infos) do
        local config = Database.Query('d_task_story', v.mission_id)
        local quest = {
            mission_id = v.mission_id,
            mission_record_args = v.mission_record_args,
            completed = v.completed,
        }
        QuestSystem:GetInstance().QuestInfo[v.mission_id] = quest
        if config and (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) then
            QuestSystem:GetInstance():CheckMissionFinished(quest, config.taskContent, config)
        end
    end

    local new_mission_id = 0
    local no_jump = false
    local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
    if saveGameSpeak.SubMissionIds:Length() > 0 then
        local mission_id = saveGameSpeak.SubMissionIds:Get(1)
        local config = Database.Query('d_task_story', mission_id)
        if config and config.dominantType == 1 then
            new_mission_id = mission_id
            QuestSystem:GetInstance():SetTrackQuestId(mission_id)
            print("------------追踪剧情主线任务:" .. tostring(mission_id))
            if config.unJump == 1 then
                no_jump = true
            else
                no_jump = false
            end
            playerController.StateTreeNoJump = no_jump
        end
    end

    if new_mission_id == 0 then
        if saveGameSpeak.MissionIds:Length() > 0 then
            local mission_id = saveGameSpeak.MissionIds:Get(1)
            local config = Database.Query('d_task_story', mission_id)
            if config and config.dominantType == 1 then
                new_mission_id = mission_id
                QuestSystem:GetInstance():SetTrackQuestId(mission_id)
                print("------------追踪剧情主线任务:" .. tostring(mission_id))
                if config.unJump == 1 then
                    no_jump = true
                else
                    no_jump = false
                end
                playerController.StateTreeNoJump = no_jump
            end
        end
    end
    LOG_DEBUG_TRACKBACK("playerController.StateTreeNoJump", playerController.StateTreeNoJump, "mission_id", new_mission_id)
    self.NewMissionId = new_mission_id
end

function PlotSystem:ReqCompletePlotMission(msg)
    if msg then
        local send_caches = Client.get_send_caches()
        for _, send_cache in ipairs(send_caches) do
            if send_cache.msg_name == "req_complete_plot_mission" then
                if send_cache.msg and send_cache.msg.mission_id == msg.mission_id then
                    return
                end
            end
        end
        self.CheckNodeCompleteReward = true
        Client.send("req_complete_plot_mission", msg)
    end
end

function PlotSystem:OnNetCmd_Res_Complete_Plot_Mission(result, msgId, parsed_msg)
    if result == 0 then
        local CachedStateTreeNoJump
        if UE.UGameplayStatics.GetCurrentLevelName(self.GameInstance, true) == "CityMap" then
            local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
            CachedStateTreeNoJump = playerController.StateTreeNoJump
        end
        self.CheckNodeCompleteReward = false
        local finishMission = false
        if self.GameInstance then
            self.GameInstance.firstMission = false
            local completed_mission_id = parsed_msg.req_data.mission_id
            self.GameInstance.req_data.req_complete_plot_mission = nil
            --如果在当前已开启的任务中
            for index, mission_info in ipairs(self.PlotInfo.plot_mission_infos) do
                if completed_mission_id == mission_info.mission_id then
                    table.insert(self.PlotInfo.node_completed_mission_ids, completed_mission_id)
                    table.remove(self.PlotInfo.plot_mission_infos, index)
                    finishMission = true
                    break
                end
            end
            if finishMission then
                table.insert(self.PlotInfo.new_completed_mission_ids, completed_mission_id)
                local task_info = Database.Query("d_task_story", completed_mission_id)
                for __, key in ipairs(task_info.key) do
                    table.insert(self.PlotInfo.taskKey_ids, key)
                end
                --解锁node
                self:RefreshUnlockedNodes()
                print("------------关闭追踪剧情主线任务:")
                QuestSystem:GetInstance():SetTrackQuestId(0)
            end
            self:RefreshQuestInfo()
        end
        
        local scene_id = self:GetCurrentSceneId()
        if scene_id then
            local playerInfo = PlayerSystem:GetInstance().PlayerInfo
            for _, player_transform_in_scene in ipairs(playerInfo.player_transform_in_scenes) do
                if player_transform_in_scene.scene_id == scene_id then
                    LOG_DEBUG("req_remove_player_transform_in_scene", scene_id)
                    Client.send("req_remove_player_transform_in_scene", { scene_ids = {scene_id} })
                    break
                end
            end
        end
        -- local playerInfo = PlayerSystem:GetInstance().PlayerInfo
        -- playerInfo.player_transform_in_scenes = {}
        print('---------------------------------------------------------')
        print('-------zzzplot完成任务:' .. tostring(parsed_msg.req_data.mission_id))
        print('---------------------------------------------------------')
        MessageManager:GetInstance():Broadcast("complete_plot_mission", parsed_msg.req_data.mission_id)
        QuestSystem:GetInstance():OnComplete_Plot_Mission(parsed_msg.req_data.mission_id)
        self:CheckParentMission()
        self:DestroySTTAcots()
        local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        if UE.UGameplayStatics.GetCurrentLevelName(self.GameInstance, true) == "CityMap" then
            local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
            if CachedStateTreeNoJump == nil then
                CachedStateTreeNoJump = playerController.StateTreeNoJump
            end
            if playerController.bIsInStationScene then
                if not CachedStateTreeNoJump then
                    playerController.DelayHideUILoading2 = true
                    playerController:UnloadStationScene({ self, function( self )
                        LOG_DEBUG_TRACKBACK('-----------------UnloadStationScene RestartStateTree bIsInStationScene')
                        self:RestartStateTree(CachedStateTreeNoJump)
                        --self.GameInstance.OnUnloadPlotLevels:Add(self.GameInstance, PlotSystem.RestartStateTree)
                    end })
                end
            elseif playerController.IsInBuildLevel then
                if not CachedStateTreeNoJump then
                    playerController:LeaveBuildLevel('BuildEnter2', { self, function( self )
                        LOG_DEBUG_TRACKBACK('-----------------UnloadStationScene RestartStateTree IsInBuildLevel')
                        self:RestartStateTree(CachedStateTreeNoJump)
                    end })
                end
            else
                self:RestartStateTree(CachedStateTreeNoJump)
                --self.GameInstance.OnUnloadPlotLevels:Add(self.GameInstance, PlotSystem.RestartStateTree)
            end
        end
    end
end

function PlotSystem:GetCurrentSceneId()
    local levelNames = self.GameInstance:GetVisibleStreamingLevel()
    for i = 1, levelNames:Length() do
        local LevelName = levelNames:Get(i)
        if LevelName == "City1Station" then
            return UIUtils.SceneId.City1Station
        elseif LevelName == "City1Hotel_Day" or LevelName == "City1Hotel_Night" or LevelName == "City1Hotel" then
            return UIUtils.SceneId.City1Hotel
        elseif LevelName == "City1BusinessCenter" then
            return UIUtils.SceneId.BusinessCenter
        elseif LevelName == "OpeningScene" then
            return UIUtils.SceneId.OpeningScene
        end
    end
    return 0
end

function PlotSystem:CheckParentMission()
    for _, mission_info in ipairs(self.PlotInfo.plot_mission_infos) do
        local task_info = Database.Query("d_task_story", mission_info.mission_id)
        if task_info.taskTargetAmounts and task_info.taskTargetAmounts > 0 then
            if #task_info.subTaskid >= task_info.taskTargetAmounts then
                --数据正常
                if not mission_info.completed then
                    local count = 0
                    for i, subId in ipairs(task_info.subTaskid) do
                        local subTaskComplete = self:GetMissionCompletedState(subId)
                        if subTaskComplete then
                            count = count + 1
                        end
                    end
                    if count >= task_info.taskTargetAmounts then
                        print('---------------------------------------------------------')
                        print('-------plot完成parent任务:' .. tostring(mission_info.mission_id))
                        print('---------------------------------------------------------')
                        local msg = { mission_id = mission_info.mission_id }
                        self:ReqCompletePlotMission(msg)
                    end
                end
            else
                --配表子任务完成数量过大
                LOG_WARN('Mission Id ' .. mission_info.mission_id .. ' task Target Amounts bigger than subTaskId ')
                if not mission_info.completed then
                    local count = 0
                    for i, subId in ipairs(task_info.subTaskid) do
                        local subTaskComplete = self:GetMissionCompletedState(subId)
                        if subTaskComplete then
                            count = count + 1
                        end
                    end
                    if count >= #task_info.subTaskid then
                        print('---------------------------------------------------------')
                        print('-------plot完成parent任务:' .. tostring(mission_info.mission_id))
                        print('---------------------------------------------------------')
                        local msg = { mission_id = mission_info.mission_id }
                        self:ReqCompletePlotMission(msg)
                    end
                end
            end
        elseif task_info.taskTargetAmounts == 0 and #task_info.subTaskid > 0 then
            --配表没有子任务完成数量
            LOG_ERROR('Mission Id ' .. task_info.mission_id .. ' task Target Amounts == 0 ')
        end
    end
end

function PlotSystem:GetMissionCompletedState(mission_id)
    for _, node_completed_mission_id in ipairs(self.PlotInfo.node_completed_mission_ids) do
        if mission_id == node_completed_mission_id then
            local task_info = Database.Query("d_task_story", mission_id)
            if #task_info.nextTaskid == 0 then
                --如果此任务没有子任务和任务链则自己完成就算完成
                return true
            else
                if #task_info.nextTaskid > 0 then
                    return self:GetMissionCompletedState(task_info.nextTaskid[1])
                end
            end
        end
    end
    return false
end

function PlotSystem:OnNetCmd_Res_Receive_Plot_Tree_Award(result, msgId, parsed_msg)
    if result == 0 then
        --print("===res_player:" .. tostring(table.dump(parsed_msg, nil, 10)))
        --self.PlayerInfo = parsed_msg
    end
end

function PlotSystem:OnNetCmd_Res_Unlock_Story_Line(result, msgId, parsed_msg)
    local firstId = 0
    if self.CachedUnlockStoryLinesInfo then
        if #self.CachedUnlockStoryLinesInfo > 0 then
            firstId = self.CachedUnlockStoryLinesInfo[1]
            table.remove(self.CachedUnlockStoryLinesInfo, 1)
            
        end
    end
    if result == 0 then
        table.insert(self.PlotInfo.unlocked_story_line_ids, firstId)
        if self.GameInstance and parsed_msg.req_data.req_unlock_story_line then
            for _, unlock_line in ipairs(parsed_msg.req_data.req_unlock_story_line.story_line_ids) do
                self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id][unlock_line].unlocked = true
                table.insert(self.PlotInfo.unlocked_story_line_ids, unlock_line)
                print('---------------------------------------------------------')
                print("-------解锁Story Line Tree:" .. tostring(self.PlotInfo.plot_tree_id) .. " node:" .. tostring(unlock_line))
                print('---------------------------------------------------------')
            end
        end
    end
end

function PlotSystem:OnNetCmd_Ntf_Add_Plot_Mission(result, msgId, parsed_msg)
    if result == 0 then
        for _, new_mission_info in ipairs(parsed_msg.ntf_add_plot_mission.plot_mission_infos) do
            local find = false
            for _, mission_info in ipairs(self.PlotInfo.plot_mission_infos) do
                if new_mission_info.mission_id == mission_info.mission_id then
                    find = true
                    break
                end
            end
            if not find then
                table.insert(self.PlotInfo.plot_mission_infos, new_mission_info)
            end
        end
        self:RefreshQuestInfo()

        for _, v in ipairs(self.PlotInfo.plot_mission_infos) do
            local config = Database.Query('d_task_story', v.mission_id)
            local quest = {
                mission_id = v.mission_id,
                mission_record_args = v.mission_record_args,
                completed = v.completed,
            }
            QuestSystem:GetInstance().QuestInfo[v.mission_id] = quest
            local d_task_story = require('ClientDatas.d_task_story')
            local config = d_task_story[v.mission_id]
            if config and (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) then
                QuestSystem:GetInstance():CheckMissionFinished(quest, config.taskContent, config)
            end
          
            print('---------------------------------------------------------')
            print('-------zzzplot解锁任务：' .. v.mission_id)
            print('---------------------------------------------------------')
            local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            if saveGameSpeak then
                saveGameSpeak.MissionInfo = ''
            end
            self.GameInstance:SaveSaveGameSpeak()

            MessageManager:GetInstance():Broadcast("OnMsg_Refresh_Plot_Mission", v.mission_id)
        end
    end
end

function PlotSystem:DestroySTTAcots()
    --Destroy Mission Track
    local MissionTrackClass = UE.LoadClass('/Game/_Game/Blueprints/Procedure/City/Mission_Track.Mission_Track_C')
    local MissionTrackActors = UE.UGameplayStatics.GetAllActorsOfClass(self.GameInstance, MissionTrackClass)
    local x = MissionTrackActors:Length()
    for i = 1, MissionTrackActors:Length() do 
        local actor = MissionTrackActors:Get(i)
        actor:K2_DestroyActor()
    end

    --Destroy Mission Track
    local SOPlotDialogClass = UE.LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_Plot_Dialog.SO_Plot_Dialog_C')
    local SOPlotDialogActors = UE.UGameplayStatics.GetAllActorsOfClass(self.GameInstance, SOPlotDialogClass)
    local x = SOPlotDialogActors:Length()
    for i = 1, SOPlotDialogActors:Length() do 
        local actor = SOPlotDialogActors:Get(i)
        actor.IsActivated = false
    end
end

function PlotSystem:IsCompletedDialog(dialog_id)
    local d_task_story = require('ClientDatas.d_task_story')
    for _, v in ipairs(self.PlotInfo.completed_mission_ids) do
        local config = d_task_story[v]
        if config.taskContent == 60001 and #config.taskNumber > 0 then
            if tonumber(config.taskNumber[1]) == dialog_id then
                return true
            end
        end
    end
    return false
end

function PlotSystem:IsCompletedDialogOption(dialog_id, option_id)
    local d_task_story = require('ClientDatas.d_task_story')
    for _, v in ipairs(self.PlotInfo.completed_mission_ids) do
        local config = d_task_story[v]
        if config.taskContent == 60001 and #config.taskNumber > 1 then
            if tonumber(config.taskNumber[1]) == dialog_id and tonumber(config.taskNumber[2]) == option_id then
                return true
            end
        end
    end
    return false
end

function PlotSystem:RefreshUnlockedNodes()
    if self.PlotInfo.story_node_infos and self.PlotInfo.plot_tree_id and self.PlotInfo.plot_tree_id > 0 and self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id] then

    else
        print("------------数据有点问题!!!")
        return
    end
    for node_id, story_node_info in pairs(self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id]) do
        --需要key解锁
        if #story_node_info.key > 0 then
            local can_unlock = true
            for _, need_taskKey_id in ipairs(story_node_info.key) do
                local find = false
                for _, finish_taskKey_id in ipairs(self.PlotInfo.taskKey_ids) do
                    if need_taskKey_id == finish_taskKey_id then
                        find = true
                        break
                    end
                end
                if not find then
                    can_unlock = false
                    break
                end
            end
            if can_unlock and not self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id][node_id].unlocked then
                self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id][node_id].unlocked = true
                print('---------------------------------------------------------')
                print("-------zzzplot解锁新剧情节点 Tree:" .. tostring(self.PlotInfo.plot_tree_id) .. " node:" .. tostring(node_id))
                print('---------------------------------------------------------')
            end
        end
    end
end


--根据当前完成的任务 拿到可以跳转的所有节点
function PlotSystem:GetTransNode()
    --根据已解锁的task找到nextnode
    local canTransNodeId = 0
    local story_node_info = self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id][self.PlotInfo.plot_node_id]

    if #self.PlotInfo.node_completed_mission_ids > 0 then
        for _, mission_id in ipairs(self.PlotInfo.node_completed_mission_ids) do
            local task_info = Database.Query("d_task_story", mission_id)
            if task_info and task_info.nextNode ~= 0 then 
                canTransNodeId = task_info.nextNode
                break
            end
        end
    else
        local nextNodes = {}
        for _, mission_id in ipairs(self.PlotInfo.completed_mission_ids) do
            local task_info = Database.Query("d_task_story", mission_id)
            if task_info and task_info.nextNode ~= 0 then 
                nextNodes[task_info.nextNode] = task_info.nextNode
            end
        end

        for _, son_id in ipairs(story_node_info.sonid) do
            local son_node_info = self.PlotInfo.story_node_infos[self.PlotInfo.plot_tree_id][son_id]
            if #son_node_info.key > 0 then
                if nextNodes[son_id] then
                    canTransNodeId = son_id
                    break
                end
            end
        end
    end
    return canTransNodeId
end

function PlotSystem:RestartStateTree(CachedStateTreeNoJump)
    if UE.UGameplayStatics.GetCurrentLevelName(self.GameInstance, true) == "CityMap" then
        local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
        if CachedStateTreeNoJump == nil then
            CachedStateTreeNoJump = playerController.StateTreeNoJump
        end
        if not CachedStateTreeNoJump then
            --销毁所有UI和pawn
            if self.NewMissionId then
                local config = Database.Query('d_task_story', self.NewMissionId)
                if config and config.unJump == 0 then
                    local oldCharacter = playerController:K2_GetPawn()
                    playerController:UnPossess()
                    if oldCharacter then
                        oldCharacter:K2_DestroyActor()
                    end
                    -- print("------------->RemoveAll")
                    -- self.GameInstance:GetOrAddUMG("UI_Loading2", nil, 1)
                    self.GameInstance.bPlotSystemRemoveAllUI = true
                    UIManager:GetInstance():RemoveAll()
                end
            end
            if playerController.BP_StateTree:IsRunning() then
                playerController.BP_StateTree:StopLogic("Finish")
            end
            print("------------->startlogic")
            playerController.BP_StateTree:StartLogic()
        end
    else
        local playerController = UE.UGameplayStatics.GetPlayerController(self.GameInstance, 0)
        local oldCharacter = playerController:K2_GetPawn()
        if oldCharacter then
            oldCharacter:SetActorEnableCollision(false)
            oldCharacter:SetActorHiddenInGame(true)
            oldCharacter.CharacterMovement:SetActive(false, false)
        end
        self.GameInstance:LoadLevel("CityMap")
    end
end

function PlotSystem:OnCompletedStoryTask(mission_id)
    local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
    if saveGameSpeak then
        for i = 1, saveGameSpeak.MissionInfos:Length() do
            local MissionStr = saveGameSpeak.MissionInfos:Get(i)
            local array = string.split(MissionStr, '_')
            if tonumber(array[1]) == mission_id then
                saveGameSpeak.MissionInfos:RemoveItem(MissionStr)
                break
            end
        end
    end
    self.GameInstance:SaveSaveGameSpeak()
    local msg = { mission_id = mission_id }
    self:ReqCompletePlotMission(msg)
    self.GameInstance.req_data.req_complete_plot_mission = msg
end

--完成节点奖励
function PlotSystem:OnNetCmd_Ntf_Item_Info(result, msgId, parsed_msg)
    if result == 0 and
        parsed_msg and 
        parsed_msg.ntf_item_info and 
        parsed_msg.ntf_item_info.changed_item_infos then
        if self.CheckNodeCompleteReward then
            local itemList = {}
            for _, changed_item_info in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
                table.insert(itemList,
                    { item_id = changed_item_info.item_id, count = changed_item_info.count })
            end
            if #itemList > 0 then
                self.CompleteReward = itemList
            end
            self.CheckNodeCompleteReward = false
        end
    end
end

function PlotSystem:ShowNodeReward()
    if self.CompleteReward and #self.CompleteReward > 0 then
        self.UI_GetItem_Notice = self.GameInstance:AddUMG('UI_GetItem_Notice')
        self.UI_GetItem_Notice:RefreshUI(self.CompleteReward)
        self.CompleteReward = {}
        return self.UI_GetItem_Notice
    end
    return nil
end

function PlotSystem:SaveTurorialId(tutorial_id)
    if not self.TutorialIds then
        self.TutorialIds = {}
    end
    table.insert(self.TutorialIds, tutorial_id)
end

return PlotSystem

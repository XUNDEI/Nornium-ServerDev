local NetCmdController = require "Framework.Common.NetCmdController"
local QuestSystem = BaseClass("QuestSystem", NetCmdController)
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local UIUtils = require '_Game.Utils.UIUtils'
local Database = require '_Game.Utils.Database'
local SrpgModel = require("Module.Srpg.SrpgModel")
local SrpgController = require("Module.Srpg.SrpgController")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local RedPointSystem = require('Module.RedPointSystem.RedPointSystem')
local BackpackSystem = require 'Module.Backpack.BackpackSystem'

local ErrorCode = 
{
    RefreshDailyResultType = 
    {
        OK = 0,
        REFRESHED = 1,
        NO_MISSION = 2,
        MISSION_COMPLETED = 3,
        MISSION_COMPLETE = 4,
    },
    CompleteDailyResultType = 
    {
        OK                     = 0,
        NO_MISSION             = 1,
        MISSION_COMPLETED      = 2,
        CHECK_CONDITION_FAILED = 3,
    }
};

--任务数据
QuestSystem.QuestInfo = {}
QuestSystem.TrackQuestId = 0

--奖励册数据
QuestSystem.QuestBookInfo = {}

--savegame
QuestSystem.GameInstance = nil

function QuestSystem:ClearCache()
    self.CachedInteractBuildId = 0
end

function QuestSystem:GetTaskConfigById(questId)
    local taskConfig = nil
    if questId > 100000 then
        taskConfig = Database.Query('d_task_story', questId)
    else
        taskConfig = Database.Query('d_task', questId)
    end
    return taskConfig
end

function QuestSystem:SetTrackQuestId(questId)
    QuestSystem.TrackQuestId = questId
    UIManager:GetInstance():SetShouldShowTracker(questId and questId > 0 or false)
end

-- function QuestSystem:InitTrackPosMap()
--     self.TrackPosMap = self.TrackPosMap or {}
--     return self.TrackPosMap
-- end

function QuestSystem:CheckQuest()
    local gameInstance = self.GameInstance
    if not gameInstance then return end
    self.LastTrackQuestId = self.LastTrackQuestId or 0
    local TrackQuestId = self.TrackQuestId
    if TrackQuestId > 0 then
        if self.LastTrackQuestId ~= TrackQuestId then
            local true_last_track_id = self.LastTrackQuestId
            self.LastTrackQuestId = TrackQuestId

            if TrackQuestId > 0 then
                local taskConfig = self:GetTaskConfigById(TrackQuestId)
                if not taskConfig then return end
                if taskConfig and taskConfig.maps and taskConfig.maps ~= ''
                and not gameInstance:LevelIsVisible(taskConfig.maps) then
                    --LOG_ERROR("===check task:" .. tostring(self.LastTrackQuestId)
                    --.. " 's curLevelName:" .. tostring(gameInstance:TopSubLevelName())
                    --.. ",maps:" .. tostring(taskConfig.maps))
                    --self:StartTrackPos(self.LastTrackQuestId, false, nil)
                    UIManager:GetInstance():ClearSpecialTracker()
                    return
                end
                if taskConfig and #taskConfig.coordinate < 3 then
                    --LOG_ERROR("===check task:" .. tostring(self.LastTrackQuestId)
                    --.. " 's coordinate error:" .. tostring(#taskConfig.coordinate))
                    --self:StartTrackPos(self.LastTrackQuestId, false, nil)
                    UIManager:GetInstance():ClearSpecialTracker()
                    return
                end
                if true_last_track_id > 0 then
                    UIManager:GetInstance():ClearSpecialTracker()
                end
                local worldPos = UE.FVector(taskConfig.coordinate[1], taskConfig.coordinate[2], taskConfig.coordinate[3])
                UIManager:GetInstance():CreateSpecialTracker(worldPos)
            end
        else
            return
        end
    else
        if self.LastTrackQuestId > 0 then
            UIManager:GetInstance():ClearSpecialTracker()
            self.LastTrackQuestId = 0
            return
        end
    end
end

function QuestSystem:RecheckQuest()
    local gameInstance = self.GameInstance
    if not gameInstance then return end
    local TrackQuestId = self.TrackQuestId
    UIManager:GetInstance():ClearSpecialTracker()
    if TrackQuestId > 0 then
        local taskConfig = self:GetTaskConfigById(TrackQuestId)
        if not taskConfig then return end
        if taskConfig and taskConfig.maps and taskConfig.maps ~= ''
        and not gameInstance:LevelIsVisible(taskConfig.maps) then
            return
        end
        if taskConfig and #taskConfig.coordinate < 3 then
            return
        end
        local worldPos = UE.FVector(taskConfig.coordinate[1], taskConfig.coordinate[2], taskConfig.coordinate[3])
        UIManager:GetInstance():CreateSpecialTracker(worldPos)
    end
end

function QuestSystem:GetQuestInfo(questId)
    for qId, info in pairs(QuestSystem.QuestInfo) do
        if qId == questId then
            return info
        end
    end
    return nil
end

function QuestSystem:SetGameInstance(gameInstance)
    self.GameInstance = gameInstance
end

function QuestSystem:SetMainTrackQuestId(questId)
    QuestSystem.TrackQuestId = questId
    if self.GameInstance then
        local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        if saveGameSpeak then
            saveGameSpeak.QuestId = questId
        end
        self.GameInstance:SaveSaveGameSpeak()
    end
end

function QuestSystem:OnNetCmd_Res_Player(result, msgId, parsed_msg)
    if result == 0 then
        self:InitDailyQuest(parsed_msg.res_player.player_info.player_daily_mission_info)
        self:InitBookQuest(parsed_msg.res_player.player_info.player_book_mission_infos)
    end
end

function QuestSystem:InitDailyQuest(questInfo)
    MessageManager:GetInstance():AddListener(SrpgController.GameEnded, self)


    --上次手动刷新时间
    QuestSystem.DailyLastRefreshSeconds = questInfo.manual_refresh_seconds
    --上次自动刷新时间
    QuestSystem.DailyLastAutoRefreshSeconds = questInfo.last_auto_refresh_seconds

    --清除所有日常任务，保留主线和剧情引导类型任务
    for qid, v in pairs(QuestSystem.QuestInfo) do
        if qid < 100000 then
            QuestSystem.QuestInfo[qid] = nil
        end
    end

    for _, v in ipairs(questInfo.player_mission_infos) do
        if #v.mission_record_args == 0 then
            table.insert(v.mission_record_args, 0) 
        end
        local quest = {
            mission_id = v.mission_id,
            mission_record_args = questInfo and v.mission_record_args or { 0 },
            completed = questInfo and v.completed or false,
        }
        QuestSystem.QuestInfo[v.mission_id] = quest
    end

    --标记登录任务
    self:AddMissionRecord(UIUtils.EOpenNeedType.Login)

    --追踪任务判断
    if QuestSystem.TrackQuestId == 0 or nil == QuestSystem.QuestInfo[QuestSystem.TrackQuestId] then
        local minQuestId = 0
        for qId, _ in pairs(QuestSystem.QuestInfo) do
            minQuestId = (minQuestId == 0 or minQuestId > qId) and qId or minQuestId
        end
        --主线任务显示
        if self.GameInstance then
            local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            if saveGameSpeak and saveGameSpeak.QuestId > 0 then
                self.TrackQuestId = tonumber(saveGameSpeak.QuestId)
            end
        end
        --QuestSystem.TrackQuestId = minQuestId
    end
    self:CheckAllMissionState()
    MessageManager:GetInstance():Broadcast("OnMsg_RefreshDailyMission")
end

--请求刷新当前任务
function QuestSystem:ReqRefreshPlayerDailyMission(mission_id)
    QuestSystem.CachedRefreshDailyMissionId = mission_id
    Client.send('req_refresh_player_daily_mission', { mission_id = mission_id })
end

--刷新当前任务返回
function QuestSystem:OnNetCmd_Res_Refresh_Player_Daily_Mission(result, msgId, parsed_msg)
    if result == ErrorCode.RefreshDailyResultType.OK then
        QuestSystem.DailyLastRefreshSeconds = os.time()
        --缓存的任务id
        QuestSystem.QuestInfo[QuestSystem.CachedRefreshDailyMissionId] = nil

        local v = parsed_msg.res_refresh_player_daily_mission.player_mission_info
        local quest = {
            mission_id = v.mission_id,
            completed = v.completed,
            mission_record_args = v.mission_record_args
        }
        QuestSystem.QuestInfo[v.mission_id] = quest
        local config = self:GetTaskConfigById(v.mission_id)
        if config then
            self:CheckMissionFinished(quest, config.taskContent, config)
        end
        --追踪任务判断
        if QuestSystem.TrackQuestId ~= 0 and nil == QuestSystem.QuestInfo[QuestSystem.TrackQuestId] then
            QuestSystem.TrackQuestId = 0
        end
        MessageManager:GetInstance():Broadcast("OnMsg_RefreshDailyMission", v)
    elseif result == ErrorCode.RefreshDailyResultType.REFRESHED then
        print("===任务已经刷新!!!")
    elseif result == ErrorCode.RefreshDailyResultType.NO_MISSION then
        print("===无任务了!!!")
    elseif result == ErrorCode.RefreshDailyResultType.MISSION_COMPLETED then
        print("===任务完成了111")
    elseif result == ErrorCode.RefreshDailyResultType.MISSION_COMPLETE then
        print("===任务完成了222")
    end
end

function QuestSystem:OnNetCmd_Ntf_Player_Daily_Mission_Info(result, msgId, parsed_msg)
    if result == 0 then
        local playerDailyMissionInfo = parsed_msg.ntf_player_daily_mission_info.player_daily_mission_info
        self:InitDailyQuest(playerDailyMissionInfo)
    end
end

--请求获取当前任务奖励
function QuestSystem:ReqCompletePlayerDailyMission(mission_id)
    QuestSystem.CachedCompleteDailyMissionId = mission_id
   
    local isInSend = self:ReqMsgIsInSendCache('req_complete_player_daily_mission', { mission_id = mission_id })
    if not isInSend then
        Client.send('req_complete_player_daily_mission', { mission_id = mission_id })
    end
end

function QuestSystem:OnNetCmd_Res_Complete_Player_Daily_Mission(result, msgId, parsed_msg)
    if result == ErrorCode.CompleteDailyResultType.OK then
        local questId = QuestSystem.CachedCompleteDailyMissionId
        if QuestSystem.QuestInfo[questId] then
            QuestSystem.QuestInfo[questId].completed = true
            local config = self:GetTaskConfigById(questId)
            --日常任务完成
            if config and config.taskType == UIUtils.ETaskType.Daily then
                self:AddMissionRecord(UIUtils.EOpenNeedType.CompletedDailyMission, { 1 })
            end
            RedPointSystem:RemoveRecord('UI_City.UI_CityMenu.UI_DailyQuest', questId)
        end
        MessageManager:GetInstance():Broadcast("OnMsg_CompleteDailyMission", questId)
    elseif result == ErrorCode.CompleteDailyResultType.NO_MISSION then
        print("===无任务了!!!")
    elseif result == ErrorCode.CompleteDailyResultType.MISSION_COMPLETED then
        print("===任务完成了111")
    elseif result == ErrorCode.CompleteDailyResultType.CHECK_CONDITION_FAILED then
        print("===任务条件检测失败222")
    end
end

-------------------------------------------------------------------------------------------
---奖励册
function QuestSystem:InitBookQuest(bookQuestInfo)
    local d_task_book = require("ClientDatas.d_task_book")
    print("====InitBookQuest:" .. tostring(table.dump(bookQuestInfo, nil, 10)))
    local localQuestInfoTab = {}
    for _, v in ipairs(bookQuestInfo) do
        if #v.mission_record_args == 0 then
            table.insert(v.mission_record_args, 0) 
        end
        localQuestInfoTab[v.mission_id] = v
    end

    local questList = {}
    
    for _, v in ipairs(d_task_book) do
        local questInfo = localQuestInfoTab[v.id]
        local quest = {
            mission_id = v.id,
            mission_record_args = questInfo and questInfo.mission_record_args or { 0 },
            completed = questInfo and questInfo.completed or false,
        }
        questList[v.id] = quest
    end
    QuestSystem.QuestBookInfo = questList

    self:CheckAllBookMissionState()
end

function QuestSystem:InitStoryQuest(storyQuestInfo)
    local d_task_book = require("ClientDatas.d_task_book")
    print("====InitBookQuest:" .. tostring(table.dump(d_task_book, nil, 10)))
    local localQuestInfoTab = {}
    for _, v in ipairs(d_task_book) do
        local config = d_task_book[v.mission_id]
        if #v.mission_record_args == 0 then
            if v.completed then
                v.mission_record_args[1] = config.taskNumber[1]
            else
                table.insert(v.mission_record_args, 0)
            end
        end
        localQuestInfoTab[v.mission_id] = v
    end

    local questList = {}
    
    for _, v in ipairs(d_task_book) do
        local questInfo = localQuestInfoTab[v.id]
        local quest = {
            mission_id = v.id,
            mission_record_args = questInfo and questInfo.mission_record_args or { 0 },
            completed = questInfo and questInfo.completed or false,
        }
        questList[v.id] = quest
    end
    QuestSystem.QuestBookInfo = questList
end

function QuestSystem:ReqCompletePlayerBookMission(mission_id)
    if QuestSystem.CachedCompleteBookMissionId == mission_id then return end
    QuestSystem.CachedCompleteBookMissionId = mission_id
    Client.send('req_complete_player_book_mission', { mission_id = mission_id })
end 

function QuestSystem:OnNetCmd_Res_Complete_Player_Book_Mission(result, msgId, parsed_msg)
    if result == ErrorCode.CompleteDailyResultType.OK then
        local questId = QuestSystem.CachedCompleteBookMissionId
        if QuestSystem.QuestBookInfo[questId] then
            QuestSystem.QuestBookInfo[questId].completed = true
        end
        self:CheckAllBookMissionState()
        RedPointSystem:GetInstance():RemoveRecord('UI_City.UI_CityMenu.UI_RewardBook', questId)
        MessageManager:GetInstance():Broadcast("OnNetCmd_Res_Mission_RewardBook_Reward", questId)
        QuestSystem.CachedCompleteBookMissionId = 0
    elseif result == ErrorCode.CompleteDailyResultType.NO_MISSION then
        print("===无任务了!!!")
    elseif result == ErrorCode.CompleteDailyResultType.MISSION_COMPLETED then
        print("===任务完成了111")
    elseif result == ErrorCode.CompleteDailyResultType.CHECK_CONDITION_FAILED then
        print("===任务条件检测失败222")
    end
end

function QuestSystem:CheckAllMissionState()
    local d_task = require("ClientDatas.d_task")
    for _, v in pairs(QuestSystem.QuestInfo) do
        local config = d_task[v.mission_id]
        if not config then
            config = Database.Query('d_task_story', v.mission_id)
        end
        if config then
            self:CheckMissionFinished(v, config.taskContent, config)
            if config.taskType == UIUtils.ETaskType.Daily and not v.completed and v.finished then
                RedPointSystem:AddRecord('UI_City.UI_CityMenu.UI_DailyQuest', v.mission_id)
            end
        end
    end
end

function QuestSystem:CheckAllBookMissionState()
    local d_task_book = require("ClientDatas.d_task_book")
    for _, v in pairs(QuestSystem.QuestBookInfo) do
        local config = d_task_book[v.mission_id]
        self:CheckMissionFinished(v, config.taskContent, config)
        if not v.completed and v.finished then
            RedPointSystem:GetInstance():AddRecord('UI_City.UI_CityMenu.UI_RewardBook', v.mission_id)
        end
    end
end

function QuestSystem:CheckAllBookMission()
    local questTab = {}
    local taskList = QuestSystem.QuestBookInfo
    for _, v in pairs(taskList) do
        local config = Database.Query('d_task_book', v.mission_id)
        if not questTab[config.page] then 
            questTab[config.page] = 
            {
                completeCount = 0,
                finishedCount = 0,
            } 
        end
        if v.completed then
            questTab[config.page].completeCount = questTab[config.page].completeCount + 1
            questTab[config.page].finishedCount = questTab[config.page].finishedCount + 1
        elseif v.finished then
            questTab[config.page].finishedCount = questTab[config.page].finishedCount + 1
        end
    end
    --print("===questTab:" .. tostring(table.dump(questTab, nil, 10)))
    local maxPage = 1
    local curChapter = 0
    for page, v in ipairs(questTab) do
        maxPage = maxPage >= page and maxPage or page
        if v.finishedCount > v.completeCount then
            if curChapter == 0 then
                curChapter = page
            else
                curChapter = math.min(curChapter, page)
            end
        end
        --本章未全部完成(本页5个子任务全完成后，才开启下一页的翻页按钮)
        if v.finishedCount < 5 then
            break
        end
    end
    curChapter = curChapter == 0 and maxPage or curChapter

    self:CheckAllBookMissionState()
    return curChapter, maxPage
end

function QuestSystem:GetMissionNeedCount(taskConfig)
    if taskConfig then
        local quesType = taskConfig.taskContent
        local num1 = taskConfig.taskNumber[1] or 1
        local num2 = taskConfig.taskNumber[2] or 1

        if quesType == UIUtils.EOpenNeedType.CharWeaponLvCount or --30005, --X件武器升至X级
            quesType == UIUtils.EOpenNeedType.CharEquipLvCount or --30006, --X件装备升至X级
            quesType == UIUtils.EOpenNeedType.CharTalentCount then -- 30004, --X名角色天赋点亮X个
            return num1
        elseif quesType == UIUtils.EOpenNeedType.CharLevel then --30000, --XX角色等级升至X级
            return num2
        elseif quesType == UIUtils.EOpenNeedType.CharSkillLv then --30001, --XX技能升至X级
            return num2
        elseif quesType == UIUtils.EOpenNeedType.CharLevelCount then --30002, --X名角色等级升至X级
            return num1
        elseif quesType == UIUtils.EOpenNeedType.CharSkillLvCount then --30003, --X名角色任意技能技能升至X
            return num1
        elseif quesType == UIUtils.EOpenNeedType.DailyCopyCount then --10000 打%s次任意日常本
            return num1
        elseif quesType == UIUtils.EOpenNeedType.Shopping then --30007 买若干个道具
            return num1
        elseif quesType == UIUtils.EOpenNeedType.SRPGDifficulty then --20008, --完成某难度SRPG
            return 1
        elseif quesType == UIUtils.EOpenNeedType.SRPGCount --20006, --进行X局SRPG
            or quesType == UIUtils.EOpenNeedType.UnlockTalent --30008, --点亮一个星位
            or quesType == UIUtils.EOpenNeedType.ForgeCount --50001,--进行%s次装备锻造
            or quesType == UIUtils.EOpenNeedType.DecomposeCount --50002,--进行%s次熔炉拆解
            or quesType == UIUtils.EOpenNeedType.SyntheticCount then --50007 --进行%s次熔炉合成
            return num1
        elseif quesType == UIUtils.EOpenNeedType.SpecifyShopping then --30010, --购买特定的商店的任意物品
            return num2
        elseif quesType == UIUtils.EOpenNeedType.RewardBook then --50006,--完成若干个任务
            return #taskConfig.taskNumber
        elseif quesType == UIUtils.EOpenNeedType.CompletedDailyMission then --50008,--完成若干个日常任务
            return num1
        elseif quesType == UIUtils.EOpenNeedType.PlayerLevel then --30000
            return num1
        elseif quesType == UIUtils.EOpenNeedType.Dialog then
            return 1
        elseif quesType == UIUtils.EOpenNeedType.BuildCreate then
            return 1
        else
            return num1
        end
    end
    return 1
end
--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
---检测任务是否完成
function QuestSystem:CheckMissionFinished(missionData, type, config)
    missionData.AllCount = self:GetMissionNeedCount(config)

    local num1 = config.taskNumber[1] or 1
    local num2 = config.taskNumber[2] or 1
    --已经领取奖励,标记完成
    local PlotSystem = require("Module.Plot.PlotSystem")
    if missionData.completed then 
        missionData.DoneCount = missionData.AllCount
        return true 
    end
    missionData.DoneCount = missionData.mission_record_args[1] or 0
    if type == UIUtils.EOpenNeedType.DailyCopyCount then --10000 打%s次任意日常本
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            -- if self.GameInstance then
            -- local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            -- local find = false
            -- for i = 1, saveGameSpeak.MissionInfos:Length() do
            --     local MissionStr = saveGameSpeak.MissionInfos:Get(i)
            --     local array = string.split(MissionStr, '_')
            --     if #array >= 2 and tonumber(array[1]) == config.id then
            --         if tonumber(array[2]) >= missionData.AllCount then
            --             missionData.finished = true
            --             PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            --             break
            --         end
            --     end
            -- end
            -- end
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.SRPGDifficulty then --20008, --完成某难度的SRPG
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            --此任务不进剧情
        else
            print("------------------------recored difficuty:" .. tostring(missionData.mission_record_args[1]) .. ', num1:' .. tostring(num1))
            missionData.DoneCount = missionData.mission_record_args[1] or 0
            missionData.finished = missionData.DoneCount >= missionData.AllCount
        end
    elseif type == UIUtils.EOpenNeedType.CharLevel then --30000, --XX角色等级升至X级
        missionData.DoneCount = UIUtils.GetLevelByCharacterId(num1)
        print('---------->角色id:' .. tostring(num1) .. ',等级:' .. tostring(missionData.DoneCount))
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharSkillLv then --30001, --XX技能升至X级
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local lv = 1
        for _, v in pairs(characterInfo) do
            for _, skillInfo in ipairs(v.skill_infos) do
                if skillInfo.skill_id == num1 then
                    lv = skillInfo.skill_level
                    break
                end
            end
        end
        missionData.DoneCount = lv
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharLevelCount then --30002, --X名角色等级升至X级
        print('----------->charlevelcount' .. tostring(num1) .. ",level:" .. tostring(num2))
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local count = 0
        for _, v in pairs(characterInfo) do
            local character_level = UIUtils.GetCharacterLevel(v.character_id, v.break_times, v.exp)
            print('-->>charid:' .. tostring(v.character_id) .. ',lvl:' .. tostring(character_level))
            if character_level >= num2 then
                count = count + 1
                if count >= num1 then
                    break
                end
            end
        end
        print('----count:' .. tostring(count) .. ',all:' .. tostring(missionData.AllCount))
        missionData.DoneCount = count
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharSkillLvCount then --30003, --X名角色任意技能技能升至X
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local count = 0
        for _, v in pairs(characterInfo) do
            for _, skillInfo in ipairs(v.skill_infos) do
                if skillInfo.skill_level >= num2 then
                    count = count + 1
                    break
                end
            end
            if count >= num1 then
                break
            end
        end
        missionData.DoneCount = count
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharTalentCount then --30004 X名角色天赋点亮X个
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local count = 0
        for _, v in pairs(characterInfo) do
            if #v.talent_ids >= num2 then
                count = count + 1
                if count >= num1 then
                    break
                end
            end
        end
        missionData.DoneCount = count
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharWeaponLvCount then --30005 X件武器升至X级
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local count = 0
        for _, v in pairs(characterInfo) do
            local weapon_info = v.weapon_info
            local weapon_level = UIUtils.GetWeaponLevel(weapon_info.item_id, weapon_info.weapon_info.break_times, weapon_info.weapon_info.exp)
            if weapon_level >= num2 then
                count = count + 1
                if count >= num1 then
                    break
                end
            end
        end

        local weapon_infos = BackpackSystem:GetInstance():GetAllItemByMainType(UIUtils.ItemMainType.Weapon)
        for _, weapon_info in pairs(weapon_infos) do
            local weapon_level = UIUtils.GetWeaponLevel(weapon_info.item_id, weapon_info.weapon_info.break_times,
                weapon_info.weapon_info.exp)
            if weapon_level >= num2 then
                count = count + 1
                if count >= num1 then
                    break
                end
            end
        end
        missionData.DoneCount = count
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CharEquipLvCount then --30006 X件装备升至X级
        local characterInfo = CharacterSystem:GetInstance().CharacterInfo
        local count = 0
        for _, v in pairs(characterInfo) do
            if v.arm_infos then
                for _, arm_info in ipairs(v.arm_infos) do
                    local arm_level = UIUtils.GetEquipLevel(arm_info.item_id, arm_info.arm_info.break_times, arm_info.arm_info.exp)
                    if arm_level >= num2 then
                        count = count + 1
                        if count >= missionData.AllCount then
                            break
                        end
                    end
                end
            end
        end

        local equip_infos = BackpackSystem:GetInstance():GetAllItemByMainType(UIUtils.ItemMainType.Equip)
        for _, equip_info in pairs(equip_infos) do
            local arm_level = UIUtils.GetWeaponLevel(equip_info.item_id, equip_info.weapon_info.break_times,
                equip_info.weapon_info.exp)
            if arm_level >= num2 then
                count = count + 1
                if count >= missionData.AllCount then
                    break
                end
            end
        end

        missionData.DoneCount = count
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.Shopping then --30007 买若干个特定道具
        --config.taskNumber = { 18, 1 }
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.TotalWarFight --10001, 总力战完成X次
        or type == UIUtils.EOpenNeedType.BuildCountInUniverse --20001, --在宇宙进行%s次探索
        or type == UIUtils.EOpenNeedType.CostCountInUniverse --20002, --在宇宙进行%s次探索
        or type == UIUtils.EOpenNeedType.SRPGCount --20006, --进行X局SRPG
        or type == UIUtils.EOpenNeedType.BuildTargetCountInUniverse -- 20004, --在宇宙建造%s个带有「XX」词条的建筑
        or type == UIUtils.EOpenNeedType.BuildTraceCountInUniverse  -- 20005, --在宇宙建造%s个带有「XX」种族的建筑
        or type == UIUtils.EOpenNeedType.SRPGCardDemolition -- 20009, --在宇宙拆毁若干张卡牌
        or type == UIUtils.EOpenNeedType.SRPGCardUpgrade -- 20010， --在宇宙晋升若干张卡牌
        or type == UIUtils.EOpenNeedType.SRPGChangeCharacter -- 20011， --在宇宙替换%s次出场角色
        or type == UIUtils.EOpenNeedType.UnlockTalent --30008, --点亮一个星位
        or type == UIUtils.EOpenNeedType.ForgeCount --50001,--进行%s次装备锻造
        or type == UIUtils.EOpenNeedType.DecomposeCount --50002,--进行%s次熔炉拆解
        or type == UIUtils.EOpenNeedType.SyntheticCount --50007 --进行%s次熔炉合成
        or type == UIUtils.EOpenNeedType.SRPGGrowth --60010, --肉鸽局外养成加点x次
        or type == UIUtils.EOpenNeedType.Gacha then --60011, --抽卡次数
        
        -- if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
        --     if self.GameInstance then
        --         local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        --         local find = false
        --         for i = 1, saveGameSpeak.MissionInfos:Length() do
        --             local MissionStr = saveGameSpeak.MissionInfos:Get(i)
        --             local array = string.split(MissionStr, '_')
        --             if #array >= 2 and tonumber(array[1]) == config.id then
        --                 if tonumber(array[2]) >= num1 then
        --                     missionData.DoneCount = array[2]
        --                     missionData.finished = true
        --                     PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
        --                     break
        --                 end
        --             end
        --         end

        --         if not find then
        --             missionData.finished = false
        --         end
        --     end
        -- else
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
        -- end
    elseif type == UIUtils.EOpenNeedType.DiamondCount then --30009, --当单局结算后RMB钻超过N个
        missionData.DoneCount = UIUtils.GetDimond()
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.SpecifyShopping then --30010, --购买特定的商店的任意物品
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            -- if self.GameInstance then
            --     local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            --     local find = false
            --     for i = 1, saveGameSpeak.MissionInfos:Length() do
            --         local MissionStr = saveGameSpeak.MissionInfos:Get(i)
            --         local array = string.split(MissionStr, '_')
            --         if #array >= 3 then
            --             if tonumber(array[1]) == config.id and tonumber(array[2]) == config.taskNumber[1] then 
            --                 missionData.DoneCount = tonumber(array[3])
            --                 if tonumber(array[3]) >= config.taskNumber[2] then
            --                     missionData.finished = true
            --                     PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            --                     break
            --                 end
            --             end
            --         end
            --     end
            -- end 
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.RewardBook then --50006,--完成若干个任务
        local completeCount = 0
        for i = 1, #config.taskNumber do 
            local taskId = config.taskNumber[i]
            local taskData = QuestSystem.QuestBookInfo[taskId]
            --任务册任务是否领取
            if taskData and (taskData.completed) then
                completeCount = completeCount + 1
            end
        end
        missionData.DoneCount = completeCount
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CompletedDailyMission then --50008,--完成若干个日常任务
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            -- if self.GameInstance then
            --     local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            --     local find = false
            --     for i = 1, saveGameSpeak.MissionInfos:Length() do
            --         local MissionStr = saveGameSpeak.MissionInfos:Get(i)
            --         local array = string.split(MissionStr, '_')
            --         if #array >= 2 and tonumber(array[1]) == config.id then
            --             missionData.DoneCount = tonumber(array[2])
            --             if tonumber(array[2]) >= missionData.AllCount then
            --                 missionData.finished = true
            --                 PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            --                 break
            --             end
            --         end
            --     end
            -- end
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.PlayerLevel then --60002 --玩家等级大于等于某等级
        local PlayerSystem = require('Module.Player.PlayerSystem')
        missionData.DoneCount = PlayerSystem:GetInstance().Level
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial then
            if missionData.finished then
                PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
            end
        end
    elseif type == UIUtils.EOpenNeedType.CompleteFight  --60003 --完成某场战斗
        or type == UIUtils.EOpenNeedType.CompleteUniverseTrip --60004, --完成某段宇宙航行
        or type == UIUtils.EOpenNeedType.CompleteSpecialSRPG --60005, --完成某个剧情星图
        or type == UIUtils.EOpenNeedType.STTButton   --60007 --点击特定按钮
        or type == UIUtils.EOpenNeedType.BuildActor  --60008,--完成家具交互
        or type == UIUtils.EOpenNeedType.OpenUI then --60009,--打开某个ui/系统连接 
        if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) then
            if self.GameInstance then
                local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
                -- local find = false
                for i = 1, saveGameSpeak.MissionInfos:Length() do
                    local MissionStr = saveGameSpeak.MissionInfos:Get(i)
                    local array = string.split(MissionStr, '_')
                    if #array >= 2 and tonumber(array[1]) == config.id and tonumber(array[2]) == config.taskNumber[1] and not missionData.finished then
                        missionData.finished = true
                        PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
                        break
                    end
                end

                -- if not find then
                --     missionData.finished = false
                -- end
            end
        end
    elseif type == UIUtils.EOpenNeedType.BuildCreate then
        missionData.finished = missionData.DoneCount >= missionData.AllCount
        if missionData.finished then
            PlotSystem:GetInstance():OnCompletedStoryTask(config.id)
        end
    else
        missionData.finished = missionData.DoneCount >= missionData.AllCount
    end
    return missionData.finished or false
end

function QuestSystem:FinishAllStoryMission()
    local d_task = require("ClientDatas.d_task")
    for k, v in pairs(QuestSystem.QuestInfo) do
        local config = d_task[v.mission_id]
        if not config then
            config = Database.Query('d_task_story', v.mission_id)
        end
        if config and (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) then
            LOG_DEBUG_TRACKBACK('---->FinishAllStoryMission:' .. tostring(k))
            QuestSystem.QuestInfo[k] = nil
        end
    end
end

---记录信息(打点信息)
function QuestSystem:InternalAddMissionRecord(missionData, type, config, addRecordArg, extraArg)
    -- DailyCopyCount = 10000, --打%s次任意日常本
    -- TotalWarFight = 10001, --总力战完成X次
    -- TowerCopyId = 10002, --对战塔到达X层
    -- CopyFinishCount = 10003, --副本关累计获得X次胜利
    -- FightCountInUniverse = 20000, --在宇宙进行%s次战斗
    -- BuildCountInUniverse = 20001, --在宇宙建造%s个建筑
    -- CostCountInUniverse = 20002, --在宇宙消耗%s燃料
    -- BuyCountInUniverse = 20003, --在宇宙购买%s次建筑
    -- BuildTargetCountInUniverse = 20004, --在宇宙建造%s个带有「XX」词条的建筑
    -- BuildTraceCountInUniverse = 20005, --在宇宙建造%s个带有「XX」种族的建筑
    -- SRPGCount = 20006, --进行X局SRPG
    -- SRPGRecord = 20007, --单局积分到达X
    -- SRPGDifficulty = 20008, --完成某难度的SRPG
    -- SRPGCardDemolition = 20009, --在宇宙拆毁若干张卡牌
    -- SRPGCardUpgrade = 20010， --在宇宙晋升若干张卡牌
    -- SRPGChangeCharacter = 20011， --在宇宙替换%s次出场角色
    -- CharLevel = 30000, --XX角色等级升至X级
    -- CharSkillLv = 30001, --XX技能升至X级
    -- CharLevelCount = 30002, --X名角色等级升至X级
    -- CharSkillLvCount = 30003, --X名角色任意技能技能升至X
    -- CharTalentCount = 30004, --X名角色天赋点亮X个
    -- CharWeaponLvCount = 30005, --X件武器升至X级
    -- CharEquipLvCount = 30006, --X件装备升至X级
    -- Shopping = 30007, 买若干个特定道具
    -- UnlockTalent = 30008, --点亮一个星位
    -- MainQuestChapter = 40000,--主线剧情完成X章X节
    -- ForgeCount = 50001,--进行%s次装备锻造
    -- DecomposeCount = 50002,--进行%s次熔炉拆解
    -- Login = 50003,--登录游戏
    -- CostItem = 50004, --【消耗条件区别于检测条件】消耗%s道具（含金币）
    -- HaveChar = 50005, --拥有某角色
    -- RewardBook = 50006,--完成若干个任务
    -- SyntheticCount = 50007 --进行%s次熔炉合成
    -- CompletedDailyMission = 50008 --完成若干个日常任务
    -- PlayerLevel = 60002 --玩家等级大于等于某等级
    -- CompleteFight = 60003, --完成某场战斗
    -- CompleteUniverseTrip = 60004, --完成某段宇宙航行
    -- CompleteSpecialSRPG = 60005, --完成某个剧情星图
    -- SelectPanel = 60006, --在剧情选择界面完成剧情跳转
    -- STTButton = 60007， --点击特定按钮

    local num1 = config.taskNumber[1] or 1
    local num2 = config.taskNumber[2] or 1

    if type == UIUtils.EOpenNeedType.DailyCopyCount then --10000 打%s次任意日常本
        -- if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) then
        --     if self.GameInstance then
        --         local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        --         local find = false
        --         local count = 0
        --         for i = 1, saveGameSpeak.MissionInfos:Length() do
        --             local MissionStr = saveGameSpeak.MissionInfos:Get(i)
        --             local array = string.split(MissionStr, '_')
        --             if #array >= 2 and tonumber(array[1]) == config.id then
        --                 count = count + tonumber(array[2]) + 1
        --                 saveGameSpeak.MissionInfos:Set(i, tostring(config.id .. "_" .. count))
        --                 self.GameInstance:LoadSaveGameSpeak()
        --                 find = true
        --                 break
        --             end
        --         end

        --         if not find then
        --             count = count + 1
        --             saveGameSpeak.MissionInfos:Add(tostring(config.id .. "_" .. count))
        --             self.GameInstance:SaveSaveGameSpeak()
        --         end
        --     end
        -- end
        missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + 1
    elseif type == UIUtils.EOpenNeedType.Shopping then --30007 买若干个道具
        --addRecordArg[1]:item_id addRecordArg[2]:购买数量
        -- if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) and addRecordArg[2] then
        --     if self.GameInstance then
        --         local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
        --         local find = false
        --         local count = 0
        --         for i = 1, saveGameSpeak.MissionInfos:Length() do
        --             local MissionStr = saveGameSpeak.MissionInfos:Get(i)
        --             local array = string.split(MissionStr, '_')
        --             if #array >= 2 and tonumber(array[1]) == config.id then
        --                 count = count + tonumber(array[2]) + addRecordArg[2]
        --                 saveGameSpeak.MissionInfos:Set(i, tostring(config.id .. "_" .. count))
        --                 self.GameInstance:LoadSaveGameSpeak()
        --                 find = true
        --                 break
        --             end
        --         end

        --         if not find then
        --             count = count + addRecordArg[2]
        --             saveGameSpeak.MissionInfos:Add(tostring(config.id .. "_" .. count))
        --             self.GameInstance:SaveSaveGameSpeak()
        --         end
        --     end
        -- end
        missionData.mission_record_args[2] = (missionData.mission_record_args[2] or 0) + addRecordArg[1]
    elseif type == UIUtils.EOpenNeedType.SRPGDifficulty then --20008, --完成某难度SRPG
        if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) and addRecordArg[1] then
            --此任务不进剧情
        else
            local difficulty = config.taskNumber[1]
            if addRecordArg[1] >= difficulty then
                missionData.mission_record_args[1] = 1
            end
            -- missionData.mission_record_args[1] = addRecordArg[1]
        end
    elseif type == UIUtils.EOpenNeedType.TotalWarFight --10001, 总力战完成X次
        or type == UIUtils.EOpenNeedType.BuildCountInUniverse --20001, --在宇宙建造%s个建筑
        or type == UIUtils.EOpenNeedType.CostCountInUniverse --20002, --在宇宙进行%s次探索
        or type == UIUtils.EOpenNeedType.SRPGCount --20006, --进行X局SRPG
        -- or type == UIUtils.EOpenNeedType.BuildTargetCountInUniverse -- 20004, --在宇宙建造%s个带有「XX」词条的建筑
        -- or type == UIUtils.EOpenNeedType.BuildTraceCountInUniverse  -- 20005, --在宇宙建造%s个带有「XX」种族的建筑
        or type == UIUtils.EOpenNeedType.SRPGCardDemolition -- 20009, --在宇宙拆毁若干张卡牌
        or type == UIUtils.EOpenNeedType.SRPGCardUpgrade -- 20010， --在宇宙晋升若干张卡牌
        or type == UIUtils.EOpenNeedType.SRPGChangeCharacter -- 20011， --在宇宙替换%s次出场角色
        or type == UIUtils.EOpenNeedType.UnlockTalent --30008, --点亮一个星位
        or type == UIUtils.EOpenNeedType.ForgeCount --50001,--进行%s次装备锻造
        or type == UIUtils.EOpenNeedType.DecomposeCount --50002,--进行%s次熔炉拆解
        or type == UIUtils.EOpenNeedType.SyntheticCount --50007 --进行%s次熔炉合成
        or type == UIUtils.EOpenNeedType.SRPGGrowth --60010, --肉鸽局外养成加点x次
        or type == UIUtils.EOpenNeedType.Gacha then --60011, --抽卡次数
        missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + addRecordArg[1]
    elseif type == UIUtils.EOpenNeedType.SpecifyShopping then --30010, --购买特定的商店的任意物品
        if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) and addRecordArg[1] then
            if addRecordArg[1] == config.taskNumber[1] and addRecordArg[3] then
                missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + addRecordArg[3]
            end
            -- if self.GameInstance then
            --     local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
            --     local find = false
            --     local count = 0
            --     local shop_id = addRecordArg[1]
            --     for i = 1, saveGameSpeak.MissionInfos:Length() do
            --         local MissionStr = saveGameSpeak.MissionInfos:Get(i)
            --         local array = string.split(MissionStr, '_')
            --         if #array >= 3 and tonumber(array[1]) == config.id and tonumber(array[2]) == shop_id then
            --             count = count + tonumber(array[3]) + addRecordArg[3]
                        
            --             saveGameSpeak.MissionInfos:Set(i, tostring(config.id .. "_" .. count))
            --             self.GameInstance:LoadSaveGameSpeak()
            --             find = true
            --             break
            --         end
            --     end

            --     if not find then
            --         count = count + addRecordArg[3]
            --         saveGameSpeak.MissionInfos:Add(tostring(config.id .. "_" .. shop_id .. "_" .. count))
            --         self.GameInstance:SaveSaveGameSpeak()
            --     end
            -- end
        end
    elseif type == UIUtils.EOpenNeedType.RewardBook then --50006,--完成若干个任务
        -- local completeCount = 0
        -- for i = 1, #config.taskNumber do 
        --     local taskId = config.taskNumber[i]
        --     --任务册任务是否完成
        --     if true then
        --         completeCount = completeCount + 1
        --     end
        -- end
        -- missionData.mission_record_args[1] = completeCount
    elseif type == UIUtils.EOpenNeedType.CompletedDailyMission then --50008,--完成若干个日常任务
        missionData.AllCount = num1
        missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + (addRecordArg[1] or 1)
    elseif type == UIUtils.EOpenNeedType.PlayerLevel then --30000
        local PlayerSystem = require('Module.Player.PlayerSystem')
        missionData.mission_record_args[1] = PlayerSystem:GetInstance().Level
    elseif type == UIUtils.EOpenNeedType.CompleteFight  --60003 --完成某场战斗
        or type == UIUtils.EOpenNeedType.CompleteUniverseTrip --60004, --完成某段宇宙航行
        or type == UIUtils.EOpenNeedType.CompleteSpecialSRPG --60005, --完成某个剧情星图
        or type == UIUtils.EOpenNeedType.STTButton  --60007 --点击特定按钮
        or type == UIUtils.EOpenNeedType.BuildActor  --60008,--完成家具交互
        or type == UIUtils.EOpenNeedType.OpenUI then --60009,--打开某个ui/系统连接 
            LOG_DEBUG_TRACKBACK("InternalAddMissionRecord", type, config.taskType, addRecordArg[1], self.GameInstance, table.dump(missionData))
            if self.GameInstance then
                local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
                for i = 1, saveGameSpeak.MissionInfos:Length() do
                    local MissionStr = saveGameSpeak.MissionInfos:Get(i)
                    LOG_DEBUG("MissionStr:", MissionStr)
                end
            end
        if (config.taskType == UIUtils.ETaskType.Main or config.taskType == UIUtils.ETaskType.Tutorial) and addRecordArg[1] then
            if self.GameInstance then
                local saveGameSpeak = self.GameInstance:LoadSaveGameSpeak()
                local find = false
                local fight_id = addRecordArg[1]
                for i = 1, saveGameSpeak.MissionInfos:Length() do
                    local MissionStr = saveGameSpeak.MissionInfos:Get(i)
                    local array = string.split(MissionStr, '_')
                    if #array >= 2 and tonumber(array[1]) == config.id and tonumber(array[2]) == fight_id then
                        find = true
                        break
                    end
                end

                if not find then
                    print('---->fight_id:' .. tostring(fight_id))
                    saveGameSpeak.MissionInfos:Add(tostring(config.id .. "_" .. fight_id))
                    self.GameInstance:SaveSaveGameSpeak()
                end
            end
        end
    elseif type == UIUtils.EOpenNeedType.BuildCreate then
        missionData.AllCount = 1
        if config.taskNumber[1] == addRecordArg[1] then
            missionData.mission_record_args[1] = 1
        end
    else
        if extraArg then
            if config and #config.taskNumber > 1 then
                local param = config.taskNumber[2]
                local bFind = false
                for _, value in ipairs(extraArg) do
                    if value == param then 
                        bFind = true
                        break
                    end
                end
                if bFind then
                    missionData.AllCount = num2
                    missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + (addRecordArg[1] or 1)
                    return
                else
                    return
                end
            end
        end
        addRecordArg = addRecordArg or {}
        missionData.mission_record_args[1] = (missionData.mission_record_args[1] or 0) + (addRecordArg[1] or 1)
    end
end

function QuestSystem:AddMissionRecord(type, addRecordArg, extraArg)
    LOG_DEBUG_TRACKBACK("------->addMissionRecord:", type)
    print('----questinfo:' .. tostring(table.dump(QuestSystem.QuestInfo, nil, 10)))
    --日常任务
    for qId, v in pairs(QuestSystem.QuestInfo) do
        local config = self:GetTaskConfigById(qId)
        print("------->qId:" .. tostring(qId) .. ",qid:" .. tostring(config))
        if config and config.taskContent == type then
            print("------->addMissionRecord:" .. tostring(type) .. ",qid:" .. tostring(qId))
            self:InternalAddMissionRecord(v, type, config, addRecordArg, extraArg)
            self:CheckMissionFinished(v, config.taskContent, config)
            if config.taskType == UIUtils.ETaskType.Daily and not v.completed and v.finished then
                RedPointSystem:AddRecord('UI_City.UI_CityMenu.UI_DailyQuest', v.mission_id)
            end
        end
    end
    --奖励册任务
    for qId, v in pairs(QuestSystem.QuestBookInfo) do 
        local config = Database.Query('d_task_book', qId)
        if config and config.taskContent == type then
            self:InternalAddMissionRecord(v, type, config, addRecordArg, extraArg)
            self:CheckMissionFinished(v, config.taskContent, config)
            if not v.completed and v.finished then
                RedPointSystem:GetInstance():AddRecord('UI_City.UI_CityMenu.UI_RewardBook', v.mission_id)
            end
        end
    end
    --self:CheckAllMissionState()
    -- self:CheckAllBookMissionState()
    MessageManager:GetInstance():Broadcast('OnMsg_MissionRecord')
end

function QuestSystem:IsExploreBlocked()
    for _, quest in pairs(QuestSystem.QuestInfo) do
        local config = Database.Query('d_task_story', quest.mission_id)

        if config then
            if not quest.completed and config.unExplore == 1 then
                return true
            end
        end
    end

    return false
end

function QuestSystem:IsDemolitionBlocked()
    for _, quest in pairs(QuestSystem.QuestInfo) do
        if quest.mission_id > 10000 then
            local config = Database.Query('d_task_story', quest.mission_id)

            if config then
                if not quest.completed and config.unDemolition == 1 then
                    return true
                end
            end
        end
    end

    return false
end

---------------------------------------------------------------------------------------------------------
---监听其他接口
function QuestSystem:OnMsg_SRPG_NextTurn()
    --在宇宙进行探索
    self:AddMissionRecord(UIUtils.EOpenNeedType.CostCountInUniverse, { 1 })
end

--消耗道具处理
function QuestSystem:OnNetCmd_Ntf_Item_Info(result, msgId, parsed_msg)
    if result == 0 and
        parsed_msg and 
        parsed_msg.ntf_item_info and 
        parsed_msg.ntf_item_info.changed_item_infos then
        for _, changedItemInfo in ipairs(parsed_msg.ntf_item_info.changed_item_infos) do
            local bagConfig = UIUtils.GetItemConfigById(changedItemInfo.item_id)
            --金币
            if bagConfig.itemType == UIUtils.ItemMainType.Currency and bagConfig.subType == UIUtils.ItemCurrencyType.Gold then
                if changedItemInfo.count < 0 then
                    self:AddMissionRecord(UIUtils.EOpenNeedType.CostGold, { -changedItemInfo.count })
                end
            end
        end
    end
end

function QuestSystem:OnMsg_Place_Card(cardId)
    LOG_ERROR('--->OnMsg_Place_Card:' .. tostring(cardId))
    if cardId then
        local cardConfig = Database.Query("d_srpg_card_base", cardId)
        self:AddMissionRecord(UIUtils.EOpenNeedType.BuildCountInUniverse, {1})
        LOG_ERROR('--->keywords:' .. tostring(table.dump(cardConfig.keywords, nil, 10)))
        --关键词卡牌
        if #cardConfig.keywords > 0 then
            self:AddMissionRecord(UIUtils.EOpenNeedType.BuildTargetCountInUniverse, { 1 }, cardConfig.keywords)
        end
        LOG_ERROR('--->race:' .. tostring(table.dump(cardConfig.race, nil, 10)))
        --种族类卡牌
        if #cardConfig.race > 0 then
            self:AddMissionRecord(UIUtils.EOpenNeedType.BuildTraceCountInUniverse, { 1 }, cardConfig.race)
        end
    end
end

function QuestSystem:OnMsg_Demolition_Card()
    self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGCardDemolition, { 1 })
end

function QuestSystem:OnMsg_Upgrade_Card()
    self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGCardUpgrade, { 1 })
end

function QuestSystem:OnMsg_Universe_Growth()
    self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGGrowth, { 1 })
end

function QuestSystem:OnMsg_Gacha(times)
    self:AddMissionRecord(UIUtils.EOpenNeedType.Gacha, { times })
end

function QuestSystem:OnMsg_Complete_Total_War_Fight()
    self:AddMissionRecord(UIUtils.EOpenNeedType.TotalWarFight, { 1 })
end

function QuestSystem:OnMsg_Change_Character()
    self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGChangeCharacter, { 1 })
end

function QuestSystem:OnMsg_Shop_Buy(msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.Shopping, { msg.shop_item_id, msg.shop_item_count })
    self:AddMissionRecord(UIUtils.EOpenNeedType.SpecifyShopping, { msg.shop_id, msg.shop_item_id, msg.shop_item_count })
end

function QuestSystem:OnMsg_STT_Button(msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.STTButton, { msg.task_id })
end

function QuestSystem:OnMsg_Item_Synthetic(msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.SyntheticCount, { msg.count })
end

function QuestSystem:OnMsg_Item_Decompose(msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.DecomposeCount, { #msg.item_uuids })
end

function QuestSystem:OnMsg_Complete_TempFight(fight_id)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CompleteFight, { fight_id })
end

function QuestSystem:OnMsg_Complete_UniverseFly(map_id)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CompleteUniverseTrip, { map_id })
end

function QuestSystem:OnMsg_Req_Character_Level_Up_Success(result, msgId, parsed_msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CharLevel)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CharLevelCount)
end

function QuestSystem:OnMsg_Req_Strengthen_Weapon_Success(result, msgId, parsed_msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CharWeaponLvCount)
end

function QuestSystem:OnMsg_Item_Forge(itemList)
    self:AddMissionRecord(UIUtils.EOpenNeedType.ForgeCount, { itemList.count })
end

function QuestSystem:OnMsg_Req_Character_Talent_Active_Success(result, msgId, parsed_msg)
    self:AddMissionRecord(UIUtils.EOpenNeedType.UnlockTalent, { 1 })
end

function QuestSystem:OnNetCmd_res_daily_level_sweep(result, msgId, parsed_msg)
    if result == 0 then
        self:AddMissionRecord(UIUtils.EOpenNeedType.DailyCopyCount)
    end
end

function QuestSystem:OnMsg_Req_Character_Skill_Level_Up_Success(param)
    self:AddMissionRecord(UIUtils.EOpenNeedType.CharSkillLv, nil, param) --XX技能升到x级
    self:AddMissionRecord(UIUtils.EOpenNeedType.CharSkillLvCount, nil, param) --x个角色任意技能升到x级
end

QuestSystem[SrpgController.GameEnded] = function(self, reason, difficulty, mapType, mapId)
    -- print('--------game end:' .. tostring(difficulty))
    LOG_DEBUG_TRACKBACK("--------game end:", reason, difficulty, mapType, mapId)
    if not mapType or mapType == 0 then
        if reason == SrpgModel.EndReason.Clear or reason == SrpgModel.EndReason.Abort then
            LOG_DEBUG_TRACKBACK("--------CompleteSpecialSRPG:")
            --Specific Srpg
            self:AddMissionRecord(UIUtils.EOpenNeedType.CompleteSpecialSRPG, { mapId }) --60005 --完成某个剧情星图
        end
    else
        if reason == SrpgModel.EndReason.Clear then
            LOG_DEBUG_TRACKBACK("--------SRPGCount:")
            self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGCount, { 1 })
            self:AddMissionRecord(UIUtils.EOpenNeedType.SRPGDifficulty, { difficulty }) --20008 完成某难度的SRPG
        end
    end
end

-- QuestSystem[SrpgController.SpecificGameEnded] = function(self, reason)
--     print('--------specific game end:')
--     if reason == SrpgModel.EndReason.Clear then
--         self:AddMissionRecord(UIUtils.EOpenNeedType.CompleteSpecialSRPG, { 1 }) --20008 完成某难度的SRPG
--     end
-- end

function QuestSystem:OnMsg_Player_Exp_Changed()
    self:AddMissionRecord(UIUtils.EOpenNeedType.PlayerLevel, {1}) --XX技能升到x级
end

-- function QuestSystem:OnMsg_Player_LevelUp(oldLevel, newLevel)
--     self:AddMissionRecord(UIUtils.EOpenNeedType.PlayerLevel, {1}) --XX技能升到x级
-- end

function QuestSystem:OnComplete_Plot_Mission(mission_id)
    if mission_id > 0 then
        if self.QuestInfo[mission_id] then
            self.QuestInfo[mission_id].completed = true
            self.QuestInfo[mission_id].finished = true
        end
    end
    MessageManager:GetInstance():Broadcast("OnMsg_Refresh_Plot_Mission", mission_id)
end

--摆放家具事件
function QuestSystem:OnMsg_BuildCreate(buildId)
    self:AddMissionRecord(UIUtils.EOpenNeedType.BuildCreate, { buildId }) --XX技能升到x级
end

--家具交互事件
function QuestSystem:OnMsg_InteractionBuildActor(buildActorId)
    self:AddMissionRecord(UIUtils.EOpenNeedType.BuildActor, { buildActorId }) --XX技能升到x级
end

--打开ui 
function QuestSystem:OnMsg_InteractionOpenUI(id)
    self:AddMissionRecord(UIUtils.EOpenNeedType.OpenUI, { id }) --XX技能升到x级
end

return QuestSystem

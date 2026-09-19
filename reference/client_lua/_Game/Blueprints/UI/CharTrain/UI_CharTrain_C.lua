
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local HardLevelSystem = require "Module.HardLevel.HardLevelSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local PlayerSystem = require("Module.Player.PlayerSystem")
local datetime = require('_Game.Utils.datetime')

---@type UI_CharTrain_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitUI()
    self:InitData()

end

function M:Destruct()
  
end

function M:InitUI()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not controller.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitBlock = true
    end

    self.Btn_Quit.OnGHSClicked:Add(self, self.OnClicked_Btn_Quit)
    self.Btn_Left.OnGHSClicked:Add(self, self.OnClicked_Btn_Left)
    self.Btn_Right.OnGHSClicked:Add(self, self.OnClicked_Btn_Right)

    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)

    self['UI_CharTrainItem1'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter1)
    self['UI_CharTrainItem2'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter2)
    self['UI_CharTrainItem3'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter3)
    self['UI_CharTrainItem4'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter4)

    self.Btn_Fight.OnGHSClicked:Add(self, self.OnClicked_Btn_Fight)
end

function M:InitData()
    self.LastPassLevelId = self:InitActivityInfo(true)

    local hasQuest = false
    --判断任务100011101 100030007 教室任务
    local QuestSystem = require("Module.Quest.QuestSystem")
    local QuestInfo = QuestSystem:GetInstance():GetQuestInfo(100011101)
    if QuestInfo or (QuestInfo and (not QuestInfo.completed or not QuestInfo.finished)) then
        hasQuest = true
    end
    QuestInfo = QuestSystem:GetInstance():GetQuestInfo(100030007)
    if QuestInfo or (QuestInfo and (not QuestInfo.completed or not QuestInfo.finished)) then
        hasQuest = true
    end

    if hasQuest then
        self.SelectedTabIndex = 1
    end
    self:RefreshMainUI(true)
end

function M:InitActivityInfo(isInit)
    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    local copyInfo = HardLevelSystem:GetInstance().HardLevelInfos
    local starList = copyInfo.stars
    print("==starList:" .. tostring(table.dump(starList or {}, false, 10)))

    local pageList = {}
    for _, config in pairs(d_levels_challenge) do
        if config.levelTypes == UIUtils.ECopyType.ECopyType_Train then
            if not pageList[config.page] then 
                pageList[config.page] = {}
            end
        
            table.insert(pageList[config.page], config.id)
        end
    end

    if #pageList > 0 then
        for _, lvs in pairs(pageList) do
            if #lvs > 1 then
                table.sort(lvs, function(a, b)
                    return a < b
                end)
            end
        end
    end

    local lastPastLv = -1 
    local lastTab = -1
    for pageIdx, lvs in pairs(pageList) do
        local starInfo = {}
        for idx, lv in ipairs(lvs) do 
            if not starInfo[pageIdx] then starInfo[pageIdx] = {} end
            local startIdx = (lv - 1) * 3 + 1
            local endIdx = lv * 3
            local starNum = 0
            for i = startIdx, endIdx do 
                --table.insert(starTab, starList[i] or false)
                local isFinished = starList[i] or false
                if isFinished then
                    starNum = starNum + 1
                end
            end
            if lastPastLv <= 0 then
                lastPastLv = lv - 1
                lastTab = pageIdx
            end
            if starNum > 0 then
                lastPastLv = math.max(lastPastLv, lv)
                if lastPastLv == lv then
                    lastTab = pageIdx
                end
            end
        end
    end

    if isInit then
        self.SelectedTabIndex = lastTab
        self.SelectedLevelIndex = 1
        self.TabMax = #pageList
    end
  
    return lastPastLv
end

function M:GetPassedLvId()

end 

function M:GetChallengeCopyList(index)
    local passed_level_id = self.LastPassLevelId

    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    local result = {}
    local copyInfo = HardLevelSystem:GetInstance().HardLevelInfos
    local starList = copyInfo.stars

    for idx, config in ipairs(d_levels_challenge) do
        if config.levelTypes == UIUtils.ECopyType.ECopyType_Train then
            if config.page == index then 
                local starTab = {}
                local startIdx = (idx - 1) * 3 + 1
                local endIdx = idx * 3
                for i = startIdx, endIdx do 
                    table.insert(starTab, starList[i] or false)
                end
                local copy = {
                    activity_id = config.id,
                    stars = starTab,
                    unlock = config.id <= (passed_level_id + 1)
                }
                table.insert(result, copy)
            end
        end
    end

    if #result > 1 then
        table.sort(result, function(a, b)
            return a.activity_id < b.activity_id
        end)
    end

    return result
end

function M:RefreshUI(args)
    if args and args ~= '' then
        local argTab = string.split(args, '|')
        local tabIdx = tonumber(argTab[1])
        -- local levelIdx = tonumber(argTab[2])
        self.SelectedTabIndex = tabIdx
        self:RefreshMainUI(true)
        --self:RefreshChapterUI(levelIdx)
    end
end

function M:RefreshCharacterId(charId)
    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    for idx, config in ipairs(d_levels_challenge) do
        if config.levelTypes == UIUtils.ECopyType.ECopyType_Train then
            if config.characterTrial and #config.characterTrial > 0 then
                for _, trainCharId in ipairs(config.characterTrial) do
                    if trainCharId > 1 then
                        local d_character_trial = require('ClientDatas.d_character_trial')
                        local trailConfig = d_character_trial[trainCharId]
                        if trailConfig and trailConfig.roleTrialId then
                            if tonumber(trailConfig.roleTrialId) == charId then
                                self.SelectedTabIndex = config.page
                                self:RefreshMainUI(true)
                                --跳转二级ui
                                if self.CurCopyList then
                                    for index, value in ipairs(self.CurCopyList) do
                                        if value.activity_id == config.id then
                                            self:RefreshChapterUI(index)
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function M:RefreshMainUI(bInit)
    self.Panel_Main:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.Panel_Sub:SetVisibility(UE.ESlateVisibility.Hidden)

    self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.Panel_SubExit:SetVisibility(UE.ESlateVisibility.Hidden)

    self.Btn_Left:SetIsEnabled(true)
    self.Btn_Right:SetIsEnabled(true)

    if not self.CurCopyList then
        self.CurCopyList = self:GetChallengeCopyList(self.SelectedTabIndex)
    end

    self.Btn_Left:SetVisibility(self.SelectedTabIndex == 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_Right:SetVisibility(self.SelectedTabIndex == self.TabMax and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)

    --从活动表获取活动id为2的活动配置的时间
    local config = Database.Query("d_activity", 2)
    local startTime = datetime.str_to_time(config.showTime)
    local endTime = datetime.str_to_time(config.closeTime)
    local timeLeft = endTime - PlayerSystem:GetInstance():GetServerTime()

    self.Text_LeftTime:SetText(datetime.format_time(timeLeft))
    self.Text_StartTime:SetText(string.format("%s - %s", datetime.formate_date(startTime - 14401), datetime.formate_date(endTime - 14401)))

    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        local copyInfo = self.CurCopyList[idx]
        if ui then
            if copyInfo then
                ui:SetRenderOpacity(1)
                self:RefreshLevel(ui, copyInfo)
                if bInit then
                    ui:PlayIn()
                end
            else
                ui:SetRenderOpacity(0)
            end
        end
    end
    -- for idx, copyInfo in ipairs(self.CurCopyList) do 
    --     self:RefreshLevel(self['UI_CharTrainItem' .. idx], copyInfo)
    -- end
    --副本名字
    -- self.Text_CopyName:SetText(Database.L10n(286))
end

function M:RefreshChapterUI(levelIndex)
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        local newCopyInfo = self.CurCopyList[idx]
        if ui then
            if newCopyInfo then
                ui:PlayAnimationForward(ui.deactive)
            end
        end
    end
    self.Panel_SubExit:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.Hidden)

    self:PlayAnimationForward(self.DetailIn)

    self.SelectedLevelIndex = levelIndex
    local copyInfo = self.CurCopyList[levelIndex]
    local config = Database.Query('d_levels_challenge', copyInfo.activity_id)

    self.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Sub:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

    --章节名
    self.Text_Chapter:SetText(Database.L10n(config.levelName))
    self.Text_Chapter_1:SetText("")

    --目标
    for i = 1, 3 do
        local bStar = copyInfo.stars[i] or false
        local ui = self['UI_ChallengeTarget' .. i]
        local target = config.target[i]
        local param = config.targetNumber[i] or ''
        if ui then
            if target then
                ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                local str = Database.L10n(target)
                local textStr = string.format(str, param, 0, 0, 0)
                ui.Txt_Black:SetText(textStr)
                ui.Txt_White:SetText(textStr)
                ui.Txt_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
                ui.Img_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            else
                ui:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
    end

    --奖励
    self.UI_Reward1.Text_Index:SetText('1')
    self.UI_Reward2.Text_Index:SetText('2')
    self.UI_Reward3.Text_Index:SetText('3')
    local starNum = 0
    for i = 1, 3 do 
        if copyInfo.stars[i] then
            starNum = starNum + 1
        end
    end

    local rewardList = {}
    for i = 1, #config.reward1, 3 do 
        local itemId = config.reward1[i]
        local count = config.reward1[i + 2]
        table.insert(rewardList, {
            itemId = itemId,
            count = count,
        })
    end
    for i = 1, 3 do 
        local ui = self['UI_Reward' .. i]
        local reward = config['reward' .. i]
        if ui then
            if reward and #reward > 0 then
                ui:SetVisibility(UE.ESlateVisibility.visible)
                self:RefreshReward(ui, reward, i <= starNum)
                if i > 1 then
                    local img_tag = self['Img_Tag' .. i]
                    if img_tag then
                        img_tag:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    end
                end
            else
                ui:SetVisibility(UE.ESlateVisibility.Collapsed)
                if i > 1 then
                    local img_tag = self['Img_Tag' .. i]
                    if img_tag then
                        img_tag:SetVisibility(UE.ESlateVisibility.Hidden)
                    end
                end
            end
        end
    end

    local isSwitch = config.switch > 0
    self.Panel_Des:SetVisibility(isSwitch and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    if isSwitch then
        self.Txt_White:SetText(UIUtils.GetSwitchText(config.switch))
    end

    -- self.Btn_Fight:SetIsEnabled(copyInfo.unlock)
end

function M:RefreshLevel(ui, copyInfo)
    print("=====RefreshLevel:" .. tostring(table.dump(copyInfo, nil, 10)))
    if ui then
        local config = Database.Query('d_levels_challenge', copyInfo.activity_id)
        -- ui.Text_Lock:SetText(Database.L10n(config.levelName))
        ui.UI_CharTrainName.Text_Unlock:SetText(Database.L10n(config.levelName))

        --headicon
        if config.pathIcon and config.pathIcon ~= '' then
            local itemRarityPic = LoadObject(config.pathIcon)
            if itemRarityPic then
                ui.CharIcon:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        for idx = 1, 3 do
            local bStar = copyInfo.stars[idx] or false
            local starImg = ui['Img_White' .. idx]
            if starImg then
                starImg:SetVisibility(UE.ESlateVisibility.Hidden)
            end
            if bStar then
                if starImg then
                    starImg:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                end
            end
        end
        local bUnlock = copyInfo.unlock
        -- ui.Panel_Lock:SetVisibility(bUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        -- ui.Panel_Unlock:SetVisibility(bUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshReward(ui, reward, bGot)
    ui.HBox_Reward:ClearChildren()
    for i = 1, #reward, 3 do 
        local itemId = reward[i]
        local itemCount = reward[i + 2]

        local itemConfig = UIUtils.GetItemConfigById(itemId)

        local itemUI = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
        itemUI.TextName:SetText(Database.L10n(itemConfig.itemName))
        itemUI.TextNum:SetText(itemCount)
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                itemUI.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end

        --icon
        if itemConfig.iconPath and itemConfig.iconPath ~= '' then
            local strArr = string.split(itemConfig.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                itemUI.icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end

        itemUI.ItemPanel:SetRenderOpacity(1)
        --领取类型
        itemUI.Img_bg.OnMouseButtonDownEvent:Unbind()
        itemUI.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
            UIUtils.ShowItemInfo(itemId)
            return UE.UWidgetBlueprintLibrary.Handled()
        end)
        

        ui.HBox_Reward:AddChild(itemUI)
    end
    ui.Img_Got:SetVisibility(bGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.Text_Got:SetVisibility(bGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

function M:LoadFightLevel(path)
    local classPath = path
    if not string.endswith(classPath, "_C'") then
        local sub = string.sub(classPath, 1, -2) .. "_C'"
        classPath = sub
    end
    local lvClass = LoadClass(classPath)
    return lvClass
end

----------------------------------------------------------------------
--- ui event
function M:OnClicked_Btn_Quit()
    if self.InitBlock then
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        self.InitBlock = false
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveTopUI(true)
end

function M:OnClicked_Btn_Exit()
    self:PlayAnimationForward(self.DetailOut)
    self:BindToAnimationFinished(self.DetailOut, function()
        self.Panel_Sub:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_Main:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.Panel_SubExit:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end)
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        local newCopyInfo = self.CurCopyList[idx]
        if ui then
            ui:StopAllAnimations()
            if newCopyInfo then
                ui:PlayAnimationForward(ui.Switch)
            end
        end
    end
end

function M:IA_Back()
    if self.Panel_MainExit:IsVisible() then
        self:OnClicked_Btn_Quit()
    else
        self:OnClicked_Btn_Exit()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)

function M:OnClicked_Btn_Left()
    self.SelectedTabIndex = math.max(1, self.SelectedTabIndex - 1)
    self.CurCopyList = self:GetChallengeCopyList(self.SelectedTabIndex)
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        local newCopyInfo = self.CurCopyList[idx]
        if ui then
            ui:StopAllAnimations()
            if newCopyInfo then
                ui:PlayAnimationForward(ui.Switch)
            else
                ui:PlayAnimationForward(ui.deactive)
            end
        end
    end
    self.Btn_Left:SetIsEnabled(false)
    self.Btn_Right:SetIsEnabled(false)
    self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.RefreshMainUI }, 
        0.2, 
        false
    )
end

function M:OnClicked_Btn_Right()
    self.SelectedTabIndex = math.min(self.TabMax, self.SelectedTabIndex + 1)
    self.CurCopyList = self:GetChallengeCopyList(self.SelectedTabIndex)
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        local newCopyInfo = self.CurCopyList[idx]
        if ui then
            ui:StopAllAnimations()
            if newCopyInfo then
                ui:PlayAnimationForward(ui.Switch)
            else
                ui:PlayAnimationForward(ui.deactive)
            end
        end
    end
    self.Btn_Left:SetIsEnabled(false)
    self.Btn_Right:SetIsEnabled(false)
    self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.RefreshMainUI }, 
        0.2, 
        false
    )
end

function M:OnClicked_Btn_Fight()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local copyInfo = self.CurCopyList[self.SelectedLevelIndex]
    local levelConfig = Database.Query('d_levels_challenge', copyInfo.activity_id)

    gameInstance.LevelClass = nil
    gameInstance.LevelClassPath = levelConfig.path
    gameInstance.fightType = gameInstance.FIGHT_STATE.CharTrainCopy
    gameInstance.fightCanBack = true

    gameInstance.fightMsg =
    {
        fight_level_id = copyInfo.activity_id
    }

    local teamList = gameInstance:LoadTeamList()
    if not teamList then
        teamList = gameInstance:CreateTeamList()
    end
    local freeRoleNum = 0
    local teamData = teamList.TrainPos
    for idx, trainCharId in ipairs(levelConfig.characterTrial) do
        if trainCharId == 1 then freeRoleNum = freeRoleNum + 1 end
        teamData:Set(idx, trainCharId)
    end
    gameInstance:SaveTeamList()

    -- local freeRoleNum = 0
    -- for _, trainCharId in ipairs(levelConfig.characterTrial) do
    --     if trainCharId == 1 then freeRoleNum = freeRoleNum + 1 end
    --     if trainCharId > 1 then
    --         local d_character_trial = require('ClientDatas.d_character_trial')
    --         local config = d_character_trial[trainCharId]
    --         if config and config.roleTrialId then
    --             --生成临时角色数据
    --             local roleInfo = UIUtils.BuildCharInfo(config.roleTrialId, config.roleLevel, config.firstWeapon, config.roleSkill, config.roleInborn)
    --         end
    --     end
    -- end

    --记录当前ui和管卡
    gameInstance.UIName = 'UI_CharTrain'
    gameInstance.UIArgs = self.SelectedTabIndex .. '|' .. self.SelectedLevelIndex
    gameInstance:CachePlayInCity()

    if freeRoleNum > 0 then
        if playerController and gameInstance then
            if playerController.LoadFightBeforeInCity then
                gameInstance.CachedSubLevel = 'City1BusinessCenter'
                gameInstance:HideAllUI()

                local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
                controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
          
                playerController:LoadFightBeforeInCity()
            end
        end
    else
        NetworkMessageManager:GetInstance():AddListener("res_hard_level_fight", self)
        HardLevelSystem:GetInstance():ReqHardLevelFight(gameInstance.fightMsg)
    end
end

function M:res_hard_level_fight(result, msgId, parsed_msg)
    NetworkMessageManager:GetInstance():RemoveListener("res_hard_level_fight", self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local teamList = gameInstance:LoadTeamList()
    if not teamList then
        teamList = gameInstance:CreateTeamList()
    end
    local teamData = teamList.TrainTeamInfo:Get(1)
    local TrainPos = teamList.TrainPos
    local d_character_trial = require('ClientDatas.d_character_trial')
    for idx = 1, TrainPos:Length() do
        local trainCharId = TrainPos:Get(idx)
        if trainCharId > 1 then
            local config = d_character_trial[trainCharId]
            if config and config.roleTrialId then
                teamData.RoleList:Set(idx, config.roleTrialId)
            end
        else
            teamData.RoleList:Set(idx, 0)
        end
    end
    teamList.TrainTeamInfo:Set(1, teamData)
    gameInstance:SaveTeamList()

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    if playerController and playerController.BP_PlayerController_City_UniverseBridge then
        gameInstance:ShowTopUI(false)
        playerController.BP_PlayerController_City_UniverseBridge:FastLoadFight()
    end
end

function M:OnClicked_Btn_Chapter1()
    self:RefreshChapterUI(1)
end

function M:OnClicked_Btn_Chapter2()
    self:RefreshChapterUI(2)
end

function M:OnClicked_Btn_Chapter3()
    self:RefreshChapterUI(3)
end

function M:OnClicked_Btn_Chapter4()
    self:RefreshChapterUI(4)
end

return M
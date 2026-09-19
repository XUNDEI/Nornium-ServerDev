--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"
local Client = require "Network.Client"
local Database = require "_Game.Utils.Database"
local Protos = require("Helper.Protos")
local UIUtils = require "_Game.Utils.UIUtils"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local HardLevelSystem = require 'Module.HardLevel.HardLevelSystem'
local BossRushController = require("Module.BossRush.BossRushController")

---@type UI_Fight_Start_C
local UI_Fight_Start_C = Class()

UI_Fight_Start_C.HideCursor = false
UI_Fight_Start_C.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(UI_Fight_Start_C)

--构造函数
function UI_Fight_Start_C:Construct()
    self:InitUI()
end

function UI_Fight_Start_C:Destruct()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG('UI_Team_List')
    gameInstance:SaveTeamList()
end

function UI_Fight_Start_C:AddListener()
    NetworkMessageManager:GetInstance():AddListener("res_daily_level_fight", self)
    NetworkMessageManager:GetInstance():AddListener("res_hard_level_fight", self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_TOTAL_WAR_FIGHT, self)
end

function UI_Fight_Start_C:RemoveListener()
    NetworkMessageManager:GetInstance():RemoveListener("res_daily_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener("res_hard_level_fight", self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_TOTAL_WAR_FIGHT, self)
end

function UI_Fight_Start_C:OnShowUI()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.bEnableTouchOverEvents = true

    self:SetAllChairListCollision(true)
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    self:PlayAnimationReverse(self.Fight_Start)
    self:InitData()
    self:RefreshUI()
end

function UI_Fight_Start_C:OnHideUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if UE.UGameplayStatics.IsValid(gameInstance) then
        print('---------error') 
        gameInstance.IsSpecialTeamInfo = false
        gameInstance.TeamContext = nil
    end
    if self.bIsHidingUI then return end

    if UE.ESlateVisibility.Hidden == self:GetVisibility() then
        print('-------已经被影藏了')
        return
    end

    self.bIsHidingUI = true

    self:SetAllChairListCollision(false)
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    self:BindToAnimationFinished(self.Fight_Start, function() self:OnHideUIFinishe(self) end)
    self:PlayAnimation(self.Fight_Start)
    -- print("======PlayAnimation:self.Fight_Start")
    UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
end

function UI_Fight_Start_C:InitData()
    print("----------initdata")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local teamList = gameInstance:LoadTeamList()
    if not teamList then
        teamList = gameInstance:CreateTeamList()
    end
    self.TeamListData = teamList

    self.LockedFlags = { 0, 0, 0 }

    local teamInfo = nil
    if gameInstance.IsSpecialTeamInfo then
        teamInfo = self.TeamListData.SpecialTeamInfo
        if gameInstance.TeamContext then
            if gameInstance.TeamContext.type == 1 then
                local bossId = gameInstance.TeamContext.bossId

                local characters = BossRushController:GetInstance():GetPlayerCharacters(bossId)

                local teamData = teamInfo:GetRef(1)
                for i = 1, 3 do
                    teamData.RoleList:Set(i, characters[i] or 0)
                end
                teamData.bIsSelected = true
                teamInfo:Set(1, teamData)
                UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
            end
        end
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        teamInfo = self.TeamListData.TrainTeamInfo --上一次的
        local teamData = teamInfo:Get(1)
        --匹配 角色ID读试用角色表、1表示可上卡池角色、0表示必须空着
        local TrainPos = self.TeamListData.TrainPos
        for i = 1, TrainPos:Length() do
            local trainCharId = TrainPos:Get(i)
            if trainCharId == 0 then --锁定
                self.LockedFlags[i] = 1
                teamData.RoleList:Set(i, 0)
            elseif trainCharId == 1 then --可自由安排一个角色
                self.LockedFlags[i] = 0 
            elseif trainCharId > 1 then
                local d_character_trial = require('ClientDatas.d_character_trial')
                local config = d_character_trial[trainCharId]
                if config and config.roleTrialId then
                    teamData.RoleList:Set(i, config.roleTrialId)
                end
                self.LockedFlags[i] = config.roleTrialId
            end
        end
        self.TeamListData.TrainTeamInfo:Set(1, teamData)
    else
        teamInfo = self.TeamListData.TeamInfo
    end
    self.TeamListMax = teamInfo:Length()
    --修正TeamListData.TeamInfo.RoleList 为 3个元素
    for i = 1, teamInfo:Length() do
        local teamData = teamInfo:Get(i)
        if teamData then
            local isNew = false
            for k = 1, 3 do
                if k > teamData.RoleList:Length() then
                    teamData.RoleList:Add(0)
                    isNew = true
                end
            end
            if isNew then
                if gameInstance.IsSpecialTeamInfo then
                    teamInfo = self.TeamListData.SpecialTeamInfo:Set(i, teamData)
                elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
                    gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
                    teamInfo = self.TeamListData.TrainTeamInfo:Set(i, teamData)
                else
                    teamInfo = self.TeamListData.TeamInfo:Set(i, teamData)
                end
            end
        end
    end
    UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()

    --上次选择的队伍id
    self.LastTeamListIndex = 1 --保存的选中的队伍索引
    self.TeamListIndex = 1 --当前选中的队伍索引

    for i = 1, teamInfo:Length() do 
        local teamData = teamInfo:Get(i)
        if teamData.bIsSelected then
            self.LastTeamListIndex = i
        end
    end
    self.TeamListIndex = self.LastTeamListIndex

    --选中的角色所在队伍的索引
    self.SelectedIndex = 1
    self.bIsForceHideOnClickEvent = false

    --移动模型标记
    self.FromTeamIndex = -1
    self.ToTeamIndex = -1
    self.bIsEndTouch = false

    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge and 
        bp_pc_city_universeBridge.DefaultChairList then
        local chairActorList = bp_pc_city_universeBridge.DefaultChairList
        for _, actor in pairs(chairActorList) do
            actor.OnTouchActorMoved:Add(self, self.OnTouchActorMoved)
            actor.OnTouchActorReleased:Add(self, self.OnTouchActorReleased)
            actor.OnTouchActorEnter:Add(self, self.OnTouchActorEnter)
            actor.OnTouchActorLeave:Add(self, self.OnTouchActorLeave)
            actor.OnTouchActorEnd:Add(self, self.OnTouchActorEnd)

            actor.OnTouchActorClicked:Add(self, self.OnTouchActorClicked)
            actor.OnTouchActorDoubleClicked:Add(self, self.OnTouchActorClicked)
        end

        bp_pc_city_universeBridge.OnChangeRoleCameraEnd:Add(self, self.OnChangeRoleCameraEnd)
        bp_pc_city_universeBridge.OnDoDelayTimeStart:Add(self, self.OnDoDelayTimeStart)
        bp_pc_city_universeBridge.OnDoDelayTimeEnd:Add(self, self.OnDoDelayTimeEnd)
    end
end

function UI_Fight_Start_C:InitUI()
    --修改组队名字
    self.Btn_SetTeamName.OnGHSClicked:Clear()
    self.Btn_SetTeamName.OnGHSClicked:Add(self, self.OnClicked_Btn_SetTeamName)
    --切换队伍
    self.Btn_Left.OnGHSClicked:Clear()
    self.Btn_Left.OnGHSClicked:Add(self, self.OnClicked_Btn_Left)
    self.Btn_Right.OnGHSClicked:Clear()
    self.Btn_Right.OnGHSClicked:Add(self, self.OnClicked_Btn_Right)

    self.Btn_Left:SetVisibility(self.TeamListMax == 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_Right:SetVisibility(self.TeamListMax == 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)

    --快速编队
    self.FastSetTeam.OnGHSClicked:Clear()
    self.FastSetTeam.OnGHSClicked:Add(self, self.OnClicked_FastSetTeam)

    --退出战前准备
    self.BackButton.OnGHSClicked:Clear()
    self.BackButton.OnGHSClicked:Add(self, self.OnClicked_BackButton)

    self.Fight.OnClicked:Clear()
    self.Fight.OnClicked:Add(self, self.OnClick_Fight)

    self.FirstTeam.OnGHSClicked:Clear()
    self.FirstTeam.OnGHSClicked:Add(self, self.OnClick_FirstTeam)

    self.SelectedImgList = {}
    for i = 1, 6 do
        self.SelectedImgList[i] = self["Selected_" .. i]
    end

    self.DragBackImg = {}
    for i = 1, 3 do
        self.DragBackImg[i] = self["No" .. tostring(i)]
        self.DragBackImg[i].ParentUI = self
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        self.FirstTeam:SetVisibility(UE.ESlateVisibility.Hidden) 
    end
end

function UI_Fight_Start_C:OnTouchActorMoved(location, teamIndex)
    if self.LockedFlags[teamIndex] > 0 then
        return
    end
    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.PositionShadow):SetPosition(UE.FVector2D(location.X, location.Y))
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
end

function UI_Fight_Start_C:OnTouchActorReleased(teamIndex)
    if self.LockedFlags[teamIndex] > 0 or (self.ToTeamIndex and self.LockedFlags[self.ToTeamIndex] > 0) then
        return
    end
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    self.FromTeamIndex = teamIndex
    self.bIsEndTouch = false
    self:OnDragAndDropEnd(self.FromTeamIndex, self.ToTeamIndex)
end

function UI_Fight_Start_C:OnTouchActorEnter(teamIndex)
    self.ToTeamIndex = teamIndex
end

function UI_Fight_Start_C:OnTouchActorLeave(teamIndex)
    if not self.bIsEndTouch then
        self.ToTeamIndex = nil
    end
    self.bIsEndTouch = false
end

function UI_Fight_Start_C:OnTouchActorEnd(teamIndex)
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    self.bIsEndTouch = true
end

function UI_Fight_Start_C:OnTouchActorClicked(teamIndex)
    local DataBase = require('_Game.Utils.Database')
    if self.LockedFlags[teamIndex] == 1 then
        UIUtils.ShowNotify(self, DataBase.L10n(315))
        return
    elseif self.LockedFlags[teamIndex] > 1 then
        UIUtils.ShowNotify(self, DataBase.L10n(316))
        return
    end
    
    --获取控制器组件
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge and not bp_pc_city_universeBridge:IsChangeRoleCamera() then
        self:OnSelectedRole(teamIndex)
    end
end

function UI_Fight_Start_C:OnChangeRoleCameraEnd()
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if not bp_pc_city_universeBridge then return end
    if bp_pc_city_universeBridge.LastCameraIndex ~= 0 then
        local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Team_List')
        ui:SetBackUI(self, 0, "FightStart", self.SelectedIndex)
    else
        self:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function UI_Fight_Start_C:OnDoDelayTimeStart()
    self:SetEnableAllButton(false)
end

function UI_Fight_Start_C:OnDoDelayTimeEnd()
    self:SetEnableAllButton(true)
end

function UI_Fight_Start_C:RefreshModel(playEffect)
    --角色(3个)模型修改 TODO
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        local roleList = {}
        for i = 1, 3 do 
            if i <= self.CurTeamData.RoleList:Length() then
                roleList[i] = self.CurTeamData.RoleList:Get(i)
            else
                roleList[i] = 0
            end
        end
        if playEffect then
            bp_pc_city_universeBridge:ShowAllTeamModel(roleList)
        else
            bp_pc_city_universeBridge:ShowTeamModel(roleList)
        end
    end
    self:RefreshFirstTeam()
end

function UI_Fight_Start_C:RefreshFirstTeam()
    --判定是否有角色上场
    local roleNum = 0
    for _, roleId in pairs(self.CurTeamData.RoleList) do 
        if roleId > 0 then
            roleNum = roleNum + 1
        end
    end
    
    self.FirstTeam:SetIsEnabled(roleNum > 0)
end

function UI_Fight_Start_C:RefreshButton()
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    local isFirstTeam = not bp_pc_city_universeBridge.IsGotoFight
    --关闭出击按钮
    self.Fight:SetVisibility(isFirstTeam and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.FirstTeam:SetVisibility(isFirstTeam and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    
    local bIsLast = self.LastTeamListIndex == self.TeamListIndex
    self.Switcher:SetActiveWidgetIndex(bIsLast and 1 or 0)

    self:RefreshFirstTeam()

    --srpg中要屏蔽掉返回，好像只能靠是否在宇宙场景来判断了
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if not gameInstance.fightCanBack then
        self.BackButton:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function UI_Fight_Start_C:RefreshUI()
    --print("====team:" .. tostring(self.TeamListIndex))
    --当前页标签
    for i = 1, #self.SelectedImgList do
        self.SelectedImgList[i]:SetVisibility(self.TeamListIndex == i 
            and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end

    self:GetCurTeamData(true)
    --队伍名字
    self.Text_RoleName:SetText(self.CurTeamData.TeamName)
    
    self:RefreshModel(true)

    self:RefreshButton()

    --更新点击区域
    --self:GetDragItemPos()

    --self:RefresDragItemPos()
end

function UI_Fight_Start_C:SetEnableAllButton(bEnable)
    self.BackButton:SetIsEnabled(bEnable)

    self.Btn_SetTeamName:SetIsEnabled(bEnable)
    --切换队伍
    if self.TeamListMax ~= 1 then
        self.Btn_Left:SetIsEnabled(bEnable)
        self.Btn_Right:SetIsEnabled(bEnable)
    end

    --快速编队
    self.FastSetTeam:SetIsEnabled(bEnable)

    self.Fight:SetIsEnabled(bEnable)

    self.FirstTeam:SetIsEnabled(bEnable)

    if bEnable then
        self:RefreshButton()
    end
end

function UI_Fight_Start_C:GetDragItemPos()
    self.CachedActorList:Clear()

    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        if #bp_pc_city_universeBridge.DefaultChairList > 0 then
            for i, actor in pairs(bp_pc_city_universeBridge.DefaultChairList) do
                self.CachedActorList:Add(actor)
            end
        end
    end
end

function UI_Fight_Start_C:ChangeTeamName(NewTeamName)
    if self.CurTeamData then
        self.CurTeamData.TeamName = NewTeamName
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    --刷新队伍名字
    self.Text_RoleName:SetText(self.CurTeamData.TeamName)
end

function UI_Fight_Start_C:GetCurTeamData(bForce)
    if bForce then
        local teamData = nil
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            teamData = self.TeamListData.SpecialTeamInfo:Get(1)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            teamData = self.TeamListData.TrainTeamInfo:Get(self.TeamListIndex)
        else
            teamData = self.TeamListData.TeamInfo:Get(self.TeamListIndex)
        end
        if not teamData then
            print("===无此数据")
            return
        end
        self.CurTeamData = teamData
    end
    return self.CurTeamData
end

function UI_Fight_Start_C:OnDragAndDropEnd(fromIndex, toIndex)
    -- print("===drop : from :" .. tostring(fromIndex) .. ",to :" .. tostring(toIndex))
    if not fromIndex or not toIndex or fromIndex < 0 or toIndex < 0 or fromIndex == toIndex then
        return
    end

    local delayTime = 0.5
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        delayTime = bp_pc_city_universeBridge.ChangePlayerWaitTime or delayTime
    end
    delayTime = delayTime or 0.5
    delayTime = delayTime + 0.1
    --时间判断
    self.LastSwapTime = self.LastSwapTime or 0

    local curTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
    if curTime - self.LastSwapTime < delayTime then
        return
    end
    self.LastSwapTime = curTime 

    self:SwapRole(fromIndex, toIndex)
end

function UI_Fight_Start_C:SwapRole(fromIndex, toIndex)
    -- print("===swapRole:fromIndex:" .. tostring(fromIndex) .. ",toIndex:" .. tostring(toIndex))
    if self.CurTeamData then
        local formRoleId = self.CurTeamData.RoleList:Get(fromIndex)
        local toRoleId = self.CurTeamData.RoleList:Get(toIndex)
        if formRoleId == 0 and toRoleId == 0 then
            return
        end
        self.CurTeamData.RoleList:Swap(fromIndex, toIndex)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    --self:RefreshModel(true)
    --角色(3个)模型修改 TODO
    local newRoleList = {}
    for i = 1, 3 do 
        newRoleList[i] = self.CurTeamData.RoleList:Get(i)
    end
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        bp_pc_city_universeBridge:SwapTeamModel(0, newRoleList, false)
    end
end

function UI_Fight_Start_C:AddRole(RoleId)
    -- print("===chageRole:" .. tostring(RoleId))
    if self.CurTeamData then
        self.CurTeamData.RoleList[self.SelectedIndex] = RoleId
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    self:RefreshModel()
end

function UI_Fight_Start_C:ChangeRole(index, roleId)
    -- print("===chageRole:" .. tostring(index) .. ", roleid:" .. tostring(roleId))
    if self.CurTeamData then
        self.CurTeamData.RoleList[index] = roleId
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    self:RefreshModel()
end

function UI_Fight_Start_C:RemoveRole(Index)
    -- print("===RemoveRole:" .. tostring(Index))
    if self.CurTeamData then
        self.CurTeamData.RoleList[Index] = 0
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    self:RefreshModel()
end

function UI_Fight_Start_C:QuickEditTeam(roleList)
    if self.CurTeamData then
        self.CurTeamData.RoleList:Clear()
        self.CurTeamData.RoleList:Add(0)
        self.CurTeamData.RoleList:Add(0)
        self.CurTeamData.RoleList:Add(0)
        for index, roleId in pairs(roleList) do
            self.CurTeamData.RoleList[index] = roleId
        end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        else
            self.TeamListData.TeamInfo:Set(self.TeamListIndex, self.CurTeamData)
        end
        UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    end
    --self:RefreshModel(false)
    --self:RefreshModel(true)
    --角色(3个)模型修改 TODO
    local newRoleList = {}
    for i = 1, 3 do 
        newRoleList[i] = self.CurTeamData.RoleList:Get(i)
    end
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        bp_pc_city_universeBridge:SwapTeamModel(0, newRoleList, false)
    end
    self:RefreshFirstTeam()
end

function UI_Fight_Start_C:OnSelectedRole(roleIndex)
    --print("====self.CurTeamData.RoleList:" .. tostring(self.CurTeamData.RoleList:Length()))
    --print("====selectedIndex:" .. tostring(self.SelectedIndex))
    
    self.SelectedIndex = roleIndex
    local roleId = self.CurTeamData.RoleList:Get(self.SelectedIndex)
    self:OnClickTeamIndex(self.SelectedIndex, roleId)

    self:SetAllChairListCollision(false)
    
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    self:ChangeRoleCamera(self.SelectedIndex, roleId)
end

function UI_Fight_Start_C:ChangeRoleCamera(index, roleId)
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        bp_pc_city_universeBridge:ChangeRoleCamera(index, false, roleId)
    end
end

function UI_Fight_Start_C:OnClickTeamIndex(index, roleId)
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        bp_pc_city_universeBridge:OnClickTeamIndex(index, roleId)
    end
end

function UI_Fight_Start_C:SetAllChairListCollision(enable)
    local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
    if bp_pc_city_universeBridge then
        bp_pc_city_universeBridge:SetEnableCollision_ChairActorList(enable)
    end
end

function UI_Fight_Start_C:SaveSelectedIndex()
    local teamInfo = nil
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.IsSpecialTeamInfo then
        teamInfo = self.TeamListData.SpecialTeamInfo
    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        teamInfo = self.TeamListData.TrainTeamInfo
    else
        teamInfo = self.TeamListData.TeamInfo
    end
    for i = 1, teamInfo:Length() do
        local data = teamInfo:Get(i)
        data.bIsSelected = self.TeamListIndex == i and true or false
        if gameInstance.IsSpecialTeamInfo then
            self.TeamListData.SpecialTeamInfo:Set(i, data)
        elseif gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
            gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
            self.TeamListData.TrainTeamInfo:Set(i, data)
        else
            self.TeamListData.TeamInfo:Set(i, data)
        end
    end
    UE.UGameplayStatics.GetGameInstance(self):SaveTeamList()
    self.LastTeamListIndex = self.TeamListIndex
end

function UI_Fight_Start_C:SetForceHideOnClicked(bHide)
    self.bIsForceHideOnClickEvent = bHide or false
end

function UI_Fight_Start_C:OnPlayAnimationEnd()
    for i = 1, #self.SelectedImgList do
        self.SelectedImgList[i]:SetVisibility(self.TeamListIndex == i 
            and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end

    self:GetCurTeamData(true)
    --队伍名字
    self.Text_RoleName:SetText(self.CurTeamData.TeamName)

    self:RefreshModel(true)

    self:RefreshButton()
end

function UI_Fight_Start_C:OnBack(multiMode)
    self:RefreshModel()
    self:SetAllChairListCollision(true)
    if multiMode then
        self:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function UI_Fight_Start_C:OnHideUIFinishe(self)
    print('-------OnHideUIFinishe')
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    self.bIsHidingUI = false
    UIManager:GetInstance():RemoveUI(self)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.fightCanBack = true
    if self.IsGotoFight then
        self.sendRequest = false
        local bp_pc_city_universeBridge = UE.UGameplayStatics.GetPlayerController(self, 0).BP_PlayerController_City_UniverseBridge
        if bp_pc_city_universeBridge then
            print('-------LoadFight')
            bp_pc_city_universeBridge:LoadFight()
            print('-------LoadFight2')
        end
    else
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local BP_PlayerController_City_UniverseBridge = playerController.BP_PlayerController_City_UniverseBridge
        BP_PlayerController_City_UniverseBridge:UnloadFightBefore()
    end
   
end

----------------------------------------------------------------------
---
function UI_Fight_Start_C:OnLeftMouseButtonClickedActor(index)
    if self.IsGotoFight then return end
    print("---click:" .. tostring(index))
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    if index < 0 then return end
    self:OnTouchActorClicked(index)
end

function UI_Fight_Start_C:OnLeftMouseButtonChangedActor(fromIndex, toIndex)
    print("---end:" .. tostring(fromIndex) .. ', to:' .. tostring(toIndex))
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.Hidden)
    if self.IsGotoFight then return end
    if fromIndex < 0 and toIndex < 0 then
        return
    end
    if (self.LockedFlags[fromIndex] and self.LockedFlags[fromIndex] > 0) or (self.LockedFlags[toIndex] and self.LockedFlags[toIndex] > 0) then
        return
    end
    self.FromTeamIndex = fromIndex
    self.ToTeamIndex = toIndex
    self:OnDragAndDropEnd(self.FromTeamIndex, self.ToTeamIndex)
end

function UI_Fight_Start_C:OnLeftMouseButtonMove(mousePos, traceIndex)
    if self.IsGotoFight then return end
    print("---move:" .. tostring(traceIndex))
    if traceIndex < 0 or (self.LockedFlags[traceIndex] and self.LockedFlags[traceIndex] > 0) then
        return
    end
    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.PositionShadow):SetPosition(UE.FVector2D(mousePos.X, mousePos.Y))
    self.PositionShadow:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
end

function UI_Fight_Start_C:OnClicked_Btn_SetTeamName()
    self:SetAllChairListCollision(false)
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Com_Team_NameSet')
    ui:SetBackUI(self)
    ui:SetTeamName(self.CurTeamData.TeamName)
end

function UI_Fight_Start_C:OnClicked_Btn_Left()
    if self.TeamListMax == 1 then return end
    self.TeamListIndex = self.TeamListIndex - 1
    if self.TeamListIndex < 1 then
        self.TeamListIndex = self.TeamListMax
    end
    -- self:BindToAnimationFinished(self.ChangeTeamListIndex, function()
    --     self:OnPlayAnimationEnd()
    -- end)
    --播放切换动画
    -- self:PlayAnimation(self.ChangeTeamListIndex)
    -- self.DelayShowTeamModel = UE.UKismetSystemLibrary.K2_SetTimerDelegate(  
    --     { self, self.OnPlayAnimationEnd }, 
    --     self.ChangeTeamShowPlayerTime, 
    --     false)
    --self:RefreshUI()
    self:OnPlayAnimationEnd()
end

function UI_Fight_Start_C:OnClicked_Btn_Right()
    if self.TeamListMax == 1 then return end
    self.TeamListIndex = self.TeamListIndex + 1
    if self.TeamListIndex > self.TeamListMax then
        self.TeamListIndex = 1
    end
    -- self:BindToAnimationFinished(self.ChangeTeamListIndex, function()
    --     self:OnPlayAnimationEnd()
    -- end)
    --播放切换动画
    -- self:PlayAnimation(self.ChangeTeamListIndex)
    -- self.DelayShowTeamModel = UE.UKismetSystemLibrary.K2_SetTimerDelegate(  
    --     { self, self.OnPlayAnimationEnd }, 
    --     self.ChangeTeamShowPlayerTime, 
    --     false)
    self:OnPlayAnimationEnd()
    --self:RefreshUI()
end

function UI_Fight_Start_C:OnClicked_FastSetTeam()
    self:SetAllChairListCollision(false)
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Team_List')
    ui:SetBackUI(self, 1, "FightStart")
end

function UI_Fight_Start_C:OnClicked_BackButton()
    local gameInstance = UE4.UGameplayStatics.GetGameInstance(self)
    if gameInstance.fightCanBack ~= nil and not gameInstance.fightCanBack then
        print('--------->OnClicked_BackButton')
        do return end
    end
    gameInstance:RemoveUMG('UI_Team_List')
    self.IsGotoFight = false
    self:OnHideUI()
end

InputUtils.RegisterUIAction(UI_Fight_Start_C, InputAssets.IA_Back, UE.ETriggerEvent.Completed, UI_Fight_Start_C.OnClicked_BackButton)

function UI_Fight_Start_C:OnClick_Fight()
   
    if self.CurTeamData then
        local teamIds = {}
        for i = 1, self.CurTeamData.RoleList:Length() do
            local roledId = self.CurTeamData.RoleList:Get(i)
            if roledId > 0 then
                table.insert(teamIds, roledId)
            end
        end
        
        UE4.UGameplayStatics.GetGameInstance(self):RemoveUMG('UI_Team_List')
        
        if #teamIds > 0 then
            self:SaveSelectedIndex()

            ---@type BP_GameInstance_C
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

            -- 如果没设置fightMsg，说明是测试关卡
            if gameInstance.fightMsg then
                if not self.sendRequest then
                    gameInstance.fightMsg.character_ids = teamIds
                    self:AddListener()

                    if gameInstance.fightType == gameInstance.FIGHT_STATE.EVENT then
                        Client.send(Protos.REQ_EVENT_FIGHT, gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.EXPLORE then
                        Client.send(Protos.REQ_EXPLORE_FIGHT, gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.BOSS then
                        Client.send(Protos.REQ_BOSS_FIGHT, gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.MAINPOS then
                        Client.send(Protos.REQ_MAIN_POS_FIGHT, gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.DailyCopy then
                        --Client.send(Protos.REQ_DAILY_lEVEL_FIGHT, gameInstance.fightMsg)
                        if gameInstance.fightRestart then
                            self:ConfirmFight()
                            self.sendRequest = true
                            return
                        end
                        Client.send("req_daily_level_fight", gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.ChallengeCopy or
                        gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy then
                        HardLevelSystem:GetInstance():ReqHardLevelFight(gameInstance.fightMsg)
                        self.sendRequest = true
                    elseif gameInstance.fightType == gameInstance.FIGHT_STATE.BOSSRUSH then
                        local lockedIds = BossRushController:GetInstance():GetBossUsedCharacters(gameInstance.TeamContext.bossId)

                        local anyNewId = false
                        for _, id in ipairs(teamIds) do
                            if not table.indexof(lockedIds, id) then
                                anyNewId = true
                            end
                        end
                        
                        if anyNewId then
                            UIManager:GetInstance():ShowConfirm({
                                notice = Database.L10n(521),
                                confirm = function()
                                    Client.send(Protos.REQ_TOTAL_WAR_FIGHT, gameInstance.fightMsg)
                                    self.sendRequest = true
                                end,
                                showCancel = true,
                            })
                        else
                            Client.send(Protos.REQ_TOTAL_WAR_FIGHT, gameInstance.fightMsg)
                            self.sendRequest = true
                        end
                    else
                        self:ConfirmFight()
                    end
                end
            else
                self:ConfirmFight()
            end
            return
        end
    end
    --提示,选角
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(520),
        confirm = UI_Fight_Start_C.OnClicked_BtnOk,
        showCancel = false,
    })
end

function UI_Fight_Start_C:res_explore_fight(result, msgId, parsed_msg)
    self:RemoveListener()

    if result == 0 then
        self:ConfirmFight()
    else
        LOG_WARN("Res Explore Fight Error Code:", result)

        self.sendRequest = false
    end
end

function UI_Fight_Start_C:res_daily_level_fight(result, msgId, parsed_msg)
    self:RemoveListener()

    if result == 0 then
        self:ConfirmFight()
    else
        LOG_WARN("Res Daily Level Fight Error Code:", result)

        self.sendRequest = false
    end
end

function UI_Fight_Start_C:res_hard_level_fight(result, msgId, parsed_msg)
    self:RemoveListener()

    if result == 0 then
        self:ConfirmFight()
    else
        LOG_WARN("Res Activity Hard Level Fight Error Code:", result)

        self.sendRequest = false
    end
end

UI_Fight_Start_C[Protos.RES_TOTAL_WAR_FIGHT] = function(self, result, msgId, parsed_msg)
    self:RemoveListener()

    if result == 0 then
        LOG_INFO("start")
        self:ConfirmFight()
    else
        LOG_WARN("Res Total War Fight Error Code:", result)

        self.sendRequest = false
    end
end

function UI_Fight_Start_C:ConfirmFight()
    self.IsGotoFight = true
    self:OnHideUI()
end

function UI_Fight_Start_C:OnClicked_BtnOk()
    if self.TipUI then
        UIManager:GetInstance():RemoveUI(self.TipUI)
        self.TipUI = nil
    end
end

function UI_Fight_Start_C:OnClick_FirstTeam()
    if self.LastTeamListIndex ~= self.TeamListIndex then
        self:SaveSelectedIndex()
        --刷新按钮状态
        self:RefreshButton()
    else
        --返回
        self:OnClicked_BackButton()
    end
end

return UI_Fight_Start_C

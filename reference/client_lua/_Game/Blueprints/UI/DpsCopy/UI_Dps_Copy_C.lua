
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local HardLevelSystem = require "Module.HardLevel.HardLevelSystem"

---@type UI_Dps_Copy_C
local M = UnLua.Class()

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

    self['UI_ChallengeCopyItem1'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter1)
    self['UI_ChallengeCopyItem2'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter2)
    self['UI_ChallengeCopyItem3'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter3)
    self['UI_ChallengeCopyItem4'].Btn_Bg.OnClicked:Add(self, self.OnClicked_Btn_Chapter4)

    self.Btn_Fight.OnGHSClicked:Add(self, self.OnClicked_Btn_Fight)
end

function M:InitData()
    self:InitActivityInfo(true)
    self:RefreshMainUI()
end

function M:InitActivityInfo(isInit)
    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    local copyInfo = HardLevelSystem:GetInstance().HardLevelInfos
    local starList = copyInfo.stars
    print("==starList:" .. tostring(table.dump(starList or {}, false, 10)))

    local pageList = {}
    for _, config in pairs(d_levels_challenge) do
        if config.levelTypes == UIUtils.ECopyType.ECopyType_DPS then
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

function M:GetChallengeCopyList(index)
    local d_levels_challenge = require('ClientDatas.d_levels_challenge')
    local result = {}
    local copyInfo = HardLevelSystem:GetInstance().HardLevelInfos
    local starList = copyInfo.stars
 
    local passed_level_id = self:InitActivityInfo(false)

    for idx, config in ipairs(d_levels_challenge) do
        if config.levelTypes == UIUtils.ECopyType.ECopyType_DPS then
            if config.page == index then 
                local starTab = {}
                local startIdx = (idx - 1) * 3 + 1
                local endIdx = idx * 3
                for i = startIdx, endIdx do 
                    table.insert(starTab, starList[i] or false)
                end
                local copyInfo = {
                    activity_id = config.id,
                    stars = starTab,
                    unlock = config.id <= (passed_level_id + 1)
                }
                table.insert(result, copyInfo)
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
        local levelIdx = tonumber(argTab[2])
        self.SelectedTabIndex = tabIdx
        self:RefreshMainUI()
        --self:RefreshChapterUI(levelIdx)
    end
end

function M:RefreshMainUI()
    self.Btn_Left:SetIsEnabled(true)
    self.Btn_Right:SetIsEnabled(true)

    self.CurCopyList = self:GetChallengeCopyList(self.SelectedTabIndex)

    self.Btn_Left:SetVisibility(self.SelectedTabIndex == 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_Right:SetVisibility(self.SelectedTabIndex == self.TabMax and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)

    -- local copyInfo = HardLevelSystem:GetInstance().HardLevelInfos
    -- local startTime = os.date("*t", copyInfo.begin_seconds)
    -- local endTime = os.date("*t", copyInfo.end_seconds)
    -- local deltaTime = math.abs(copyInfo.end_seconds - os.time())
    --print("==startTime.month:" .. tostring(startTime.month))
    --print("==startTime.day:" .. tostring(startTime.day))
    --print("==endTime.month:" .. tostring(endTime.month))
    --print("==endTime.day:" .. tostring(endTime.day))
    --活动时间
    -- self.Text_StartTime:SetText(startTime.month .. "月" .. startTime.day .. '日—' .. endTime.month .. "月" .. endTime.day .. '日')
    
    --- **`day`** (1-31)
    --- **`hour`** (0-23)
    --- **`min`** (0-59)
    ---
    -- local leftTime = os.date("*t", deltaTime)
    --剩余时间
    -- local day = leftTime.day
    -- local month = leftTime.hour
    -- local minus = leftTime.min
    --print("==day:" .. tostring(day))
    --print("==month:" .. tostring(month))
    --print("==minus:" .. tostring(minus))
    -- local leftTimeStr = string.format(Database.L10n(293), day, month, minus)
    --print("==leftTime:" .. tostring(leftTimeStr))
    -- self.Text_LeftTime:SetText(leftTimeStr)

  
    for idx = 1, 4 do 
        local ui = self['UI_ChallengeCopyItem' .. idx]
        local copyInfo = self.CurCopyList[idx]
        if ui then
            if copyInfo then
                ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                self:RefreshLevel(ui, copyInfo)
            else
                ui:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
    end
    -- for idx, copyInfo in ipairs(self.CurCopyList) do 
    --     self:RefreshLevel(self['UI_ChallengeCopyItem' .. idx], copyInfo)
    -- end
    --副本名字
    -- self.Text_CopyName:SetText(Database.L10n(286))

    for idx = 1, 3 do 
        local ui = self['UI_ChallengeCopyItem' .. idx]

        local copyInfo = self.CurCopyList[idx]
        local config = Database.Query('d_levels_challenge', copyInfo.activity_id)
        LOG_INFO(idx, table.dump(config, false, 10))

        ui.TextLevel:SetText(string.format(Database.L10n(816000301), config.proposeLevel))
    end
end

function M:RefreshChapterUI(levelIndex)
    self:PlayAnimationForward(self.DetailIn)
    self.SelectedLevelIndex = levelIndex
    local copyInfo = self.CurCopyList[levelIndex]
    local config = Database.Query('d_levels_challenge', copyInfo.activity_id)
    LOG_INFO(table.dump(config, false, 10))

    self.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_Sub:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    --章节名
    self.Text_Chapter:SetText(Database.L10n(config.levelName))
    -- self.Text_Chapter_1:SetText(Database.L10n(286))

    --目标
    for i = 1, 3 do
        local bStar = copyInfo.stars[i] or false
        local ui = self['UI_ChallengeTarget' .. i]
        local target = config.target[i]
        local param = config.targetNumber[i] or ''
        if ui and target then
            local textStr = string.format(Database.L10n(target), param)
            ui.Txt_Black:SetText(textStr)
            ui.Txt_White:SetText(textStr)
            ui.Txt_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            ui.Img_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
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

    for i = 1, 3 do 
        local ui = self['UI_Reward' .. i]
        local reward = config['reward' .. i]
        if ui and reward then
            self:RefreshReward(ui, reward, i <= starNum)
        end
    end

    local isSwitch = config.switch > 0
    self.Panel_Des:SetVisibility(isSwitch and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    if isSwitch then
        self.Txt_White:SetText(UIUtils.GetSwitchText(config.switch))
    end

    self.Btn_Fight:SetIsEnabled(copyInfo.unlock)
    
    self.TextLevel:SetText(string.format(Database.L10n(816000301), config.proposeLevel))
end

function M:RefreshLevel(ui, copyInfo)
    print("=====RefreshLevel:" .. tostring(table.dump(copyInfo, nil, 10)))
    if ui then
        local config = Database.Query('d_levels_challenge', copyInfo.activity_id)
        ui.Text_Lock:SetText(Database.L10n(config.levelName))
        ui.Text_Unlock:SetText(Database.L10n(config.levelName))

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
        ui.Panel_Lock:SetVisibility(bUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        ui.Panel_Unlock:SetVisibility(bUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
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
    local lvClass = UE.UClass.Load(classPath)
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
    end)
end

function M:OnClicked_Btn_Left()
    self.SelectedTabIndex = math.max(1, self.SelectedTabIndex - 1)
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        if ui then
            ui:PlayAnimationForward(ui.Switch)
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
    for idx = 1, 4 do 
        local ui = self['UI_CharTrainItem' .. idx]
        if ui then
            ui:PlayAnimationForward(ui.Switch)
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
    local config = Database.Query('d_levels_challenge', copyInfo.activity_id)
    
    gameInstance.LevelClass = self:LoadFightLevel(config.path)
    gameInstance.fightMsg = 
    { 
        activity_id = 1,
        fight_level_id = copyInfo.activity_id
    }
    gameInstance.fightType = gameInstance.FIGHT_STATE.ChallengeCopy
    gameInstance.fightCanBack = true

    --记录当前ui和管卡
    gameInstance.UIName = 'UI_Dps_Copy'
    gameInstance.UIArgs = self.SelectedTabIndex .. '|' .. self.SelectedLevelIndex
 
    if playerController and gameInstance and gameInstance.LevelClass then
        if playerController.LoadFightBeforeInCity then
            gameInstance:CachePlayInCity()
            gameInstance.CachedSubLevel = 'City1BusinessCenter'
            gameInstance:HideAllUI()
 
            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false

            playerController:LoadFightBeforeInCity()
        end
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
local GlobalConfig = require("GlobalConfig")
local Database = require "_Game.Utils.Database"
local d_levels = require "ClientDatas.d_levels"
local UIUtils = require "_Game.Utils.UIUtils"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local RedPointSystem = require('Module.RedPointSystem.RedPointSystem')
local QuestSystem = require('Module.Quest.QuestSystem')
local PlotSystem = require("Module.Plot.PlotSystem")
local ActivitySystem = require('Module.Activity.ActivitySystem')
local MailController = require('Module.Mail.MailController')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_CityMenu_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    self:InitUI()
    self:RefreshUI()
    MessageManager:GetInstance():AddListener('OnMsg_Player_Exp_Changed', self)
    MessageManager:GetInstance():AddListener('OnMsg_RedPointSystem', self)
    MessageManager:GetInstance():AddListener(MailController.MailUpdated, self)
end

function M:Destruct()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        player:ChangeCamera(true)
    end
    MessageManager:GetInstance():RemoveListener('OnMsg_Player_Exp_Changed', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_RedPointSystem', self)
    MessageManager:GetInstance():RemoveListener(MailController.MailUpdated, self)

    if self.InitBlock then
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        if controller and controller.BP_PlayerController_City_UniverseBridge then
            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
            self.InitBlock = false
        end
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitData()
    self.CaptureActor = nil
    self.CaptureCharacterActor = nil
end

function M:InitUI()
    self.Back.OnClicked:Add(self, self.OnClicked_Back)
    self.Exit.OnClicked:Add(self, self.OnClicked_Exit)

    self.set.OnGHSClicked:Add(self, self.OnClicked_Set)
    self.character.OnGHSClicked:Add(self, self.OnClicked_Character)
    self.backpack.OnGHSClicked:Add(self, self.OnClicked_Backpack)
    self.team.OnGHSClicked:Add(self, self.OnClicked_Team)
    self.task.OnGHSClicked:Add(self, self.OnClicked_Task)
    self.target.OnGHSClicked:Add(self, self.OnClicked_Target)
    self.Active.OnGHSClicked:Add(self, self.OnClicked_Active)
    self.achieve.OnGHSClicked:Add(self, self.OnClicked_Achieve)
    self.Shop.OnGHSClicked:Add(self, self.OnClicked_Shop)
    self.Card.OnGHSClicked:Add(self, self.OnClicked_Card)
    self.announcement.OnGHSClicked:Add(self, self.OnClicked_Announcement)
    self.mail.OnGHSClicked:Add(self, self.OnClicked_Mail)
    self.friend.OnGHSClicked:Add(self, self.OnClicked_Friend)
    self.pass.OnGHSClicked:Add(self, self.OnClicked_Pass)
    self.HandBook.OnGHSClicked:Add(self, self.OnClicked_HandBook)
    self.Plot.OnGHSClicked:Add(self, self.OnClicked_Plot)

    self.Btn_Activity.OnGHSClicked:Add(self, self.OnClicked_Activity)

    self:PlayAnimationForward(self.In, 1.0, false)

    self.OnVisibilityChanged:Add(self, function(ui, visible)
        print('----visible:' .. tostring(visible))
        --隐藏
        if visible == 1 or visible == 2 then
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = gameMode:BPI_GetPlayer()
            if player then
                player:ChangeCamera(false)
            end
        else
            self:RefreshRedPoint()
            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
            
            UE.UKismetSystemLibrary.K2_SetTimerDelegate(
                { self, self.CreatePlayer }, 
                0.2, 
                false
            )
        end
    end)

    self:RefreshRedPoint()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not controller.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitBlock = true
    end

    --判定当前是否在openscene
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local sceneId = gameInstance:GetCurrentSceneId()
    self.character:SetIsEnabled(sceneId ~= UIUtils.SceneId.OpeningScene)
end

function M:OnMsg_Player_Exp_Changed()
    local level, needExp, nextNeedExp, leftExp = UIUtils.GetPlayerLevel()
    local maxLv = UIUtils.GetPlayerMaxLevel()
    if level >= maxLv then
        self.ExpNum:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.CurrentLevel_1:SetText(leftExp)
        self.MaxLevel_1:SetText(nextNeedExp)
    end 

    self.CurrentLevel:SetText(level)
    self.MaxLevel:SetText(maxLv)
    --经验值
    self.LevelExp:SetPercent(leftExp / nextNeedExp)
end

function M:OnMsg_RedPointSystem(type)
    self:RefreshRedPoint()
end

function M:RefreshRedPoint()
    self:RefreshRewardBookRedPoint()

    self:RefreshMailRedPoint()

    self:RefreshActivityRedPoint()

    self:RefreshTaskRedPoint()
end

function M:RefreshRewardBookRedPoint()
    local firstTabIndex, _ = QuestSystem:GetInstance():CheckAllBookMission()
    local records = RedPointSystem:GetInstance():GetRecord('UI_City.UI_CityMenu.UI_RewardBook')
    local d_task_book = require("ClientDatas.d_task_book")
    local count = 0
    if records then
        for _, mission_id in ipairs(records) do
            local config = d_task_book[mission_id]
            if config.page == firstTabIndex then
                count = count + 1
            end
        end
    end
    
    self.Img_RedPoint_Target:SetVisibility(count > 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

function M:RefreshActivityRedPoint()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local isOpen, _ = gameInstance:OpenLinkEx(9026, true)
    if isOpen then
        self.Img_RedPoint_Target_1:SetVisibility(ActivitySystem:GetInstance():AnyRewardAvailable() and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshMailRedPoint()
    self.Img_RedPoint_Mail:SetVisibility(MailController:GetInstance():HasUnreadMail() and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
end

M[MailController.MailUpdated] = function(self)
    self:RefreshMailRedPoint()
end

function M:RefreshTaskRedPoint()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local isOpen, _ = gameInstance:OpenLinkEx(9012, true)
    if isOpen then
            
        local records = RedPointSystem:GetInstance():GetRecord('UI_City.UI_CityMenu.UI_DailyQuest')
        self.Img_RedPoint_Task:SetVisibility(table.count(records) > 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    else
        self.Img_RedPoint_Task:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local d_story_tree = require("ClientDatas.d_story_tree")
    local story_tree_info = d_story_tree[plot_info.plot_tree_id]
    
    local PlayerSystem = require "Module.Player.PlayerSystem"
    local player_sequence_name = PlayerSystem:GetInstance().PlayerInfo.player_sequence_name 
    if player_sequence_name and player_sequence_name ~= "" then
        self.Text_Account:SetText(player_sequence_name)
        self.Text_Account:SetVisibility(UE.ESlateVisibility.Visible)
    else
        self.Text_Account:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    local PlayerSystem = require('Module.Player.PlayerSystem')
    if PlayerSystem:GetInstance().PlayerInfo and PlayerSystem:GetInstance().PlayerInfo.player_id then
        self.Text_UID:SetText('#' .. (100000000 + PlayerSystem:GetInstance().PlayerInfo.player_id))
    end
   

    --头像
    -- local cityId = gameInstance:GetPlayerCharacterIdInCity()
    -- local HeadPath = UIUtils.GetCharacterIdolIcon(cityId)
    -- local iconTexture = LoadObject(HeadPath)
    -- if iconTexture then
    --     self.HeadIcon:SetBrushFromAtlasInterface(iconTexture)
    -- end
    local level, needExp, nextNeedExp, leftExp = UIUtils.GetPlayerLevel()
    local maxLv = UIUtils.GetPlayerMaxLevel()

    if level >= maxLv then
        self.ExpNum:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.CurrentLevel_1:SetText(leftExp)
        self.MaxLevel_1:SetText(nextNeedExp)
    end 

    self.CurrentLevel:SetText(level)
    self.MaxLevel:SetText(maxLv)
    --经验值
    self.LevelExp:SetPercent(leftExp / nextNeedExp)

    --剧情
    if story_tree_info then
        if story_tree_info.num < 10 then
            self.Text_Plot_Id:SetText(0 .. tostring(story_tree_info.num))
        else
            self.Text_Plot_Id:SetText(story_tree_info.num)
        end
        self.Text_Plot_Name:SetText(Database.L10n(story_tree_info.name))
        local iconTexture = LoadObject(story_tree_info.entrance)
        if iconTexture then
            self.Image_119:SetBrushFromAtlasInterface(iconTexture)
        end
    end

    self:CreatePlayer()
end

function M:OnClicked_Back()
    if self.bIsBacking then return end
    self.bIsBacking = true
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        if playerController.BP_PlayerController_UniverseMenu then
            if playerController and playerController.SwitchMenuToMap then
                local gameMode = UE.UGameplayStatics.GetGameMode(self)
                if playerController.detailedShip then
                    playerController.detailedShip:SetActorHiddenInGame(playerController.BP_PlayerController_UniverseMenu.SpringArmScale < GlobalConfig.DetailThreshold)
                    playerController.detailedShip:ResetActors()
                end
                if gameMode and gameMode.PlayerInMenu then
                    playerController:SetViewTargetWithBlend(gameMode.PlayerInMenu, 0., UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
                    gameMode.PlayerInMenu:GetComponentByClass(UE.USceneCaptureComponent2D):CaptureScene()
                else
                    local gameMode = UE.UGameplayStatics.GetGameMode(self)
                    local player = gameMode:BPI_GetPlayer()
                    if player then
                        player:ChangeCamera(true)
                    end
                end
            end
            
            if playerController.BP_PlayerController_UniverseMenu.UI_Menu then
                playerController.BP_PlayerController_UniverseMenu.UI_Menu:Show()
            end
        else
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = gameMode:BPI_GetPlayer()
            if player then
                player:ChangeCamera(true)
            end
        end
    end
    self:vfx_Out()
    coroutine.resume(coroutine.create(function ()
        UE.UKismetSystemLibrary.Delay(self, 0.2)
        self.bIsBacking = false
        UE.UGameplayStatics.GetGameInstance(self):RemoveTopUI(true)
    end))
    
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Back)

----------------------------------------------------------------------------
---ui event
--设置
function M:OnClicked_Set()
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc and pc.ShowUISettings then
        pc:ShowUISettings(20)
    end
end

--角色
function M:OnClicked_Character()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9009, "") then
        UE.UGameplayStatics.GetGameInstance(self):ShowTopUI(false)
        ---@type BP_PlayerController_Universe_C
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        if pc and pc.BP_PlayerController_UniverseMenu then
            local ui = UE.UGameplayStatics.GetGameInstance(self):GetUMG('UI_Menu')
            if ui then
                ui:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
    end
end

--背包
function M:OnClicked_Backpack()
    UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Backpack')
end

function M:OnClicked_Exit()
    UIUtils.ShowComNotice(Database.L10n(282), self, function()
        UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
    end, function() end)
    --UE.UGameplayStatics.OpenLevel(self, "LoginMap", false, '')
end

--编队
function M:OnClicked_Team()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:ShowTopUI(false)
    gameInstance.fightType = 0
    gameInstance.fightCanBack = true
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc and pc.BP_PlayerController_City_UniverseBridge then
        pc.BP_PlayerController_City_UniverseBridge:LoadFightBefore(false, false)
    end
end

--任务
function M:OnClicked_Task()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9008, "")
end

--目标
function M:OnClicked_Target()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9013, "") then
        self:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

--活动
function M:OnClicked_Active()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9010, '') then
        self:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

--成就
function M:OnClicked_Achieve()
    UIUtils.ShowNotify(self, Database.L10n(50500))
end

function M:OnClicked_Activity()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9026, "") then
        self:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

--商店
function M:OnClicked_Shop()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --UIUtils.ShowNotify(self, Database.L10n(50500))
    if gameInstance:OpenLink(9029, "") then
        -- self:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

--抽卡
function M:OnClicked_Card()
    -- UIUtils.ShowNotify(self, Database.L10n(50500))
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9024, "") then
        --判断是否在地铁
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        if pc then
            if pc.LoadStationScene then--
                if pc.bIsInStationScene then --已经在地图中
                    gameInstance:RemoveTopUI(false)
                    gameInstance:ShowTopUI(true)
                    local ui = gameInstance:GetUMG('UI_TrainStation')
                    if ui then
                        ui:OnClicked_UI_MenuButton()
                    end
                else --不在地图,提示信息
                    UIUtils.ShowComNotice(Database.L10n(438), self, function() 
                        gameInstance:RemoveTopUI(false)
                        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
                        playerController:LoadStationScene(true)
                    end, function() end)
                end
            else --不在主城地图
                UIUtils.ShowComNotice(Database.L10n(448), self, function()
                end, function() end)
            end
        end
    end
end

--公告
function M:OnClicked_Announcement()
    local widget_class = UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_Bulletin/UI_Bulletin.UI_Bulletin_C')
    ---@type UI_Bulletin_C
    local widget = UE.UWidgetBlueprintLibrary.Create(self, widget_class)
    UIManager:GetInstance():AddUI(widget)
    widget:Setup()
end

--邮件
function M:OnClicked_Mail()
    local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Email/UI_Email.UI_Email_C")
    local widget = UE.UWidgetBlueprintLibrary.Create(self, widget_class)
    UIManager:GetInstance():AddUI(widget)
    widget:Refresh()
end

--好友
function M:OnClicked_Friend()
    UIUtils.ShowNotify(self, Database.L10n(50500))
end

function M:OnClicked_Pass()
    UIUtils.ShowNotify(self, Database.L10n(50500))
end

--奖励册
function M:OnClicked_HandBook()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9015, "") then
        local ui = gameInstance:GetUMG('UI_HandBook')
        ui:RefreshUI()
    end
end

--剧情树
function M:OnClicked_Plot()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9014, "")
end

----------------------------------------------------------------------
---创建模型
function M:CreatePlayer()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        if playerController.BP_PlayerController_UniverseMenu then
            if playerController.BP_PlayerController_City_UniverseBridge then
                if not playerController.BP_PlayerController_City_UniverseBridge.IsInCharacterScene then 
                    if playerController.detailedShip then
                        playerController.detailedShip:SetActorHiddenInGame(false)
                        playerController:SetViewTargetWithBlend(playerController.detailedShip, 0., UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
                        playerController.detailedShip:ChangeCamera()
                    else
                        local gameMode = UE.UGameplayStatics.GetGameMode(self)
                        local player = gameMode:BPI_GetPlayer()
                        if player then
                            player:ChangeCamera(false)
                        end
                    end
                else
                    local gameMode = UE.UGameplayStatics.GetGameMode(self)
                    local player = gameMode:BPI_GetPlayer()
                    if player then
                        player:ChangeCamera(false)
                    end
                end
            end
        else
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            local player = gameMode:BPI_GetPlayer()
            if player then
                player:ChangeCamera(false)
            end
        end
    end
end

return M
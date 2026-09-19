local UIUtils = require "_Game.Utils.UIUtils"
local NameUtil = require("_Game.Utils.NameUtil")
local Database = require("_Game.Utils.Database")
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local PlotSystem = require "Module.Plot.PlotSystem"
local Client = require "Network.Client"
local GlobalConfig = require('GlobalConfig')
local Update = require "Update.Update"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Login_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    -- self:InitUI()
    self.Overridden.Construct(self)
    NetworkMessageManager:GetInstance():AddListener("res_login", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_List_Success", self)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.LoggedIn = false
    self.bSkip = false

    self.HideCursor = false
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Confirm)

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener("res_login", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_List_Success", self)
    -- if self.UI_LoginPanel then
    --     self.UI_LoginPanel.PlayHideFinished:Remove(self, self.On_LoginPanel_PlayHideFinished)
    --     UIManager:GetInstance():RemoveUI(self.UI_LoginPanel)
    --     self.UI_LoginPanel = nil
    -- end
  
    if self.LoopLevelSequencePlayerActor then
        self.LoopLevelSequencePlayerActor:K2_DestroyActor()
        self.LoopLevelSequencePlayerActor = nil
    end
    if self.LoopLevelSequencePlayerActor2 then
        self.LoopLevelSequencePlayerActor2:K2_DestroyActor()
        self.LoopLevelSequencePlayerActor2 = nil
    end
    if self.StartLevelSequencePlayerActor then
        self.StartLevelSequencePlayerActor:K2_DestroyActor()
        self.StartLevelSequencePlayerActor = nil
    end
end


function M:Tick(geometry, deltaTime)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if self.UpdateLoadingProgress then 
        if playerController.LoadStreamLevel then
            if playerController.LoadStreamLevel:IsLevelLoaded() then
                self:ProcessLevelLoaded()
            else
                local rate = UE.UGHSFunctionLibrary.LSS_Plugin_GetAsyncLoadPercentage(playerController.LoadStreamLevel:GetWorldAssetPackageFName())
                self:UpdateProgress(rate)
            end
        end
    elseif self.StartUpdateFile then
        local info = Update.get_progress()
        if info.LastError ~= "" then
            self.StartUpdateFile = false
            local text
            if info.LastError == "Not enough space on device." then
                text = string.format(Database.L10n(310))
            else
                text = string.format(Database.L10n(309), info.LastError)
            end
            UIUtils.ShowComNotice(
                text,
                self,
                function()
                    UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                end
            )
            return
        end
        local TmpCurDownLoadValue = tonumber(info.BytesDownloaded) - self.TmpSize
        self.PreDownloadValue = self.PreDownloadValue or TmpCurDownLoadValue
        self.PreDownloadTime = self.PreDownloadTime or os.time()
        if TmpCurDownLoadValue > self.PreDownloadValue then
            self.PreDownloadValue = TmpCurDownLoadValue
            self.PreDownloadTime = os.time()
        else
            if os.time() - self.PreDownloadTime > 30 then
                self.StartUpdateFile = false
                local text = string.format(Database.L10n(308))
                UIUtils.ShowComNotice(
                    text,
                    self,
                    function()
                        UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                    end
                )
                return
            end
        end
        -- ---@class FChunkCoreStats
        -- ---@field public FilesDownloaded integer
        -- ---@field public TotalFilesToDownload integer
        -- ---@field public BytesDownloaded string
        -- ---@field public TotalBytesToDownload string
        -- ---@field public ChunksMounted integer
        -- ---@field public TotalChunksToMount integer
        -- ---@field public LoadingStartTime FDateTime
        -- ---@field public LastError string
        -- local FChunkCoreStats = {}
        print("----------download:" .. tostring(info.BytesDownloaded) .. ",TotalBytesToDownload:" .. tostring(info.TotalBytesToDownload))
        self.CurDownLoadValue = tonumber(info.BytesDownloaded) - self.TmpSize
        if self.CurDownLoadValue < 0 then
            self.CurDownLoadValue = 0
        end
        self.AllLoadValue = tonumber(info.TotalBytesToDownload) - self.TmpSize
        self:UpdateFileUI()
        -- if self.CurDownLoadValue >= self.AllLoadValue then
        --     self:EnterExtractFileProcess()
        -- end
    elseif self.StartExtractFile then
        self.CurDownLoadValue = math.min(self.CurDownLoadValue + math.random(0, 10) * math.random(0, 10) * 1024, self.AllLoadValue)
        self:UpdateExtractUI()
        if self.CurDownLoadValue >= self.AllLoadValue then
            self:EnterLoginProcess()
        end
    elseif self.StartLoadStreamLevel then
        if playerController.LoadStreamLevel then
            if playerController.LoadStreamLevel:IsLevelLoaded() then
                self:LoadStreamLevelEnd()
            else
                --local rate = UE.UGHSFunctionLibrary.LSS_Plugin_GetAsyncLoadPercentage(playerController.LoadStreamLevel:GetWorldAssetPackageFName())
                --self:UpdateLoadStreamLevel(rate)

                local rate = (self.LoadRate or 0) + deltaTime * 50
                --print("=====rate:" .. tostring(rate))
                self.LoadRate = math.min(rate, 100)
                self:UpdateLoadStreamLevel(self.LoadRate)
            end
        end
    end
end

function M:InitData()
    --local deviceId = UE4.UKismetSystemLibrary.GetDeviceId()
    print("===GlobalConfig.Channel:" .. GlobalConfig.Channel)
end

function M:InitUI()
    self.Loading_Bar:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Btn_Background.OnClicked:Add(self, self.OnClicked_Btn_Background)
    self.Btn_User.OnClicked:Add(self, self.OnClicked_Btn_User)
    self.Btn_Notice.OnClicked:Add(self, self.OnClicked_Btn_Notice)
    self.Btn_Skip.OnClicked:Add(self, function()
        self:OnClicked_Btn_Skip(true)
    end)
    self.Btn_Enter.OnClicked:Add(self, function()
        self:OnClicked_Btn_Skip(false)
    end)
    self.ExitBtn.OnClicked:Add(self, self.OnClicked_Btn_Exit)

    if GlobalConfig.Channel ~= "develop" and not UE.UGHSFunctionLibrary.WithEditor() then
        -- self.Button_Notice:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Button_Skip:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Button_Enter:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.IsSteamPlatform then
        -- self.Button_Notice:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Button_User:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Button_Skip:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Button_Enter:SetVisibility(UE.ESlateVisibility.Hidden)

        self.Btn_Background:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    --登录面板
    self.UI_LoginPanel.Btn_Login.OnClicked:Add(self, self.OnClicked_Btn_Login)

    self.UI_LoginPanel.Btn_Register.OnClicked:Add(self, self.OnClicked_Btn_Register)
    self.UI_LoginPanel.Register.OnClicked:Add(self, self.RegisterAndLogin)
    self.UI_LoginPanel.Btn_Close.OnClicked:Add(self, self.BackToLogin)
    self.UI_LoginPanel.Btn_ForgetPwd.OnClicked:Add(self, self.OnClicked_Btn_ForgetPwd)
    self.UI_LoginPanel.PlayHideFinished:Add(self, self.On_LoginPanel_PlayHideFinished)

    self.UI_LoginPanel.AccountName.OnTextChanged:Add(self, self.UpdateRegisterButton)
    self.UI_LoginPanel.Password.OnTextChanged:Add(self, self.UpdateRegisterButton)
    self.UI_LoginPanel.ConfirmPassword.OnTextChanged:Add(self, self.UpdateRegisterButton)
    self:UpdateRegisterButton()
    self:HideEnterGameText()
end

function M:OnLevelLoaded()
    local sequencePath = '/Game/_Game/Characters/perform/login/enteranim_fly_loop1_login.enteranim_fly_loop1_login'
    local levelSequence = LoadObject(sequencePath)
    if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(sequencePath))
        return
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    print("----------------OnLevelLoaded")
    local LoopCount = UE.FMovieSceneSequenceLoopCount()
    LoopCount.Value = -1
    local Settings = UE.FMovieSceneSequencePlaybackSettings()
    Settings.LoopCount = LoopCount
    
    local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
        Settings, nil)
    self.LoopLevelSequencePlayerActor = levelSequenceActor
    self.LoopLevelSequencePlayerActor.SequencePlayer:PlayLooping(-1)
end

------------------------------------------------------------------------------
---消息处理
local ELoginResultType = {
    OK                 = 0,
    CHANNEL_MISMATCH   = 1,
    NO_ACCOUNT         = 2,
    PASSWORD_NOT_MATCH = 3,
    SURE_AGENT_FAILED  = 4,
    UPDATE_DB_FAILED   = 5,
    CODE_NOT_MATCH     = 6,
}

---@param parsed_msg ResLoginMessage
function M:res_login(result, msgId, parsed_msg)
    print("===res_login")
    if result == 0 then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance.LoggedIn = true
        if gameInstance.IsSteamPlatform then
            self.Btn_Background:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.Btn_Background:SetVisibility(UE.ESlateVisibility.Hidden)
            local saveGameLogin = self:GetSaveGameLogin()
            if saveGameLogin then
                print("===lastAcount:" .. tostring(parsed_msg.req_data.account_name) .. ",lastPwd:" .. tostring(parsed_msg.req_data.password))
                saveGameLogin.LastLoginAccount = parsed_msg.req_data.account_name
                saveGameLogin.LastLoginpassword = parsed_msg.req_data.password
                UE.UGameplayStatics.SaveGameToSlot(saveGameLogin, 'SG_SaveGame_Login', 0)
            end
            if not self.CachedAccount or '' == self.CachedAccount then
                self.CachedAccount = parsed_msg.req_data.account_name
            end
            if self.UI_LoginPanel:IsVisible() then
                self.UI_LoginPanel:Hide()
            else
                self.IsPlayFront = false
                self:On_LoginPanel_PlayHideFinished()
            end
        end
    end
    self.isReqLogin = false
end

function M:OnMsg_Req_Character_List_Success()
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:LoadTeamList()
    gameInstance:LoadSaveGameChar()
    PlotSystem:GetInstance():SetGameInstance(gameInstance)
    local MallSystem = require("Module.ShopSystem.MallSystem")
    MallSystem:GetInstance():SetGameInstance(gameInstance)
    local QuestSystem = require('Module.Quest.QuestSystem')
    QuestSystem:GetInstance():SetGameInstance(gameInstance)
    CharacterSystem:GetInstance():SetGameInstance(gameInstance)
    local PlayerSystem = require("Module.Player.PlayerSystem")
    PlayerSystem:GetInstance():SetGameInstance(gameInstance)
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    if GlobalConfig.Channel == "develop" and string.startswith(self.CachedAccount, "skip") then
        saveGameSpeak.StoryFinished = false
        gameInstance:SaveSaveGameSpeak()
    end
    if not gameInstance.IsSteamPlatform then
        UIManager:GetInstance():RemoveUI(self)
    end

    saveGameSpeak.StoryFinished = self.bSkip
    gameInstance:SaveSaveGameSpeak()

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    if gameMode.InitData then gameMode:InitData() end
    gameInstance:LoadSaveGameSettings()
    gameInstance:UpdateVolumeSetting()
end

------------------------------------------------------------------------------
---事件处理
function M:OnClicked_Btn_Background()
    local now = os.time()
    if not self.LastClickGachaTenTime then 
        self.LastClickGachaTenTime = now - 1
    end
    if now - self.LastClickGachaTenTime < 0.5 then
        print('------点击太快') 
        return 
    end
    self.LastClickGachaTenTime = now
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.bIsInitReqMsg then 
        print('--------等待登录消息回执完毕中')
        return 
    end
    if gameInstance.IsSteamPlatform then
        if self.bIsLoadingEnd and gameInstance.InitLoginWithSteamSuccess and not self.isReqLogin then
            self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:ShowEnterGameText()
            -- 自动登录
            print("-------AutoLogin")
            gameInstance:LuaLogin('', '', gameInstance:GetDeviceId())
            self.isReqLogin = true
            self.lastReqLogin = os.time()
        else
            if self.isReqLogin then
                self.lastReqLogin = self.lastReqLogin or os.time()
                --上一次请求登录，可能连接不上，失败了，重新请求下
                if os.time() - self.lastReqLogin > 5 then
                    gameInstance:LuaLogin('', '', gameInstance:GetDeviceId())
                    self.lastReqLogin = os.time()
                end
            end
            print("---------等待登录完成")
            UIUtils.ShowComNotice(Database.L10n(457), self, function() end)
        end
        return
    end

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not self.login_wait and not gameInstance.bIsInitReqMsg and not playerController.EnterGameAnimating and self.EnterGameText:IsVisible() then
        --快捷登录
        print("========快捷登录")
        -- local device_id = ""
        -- if GlobalConfig.Channel == "test1" then
        --     device_id = UE.UGHSFunctionLibrary.GetDeviceIdAnyway()
        -- end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:LuaLogin(self.CachedAccount, self.CachedPwd, gameInstance:GetDeviceId())
    end
end

function M:OnClicked_Confirm()
    if not self:IsAnimationPlaying(self.ShowCompanyLogo) and not self.UI_LoginPanel.PlayingAnimation and not self.PlaySequenceFlag and not self.UI_LoginPanel:IsVisible() then
        self:OnClicked_Btn_Login()
    end
end

function M:OnClicked_Btn_User()
    local saveGameLogin = self:GetSaveGameLogin()
    if saveGameLogin then
        if saveGameLogin.LastLoginAccount and saveGameLogin.LastLoginpassword and saveGameLogin.LastLoginAccount ~= '' and saveGameLogin.LastLoginpassword ~= '' then
            if not self:IsAnimationPlaying(self.ShowCompanyLogo) and not self.UI_LoginPanel.PlayingAnimation and not self.PlaySequenceFlag then
                if not self.UI_LoginPanel:IsVisible() then
                    self:HideEnterGameText()
                    self.Game_Logo:SetVisibility(UE.ESlateVisibility.Hidden)

                    self.IsPlayFront = true
                    self:On_LoginPanel_PlayHideFinished()
                    self.PlaySequenceFlag = true
                else
                    self.IsPlayFront = false
                    self:On_LoginPanel_PlayHideFinished()
                    self.PlaySequenceFlag = true
                    self.UI_LoginPanel:Hide()
                end
            end
        end
    end
end

function M:On_LoginPanel_PlayHideFinished()
    if not self.StartLevelSequencePlayerActor then
        local sequencePath = '/Game/_Game/Characters/perform/enteranim_fly_start.enteranim_fly_start'
        local levelSequence = LoadObject(sequencePath)
        if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
            LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(sequencePath))
            return 
        end
        -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
        print("----------------On_LoginPanel_PlayHideFinished")
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
            Settings, nil)
        self.StartLevelSequencePlayerActor = levelSequenceActor
        self.StartLevelSequencePlayerActor.SequencePlayer.OnFinished:Add(self, self.OnSequenceShowEnd)
    end
    if self.IsPlayFront then
        
        if self.LoopLevelSequencePlayerActor then
            self.LoopLevelSequencePlayerActor.SequencePlayer:Stop()
        end
        self.StartLevelSequencePlayerActor.SequencePlayer:Play()
    else
        if self.LoopLevelSequencePlayerActor2 then
            self.LoopLevelSequencePlayerActor2.SequencePlayer:Stop()
        end
        self.StartLevelSequencePlayerActor.SequencePlayer:PlayReverse()
    end

    self.PlaySequenceFlag = true
end

function M:UpdateRegisterButton()
    self.UI_LoginPanel.Register:SetIsEnabled(self.UI_LoginPanel.AccountName:GetText() ~= ""
        and self.UI_LoginPanel.Password:GetText() ~= ""
        and self.UI_LoginPanel.ConfirmPassword:GetText() ~= "")
end

function M:OnSequenceShowEnd()
    self.PlaySequenceFlag = false

    if self.IsPlayFront then
        self.UI_LoginPanel:Show()
        if not self.LoopLevelSequencePlayerActor2 then
            local sequencePath = '/Game/_Game/Characters/perform/enteranim_fly_loop.enteranim_fly_loop'
            local levelSequence = LoadObject(sequencePath)
            if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
                LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(sequencePath))
                return 
            end
            -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
            print("----------------OnSequenceShowEnd")
            local LoopCount = UE.FMovieSceneSequenceLoopCount()
            LoopCount.Value = 0
            local Settings = UE.FMovieSceneSequencePlaybackSettings()
            Settings.LoopCount = LoopCount

            local _, levelSequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, 
                Settings, nil)
            self.LoopLevelSequencePlayerActor2 = levelSequenceActor
            self.LoopLevelSequencePlayerActor2.SequencePlayer.OnFinished:Add(self, self.OnSequenceShowEnd)
        end
        if self.LoopLevelSequencePlayerActor2 then
            self.LoopLevelSequencePlayerActor2.SequencePlayer:PlayLooping(-1)
        end
    else
        self:ShowEnterGameText()
        self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        if self.LoopLevelSequencePlayerActor then
            self.LoopLevelSequencePlayerActor.SequencePlayer:PlayLooping(-1)
        end
    end
end

function M:OnClicked_Btn_Notice()
    local widget_class = UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_Bulletin/UI_Bulletin.UI_Bulletin_C')
    ---@type UI_Bulletin_C
    local widget = UE.UWidgetBlueprintLibrary.Create(self, widget_class)
    UIManager:GetInstance():AddUI(widget)
    widget:Setup()
    -- widget.BulletinTab:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
end

function M:OnClicked_Btn_Skip(bSkip)
    self.bSkip = bSkip
end

function M:OnClicked_Btn_Exit()
    UIUtils.ShowComNotice(Database.L10n(282), self, function()
        UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
    end, function() end)
end

function M:OnClicked_Btn_Login()
    local account = self.UI_LoginPanel.EditableTextAccount:GetText() 
    local pwd = self.UI_LoginPanel.EditableTextPassword:GetText()
    print("=====acount:" .. tostring(account) .. ",pwd:" .. tostring(pwd))

    if account == "" or pwd == "" then
        UIUtils.ShowNotify(self, Database.L10n(83100001))
        return
    end

    if not self.isReqLogin and account ~= '' and pwd ~= "" then
        self.CachedAccount = account 
        self.CachedPwd = pwd
        -- local device_id = ""
        -- if GlobalConfig.Channel == "test1" then
        --     device_id = UE.UGHSFunctionLibrary.GetDeviceIdAnyway()
        -- end
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        UIManager:GetInstance().account = self.CachedAccount
        gameInstance:LuaLogin(account, pwd, gameInstance:GetDeviceId())
        self.isReqLogin = true
    end
end

function M:OnClicked_Btn_Register()
    self.UI_LoginPanel.Login_Panel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Img_bg:SetVisibility(UE.ESlateVisibility.Visible)
    self.UI_LoginPanel.AccountManagement:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.UI_LoginPanel:PlayAnimationForward(self.UI_LoginPanel.vfxIn_AccountManagement)
end

function M:RegisterAndLogin()
    if GlobalConfig.Channel == "test1" then
        UIUtils.ShowNotify(self, Database.L10n(50500))
        return
    end
    local accountName = self.UI_LoginPanel.AccountName:GetText() 
    local password = self.UI_LoginPanel.Password:GetText()
    local confirmPassword = self.UI_LoginPanel.ConfirmPassword:GetText()

    if password ~= confirmPassword then
        UIManager:GetInstance():Notify(Database.L10n(83100004))
        return
    end

    local meetCriteria, warning = NameUtil.MeetCriteria(accountName, {
        { NameUtil.AccountLength },
        { NameUtil.IsValidAccountName },
    })

    if not meetCriteria then
        UIManager:GetInstance():Notify(Database.L10n(warning))
        return
    end

    meetCriteria, warning = NameUtil.MeetCriteria(password, {
        { NameUtil.PasswordLength },
        { NameUtil.IsValidPassword },
    })

    if not meetCriteria then
        UIManager:GetInstance():Notify(Database.L10n(warning))
        return
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:LuaRegister(accountName, password)
end

function M:BackToLogin()
    self.UI_LoginPanel.Login_Panel:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.Img_bg:SetVisibility(UE.ESlateVisibility.Hidden)
    self.UI_LoginPanel.AccountManagement:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnClicked_Btn_ForgetPwd()
    if not UE.UGHSFunctionLibrary.WithEditor() then
        if GlobalConfig.Channel == "test1" then
            UIUtils.ShowNotify(self, Database.L10n(50500))
            return
        end
    end
end

function M:OnProgressShow()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.IsInLoginMap = true
    self:PlayAnimationForward(self.ShowGameLogo, 1.0, false)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.OnProcessLevelLoaded then
        playerController:OnProcessLevelLoaded()
    end
    self:EnterCheckVersionProcess()
end

---------------------------------------------------------
---登录流程
---检测版本
function M:EnterCheckVersionProcess()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.IsSteamPlatform then -- not UE.UGHSFunctionLibrary.WithEditor()
        self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        if gameInstance.InitLoginWithSteamFailed then
            UIUtils.ShowComNotice(
                Database.L10n(456),
                self,
                function()
                    UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                end
            )
            return
        end
    end
    --TODO version file Check
    self:CheckVersionStart()
end

function M:CheckVersionStart()
    self.Text_Tip:SetText(Database.L10n(297))
    self.Loading_Bar:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_Progress:SetVisibility(UE.ESlateVisibility.Hidden)
    self.EnterGameText:SetVisibility(UE.ESlateVisibility.Hidden)
    if GlobalConfig.local_build then
        UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.CheckVersionEnd }, 
            1, 
            false
        )
        -- UIUtils.ShowComNotice(
        --     "Reload", 
        --     self, 
        --     function()
        --         local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        --         gameInstance:Reload()
        --     end
        -- )
        return
    end

    if not UE.UGHSFunctionLibrary.WithEditor() then
        Update.check_version(function(result, response)
            if result then
                if Update.need_update_version() then
                    self.Text_Tip:SetText(Database.L10n(298))
                    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                    Update.update_version(gameInstance, function(result, str)
                        LOG_INFO(result, str)
                        if result then
                            self.Text_Tip:SetText(Database.L10n(299))
                            self:CheckVersionEnd(false, Update.need_update_chunks(), Update.partial_size, Update.patch_size)
                        else
                            self.Text_Tip:SetText(Database.L10n(300))
                            LOG_WARN(str)
                            UIUtils.ShowComNotice(
                                Database.L10n(301), 
                                self, 
                                function()
                                    self:CheckVersionStart()
                                end
                            )
                        end
                    end)
                else
                    self:CheckVersionEnd(false, Update.need_update_chunks(), Update.partial_size, Update.patch_size)
                end
            else
                self.Text_Tip:SetText(Database.L10n(305))
                LOG_WARN(string.format("check_version failed response is: %s", response))
                UIUtils.ShowComNotice(
                    Database.L10n(306), 
                    self, 
                    function()
                        self:CheckVersionStart()
                    end
                )
            end
        end)
    else
        UE.UKismetSystemLibrary.K2_SetTimerDelegate(
            { self, self.CheckVersionEnd }, 
            1, 
            false
        )
    end
end

function M:CheckVersionEnd(needUpdateApp, needUpdateFile, partialSize, patchSize)
    if GlobalConfig.local_build then
        self:EnterLoadStreamLevelProcess()
        return
    end
    -- local needUpdateApp = false --math.random(0, 1) == 0
    -- local needUpdateFile = false --math.random(0, 1) == 0
    -- self.AllLoadValue = math.random(1, 100) * 1024 * 1024
    if not UE.UGHSFunctionLibrary.WithEditor() then
        -- local total_size = patchSize
        -- if not Update.is_chunk_cached(1) then
        --     total_size = total_size + partialSize
        -- end
        local total_size = Update.get_size_for_download()
        self.TmpSize = Update.get_tmp_size()
        self.AllLoadValue = total_size - self.TmpSize
    else
        self.AllLoadValue = 0
    end
    if needUpdateApp then
        local text = Database.L10n(307)
        UIUtils.ShowComNotice(
            text, 
            self, 
            function()
                UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
            end
        )
    elseif needUpdateFile then
        self:EnterUpdateFileProcess()
    else
        if not UE.UGHSFunctionLibrary.WithEditor() then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            Update.mount_chunks(gameInstance, function(result, str)
                if result then
                    self:EnterLoadStreamLevelProcess()
                else
                    LOG_WARN(str)
                end
            end)
        else
            self:EnterLoadStreamLevelProcess()
        end
    end
end

--下载文件
function M:EnterUpdateFileProcess()
    self.CurDownLoadValue = 0
    self:UpdateFileUI()
    self.Panel_Progress:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    
    if self.AllLoadValue > 20 * 1024 * 1024 then
        local text = string.format(Database.L10n(303), self:GetFileSize(self.AllLoadValue--[[, '%d']]))
        UIUtils.ShowComNotice(
            text, 
            self, 
            function()
                self.StartUpdateFile = true
                Update.mount_chunks(gameInstance, function(result, str)
                    if result then
                        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                        gameInstance:Reload()
                        -- local text = "更新完毕，请重启游戏！"
                        -- UIUtils.ShowComNotice(
                        --     text,
                        --     self,
                        --     function()
                        --         UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                        --     end
                        -- )
                        -- self:EnterLoadStreamLevelProcess()
                    else
                        self.Text_Tip:SetText(Database.L10n(302))
                        LOG_WARN(str)
                    end
                end)
            end, 
            function()
                UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
            end
        )
    else
        self.StartUpdateFile = true
        Update.mount_chunks(gameInstance, function(result, str)
            if result then
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                gameInstance:Reload()
                -- local text = "更新完毕，请重启游戏！"
                -- UIUtils.ShowComNotice(
                --     text,
                --     self,
                --     function()
                --         UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                --     end
                -- )
                -- self:EnterLoadStreamLevelProcess()
            else
                LOG_WARN(str)
            end
        end)
    end
end

function M:GetFileSize(size, format)
    if not format then format = "%.2f" end
    local kb = 1024
    local mb = kb * kb
    local gb = mb * mb
    if size > gb then
        return string.format(format, size / gb) .. "G"
    elseif size > mb then
        return string.format(format, size / mb) .. "M"
    else
        return string.format(format, size / kb) .. "K"
    end
    return size
end

function M:UpdateFileUI()
    self.ProgressText:SetText(string.format("%.2f%%", self.CurDownLoadValue / self.AllLoadValue * 100))
    self.NativeProgressBar:SetPercent(self.CurDownLoadValue / self.AllLoadValue)
    self.Text_Tip:SetText(Database.L10n(295) .. self:GetFileSize(self.CurDownLoadValue) .. '/' .. self:GetFileSize(self.AllLoadValue) .. ")")
end

--解压缩文件
function M:EnterExtractFileProcess()
    self.StartUpdateFile = false

    self.ProgressText:SetText(string.format("%.2f%%", self.CurDownLoadValue / self.AllLoadValue * 100))
    self.NativeProgressBar:SetPercent(0)

    self.Text_Tip:SetText(Database.L10n(296))

    self.CurDownLoadValue = 0
    self.AllLoadValue = 2048000
    self.StartExtractFile = true
end

function M:UpdateExtractUI()
    self.ProgressText:SetText(string.format("%.2f%%", self.CurDownLoadValue / self.AllLoadValue * 100))
    self.NativeProgressBar:SetPercent(self.CurDownLoadValue / self.AllLoadValue)
end

function M:UpdateExtractEnd()
    self.Panel_Update:SetVisibility(UE.ESlateVisibility.Hidden)
    self:EnterLoadStreamLevelProcess()
end

--进入加载场景流程
function M:EnterLoadStreamLevelProcess()
    --临时关闭，测试使用
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:LoadLevel("CityMap", true)
   
    -- local path = UE.UKismetSystemLibrary.MakeSoftObjectPath("/Game/_Game/Maps/City/CityMap.CityMap")
    -- UE.UGHSFunctionLibrary.PreloadMapWithPath(path, function(_, result)
    --     if result == 1 then
    --         UE.UGameplayStatics.OpenLevel(self, "CityMap", false, '')
    --     else
    --         LOG_ERROR("EnterLoadStreamLevelProcess failed %d", result)
    --     end
    -- end)
    -- UE.UGameplayStatics.GetPlayerController(self, 0):ClientTravel("CityMap", UE.ETravelType.TRAVEL_Relative, true)
    self.Text_Tip:SetText(Database.L10n(263))
    self:UpdateLoadStreamLevel(0)
end

function M:LoadStreamLevelProces()
    self.Loading_Bar:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_Progress:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

    self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self:ChangeGameLogDissolve(2)

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.OnProcessLevelLoaded then
        playerController:OnProcessLevelLoaded()
    end

    self.Text_Tip:SetText(Database.L10n(263))
    self.ProgressText:SetText(0)
    self.NativeProgressBar:SetPercent(0)

    self.LoadRate = 0

    local cityStreamPath = "City1BusinessCenter"
    UE.UGHSFunctionLibrary.PreloadStreamingLevelByName(self, cityStreamPath)
    playerController.LoadStreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, cityStreamPath)
    self.StartLoadStreamLevel = true
end

function M:UpdateLoadStreamLevel(rate)
    self.ProgressText:SetText(string.format("%.2f%%", rate))
    self.NativeProgressBar:SetPercent(rate / 100)
end

function M:LoadStreamLevelEnd()
    self.StartLoadStreamLevel = false
    self.bStartLoad = false
    self.LoadRate = 0
    self:UpdateLoadStreamLevel(1)
    self:EnterLoginProcess()
end

function M:AutoLogin()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if self.bIsLoadingEnd and gameInstance.InitLoginWithSteamSuccess then
        self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self:ShowEnterGameText()
        -- 自动登录
        gameInstance:LuaLogin('', '', gameInstance:GetDeviceId())
    end
end

--登录显示
function M:EnterLoginProcess()
    print('--------EnterLoginProcess')
    self.StartUpdateFile = false
    self.StartExtractFile = false

    self.Icon:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.bIsLoadingEnd = true
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.IsSteamPlatform then
        --self:AutoLogin()
        if gameInstance.InitLoginWithSteamSuccess then
            self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:ShowEnterGameText()
        else
            UIUtils.ShowComNotice(
                Database.L10n(456),
                self,
                function()
                    UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
                end
            )
        end
        return
    end

    --判断是否已经登录过了
    local saveGameLogin = self:GetSaveGameLogin()
    if saveGameLogin then
        print("===lastAcount:" .. tostring(saveGameLogin.LastLoginAccount) .. ",lastPwd:" .. tostring(saveGameLogin.LastLoginpassword))
        if saveGameLogin.LastLoginAccount and saveGameLogin.LastLoginpassword and saveGameLogin.LastLoginAccount ~= '' and saveGameLogin.LastLoginpassword ~= '' then
            self.CachedAccount = saveGameLogin.LastLoginAccount
            self.CachedPwd = saveGameLogin.LastLoginpassword

            self.Loading_Bar_Content:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Game_Logo:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self:ShowEnterGameText()
            UIManager:GetInstance().account = self.CachedAccount
        else
            self.Btn_Background:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Game_Logo:SetVisibility(UE.ESlateVisibility.Hidden)
            self.Loading_Bar:SetVisibility(UE.ESlateVisibility.Hidden)
            self:PlayAnimationReverse(self.ShowGameLogo, 1.0, false)
            self.UI_LoginPanel:Show()
        end
    end
end

function M:GetSaveGameLogin()
    local gameSave = nil
    if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Login", 0) then
        gameSave = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_Login", 0)
    else
        gameSave = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load("/Game/_Game/Blueprints/Game/SG_SaveGame_Login.SG_SaveGame_Login_C"))
    end
    --UE.UGameplayStatics.SaveGameToSlot(gameSave, 'SG_SaveGame_Login', 0)
    return gameSave
end

function M:IsLoginPanelVisible()
    return self.UI_LoginPanel:IsVisible()
end

return M
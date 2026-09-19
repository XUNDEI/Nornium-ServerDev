--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "_Game.Blueprints.Game.BP_GameMode_Fight_C"

if not BUILD_SHIPPING then
    require("LuaPanda")
    require("LuaPandaImp").start("127.0.0.1",8818)
end

local Client = require "Network.Client"
local SrpgController = require("Module.Srpg.SrpgController")
local BossRushController = require("Module.BossRush.BossRushController")
local SrpgModel = require("Module.Srpg.SrpgModel")
local CharacterSystem = require("Module.CharacterSystem.CharacterSystem")
local Protos = require "Helper.Protos"
-- Client.ENABLE_LOG = true
--Table
local worldTable = require "ClientDatas.d_word_cn"
local universeTable = require "ClientDatas.d_srpg_universe"
local mainPosTable = require "ClientDatas.d_srpg_main_pos_base"
local cardTable = require "ClientDatas.d_srpg_card_base"
local UIUtils = require '_Game.Utils.UIUtils'
local GlobalConfig = require('GlobalConfig')
local Update = require "Update.Update"
local ErrorFormatter = require("Helper.ErrorFormatter")
local NoticeController = require("Module.Notice.NoticeController")

local HOST = GlobalConfig.HOST
local PORT = GlobalConfig.PORT
-- 外网
if not UE.UGHSFunctionLibrary.WithEditor() and HOST == "192.168.0.201" then
    HOST = "nat.syhlgame.cn"
    PORT = PORT + 30000
end

local Database = require "_Game.Utils.Database"

---@type BP_GameInstance_C
local BP_GameInstance_C = Class()

BP_GameInstance_C.ControllerPlatformChanged = "BP_GameInstance_C.ControllerPlatformChanged"
BP_GameInstance_C.IsSteamPlatform = false

function BP_GameInstance_C:Initialize()
    local msg = [[
    Hello World!
    —— 本示例来自 "BP_GameInstance_C.lua"
    ]]
    LOG_INFO(msg)
    self.FIGHT_STATE = {
        EXPLORE = 1,
        BOSS = 2,
        EVENT = 3,
        DailyCopy = 4,
        MAINPOS = 5,
        WAITING = 6,
        ChallengeCopy = 7,
        CharTrainCopy = 8,
        TempCopy = 9,
        BOSSRUSH = 10,
        UNIVERSE = 11,
    }
    self.EVENT_STATE = {
        OPENING_EVENT_CHOOSING = 1,
        EXPLORE_EVENT_CHOOSING = 2,
        OPENING_EVENT_FIGHT = 3,
        EXPLORE_EVENT_FIGHT = 4,
        WAITING = 5,
    }

    ---@type ResUniverseMessage
    self.resUniverse = nil
    self.mainPosInfos = {}
    self.linesInfo = {}
    self.add_goods = { 0, 0, 0 }
    self.event_state = self.EVENT_STATE.WAITING
    self.fight_state = self.FIGHT_STATE.WAITING
    self.req_data = {}
    self.firstMission = true
    self.LastLoadingForStreamLevel = 0
end

function BP_GameInstance_C:ReceiveInit()
    LOG_INFO("ReceiveInit")

    Client.init()

    Client.register_connect(self.on_connect, self)
    NetworkMessageManager:GetInstance():AddListener('ServerError', self)
    NetworkMessageManager:GetInstance():AddListener("res_register", self)
    NetworkMessageManager:GetInstance():AddListener("res_login", self)
    NetworkMessageManager:GetInstance():AddListener("res_relogin", self)
    MessageManager:GetInstance():AddListener("res_new_universe", self)
    MessageManager:GetInstance():AddListener("res_new_universe_specific", self)
    MessageManager:GetInstance():AddListener(SrpgController.GameEnded, self)
    NetworkMessageManager:GetInstance():AddListener("res_gm_cmd", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_mission_info", self)
    NetworkMessageManager:GetInstance():AddListener("ntf_mission_result", self)
    NetworkMessageManager:GetInstance():AddListener('ntf_server_error', self)

    MessageManager:GetInstance():AddListener("UnFinished_Fight", self)
    self.UnFinished_Fight_Called = false

    ModuleManager:GetInstance():RegisterNetCmdController()

    MessageManager:GetInstance():AddListener("OnAppHasEnteredForeground", self)

    NetworkMessageManager:GetInstance():AddListener('ntf_kick', self)
    MessageManager:GetInstance():AddListener('OnPickSuccess', self)    
    MessageManager:GetInstance():AddListener('OnMsg_Bag_Init', self)
    MessageManager:GetInstance():AddListener('OnMsg_Player_LevelUp', self)
    MessageManager:GetInstance():AddListener('OnChangedStreamingLevel', self)

    MessageManager:GetInstance():AddListener('OnMsg_MailInit', self)
    MessageManager:GetInstance():AddListener("OnMsg_Res_Charge_Mall_Buy", self)

    UpdateManager:GetInstance():Startup()
    TimerManager:GetInstance():Startup()
    NoticeController:GetInstance():SetGameInstance(self)
    -- self.__update_handle = BindCallback(self, self.Update)
    -- UpdateManager:GetInstance():AddUpdate(self.__update_handle)

    if GlobalConfig.Channel ~= "develop" and not UE.UGHSFunctionLibrary.WithEditor() then
        UE.UKismetSystemLibrary.ExecuteConsoleCommand(self, "DisableAllScreenMessages", nil)
        UE.UKismetSystemLibrary.ControlScreensaver(false)
    end

    Update.init(GlobalConfig.UpdateDeploymentName, GlobalConfig.UpdateDeploymentUrl)
    Update.get_local_version(GlobalConfig.Version)

    -- self.IsSteamPlatform = true
    self.IsSteamPlatform = GlobalConfig.Channel:endswith("_steam") and not UE.UGHSFunctionLibrary.WithEditor() 
    print("---------------------IsSteamPlatform:" .. tostring(self.IsSteamPlatform))
    self.OnLoginWithSteam:Add(self, self.OnLoginWithSteamCallback)
    self.OnWebApiWithSteam:Add(self, self.OnWebApiWithSteamCallback)
    self.OnMicroTxnAuthorizationWithSteam:Add(self, self.OnMicroTxnAuthorizationWithSteamCallback)
    self.OnControllerPlatformChanged:Add(self, self.OnControllerPlatformChangedCallback)
    if self.IsSteamPlatform then
        local check = self:LoginWithSteam(0)
        if not check then
            LOG_ERROR("LoginWithSteam failed")
            --标记登录失败
            self.InitLoginWithSteamFailed = true
        end
    end

    if UE.UGHSFunctionLibrary.WithEditor() then
        LoadClass("/Game/_Game/Blueprints/UI/UI_Loading.UI_Loading_C")
        LoadClass("/Game/_Game/Blueprints/UI/UI_Loading2.UI_Loading2_C")
        LoadClass("/Game/_Game/Blueprints/UI/UI_StreamLoading.UI_StreamLoading_C")
        -- local BGPath = {
        --     [1] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading1.Loading1'",
        --     [2] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading2.Loading2'",
        --     [3] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading3.Loading3'",
        --     [4] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading4.Loading4'",
        --     [5] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading5.Loading5'",
        -- }
        -- for _, v in pairs(BGPath) do
        --     LoadObject(v)
        -- end
    end

    self.Overridden.ReceiveInit(self)
end
function BP_GameInstance_C:OnLoginWithSteamCallback(LocalUserNum, bWasSuccessful, UserId, SteamId, PchIdentity, Error)
    -- bWasSuccessful = true
    LOG_INFO("BP_GameInstance_C:OnLoginWithSteamCallback", LocalUserNum, bWasSuccessful, UserId, PchIdentity, Error)
    if bWasSuccessful then
        self.SteamAccountName = UserId
        self.SteamId = math.tointeger(SteamId)
        self.SteamIdentity = PchIdentity

        self.InitLoginWithSteamSuccess = true
    else
        self.InitLoginWithSteamSuccess = false
    end
end

function BP_GameInstance_C:OnWebApiWithSteamCallback(LocalUserNum, Token, Result)
    -- Result = 1
    LOG_INFO("BP_GameInstance_C:OnWebApiWithSteamCallback", LocalUserNum, Token, Result)
    if Result == 1 then
        self.SteamTicket = Token
        local bSuccess, SteamId = self:PreparePayWithSteam(0)
        if not bSuccess then
            LOG_ERROR("PreparePayWithSteam failed")
            return
        end
        local SteamIdInt = math.tointeger(SteamId)
        if not SteamIdInt then
            LOG_ERROR("SteamIdInt is nil")
            return
        end
        self:GetSteamUserInfo(0, SteamIdInt)
    end
end

function BP_GameInstance_C:GetSteamUserInfo(try_times, SteamIdInt)
    local host = "https://sdk-staging.feimogames.com:8002"
    local appKey = "hmtj0jGf0qTXn4gP"
    local appChannelKey = "steam2dwqzvbgztu"
    local url = string.format("%s/api/payment/v1/verify_steam_user/app_key/%s/app_channel_key/%s", host, appKey, appChannelKey)
    local rapidjson = require "rapidjson"
    local req = rapidjson.encode({
        appKey = appKey,
        appChannelKey = appChannelKey,
        steamId = SteamIdInt,
    })
    UE.UHTTPRequestClient.SetTimeoutDuration(10)
    UE.UHTTPRequestClient.MakeAHttpRequest(UE.EMethod.POST, url, {}, {
        ["Content-Type"] = "application/json",
    }, req, function(_, Status, ResponseString)
        if Status ~= 200 then
            if try_times < 10 then
                LOG_ERROR("Status ~= 200", Status)
                self:GetSteamUserInfo(try_times+1, SteamIdInt)
            else
                -- OnComplete(false, ResponseString)
            end
        else
            local res, err = rapidjson.decode(ResponseString)
            if not res then
                LOG_ERROR("rapidjson.decode failed", err)
                if try_times < 10 then
                    self:GetSteamUserInfo(try_times+1, SteamIdInt)
                else
                    -- OnComplete(false, ResponseString)
                end
                return
            end
            if res.code ~= 0 then
                LOG_ERROR("code ~= 0", res.code, res.msg)
                if try_times < 10 then
                    self:GetSteamUserInfo(try_times+1, SteamIdInt)
                else
                    -- OnComplete(false, ResponseString)
                end
                return
            end
            self.steam_user_info = res.InitData
        end
    end)
end

function BP_GameInstance_C:PayWithSteam(OrderItemId, OrderItemCount)
    local steam_user_info = self.steam_user_info
    if steam_user_info and steam_user_info.status == "Locked from purchasing" then
        LOG_ERROR("steam_user_info status invalid")
        return false
    end
    local bSuccess, SteamId, CurrentGameLanguage = self:PreparePayWithSteam(0)
    if not bSuccess then
        LOG_ERROR("PayWithSteam failed")
        return false
    end
    local SteamIdInt = math.tointeger(SteamId)
    Client.send("req_create_order", {
        order_item_id = OrderItemId,
        order_item_count = OrderItemCount,
        steam_id = SteamIdInt,
        steam_current_game_language = CurrentGameLanguage,
    }, true)
    LOG_INFO("wait PayWithSteam...")
    return true
end

function BP_GameInstance_C:OnMicroTxnAuthorizationWithSteamCallback(LocalUserNum, AppId, OrderId, Authorized)
    LOG_INFO("BP_GameInstance_C:OnMicroTxnAuthorizationWithSteamCallback", LocalUserNum, AppId, OrderId, Authorized)
    if Authorized == 1 then
        Client.send("req_finish_order", {
            app_id = tostring(AppId),
            sdk_order_id = OrderId,
            game_order_id = self.gameOrderId,
            access_token = self.key,
        }, true)
    else
        --取消交易
        local ui = self:GetUMG('UI_TopUp_Shop')
        if ui and UE.UKismetSystemLibrary.IsValid(ui) then
            ui.WaitPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        ui = self:GetUMG('UI_Waiting')
        if ui and UE.UKismetSystemLibrary.IsValid(ui) then
            self:RemoveUMG('UI_Waiting')
        end
    end
end

-- path
-- /client/notice/list
-- /client/system/serverStatus
-- /client/marquee/list
function BP_GameInstance_C:GMHttpPost(path, req_data, OnComplete)
    local host = GlobalConfig.GM_HOST
    local url = string.format("%s%s", host, path)
    local rapidjson = require "rapidjson"
    local req = req_data and rapidjson.encode(req_data) or ""
    UE.UHTTPRequestClient.SetTimeoutDuration(10)
    UE.UHTTPRequestClient.MakeAHttpRequest(UE.EMethod.POST, url, {}, {
        ["Content-Type"] = "application/json",
    }, req, function(_, Status, ResponseString)
        if Status ~= 200 then
            LOG_ERROR("Status ~= 200", Status)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        local isok, msg = pcall(rapidjson.decode, ResponseString)
        if not isok then
            LOG_ERROR("rapidjson.decode failed", ResponseString)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        if not msg or not msg.code or msg.code ~= 0 then
            LOG_ERROR("msg.code ~= 0", ResponseString)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        if OnComplete then
            OnComplete(true, Status, ResponseString, msg)
        end
    end)
end

local function snake_case_to_train_case(str)
    local arr = {}
    for word in string.gmatch(input, "[^_]+") do
        table.insert(arr, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    local result = table.concat(arr, "-")
    return result
end
-- path
-- /client/upload/xxx
function BP_GameInstance_C:GMHttpUpload(path, filename, body, req_data, OnComplete)
    local host = GlobalConfig.GM_HOST
    local url = string.format("%s%s", host, path)
    local headers = {
        ["Content-Type"] = "application/octet-stream",
        ["Filename"] = filename,
    }
    if req_data then
        for k, v in pairs(req_data) do
            headers[snake_case_to_train_case(k)] = tostring(v)
            -- table.insert(headers, string.format("%s: %s", snake_case_to_train_case(k), tostring(v)))
        end
    end
    local rapidjson = require "rapidjson"
    UE.UHTTPRequestClient.SetTimeoutDuration(10)
    UE.UHTTPRequestClient.MakeAHttpRequest(UE.EMethod.POST, url, {}, headers, body, function(_, Status, ResponseString)
        if Status ~= 200 then
            LOG_ERROR("Status ~= 200", Status)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        local isok, msg = pcall(rapidjson.decode, ResponseString)
        if not isok then
            LOG_ERROR("rapidjson.decode failed", ResponseString)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        if not msg or not msg.code or msg.code ~= 0 then
            LOG_ERROR("msg.code ~= 0", ResponseString)
            if OnComplete then
                OnComplete(false, Status, ResponseString)
            end
            return
        end
        if OnComplete then
            OnComplete(true, Status, ResponseString, msg)
        end
    end)
end

function BP_GameInstance_C:OnControllerPlatformChangedCallback(Platform)
    MessageManager:GetInstance():Broadcast(BP_GameInstance_C.ControllerPlatformChanged, Platform)
end

function BP_GameInstance_C:ReceiveShutdown()
    LOG_INFO("ReceiveShutdown")
    -- UpdateManager:GetInstance():RemoveUpdate(self.__update_handle)
    -- self.__update_handle = nil
    UpdateManager:GetInstance():Dispose()
    TimerManager:GetInstance():Dispose()
    self.Overridden.ReceiveShutdown(self)
end

function BP_GameInstance_C:GetConfigData(TableName, Id, KeyName)
    local t = Database.Query(TableName, Id)
    if not t then
        LOG_INFO(string.format("%s[%d] not found", TableName, Id))
        return false
    end
    local v = t[KeyName]
    if v == nil then
        LOG_INFO(string.format("%s[%d].%s not found", TableName, Id, KeyName))
        return false
    end
    local type_v = type(v)
    if type_v == "number" then
        return true, v
    end
    if type_v == "string" then
        return true, nil, nil, v
    end
    if type_v == "table" then
        local v1 = v[1]
        if v1 == nil then
            return true, nil, v, nil, v
        end
        local type_v_item = type(v1)
        if type_v_item == "number" then
            return true, nil, v
        end
        if type_v_item == "string" then
            return true, nil, nil, nil, v
        end
    end
    LOG_INFO(string.format("%s[%d].%s not found!!!", TableName, Id, KeyName))
    return false
end

local PREFIX = "Data.AttributeSet."

function BP_GameInstance_C:GetBossRushBuffInfo(Id)
    local tags = {}
    local values = {}

    local config = Database.Query("d_bossrush_buff", Id)

    for i = 1, #config.attribute do
        local attributeId = config.attribute[i]
        local attributeName = Database.Query("d_attributes", attributeId).attributeNameInFight
        local tagName = PREFIX .. attributeName
        local tag = UE.UGHSFunctionLibrary.RequestGameplayTag(tagName, false)

        table.insert(tags, tag)
        table.insert(values, config.value[i])
    end

    return tags, values
end

function BP_GameInstance_C:LuaRegister(AccountName, Password)
    if self.login_wait then
        return
    end
    self.login_wait = true
    self.account_name = AccountName
    self.register_or_login = {
        "req_register", {
            account_name = AccountName,
            password = Password,
            channel = GlobalConfig.Channel,
            client_version = GlobalConfig.Version,
            device_id = self:GetDeviceId(),
            platform_name = UE.UGameplayStatics.GetPlatformName(),
        }
    }
    self:GMHttpPost("/client/system/serverStatus", {}, function(res, status, responseString, msg)
        self:OnServerStatus(res, status, responseString, msg)
    end)
    LOG_INFO("注册")
end

function BP_GameInstance_C:LuaLogin(AccountName, Password, DeviceId, RegisterAndLogin)
    if not RegisterAndLogin and self.login_wait then
        return
    end
    self.login_wait = true
    if self.SteamAccountName then
        AccountName = self.SteamAccountName
    end
    self.account_name = AccountName
    UIManager:GetInstance().account = self.account_name
    local platform_name = UE.UGameplayStatics.GetPlatformName()
    self.register_or_login = { "req_login", {
        account_name = AccountName,
        password = Password,
        channel = GlobalConfig.Channel,
        client_version = GlobalConfig.Version,
        device_id = DeviceId,
        platform_name = platform_name,
        steam_ticket = self.SteamTicket,
        steam_identity = self.SteamIdentity,
        steam_id = self.SteamId,
    }}
    self:GMHttpPost("/client/system/serverStatus", {}, function(res, status, responseString, msg)
        self:OnServerStatus(res, status, responseString, msg)
    end)
    LOG_INFO("登录")
end

function BP_GameInstance_C:OnServerStatus(res, status, responseString, msg)
    if res then
        if msg.code == 0 and msg.data.status == 0 then
            if Client.need_connect() then
                Client.connect(HOST, PORT)
            elseif Client.isconnected() then
                LOG_DEBUG_TRACKBACK('------login OnServerStatus')
                Client.send(table.unpack(self.register_or_login))
            end
        else
            UIManager:GetInstance():ShowConfirm({
                notice = msg.data.notice,
                showCancel = false
            })
            self.login_wait = false
        end
    else
        UIManager:GetInstance():ShowConfirm({
            notice = "请检查你的网络",
            showCancel = false
        })
        self.login_wait = false
    end
end

-- function BP_GameInstance_C:Update(DeltaTime)
--     Client.update(DeltaTime)
-- end
local last_log_send_cache = 0
function BP_GameInstance_C:OnTick(DeltaTime)
    -- Client.update(DeltaTime)
    if self.bIsInitReqMsg then return end
    if self.UnFinished_Fight_Called then
        self.UnFinished_Fight_Called = false
        self:UnFinished_Fight()
        return
    end
    if Client and Client.isconnected() then
        local send_caches = Client.get_send_caches()
      
        if #send_caches > 0 then
            if os.time() - last_log_send_cache > 1 then
                last_log_send_cache = os.time()
                print('-------onTick：')
                for _, v in ipairs(send_caches) do
                    print('---->>msg_name:' .. tostring(v.msg_name))
                end
            end
        end
       
        if send_caches and #send_caches > 0 then
            local hasTimeOut = false
            for _, v in pairs(send_caches) do
                local delay = v.show_wait_delay or 10
                if os.time() - v.time > delay then
                    hasTimeOut = true
                    break
                end
            end
            if hasTimeOut then
                -- print("--------conect is delaying:")
                if not self.UIReconnect then
                    local ui = UIManager:GetInstance():AddUI("UI_Reconnect", true)
                    self.UIReconnect = ui
                end
                return
            end
        end
    end
    if not self.reconnecting then
        if self.UIReconnect then
            if UE.UKismetSystemLibrary.IsValid(self.UIReconnect) then
                UIManager:GetInstance():RemoveUI(self.UIReconnect, true)
            end
            self.UIReconnect = nil
        end
    end
    if self.reconnect_failed then
        repeat
            local widgetList = UIManager:GetInstance().layers.Loading:GetAllChildren()
            -- 有任意一个加载界面存在，则不再显示重连失败提示
            if widgetList:Length() > 0 then break end
            local topUI = UIManager:GetInstance():GetTopUI()
            if topUI then
                local className = string.lower(topUI:GetClass():GetName())
                if string.endswith(className, "_c") then
                    className = string.sub(className, 1, -3)
                end
                -- 如果是提示界面，则不再显示重连失败提示
                if className == "ui_com_notice" then break end
            end
            UIManager:GetInstance():RemoveAll()
            UE.UGameplayStatics.SetGamePaused(self, true)
            local UIUtils = require "_Game.Utils.UIUtils"
            local text = '<span color="#FF0000FF">' .. Database.L10n(50503) .. '</>'
            UIUtils.ShowComNotice(text, self, function()
                self.reconnect_failed = false
                self:LoadLevel("LoginMap", true)
            end)
        until false
    elseif self.reconnecting then
        repeat
            local widgetList = UIManager:GetInstance().layers.Loading:GetAllChildren()
            -- 有任意一个加载界面存在，则不再显示重连提示
            if widgetList:Length() > 0 then break end
            local topUI = UIManager:GetInstance():GetTopUI()
            if topUI then
                local className = string.lower(topUI:GetClass():GetName())
                if string.endswith(className, "_c") then
                    className = string.sub(className, 1, -3)
                end
                -- 如果是重连界面，则不再显示重连提示
                if className == "ui_reconnect" then break end
            end
            if self.UIReconnect then
                if UE.UKismetSystemLibrary.IsValid(self.UIReconnect) then
                    UIManager:GetInstance():RemoveUI(self.UIReconnect, true)
                end
                self.UIReconnect = nil
            end
            local ui = UIManager:GetInstance():AddUI("UI_Reconnect", true)
            ui.OnReconnecting:Add(self, self.OnReconnecting)
            ui.OnReconnectFailed:Add(self, self.OnReconnectFailed)
            self.UIReconnect = ui
            self.UIReconnect:StartReconnect("请检查你的网络...", "重连中...")
        until false
    end
end

function BP_GameInstance_C:on_connect(status)
    if status == Client.CLIENT_STATUS.CONNECTED then
        self.bConnected = true
        if self.reconnecting then
            if self.UIReconnect then
                self.UIReconnect.OnReconnecting:Remove(self, self.OnReconnecting)
                self.UIReconnect.OnReconnectFailed:Remove(self, self.OnReconnectFailed)
                UIManager:GetInstance():RemoveUI(self.UIReconnect, true)
                self.UIReconnect = nil
            end
            print("==重新登录请求:" .. tostring(self.account_id) .. ", key:" .. tostring(self.key))
            self.bIsReconnectSuccess = false
            Client.send("req_relogin", {
                account_id = self.account_id,
                key = self.key
            })
        else
            LOG_DEBUG_TRACKBACK('------login on_connect')
            local register_or_login = self.register_or_login
            Client.send(table.unpack(register_or_login))
            -- self.register_or_login = nil
        end
        return
    end
    if status == Client.CLIENT_STATUS.CONNECT_TIMEOUT then
        LOG_INFO("连接超时")
        UIUtils.ShowNotify(self, Database.L10n(311))
        self.login_wait = false
        return
    end
    if status == Client.CLIENT_STATUS.CONNECT_FAILED then
        LOG_INFO("连接失败")
        UIUtils.ShowNotify(self, Database.L10n(312))
        self.login_wait = false
        return
    end
    if status == Client.CLIENT_STATUS.DISCONNECT then
        LOG_INFO("连接断开")
        -- UIUtils.ShowNotify(self, Database.L10n(313))
        if self.LoggedIn then
            -- local player_controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            -- player_controller:DisableInput()

            if not UE.UGameplayStatics.IsGamePaused(self) then
                self:RemoveUMG('UI_PlayerLevelUp')
                UE.UGameplayStatics.SetGamePaused(self, true)
                self.reconnecting_should_reset_game_pause = true
            end
            Client:close()
            self.reconnecting = false
            self.reconnect_failed = true
        
            local UIUtils = require "_Game.Utils.UIUtils"
            UIUtils.ShowComNotice(Database.L10n(523), self, function() 
                self.reconnecting = false
                self.reconnect_failed = false
                self:LoadLevel("LoginMap", true)
            end)
        end
        
        return
    end
end

--------------------------------------OnResMsg Start-------------------------------------------
function BP_GameInstance_C:ServerError(msgName, result, parsed_msg)
    local msg = ErrorFormatter.FormatError(msgName, result, parsed_msg)

    if msg ~= '' then
        UIUtils.ShowNotify(self, msg)
    end
end

function BP_GameInstance_C:GetDeviceId()
    -- local device_id = ""
    -- if GlobalConfig.Channel == "test1" then
    --     device_id = UE.UGHSFunctionLibrary.GetDeviceIdAnyway()
    -- end
    local device_id = UE.UGHSFunctionLibrary.GetDeviceIdAnyway()
    return device_id
end

---@param parsed_msg ResRegisterMessage
function BP_GameInstance_C:res_register(result, msgId, parsed_msg)
    self.login_wait = false
    if result == 0 then
        LOG_INFO("注册完成")

        UIManager:GetInstance():Notify(Database.L10n(83100007))

        self:LuaLogin(parsed_msg.req_data.account_name, parsed_msg.req_data.password, self:GetDeviceId(), true)
        return
    elseif result == 2 then
        UIUtils.ShowComNotice(
            Database.L10n(452),
            self,
            function()
                UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
            end
        )
    end
   
    LOG_INFO("注册失败", result)
end

function BP_GameInstance_C:res_login(result, msgId, parsed_msg)
    self.login_wait = false
    if result == 0 then
        self.bIsInitReqMsg = true
       
        UIManager:GetInstance():ShowWaterMask(self)
        LOG_INFO("登录完成")
        print('===登录返回:' .. tostring(table.dump(parsed_msg.res_login)))
        self.account_id = parsed_msg.res_login.account_id
       
        self.key = parsed_msg.res_login.key

        Client.send("req_player")
        LOG_INFO("请求玩家信息")

        Client.send("req_bag")
        LOG_INFO("请求背包")

        Client.send('req_home', {})
        
        Client.send(Protos.REQ_UNIVERSE)
        SrpgController:GetInstance():Load(self.account_id)
        LOG_INFO("请求宇宙")

        Client.send(Protos.REQ_TOTAL_WAR)
      
        Client.send("req_shop_list")
        LOG_INFO("请求商店")

        Client.send("req_mall_list")
        LOG_INFO("请求商城")

        Client.send("req_hard_level")
        LOG_INFO("请求活动")

        Client.send("req_character_list")
        LOG_INFO("请求角色列表")

        Client.send("req_plot")
        LOG_INFO("请求剧情树")

        Client.send("req_activity_list")
        LOG_INFO("请求活动")

        Client.send('req_gacha')
        LOG_INFO('请求扭蛋')

        Client.send(Protos.REQ_MAIL_LIST) --临时把邮件接收返回作为初始请求数据结束标记
        MessageManager:GetInstance():Broadcast("res_login")
        return
    elseif result == 2 then --版本不匹配
        UIUtils.ShowComNotice(
            Database.L10n(452),
            self,
            function()
                UE.UKismetSystemLibrary.QuitGame(self, nil, UE.EQuitPreference.Quit, true)
            end
        )
    end
   
    LOG_INFO("登录失败", result)
end

function BP_GameInstance_C:res_relogin(result, msgId, parsed_msg)
    if result == 0 then
        LOG_INFO("重新登录完成")
        self.reconnecting = false
        if self.reconnecting_should_reset_game_pause then
            UE.UGameplayStatics.SetGamePaused(self, false)
            self.reconnecting_should_reset_game_pause = false
        end
        self.bIsReconnectSuccess = true

        if self.UIReconnect then
            self.UIReconnect.OnReconnecting:Remove(self, self.OnReconnecting)
            self.UIReconnect.OnReconnectFailed:Remove(self, self.OnReconnectFailed)
            UIManager:GetInstance():RemoveUI(self.UIReconnect, true)
            self.UIReconnect = nil
        end

        local player_controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        -- player_controller:EnableInput()
        if player_controller and player_controller.BP_PlayerController_City_UniverseBridge then
            player_controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        end
        return
    end
    LOG_INFO("重新登录失败", result)
    Client:close()
   
    self.reconnecting = false
    self.reconnect_failed = true
    local UIUtils = require "_Game.Utils.UIUtils"
    local text = '<span color="#FF0000FF">' .. Database.L10n(50503) .. '</>'
    UIUtils.ShowComNotice(text, self, function()
        self.reconnect_failed = false
        self:LoadLevel("LoginMap", true)
    end)
end

---@param parsed_msg ResNewUniverseMessage
function BP_GameInstance_C:res_new_universe(result, msgId, parsed_msg)
    ---@type BP_GameMode_City_C
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    gameMode.LevelName = "UniverseMap"
    ---@type BP_PlayerController_City_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    playerController:OnOpenNextLevel()
end

---@param parsed_msg ResNewUniverseSpecificMessage
function BP_GameInstance_C:res_new_universe_specific(result, msgId, parsed_msg)
    if result == 0 then
        local characterFightData = parsed_msg.res_new_universe_specific.universe_info.universe_fight_data.character_fight_datas
        ---@type SG_TeamList_C
        local teamList = self:LoadTeamList()

        for i = 1, teamList.SpecialTeamInfo:Length() do
            ---@type FST_TeamInfo
            local teamInfo = teamList.SpecialTeamInfo:Get(i)
            -- if teamInfo.bIsSelected then
                for j = 1, teamInfo.RoleList:Length() do
                    if characterFightData[j].character_id ~= 0 then
                        teamInfo.RoleList:Set(j, characterFightData[j].character_id)
                    else
                        teamInfo.RoleList:Set(j, 0)
                    end
                end
            -- end
            teamList.SpecialTeamInfo:Set(i, teamInfo)
            break
        end

        self:SaveTeamList()

        local PC = UE.UGameplayStatics.GetPlayerController(self, 0)
        local function OnFadeInFinished()
            PC.BP_ScreenFade.OnFadeInFinished:Remove(self, OnFadeInFinished)
            coroutine.resume(coroutine.create(function()
                UE.UKismetSystemLibrary.Delay(self, 0.3)
                --self:res_new_universe(result, msgId, { res_new_universe = parsed_msg.res_new_universe_specific })
                local gameMode = UE.UGameplayStatics.GetGameMode(self)
                gameMode.LevelName = "UniverseMap"
                ---@type BP_PlayerController_City_C
                local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

                self:LoadLevel("UniverseMap")
            end))
        end
        PC.BP_ScreenFade.OnFadeInFinished:Add(self, OnFadeInFinished)
        PC.BP_ScreenFade:FadeIn(false, true)
        PC:DisableInput()
    end
end

function BP_GameInstance_C:res_gm_cmd(result, msgId, parsed_msg)
    LOG_INFO(result, parsed_msg and parsed_msg.msg)
    -- if parsed_msg and parsed_msg.res_gm_cmd then
    --     Client.send("req_bag")
    -- end

    if result == 0 then
        if self.req_data and self.req_data.req_gm_cmd then
            local array = string.split(self.req_data.req_gm_cmd, ' ')
            if array[1] == 'add_item' then
                self.UI_GetItem_Notice = self:AddUMG('UI_GetItem_Notice')
                if self.req_data.isMission then
                    self.UI_GetItem_Notice.TextTitle:SetText('任务奖励')
                    self.req_data.isMission = nil
                end

                local item_count = (#array - 1) / 3
                for i = 1, item_count do
                    local item_id = tonumber(array[3 * i - 1])
                    local count = array[3 * i + 1]
                    local config = UIUtils.GetItemConfigById(item_id)
                    local item_ui = UE.UWidgetBlueprintLibrary.Create(self,
                        UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
                    item_ui.TextName:SetText(Database.L10n(config.itemName))
                    item_ui.TextNum:SetText(count)
                    --稀有度背景图片
                    if config.rarityPath and config.rarityPath ~= '' then
                        local strArr = string.split(config.rarityPath, '/')
                        local littePath = strArr[#strArr]
                        local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                        local itemRarityPic = LoadObject(rarityPath)
                        if itemRarityPic then
                            item_ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                        end
                    end

                    --icon
                    if config.iconPath and config.iconPath ~= '' then
                        local strArr = string.split(config.iconPath, '/')
                        local littePath = strArr[#strArr]
                        local iconResPath = string.format('/Game/_Game/%s.%s', config.iconPath, littePath)
                        local iconRes = LoadObject(iconResPath)
                        if iconRes then
                            item_ui.icon_res:SetBrushFromAtlasInterface(iconRes)
                        end
                    end

                    item_ui.ItemPanel:SetRenderOpacity(0)
                    item_ui.Img_bg.OnMouseButtonDownEvent:Unbind()
                    item_ui.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
                        UIUtils.ShowItemInfo(item_id)
                        return UE.UWidgetBlueprintLibrary.Handled()
                    end)

                    self.UI_GetItem_Notice.ItemBox:AddChild(item_ui)
                    self.UI_GetItem_Notice:PlayAnimationForward(self.UI_GetItem_Notice.start, 1, false)
                    self.UI_GetItem_Notice:PlayItemAnim()
                end
            end
            self.req_data.req_gm_cmd = nil
        end
        if parsed_msg.req_data.cmd then
            local array = string.split(parsed_msg.req_data.cmd, ' ')
            if array[1] == 'add_plot_completed_mission' then
                for i = 2, #array do
                    local mission_id = tonumber(array[i] or -1)
                    if mission_id then
                        local PlotSystem = require("Module.Plot.PlotSystem")
                        table.insert(PlotSystem:GetInstance().PlotInfo.completed_mission_ids, mission_id)
                        local task_info = Database.Query("d_task_story", mission_id)
                        for __, key in ipairs(task_info.key) do
                            table.insert(PlotSystem:GetInstance().PlotInfo.taskKey_ids, key)
                        end
                    end
                end
            end
        end

        if parsed_msg.req_data["cmd"] then
            local array = string.split(parsed_msg.req_data["cmd"], ' ')
            if array[1] == 'play_plot_node' then
                local saveGameSpeak = self:LoadSaveGameSpeak()
                if saveGameSpeak then
                    saveGameSpeak.MissionInfos:Clear()
                    saveGameSpeak.PlotIndex = 0
                end
                self:SaveSaveGameSpeak()
            end
        end
    end
end

function BP_GameInstance_C:ntf_mission_info(result, msgId, parsed_msg)
    if result == 0 then
        table.insert(self.resUniverse.res_universe.universe_info.mission_infos, parsed_msg.ntf_mission_info.mission_info)
    end
end

function BP_GameInstance_C:ntf_mission_result(result, msgId, parsed_msg)
    if result == 0 then
        local missionResult = parsed_msg.ntf_mission_result

        for _, missionInfo in pairs(self.resUniverse.res_universe.universe_info.mission_infos) do
            if missionInfo.mission_uuid == missionResult.mission_uuid then
                missionInfo.mission_result = missionResult.mission_result
                missionInfo.mission_end_turn = missionResult.mission_end_turn
                missionInfo.mission_end_step = missionResult.mission_end_step
                break
            end
        end
    end
end

function BP_GameInstance_C:ntf_server_error(result, msgId, parsed_msg)
    local msg = ErrorFormatter.FormatError('ntf_server_error', result)

    if msg ~= '' then
        UIUtils.ShowNotify(self, msg)
    end
end

local LEVEL_CONFIG_PATH = '/Game/_Game/Blueprints/Levels/SRPG/Level%d/TestLevel%d.TestLevel%d_C'

function BP_GameInstance_C:ConfirmFight()
    local levelId
    if self.fightType == self.FIGHT_STATE.BOSS then
        local bossIndex = self.fightMsg.boss_index
        local bossConfigId = SrpgController:GetInstance():GetBossConfigId()
        local bossInfo = Database.Query("d_srpg_level_boss", bossConfigId)
        local fightLevelId = bossInfo.path[bossIndex + 1]
        levelId = Database.Query("d_srpg_level_base", fightLevelId).path
    else
        local fightLevelId = self.resUniverse.res_universe.universe_info.fight_infos[1].fight_level_id
        levelId = Database.Query("d_srpg_level_base", fightLevelId).path
    end

    local levelPath = string.format(LEVEL_CONFIG_PATH, levelId, levelId, levelId)
    LOG_INFO("Fight Level", levelPath)
    
    ---@type FightLevel_C
    local fightLevelClass = UE.UClass.Load(levelPath)
    self.LevelClass = fightLevelClass
    ---@type BP_PlayerController_Universe_C
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        playerController:LoadFight()
    end
end

--------------------------------------OnResMsg End-------------------------------------------

--------------------------------------OnReqMsg Start-------------------------------------------

--------------------------------------OnReqMsg End-------------------------------------------

--------------------------------------Table Start-------------------------------------------
function BP_GameInstance_C:GetWordTable(key, attr)
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if worldTable[key] and worldTable[key][attr] then
        return worldTable[key][attr]
    end
end

function BP_GameInstance_C:GetUniverseTable(key, attr)
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if universeTable[key] and universeTable[key][attr] then
        return universeTable[key][attr]
    end
end

function BP_GameInstance_C:GetMainPosTable(key, attr)
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if mainPosTable[key] and mainPosTable[key][attr] then
        return mainPosTable[key][attr]
    end
end

function BP_GameInstance_C:GetCardTable(key, attr)
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if cardTable[key] and cardTable[key][attr] then
        if attr == "baseEffectvalue" then
            local ret = cardTable[key][attr][1]
            return ret
        else
            return cardTable[key][attr]
        end
    end
end

function BP_GameInstance_C:GetAttrByName(tableName, key, attr)
    if not string.startswith(tableName, "d_") then
        tableName = "d_" .. tableName
    end
    local tab = require("ClientDatas." .. tostring(tableName))
    if not tab then
        LOG_ERROR("Not find table:ClientDatas." .. tableName)
        return ""
    end
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    
    if tab[key] and tab[key][attr] then
        local value = tab[key][attr]
        if type(value) == 'table' then
            local strValue = ''
            for _, v in ipairs(value) do
                strValue = (strValue == '') and (strValue .. v) or (strValue .. ',' .. v)
            end
            return strValue
        end
        return tab[key][attr]
    end
    return ""
end

function BP_GameInstance_C:GetAttrByKey2(tableName, k1, v1, k2, v2, attr)
    if not string.startswith(tableName, "d_") then
        tableName = "d_" .. tableName
    end
    local tab = require("ClientDatas." .. tostring(tableName))
    if not tab then
        LOG_ERROR("Not find table:ClientDatas." .. tableName)
        return ""
    end
    -- print('===k1:' .. tostring(k1) .. ",v1:" .. tostring(v1))
    -- print('===k2:' .. tostring(k2) .. ",v2:" .. tostring(v2))
    -- print('attr:' .. tostring(attr))
    for _, line in ipairs(tab) do
        -- print("====line:" .. tostring(table.dump(line, nil, 10)))
        if line[k1] == v1 and line[k2] == v2 then
            local value = line[attr]
            if type(value) == 'table' then
                local strValue = ''
                for _, v in ipairs(value) do
                    strValue = (strValue == '') and (strValue .. v) or (strValue .. ',' .. v)
                end
                return strValue
            end
            return value
        end
    end
    return ""
end

--------------------------------------Table End-------------------------------------------

function BP_GameInstance_C:InitMainPosInfoAndLines()
    if self.resUniverse ~= nil then
        local posInfos = self.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos
        for index, mainPos in ipairs(posInfos) do
            --init main pos info
            local hex = mainPos.hex
            local hex_id = string.format("%d,%d", hex.r, hex.q)
            self.mainPosInfos[hex_id] = mainPos
            self.mainPosInfos[hex_id].index = index
            self.mainPosInfos[hex_id].card_in_place = {}
            --init line
            for _, line_hex in ipairs(mainPos.hex_lines) do
                local line_hex_id = string.format("%d,%d", line_hex.r, line_hex.q)
                local line = { hex_id, line_hex_id }
                table.sort(line)
                local isContain = false
                for __, pos in ipairs(self.linesInfo) do
                    if pos[1] == line[1] and pos[2] == line[2] then
                        isContain = true
                    end
                end
                if isContain == false then
                    table.insert(self.linesInfo, line)
                end
            end
        end
        --init place card info
        local cardPosInfos = self.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos
        for k, CardInfo in ipairs(cardPosInfos) do
            local hex = CardInfo.hex
            local hex_id = string.format("%d,%d", hex.r, hex.q)
            self.mainPosInfos[hex_id].card_in_place = { CardInfo }
        end
    end
end

function BP_GameInstance_C:GetUniverseInfo()
    return self.resUniverse
end

function BP_GameInstance_C:GetViceMode(key)
    local ModeId = 0
    if type(key) ~= "number" then
        key = tonumber(key)
    end
    if mainPosTable[key] and mainPosTable[key].vicePosMods then
        local VicePosModes = mainPosTable[key].vicePosMods
        local num = 0
        for k, v in pairs(VicePosModes) do
            num = num + 1
        end
        local i = math.random(num)
        ModeId = VicePosModes[i]
    end
    return ModeId
end

function BP_GameInstance_C:GetExploreInfoCount()
    return 0
end

function BP_GameInstance_C:UpdateNextTurnCurrency()
    self.add_goods[1] = 0
    self.add_goods[2] = 0
    self.add_goods[3] = 0
    local planetId = self.resUniverse.res_universe.universe_info.planet_infos[1].planet_id or 0
    local resourceValue = self:GetUniverseTable(planetId, "resourceValue") or 0
    local mainpos1Num = 0
    local mainpos2Num = 0
    local mainpos3Num = 0
    for _, value in ipairs(self.resUniverse.res_universe.universe_info.planet_infos[1].main_pos_infos) do
        if tonumber(value.main_pos_id) == 317 and value.explored then
            mainpos1Num = mainpos1Num + 1
        elseif tonumber(value.main_pos_id) == 315 and value.explored then
            mainpos2Num = mainpos2Num + 1
        elseif tonumber(value.main_pos_id) == 316 and value.explored then
            mainpos3Num = mainpos3Num + 1
        end
    end

    for _, value in ipairs(self.resUniverse.res_universe.universe_info.planet_infos[1].card_pos_infos) do
        local card_info = Database.Query("d_srpg_card_base", value.card_info.card_id)
        if card_info.type == 3 then
            if card_info.effectsTypeValues[1] == 1 then
                self.add_goods[1] = self.add_goods[1] + card_info.effectsTypeValues[2]
            elseif card_info.effectsTypeValues[1] == 2 then
                self.add_goods[2] = self.add_goods[2] + card_info.effectsTypeValues[2]
            elseif card_info.effectsTypeValues[1] == 3 then
                self.add_goods[3] = self.add_goods[3] + card_info.effectsTypeValues[2]
            end
        end
    end
    self.add_goods[1] = self.add_goods[1] + mainpos1Num * resourceValue[1]
    self.add_goods[2] = self.add_goods[2] + mainpos2Num * resourceValue[2]
    self.add_goods[3] = self.add_goods[3] + mainpos3Num * resourceValue[3]
end

function BP_GameInstance_C:NextTurn()
    local cur_step = self.resUniverse.res_universe.universe_info.step
    local cur_turn = self.resUniverse.res_universe.universe_info.turn

    SrpgController:GetInstance():ChangeResource(1, self.add_goods[1])
    SrpgController:GetInstance():ChangeResource(2, self.add_goods[2])
    SrpgController:GetInstance():ChangeResource(3, self.add_goods[3])

    self.resUniverse.res_universe.universe_info.turn = cur_turn + 1
    self.resUniverse.res_universe.universe_info.step = cur_step + 1

    self:UpdateEventState()
end

function BP_GameInstance_C:UpdateFightState()
    if self.resUniverse == nil or self.resUniverse.res_universe == nil then
        return
    end
    if #self.resUniverse.res_universe.universe_info.fight_infos > 0 then
        if self.resUniverse.res_universe.universe_info.fight_infos[1].event_uuid ~= 0 then
            if #self.resUniverse.res_universe.universe_info.fight_infos[1].cards_for_select == 0 then
                self.fight_state = self.FIGHT_STATE.EVENT
            end
        else
            local isBossFight = false
            for index, boss_info in ipairs(self.resUniverse.res_universe.universe_info.boss_infos) do
                if boss_info.fight_uuid == self.resUniverse.res_universe.universe_info.fight_infos[1].fight_uuid then
                    if #self.resUniverse.res_universe.universe_info.fight_infos[1].cards_for_select == 0 then
                        isBossFight = true
                        self.fight_state = self.FIGHT_STATE.BOSS
                    end
                end
            end
            if not isBossFight then
                self.fight_state = self.FIGHT_STATE.MAINPOS
            end
        end
    end
    self.fight_state = self.FIGHT_STATE.WAITING
end

function BP_GameInstance_C:UnFinished_Fight()
    print("---UnFinished_Fight")
    if self.bIsReconnectSuccess then return end --重连成功
    print("---UnFinished_Fight1111")
    if self.bIsInitReqMsg then
        self.UnFinished_Fight_Called = true
        return
    end
    print("---UnFinished_Fight222")
    UIManager:GetInstance():ClearConfirm()
    self:RemoveUMG('UI_Login')
    if SrpgController:GetInstance():HasPendingEvent() then
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        gameMode.LevelName = "UniverseMap"
        ---@type BP_PlayerController_City_C
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

        playerController:OnOpenNextLevel()
        print("===有宇宙信息:")
    else
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        if gameMode.SpawnActors then
            gameMode:SpawnActors()
            --日常战斗检测
            local PlayerSystem = require('Module.Player.PlayerSystem')
            if PlayerSystem:GetInstance().PlayerInfo and PlayerSystem:GetInstance().PlayerInfo.daily_level_fight_info then
                local fight_info = PlayerSystem:GetInstance().PlayerInfo.daily_level_fight_info
                if fight_info and fight_info.fight_level_id > 0 then
                    local level_path = '/Game/_Game/Blueprints/Levels/ARPG/Level_Dungeon/%s/%s.%s_C'
                    local level_id = Database.Query('d_levels', fight_info.fight_level_id).path
                    level_path = string.format(level_path, level_id, level_id, level_id)
                    local fightLevelClass = UE.LoadClass(level_path)
                    self.LevelClass = fightLevelClass
                    self.fightMsg = { fight_level_id = fight_info.fight_level_id }
                    self.fightType = self.FIGHT_STATE.DailyCopy
                    self.fightCanBack = false

                    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
                    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
                    controller:LoadFightBeforeInCity()
                    return
                end
            end

            --挑战战斗检测
            local HardLevelSystem = require('Module.HardLevel.HardLevelSystem')
            if HardLevelSystem:GetInstance().HardLevelInfos then
                local fight_level_id = HardLevelSystem:GetInstance():GetFightLevelId()
                if fight_level_id > 0 then
                   
                    local config = Database.Query('d_levels_challenge', fight_level_id)
                    local classPath = config.path
                    if not string.endswith(classPath, "_C'") then
                        local sub = string.sub(classPath, 1, -2) .. "_C'"
                        classPath = sub
                    end
                    self.LevelClass = UE.UClass.Load(classPath)
                    self.fightMsg = 
                    { 
                        fight_level_id = fight_level_id
                    }
                    self.fightCanBack = false

                    if config.levelTypes == UIUtils.ECopyType.ECopyType_Train then
                        self.fightType = self.FIGHT_STATE.CharTrainCopy

                        local freeRoleNum = self:ParseCharacterTrainl(config.characterTrial)

                        if freeRoleNum <= 0 then
                            NetworkMessageManager:GetInstance():AddListener("res_hard_level_fight", self)
                            HardLevelSystem:GetInstance():ReqHardLevelFight(self.fightMsg)
                            return
                        end 
                    else
                        self.fightType = self.FIGHT_STATE.ChallengeCopy
                    end
                
                    if playerController and self and self.LevelClass then
                        if playerController.LoadFightBeforeInCity then
                            self:HideAllUI()
                            
                            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
                            controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
                
                            playerController:LoadFightBeforeInCity()
                            return
                        end
                    end
                end
            end
            
            if BossRushController:GetInstance():HasPendingFight() then
                local bossId = BossRushController:GetInstance():GetPendingBossFight()
                local difficulty = BossRushController:GetInstance():GetPlayerDifficulty(bossId)

                local bossConfig = BossRushController:GetInstance():GetBossConfig(bossId, difficulty)

                self:HideAllUI()

                local level_path = bossConfig.Level
                local fightLevelClass = LoadObject(string.sub(level_path, 1, -2) .. "_C'")
                self.LevelClass = fightLevelClass
                self.fightMsg = { boss_id = bossId }
                self.fightType = self.FIGHT_STATE.BOSSRUSH
                self.fightCanBack = false
                self.IsSpecialTeamInfo = true
                self.TeamContext = {
                    type = 1,
                    bossId = bossId
                }

                self.CachedSubLevel = 'City1BusinessCenter'
                self:CachePlayInCity()

                local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
                controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
                controller:LoadFightBeforeInCity()
                return
            end
            print("--------playerController:EnterGame")
            playerController:EnterGame()
        end
    end
end


function BP_GameInstance_C:res_hard_level_fight(result, msgId, parsed_msg)
    NetworkMessageManager:GetInstance():RemoveListener("res_hard_level_fight", self)
    if result == 0 then
        local teamList = self:LoadTeamList()
        if not teamList then
            teamList = self:CreateTeamList()
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
        self:SaveTeamList()
        
        local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
        if playerController and playerController.BP_PlayerController_City_UniverseBridge then
            self:ShowTopUI(false)
            playerController.BP_PlayerController_City_UniverseBridge:FastLoadFight()
        end
    else
        LOG_WARN("Res Activity Hard Level Fight Error Code:", result)
    end
end

---------------------------------------------------------
---
function BP_GameInstance_C:GetSelectedTeamList()
    local teamListData = self:LoadTeamList()
    for i = 1, teamListData.TeamInfo:Length() do
        local teamData = teamListData.TeamInfo:Get(i)
        if teamData.bIsSelected then
            return teamData
        end
    end
    return nil
end

function BP_GameInstance_C:GetSelectedSpecialTeamList()
    local teamListData = self:LoadTeamList()
    for i = 1, teamListData.SpecialTeamInfo:Length() do
        local teamData = teamListData.SpecialTeamInfo:Get(i)
        -- if teamData.bIsSelected then
            return teamData
        -- end
    end
    return nil
end

function BP_GameInstance_C:GetTrainCopyTeamList()
    local teamListData = self:LoadTeamList()
    for i = 1, teamListData.TrainTeamInfo:Length() do
        local teamData = teamListData.TrainTeamInfo:Get(i)
        -- if teamData.bIsSelected then
            return teamData
        -- end
    end
    return nil
end

function BP_GameInstance_C:GetUniverseExists()
    return SrpgController:GetInstance():IsUniverseExist()
end

--获取主城角色类
function BP_GameInstance_C:GetCityCharacterClass(id)
    LOG_DEBUG_TRACKBACK("==========GetCityCharacterClass:" .. tostring(id))
    --获取角色列表第一个角色
    if id == 0 then
        for _, charData in pairs(CharacterSystem:GetInstance().CharacterInfo) do
            id = charData.character_id
            break
        end
    end
    if id == 0 then
        return nil
    else
        
    end
    local modelPath = self:GetAttrByName("d_character", id, "cityModelPath")
    if modelPath ~= '' then
        local strArr = string.split(modelPath, '/')
        local path = string.format("'/Game/_Game/Blueprints/Players/%s.%s_C'", modelPath, strArr[2])
        local playerClass = LoadClass(path)
        if playerClass then
            return playerClass
        else
            LOG_ERROR("加载模型:" .. path .. ", failed!!!")
        end
    end
    return nil
end

--获取主城角色id
function BP_GameInstance_C:GetPlayerCharacterIdInCity()
    
    self:LoadSaveGameChar()
    print("-------GetPlayerCharacterIdInCity：" .. tostring(self.SaveGameChar.CityCharacterId))
    if self.SaveGameChar.CityCharacterId == 0 then
        self.SaveGameChar.CityCharacterId = 10501
        self:SaveSaveGameChar()
        -- local charInfo = CharacterSystem:GetInstance().CharacterInfo
        -- if charInfo and charInfo[1] and charInfo[1].character_id > 0 then
        --     self.SaveGameChar.CityCharacterId = charInfo[1].character_id
        --     self:SaveSaveGameChar()
        -- end
    end
    return self.SaveGameChar.CityCharacterId
end

--创建默认主城角色
function BP_GameInstance_C:CreateDefaultCharacterInCity()
    local charId = self:GetPlayerCharacterIdInCity()
    LOG_DEBUG_TRACKBACK('---CreateDefaultCharacterInCity' .. tostring(charId))
    if charId and charId > 0 then
        local playerClass = self:GetCityCharacterClass(charId)
        if playerClass then
            local newPlayer = self:GetWorld():SpawnActor(playerClass,  
                UE.UKismetMathLibrary.MakeTransform(
                    UE.FVector(0, 0, 0),
                    UE.FRotator(0, 0, 0),
                    UE.FVector(1, 1, 1)),
                UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
            newPlayer:SetActorHiddenInGame(false)
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            gameMode:BPI_SetPlayer(newPlayer)
            self.Walk = false
            return newPlayer
        end
        self:ChangeDress()
    end
    return nil
end

--切换主城角色
function BP_GameInstance_C:ChangePlayerCharacterInCity(charId)
    print("===ChangePlayerCharacterInCity:" .. tostring(charId) .. ",oldId:" .. tostring(self.SaveGameChar.CityCharacterId))
    if charId ~= self.SaveGameChar.CityCharacterId then
        self.SaveGameChar.CityCharacterId = charId
        self:SaveSaveGameChar()
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local player = gameMode:BPI_GetPlayer()
        if player then
            player:ChangeCamera(false)
            local playerClass = self:GetCityCharacterClass(charId)
            if playerClass then
                local newPlayer = self:GetWorld():SpawnActor(playerClass, player:GetTransform(), UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
                newPlayer:SetActorHiddenInGame(false)
                local oldGravityScale = player.CharacterMovement.GravityScale
                local oldJUmpZVelocity = player.CharacterMovement.JumpZVelocity
                --playerController:Possess(newPlayer)
                player:K2_DestroyActor()
                gameMode:BPI_SetPlayer(newPlayer)
                newPlayer.CharacterMovement.GravityScale = oldGravityScale
                newPlayer.CharacterMovement.JumpZVelocity = oldJUmpZVelocity
            end
            self:ChangeDress()
        end
        player = nil

        local ui = self:GetUMG('UI_CityMenu')
        if ui then
            ui:CreatePlayer()
        end
    end
end

function BP_GameInstance_C:ChangeDress()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        local curCharacterId = self:GetPlayerCharacterIdInCity()
        local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(curCharacterId)
        print("-->>changeDress:" .. tostring(savedCityCharId) .. ",defualtCharid:" .. tostring(defaultCityCharId))
        if savedCityCharId > 0 then
            local config = Database.Query("d_char_clothes", savedCityCharId)
            if config then
                --身体
                if config.modelF ~= '' then
                    local newMesh = LoadObject(config.modelF)
                    if newMesh then
                        if curCharacterId == 10601 then
                            player.SkeletalMesh:SetSkeletalMeshAsset(newMesh)
                            -- player.SkeletalMes:SetSimulatePhysics(false)
                            local mats = newMesh:GetMaterials()
                            for i = 1, mats:Length() do
                                local mi = mats:Get(i).MaterialInterface
                                player.SkeletalMesh:CreateDynamicMaterialInstance(i - 1, mi)
                            end
                        else
                            player.Mesh:SetSkeletalMeshAsset(newMesh)
                            -- player.Mesh:SetSimulatePhysics(false)
                            -- if player.SkeletalMesh then
                            --     player.SkeletalMesh:SetSimulatePhysics(false)
                            -- end
                        end
                    end
                end
                --头发
                if config.modelHair ~= '' then
                    local newMesh = LoadObject(config.modelHair)
                    if newMesh then
                        player.Hair:SetSkeletalMeshAsset(newMesh, false)
                    end
                end
                --脸
                if config and config.modelFace ~= '' then
                    local newMesh = LoadObject(config.modelFace)
                    if newMesh then
                        player.face:SetSkeletalMeshAsset(newMesh, false)
                    end
                end
            end
        end
    end 
end

function BP_GameInstance_C:GetCharCityDress(charId)
    local _, _, savedCityCharId, _, _, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(charId)
    print("-->>changeDress:" .. tostring(savedCityCharId) .. ",defualtCharid:" .. tostring(defaultCityCharId))
    if savedCityCharId > 0 then
        local config = Database.Query("d_char_clothes", savedCityCharId)
        if config and config.modelF ~= '' then
            local newMesh = LoadObject(config.modelF)
            if newMesh then
                return newMesh
            end
        end
    end
    return nil
end

--加载角色的SaveGame
function BP_GameInstance_C:LoadSaveGameChar()
    if not self.SaveGameChar then
        self.account_id = self.account_id or "XXXXXX"
        if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Char_" .. self.account_id, 0) then
            self.SaveGameChar = UE.UGameplayStatics.LoadGameFromSlot('SG_SaveGame_Char_' .. self.account_id, 0)
        else
            self.SaveGameChar = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load("/Game/_Game/Blueprints/Game/SG_SaveGame_Char.SG_SaveGame_Char_C"))
        end
    end
    return self.SaveGameChar
end

--保存角色的SaveGame
function BP_GameInstance_C:SaveSaveGameChar()
    UE.UGameplayStatics.SaveGameToSlot(self.SaveGameChar, "SG_SaveGame_Char_" .. self.account_id, 0)
end

function BP_GameInstance_C:GetIsGachaAllOpened()
    self:LoadSaveGameChar()
    if UE.UKismetSystemLibrary.IsValid(self.SaveGameChar) then
        return self.SaveGameChar.bIsGachaAllOpen
    end
    return true
end

function BP_GameInstance_C:SaveIsGachaAllOpened(allOpened)
    if UE.UKismetSystemLibrary.IsValid(self.SaveGameChar) then
        self.SaveGameChar.bIsGachaAllOpen = allOpened
        self:SaveSaveGameChar()
    end
end

function BP_GameInstance_C:GetIsBuildOpenDay()
    self:LoadSaveGameChar()
    if UE.UKismetSystemLibrary.IsValid(self.SaveGameChar) then
        return self.SaveGameChar.bIsBuildOpenDay
    end
    return true
end

function BP_GameInstance_C:SaveIsBuildOpenDay(bIsOpenDay)
    self:LoadSaveGameChar()
    if UE.UKismetSystemLibrary.IsValid(self.SaveGameChar) then
        self.SaveGameChar.bIsBuildOpenDay = bIsOpenDay
        self:SaveSaveGameChar()
    end
end

-------------------------------------------------------
---Application Event 
function BP_GameInstance_C:OnAppHasEnteredForeground(pastTime)
    -- --刚登陆游戏时,还没开始连接
    -- if not self.LoggedIn then return end

    -- if pastTime > 600 then
    --     self:StartReconnect()
    -- else
    --     if Client.need_connect() then
    --         Client.connect(HOST, PORT)
    --         self.reconnecting = true
    --     end
    -- end
end

function BP_GameInstance_C:StartReconnect()
    --print("===StartReconnect")
    Client:close()
    self.reconnecting = true
    if not self.UIReconnect or not UE.UKismetSystemLibrary.IsValid(self.UIReconnect) then
        local ui = UIManager:GetInstance():AddUI("UI_Reconnect", true)
        ui.OnReconnecting:Add(self, self.OnReconnecting)
        ui.OnReconnectFailed:Add(self, self.OnReconnectFailed)
        self.UIReconnect = ui

        -- local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        -- pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    end
    self.UIReconnect:StartReconnect("请检查你的网络...", "重连中...")
end

function BP_GameInstance_C:OnReconnecting()
    --print("===OnReconnecting")
    Client:close()
    Client.connect(HOST, PORT, true)
end

function BP_GameInstance_C:OnReconnectFailed()
    --print("===OnReconnectFailed")
    if self.reconnecting and not self.bIsReconnectSuccess then 
        if self.UIReconnect then
            self.UIReconnect.OnReconnecting:Remove(self, self.OnReconnecting)
            self.UIReconnect.OnReconnectFailed:Remove(self, self.OnReconnectFailed)
            UIManager:GetInstance():RemoveUI(self.UIReconnect, true)
            self.UIReconnect = nil
        end
    
        Client:close()
        self.reconnecting = false
        self.reconnect_failed = true
    
        local UIUtils = require "_Game.Utils.UIUtils"
        local text = '<span color="#FF0000FF">多次连接失败</>\n<span color="#FF0000FF">是否返回登录界面?</>'
        UIUtils.ShowComNotice(text, self, function() 
            self.reconnecting = false
            self.reconnect_failed = false
            self:LoadLevel("LoginMap", true)
        end, function() 
            self:StartReconnect()
        end)
    end
end

---------------------------------------------------------
---剧情对话
function BP_GameInstance_C:OpenPlot(InParam, hideNpc)
    LOG_DEBUG_TRACKBACK('------open plot')
    if hideNpc then
        local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, '10000201')
        if actors:Length() > 0 then
            for i = 1, actors:Length() do 
                local actor = actors:Get(i)
                actor:SetActorHiddenInGame(true)
                local attachedActors = UE.TArray(UE.AActor)
                actor:GetAttachedActors(attachedActors, true, false)
                for i = 1, attachedActors:Length() do 
                    local attachActor = attachedActors:Get(i)
                    attachActor:SetActorHiddenInGame(true)
                end
            end
        end
    end
    

    local FlyBoxs = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "flybox_coli")
    if FlyBoxs:Length() > 0 then
        for i = 1, FlyBoxs:Length() do 
            FlyBoxs:Get(i):SetActorHiddenInGame(true)
            FlyBoxs:Get(i):K2_GetRootComponent():SetCollisionProfileName('Spectator', true)
        end
    end

    local plotId = tonumber(InParam)
    if self.DialogStoryIndex <= 0 then
        self.DialogStoryIndex = plotId
    end
    if not self.UI_Dialog_Story or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_Story) then
        self.UI_Dialog_Story = self:AddUMG('UI_Dialog_Story')
    end
    self:HideAllUI('UI_Dialog_Story')
    self.UI_Dialog_Story:InitUI(plotId)
    self.UI_Dialog_Story:SetShouldHideLoading2InBackLevel()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.BP_PlayerController_UniverseMenu then
        playerController.BP_PlayerController_UniverseMenu:HidePlanetUI()
    end
    self.PreViewTarget = playerController:K2_GetPawn()
    return self.UI_Dialog_Story
end

function BP_GameInstance_C:OpenStory(InParam)
    print("====OpenStory:" .. InParam)
    local plotId = tonumber(InParam)
    if self.DialogStoryIndex <= 0 then
        self.DialogStoryIndex = plotId
    end
    if not self.UI_Dialog_Story or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_Story) then
        self.UI_Dialog_Story = self:AddUMG('UI_Dialog_Story')
        self:HideAllUI('UI_Dialog_Story')
    else
        self.UI_Dialog_Story.EventOnPlayEnd:Clear()
    end
   
    self.UI_Dialog_Story:InitUI(plotId)
    self.UI_Dialog_Story:SetShouldHideLoading2InBackLevel()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.BP_PlayerController_UniverseMenu then
        playerController.BP_PlayerController_UniverseMenu:HidePlanetUI()
    end
    self.PreViewTarget = playerController:K2_GetPawn()
    return self.UI_Dialog_Story
end

function BP_GameInstance_C:OpenCutScene(InParam)
    local plotId = tonumber(InParam)
    if not self.UI_Dialog_CutScene or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_CutScene) then
        local ui = self:AddUMG('UI_Dialog_Cutscene')
        ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.UI_Dialog_CutScene = ui
        self:HideAllUI('UI_Dialog_Cutscene')
    else
        self.UI_Dialog_CutScene.EventOnPlayEnd:Clear()
    end
   
    self.UI_Dialog_CutScene:InitUI(plotId)
    return self.UI_Dialog_CutScene
end

function BP_GameInstance_C:OpenStoryInSTT(InParam)
    print("====OpenStoryInSTT:" .. InParam)
    local plotId = tonumber(InParam)
    if self.DialogStoryIndex <= 0 then
        self.DialogStoryIndex = plotId
    end
    if not self.UI_Dialog_Story or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_Story) then
        self.UI_Dialog_Story = self:AddUMG('UI_Dialog_Story')
        self:HideAllUI("UI_Dialog_Story")
    else
        self.UI_Dialog_Story.EventOnPlayEnd:Clear()
    end
    
    self.UI_Dialog_Story:SetShouldSkipLoading()
    self.UI_Dialog_Story:InitUI(plotId)

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController.BP_PlayerController_UniverseMenu then
        playerController.BP_PlayerController_UniverseMenu:HidePlanetUI()
    end
    self.PreViewTarget = playerController:K2_GetPawn()
    return self.UI_Dialog_Story
end

function BP_GameInstance_C:OpenCutSceneInSTT(InParam)
    local plotId = tonumber(InParam)
    if not self.UI_Dialog_CutScene or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_CutScene) then
        local ui = self:AddUMG('UI_Dialog_Cutscene')
        ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.UI_Dialog_CutScene = ui
        self:HideAllUI("UI_Dialog_Cutscene")
    else
        self.UI_Dialog_CutScene.EventOnPlayEnd:Clear()
    end
   
    self.UI_Dialog_CutScene:InitUI(plotId)
    return self.UI_Dialog_CutScene
end

function BP_GameInstance_C:ShowTalkUI(id)
    local playId = id
    if id > 0 then
        playId = id
    else
        if self.DialogTalkIndex > 0 then
            playId = self.DialogTalkIndex
        end
    end
    if playId > 0 then
        if not self.UI_Dialog_Talk or not UE.UKismetSystemLibrary.IsValid(self.UI_Dialog_Talk) then
            local ui = self:AddUMG('UI_Dialog_Talk')
            self.UI_Dialog_Talk = ui
        end
        self.UI_Dialog_Talk:InitUI(playId)
    end
    return self.UI_Dialog_Talk
end

function BP_GameInstance_C:CloseTalkUI()
    if self.UI_Dialog_Talk then
        self.UI_Dialog_Talk:Pause()
        self.UI_Dialog_Talk:CloseUI()
        self.UI_Dialog_Talk = nil
    end
end

function BP_GameInstance_C:LoadBackLevel()
    self:CloseTalkUI()
    if self.BackLevelName == "None" then
        self.BackLevelName = "CityMap"
    end
    self:LoadLevel(self.BackLevelName, true)
end

function BP_GameInstance_C:LoadLevel(LevelName, skip_record_back)
    LOG_DEBUG_TRACKBACK("LoadLevel:", LevelName)
    local cur_level_name = UE.UGameplayStatics.GetCurrentLevelName(self, true)
    local LSM = UE.USubsystemBlueprintLibrary.GetGameInstanceSubsystem(self, UE.ULoadingScreenManager)
    if cur_level_name ~= "LoginMap" then
        LSM:SetForceSkipLoadingScreen(false)
    end
    LSM:SetHoldLoadingScreenAdditionalSecsEvenInEditor(true)
    local widget_class
    if LevelName == "FightMap" then
        widget_class = UE.UGHSFunctionLibrary.PackageNameToSoftClassPath("/Game/_Game/Blueprints/UI/UI_Loading.UI_Loading_C")
    else
        widget_class = UE.UGHSFunctionLibrary.PackageNameToSoftClassPath("/Game/_Game/Blueprints/UI/UI_Loading2.UI_Loading2_C")
        -- widget_class = UE.UGHSFunctionLibrary.PackageNameToSoftClassPath("/Game/_Game/Blueprints/UI/UI_Loading.UI_Loading_C")
    end
    LSM:SetUserWidgetClass(widget_class)
    if not skip_record_back then
        self.BackLevelName = cur_level_name -- UE.UKismetStringLibrary.Conv_StringToName(cur_level_name)
    end
    self:CloseTalkUI()
    UE.UGameplayStatics.OpenLevel(self, LevelName, false, "")
end

function BP_GameInstance_C:IsCurrentlyShowingLoadingScreen()
    local LSM = UE.USubsystemBlueprintLibrary.GetGameInstanceSubsystem(self, UE.ULoadingScreenManager)
    return LSM:IsCurrentlyShowingLoadingScreen()
end

function BP_GameInstance_C:LoadStreamLevel(LevelName)
    LOG_DEBUG_TRACKBACK("LoadStreamLevel:", LevelName)
    coroutine.resume(coroutine.create(function()
        -- local ms = UE.UKismetMathLibrary.ToUnixTimestampDouble(UE.UKismetMathLibrary.Now())
        local time_space = UE.UGameplayStatics.GetRealTimeSeconds(self) - self.LastLoadingForStreamLevel
        local delay = time_space > 2 and 0.1 or (2 - time_space)
        LOG_DEBUG("Delay LoadStreamLevel:", LevelName, delay)
        if delay > 2 then
            LOG_DEBUG("FixDelay LoadStreamLevel:", LevelName, 2)
            UE.UKismetSystemLibrary.Delay(self, 2)
        else
            UE.UKismetSystemLibrary.Delay(self, delay)
        end
        LOG_DEBUG("Real LoadStreamLevel:", LevelName)
        UE.UGameplayStatics.LoadStreamLevel(self, LevelName, true, false)
        -- local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
        -- if StreamLevel then
        --     StreamLevel:SetShouldBeVisible(true)
        -- end
        LOG_DEBUG("Done LoadStreamLevel:", LevelName)
        local QuestSystem = require "Module.Quest.QuestSystem"
        QuestSystem:GetInstance():RecheckQuest()
        self:CallOnStreamLevelLoaded(LevelName)
    end))
end

function BP_GameInstance_C:UnloadStreamLevel(LevelName)
    LOG_DEBUG_TRACKBACK("UnloadStreamLevel:", LevelName)
    coroutine.resume(coroutine.create(function()
        local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
        if StreamLevel then
            local time_space = UE.UGameplayStatics.GetRealTimeSeconds(self) - self.LastLoadingForStreamLevel
            local delay = time_space > 2 and 0.1 or (2 - time_space)
            LOG_DEBUG("Delay UnloadStreamLevel:", LevelName, delay)
            if delay > 2 then
                LOG_DEBUG("FixDelay UnloadStreamLevel:", LevelName, 2)
                UE.UKismetSystemLibrary.Delay(self, 2)
            else
                UE.UKismetSystemLibrary.Delay(self, delay)
            end
            LOG_DEBUG("Real UnloadStreamLevel:", LevelName)
            StreamLevel:SetShouldBeVisible(false)
            UE.UGameplayStatics.UnloadStreamLevel(self, LevelName, false)
        end
        LOG_DEBUG("Done UnloadStreamLevel:", LevelName)
        local QuestSystem = require "Module.Quest.QuestSystem"
        QuestSystem:GetInstance():RecheckQuest()
        self:CallOnStreamLevelUnloaded(LevelName)
    end))
end

function BP_GameInstance_C.LoadStreamLevelCoroutine(this, LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad)
    LOG_DEBUG_TRACKBACK("LoadStreamLevelCoroutine:", LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad)
    local self = UE.UGameplayStatics.GetGameInstance(this)
    local time_space = UE.UGameplayStatics.GetRealTimeSeconds(self) - self.LastLoadingForStreamLevel
    local delay = time_space > 2 and 0.1 or (2 - time_space)
    LOG_DEBUG("Delay LoadStreamLevelCoroutine:", LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad, delay)
    if delay > 2 then
        LOG_DEBUG("FixDelay LoadStreamLevelCoroutine:", LevelName, 2)
        UE.UKismetSystemLibrary.Delay(self, 2)
    else
        UE.UKismetSystemLibrary.Delay(self, delay)
    end
    LOG_DEBUG("Real LoadStreamLevelCoroutine:", LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad)
    UE.UGameplayStatics.LoadStreamLevel(self, LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad)
    local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
    if StreamLevel then
        StreamLevel:SetShouldBeVisible(bMakeVisibleAfterLoad)
    end
    LOG_DEBUG("Done LoadStreamLevelCoroutine:", LevelName, bMakeVisibleAfterLoad, bShouldBlockOnLoad)
    local QuestSystem = require "Module.Quest.QuestSystem"
    QuestSystem:GetInstance():RecheckQuest()
    self:CallOnStreamLevelLoaded(LevelName)
end

function BP_GameInstance_C.UnloadStreamLevelCoroutine(this, LevelName, bShouldBlockOnUnload)
    LOG_DEBUG_TRACKBACK("UnloadStreamLevelCoroutine:", LevelName, bShouldBlockOnUnload)
    local self = UE.UGameplayStatics.GetGameInstance(this)
    local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
    if StreamLevel then
        local time_space = UE.UGameplayStatics.GetRealTimeSeconds(self) - self.LastLoadingForStreamLevel
        local delay = time_space > 2 and 0.1 or (2 - time_space)
        LOG_DEBUG("Delay UnloadStreamLevelCoroutine:", LevelName, bShouldBlockOnUnload, delay)
        if delay > 2 then
            LOG_DEBUG("FixDelay UnloadStreamLevelCoroutine:", LevelName, 2)
            UE.UKismetSystemLibrary.Delay(self, 2)
        else
            UE.UKismetSystemLibrary.Delay(self, delay)
        end
        LOG_DEBUG("Real UnloadStreamLevelCoroutine:", LevelName, bShouldBlockOnUnload)
        StreamLevel:SetShouldBeVisible(false)
        UE.UGameplayStatics.UnloadStreamLevel(self, LevelName, bShouldBlockOnUnload)
        LOG_DEBUG("Done UnloadStreamLevelCoroutine:", LevelName, bShouldBlockOnUnload)
        local QuestSystem = require "Module.Quest.QuestSystem"
        QuestSystem:GetInstance():RecheckQuest()
    end
end

function BP_GameInstance_C:StreamLevelSetShouldBeVisible(LevelName, bVisible)
    LOG_DEBUG_TRACKBACK("StreamLevelSetShouldBeVisible:", LevelName, bVisible)
    local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
    if StreamLevel then
        if bVisible then
            if not StreamLevel:IsLevelVisible() then
                local function OnLevelShown()
                    StreamLevel.OnLevelShown:Remove(self, OnLevelShown)
                    self:StreamLevelOnShown(LevelName)
                end
                StreamLevel.OnLevelShown:Add(self, OnLevelShown)
                StreamLevel:SetShouldBeVisible(true)
            end
        else
            if StreamLevel:IsLevelVisible() then
                local function OnLevelHidden()
                    StreamLevel.OnLevelHidden:Remove(self, OnLevelHidden)
                    self:StreamLevelOnHidden(LevelName)
                end
                StreamLevel.OnLevelHidden:Add(self, OnLevelHidden)
                StreamLevel:SetShouldBeVisible(false)
            end
        end
    end
end

function BP_GameInstance_C:StreamLevelSetShouldBeVisibleCoroutine(LevelName, bVisible)
    LOG_DEBUG_TRACKBACK("StreamLevelSetShouldBeVisibleCoroutine:", LevelName, bVisible)
    local StreamLevel = UE.UGameplayStatics.GetStreamingLevel(self, LevelName)
    if StreamLevel then
        if bVisible then
            if not StreamLevel:IsLevelVisible() then
                local visible = false
                local function OnLevelShown()
                    StreamLevel.OnLevelShown:Remove(self, OnLevelShown)
                    self:StreamLevelOnShown(LevelName)
                    visible = true
                end
                StreamLevel.OnLevelShown:Add(self, OnLevelShown)
                StreamLevel:SetShouldBeVisible(true)
                while not visible do
                    -- coroutine.yield()
                    UE.UKismetSystemLibrary.DelayUntilNextTick(self)
                end
            end
        else
            if StreamLevel:IsLevelVisible() then
                local visible = true
                local function OnLevelHidden()
                    StreamLevel.OnLevelHidden:Remove(self, OnLevelHidden)
                    self:StreamLevelOnHidden(LevelName)
                    visible = false
                end
                StreamLevel.OnLevelHidden:Add(self, OnLevelHidden)
                StreamLevel:SetShouldBeVisible(false)
                while visible do
                    -- coroutine.yield()
                    UE.UKismetSystemLibrary.DelayUntilNextTick(self)
                end
            end
        end
    end
end

function BP_GameInstance_C:StreamLevelOnShown(LevelName)
    local QuestSystem = require "Module.Quest.QuestSystem"
    QuestSystem:GetInstance():RecheckQuest()
end

function BP_GameInstance_C:StreamLevelOnHidden(LevelName)
    local QuestSystem = require "Module.Quest.QuestSystem"
    QuestSystem:GetInstance():RecheckQuest()
end

function BP_GameInstance_C:ForceHideHeadUI(bShow)
    if self.UI_Dialog_Talk then
        self.UI_Dialog_Talk:ForceHideHeadUI()
    end
end

function BP_GameInstance_C:PlayStoryEndCallback()
    self:OpenCutScene(self.DialogCutSceneIndex)
    if self.UI_Dialog_CutScene then
        self.UI_Dialog_CutScene.EventOnPlayEnd:Add(self, self.PlayCutSceneEndCallBack)
    end
end

BP_GameInstance_C.TeamListUpdated = "BP_GameInstance_C.TeamListUpdated"

function BP_GameInstance_C:SaveTeamList(result)
    self.Overridden.SaveTeamList(self, result)

    MessageManager:GetInstance():Broadcast(BP_GameInstance_C.TeamListUpdated)
end

---@param self BP_GameInstance_C
BP_GameInstance_C[SrpgController.GameEnded] = function(self)
    if SrpgController:GetInstance():GetEndReason() == SrpgModel.EndReason.Abort then
        ---@type SG_SaveGame_Universe_C
        local gameSave
        if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Universe_" .. self.account_id, 0) then
            gameSave = UE.UGameplayStatics.LoadGameFromSlot("SG_SaveGame_Universe_" .. self.account_id, 0)
        else
            gameSave = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load("/Game/_Game/Blueprints/Game/SG_SaveGame_Universe.SG_SaveGame_Universe_C"))
        end
        gameSave.AbortLastGame = true
        UE.UGameplayStatics.SaveGameToSlot(gameSave, "SG_SaveGame_Universe_" .. self.account_id, 0)
    end

    self.resUniverse = {}
    self.fightType = self.FIGHT_STATE.WAITING
    self.IsFadeInOrOut = false
    
    if self.SRPGBackLevel ~= "None" then
        --1-宇宙行动 2-SpecialSPRG
        local SaveGameSpeak = self:LoadSaveGameSpeak()
        if self.SpecialUniverse == 1 then
        elseif self.SpecialUniverse == 2 then
        end
        self.SpecialUniverse = 0
        self:LoadLevel(self.SRPGBackLevel)
        self.SRPGBackLevel = "None"
    else
        self.SpecialUniverse = 0
        self.BackFromSpeicalUniverse = true
        self:LoadLevel("CityMap")
    end
end

function BP_GameInstance_C:GetAccountName()
    return self.account_id
end

function BP_GameInstance_C:Abort()
    SrpgController:GetInstance():SetEndReason(SrpgModel.EndReason.Abort)

    Client.send(Protos.REQ_COMPLETE_UNIVERSE, {})
end

function BP_GameInstance_C:AbortAndStopRunning()
    --剧情UI清除残留SRPG专用
    SrpgController:GetInstance():SetEndReason(SrpgModel.EndReason.Abort)
    NetworkMessageManager:GetInstance():AddListener("res_complete_universe", self)
    Client.send(Protos.REQ_COMPLETE_UNIVERSE, {})
end

function BP_GameInstance_C:res_complete_universe(result, msgId, parsed_msg)
    --剧情UI清除残留SRPG专用
    if result == 0 then
        SrpgController:GetInstance().model.running = false
    end
    NetworkMessageManager:GetInstance():RemoveListener("res_complete_universe", self)
end

-- 前往配置指定的宇宙
function BP_GameInstance_C:RequestSpecialSrpgLevel(id)
    if SrpgController:GetInstance():IsUniverseExist() and SrpgController:GetInstance():IsSpecificMap() then
        --已有Specific SRPG
        self.SRPGBackLevel = "CityMap"

        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        gameMode.LevelName = "UniverseMap"

        self:LoadLevel("UniverseMap")
    else
        self.fightType = self.FIGHT_STATE.WAITING
        self.specificLevelId = id
        Client.send("req_new_universe_specific", { specific_id = id })
    end
end

function BP_GameInstance_C:OnMessage(type, args)
    if type == 'UI_Daily_Copy' then
        local npcType = tonumber(args)

        local isOpen = false
        local dayOfWeek = UIUtils.GetDayOfWeek()
        local d_levels = require 'ClientDatas.d_levels'
        for id, level_info in ipairs(d_levels) do
            for _, openDay in ipairs(level_info.openTime) do
                local isTypeOne = npcType == 1 and (level_info.levelType == 3 or level_info.levelType == 4) 
                local isTypeTwo = npcType == 2 and (level_info.levelType == 1 or level_info.levelType == 5)
                if dayOfWeek == openDay and (isTypeOne or isTypeTwo) then
                    isOpen = true
                    break
                end
            end
        end

        if npcType == 1 and not isOpen then
            UIUtils.ShowNotify(self, Database.L10n(261))
        elseif npcType == 2 and not isOpen then
            UIUtils.ShowNotify(self, Database.L10n(262))
        else
            if npcType == 1 then
                if self:OpenLink(9001, 1) then
                    local ui = self:GetUMG('UI_Daily_Copy')
                    if ui then
                        ui:InitUI(npcType)
                    end
                end
            elseif npcType == 2 then
                if self:OpenLink(9002, 1) then
                    local ui = self:GetUMG('UI_Daily_Copy')
                    if ui then
                        ui:InitUI(npcType)
                    end
                end
            end
        end
    elseif type == 'UI_Tutorial' then
        self:ShowTutorial(tonumber(args))
    elseif type == 'OpenActivityUI' then
        local activityType = tonumber(args)
      
        if activityType == 1 then
            if self:OpenLink(9021, "") then
                local ui = self:GetUMG('UI_Challenge_Copy')
                if ui then
                    ui:RefreshUI('')
                end
            end
        end 
    elseif type == 'openlink' then
        self:OpenLink(args[1], args[2], args[3] or 0)
    elseif type == 'debugui' then
        self:DebugUI()
    elseif type == 'com_notice' then
        local str
        if args[1] then
            local n = math.tointeger(args[1])
            if n then
                str = Database.L10n(n)
            else
                str = args[1]
            end
        else
            str = "测试"
        end
        UIManager:GetInstance():ShowConfirm({
            notice = str,
            showCancel = false,
        })
    elseif type == 'handbook' then
        local ui = self:AddUMG('UI_HandBook')
        if ui and ui.InitUIEx then
            ui:InitUIEx(tonumber(args))
        end

    elseif type == 'add_all' then
        local msg = 'add_item'
        local config = require('ClientDatas.d_com_params')
        for id, v in pairs(config) do 
            if id >= 16 and id <= 21 then
                local paramsArr = v.value
                if #paramsArr % 3 == 0 then
                    for i = 1, #paramsArr, 3 do 
                        local item_id = paramsArr[i]
                        local config = UIUtils.GetItemConfigById(item_id)
                        -- print('----itemId:' .. tostring(item_id) .. ",config:" .. tostring(config ~= nil))
                        if config then
                            msg = msg .. ' ' .. paramsArr[i] .. ' ' .. paramsArr[i + 1] .. ' ' .. paramsArr[i + 2]
                        else
                            LOG_ERROR('----add_all error id:' .. tostring(item_id))
                        end
                    end
                else
                    LOG_ERROR('----add_all error id:' .. tostring(paramsArr[1]) .. ',' .. tostring(paramsArr[2] or nil) .. ',' .. tostring(paramsArr[3] or nil))
                end
            end
        end 

        Client.send("req_gm_cmd", { cmd = msg })
    elseif type == 'unlock_storyline' then
        local PlotSystem = require("Module.Plot.PlotSystem")
        PlotSystem:GetInstance():ReqUnlockStoryLines(tonumber(args[1]))
    elseif type == 'add_char' then
        local config = require('ClientDatas.d_com_params')
        
        local paramsArr = config[23].value
        for i = 1, #paramsArr do 
            Client.send("req_gm_cmd", { cmd = 'add_item ' .. paramsArr[i] .. ' ' .. 12 .. ' ' .. 1 })
        end
    elseif type == 'OpenTempCopy' then
        self:OpenTempCopy(args)
    elseif type == 'Srpg_Growth_Shop' then
        if self:OpenLinkEx(9022) then
            local shopUI = UE4.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/UI_SRPG_Shop/UI_SRPG_Shop_Growth.UI_SRPG_Shop_Growth_C'))
            UIManager:GetInstance():AddUI(shopUI)
            shopUI:Init()
        end
    elseif type == 'OnChangedStreamingLevel' then
        MessageManager:GetInstance():Broadcast('OnChangedStreamingLevel')
    elseif type == 'debuglevel' then
        self:DebugLevel()
    -- elseif type == 'debugtrack' then
    --     local ui = self:GetUMG('UI_City')
    --     if ui then
    --         ui:DebugTrack()
    --     end
    elseif type == 'AnimationLooping' then
        MessageManager:GetInstance():Broadcast('AnimationLooping')
    elseif type == 'AnimationDialog' then
        MessageManager:GetInstance():Broadcast('AnimationDialog', args)
    elseif type == 'ShowFightNotify' then
        self:ShowFightNotify(tonumber(args[2]), tonumber(args[3]))
    elseif type == 'send_msg' then
        local cmd = math.tointeger(args[1])
        local s = args[2]
        if not cmd or not s then
            UIUtils.ShowNotify(self, "send_msg发送失败-参数错误")
            return
        end
        local pbmsg = require "Helper.pbmsg"
        local _, msg_name = pbmsg.get_msg_name_and_field_name(cmd)
        local base64 = require "_Game.Utils.base64"
        local s_json = base64.decode(s)
        if not s_json then
            UIUtils.ShowNotify(self, "send_msg发送失败-base64解析错误")
            return
        end
        local rapidjson = require "rapidjson"
        local isok, msg = pcall(rapidjson.decode, s_json)
        if not isok then
            UIUtils.ShowNotify(self, "send_msg发送失败-json解析错误")
            return
        end
        Client.send(msg_name, msg)
        UIUtils.ShowNotify(self, "send_msg发送成功")
    elseif type == 'GlobalTimeDilation' then
        print('---->GlobalTimeDilation:' .. tostring(UE.UGameplayStatics.GetGlobalTimeDilation(self)))
    elseif type == 'change_server_time' then
        local time = UIUtils.ParseTimeStr(args[1] .. ' ' .. args[2])
        local msg = { cmd = 'change_server_time ' .. tostring(time) }
        Client.send("req_gm_cmd", msg)
    end
end

function BP_GameInstance_C:GetFightType()
    return self.fightType
end

function BP_GameInstance_C:GetFightType(type)
    self.fightType = type
end

--显示引导ui
function BP_GameInstance_C:ShowTutorial(id, bPauseGame)
    local id = tonumber(id)
    local ui = self:AddDialogUI('UI_tutorial') 
    ui:InitUI(id, bPauseGame)
    ui.Slot:SetZOrder(100)
    return ui
end

function BP_GameInstance_C:HideTutorial()
    local ui = self:GetUMG('UI_Tutorial')
    if ui then
        UIManager:GetInstance():RemoveUI(ui)
    end
end

function BP_GameInstance_C:ReturnToLoginMap()
    Client:close()
    self.reconnecting = false
    self:LoadLevel("LoginMap", true)
end

function BP_GameInstance_C:ntf_kick(result, msgId, parsed_msg)
    -- local player_controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    -- player_controller:DisableInput()
    Client:close()
    self.reconnecting = false
    self.reconnect_failed = true
    local UIUtils = require "_Game.Utils.UIUtils"
    
    local wordId = 0
    if parsed_msg.ntf_kick.reason == 1 then --您的帐号在其他设备登陆
        wordId = 50504
    elseif parsed_msg.ntf_kick.reason == 2 then --服务器关闭中
        wordId = 50505
    elseif parsed_msg.ntf_kick.reason == 3 then --失去与服务器的连接，请重新登录
        wordId = 50503
    elseif parsed_msg.ntf_kick.reason == 4 then --协议不匹配，请尝试更新游戏
        wordId = 50506
    elseif parsed_msg.ntf_kick.reason == 5 then --信息传输失败，请尝试更新游戏
        wordId = 50507
    elseif parsed_msg.ntf_kick.reason == 6 then --您的账号已被封禁
        wordId = 50508
    elseif parsed_msg.ntf_kick.reason == 7 then --信息传输内容错误，请尝试更新游戏
        wordId = 50509
    end
    local text = '<span color="#FF0000FF">' .. Database.L10n(wordId) .. '</>'
    UIUtils.ShowComNotice(text, self, function()
        self.reconnect_failed = false
        self:LoadLevel("LoginMap", true)
    end)
end

----------------------------------------------------------------------
--跳转相关
function BP_GameInstance_C:OpenLink(type, args1, args2)
    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
    print('openlink--->' .. tostring(type))
    local config = d_bag_item_link[tonumber(type)]
    if config then
        --判定是否解锁
        local PlotSystem = require("Module.Plot.PlotSystem")
        if not PlotSystem:GetInstance():IsHasKey(1) then
            if config.Condition and tonumber(config.Condition) then
                local needKey = tonumber(config.Condition)
                if not PlotSystem:GetInstance():IsHasKey(needKey) then
                    UIUtils.ShowNotify(self, Database.L10n(50602))
                    return false
                end
            end
        end

        --发送给任务系统判断
        MessageManager:GetInstance():Broadcast('OnMsg_InteractionOpenUI', tonumber(type))
       
        --跳转到角色系统
        if config.id == 9009 then
            local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
            if pc and pc.BP_PlayerController_City_UniverseBridge and pc.BP_PlayerController_City_UniverseBridge.LoadCharacterSystem then
                pc.BP_PlayerController_City_UniverseBridge:LoadCharacterSystem(0, 0)
            end
            return true
        end
        if config.id == 9007 then
            --判断宇宙是否存在
            if self:GetUniverseExists() then
                local gameMode = UE.UGameplayStatics.GetGameMode(self)
                gameMode:BPI_SetLevelName('UniverseMap')
                local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
                pc:OnOpenNextLevel()
                return true
            end
        end
        --抽卡场景判断
        if config.id == 9024 then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local sceneId = gameInstance:GetCurrentSceneId()
            if sceneId == UIUtils.SceneId.OpeningScene then
                UIUtils.ShowComNotice(Database.L10n(448), self, function()
                end) 
                return false
            end
        end
        --试炼战斗ui和总力战ui 判定不在地铁和家装地图中
        if config.id == 9010 or config.id == 9027 then
             --判定当前是否在家装或者地铁站
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            local sceneId = gameInstance:GetCurrentSceneId()
            if sceneId == UIUtils.SceneId.City1Station or sceneId == UIUtils.SceneId.City1Hotel then
                UIUtils.ShowComNotice(Database.L10n(448), self, function()
                end) 
                return false
            end
        end
        if config.UI and config.UI ~= '' then
            local ui = self:AddUMG(config.UI)
            if ui and ui.InitUIEx then
                ui:InitUIEx(config.args)
            end
        end
    end
    return true
end

function BP_GameInstance_C:OpenLinkEx(type, dontShowTip)
    local d_bag_item_link = require('ClientDatas.d_bag_item_link')
    local config = d_bag_item_link[tonumber(type)]
    if config then
        --判定是否解锁
        local PlotSystem = require("Module.Plot.PlotSystem")
        if not PlotSystem:GetInstance():IsHasKey(1) then
            if config.Condition and tonumber(config.Condition) then
                local needKey = tonumber(config.Condition)
                if not PlotSystem:GetInstance():IsHasKey(needKey) then
                    if not dontShowTip then
                        UIUtils.ShowNotify(self, Database.L10n(50602))
                    end
                    return false, nil
                end
            end
        end
    end
    return true, config
end

----------------------------------------------------------------------
--UI相关
local loading_ui_names = nil
local function is_loading_ui_name(ui_name)
    loading_ui_names = loading_ui_names or {
        string.lower("UI_StreamLoading"),
        string.lower("UI_Loading"),
        string.lower("UI_Loading2"),
        string.lower("UI_Loading3"),
    }
    for _, loading_ui_name in ipairs(loading_ui_names) do
        if ui_name == loading_ui_name then
            return true
        end
    end
    return false
end
function BP_GameInstance_C:AddDialogUI(UIName)
    UIName = string.lower(UIName)
    local uiConfig = nil
    local d_ui_path = require('ClientDatas.d_ui_path')
    for _, v in pairs(d_ui_path) do
        if string.lower(v.uiName) == UIName then
            uiConfig = v
            break
        end
    end
    if uiConfig and uiConfig.path and uiConfig.path ~= '' then
        --重新创建新的ui
        local path = uiConfig.path
        if not string.endswith(path, "_C'") then
            path = string.sub(path, 1, -2) .. "_C'"
        end
        local widget_class = UE.UClass.Load(path)
        if widget_class then
            local ui = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
            if ui then
                UIManager:GetInstance():AddUI(ui)
                return ui
            end
        end
    end
    return nil
end


function BP_GameInstance_C:AddUMG(UIName, bMultiUI, z_order)
    if not UIManager:GetInstance().layers or not UIManager:GetInstance().layers.Normal then
        return nil 
    end

    UIName = string.lower(UIName)
    local isLoading = is_loading_ui_name(UIName)
    local uiConfig = nil
    local d_ui_path = require('ClientDatas.d_ui_path')
    for _, v in pairs(d_ui_path) do
        if string.lower(v.uiName) == UIName then
            uiConfig = v
            break
        end
    end
    
    if uiConfig and uiConfig.path and uiConfig.path ~= '' then
        --判断是否在显示
        if not bMultiUI then
            if self:RemoveUMG(UIName) then
                LOG_WARN('-------->不允许多个ui,移除当前正在显示的ui:' .. tostring(UIName))
            end
        end
        
        --重新创建新的ui
        local path = uiConfig.path
        if not string.endswith(path, "_C'") then
            path = string.sub(path, 1, -2) .. "_C'"
        end
        local widget_class = UE.UClass.Load(path)
        if widget_class then
            local ui = UE4.UWidgetBlueprintLibrary.Create(self, widget_class, UE.UGameplayStatics.GetPlayerController(self, 0))
            -- if not ui then
            --     ui = NewObject(widget_class)
            -- end
            if ui then
                if isLoading then
                    UIManager:GetInstance():AddLoadingUI(ui, z_order)
                else
                    local upUI = z_order
                    UIManager:GetInstance():AddUI(ui, upUI)
                end
                return ui
            end
        end
    else
        LOG_ERROR('---添加ui:' .. tostring(UIName) .. ',未在配置表中配置d_ui_path')
    end
    return nil
end

function BP_GameInstance_C:RemoveUMG(UIName, upUI)
    if UIName == "UI_Loading2" then
        self.LastLoadingForStreamLevel = 0
    end
    if type(UIName) == 'table' then
        local wiget = UIName
        if wiget.GetClass then
            local className = string.lower(wiget:GetClass():GetName())
            if string.endswith(className, "_c") then
                className = string.sub(className, 1, -3)
            end
            UIName = className
        end
    else
        UIName = string.lower(UIName)
    end
    
    local isLoading = is_loading_ui_name(UIName)
    local ui = self:GetUMG(UIName)
    if ui then
        if isLoading then
            UIManager:GetInstance():RemoveLoadingUI(ui)
        else
            UIManager:GetInstance():RemoveUI(ui, upUI)
        end
        return true
    end
    return false
end

function BP_GameInstance_C:GetOrAddUMG(UIName, bMultiUI, z_order)
    local ui = self:GetUMG(UIName, bMultiUI)
    if ui then
        if UIName == "UI_Loading2" then
            ui:CancelDelayDestroy()
        end
        return ui
    end
    if UIName == "UI_Loading2" then
        self.LastLoadingForStreamLevel = UE.UGameplayStatics.GetRealTimeSeconds(self)
    end
    return self:AddUMG(UIName, bMultiUI, z_order)
end

function BP_GameInstance_C:AddLoadingUMG(UIName, z_order)
    UIName = string.lower(UIName)
    local uiConfig = nil
    local d_ui_path = require('ClientDatas.d_ui_path')
    for _, v in pairs(d_ui_path) do
        if string.lower(v.uiName) == UIName then
            uiConfig = v
            break
        end
    end
    
    if uiConfig and uiConfig.path and uiConfig.path ~= '' then
        --判断是否在显示
        self:RemoveUMG(UIName)
        
        --重新创建新的ui
        local path = uiConfig.path
        if not string.endswith(path, "_C'") then
            path = string.sub(path, 1, -2) .. "_C'"
        end
        local widget_class = UE.UClass.Load(path)
        if widget_class then
            local ui = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
            -- if not ui then
            --     ui = NewObject(widget_class)
            -- end
            if ui then
                UIManager:GetInstance():AddLoadingUI(ui, z_order)
                return ui
            end
        end
    else
        LOG_ERROR('---添加ui:' .. tostring(UIName) .. ',未在配置表中配置d_ui_path')
    end
    return nil
end

function BP_GameInstance_C:GetLoadingUMG(UIName)
    UIName = string.lower(UIName)
    local widgetList = UIManager:GetInstance().layers.Loading:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == UIName then
            return ui
        end
    end
    return nil
end

function BP_GameInstance_C:GetUMG(UIName, bMultiUI)
    UIName = string.lower(UIName)
    local isLoading = is_loading_ui_name(UIName)
    if isLoading then
        local loadingUI = self:GetLoadingUMG(UIName)
        if loadingUI then
            return loadingUI
        end
    end
    if not UIManager:GetInstance().layers or not UIManager:GetInstance().layers.Normal then
        return nil 
    end
    local widgetList = UIManager:GetInstance().layers.Normal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == UIName then
            return ui
        end
    end

    local widgetList = UIManager:GetInstance().layers.UpNormal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == UIName then
            return ui
        end
    end

    local widgetList = UIManager:GetInstance().layers.Talk:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == UIName then
            return ui
        end
    end
    return nil
end

function BP_GameInstance_C:GetAllUMG(UIName)
    if not UIManager:GetInstance().layers or not UIManager:GetInstance().layers.Normal then
        return nil 
    end

    UIName = string.lower(UIName or "")
    local result = UE.TArray(UE.UWidget)

    local widgetList = UIManager:GetInstance().layers.Normal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if UIName == "" or className == UIName then
            result:Add(ui)
        end
    end

    local widgetList = UIManager:GetInstance().layers.UpNormal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if UIName == "" or className == UIName then
            result:Add(ui)
        end
    end
    return result
end

function BP_GameInstance_C:HideAllUI(onlyShowUIName)
    LOG_DEBUG_TRACKBACK("HideAllUI:", onlyShowUIName)
    self:RemoveUMG("UI_PlayerLevelUp")
    if type(onlyShowUIName) == 'table' then
        if onlyShowUIName.GetClass then
            onlyShowUIName = onlyShowUIName:GetClass():GetName()
        end
    end
    if not self.UICahed then self.UICahed = {} end
    onlyShowUIName = string.lower(onlyShowUIName or "")
    local uiCached = {}
    local widgetList = UIManager:GetInstance().layers.Normal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == onlyShowUIName then
            ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        else
            ui:StopAllAnimations()
            uiCached[className] = self.UICahed[className] or ui:GetVisibility()
            ui:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    local widgetList = UIManager:GetInstance().layers.UpNormal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className == onlyShowUIName then
            ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        else
           
            uiCached[className] = self.UICahed[className] or ui:GetVisibility()
            ui:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
    self.UICahed = uiCached
end

function BP_GameInstance_C:ShowAllUI()
    LOG_DEBUG_TRACKBACK("ShowAllUI:")
    local widgetList = UIManager:GetInstance().layers.Normal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if self.UICahed and self.UICahed[className] then
            ui:SetVisibility(self.UICahed[className])
            if ui.OnShow then
                ui:OnShow()
            end
        end
    end
    local widgetList = UIManager:GetInstance().layers.UpNormal:GetAllChildren()
    for _, ui in pairs(widgetList) do
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if self.UICahed and self.UICahed[className] then
            ui:SetVisibility(self.UICahed[className])
            if ui.OnShow then
                ui:OnShow()
            end
        end
    end
    self.UICahed = {}
end

function BP_GameInstance_C:GetTopUI()
    local widgetList = UIManager:GetInstance().layers.UpNormal:GetAllChildren()
    local allUICount = widgetList:Length()
    for i = allUICount, 1, -1 do
        local ui = widgetList:Get(i)
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className ~= 'ui_stt_button' then
            return ui , allUICount
        end
    end
    local widgetList = UIManager:GetInstance().layers.Normal:GetAllChildren()
    local allUICount = widgetList:Length()
    for i = allUICount, 1, -1 do
        local ui = widgetList:Get(i)
        local className = string.lower(ui:GetClass():GetName())
        if string.endswith(className, "_c") then
            className = string.sub(className, 1, -3)
        end
        if className ~= 'ui_stt_button' then
            return ui , allUICount
        end
    end
    return nil, 0
end

--显示/隐藏最上层ui
function BP_GameInstance_C:ShowTopUI(bShow)
    bShow = bShow or false
    local ui = self:GetTopUI()
    if ui then
        ui:SetVisibility(bShow and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        if bShow and ui.OnShow then
            ui:OnShow()
        elseif not bShow and ui.OnHide then
            ui:OnHide()
        end
    else
        print('----showtopui: eror!')
    end
end

--删除最上面一个ui
function BP_GameInstance_C:RemoveTopUI(bShowNewTopUI)
    self:DebugUI()
    local ui, count = self:GetTopUI()
    if ui then
        --强制不能删除ui_city
        if count > 1 then
            UIManager:GetInstance():RemoveUI(ui)
        else
            -- LOG_ERROR('Error!!! ---RemoveTopUI:' .. tostring(ui:GetClass():GetName()))
        end
    end
    if bShowNewTopUI then
        self:ShowTopUI(true)
    end
end

--debugui
function BP_GameInstance_C:DebugUI()
    UIManager:GetInstance():DebugUI()
end

function BP_GameInstance_C:AddInteractOptionEx(OptionId)
    local ui_city = self:GetUMG('UI_City')
    if ui_city then
        local option = ui_city:AddOptionItem(Database.L10n(OptionId))
        return option
    end
    return nil
end

function BP_GameInstance_C:RemoveInteractOptionEx(opItem)
    local ui_city = self:GetUMG('UI_City')
    if ui_city then
        ui_city:RemoveOptionItem(opItem)
    end
end

----------------------------------------------------------------------
---pick 
function BP_GameInstance_C:OnPickSuccess(rewardList)
    UIUtils.ShowGetRewardCommonUI(self, rewardList)
end

function BP_GameInstance_C:OnMsg_Bag_Init()
    local PlayerSystem = require "Module.Player.PlayerSystem"
    local level = UIUtils.GetPlayerLevel()
    PlayerSystem:GetInstance().Level = level
end

function BP_GameInstance_C:OnMsg_Player_LevelUp(oldLevel, newLevel)
    UIUtils.ShowPlayerLevelUp(self, oldLevel, newLevel)
end

function BP_GameInstance_C:ParseCharacterTrainl(teamPosStr)
    local teamList = self:LoadTeamList()
    if not teamList then
        teamList = self:CreateTeamList()
    end

    if type(teamPosStr) ~= 'table' then
        teamPosStr = teamPosStr:ToTable()
    end 
    local strArr = teamPosStr
    local freeRoleNum = 0
    local teamData = teamList.TrainTeamInfo:Get(1)
    local TrainPos = teamList.TrainPos
    local d_character_trial = require('ClientDatas.d_character_trial')
    for idx, str in ipairs(strArr) do
        local trainCharId = tonumber(str)
        if trainCharId == 1 then freeRoleNum = freeRoleNum + 1 end
        TrainPos:Set(idx, trainCharId)

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
    self:SaveTeamList()
    return freeRoleNum
end

---临时战斗
function BP_GameInstance_C:OpenTempCopy(fight_level_id, teamPosStr)
    local config = Database.Query('d_levels_challenge', fight_level_id)
    if not config then return end
    local classPath = config.path
    if not string.endswith(classPath, "_C'") then
        local sub = string.sub(classPath, 1, -2) .. "_C'"
        classPath = sub
    end
    self.LevelClass = UE.UClass.Load(classPath)

    self.fightCanBack = false
    self.fightMsg = { fight_level_id = fight_level_id }
    self.fightType = self.FIGHT_STATE.TempCopy

    if not teamPosStr then
        teamPosStr = config.characterTrial
    end
    local freeRoleNum = self:ParseCharacterTrainl(teamPosStr)

    --记录当前ui和管卡
    -- self.UIName = 'UI_CharTrain'
    -- self.UIArgs = self.SelectedTabIndex .. '|' .. self.SelectedLevelIndex
    self:CachePlayInCity()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if freeRoleNum > 0 then
        if playerController and playerController.BP_PlayerController_City_UniverseBridge then
            if playerController.LoadFightBeforeInCity then
                
                self.CachedSubLevel = 'City1BusinessCenter'
                self:HideAllUI()
                
                local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
                controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    
                playerController:LoadFightBeforeInCity()
            end
        end
    else
        --self:ShowTopUI(false)
        playerController.BP_PlayerController_City_UniverseBridge:FastLoadFight()
    end 

end

function BP_GameInstance_C:OnUpdateBuild(WasSuccessful)
    Update._on_update_build(self, WasSuccessful)
end

function BP_GameInstance_C:OnMountChunks(WasSuccessful)
    Update._on_mount_chunks(self, WasSuccessful)
end

function BP_GameInstance_C:OnChangedStreamingLevel()
    local sgspeak = self:LoadSaveGameSpeak()
    if not sgspeak.StoryFinished then
        local MainFlys = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "MainFly")
        if MainFlys:Length() > 0 then
            for i = 1, MainFlys:Length() do 
                MainFlys:Get(i):SetActorHiddenInGame(true)
                MainFlys:Get(i):K2_GetRootComponent():SetCollisionProfileName('Spectator', true)
            end
        end
        local FlyBoxs = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "flybox_coli")
        if FlyBoxs:Length() > 0 then
            for i = 1, FlyBoxs:Length() do 
                FlyBoxs:Get(i):SetActorHiddenInGame(true)
                FlyBoxs:Get(i):K2_GetRootComponent():SetCollisionProfileName('Spectator', true)
            end
        end

        local bpIronArmLow = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BP_IronArmLow")
        if bpIronArmLow:Length() > 0 then
            for i = 1, bpIronArmLow:Length() do 
                bpIronArmLow:Get(i):SetActorHiddenInGame(true)
            end
        end
    else
        local FlyBoxs = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ASkeletalMeshActor, "flybox_coli")
        if FlyBoxs:Length() > 0 then
            for i = 1, FlyBoxs:Length() do 
                FlyBoxs:Get(i):SetActorHiddenInGame(true)
                FlyBoxs:Get(i):K2_GetRootComponent():SetCollisionProfileName('Spectator', true)
            end
        end
        local bpIronArmLow = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AActor, "BP_IronArmLow")
        if bpIronArmLow:Length() > 0 then
            for i = 1, bpIronArmLow:Length() do 
                bpIronArmLow:Get(i):SetActorHiddenInGame(true)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------
---切换bgm
function BP_GameInstance_C:ChangeBgm(path, params)
    print('----self.DialogBmg:' .. tostring(self.DialogBmg))
    print('---changeBgm:' .. tostring(path) .. ',params:' .. tostring(params))
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)

    local isDifferentBmg = false
    if self.DialogBmg ~= path then
        self.DialogBmg = path
        isDifferentBmg = true
        if playerController and playerController.CityBGM and UE.UKismetSystemLibrary.IsValid(playerController.CityBGM) then
            playerController.CityBGM:SetPaused(true)
        elseif playerController and playerController.BP_PlayerController_UniverseMenu and playerController.BP_PlayerController_UniverseMenu.UniverseBGM then
            playerController.BP_PlayerController_UniverseMenu.UniverseBGM:SetPaused(true)
        end
        if UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
            print('---DialogComp:FadeOut:' .. tostring(self.FadeOutTime))
            self.DialogComp:FadeOut(self.FadeOutTime or 0, 1)
        end
    end
    if not UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
        print('-------------222: load object:' .. tostring(path))
        local audioSource = LoadObject(path)
        if audioSource then
            print('---CreateSound2D:')
            local justNew = LoadObject("/Script/Engine.SoundConcurrency'/Game/_Game/SoundEffects/ConcurrencyPresets/SCon_BGMJustNew.SCon_BGMJustNew'")
            -- self.AudioComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource, 1, 1, 0, justNew)
            self.DialogComp = UE.UGameplayStatics.CreateSound2D(self, audioSource, 1, 1, 0, justNew)
            self.DialogComp.bAutoDestroy = false
            self.DialogComp.bIsUISound = true
            self.DialogComp:SetTickableWhenPaused(true)
        else
            print('-------------222: load failed:' .. tostring(path))
        end
    end
    print('---params:' .. tostring(params))
    if params ~= '' and (isDifferentBmg or (not isDifferentBmg and self.DialogBmgParams ~= params)) then --0|0|1|0|0.5
        self.DialogBmgParams = params
        local strArr = string.split(params, '|')
        local delayTime = tonumber(strArr[1])
        local volume = tonumber(strArr[3])
        self.FadeOutTime = tonumber(strArr[5])
        if UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
            self.DialogComp:SetVolumeMultiplier(volume)
            if isDifferentBmg then
                if delayTime > 0 then
                    print('---delayChangeBgm:' .. tostring(delayTime))
                    self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
                        { self, self.DelayChangeBgm }, 
                        delayTime, 
                        false
                    )
                else
                    print('---delayChangeBgm2' .. tostring(delayTime))
                    self:DelayChangeBgm()
                end
            end
        end
    end
    
    self.Overridden.ChangeBgm(self, path, params)
end

function BP_GameInstance_C:DelayChangeBgm()
    if UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
        self.DialogComp:Stop()
    end
    local audioSource = LoadObject(self.DialogBmg)
    if audioSource then
        local justNew = LoadObject("/Script/Engine.SoundConcurrency'/Game/_Game/SoundEffects/ConcurrencyPresets/SCon_BGMJustNew.SCon_BGMJustNew'")
        self.DialogComp = UE.UGameplayStatics.SpawnSound2D(self, audioSource, 1, 1, 0, justNew)
        -- self.DialogComp = UE.UGameplayStatics.CreateSound2D(self, audioSource)
        if UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
            local strArr = string.split(self.DialogBmgParams, '|')
            local startTime = tonumber(strArr[2])
            local fadeInTime = tonumber(strArr[4])
            self.DialogComp:FadeIn(fadeInTime, 1, startTime)
        end
    end
    self.Overridden.DelayChangeBgm(self)
end

function BP_GameInstance_C:ClearBgm()
    if UE.UKismetSystemLibrary.IsValid(self.DialogComp) then
        self.DialogComp:Stop()
        self.DialogComp.bAutoDestroy = true
        self.DialogComp = nil
    end
    if self.DoDelayTimerHandler then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self.DoDelayTimerHandler)
        self.DoDelayTimerHandler = nil
    end

    self.DialogBmg = ''
    self.DialogBmgParams = ''
    self.Overridden.ClearBgm(self)
end

function BP_GameInstance_C:LevelIsVisible(levelName)  
    local levelNames = self:GetVisibleStreamingLevel()
    if levelNames:Length() > 0 then
        for i = 1, levelNames:Length() do 
            local streamingLevelName = levelNames:Get(i)
            if streamingLevelName == levelName then
                return true
            end
        end
    end
    return false
end

function BP_GameInstance_C:ShowDebug()
    local debugUI = UE.UWidgetBlueprintLibrary.Create(self, LoadClass('/Game/_Game/Blueprints/UI/Debug.Debug_C'))

    UIManager:GetInstance():AddUI(debugUI)
    debugUI:SetUp()
end

function BP_GameInstance_C:FinishUniverseFly()
    local mapName = UE.UGameplayStatics.GetCurrentLevelName(self, true)
    local str_start, str_end = string.find(tostring(mapName), "Speak_Universe")
    if str_start and str_end then
        local map_id = tonumber(string.sub(tostring(mapName), str_end + 2, #tostring(mapName)))
        if map_id then
            MessageManager:GetInstance():Broadcast("OnMsg_Complete_UniverseFly", map_id)
        end
    end
end

function BP_GameInstance_C:GetEnterStreamingLevels(enterLevelNames)
    --获取当前场景加载的场景 保存数据
    local loadedLevels = UE.TArray(UE.FName)
    UE.UGHSFunctionLibrary.LSS_Plugin_GetStreamingLevelsInfo(self, nil, nil, loadedLevels, nil)
    if not self.LoadedStreamingLevelNameStack then
        self.LoadedStreamingLevelNameStack = {}
    end
    local curLevelNames = {}
    local currentLoadedLevels = loadedLevels:ToTable()
    for _, levelName in pairs(currentLoadedLevels) do
        if string.contains(levelName, 'UEDPIE_') then
            levelName = string.sub(levelName, 10, -1)
        end
        if not string.contains(levelName, 'LevelInstance_') then
            local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, levelName)
            if levelScene and levelScene:IsLevelLoaded() and levelScene:IsLevelVisible() then
                table.insert(curLevelNames, levelName)
            end
        end
    end
    if #curLevelNames == 0 then
        table.insert(curLevelNames, 'City1BusinessCenter')
    end
    return self:GetNeedLoadStreamingLevelNames(curLevelNames, enterLevelNames)
end

function BP_GameInstance_C:GetLeaveStreamingLevels()
    local topIndex = #self.LoadedStreamingLevelNameStack
    local topLevelInfo = self.LoadedStreamingLevelNameStack[topIndex]
    if topLevelInfo then 
        local curLevelNames = topLevelInfo[2] or {}
        local enterLevelNames = topLevelInfo[1] or {}
        return self:GetNeedLoadStreamingLevelNames(curLevelNames, enterLevelNames)
    end
    
    return {}, {}
end

function BP_GameInstance_C:GetNeedLoadStreamingLevelNames(leaveLevelNames, enterLevelNames)
    --复制数组
    local curLevelInfo = {}
    local enterLevelInfo = {}

    print('----->当前场景:' .. tostring(table.dump(leaveLevelNames, nil, 10)))
    print('----->进入场景:' .. tostring(table.dump(enterLevelNames, nil, 10)))

    for _, levelName in pairs(leaveLevelNames) do
        table.insert(curLevelInfo, levelName)
    end

    for _, levelName in pairs(enterLevelNames) do
        table.insert(enterLevelInfo, levelName)
    end

    local deleteLevelName = {}
    --去除卸载场景中重复场景名字
    for _, unloadName in pairs(curLevelInfo) do 
        for _, loadName in pairs(enterLevelInfo) do
            if unloadName == loadName then
                table.insert(deleteLevelName, unloadName)
            end
        end
    end
    for _, name in pairs(deleteLevelName) do
        table.removebyvalue(curLevelInfo, name)
        table.removebyvalue(enterLevelInfo, name)
    end
    print('----->当前场景2:' .. tostring(table.dump(curLevelInfo, nil, 10)))
    print('----->进入场景2:' .. tostring(table.dump(enterLevelInfo, nil, 10)))
    return curLevelInfo, enterLevelInfo
end

-------------------------------------------------------
---进入loadLevelNames场景
function BP_GameInstance_C:EnterStreamingLevel(enterLevelNames, bShowLoading2, isRecover, callback)
    self.OnChangeLevelCity:Broadcast(self)
    --删除所有动态的sequence 太暴力了
    -- local levelSequenceActor = UE.UGameplayStatics.GetAllActorsOfClass(self, UE.ALevelSequenceActor)
    -- if levelSequenceActor:Length() > 0 then
    --     for i = 1, levelSequenceActor:Length() do
    --         levelSequenceActor:Get(i):K2_DestroyActor()
    --     end
    -- end


    --获取主控角色 关闭身体和头发的物理
    -- self:SetPlayerSimulatePhysics(false)
    UIManager:GetInstance():ClearInteractOption()
    --复制数组
    local curLevelInfo = {}
    local enterLevelInfo = enterLevelNames

    if not isRecover then
        --获取当前场景加载的场景 保存数据
        local curLevelNames, enterLevelNames2 = self:GetEnterStreamingLevels(enterLevelInfo)
        print('----->EnterStreamingLevel.curLevelNames:' .. tostring(table.dump(curLevelNames, nil, 10)))
        print('----->EnterStreamingLevel.enterLevelNames2' .. tostring(table.dump(enterLevelNames2, nil, 10)))
        -- if #curLevelNames == 0 then
        --     table.insert(curLevelNames, 'City1BusinessCenter')
        --     local loadedLevels = UE.TArray(UE.FName)
        --     UE.UGHSFunctionLibrary.LSS_Plugin_GetStreamingLevelsInfo(self, nil, nil, loadedLevels, nil)
        --     enterLevelNames2 = loadedLevels:ToTable()
        -- end
        table.insert(self.LoadedStreamingLevelNameStack, { curLevelNames, enterLevelNames2 })

        curLevelInfo = curLevelNames
        enterLevelInfo = enterLevelNames2
    end


    local allLevelCount = #curLevelInfo + #enterLevelInfo
    self:OnAdvanceLoadStreamingLevel(0, allLevelCount, bShowLoading2)

    self.hideLevelCount = 0
    self.hideLevelAllCount = table.count(curLevelInfo)
    self.curLevelInfo = curLevelInfo
    self.enterLevelInfo = enterLevelInfo
    self.allLevelCount = allLevelCount
    self.bShowLoading2 = bShowLoading2
    self.callback = callback

    --卸载场景
    if table.count(curLevelInfo) > 0 then
        for i, levelName in pairs(curLevelInfo) do
            self:OnAdvanceLoadStreamingLevel(i, allLevelCount, bShowLoading2)
            local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, levelName)
            if levelScene then
                print('------OnLevelHidden:' .. tostring(levelName))
                if levelScene:IsLevelLoaded() and levelScene:IsLevelVisible() then
                    levelScene.OnLevelShown:Clear()
                    levelScene.OnLevelHidden:Clear()
                    levelScene.OnLevelHidden:Add(self, self.OnEnterStreamingLevel_LevelHidden)
                    self:StreamLevelSetShouldBeVisible(levelName, false)
                else
                    self:OnEnterStreamingLevel_LevelHidden()
                end
            else
                print('----------not streaming:' .. tostring(levelName))
            end
            --UE.UGameplayStatics.UnloadStreamLevel(self, levelName, true, false)
        end
    else
        self:OnEnterStreamingLevel_LevelHidden()
    end
end

function BP_GameInstance_C:OnEnterStreamingLevel_LevelHidden()
    self.hideLevelCount = self.hideLevelCount + 1
    print("---->OnEnterStreamingLevel_LevelHidden:" .. tostring(self.hideLevelCount) .. ",all:" .. tostring(self.hideLevelAllCount))
    if self.hideLevelCount >= self.hideLevelAllCount then
        if table.count(self.curLevelInfo) > 0 then
            for i, levelName in pairs(self.curLevelInfo) do
                local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, levelName)
                if levelScene then
                    levelScene.OnLevelShown:Clear()
                    levelScene.OnLevelHidden:Clear()
                end
            end
        end
        coroutine.resume(coroutine.create(function()
            --加载新场景
            for i, levelName in pairs(self.enterLevelInfo) do
                self:OnAdvanceLoadStreamingLevel(self.hideLevelCount + i, self.allLevelCount, self.bShowLoading2)
                self.LoadStreamLevelCoroutine(self, levelName, true, false)
                print('------LoadStreamLevel:' .. tostring(levelName))
            end
            self:OnAdvanceLoadStreamingLevel(self.allLevelCount, self.allLevelCount, self.bShowLoading2)
            print('-----------进入场景完成:')
            --获取主控角色 开启身体和头发的物理
            -- self:SetPlayerSimulatePhysics(true)
            if self.callback then
                local obj = self.callback[1]
                local func = self.callback[2]
                func(obj)
            end
        end))
    end
end

function BP_GameInstance_C:OnLeaveStreamingLevel_LevelShown()
    self.showLevelCount = self.showLevelCount + 1
    if self.showLevelCount >= self.showLevelAllCount then
        if table.count(self.enterLevelInfo) > 0 then
            for i, levelName in pairs(self.enterLevelInfo) do
                local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, levelName)
                if levelScene then
                    levelScene.OnLevelShown:Clear()
                    levelScene.OnLevelHidden:Clear()
                end
            end
        end
        self:OnAdvanceLoadStreamingLevel(self.allLevelCount, self.allLevelCount, self.bShowLoading2)
        print('-----------离开场景完成:')
        --获取主控角色 开启身体和头发的物理
        -- self:SetPlayerSimulatePhysics(true)
        if self.callback then
            local obj = self.callback[1]
            local func = self.callback[2]
            func(obj)
        else
            -- 这里不该隐藏，可能后续还有需要遮挡，而且OnAdvanceLoadStreamingLevel也会显示
            -- self:RemoveUMG("UI_Loading2")
        end
    end
end

--离开上次进入的场景
function BP_GameInstance_C:LeaveStreamingLevel(bShowLoading2, callback)
    UIManager:GetInstance():ClearTracker()
    --获取主控角色 关闭身体和头发的物理
    -- self:SetPlayerSimulatePhysics(false)
    UIManager:GetInstance():ClearInteractOption()
    if not self.LoadedStreamingLevelNameStack then self.LoadedStreamingLevelNameStack = {} end
    if #self.LoadedStreamingLevelNameStack == 0 then
        LOG_WARN('------>current not level name is record!!!')
        if callback then
            local obj = callback[1]
            local func = callback[2]
            func(obj)
        end
        return
    else
        local currentLevelInfo, enterLevelInfo = self:GetLeaveStreamingLevels()
        local topIndex = #self.LoadedStreamingLevelNameStack
        table.remove(self.LoadedStreamingLevelNameStack, topIndex)

        local allLevelCount = #currentLevelInfo + #enterLevelInfo
        self.showLevelCount = 0
        self.showLevelAllCount = table.count(enterLevelInfo)
        self.enterLevelInfo = enterLevelInfo
        self.allLevelCount = allLevelCount
        self.bShowLoading2 = bShowLoading2
        self.callback = callback

        self:OnAdvanceLoadStreamingLevel(0, allLevelCount, bShowLoading2)

        coroutine.resume(coroutine.create(function()
            local hideLevelAllCount = table.count(currentLevelInfo)
            --卸载场景
            for i, levelName in pairs(currentLevelInfo) do
                self:OnAdvanceLoadStreamingLevel(i, allLevelCount, bShowLoading2)
                self.UnloadStreamLevelCoroutine(self, levelName, true, false)
                print('------UnloadStreamLevel:' .. tostring(levelName))
            end
            --加载新场景
            if table.count(enterLevelInfo) > 0 then
                for i, levelName in pairs(enterLevelInfo) do
                    self:OnAdvanceLoadStreamingLevel(hideLevelAllCount + i, allLevelCount, bShowLoading2)
                    local levelScene = UE.UGameplayStatics.GetStreamingLevel(self, levelName)
                    if levelScene and levelScene:IsLevelLoaded() and not levelScene:IsLevelVisible() then
                        levelScene.OnLevelHidden:Clear()
                        levelScene.OnLevelShown:Clear()
                        levelScene.OnLevelShown:Add(self, self.OnLeaveStreamingLevel_LevelShown)
                        self:StreamLevelSetShouldBeVisible(levelName, true)
                        print('------OnLevelShown:' .. tostring(levelName))
                    else
                        print('---------2')
                        self.LoadStreamLevelCoroutine(self, levelName, true, false)
                        self:OnLeaveStreamingLevel_LevelShown()
                    end
                end
            else
                -- self:SetPlayerSimulatePhysics(false)
                if self.callback then
                    local obj = self.callback[1]
                    local func = self.callback[2]
                    func(obj)
                end
            end
        end))
    end
end

function BP_GameInstance_C:OnAdvanceLoadStreamingLevel(curLoadLevelCount, allLevelCount, bShowLoading2)
    if not bShowLoading2 then 
        -- local ui = self:GetUMG("UI_Loading2")
        -- if ui then
        --    self:RemoveUMG("UI_Loading2") 
        -- end
        return 
    end
    -- if not self.UI_Loading2 then
    --     self.UI_Loading2 = self:GetOrAddUMG("UI_Loading2", nil, 1)
    -- end
    -- self.UI_Loading2 = self:GetOrAddUMG("UI_Loading2", nil, 1)
    if self.UI_Loading2 and UE.UKismetSystemLibrary.IsValid(self.UI_Loading2) then
        self.UI_Loading2:RefreshUI(curLoadLevelCount, allLevelCount)
    end

    if curLoadLevelCount == allLevelCount then
        -- self:RemoveUMG("UI_Loading2")
        -- self.UI_Loading2 = nil
    end
end

function BP_GameInstance_C:GetTopLevelInfo()
    if not self.LoadedStreamingLevelNameStack then
        self.LoadedStreamingLevelNameStack = {}
    end
    local topIndex = #self.LoadedStreamingLevelNameStack
    if topIndex > 0 then
        return self.LoadedStreamingLevelNameStack[topIndex]
    end
    return nil
end

--提供给剧情强制清空历史信息
function BP_GameInstance_C:ClearTopLevelInfo()
    self.LoadedStreamingLevelNameStack = {}
end


function BP_GameInstance_C:SetPlayerSimulatePhysics(bSimulatePhysics)
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        if player.Mesh then
            player.Mesh:SetSimulatePhysics(bSimulatePhysics) 
        end
        if player.hair then
            player.hair:SetSimulatePhysics(bSimulatePhysics) 
        end
    end
end
---新加载流场景
-------------------------------------------------------

function BP_GameInstance_C:GetUISttButton()
    if not self.UI_STT_Button or not UE.UKismetSystemLibrary.IsValid(self.UI_STT_Button) then
        self.UI_STT_Button = self:AddUMG('UI_STT_Button')
    end
    return self.UI_STT_Button
end

function BP_GameInstance_C:ShowFightNotify(wordId, duration)
    local ui = self:GetUMG('UI_Fight')
    if not ui then 
        ui = self:GetUMG('UI_City')
    end
    if ui then
        ui:ShowFightNotify(Database.L10n(wordId), duration)
    end
end

function BP_GameInstance_C:HideFightNotify()
    local ui = self:GetUMG('UI_Fight')
    if not ui then 
        ui = self:GetUMG('UI_City')
    end
    if ui then
        ui:HideFightNotify()
    end
end

function BP_GameInstance_C:OnMsg_MailInit()
    self.bIsInitReqMsg = false
end

function BP_GameInstance_C:OnMsg_Res_Charge_Mall_Buy(parsed_msg)
    self.gameOrderId = parsed_msg.res_mall_buy.game_order_id
end

function BP_GameInstance_C:RecordPlayerTransformBeforeFight()
    local saveGameSpeak = self:LoadSaveGameSpeak()
    if not saveGameSpeak.StoryFinished then
        if self.fightType == self.FIGHT_STATE.DailyCopy
            or self.fightType == self.FIGHT_STATE.CharTrainCopy
            or self.fightType == self.FIGHT_STATE.ChallengeCopy then
            self:RecordPlayerTransform()
        end
    end
end

function BP_GameInstance_C:RecordPlayerTransform()
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode.Player
    if player then
        local msg = {}
        local location = player:K2_GetActorLocation()
        local rotation = player:K2_GetActorRotation()
        msg.player_transform_in_scene = {}
        local scene_id = self:GetCurrentSceneId()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
        --compare
        local transform = UE.UKismetMathLibrary.MakeTransform(
            location,
            rotation,
            UE.FVector(1, 1, 1))
        gameInstance:SaveSaveGameSpeak()
        saveGameSpeak.PlayerTransformInScene = transform
        msg.player_transform_in_scene.scene_id = scene_id
        msg.player_transform_in_scene.location = { location.X, location.Y, location.Z }
        msg.player_transform_in_scene.yaw = rotation.yaw
        Client.send("req_record_player_transform_in_scene", msg)
    else
        --当前没有角色可能是刚开始游戏就进战斗了
    end
end

function BP_GameInstance_C:GetCurrentSceneId()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local levelNames = gameInstance:GetVisibleStreamingLevel()
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

function BP_GameInstance_C:GetLoadLevelName()
    local levelName = UE.TArray(UE.FName)
    local PlayerSystem = require('Module.Player.PlayerSystem')
    local playerInfo = PlayerSystem:GetInstance().PlayerInfo
    if playerInfo and #playerInfo.player_transform_in_scenes > 0 then
        local transform_in_scene = playerInfo.player_transform_in_scenes[1]
        if transform_in_scene.scene_id == UIUtils.SceneId.City1Station then
            levelName:Add(UE.FName("City1Station"))
        elseif transform_in_scene.scene_id == UIUtils.SceneId.City1Hotel then
            levelName:Add(UE.FName("City1Hotel"))
        end
    end
    return levelName
end

function BP_GameInstance_C:StartTrackPos(trackId, startOrEnd, pos)
    LOG_DEBUG_TRACKBACK('---->StartTrackPos:' .. tostring(trackId) .. ", startOrEnd" .. tostring(startOrEnd) .. ", pos:" .. tostring(pos))
    -- local ui = self:GetUMG('UI_City')
    -- if ui then
    --     ui:StartTrackPos(trackId, startOrEnd, pos)
    -- else
    --     if not pos then
    --         UIManager:GetInstance():ClearTracker()
    --     else
    --         UIManager:GetInstance():CreateTracker(pos)
    --     end
    -- end
    if not startOrEnd then
        UIManager:GetInstance():ClearTracker()
    else
        UIManager:GetInstance():CreateTracker(pos)
    end
end

function BP_GameInstance_C:StartTrackPosEx(trackId, startOrEnd, pos)
    LOG_DEBUG_TRACKBACK('---->StartTrackPosEx:' .. tostring(trackId) .. ", startOrEnd" .. tostring(startOrEnd) .. ", pos:" .. tostring(pos))
    -- local ui = self:GetUMG('UI_City')
    -- if ui then
    --     ui:StartTrackPos(trackId, startOrEnd, pos)
    -- else
    --     if not pos then
    --         UIManager:GetInstance():ClearTracker()
    --     else
    --         UIManager:GetInstance():CreateTracker(pos)
    --     end
    -- end
    if not startOrEnd then
        UIManager:GetInstance():ClearTracker()
    else
        UIManager:GetInstance():CreateTracker(pos)
    end
end

----------------------------------------------------------
--终极loading
function BP_GameInstance_C:ShowLoading3(delayTimeToDestroy) 
    local ui = self:AddLoadingUMG('UI_Loading3')
    if ui then
        ui:RefreshUI(delayTimeToDestroy)
    end
end

return BP_GameInstance_C

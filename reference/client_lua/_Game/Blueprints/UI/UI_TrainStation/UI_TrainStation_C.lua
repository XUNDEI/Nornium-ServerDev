require "UnLua"
require "Common.TableUtil"

---@type UI_TrainStation_C
local M = UnLua.Class()

local Database = require('_Game.Utils.Database')
local UIUtils = require('_Game.Utils.UIUtils')
local GachaSystem = require('Module.Gacha.GachaSystem')
local PlayerSystem = require('Module.Player.PlayerSystem')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local NetworkMessageManager = require('Framework.Updater.NetworkMessageManager')
local MessageManager = require('Framework.Updater.MessageManager')
local UI_CityMenu_C = require "_Game.Blueprints.UI.UI_CityMenu.UI_CItyMenu_C"
local BackpackSystem = require("Module.Backpack.BackpackSystem")

M.EnableMove = true
M.InputMappingContexts = {
    InputAssets.IMC_UI_SystemEntry,
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Gacha,
    -- InputAssets.IMC_UI_Cursor,
}

-- InputUtils.RegisterMouseEvent(M)
--构造函数
function M:Construct()
    self:InitUI()
    self:InitData()
    MessageManager:GetInstance():AddListener('OnMsg_Gacha_Create', self)
    NetworkMessageManager:GetInstance():AddListener('res_gacha_confirm', self)
    NetworkMessageManager:GetInstance():AddListener('res_gacha_choose_card', self)
    MessageManager:GetInstance():AddListener('OnGachaFinished', self)
    MessageManager:GetInstance():AddListener('OnMsg_SO_TrainCabin_Opened', self)
    MessageManager:GetInstance():AddListener('OnMsg_Ding_Cancel', self)
    MessageManager:GetInstance():AddListener('OnMsg_GachaDing', self)
    MessageManager:GetInstance():AddListener('OnLoadCharacterSystem', self)
    MessageManager:GetInstance():AddListener('OnMsg_OpenAllCabin', self)
    MessageManager:GetInstance():AddListener('OnMsg_SwapTicket', self)
    -- self:ChangeBgm()
    self.Overridden.Construct(self)
end

function M:Destruct()
    local cameraManagerActor = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
    if cameraManagerActor then
        cameraManagerActor:StopAllCameraShakes()
    end

    MessageManager:GetInstance():RemoveListener('OnMsg_Gacha_Create', self)
    NetworkMessageManager:GetInstance():RemoveListener('res_gacha_confirm', self)
    NetworkMessageManager:GetInstance():RemoveListener('res_gacha_choose_card', self)
    MessageManager:GetInstance():RemoveListener('OnGachaFinished', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_SO_TrainCabin_Opened', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_Ding_Cancel', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_GachaDing', self)
    MessageManager:GetInstance():RemoveListener('OnLoadCharacterSystem', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_OpenAllCabin', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_SwapTicket', self)


    self.TrainCar1:K2_DestroyActor()
    self.TrainCar2:K2_DestroyActor()
    self.TrainCar1 = nil
    self.TrainCar2 = nil
    self.CurTrainCarIndex = 0
    self.SelectedTabUI = nil
    if self.ArrivalSequenceActor then
        self.ArrivalSequenceActor:K2_DestroyActor()
        self.ArrivalSequenceActor = nil
    end
    if self.LevelSequenceActor then
        self.LevelSequenceActor:K2_DestroyActor()
        self.LevelSequenceActor = nil
    end
end

function M:OnGachaFinished(poolId, gachaType)
    self.bIsStudy = false
    self.LastSelectedTabIndex = math.max(self.LastSelectedTabIndex - 1, 1)
    self:RefreshUI()
    if gachaType == UIUtils.EGachaPoolType.NewPlayer then
        UIUtils.ShowComNotice(Database.L10n(499), self, function()
            
        end)
    end
end

function M:OnMsg_SwapTicket()
    if self.bIsTenLottery then
        self:OnClicked_Btn_TenLottery()
    else
        self:OnClicked_Btn_OneLottery()
    end
end

function M:GetLastGachaCreateInfo()
    local gachaInfo =  GachaSystem:GetInstance().GachaInfo
    if gachaInfo and gachaInfo.gacha_list_infos then
        for gachaId, gachaList in pairs(gachaInfo.gacha_list_infos) do
            local config = require('ClientDatas.d_gacha_list')[gachaId]
            -- if config and (config.gachaType == UIUtils.EGachaPoolType.CharPool or config.gachaType == UIUtils.EGachaPoolType.WeaponPool) then
            if config then
                if gachaList.gacha_pending_record_infos and
                    table.count(gachaList.gacha_pending_record_infos) > 0 then
                    if config.gachaType == UIUtils.EGachaPoolType.NewPlayer then
                        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                        if not gameInstance:GetIsGachaAllOpened() then
                            return gachaId, DeepCopy(gachaList.gacha_pending_record_infos), config.gachaType
                        end
                    else
                        return gachaId, DeepCopy(gachaList.gacha_pending_record_infos), config.gachaType
                    end
                end
            end
        end
    end
    return 0, nil, 0
end

function M:OnInitAnimation()
    self.bIsStudy = false
    local player = UE.UGameplayStatics.GetGameMode(self):BPI_GetPlayer()
    print('---------OnInitAnimation' .. tostring(player))
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    --判断是否有上次up池奖励可ding
    local gachaId, pendingList, gachaType = self:GetLastGachaCreateInfo()
    if gachaId and 
        gachaId > 0 and 
        pendingList and 
        table.count(pendingList) > 0 then
        print('---------有记录')
        for i = 1, 5 do 
            local itemUI = self.SO_Train_UI['Widget' .. i]:GetWidget().UI_TrainStation_Tab1
            local config = self.GachaConfigList[i]
            if config then
                if config.gachaId == gachaId then
                    self.SelectedTabUI = itemUI
                    self.LastSelectedTabIndex = i
                end
            end
        end
        self:RefreshUI(true)

        self:OnClicked_Btn_Quit()
        self.CurTrainCarIndex = 0

        if table.count(pendingList) > 1 then
            table.sort(pendingList, function(a, b)
                if a.gacha_item_type ~= b.gacha_item_type then
                    return a.gacha_item_rarity > b.gacha_item_rarity
                end
                if a.gacha_item_rarity ~= b.gacha_item_rarity then
                    return a.gacha_item_rarity > b.gacha_item_rarity
                end
                return false
            end)
        end

        self:InitSoTrainInfo(gachaId, pendingList)
        local carActor = self.CurTrainCarIndex == 0 and self.TrainCar1 or self.TrainCar2
        carActor:K2_SetActorLocation(UE.FVector(0, 1338.833471, -3580.0), false, nil, false)

        self.CurTrainCarIndex = 1
        self.IsCarIn = true

        self:ShowAutoOpenAllCabinOptions()
        self:ShowPanelLottery(false)

        --查询所有ding的索引
        self.DingQueue = {}
    else
        print('---------无记录')
        local cameraArray = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACameraActor, 'TrainStationInitPos')
        print('---------cameraArray:' .. tostring(cameraArray:Length()))
        if cameraArray:Length() > 0 then
            local camera = cameraArray:Get(1)
            if camera then
                print('---------SetViewTargetWithBlend')
                pc:SetViewTargetWithBlend(camera, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
            end
        end

        local studyMissionId = 100030105
        local isFinished = false
        local PlotSystem = require("Module.Plot.PlotSystem")
        local missions = PlotSystem:GetInstance().PlotInfo.completed_mission_ids
        for _, mission_id in ipairs(missions) do
            if mission_id == studyMissionId then
                isFinished = true
                break
            end
        end
        if not isFinished then
            --判断任务100030104是否完成，播放剧情1000039019
            local QuestSystem = require("Module.Quest.QuestSystem")
            local QuestInfo = QuestSystem:GetInstance():GetQuestInfo(studyMissionId)
            if (QuestInfo and (not QuestInfo.completed or not QuestInfo.finished)) then
                self:OnClicked_Btn_Quit()
                -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                -- local ui = gameInstance:OpenPlot(1000039019)
                -- if ui then
                --     ui.EventOnPlayEnd:Add(self, self.OnEvent_UI_Dialog_Stroy_PlayEnd)
                -- end
                print('---------任务未完成!')
                ---只显示教学池
                self.bIsStudy = true
            end
        end
        self:RefreshUI(true)
    end
    local player = UE.UGameplayStatics.GetGameMode(self):BPI_GetPlayer()
    if player and not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
        player.CharacterMovement:SetActive(true, false)
    end

    --播放sequence
    self:PlayAnimationForward(self.vfxin)
    self.UI_TrainStation_Tab:PlayAnimationForward(self.UI_TrainStation_Tab.vfxin)
end

function M:OnHide()
    -- print("----------dingQueue:" .. tostring(table.dump(self.DingQueue, nil, 10)))
    --判断是否抽卡未完成
    if not self:IsAllCabinOpened() or (self.DingQueue and #self.DingQueue > 0) then
        UIUtils.ShowNotify(self, Database.L10n(442))
        return
    end
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    --判断是否接机完成否则提示
    self:UnbindAllFromAnimationFinished(self.vfxquit)
    self:BindToAnimationFinished(self.vfxquit, function()
        UIManager:GetInstance():RemoveUI(self)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        if pc and pc.UnloadStationScene then
            pc:UnloadStationScene()
        end
    end)
    self:PlayAnimationForward(self.vfxquit)
    self.UI_TrainStation_Tab:UnbindAllFromAnimationFinished(self.UI_TrainStation_Tab.vfxquit)
    self.UI_TrainStation_Tab:PlayAnimationForward(self.UI_TrainStation_Tab.vfxquit)
end

function M:InitUI()
    -- print('--------->InitUI')
    self.Btn_Quit.OnGHSClicked:Add(self, self.OnClicked_Back)
    self.UI_MenuButton.OnClicked:Add(self, self.OnClicked_MenuButton)

    self.Btn_One.OnGHSClicked:Add(self, self.OnClicked_Btn_OneLottery)
    self.Btn_Ten.OnGHSClicked:Add(self, self.OnClicked_Btn_TenLottery)

    self.Btn_Detail.OnClicked:Add(self, self.OnClicked_Btn_Detail) --详情
    self.Btn_Exchange.OnClicked:Add(self, self.OnClicked_Btn_Exchange) --兑换-->跳转商店
    self.Btn_Up.OnClicked:Add(self, self.OnClicked_Btn_Up) --角色试用
    self.Btn_Welfare.OnClicked:Add(self, self.OnClicked_Btn_Welfare) --接机结果
    self.Btn_Always.OnClicked:Add(self, self.OnClicked_Btn_Always) --自选

    self.Btn_Open.OnGHSClicked:Add(self, self.OnClicked_Btn_Open)

    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    self.ShowInteractOptions = false
    self.HideCursor = false
    UIManager:GetInstance().layers.bg:SetVisibility(UE.ESlateVisibility.Hidden)
    UIManager:GetInstance().layers:SetRequireShowInteractOptions(false)
    UIManager:GetInstance():SetForceShowCursor(true)

    self.Panel_MenuButton:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.UI_TrainStation_Tab:SetRenderOpacity(0)
    self.UI_TrainStation_Tab.Btn_Tab:SetVisibility(UE.ESlateVisibility.Hidden)

    self.UI_MenuMissionStory:SetVisibility(UE.ESlateVisibility.Hidden)
    -- self.Panel_Lottery:SetVisibility(UE.ESlateVisibility.Hidden)


    self.LastSelectedTabIndex = 0

    self.ShakePath = '/Game/_Game/Blueprints/UI/UI_TrainStation/BP_TrainShake.BP_TrainShake_C'
    self.GachaTickNormalPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201003_png.Icon_mini_1201003_png' --常驻抽卡券
    self.GachaTickLimitPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201001_png.Icon_mini_1201001_png'--限定抽卡券
end

function M:OnShow()
    if UE.UKismetSystemLibrary.IsValid(self.SelectedTabUI) then return end

    --获取场景中的所有车
    local cars = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, self.CarClass, 'TrainCar1')
    self.TrainCar1 = cars:Get(1)
    local cars = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, self.CarClass, 'TrainCar2')
    self.TrainCar2 = cars:Get(1)

    --获取场景中所有面片
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "TrainAdPlane")
    if actors:Length() > 0 then
        self.TrainAdPlane = actors:ToTable()
    end
    --立柱
    actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "TrainAdPlane1")
    if actors:Length() > 0 then
        self.TrainAdPlane1 = actors:ToTable()
    end

    --缓存动画材质实例
    -- local M_Screen_Inst1 = UE.UObject.Load('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/pingmu/M_Screen_Inst1.M_Screen_Inst1')
    -- self.MaterialInstance1 = UE.UKismetMaterialLibrary.CreateDynamicMaterialInstance(self, M_Screen_Inst1)
    local M_Screen_Inst2 = UE.UObject.Load('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/pingmu/M_Screen_Inst1_Inst.M_Screen_Inst1_Inst')
    self.MaterialInstance2 = UE.UKismetMaterialLibrary.CreateDynamicMaterialInstance(self, M_Screen_Inst2)
    -- for _, plane in pairs(self.TrainAdPlane) do
    --     plane.StaticMeshComponent:SetMaterial(0, self.MaterialInstance1)
    -- end
    for _, plane in pairs(self.TrainAdPlane1) do
        plane.StaticMeshComponent:SetMaterial(1, self.MaterialInstance2)
    end

    --获取3dui
    local class = UE.LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_Train_UI.SO_Train_UI_C')
    self.SO_Train_UI = UE.UGameplayStatics.GetActorOfClass(self, class)
    if not self.SO_Train_UI then
        local trans = UE.UKismetMathLibrary.MakeTransform(
            UE.FVector(-1169, 90, -3531), 
            UE.FRotator(0, 30, 0), 
            UE.FVector(1, 1, 1))
        self.SO_Train_UI = self:GetWorld():SpawnActor(class,
            trans,
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)
    end

    self:RefreshUI(true)
end

function M:InitData()
    -- print('--------->InitData')
    local trans = UE.UKismetMathLibrary.MakeTransform(UE.FVector(-20000, 1338.833471, -3580.0), UE.FRotator(0, 180, 0), UE.FVector(1, 1, 1))
    --动态创建2个车
    self.CarClass = UE.LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_Train_Car.SO_Train_Car_C')
    self.TrainCar1 = self:GetWorld():SpawnActor(self.CarClass, trans, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    self.TrainCar1.Tags:Add('TrainCar1')
    self.TrainCar2 = self:GetWorld():SpawnActor(self.CarClass, trans, UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
    self.TrainCar2.Tags:Add('TrainCar2')
    self.CurTrainCarIndex = 0

    self.CarArrivalSequence = LoadObject('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/SQ_Train_Arrival.SQ_Train_Arrival')
    self.CarLeaveSequence = LoadObject('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/SQ_Train_Leave.SQ_Train_Leave')

    self.IsPossessedChar = false
    self.SelectedTabUI = nil --默认选中的奖池id
    self.bShowOpenAll = false

    --获取车的actor
    -- local class = UE.LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_Train_Car.SO_Train_Car_C')
    -- local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, class, "MainTrain")
    -- if actors:Length() > 0 then
    --     self.SO_Train_Car = actors:Get(1)
    -- end

    --获取场景中所有面片
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "TrainAdPlane")
    if actors:Length() > 0 then
        self.TrainAdPlane = actors:ToTable()
    end
    --立柱
    local actors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.AStaticMeshActor, "TrainAdPlane1")
    if actors:Length() > 0 then
        self.TrainAdPlane1 = actors:ToTable()
    end
    self.TrainAdPlane = self.TrainAdPlane or {}
    self.TrainAdPlane1 = self.TrainAdPlane1 or {}

    --缓存动画材质实例
    -- local M_Screen_Inst1 = UE.UObject.Load('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/pingmu/M_Screen_Inst1.M_Screen_Inst1')
    -- self.MaterialInstance1 = UE.UKismetMaterialLibrary.CreateDynamicMaterialInstance(self, M_Screen_Inst1)
    local M_Screen_Inst2 = UE.UObject.Load('/Game/_Game/3DRES/Effect/NiagaraSystem/ditie/pingmu/M_Screen_Inst1_Inst.M_Screen_Inst1_Inst')
    self.MaterialInstance2 = UE.UKismetMaterialLibrary.CreateDynamicMaterialInstance(self, M_Screen_Inst2)
    -- for _, plane in pairs(self.TrainAdPlane) do
    --     plane.StaticMeshComponent:SetMaterial(0, self.MaterialInstance1)
    -- end
    for _, plane in pairs(self.TrainAdPlane1) do
        plane.StaticMeshComponent:SetMaterial(1, self.MaterialInstance2)
    end

    --获取3dui
    local class = UE.LoadClass('/Game/_Game/Blueprints/SceneObjects/SO_Train_UI.SO_Train_UI_C')
    self.SO_Train_UI = UE.UGameplayStatics.GetActorOfClass(self, class)
    if not self.SO_Train_UI then
        local trans = UE.UKismetMathLibrary.MakeTransform(
            UE.FVector(-1169, 90, -3531), 
            UE.FRotator(0, 30, 0), 
            UE.FVector(1, 1, 1))
        self.SO_Train_UI = self:GetWorld():SpawnActor(class,
            trans,
            UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn,
            self, self)
    end

    self:RefreshUI()

    --播放摄像机shake
    local cameraManagerActor = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
    self.CameraShake = cameraManagerActor:StartCameraShakeFromSource(LoadClass(self.ShakePath), nil)

    self.DingQueue = {}
end

function M:OnEvent_UI_Dialog_Stroy_PlayEnd()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Dialog_Story')
    if ui then
        ui.EventOnPlayEnd:Remove(self, self.OnEvent_UI_Dialog_Stroy_PlayEnd)

        self:OnClicked_Btn_Quit()
    end
end

function M:RefreshUI(bIsForce)
    -- local umg = self.SO_Train_UI.Widget:GetWidget()
    self.GachaConfigList = self:InitGachaConfigList()
    print('-----InitGachaConfigList:' .. tostring(table.dump(self.GachaConfigList, nil, 10)))
    local d_gacha_list = require('ClientDatas.d_gacha_list')
    for i = 1, 5 do 
        local itemUI = self.SO_Train_UI['Widget' .. i]:GetWidget().UI_TrainStation_Tab1
        itemUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        local config = self.GachaConfigList[i]
        if config then
            print('-------->config.gachaId:' .. tostring(config.gachaId))
            local listConfig = d_gacha_list[config.gachaId]
            if listConfig then
                itemUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                itemUI.Index = i
                itemUI.ID = listConfig.id
                itemUI.Layer = listConfig.gachaType
                --活动名字
                itemUI.Text_Name:SetText(Database.L10n(config.gachaName))
                itemUI.Text_Name_ON:SetText(Database.L10n(config.gachaName))
                if config.bannerTab ~= '' then
                    local bg_texture = UE.UObject.Load(config.bannerTab)
                    if bg_texture then
                        itemUI.Tab:SetBrushFromTexture(bg_texture)
                    end
                end
                itemUI.Btn_Tab.OnClicked:Add(self, function()
                    self:OnClicked_Btn_Tab(itemUI, config)
                end)
                if self.LastSelectedTabIndex == 0 and not self.SelectedTabUI then 
                    self.SelectedTabUI = itemUI
                    self.LastSelectedTabIndex = itemUI.Index
                    self.SelectedTabUI.Image_6:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self.SelectedTabUI.Image_7:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self.SelectedTabUI.Text_Name:SetVisibility(UE.ESlateVisibility.Hidden)
                    self.SelectedTabUI.Text_Name_ON:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self:RefreshMainPanel(config, bIsForce)
                    self.SelectedTabUI.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
                elseif self.LastSelectedTabIndex > 0 and i == self.LastSelectedTabIndex then
                    self.SelectedTabUI = itemUI
                    self.LastSelectedTabIndex = itemUI.Index
                    self.SelectedTabUI.Image_6:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self.SelectedTabUI.Image_7:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self.SelectedTabUI.Text_Name:SetVisibility(UE.ESlateVisibility.Hidden)
                    self.SelectedTabUI.Text_Name_ON:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    self:RefreshMainPanel(config, bIsForce)
                    self.SelectedTabUI.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
                else
                    itemUI.Text_Name:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                    itemUI.Text_Name_ON:SetVisibility(UE.ESlateVisibility.Hidden)

                    itemUI.Image_6:SetVisibility(UE.ESlateVisibility.Hidden)
                    itemUI.Image_7:SetVisibility(UE.ESlateVisibility.Hidden)

                    itemUI.Panel_Main:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
                end

                itemUI.UI_Key_OneLottery:SetVisibility(UE.ESlateVisibility.Hidden)
            else
                print('-------->无2此活动')
                itemUI:SetVisibility(UE.ESlateVisibility.Collapsed)
            end
        else
            print('-------->无此活动')
            itemUI:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
    end
end

function M:InitGachaConfigList()
    local result = {}
    local d_gacha_schedule = require('ClientDatas.d_gacha_schedule')

    for _, v in ipairs(d_gacha_schedule) do
        -- print('--v.id:' .. tostring(v.gachaId) .. ',start:' .. tostring(v.startTime) .. ',end:' .. tostring(v.endTime))
        local startTime = UIUtils.ParseTimeStr(v.startTime)
        local endTime = UIUtils.ParseTimeStr(v.endTime)
        local server_time = PlayerSystem:GetInstance():GetServerTime()
        if server_time >= startTime and server_time < endTime then
            --判定是否完成
            if not GachaSystem:GetInstance():IsFinished(v.gachaId) then
                local config = Database.Query('d_gacha_list', v.gachaId)
                if config and config.gachaType == UIUtils.EGachaPoolType.Study then
                    if self.bIsStudy then
                        table.insert(result, v)
                    end
                else
                    if not self.bIsStudy then
                        table.insert(result, v)
                    end
                end
            end
        end
    end
    if #result > 0 then
        table.sort(result, function(a, b)
            return a.order < b.order
        end)
    end
    return result
end

function M:GetGachaTicketImg(ticketId)
    if not ticketId or ticketId <= 0 then
        return nil
    end
    local strIcon = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', ticketId, ticketId)
    return LoadObject(strIcon)
end

--刷新左边面板
function M:RefreshMainPanel(config, bIsForce, bPlayInAnimation)
    if not config then
        print("-------------没有配置config:") 
        do return end
    end
    self.Panel_Detail:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Study and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.Visible)

    --货币栏
    local currencyData = {}
    if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool or
        self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.WeaponPool or
        self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer then
        currencyData = { UIUtils.EGachaTicket.GachaTickLimit, UIUtils.ECurrencyId.Diamond }
    else
        currencyData = { UIUtils.EGachaTicket.GachaTickNormal, UIUtils.ECurrencyId.Diamond }
    end
    self.UI_Money:RefreshData(currencyData)

    print('---------gachaId:' .. tostring(config.gachaId))
    local listConfig = Database.Query('d_gacha_list', config.gachaId)

    local bannerBig = UE.UObject.Load(config.bannerBig)
    -- self.MaterialInstance1:SetTextureParameterValue('Screen', bannerBig)
    for _, plane in pairs(self.TrainAdPlane) do
        plane.StaticMeshComponent:SetMaterial(0, bannerBig)
    end

    local bannerSmall = UE.UObject.Load(config.bannerSmall)
    self.MaterialInstance2:SetTextureParameterValue('Screen', bannerSmall)
    -- for _, plane in pairs(self.TrainAdPlane1) do
    --     plane.StaticMeshComponent:SetMaterial(1, bannerSmall)
    -- end

    local bIsUp = self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool or self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.WeaponPool
    if not bIsForce then
        self.Panel_Up:SetVisibility(bIsUp and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.Panel_Always:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.Panel_welfare:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end

    if not self.bIsAnimWaiting then
        --新手池
        local bIsNewPlayerPool = self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer
        self.Panel_One:SetVisibility(bIsNewPlayerPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        self.Image_Ten:SetVisibility(bIsNewPlayerPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        self.Text_Ten:SetVisibility(bIsNewPlayerPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        self.Text_FreeOne_1:SetVisibility(bIsNewPlayerPool and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        --刷新抽奖卷
        local image = self:GetGachaTicketImg(listConfig.ticket)
        if image then
            self.Image_One:SetBrushFromAtlasInterface(image)
            self.Image_Ten:SetBrushFromAtlasInterface(image)
        end
        if not bIsNewPlayerPool then
            --教学池
            local bIsStudyPool = self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Study
            if bIsStudyPool then
                self.Panel_One:SetVisibility(bIsStudyPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)

                self.Image_Ten:SetVisibility(not bIsStudyPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
                self.Text_Ten:SetVisibility(not bIsStudyPool and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
                self.Text_FreeOne_1:SetVisibility(not bIsStudyPool and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
            end
        end
    end
    self.Panel_Btn_Up:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    self.Panel_Result:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    self.Button_Choose:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)

    if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer then
        local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
        local allCount = 0 
        if gachaInfo and gachaInfo.gacha_pending_record_infos then
            allCount = #gachaInfo.gacha_pending_record_infos
        end 
        --额外刷新兑换按钮
        self.Panel_Result:SetVisibility(allCount > 0 and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
   

    local uiNamePre = ''
    if bIsUp then
        uiNamePre = 'UI_TrainStation_UpName' 
    elseif self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal then
        uiNamePre = 'UI_TrainStation_AlwaysName_'
    elseif self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer then
        uiNamePre = 'UI_TrainStation_welfareName_'
    end
    for i = 1, #config.upName do 
        local ui = self[uiNamePre .. i]
        if ui then
            ui.Text_Unlock:SetText(Database.L10n(config.upName[i]))
        end
    end
    local gachaTypeInfo = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(config.gachaId)
    --普通池免费
    if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal then
        local isGachaOneFree = GachaSystem:GetInstance():IsFreeForFirstGacha()
        self.Panel_OneTicket:SetVisibility(isGachaOneFree and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        self.Text_FreeOne:SetVisibility(not isGachaOneFree and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        self.Button_Choose:SetVisibility(gachaTypeInfo.choose_times == 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)

        --兑换奖励次数
        if gachaTypeInfo.choose_times == 0 then
            local paramsConfig1 = GachaSystem:GetInstance():GetGachaParamsById(1)
            local curTimes = math.min(gachaTypeInfo.total_times, paramsConfig1.value2)
            self.Text_Choose_Times:SetText((curTimes) .. '/' .. paramsConfig1.value2)
        end
    else
        self.Text_FreeOne:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    local upCount = gachaTypeInfo.no_up_times
    local hasCount = gachaTypeInfo.total_times --已经抽了的次数
    local allCount = listConfig.guaranteedTime --总共抽的次数
    if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal then
        self.Text_Desc:SetText(string.format(Database.L10n(432), allCount - upCount))
    elseif self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer then
        self.Text_Desc_1:SetText(string.format(Database.L10n(433), allCount - hasCount, allCount))
    elseif self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool then
        self.Text_Desc_2:SetText(string.format(Database.L10n(454), allCount - upCount))
    elseif self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.WeaponPool then
        self.Text_Desc_2:SetText(string.format(Database.L10n(455), allCount - upCount))
    end

    --主ui上的tab
    self.UI_TrainStation_Tab.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
    --活动名字
    self.UI_TrainStation_Tab.Text_Name:SetText(Database.L10n(config.gachaName))
    self.UI_TrainStation_Tab.Text_Name_ON:SetText(Database.L10n(config.gachaName))
    if config.bannerTab ~= '' then
        local bg_texture = UE.UObject.Load(config.bannerTab)
        if bg_texture then
            self.UI_TrainStation_Tab.Tab:SetBrushFromTexture(bg_texture)
        end
    end
    
    self.UI_TrainStation_Tab.Btn_Tab.OnClicked:Add(self, function()
        self:OnClicked_UI_MenuButtonEx()
    end)


    local server_time = PlayerSystem:GetInstance():GetServerTime()
    local endTime = UIUtils.ParseTimeStr(config.endTime)
    if server_time < endTime then
        local deltaTime = endTime - server_time
        local leftTime = os.date("*t", deltaTime)
        local leftTimeStr = string.format(Database.L10n(293), leftTime.day, leftTime.hour, leftTime.min)
        self.Text_Desc_4:SetText(leftTimeStr)
    else
        self.Text_Desc_4:SetText('')
    end
end

function M:CheckTick(poolId, bIsTenLottery)
    if self.bIsAnimWaiting then
        print('----bIsAnimWaiting')
        return false
    end
    --检测所有车厢是否已经播放完毕开门动画
    if not self:IsAllCabinOpened() then
        UIUtils.ShowNotify(self, Database.L10n(442))
        return false
    end

    --当前券的数量
    local config = Database.Query('d_gacha_list', poolId)
    if config then
        --常驻池免费判定
        if not self.bIsTenLottery and config.gachaType == UIUtils.EGachaPoolType.Normal then
            local isGachaOneFree = GachaSystem:GetInstance():IsFreeForFirstGacha()
            if isGachaOneFree then
                return true
            end
        end
        --票数判定
        if config.ticket and config.ticket > 0 then
            local ticketNum = UIUtils.GetItemCount(config.ticket)
            local needCount = bIsTenLottery and 10 or 1
            if ticketNum < needCount then
                -- UIUtils.ShowNotify(self, Database.L10n(434))
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

                local ui = gameInstance:AddUMG('UI_SwapTicket_C')
                if ui then
                    ui:RefreshUI(config.ticket == UIUtils.EGachaTicket.GachaTickLimit and 40001 or 40002, needCount - ticketNum)
                end
                print('----ticket not enough')
                return false
            end
        end
        --只判断新手池,次数判定
        if config.ticket and config.ticket == 0 then
            --10连
            if bIsTenLottery then
                if config.guaranteedTime and config.guaranteedTime > 0 then
                    local info = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(poolId)
                    if info and info.total_times >= config.guaranteedTime then
                        UIUtils.ShowNotify(self, Database.L10n(435))
                        return false
                    end
                end
            else --单抽,不能抽
                return true
            end
        end
    end
  
    return true
end

--添加自动播放
function M:ShowAutoOpenAllCabinOptions()
    if self.LastClickGachaTenTime then
        self.LastClickGachaTenTime = self.LastClickGachaTenTime - 0.5
    end
    
    self.AutoOpenAllCabin = false
    self.bShowOpenAll = true
    self.Panel_Open:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
end

function M:ShowPanelLottery(bShow)
    -- print('------ShowPanelLottery:' .. tostring(bShow))
    self.UI_TrainStation_Tab:SetVisibility(bShow and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.UI_TrainStation_Tab.Btn_Tab:SetVisibility(bShow and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.UI_MenuMissionStory:SetVisibility(bShow and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    if bShow then
        self.Panel_Lottery:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.bShowOpenAll = false
        self.Panel_Open:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        self.Panel_Lottery:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    
    self.Panel_Ten:SetVisibility(bShow and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    if bShow then
        local bIsUp = self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool or self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.WeaponPool
        self.Panel_Up:SetVisibility(bIsUp and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.Panel_Always:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        self.Panel_welfare:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    else
        self.Panel_Up:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_Always:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_welfare:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnMsg_SO_TrainCabin_Opened(itemIndex, bCanDing)
    -- print("--open:" .. tostring(itemIndex) .. ",bcanding:" .. tostring(bCanDing))
    if bCanDing then
        self:AddDingQueue(itemIndex)
    else
        if self:IsAllCabinOpened() then
            -- print("--all opened")
            self:ShowPanelLottery(true)
            UIManager:GetInstance():RemoveInteractOptionByObject(self)
            --请求领取奖励
            self:CheckDingQueue()
        end
    end
end

function M:OnMsg_Ding_Cancel(itemIndex)
    self:RemoveDingQueue(itemIndex)
end

function M:OnMsg_OpenAllCabin()
    self:OnClicked_Btn_Open()
end

-------------------------------------------------------
---ui event 
function M:OnClicked_Btn_Quit()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    self.ShowInteractOptions = true
    self.HideCursor = true
    UIManager:GetInstance().layers.bg:SetVisibility(UE.ESlateVisibility.Visible)
    UIManager:GetInstance().layers:SetRequireShowInteractOptions(true)
    UIManager:GetInstance():SetForceShowCursor(false)

    local InputUtils = require "_Game.Utils.Input.InputUtils"
    InputUtils.RemoveMappingContext(controller, InputAssets.IMC_UI_Cursor)
    

    self.SO_Train_UI:SetActorHiddenInGame(true)
    self.UI_TrainStation_Tab:SetRenderOpacity(1)
    self.UI_TrainStation_Tab:PlayAnimationForward(self.UI_TrainStation_Tab.vfxin)

    self.Panel_MenuButton:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.Hidden)
    -- self.Panel_Lottery:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

    -- self.Panel_Up:SetVisibility(UE.ESlateVisibility.Hidden)
    -- self.Panel_Always:SetVisibility(UE.ESlateVisibility.Hidden)
    -- self.Panel_welfare:SetVisibility(UE.ESlateVisibility.Hidden)

    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    local cameraManagerActor = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
    cameraManagerActor:StopAllCameraShakes()
    if self.CameraShake then
        self.CameraShake = nil
    end
    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local player = gameMode:BPI_GetPlayer()
    if player then
        playerController:Possess(player)
        -- playerController:SetViewTargetWithBlend(player, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
        -- player:EnableInput(playerController)
        --player:K2_SetActorLocation(self.PlayerInStationPos, false, nil, false)
        
        --player.CharacterMovement.GravityScale = self.LastGravityScale
        if not UE.UGameplayStatics.ObjectIsA(player, LoadClass('/Game/_Game/Blueprints/BuildingSystem/Blueprints/Interactables/BP_BuildActor.BP_BuildActor_C')) then
            player.CharacterMovement:SetActive(true, false)
        end
        player:SetActorEnableCollision(true)
        player:SetActorHiddenInGame(false)
        player.Mesh:SetEnableGravity(true)
    else
        print("---------no player")
    end
    self.IsPossessedChar = true

    self.UI_TrainStation_Tab:SetRenderOpacity(1)
    -- self.UI_TrainStation_Tab:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.UI_TrainStation_Tab.Btn_Tab:SetVisibility(UE.ESlateVisibility.Visible)
    self.UI_MenuMissionStory:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
end

function M:OnClicked_MenuButton()
    if self.bIsAnimWaiting or not self:IsAllCabinOpened() then return end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    gameInstance:AddUMG('UI_CityMenu')
end

function M:OnClicked_UI_MenuButtonEx()
    if not self.IsPossessedChar then
        -- self:OnClicked_UI_MenuButton()
        return 
    end
    if self.bIsAnimWaiting or not self:IsAllCabinOpened() then 
        print("----------->等带所有车门开")
        return 
    end
    if self.UI_TrainStation_Tab:IsPlayingAnimation() then 
        print('-----------tab 动效 未完毕')
        return 
    end

    self.UI_TrainStation_Tab:UnbindAllFromAnimationFinished(self.UI_TrainStation_Tab.vfxquit)
    self.UI_TrainStation_Tab:BindToAnimationFinished(self.UI_TrainStation_Tab.vfxquit, function ()
        self.UI_TrainStation_Tab:SetRenderOpacity(0)
        self.UI_TrainStation_Tab.Btn_Tab:SetVisibility(UE.ESlateVisibility.Hidden)
        print('-------->进入卡池列表')
        self:OnClicked_UI_MenuButton()
    end)
    self.UI_TrainStation_Tab:PlayAnimationForward(self.UI_TrainStation_Tab.vfxquit)
end

function M:OnClicked_UI_MenuButton()
    if self.bIsAnimWaiting or not self:IsAllCabinOpened() then return end

    self.UI_TrainStation_Tab:SetRenderOpacity(0)
    self.UI_TrainStation_Tab.Btn_Tab:SetVisibility(UE.ESlateVisibility.Hidden)


    self.Panel_MenuButton:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Panel_MainExit:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    -- self.Panel_Lottery:SetVisibility(UE.ESlateVisibility.Hidden)

    local bIsUp = self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool or self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.WeaponPool
    self.Panel_Up:SetVisibility(bIsUp and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Always:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Normal and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_welfare:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    self.Btn_Up:SetVisibility(self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.CharPool and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
    self.ShowInteractOptions = false
    self.HideCursor = false
    UIManager:GetInstance().layers.bg:SetVisibility(UE.ESlateVisibility.Hidden)
    UIManager:GetInstance().layers:SetRequireShowInteractOptions(false)
    UIManager:GetInstance():SetForceShowCursor(true)

    local InputUtils = require "_Game.Utils.Input.InputUtils"
    InputUtils.AddMappingContext(playerController, InputAssets.IMC_UI_Cursor)

    self.SO_Train_UI:SetActorHiddenInGame(false)
    self.SO_Train_UI:vfxin()
   

    local player = playerController:K2_GetPawn()
    if player then
        gameMode:BPI_SetPlayer(player)
        -- self.PlayerInStationPos = player:K2_GetActorLocation()
        local cameraArray = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACameraActor, 'TrainStationInitPos')
        if cameraArray:Length() > 0 then
            local camera = cameraArray:Get(1)
            if camera then
                playerController:SetViewTargetWithBlend(camera, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
            end
        end
       
        -- self.LastGravityScale = player.CharacterMovement.GravityScale
        -- player.CharacterMovement.GravityScale = 0
        player:SetActorEnableCollision(false)
        player:SetActorHiddenInGame(true)
        player.Mesh:SetEnableGravity(false)
        player.CharacterMovement:SetActive(false, false)
        -- playerController:UnPossess()
    end
    local cameraManagerActor = UE.UGameplayStatics.GetPlayerCameraManager(self, 0)
    self.CameraShake = cameraManagerActor:StartCameraShakeFromSource(LoadClass(self.ShakePath), nil)

    self.IsPossessedChar = false
    self.UI_MenuMissionStory:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnClicked_Back()
    print("------OnClicked_Back:" .. tostring( self.IsPossessedChar))
    if not self.IsPossessedChar then
        self:OnClicked_Btn_Quit()
    else
        self:OnClicked_MenuButton()
    end
end

function M:IA_Back()
    if not self.IsPossessedChar then
        self:OnClicked_Btn_Quit()
    else
        self:OnClicked_MenuButton()
    end
end

function M:IA_Menu()
    if self.IsPossessedChar then
        self:OnClicked_MenuButton()
    end
end

function M:OnClicked_Btn_OneLottery()
    self.bIsTenLottery = false
    if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.Study then 
        print('---------new player pool')
        return 
    end
    if self:CheckTick(self.SelectedTabUI.ID, self.bIsTenLottery) then
        if self.SelectedTabUI.Layer == UIUtils.EGachaPoolType.NewPlayer then
            self:OnClicked_Btn_Welfare()
            return
        end
        if not self.IsPossessedChar then
            self:OnClicked_Btn_Quit()
        end
        self.bIsAnimWaiting = true
        print('---onclick one :' .. tostring(self.bIsAnimWaiting))

        if self.IsCarIn then
            --播放一个关闭所有的车厢
            local duration = self:HideAllCabin()
            if duration > 0 then
                self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate({ self, self.PlayCarLeaveSequence }, duration, false)
            else
                self:PlayCarLeaveSequence()
            end
        else
            GachaSystem:GetInstance():ReqGachaCreate(self.SelectedTabUI.ID, self.bIsTenLottery and 10 or 1)
        end
        self:ShowAutoOpenAllCabinOptions()
        self:ShowPanelLottery(false)
    end
end

function M:OnClicked_Btn_TenLottery()
    self.bIsTenLottery = true
    if self:CheckTick(self.SelectedTabUI.ID, self.bIsTenLottery) then
       
        print('---onclick ten :' .. tostring(self.bIsAnimWaiting))

        --新手池弹框确认
        local config = Database.Query('d_gacha_list', self.SelectedTabUI.ID)
        if config then
            --常驻池免费判定
            if config.gachaType == UIUtils.EGachaPoolType.NewPlayer then
                local gachaTypeInfo = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(self.SelectedTabUI.ID)
                local upCount = gachaTypeInfo.no_up_times
                local hasCount = gachaTypeInfo.total_times --已经抽了的次数
                local allCount = config.guaranteedTime --总共抽的次数+

                UIUtils.ShowComNotice(string.format(Database.L10n(498), allCount - hasCount, allCount), self,
                    function() 
                        if not self.IsPossessedChar then
                            self:OnClicked_Btn_Quit()
                        end
                        self.bIsAnimWaiting = true

                        if self.IsCarIn then
                            local duration = self:HideAllCabin()
                            if duration > 0 then
                                self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate({ self, self.PlayCarLeaveSequence }, duration, false)
                            else
                                self:PlayCarLeaveSequence()
                            end
                        else
                            GachaSystem:GetInstance():ReqGachaCreate(self.SelectedTabUI.ID, self.bIsTenLottery and 10 or 1)
                        end
                        self:ShowAutoOpenAllCabinOptions()
                        self:ShowPanelLottery(false)
                    end,
                    function()
                        
                    end
                )
            else
                if not self.IsPossessedChar then
                    self:OnClicked_Btn_Quit()
                end
                self.bIsAnimWaiting = true
                
                if self.IsCarIn then
                    local duration = self:HideAllCabin()
                    if duration > 0 then
                        self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate({ self, self.PlayCarLeaveSequence }, duration, false)
                    else
                        self:PlayCarLeaveSequence()
                    end
                else
                    GachaSystem:GetInstance():ReqGachaCreate(self.SelectedTabUI.ID, self.bIsTenLottery and 10 or 1)
                end
                self:ShowAutoOpenAllCabinOptions()
                self:ShowPanelLottery(false)
            end
        end
    end
end

function M:OnClicked_Btn_Tab(ui)
    -- print('----clicked:' .. tostring(ui.ID))
    if self.SelectedTabUI == ui then 
        return
    else
        -- self.SelectedTabUI.Image_6:SetVisibility(UE.ESlateVisibility.Hidden)
        -- self.SelectedTabUI.Image_7:SetVisibility(UE.ESlateVisibility.Hidden)
        self.SelectedTabUI.Text_Name:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        -- self.SelectedTabUI.Text_Name_ON:SetVisibility(UE.ESlateVisibility.Hidden)
        self.SelectedTabUI.Panel_Main:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.SelectedTabUI:SetIsSelected(false)
        self.SelectedTabUI = ui
        self.LastSelectedTabIndex = ui.Index
        self.SelectedTabUI.Panel_Main:SetVisibility(UE.ESlateVisibility.Hidden)
        self.SelectedTabUI.Image_6:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.SelectedTabUI.Image_7:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.SelectedTabUI.Text_Name:SetVisibility(UE.ESlateVisibility.Hidden)
        self.SelectedTabUI.Text_Name_ON:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.SelectedTabUI:SetIsSelected(true)
        self:RefreshMainPanel(self.GachaConfigList[ui.Index])
    end
end

function M:IA_GachaTen()
    local now = PlayerSystem:GetInstance():GetServerTime()
    if not self.LastClickGachaTenTime then 
        self.LastClickGachaTenTime = now - 1
    end
    if now - self.LastClickGachaTenTime < 0.5 then
        print('------点击太快') 
        return 
    end
    self.LastClickGachaTenTime = now
    if not self.bShowOpenAll then
        self:OnClicked_Btn_TenLottery()
    else
        self:OnClicked_Btn_Open()
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Menu, UE.ETriggerEvent.Completed, M.IA_Menu)
InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)
InputUtils.RegisterUIAction(M, InputAssets.IA_GachaTab, UE.ETriggerEvent.Completed, M.OnClicked_UI_MenuButtonEx)
InputUtils.RegisterUIAction(M, InputAssets.IA_GachaOne, UE.ETriggerEvent.Completed, M.OnClicked_Btn_OneLottery)
InputUtils.RegisterUIAction(M, InputAssets.IA_GachaTen, UE.ETriggerEvent.Completed, M.IA_GachaTen)
InputUtils.RegisterMouseEvent(M)

function M:OnClicked_Btn_Detail()
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Window_Details')
    if ui then
        local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
        local typeInfo = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(self.SelectedTabUI.ID)
        ui:RefreshUI(self.SelectedTabUI.ID, gachaInfo, typeInfo)
    end
end

--兑换-->跳转商店
function M:OnClicked_Btn_Exchange()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9029) then
        local ui = gameInstance:GetUMG('UI_TopUp_Shop')
        if ui and ui.ShowExchange then
            ui:ShowExchange()
        end
    end
end

function M:FindGachaPoolId(poolId)
    local ret = {}
    local d_gacha_pool = require('ClientDatas.d_gacha_pool')
    for _, v in pairs(d_gacha_pool) do 
        if v.poolId == poolId then
            table.insert(ret, v)
        end
    end
    return ret
end

--角色试用
function M:OnClicked_Btn_Up()
    UIUtils.ShowNotify(self, Database.L10n(50500))
    do return end
    --打开角色试用面板
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_CharTrain')
    if ui then
        local config = Database.Query('d_gacha_list', self.SelectedTabUI.ID)
        if config and config.upPool > 0 then
            local poolConfigs = self:FindGachaPoolId(config.upPool)
            if #poolConfigs > 0 then
                local poolConfig = poolConfigs[1]
                local gachaItemConfig = Database.Query('d_gacha_item', poolConfig.gachaItemId)
                if gachaItemConfig and gachaItemConfig.itemid and gachaItemConfig.itemid > 0 then
                    local itemInfo = UIUtils.GetItemConfigById(gachaItemConfig.itemid)
                    if itemInfo and itemInfo.subParam[1] then
                        local charId = itemInfo.subParam[1]
                        if charId and charId > 0 then
                            ui:RefreshCharacterId(charId)
                        end
                    end
                end
            end
        end
    end
end

--接机结果
function M:OnClicked_Btn_Welfare()
    local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
    local allCount = 0 
    if gachaInfo and gachaInfo.gacha_pending_record_infos then
        allCount = #gachaInfo.gacha_pending_record_infos
    end 
    if allCount <= 0 then return end 
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Welfare_Result')
    if ui then
        ui:RefreshUI(self.SelectedTabUI.ID, gachaInfo)
    end
end

--自选奖励
function M:OnClicked_Btn_Always()
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Welfare_Reward')
    if ui then
        local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
        local typeInfo = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(self.SelectedTabUI.ID)
        ui:RefreshUI(self.SelectedTabUI.ID, gachaInfo, typeInfo)
    end
end

--开启所有门
function M:OnClicked_Btn_Open()
    self.bShowOpenAll = false
    self.Panel_Open:SetVisibility(UE.ESlateVisibility.Hidden)
    self.AutoOpenAllCabin = true
    if not self.bIsAnimWaiting then
        if not self:IsAllCabinOpened() then
            self:ShowAllCabin()
        end
    end
end

-------------------------------------------------------
---
function M:PlayCarLeaveSequence()
    -- print("---PlayCarLeaveSequence:" .. tostring(self.CurTrainCarIndex))
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar2 or self.TrainCar1
    carActor:PlayCarLeave()

    GachaSystem:GetInstance():ReqGachaCreate(self.SelectedTabUI.ID, self.bIsTenLottery and 10 or 1)
end

function M:PlaySequenceOnce(obj, callback)
    -- print("----leave:" .. tostring(UE.UKismetSystemLibrary.GetDisplayName(obj)))
    local levelSequence = self.CarLeaveSequence
    if not levelSequence or levelSequence:GetClass() ~= UE.ULevelSequence:StaticClass() then
        LOG_ERROR("===加载sequence错误!!!,path:" .. tostring(levelSequence))
        return 
    end
    -- levelSequence.SequenceFlags = levelSequence.SequenceFlags | UE.EMovieSceneSequenceFlags.BlockingEvaluation
    if not self.LevelSequenceActor then
        local LoopCount = UE.FMovieSceneSequenceLoopCount()
        LoopCount.Value = 0
        local Settings = UE.FMovieSceneSequencePlaybackSettings()
        Settings.LoopCount = LoopCount
        local _, sequenceActor = UE.ULevelSequencePlayer.CreateLevelSequencePlayer(self, levelSequence, Settings, nil)
        self.LevelSequenceActor = sequenceActor
        self.LevelSequenceActor:SetBindingByTag("MainObj", { obj }, false)
    else
        self.LevelSequenceActor.SequencePlayer:GoToEndAndStop()
        self.LevelSequenceActor:ResetBindings()
        self.LevelSequenceActor:SetSequence(levelSequence)
        self.LevelSequenceActor:SetBindingByTag("MainObj", { obj }, false)
    end
    if self.LevelSequenceActor and self.LevelSequenceActor.SequencePlayer then
        self.LevelSequenceActor.SequencePlayer.OnFinished:Clear()
        self.LevelSequenceActor.SequencePlayer.OnFinished:Add(self, function()
            if callback then
                callback(self)
            end
        end)
        self.LevelSequenceActor.SequencePlayer:Play()
    end
end

-------------------------------------------------------
---
function M:OnMsg_Gacha_Create(poolId)
    -- print('--->OnMsg_Gacha_Create:' .. tostring(poolId))
    -- print('-----------OnMsg_Gacha_Create:' .. tostring(poolId))
    local config = require('ClientDatas.d_gacha_list')[poolId]
    if config and config.gachaType == UIUtils.EGachaPoolType.NewPlayer then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:SaveIsGachaAllOpened(false)
    end

    self.IsCarIn = true
    local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(poolId)
    local record_infos = gachaInfo.gacha_pending_record_infos
    if table.count(record_infos) > 1 then
        table.sort(record_infos, function(a, b)
            if a.gacha_item_type ~= b.gacha_item_type then
                return a.gacha_item_rarity > b.gacha_item_rarity
            end
            if a.gacha_item_rarity ~= b.gacha_item_rarity then
                return a.gacha_item_rarity > b.gacha_item_rarity
            end
            return false
        end)
    end
    self.DingQueue = {}
    self:InitSoTrainInfo(poolId, record_infos)
    
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar1 or self.TrainCar2
    carActor:PlayCarArrival(function()
        self.bIsAnimWaiting = false
        -- print('--car end:' .. tostring(self.bIsAnimWaiting))
        self.CurTrainCarIndex = math.abs(self.CurTrainCarIndex - 1)
        if self.AutoOpenAllCabin then
            self:ShowAllCabin()
        end
    end)

    self:RefreshMainPanel(self.GachaConfigList[self.SelectedTabUI.Index], true)
end

function M:res_gacha_confirm(result, msgId, parsed_msg)
    -- print('--->res_gacha_confirm:' .. tostring(table.dump(parsed_msg, nil, 10)))
    if result == 0 then

    end
end

function M:OnMsg_GachaDing(poolId, gachaInfo)
    -- print('--->res_gacha_ding:' .. tostring(table.dump(gachaInfo, nil, 10)))
    local carActor = self.CurTrainCarIndex == 1 and self.TrainCar1 or self.TrainCar2
    for i = 1, 10 do 
        local cabin = carActor['SO_Train_Cabin' .. i]
        if cabin and cabin.ChildActor then
            local cabinActor = cabin.ChildActor
            if cabinActor.GachaId == poolId and 
                cabinActor.GachaItemInfo and cabinActor.GachaItemInfo.Item_Index == gachaInfo.Item_Index then
                cabinActor:SetGachaItemInfo(poolId, gachaInfo)
                cabin.ChildActor:ReplayStart(poolId, gachaInfo)
                break
            end
        end
    end
       
    self:RemoveDingQueue(gachaInfo.Item_Index, true)
end

function M:res_gacha_choose_card(result, msgId, parsed_msg)
    if result == 0 then
        self.Button_Choose:SetVisibility(UE.ESlateVisibility.Collapsed)
        --关闭自选ui
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveUMG('UI_Welfare_Reward')
        --弹领取成功
        UIUtils.ShowNotify(self, '领取成功') --Database.L10n()
    end
end

function M:OnLoadCharacterSystem(bStart)
    --车模型隐藏
    if self.TrainCar1 then
        self.TrainCar1:SetActorHiddenInGame(bStart, false)
    end
    if self.TrainCar2 then
        self.TrainCar2:SetActorHiddenInGame(bStart, false)
    end
end

-------------------------------------------------------
--- 车厢
function M:InitSoTrainInfo(gachaId, gacha_info)
    -- print("---InitSoTrainInfo:" .. tostring(self.CurTrainCarIndex))
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar1 or self.TrainCar2
    if carActor then
        local maxRarity = 4
        for i = 1, 10 do 
            local cabin = carActor['SO_Train_Cabin' .. i]
            if cabin then
                local itemInfo = gacha_info[i]
                if itemInfo then
                    local curRarity = itemInfo.gacha_item_rarity
                    maxRarity = curRarity > maxRarity and curRarity or maxRarity
                    -- print("--so_train:" .. tostring(i) .. ",gachaId:" .. tostring(gachaId) .. ",item_index:" .. tostring(itemInfo.Item_Index) .. ',bcanding:' .. tostring(itemInfo.bCanDing))
                    cabin.ChildActor:SetGachaItemInfo(gachaId, itemInfo)
                else
                    -- print("--so_train:" .. tostring(i) .. ",gachaId:" .. tostring(gachaId) .. ",item_index:" .. tostring(nil))
                    cabin.ChildActor:SetGachaItemInfo(gachaId, nil)
                end
            end
        end
        carActor:SetColor(maxRarity - 3)
    end
end

function M:IsAllCabinOpened(isNotPlayAnimation)
    -- print("---IsAllCabinOpened:" .. tostring(self.CurTrainCarIndex) .. ',car:' .. tostring(self.CurTrainCarIndex == 0 and 'car2' or 'car1'))
    local allCarBinCont = 0
    local allOpenCount = 0
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar2 or self.TrainCar1
    if carActor then
        for i = 1, 10 do 
            local cabin = carActor['SO_Train_Cabin' .. i]
            if cabin and cabin.ChildActor then
                if cabin.ChildActor.GachaItemInfo then
                    allCarBinCont = allCarBinCont + 1
                    -- print("----isopend:" .. tostring(cabin.ChildActor.bIsOpened) .. ",playAni:" .. tostring(cabin.ChildActor.bIsPlayAnimation))
                    if cabin.ChildActor.bIsOpened and not cabin.ChildActor.bIsPlayAnimation then
                        allOpenCount = allOpenCount + 1
                    end
                end
            end
        end
    end
    return allOpenCount == allCarBinCont
end

function M:ShowAllCabin()
    -- print("---ShowAllCabin:" .. tostring(self.CurTrainCarIndex) .. ',car:' .. tostring(self.CurTrainCarIndex == 0 and 'car2' or 'car1'))
    local duration = 0.05
    local allOpened = 0
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar2 or self.TrainCar1
    if carActor then
        for i = 1, 10 do 
            local cabin = carActor['SO_Train_Cabin' .. i]
            if cabin and cabin.ChildActor and cabin.ChildActor.GachaItemInfo and not cabin.ChildActor.bIsOpened and not cabin.ChildActor.bIsPlayAnimation then
                cabin.ChildActor:OpenAnimStart(i * duration)
                allOpened = allOpened + 1
            end
        end
    end
    return allOpened * duration
end

function M:HideAllCabin()
    -- print("---HideAllCabin:" .. tostring(self.CurTrainCarIndex)  .. ',car:' .. tostring(self.CurTrainCarIndex == 0 and 'car2' or 'car1'))
    local duration = 0.05
    local allOpened = 0
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar2 or self.TrainCar1
    if carActor then
        for i = 1, 10 do 
            local cabin = carActor['SO_Train_Cabin' .. i]
            if cabin and cabin.ChildActor and cabin.ChildActor.GachaItemInfo then
                cabin.ChildActor:OpenAnimEnd(i * duration)
                allOpened = allOpened + 1
            end
        end
    end
    return allOpened * duration
end

function M:GetCabinActor(index)
    local carActor = self.CurTrainCarIndex == 0 and self.TrainCar2 or self.TrainCar1
    if carActor then
        for i = 1, 10 do 
            local cabin = carActor['SO_Train_Cabin' .. i]
            if cabin and cabin.ChildActor and cabin.ChildActor.GachaItemInfo and cabin.ChildActor.GachaItemInfo.Item_Index == index then
                return cabin.ChildActor
            end
        end
    end
    return nil
end

-------------------------------------------------------
--- 叮的逻辑
function M:AddDingQueue(itemIndex)
    table.insert(self.DingQueue, itemIndex)
    self:CheckDingQueue()
end

function M:RemoveDingQueue(itemIndex, ignoreCheck)
    for i = #self.DingQueue, 1, -1 do
        if self.DingQueue[i] == itemIndex then
            table.remove(self.DingQueue, i)
            break
        end
    end
    -- print("-------removeDingQueue" .. tostring(table.dump(self.DingQueue, nil, 10)))
    if not ignoreCheck then
        self:CheckDingQueue()
    end
end

function M:CheckDingQueue()
    -- print("----------checkDingQueue:" .. tostring(table.dump(self.DingQueue, nil, 10)))
    if self.DingQueue and #self.DingQueue > 0 then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local ui = gameInstance:GetUMG('UI_Welfare_Ding')
        if not ui then
            self:ShowDingUI()
        end
    else
        if self:IsAllCabinOpened() then
            local gachaInfo = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
            if gachaInfo and gachaInfo.gacha_pending_record_infos and table.count(gachaInfo.gacha_pending_record_infos) > 0 then
                -- print("----------gachaInfo:" .. tostring(table.dump(gachaInfo, nil, 10)))
                local hasCanDing = false
                for _, v in pairs(gachaInfo.gacha_pending_record_infos) do
                    if v.bCanDing then
                        hasCanDing = true
                        break 
                    end
                end
                if not hasCanDing then
                    -- print("----------ReqGachaConfirm:" .. tostring(hasCanDing))
                    local config = require('ClientDatas.d_gacha_list')[self.SelectedTabUI.ID]
                    if config then
                        if config.gachaType == UIUtils.EGachaPoolType.NewPlayer then
                            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                            gameInstance:SaveIsGachaAllOpened(true)
                        else
                            GachaSystem:GetInstance():ReqGachaConfirm(self.SelectedTabUI.ID, table.count(gachaInfo.gacha_pending_record_infos))
                        end
                    end
                end
            end
        end
    end
end

function M:ShowDingUI()
    local dingItemIndex = self.DingQueue[1]
    local gachaInfo = nil
    local gachaList = GachaSystem:GetInstance():GetGachaInfoByPoolId(self.SelectedTabUI.ID)
    if gachaList and gachaList.gacha_pending_record_infos then
        for _, v in pairs(gachaList.gacha_pending_record_infos) do
            if v.Item_Index == dingItemIndex then
                gachaInfo = v
                break
            end
        end
    end
    if not gachaInfo then
        -- LOG_ERROR('----->ding:' .. tostring(dingItemIndex) .. ",list:" .. tostring(table.dump(gachaList and gachaList.gacha_pending_record_infos or {}, nil, 10)))
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:HideAllUI()
    local ui = gameInstance:AddUMG('UI_Welfare_Ding')
    local typeInfo = GachaSystem:GetInstance():GetGachaTypeInfoByPoolId(self.SelectedTabUI.ID)
    local cabinActor = self:GetCabinActor(dingItemIndex)
    ui:RefreshUI(self.SelectedTabUI.ID, gachaInfo, typeInfo, cabinActor)
end

return M
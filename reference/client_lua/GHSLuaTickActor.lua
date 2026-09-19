require "UnLua"
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local NoticeController = require("Module.Notice.NoticeController")
local QuestSystem = require "Module.Quest.QuestSystem"
local MallSystem = require "Module.ShopSystem.MallSystem"

local M = Class()

function M:ReceiveBeginPlay()
    self.Overridden.ReceiveBeginPlay(self)
    self.LastEnterBackTime = os.time()
    local trans = UE.UKismetMathLibrary.MakeTransform(
        UE.FVector(0, 0, 0),
        UE.FRotator(0, 0, 0),
        UE.FVector(1, 1, 1))
    self.ApplicationLifecycleComp = self:AddComponentByClass(UE.UApplicationLifecycleComponent, false, trans, false)
    if UE.UGHSFunctionLibrary.PreventSleep then
        UE.UGHSFunctionLibrary.PreventSleep()
    end
    if self.ApplicationLifecycleComp then
        self.ApplicationLifecycleComp.ApplicationWillEnterBackgroundDelegate = { self, self.OnAppWillEnterBackground }
        self.ApplicationLifecycleComp.ApplicationHasEnteredForegroundDelegate = { self, self.OnAppHasEnteredForeground }
    end

    local widgets = self:K2_GetComponentsByClass(UE.UGHSLuaTickComponent)
    local widget_num = widgets:Length()
    for i = 1, widget_num do
        widgets[i]:SetTickableWhenPaused(true)
    end

    self:SetTickableWhenPaused(true)
end

function M:OnAppWillEnterBackground()
    print("===enterback")
    --记录当前时间
    self.LastEnterBackTime = os.time()
end

function M:OnAppHasEnteredForeground()
    print("===enterforeground")
    print("===记录当前时间")
    local pastTime = os.time() - self.LastEnterBackTime
    MessageManager:GetInstance():Broadcast("OnAppHasEnteredForeground", pastTime)
end

function M:OnUpdate(DeltaTime, UnscaledDeltaTime)
    Client.update(DeltaTime)
    NoticeController:GetInstance():Update(DeltaTime)
    QuestSystem:GetInstance():CheckQuest(DeltaTime)
    MallSystem:GetInstance():CheckMonthCard(DeltaTime)
    Update(DeltaTime, UnscaledDeltaTime)
end

function M:OnFixedUpdate(DeltaTime)
    FixedUpdate(DeltaTime)
end

function M:OnLateUpdate(DeltaTime)
    LateUpdate(DeltaTime)
end

return M

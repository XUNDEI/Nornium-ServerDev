---@type SO_PickUpItem_C
local M = UnLua.Class()

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local PlayerSystem = require('Module.Player.PlayerSystem')

function M:ReceiveBeginPlay()
    self:Update()
    self.SphereInteraction.OnComponentBeginOverlap:Add(self, self.OnInteractionBeginOverlap)
    self.SphereInteraction.OnComponentEndOverlap:Add(self, self.OnInteractionEndOverlap)
end

function M:ReceiveEndPlay()
    if self.DoDelayTimerHandler then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self.DoDelayTimerHandler)
        self.DoDelayTimerHandler = nil
    end
end

function M:Update()
    if self.DoDelayTimerHandler then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self.DoDelayTimerHandler)
        self.DoDelayTimerHandler = nil
    end
    local config = Database.Query("d_com_picking", self.ConfigId)
    if not config then
        LOG_WARN(self.ConfigId, "not exist!")
        return
    end
    self.OptionName = config.txtId == 0 and 265 or config.txtId

    local pickInfo = PlayerSystem:GetInstance():GetPickInfo(self.ConfigId)
    local isPicked = pickInfo and pickInfo.picking_seconds > 0
    if isPicked then --已经拾取过了
        if config.type == 1 then --唯一类型
            self:SetActorEnableCollision(false)
            self:SetActorHiddenInGame(config.model == 1)
        else--刷新类型
            local newTime = UIUtils.get_days_refresh(pickInfo.picking_seconds, config.monthRefresh)
            --print("----pick:" .. tostring(self.ConfigId) .. ",newTime:" .. tostring(newTime) .. ",os.time():" .. tostring(os.time()))
            local server_time = PlayerSystem:GetInstance():GetServerTime()
            if newTime > 0 and server_time > newTime then --到刷新时间重新刷新
                self:SetActorEnableCollision(true)
                self:SetActorHiddenInGame(false)
            else --还没到刷新时间
                self:SetActorEnableCollision(false)
                self:SetActorHiddenInGame(config.model == 1)
              
                --剩余刷新时间
                local leftTime = newTime - server_time
                --print("---lefttime:" .. tostring(leftTime))
                if newTime > 0 and leftTime > 0 then
                    self.DoDelayTimerHandler = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
                        {self, self.Update}, 
                        leftTime, 
                        false
                    )
                end
            end
        end
    else
        self:SetActorEnableCollision(true)
        self:SetActorHiddenInGame(false)
    end
end


function M:OnInteractionBeginOverlap(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                UIManager:GetInstance():ClearInteractOption()
                UIManager:GetInstance():AddInteractOption(self, self.OptionName, function()
                    self:OnInteract()
                end)
            end
        end
    end
end

function M:OnInteractionEndOverlap(OverlappedComponent, OtherActor, OtherComp, OtherBodyIndex, bFromSweep, SweepResult)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    if playerController then
        local player = playerController:K2_GetPawn()
        if player then
            if player == OtherActor then
                UIManager:GetInstance():RemoveInteractOptionByObject(self)
            end
        end
    end
end

function M:OnInteract()
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    PlayerSystem:GetInstance():ReqPicking(self.ConfigId, self)
end

return M

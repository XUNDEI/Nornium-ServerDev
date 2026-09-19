require "UnLua"
require "Common.TableUtil"

local Database = require("_Game.Utils.Database")
local GachaSystem = require('Module.Gacha.GachaSystem')
local UIUtils = require('_Game.Utils.UIUtils')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Welfare_Ding_C
local M = Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:Construct()
    self:InitData()
    self:InitUI()
    
end

function M:Destruct()
    self.ShowInteractOptions = true
    self.HideCursor = true
end


function M:InitData()
    self.bIsReqConfirm = false
end

function M:InitUI()
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Confirm.OnGHSClicked:Add(self, self.OnClicked_Btn_Confirm)

    self.ShowInteractOptions = false
    self.HideCursor = false
end

function M:RefreshUI(gachaId, gachaInfo, gachaTypeInfo, cabinActor)
    -- local gameMode = UE.UGameplayStatics.GetGameMode(self)
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    pc:SetViewTargetWithBlend(cabinActor, 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)

    -- print('---------gachaId:' .. tostring(gachaId))
    -- print('---------gachaInfo:' .. tostring(table.dump(gachaInfo, nil, 10)))
    self.GachaId = gachaId
    self.GachaInfo = gachaInfo

    local listConfig = Database.Query('d_gacha_list', gachaId)
    if listConfig then
        local upCount = gachaTypeInfo.no_up_times
        local allCount = listConfig.guaranteedTime --总共抽的次数
        -- self.Text_Desc:SetText(string.format(Database.L10n(432), allCount - upCount))
    end
end

-------------------------------------------------------
--- UI Event
function M:OnClicked_Btn_Close()
    UIUtils.ShowComNotice(Database.L10n(478)
    , self
    , function()
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        UIManager:GetInstance():RemoveUI(self)
        local ui = gameInstance:GetUMG('UI_TrainStation')
        if ui then
            ui:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc:SetViewTargetWithBlend(gameMode:BPI_GetPlayer(), 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)

        GachaSystem:GetInstance():OnDingCancel(self.GachaId, self.GachaInfo.Item_Index)
        MessageManager:GetInstance():Broadcast('OnMsg_Ding_Cancel', self.GachaInfo.Item_Index)
    end
    , function()
    end)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)

function M:OnClicked_Btn_Confirm()
    if self.bIsReqConfirm then return end
    self.bIsReqConfirm = true
    self:vfx_Confirm1()
    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.5)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_ScreenFade:FadeIn(false)
        UE.UKismetSystemLibrary.Delay(self, 0.3)
        local gameMode = UE.UGameplayStatics.GetGameMode(self)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc:SetViewTargetWithBlend(gameMode:BPI_GetPlayer(), 0, UE.EViewTargetBlendFunction.VTBlend_Linear, 0, false)
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveTopUI(true)
        GachaSystem:GetInstance():ReqGachaDing(self.GachaId, self.GachaInfo.Item_Index)
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_ScreenFade:FadeOut(false)
    end))
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Confirm)

return M

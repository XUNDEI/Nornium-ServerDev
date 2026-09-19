
local Database = require('_Game.Utils.Database')
local d_com_tutorial = require('ClientDatas.d_com_tutorial')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_tutorial_C
local M = UnLua.Class()

M.TutorialEnd = "UI_Tutorial_C.TutorialEnd"

M.HideCursor = false
M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
}

function M:IA_Back()
    LOG_INFO("back")
    self.Btn_Sure.OnClicked:Broadcast()
end

function M:IA_Confirm()
    LOG_INFO("confirm")
    self.Btn_Sure.OnClicked:Broadcast()
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)
InputUtils.RegisterUIAction(M, InputAssets.IA_Confirm, UE.ETriggerEvent.Completed, M.IA_Confirm)

function M:Construct()
    self.Btn_Sure.OnClicked:Add(self, self.OnClicked_Btn_Sure)
end

function M:Destruct()
end

function M:InitUI(tutorialId, bPauseGame)
    self.id = tutorialId
    self.bPauseGame = bPauseGame
    if pc and pc.K2_GetPawn then
        local player = pc:K2_GetPawn()
        if player and player.CancelSkill2 then
            player:CancelSkill2()
        end
    end

    if self.bPauseGame then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
        UE.UGameplayStatics.SetGamePaused(self, true)
        -- UE.UGameplayStatics.SetGlobalTimeDilation(self, 0)
    end

    -- local gameMode = UE.UGameplayStatics.GetGameMode(self)
    -- if gameMode and gameMode.FightLevel and gameMode.FightLevel.BGM then
    --     gameMode.FightLevel.BGM:SetPaused(false)
    -- end

    self:PlayAnimationForward(self.vfxIn, 1, false)
    
    self:RefreshUI(tutorialId)
end

function M:RefreshUI(tutorialId)
    self.tutorialId = tutorialId 
    -- 读取配置
    local config = d_com_tutorial[tutorialId]
    if not config then
        LOG_ERROR('===>>d_com_tutorial 未找到id:' .. tostring(tutorialId))
        return
    end

    self.Text_Title:SetText(Database.L10n(config.title))
    self.Text_Content:SetText(Database.L10n(config.text))

    if config.chart then
        local icon = LoadObject(config.chart)
        if icon then
            --self.Img_Chart:SetBrushFromAtlasInterface(icon)
            self.Img_Chart:SetBrushFromTexture(icon)
        end
    end
end

function M:PlayNext()
    if self.tutorialId and self.tutorialId > 0 then
        local config = d_com_tutorial[self.tutorialId]
        if config then
            if config.next and config.next > 0 then
                self:RefreshUI(config.next)
                return true
            end
        end
    end
    return false
end

function M:Close()
    if self.bPauseGame then
        UE.UGameplayStatics.SetGamePaused(self, false)
        -- UE.UGameplayStatics.SetGlobalTimeDilation(self, 1)
    end
    -- local gameMode = UE.UGameplayStatics.GetGameMode(self)
    -- if gameMode and gameMode.FightLevel and gameMode.FightLevel.BGM then
    --     gameMode.FightLevel.BGM:SetPaused(false)
    -- end
    if self.EventOnEnd then
        self.EventOnEnd:Broadcast()
    end
    UIManager:GetInstance():RemoveUI(self)
    MessageManager:GetInstance():Broadcast("Finished_Tutorial")
    MessageManager:GetInstance():Broadcast(M.TutorialEnd, self.id, 2)
end

function M:OnAnimationFinished(animation)
    if animation == self.vfxExit then
        self:Close()
    end
end

function M:OnClicked_Btn_Sure()
    if self:PlayNext() then return UE.UWidgetBlueprintLibrary.Handled() end
    self:PlayAnimationForward(self.vfxExit, 1, false)
    return UE.UWidgetBlueprintLibrary.Handled()
end

return M


local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local SrpgController = require("Module.Srpg.SrpgController")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Fight_C
local M = UnLua.Class()

M.HideCursor = true
M.EnableMove = true
M.InputMappingContexts = {
}

function M:Pause()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG('UI_PlayerLevelUp')
    UE.UGameplayStatics.SetGamePaused(self, true)
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(241),
        confirm = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            local gameMode = UE.UGameplayStatics.GetGameMode(self)
            gameMode:GameOver()
        end,
        cancel = function()
            if not UE.UKismetSystemLibrary.IsValid(self) then return end
            UE.UGameplayStatics.SetGamePaused(self, false)
        end,
        showCancel = true,
    })
end

function M:Construct()
    self.Overridden.Construct(self)
    self:InitUI()
    self:InitData()
end

function M:Destruct()
end

function M:InitUI()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.bIsChallenge = gameInstance.fightType == gameInstance.FIGHT_STATE.ChallengeCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or 
        gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy
    --self.UI_ChallegeFight:SetVisibility(self.bIsChallenge and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.UI_ChallegeFight:SetRenderOpacity(0)

    local boatEnergy = SrpgController:GetInstance():GetBoatEnergy() or 0
    self.bIsDaily = gameInstance.fightType == gameInstance.FIGHT_STATE.DailyCopy
    local show = (boatEnergy > 0) and (not self.bIsChallenge and not self.bIsDaily)
    self.boatskill:SetVisibility(show and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    self.UI_FightMenuButton.OnClicked:Add(self, self.Pause)
    self:RefreshRoleTrial()
end

function M:InitData()
    self.CachedStar = {}
    if self.bIsChallenge then
        self.InitWaveIndex = 1

        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        local challengeLevelId = gameInstance.fightMsg.fight_level_id
        self.FightConfig = Database.Query('d_levels_challenge', challengeLevelId)
       
        for i = 1, 3 do
            local ui = self.UI_ChallegeFight.VBox_Target:GetChildAt(i - 1)
            if ui then
                ui:SetRenderOpacity(0)
            end
        end
    end
end

function M:Tick(MyGeometry, Delta)
    self.Overridden.Tick(self, MyGeometry, Delta)
    if self.bEndFighting then return end
    if not self.LastTime then self.LastTime = 0 end
    if not self.AllTime then self.AllTime = 0 end
    self.AllTime = self.AllTime + Delta
    if self.AllTime - self.LastTime >= 1 then
        self.LastTime = self.AllTime
        if self.bIsChallenge and self.FightConfig then
            local index = self.InitWaveIndex
            local target = self.FightConfig.targetFight[index]
            if target and target > 0 then
                local gameMode = UE.UGameplayStatics.GetGameMode(self)
                local fightLevel = gameMode.FightLevel
                local ui = self.UI_ChallegeFight.VBox_Target:GetChildAt(0)
                local bStar, info = fightLevel:GetStarIndex(index - 1)
                -- print('----index:' .. tostring(index - 1) .. ",bStart:" .. tostring(bStar))
                if ui and target then
                    self.UI_ChallegeFight:SetRenderOpacity(1)
                    ui:SetRenderOpacity(1)
                    local curValue = info:Length() >= 1 and info[1] or ''
                    local maxValue = info:Length() >= 2 and info[2] or ''
                    local targetString = Database.L10n(target)
                    local textStr = ''
                    local count = 0
                    for _ in string.gmatch(targetString, '%%s') do
                        count = count + 1
                    end
                    if count == 3 then
                        textStr = string.format(targetString, maxValue, curValue, maxValue)
                    elseif count <= 2 then
                        textStr = string.format(targetString, curValue, maxValue)
                    end
                    
                    ui.Txt_Black:SetText(textStr)
                    ui.Txt_White:SetText(textStr)
                    ui.Txt_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
                    -- ui.Img_White:SetVisibility(bStar and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
                    --播放动画
                    if self.CachedStar[index] == nil then
                        print('------------a')
                        self.CachedStar[index] = bStar
                        if bStar then
                            self.InitWaveIndex = self.InitWaveIndex + 1
                        else
                            ui:PlayAnimation(ui.Normal)
                        end
                    elseif self.CachedStar[index] ~= bStar then
                        print('------------b')
                        if bStar then
                            ui:PlayAnimation(ui.success)
    
                            self.InitWaveIndex = self.InitWaveIndex + 1
                        else
                            ui:PlayAnimation(ui.fail)
                        end
                        self.CachedStar[index] = bStar
                    end
                end
            end
        end 
    end

    --检测角色变量
    if self.PlayerInFight then
        local tag = UE.UGHSFunctionLibrary.RequestGameplayTag("Buff.CharTransform", false)
        local tagContainer = UE.UBlueprintGameplayTagLibrary.MakeGameplayTagContainerFromTag(tag)
        local curHasBuffState = self.PlayerInFight:HasBuff(tagContainer)
        if self.lastBuff ~= curHasBuffState then
            self.lastBuff = curHasBuffState
            ---修改按钮
            self:ChangeSkillIcon(self.CharacterIdInFight, curHasBuffState)
        end
    end
end

function M:RefreshRoleTrial()
    --设置试用角色提示UI
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local hasTrainChar = false
    if gameInstance.fightType == gameInstance.FIGHT_STATE.CharTrainCopy or gameInstance.fightType == gameInstance.FIGHT_STATE.TempCopy then
        local teamList = gameInstance:LoadTeamList()
        if not teamList then
            teamList = gameInstance:CreateTeamList()
        end
        for i = 1, 3 do
            local trainCharId = teamList.TrainPos:Get(i)
            if trainCharId > 1 then 
                print('--------->试炼角色' .. trainCharId)
                hasTrainChar = true
                break
            end
        end
    end

    if hasTrainChar then
        self.RoleTrial:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    else
        self.RoleTrial:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnElement(tag)
   
    local strArray = string.split(tag, '.')
    if #strArray >= 2 then
        local ElementType = tonumber(strArray[2])
        local obj = LoadObject(string.format('/Game/_Game/TP_New/Element_res/Frames/element_%d_l_png.element_%d_l_png', ElementType, ElementType))
        if obj then
            self.Image_Element:SetBrushFromAtlasInterface(obj)
        end
    end
end

function M:UpdateCharacterSkill(player, boat)
    self.Overridden.UpdateCharacterSkill(self, player, boat)
    if player then
        print('----------当前角色:' .. tostring(player:GetClass():GetName()))
        self.PlayerInFight = player
        local d_character = require "ClientDatas.d_character"
        local class_name = player:GetClass():GetName()
        class_name = string.sub(class_name, 1, -3)
        local character_id, character_data
        for i, v in pairs(d_character) do
            if string.endswith(v.fightModelPath, class_name) then
                character_id = i
                character_data = v
                break
            end
        end
        if character_id == nil or not character_data then
            LOG_ERROR(class_name .. "::UpdateCharacterSkill " .. "id is nil")
            return
        end
        self.CharacterIdInFight = character_id
        self:ChangeSkillIcon(character_id, false)
    end
end

function M:ChangeSkillIcon(character_id, isChangeBody)
    --获取角色的所有主动技能
    local d_skill = require("ClientDatas.d_skill")
    for _, v in pairs(d_skill) do
        if v.belongCharId == character_id then
            if v.skillType == 1 and v.subType < 5 then --角色技能
                -- 普通攻击:1
                -- 技能1:2
                -- 闪避:3
                -- 大招:4
                local icon = v.fightIcon
                if isChangeBody then
                    icon = v.fightIcon2
                end
                local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", icon, icon)
                local iconObj = LoadObject(iconPath)
                if v.subType == 1 then
                    if iconObj then
                        self.UI_SkillButton1.ImageIcon:SetBrushFromAtlasInterface(iconObj)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.UI_SkillButton1.ImageIcon):SetPosition(self.UI_SkillButton1.ImageIconPos)
                    end
                elseif v.subType == 2 then
                    if iconObj then
                        self.UI_SkillButton2.ImageIcon:SetBrushFromAtlasInterface(iconObj)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.UI_SkillButton2.ImageIcon):SetPosition(self.UI_SkillButton2.ImageIconPos)
                    end
                elseif v.subType == 3 then
                    if iconObj then
                        self.UI_SkillButton4.ImageIcon:SetBrushFromAtlasInterface(iconObj)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.UI_SkillButton4.ImageIcon):SetPosition(self.UI_SkillButton4.ImageIconPos)
                    end
                elseif v.subType == 4 then
                    if iconObj then
                        self.UI_SkillButton3.ImageIcon:SetBrushFromAtlasInterface(iconObj)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.UI_SkillButton3.ImageIcon):SetPosition(self.UI_SkillButton3.ImageIconPos)
                    end
                end
            end
        end
    end
end

return M

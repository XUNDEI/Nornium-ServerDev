local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local MessageManager = require "Framework.Updater.MessageManager"

---@type UI_Panel_Equip_C
local M = UnLua.Class()

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Talent_Active_Success", self)
end

function M:Destruct()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG('UI_Sub_TalentDetail')
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Talent_Active_Success", self)
end

function M:InitData()

end

function M:OnMsg_Req_Character_Talent_Active_Success()
    --获取所有天赋数据
    self.TalentInfos = UIUtils.GetTalentInfo(self.CharInfo.character_id)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --self:RefreshUI(self.BackUI, self.CharInfo)
    if self.lastBtnTalent then
        self.lastBtnTalent:PlayAnim()
    end
   
    if self.lastTalentConfig then
        local config = self.lastTalentConfig

        --刷新下个关联节点的状态
        local allChild = self:GetAllChildConfigByHole(config.hole, self.CharInfo.character_id)
        for _, talentConfig in pairs(allChild) do
            local talentPointActor = self.AllTalentPoint[talentConfig.hole]
            if talentPointActor then
                local talentInfo = self.TalentInfos[talentConfig.id]
                if talentInfo then
                    if talentInfo.isActived then
                        talentPointActor:PlayActive()
                    else
                        if talentInfo.isPreActived then
                            talentPointActor:PlayNormal(false)
                        else
                            talentPointActor:PlayDeactive()
                        end
                    end        
                end
            end
        end

        local tag = ""
        if config.frontHole < config.hole then
            tag = config.frontHole .. "-" .. config.hole
        else
            tag = config.hole .. "-" .. config.frontHole
        end

        if #self.AllTalentLine > 0 then
            for i = 1, #self.AllTalentLine do 
                local line = self.AllTalentLine[i]
                if line and line.HoleTag then
                    local bFindTag = false
                    for i = 1, line.HoleTag:Length() do 
                        local lineTag = line.HoleTag:Get(i)
                        if lineTag == tag then
                            bFindTag = true
                            break
                        end
                    end
                    if bFindTag then
                        print('----------激活线特效:' .. tostring(i))
                        line:PlayAnimationForward(line.lian, 1.0, false)
                    end
                end
            end
        end
    end
end

function M:InitUI()
    self.AllTalentPoint = {}
    
    self.AllTalentLine = {}
    for i = 1, 23 do 
        self.AllTalentPoint[i] = self['WBP_Point_' .. tostring(i)]
        self.AllTalentLine[i] = self['WBP_Line_' .. tostring(i)]
    end
end

function M:RefreshUI(backUI, charInfo, bInit)
    self.TabIsSelected = true
    self.BackUI = backUI
    self.CharInfo = charInfo
    --print("===>CharInfo:" .. tostring(table.dump(self.CharInfo or {}, false, 10)))
    if #self.AllTalentLine > 0 then
        for i = 1, #self.AllTalentLine do 
            local line = self.AllTalentLine[i]
            if line then
                if bInit then
                    line:deActive()
                end
            end
        end
    end
    --获取所有天赋数据
    self.TalentInfos = UIUtils.GetTalentInfo(self.CharInfo.character_id)
    --print("===>TalentInfos:" .. tostring(table.dump(self.TalentInfos or {}, false, 10)))
    for talentId, info in pairs(self.TalentInfos) do
        local config = UIUtils.GetTalentConfig(talentId, self.CharInfo.character_id)
        local talentPointActor = self.AllTalentPoint[config.hole]
        if talentPointActor then
            talentPointActor.Btn_Talent.OnGHSClicked:Clear()
            talentPointActor.Btn_Talent.OnGHSClicked:Add(self, function() 
                self:OnClicked_Btn_Talent(talentPointActor)
            end)
            local talentConfig = UIUtils.GetTalentConfig(talentId, self.CharInfo.character_id)
            local isFull, tips, exInfo = UIUtils.GetTalentUnlock(self.CharInfo.character_id, talentConfig.openNeed, talentConfig.openNeedPrice, talentConfig.inbornNeedTxt)
           
            if info.isActived then
                talentPointActor:PlayActive()
            else
                if info.isPreActived then
                    talentPointActor:PlayNormal(false)
                else
                    talentPointActor:PlayDeactive()
                end
            end

            if info.isActived and info.isPreActived then
                local tag = ""
                if config.frontHole < config.hole then
                    tag = config.frontHole .. "-" .. config.hole
                else
                    tag = config.hole .. "-" .. config.frontHole
                end

                if #self.AllTalentLine > 0 then
                    for i = 1, #self.AllTalentLine do 
                        local line = self.AllTalentLine[i]
                        if line and line.HoleTag then
                            local bFindTag = false
                            for i = 1, line.HoleTag:Length() do 
                                local lineTag = line.HoleTag:Get(i)
                                if lineTag == tag then
                                    bFindTag = true
                                    break
                                end
                            end
                            if bFindTag then
                                --print('----------激活线特效:' .. tostring(i))
                                if not line.bIsActived or bInit then
                                    line:PlayAnimationForward(line.lian, 1.0, false)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function M:OnHide()
    self.TabIsSelected = false
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Sub_TalentDetail')
    if ui then
        UIManager:GetInstance():RemoveUI(ui)
    end
    if #self.AllTalentLine > 0 then
        for i = 1, #self.AllTalentLine do 
            local line = self.AllTalentLine[i]
            if line then
                line:deActive()
            end
        end
    end
    if #self.AllTalentPoint > 0 then
        for i = 1, #self.AllTalentPoint do 
            local point = self.AllTalentPoint[i]
            if point then
                point:PlayDeactive()
            end
        end
    end
end


function M:HideDetail()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local ui = gameInstance:GetUMG('UI_Sub_TalentDetail')
    if ui then
        UIManager:GetInstance():RemoveUI(ui)
    end
end
----------------------------------------------------------------------
---ui event

function M:OnClicked_Btn_Talent(actor)
    actor.VFX_Clicked:ActivateSystem(true)
    local uiSize = UE.USlateBlueprintLibrary.GetLocalSize(self:GetCachedGeometry())
    local _, actorPos = UE.USlateBlueprintLibrary.LocalToViewport(self.Panel_TalentPoint, actor:GetCachedGeometry(), UE.FVector2D(0, 0))
    local actorSize = UE.USlateBlueprintLibrary.GetLocalSize(actor:GetCachedGeometry())
    local config = UIUtils.GetTalentConfigByHole(actor.HoleId, self.CharInfo.character_id)
    if config then
        self.lastBtnTalent = actor
        self.lastTalentConfig = config
        self.LastSelectedTalentId = config.id
        
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9019, "") then
            local ui = gameInstance:AddUMG('UI_Sub_TalentDetail')
            if ui then
                ui:RefreshUI(self, self.CharInfo.character_id, self.LastSelectedTalentId)
                ui:RefreshPos(actorPos, actorSize, uiSize)
                ui.Panel_Content:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            end
        else
            return
        end
    end
end 

--获取指定天赋id的后续节点
function M:GetAllChildConfigByHole(hole, character_id)
    local result = {}
    local d_character_inborn = require("ClientDatas.d_character_inborn")
    for _, config in pairs(d_character_inborn) do
        if config.frontHole == hole and config.roleID == character_id then
            table.insert(result, config)
        end
    end
    return result
end

return M
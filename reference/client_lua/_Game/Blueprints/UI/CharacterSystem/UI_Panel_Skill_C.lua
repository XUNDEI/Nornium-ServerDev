local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"

---@type UI_Panel_Skill_C
local M = UnLua.Class()

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Skill_Level_Up_Success", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Skill_Level_Up_Success", self)
end

function M:InitData()
    self.SkillTabIndex = UIUtils.ESkillTabType.Active
    self.LastSelectedIndex = -1
    self.InitSkillList = {}
end

function M:InitUI()
    --self.UI_sub_skill_levelpanel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.Hidden)

    self.Btn_ActiveSkill.OnGHSClicked:Add(self, self.OnClicked_Btn_ActiveSkill)
    self.Btn_PassiveSkill.OnGHSClicked:Add(self, self.OnClicked_Btn_PassiveSkill)

    self.FirstSkill.OnClicked:Add(self, self.SelectFirstSkill)

    self.UI_sub_skill_sidebar.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.UI_sub_skill_sidebar.Btn_LevelUp.OnGHSClicked:Add(self, self.OnClicked_Btn_LevelUp)

    self.ListView_Skill.BP_OnEntryInitialized:Clear()
    self.ListView_Skill.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    self.ListView_Skill.BP_OnItemClicked:Clear()
    self.ListView_Skill.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
end

function M:OnMsg_Req_Character_Skill_Level_Up_Success(param)
    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.CharInfo.character_id)
    --print("====新技能:" .. tostring(table.dump(charInfo or {}, false, 10)))
    self.CharInfo = charInfo
    self:InitSkillData()
    self:RefreshSkillTab()
end

function M:GetSkillLv(skillId)
    local lv = 1
    for _, skillInfo in ipairs(self.CharInfo.skill_infos) do
        if skillInfo.skill_id == skillId then
            return skillInfo.skill_level
        end
    end
    return lv
end

function M:InitSkillData()
    self.InitSkillList = {}
    local d_skill = require("ClientDatas.d_skill")
    for k, v in pairs(d_skill) do
        if (v.belong == UIUtils.ESkillTabType.Active or v.belong == UIUtils.ESkillTabType.Passive) then
            local bFind = self.CharInfo.character_id == v.belongCharId
            -- for _, rId in ipairs(v.belongCharId) do 
            --     if rId == self.CharInfo.character_id then
            --         bFind = true
            --         break
            --     end
            -- end
            if bFind then
                if not self.InitSkillList[v.belong] then
                    self.InitSkillList[v.belong] = {}
                end
                local skillInfo = {
                    ['skill_id'] = v.id,
                    ['skill_level'] = self:GetSkillLv(v.id),
                }
                table.insert(self.InitSkillList[v.belong], skillInfo)
            end
        end
    end
    for k, v in pairs(self.InitSkillList) do
        if #v > 1 then
            table.sort(v, function(a, b) 
                return a.skill_id < b.skill_id
            end)
        end
    end
end

function M:RefreshUI(backUI, charInfo)
    self.BackUI = backUI
    self.LastSelectedIndex = -1
    self.CharInfo = charInfo
    self:InitSkillData()
    self:RefreshSkillTab()
end

function M:RefreshSkillTab()
    self.WidgetSwitcher_Active:SetActiveWidgetIndex(self.SkillTabIndex == UIUtils.ESkillTabType.Active and 1 or 0)
    self.WidgetSwitcher_Passive:SetActiveWidgetIndex(self.SkillTabIndex == UIUtils.ESkillTabType.Passive and 1 or 0)

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)

    local skills = self.InitSkillList[self.SkillTabIndex]
    print("===当前技能:" .. tostring(table.dump(skills or {}, false, 10)))
    if not skills then 
        skills = {}
    end
    local skillItemListDataSource = {}
    for i = 1, #skills do
        local itemData = NewObject(ItemClass)
        itemData.Index = i 
        itemData.ItemId = skills[i].skill_id
        table.insert(skillItemListDataSource, itemData)
    end
    
    self.ListView_Skill:ClearListItems()
    self.ListView_Skill:BP_SetListItems(skillItemListDataSource)

    local skillInfo = self.InitSkillList[self.SkillTabIndex] and self.InitSkillList[self.SkillTabIndex][self.LastSelectedIndex] or nil
    if skillInfo then
        self:RefreshSkillDetailPanel(skillInfo.skill_id, skillInfo.skill_level)
    else
        local IsVisible = self.UI_sub_skill_sidebar:IsVisible()
        if self.BackUI and IsVisible then
            print("==================SkillMoveCamera:true")
            self.BackUI:SkillMoveCamera(true)
        end
        self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshSkillDetailPanel(skillId, skillLv)
    local IsVisible = self.UI_sub_skill_sidebar:IsVisible()
    self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self.UI_sub_skill_sidebar:RefreshUI(self.CharInfo.character_id, skillId, skillLv)
    self:StopAllAnimations()
    self:PlayAnimationForward(self.detailAnim, 1, false)
    if not IsVisible and self.BackUI then
        self.BackUI:SkillMoveCamera(false)
    end
end

function M:ClickWhiteArea()
    if self.LastSelectedIndex ~= -1 then
        self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.Hidden)
        self.LastSelectedIndex = -1
        self:RefreshAllListItemSelectedState()
        if self.BackUI then
            self.BackUI:SkillMoveCamera(true)
        end
    end
end

----------------------------------------------------------------------\
---点击事件
function M:OnClicked_Btn_ActiveSkill()
    if self.SkillTabIndex ~= UIUtils.ESkillTabType.Active then
        self.SkillTabIndex = UIUtils.ESkillTabType.Active
        self:RefreshSkillTab()
    end
end

function M:OnClicked_Btn_PassiveSkill()
    if self.SkillTabIndex ~= UIUtils.ESkillTabType.Passive then
        self.SkillTabIndex = UIUtils.ESkillTabType.Passive
        self:RefreshSkillTab()
    end
end

function M:OnClicked_Btn_Close()
    self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.Hidden)
    self.LastSelectedIndex = -1
    self:RefreshAllListItemSelectedState()
    if self.BackUI then
        self.BackUI:SkillMoveCamera(true)
    end
end

function M:OnClicked_Btn_LevelUp()
    --self.UI_sub_skill_sidebar:SetVisibility(UE.ESlateVisibility.Hidden)
    --self.UI_sub_skill_levelpanel:SetVisibility(UE.ESlateVisibility.Visible)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9018, "") then
        local ui = gameInstance:GetUMG('UI_sub_skill_levelpanel')
        local skillInfo = self.InitSkillList[self.SkillTabIndex][self.LastSelectedIndex]
        ui:RefreshUI(nil, self.CharInfo.character_id, skillInfo.skill_id, skillInfo.skill_level)
    end
end

function M:BP_OnEntryInitialized(item, ui)
    ui.Index = item.Index
    ui.ItemId = item.ItemId

    local skillInfo = self.InitSkillList[self.SkillTabIndex][item.Index]
    ui.active_skill_base:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Active and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    ui.passive_skill_base:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Passive and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    ui.selected:SetVisibility(UE.ESlateVisibility.Hidden)
    
    local d_skill = require("ClientDatas.d_skill")
    local skillConfig = d_skill[skillInfo.skill_id]
    if skillConfig then
        --icon
        local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", skillConfig.showIcon, skillConfig.showIcon)
        local iconObj = LoadObject(iconPath)
        if iconObj then
            ui.skill_icon_res:SetBrushFromAtlasInterface(iconObj)
            ui.skill_icon_res_1:SetBrushFromAtlasInterface(iconObj)
        else
            LOG_ERROR("===load icon:" .. iconPath .. ', failed!!!')
        end
        local typeString = ''
        if skillConfig.belong == 2 then --被动类型 固定字符 '被动'
            typeString = Database.L10n(50406)
        else
            typeString = Database.L10n(skillConfig.subType + 50400)
        end
        ui.skill_type:SetText(typeString)
        ui.skill_name:SetText(Database.L10n(skillConfig.skillName))
        ui.skill_name_1:SetText(Database.L10n(skillConfig.skillName))
        ui.skill_name_2:SetText(Database.L10n(skillConfig.skillName))
        ui.Text_SkillLv:SetText(skillInfo.skill_level)

        
        local isUnlock = UIUtils.IsUnlock(self.CharInfo.character_id, skillConfig.unlock)
        if skillConfig.skillType == UIUtils.ESkillType.Talent then
            local talentSkills, _ = UIUtils.GetTalentSkillInfo(self.CharInfo.character_id)
            -- print("===skillInfo.skill_id:" .. tostring(skillInfo.skill_id))
            -- print("===天赋列表:" .. tostring(table.dump(talentSkills, nil, 10)))
            isUnlock = talentSkills[skillInfo.skill_id] or false
        end
        ui.skillLevel:SetVisibility(isUnlock and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        ui.Panel_Lock:SetVisibility(isUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
        if not isUnlock then
            ui.active_skill_lock:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Active and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
            ui.passive_skill_lock:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Passive and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        end
    end

    --unlock
    local selected = self.LastSelectedIndex == item.Index
    ui.selected:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.avctive_skill_base_selected:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Active and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    ui.passive_skill_base_selected:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Passive and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnItemClicked(item)
    if self.LastSelectedIndex == item.Index then
        -- local IsVisible = self.UI_sub_skill_sidebar:GetIsVisible()
        -- self.UI_sub_skill_sidebar:SetVisibility(IsVisible and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
        -- self.LastSelectedIndex = -1
        -- self:RefreshAllListItemSelectedState()
        return 
    end
    
    self.LastSelectedIndex = item.Index
    self:RefreshAllListItemSelectedState()

    local skillInfo = self.InitSkillList[self.SkillTabIndex][item.Index]
    print("====clicked skill_id:" .. tostring(skillInfo.skill_id))
    self:RefreshSkillDetailPanel(skillInfo.skill_id, skillInfo.skill_level)
end

----------------------------------------------------------------------
---辅助函数
function M:RefreshAllListItemSelectedState()
    local widgets = self.ListView_Skill:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local ui = widgets:Get(i)
        local selected = ui.Index == self.LastSelectedIndex
        ui.selected:SetVisibility(selected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.avctive_skill_base_selected:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Active and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        ui.passive_skill_base_selected:SetVisibility(self.SkillTabIndex == UIUtils.ESkillTabType.Passive and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    end
end

function M:SelectFirstSkill()
    self.ListView_Skill:ScrollToTop()

    local items = self.ListView_Skill:GetListItems()

    self:BP_OnItemClicked(items[1])
end

return M

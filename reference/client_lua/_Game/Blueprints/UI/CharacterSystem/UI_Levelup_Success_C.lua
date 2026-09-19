local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Levelup_Success_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")

local ELevelUpType = 
{
    LevelUp = 0,
    LevelBreak = 1,
    SkillUp = 2,
    Refined = 3,
}

function M:Construct()
    self:InitData()
    self:InitUI()
end

function M:Destruct()
end

function M:Tick(MyGeometry, deltaTime)
    if self.StartLvUpAnimation then
        self.PastTime = self.PastTime + deltaTime
        if self.PastTime > self.ItemAnimationDelayTime then
            local realTime = self.PastTime - self.ItemAnimationDelayTime
            local curTime = self.ItemAnimationTime + (self.IntiAnimationIndex - 1) / 7 * self.ItemAnimationTime + (self.IntiAnimationIndex - 1) % 7 * self.ItemAnimationTime
            if realTime > curTime then
                local list = nil 
                if self.Type == ELevelUpType.LevelUp then
                    list = self.List_LevelUp
                elseif self.Type == ELevelUpType.LevelBreak then
                    list = self.ListView_Attr
                elseif self.Type == ELevelUpType.SkillUp then
                    list = self.List_SkillUp
                end
                if list then
                    local widgets = list:GetDisplayedEntryWidgets()
                    if self.IntiAnimationIndex <= widgets:Length() then
                        local ui = widgets:Get(self.IntiAnimationIndex)
                        if ui then
                            ui:PlayAnimationForward(ui.In, 1, false)
                        end
                    else
                        self.StartLvUpAnimation = false
                    end
                    self.IntiAnimationIndex = self.IntiAnimationIndex + 1
                else
                    self.StartLvUpAnimation = false
                end
            end
        end
    end
end

function M:InitData()

end

function M:InitUI()
    self.Image_Bg.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Image_Bg)

    self.List_LevelUp.BP_OnEntryInitialized:Clear()
    self.List_LevelUp.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized_LevelUp(item, widget)
    end)

    self.ListView_Attr.BP_OnEntryInitialized:Clear()
    self.ListView_Attr.BP_OnEntryInitialized:Add(self, function(wbp, item, ui)
        self:BP_OnEntryInitialized_LevelBreak(item, ui)
    end)

    self.List_SkillUp.BP_OnEntryInitialized:Clear()
    self.List_SkillUp.BP_OnEntryInitialized:Add(self, function(wbp, item, widget)
        self:BP_OnEntryInitialized_SkillUp(item, widget)
    end)

    --时间太长了舍弃
    -- self:BindToAnimationFinished(self.LevelUp, function()
    --     self:OnPlayEndLevelUp()
    -- end)
end

function M:RefreshUI(eType, preLv, newLv, maxLv, attrList)
    self.Type = eType
    self.AttrInfoList = attrList
    self.isNewLv = preLv ~= newLv
    --print("=========类型:" .. tostring(eType) .. ",preLv:" .. tostring(preLv) .. ",newLv:" .. tostring(newLv) .. ",max:" .. tostring(maxLv))
    attrList = attrList or {}
    --print("=========attrList:" .. table.dump(attrList, nil, 10))

    if eType == ELevelUpType.LevelUp then
        self.level_up:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.level_break:SetVisibility(UE.ESlateVisibility.Hidden)
        self.refined:SetVisibility(UE.ESlateVisibility.Hidden)

        self.Panel_LevelUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.List_LevelUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.Panel_SkillUp:SetVisibility(UE.ESlateVisibility.Hidden)
        self.List_SkillUp:SetVisibility(UE.ESlateVisibility.Hidden)
        self:RefreshLevelUp(preLv, newLv, attrList)
        self:PlayAnimationForward(self.LevelUp)
    elseif eType == ELevelUpType.LevelBreak then
        self.level_up:SetVisibility(UE.ESlateVisibility.Hidden)
        self.level_break:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.refined:SetVisibility(UE.ESlateVisibility.Hidden)
        self:RefreshLevelBreak(preLv, maxLv, attrList)
        self:PlayAnimationForward(self.LevelBreak)
    elseif eType == ELevelUpType.SkillUp then
        self.level_up:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.level_break:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_LevelUp:SetVisibility(UE.ESlateVisibility.Hidden)
        self.List_LevelUp:SetVisibility(UE.ESlateVisibility.Hidden)
        self.refined:SetVisibility(UE.ESlateVisibility.Hidden)
        self.Panel_SkillUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.List_SkillUp:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self:RefreshSkillUp(maxLv, preLv, newLv, attrList)
        self:PlayAnimationForward(self.SkillUp)
    elseif eType == ELevelUpType.Refined then
        self.level_up:SetVisibility(UE.ESlateVisibility.Hidden)
        self.level_break:SetVisibility(UE.ESlateVisibility.Hidden)
        self.refined:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self:RefreshRefined(preLv, newLv, maxLv)
        self:PlayAnimationForward(self.Refinedanim)
    else
        self.Text_Levelup_New_2:SetText(maxLv)
        self.level_up:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:RefreshLevelUp(preLv, newLv, attrList)
    self.Text_Levelup_Old:SetText(preLv)
    self.Text_Levelup_New:SetText(newLv)

    local itemDataSource = {}
    local ItemSourcePath = "'/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_ListRoleData.BP_ListRoleData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    for i = 1, #attrList do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        ItemData.ItemId = i
        table.insert(itemDataSource, ItemData)
    end

    self.List_LevelUp:ClearListItems()
    self.List_LevelUp:BP_SetListItems(itemDataSource)

    --开始列表动画
    self.PastTime = 0
    self.IntiAnimationIndex = 1
    self.StartLvUpAnimation = true
end

function M:RefreshLevelBreak(preLv, maxLv, attrList)
    self.Text_Levelup_New_2:SetText(maxLv)

    local itemDataSource = {}
    local ItemSourcePath = "'/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_ListRoleData.BP_ListRoleData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    if not attrList then 
        attrList = {}
    end
    for i = 1, #attrList do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = i
        ItemData.ItemId = i
        table.insert(itemDataSource, ItemData)
    end

    self.ListView_Attr:ClearListItems()
    self.ListView_Attr:BP_SetListItems(itemDataSource)

    --开始列表动画
    self.PastTime = 0
    self.IntiAnimationIndex = 1
    self.StartLvUpAnimation = true
end

function M:RefreshSkillUp(skillId, preLv, newLv, attrList)
    self.Text_SkillLevel_Old:SetText(preLv)
    self.Text_SkillLevel_New:SetText(newLv)

    local d_skill = require("ClientDatas.d_skill")
    if not d_skill or not d_skill[skillId] then
        LOG_ERROR("========获取不到数据:d_skill, skillId:" .. tostring(skillId))
        return
    end
    local skillConfig = d_skill[skillId]
    --技能icon
    local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", skillConfig.showIcon, skillConfig.showIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.skill_icon_res_before:SetBrushFromAtlasInterface(iconObj)
        self.skill_icon_res_after:SetBrushFromAtlasInterface(iconObj)
    end

    local skillLvConfig = UIUtils.GetSkillFightLvConfig(skillId, preLv)
    local skillNextLvConfig = UIUtils.GetSkillFightLvConfig(skillId, newLv)

    local descList, valueList = UIUtils.ParseSkillParams(skillId, preLv)
    local nextValueList = valueList
    if skillNextLvConfig then
        local _, vlist = UIUtils.ParseSkillParams(skillId, newLv)
        nextValueList = vlist
    end
 
    local ItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --属性 
    local arrItemListDataSource = {}

    for k, desStr in ipairs(descList) do
        local itemData = NewObject(ItemClass)
        itemData.Index = k
        itemData.Value = desStr
        itemData.ValueEx = (valueList[k] or '') .. '|' .. (nextValueList[k] or '')
        table.insert(arrItemListDataSource, itemData)
    end

    self.List_SkillUp:ClearListItems()
    self.List_SkillUp:BP_SetListItems(arrItemListDataSource)

    --开始列表动画
    self.PastTime = 0
    self.IntiAnimationIndex = 1
    self.StartLvUpAnimation = true
end

function M:RefreshRefined(preLv, newLv, weaponSkill)
    self.Text_Levelup_Old_1:SetText(preLv)
    self.Text_Levelup_New_1:SetText(newLv)
    local oldDesc = UIUtils.GetSkillDescBySkillI(weaponSkill, preLv)
    local newDesc = UIUtils.GetSkillDescBySkillI(weaponSkill, newLv)
    self.old:SetText(oldDesc)
    self.new:SetText(newDesc)
end

function M:OnPlayEndLevelUp()
    --开始列表动画
    self.PastTime = 0
    self.IntiAnimationIndex = 1
    self.StartLvUpAnimation = true
end
-----------------------------------------------------------------------
--- 
function M:OnClicked_Image_Bg()
    local eType = self.Type
    --判断特效是否播放完毕
    if eType == ELevelUpType.LevelUp then
        local widgets = self.List_LevelUp:GetDisplayedEntryWidgets()
        local allPlayFlipEnd = true
        for i = 1, widgets:Length() do 
            local ui = widgets:Get(i)
            if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
                allPlayFlipEnd = false
            end
            ui:SetSkipFlip(true)
        end
        if not allPlayFlipEnd then
            for i = 1, widgets:Length() do 
                local ui = widgets:Get(i)
                if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
                    ui:SetSkipFlip(true)
                end
            end
            return UE.UWidgetBlueprintLibrary.Handled()
        end
    elseif eType == ELevelUpType.LevelBreak then
        local widgets = self.ListView_Attr:GetDisplayedEntryWidgets()
        local allPlayFlipEnd = true
        for i = 1, widgets:Length() do 
            local ui = widgets:Get(i)
            if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
                allPlayFlipEnd = false
            end
            ui:SetSkipFlip(true)
        end
        if not allPlayFlipEnd then
            for i = 1, widgets:Length() do 
                local ui = widgets:Get(i)
                if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
                    ui:SetSkipFlip(true)
                end
            end
            return UE.UWidgetBlueprintLibrary.Handled()
        end
    elseif eType == ELevelUpType.SkillUp then
        -- local widgets = self.List_SkillUp:GetDisplayedEntryWidgets()
        -- local allPlayFlipEnd = true
        -- for i = 1, widgets:Length() do 
        --     local ui = widgets:Get(i)
        --     if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
        --         allPlayFlipEnd = false
        --     end
        --     ui:SetSkipFlip(true)
        -- end
        -- if not allPlayFlipEnd then
        --     for i = 1, widgets:Length() do 
        --         local ui = widgets:Get(i)
        --         if not ui.IsFlipPlayStart or (ui.IsFlipPlayStart and ui.FlipNextValueAnimation) then
        --             ui:SetSkipFlip(true)
        --         end
        --     end
        --     return UE.UWidgetBlueprintLibrary.Handled()
        -- end
    end
    UIManager:GetInstance():RemoveUI(self)
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:BP_OnEntryInitialized_LevelUp(item, ui)
    local attrInfo = self.AttrInfoList[item.Index]
    --print("====刷新item：" .. tostring(table.dump(attrInfo, false, 10)))
    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        ui.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    ui.Img_Arrow:SetVisibility(self.isNewLv and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    ui.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))
    -- ui.Text_CurValue:SetText(self.isNewLv and attrInfo.attrValue or "")
    -- ui.Text_NextValue:SetText((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
    if attrInfo.config.types == UIUtils.AttributeType.AbsoluteValue then
        local curValue = math.floor((attrInfo.attrValue or 0))
        local attrValue = math.floor((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
        ui:SetNextValue(attrValue, '{0}')
        ui.Text_NextValue:SetText(0)
        ui.Text_CurValue:SetText(self.isNewLv and curValue or "")
    else
        local curValue = math.floor((attrInfo.attrValue * 100 or 0))
        local attrValue = math.floor((attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        ui:SetNextValue(attrValue, '{0}%')
        ui.Text_NextValue:SetText('0%')
        ui.Text_CurValue:SetText(self.isNewLv and string.format('%d%%', curValue) or "")
    end
    ui.Panel_Item:SetRenderOpacity(0)
end

function M:BP_OnEntryInitialized_LevelBreak(item, ui)
    local attrInfo = self.AttrInfoList[item.Index]
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        ui.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    --ui.Img_Arrow:SetVisibility(self.isNewLv and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    ui.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))
    -- ui.Text_CurValue:SetText(attrInfo.attrValue)
    -- ui.Text_NextValue:SetText((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
    if attrInfo.config.types == UIUtils.AttributeType.AbsoluteValue then
        local curValue = math.floor((attrInfo.attrValue or 0))
        local attrValue = math.floor((attrInfo.attrValue or 0) + (attrInfo.attrUp or 0))
        ui:SetNextValue(attrValue, '{0}')
        ui.Text_NextValue:SetText(attrValue)
        ui.Text_CurValue:SetText(curValue)
    else
        local curValue = math.floor((attrInfo.attrValue * 100 or 0))
        local attrValue = math.floor((attrInfo.attrValue * 100 or 0) + (attrInfo.attrUp * 100 or 0))
        ui:SetNextValue(attrValue, '{0}%')
        ui.Text_NextValue:SetText('0%')
        ui.Text_CurValue:SetText(string.format('%d%%', curValue))
    end
    ui.Panel_Item:SetRenderOpacity(0)
end

function M:BP_OnEntryInitialized_SkillUp(itemData, ui)
    local values = string.split(itemData.ValueEx, '|')
    ui.Text_Title:SetText(itemData.Value)
    ui.Text_CurValue:SetText(values[1])
    ui.Text_NextValue:SetText(values[2])
    ui.Img_Bg:SetVisibility(itemData.Index % 2 == 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    ui.Panel_Item:SetRenderOpacity(0)
end

return M

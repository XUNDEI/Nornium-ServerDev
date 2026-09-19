local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"

---@type UI_Panel_Equip_C
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

end

function M:InitUI()
    --self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    --self.Btn_LevelUp.OnGHSClicked:Add(self, self.OnClicked_Btn_LevelUp)
    self.Btn_SkillDes.OnGHSClicked:Add(self, self.OnClicked_Btn_SkillDes)
    self.Btn_SkillAttr.OnGHSClicked:Add(self, self.OnClicked_Btn_SkillAttr)

    self.List_Des.BP_OnEntryInitialized:Clear()
    self.List_Des.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Des(itemData, widget)
    end)
    self.List_Attr.BP_OnEntryInitialized:Clear()
    self.List_Attr.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Attr(itemData, widget)
    end)

    self.List_Mat.BP_OnEntryInitialized:Clear()
    self.List_Mat.BP_OnEntryInitialized:Add(self, function(wbp, itemData, widget) 
        self:BP_OnEntryInitialized_Mat(itemData, widget)
    end)

    self.List_Mat.BP_OnItemClicked:Clear()
    self.List_Mat.BP_OnItemClicked:Add(self, function(wbp, itemData) 
        self:BP_OnItemClicked_Mat(itemData)
    end)

    self.WidgetSwitcher_SkillDes:SetActiveWidgetIndex(1)
    self.WidgetSwitcher_SKillAttr:SetActiveWidgetIndex(0)
    self.WidgetSwitcher_Introduction:SetActiveWidgetIndex(0)

    self.skill_showtag:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:OnMsg_Req_Character_Skill_Level_Up_Success(param)
    self.InitCharId = param.character_id
    self.InitSkillId = param.skill_id
    self.InitSkillLv = param.skill_level
    self:RefreshSkillInfo()
end

function M:RefreshUI(characterId, skillId, skillLv)
    self.InitCharId = characterId
    self.InitSkillId = skillId
    self.InitSkillLv = skillLv

    local d_skill = require("ClientDatas.d_skill")
    if not d_skill or not d_skill[skillId] then
        LOG_ERROR("========获取不到数据:d_skill, skillId:" .. tostring(skillId))
        return
    end

    self.SkillConfig = d_skill[skillId]

    local isActive = self.SkillConfig.belong == UIUtils.ESkillTabType.Active
    self.WidgetSwitcher:SetActiveWidgetIndex(isActive and 0 or 1)
    --self.skill_showtag:SetVisibility(isActive and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    --icon
    local iconPath = string.format("/Script/Paper2D.PaperSprite'/Game/_Game/TP_New/Character_skill_res/Frames/%s_png.%s_png'", self.SkillConfig.showIcon, self.SkillConfig.showIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        if isActive then
            self.Img_Active_Icon:SetBrushFromAtlasInterface(iconObj)
        else
            self.Img_Passive_Icon:SetBrushFromAtlasInterface(iconObj)
        end
    end
    self.Text_SkillName:SetText(Database.L10n(self.SkillConfig.skillName))
    
    --des
    local desItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
    local desItemClass = UE.UClass.Load(desItemSourcePath)
    local desItemListDataSource = {}
    local desStrArr = string.split(Database.L10n(self.SkillConfig.skillDesc), '|')
    for k, desStr in ipairs(desStrArr) do 
        if desStr ~= '' then
            local itemData = NewObject(desItemClass)
            itemData.Index = k
            itemData.Value = desStr
            table.insert(desItemListDataSource, itemData)
        end
    end
    self.List_Des:ClearListItems()
    self.List_Des:BP_SetListItems(desItemListDataSource)

    -- local desStrArr = string.split(Database.L10n(self.SkillConfig.skillDesc), '|')
    -- for k, desStr in ipairs(desStrArr) do 
    --     local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Character/UI_sub_skill_sidebar.UI_sub_skill_sidebar_C"))

    --     local strArr = string.split(desStr, '#')
    --     ui.Text_Title:SetText(strArr[1] or "")
    --     ui.Text_Des:SetText(strArr[2] or "")

    --     self.List_Des1:AddChild(ui)
    -- end

    self:RefreshSkillInfo()
end

function M:RefreshSkillInfo()
    self.List_Attr:ClearListItems()

    self.Text_SkillLv:SetText("Lv." .. self.InitSkillLv)

    --next lv unlock
    local skillFightLvConfig = UIUtils.GetSkillFightLvConfig(self.InitSkillId, self.InitSkillLv)
    if not skillFightLvConfig then
        --LOG_ERROR("========获取不到数据:d_skill_fight_level: skillId:" .. tostring(self.InitSkillId) .. ",skillLv:" .. tostring(self.InitSkillLv))
        self.Btn_LevelUp:SetVisibility(UE.ESlateVisibility.Hidden)
        self.need_lock:SetVisibility(UE.ESlateVisibility.Hidden)
        --return 
    end

    --天赋参数
    self.TalentParsm = {}
    local paramStrArr = {}
    if self.SkillConfig.skillType == 5 then
        local talentSkillList = UIUtils.GetTalentSkillInfo(self.InitCharId)
        local talentSkillLvs = talentSkillList[self.InitSkillId]
        self.TalentParsm = UIUtils.GetTalentSkillParams(self.InitSkillId, talentSkillLvs or {1})
    else
        if skillFightLvConfig then
            paramStrArr = skillFightLvConfig.clickDamage
            for _, v in ipairs(skillFightLvConfig.pressDamage) do 
                table.insert(paramStrArr, v)
            end
        else
            paramStrArr = string.split(self.SkillConfig.rateShow, ',')
        end
    end
    local descList, resultList = UIUtils.ParseSkillParams(self.InitSkillId, self.InitSkillLv)
    local desItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
    local desItemClass = UE.UClass.Load(desItemSourcePath)
    --attr
    local arrItemListDataSource = {}
    for k, desStr in ipairs(descList) do
        local itemData = NewObject(desItemClass)
        itemData.Index = k
        itemData.Value = desStr
        if self.SkillConfig.skillType == 5 then
            itemData.ValueEx = self.TalentParsm[k] or "0"
        else
            itemData.ValueEx = resultList[k]
        end
        table.insert(arrItemListDataSource, itemData)
    end
    self.List_Attr:BP_SetListItems(arrItemListDataSource)
    
    ----------------------------------------------------------------------
    local isTalentSkill = self.SkillConfig.skillType == 5
    local isMaxLv = self.InitSkillLv >= UIUtils.GetSkillMaxLv(self.InitSkillId)
    local isUnlock = true
    local lockTip = ''
    if skillFightLvConfig then
        isUnlock, lockTip = UIUtils.IsUnlock(self.InitCharId, skillFightLvConfig.condition)
    end
    print("===ismaxLv:" .. tostring(isMaxLv) .. ",isUnlock:" .. tostring(isUnlock) .. ",locktip:" .. tostring(lockTip))
    self.Btn_LevelUp:SetVisibility((not isTalentSkill and not isMaxLv and isUnlock) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    self.need_lock:SetVisibility((not isTalentSkill and not isMaxLv and not isUnlock) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    if not isUnlock then
        self.Text_UnlockLv:SetText(lockTip)
    end

    if not isTalentSkill and not isMaxLv then
        self.List_Mat:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        self.cost:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

        local ItemSourcePath = "/Script/Engine.Blueprint'/Game/_Game/Blueprints/UI/UI_Character/UI_Data/BP_ListItemData.BP_ListItemData_C'"
        local ItemClass = UE.UClass.Load(ItemSourcePath)

        self.List_Attr:ClearListItems()
        self.List_Attr:BP_SetListItems(arrItemListDataSource)
    
        --解析材料
        local currencyList, matList, bIsfull = UIUtils.ParseMatrailConfig(skillFightLvConfig.material)
        self.MaterialList = matList
        local BagSystem = require "Module.Backpack.BackpackSystem"
        if #currencyList == 0 then
            currencyList[1] = {
                item_id = 9001,
                count = BagSystem:GetInstance():GetItemCount(9001),
                needCount = 0,
            }
        end
        --货币
        local hasGold = currencyList[1].count
        local needGold = currencyList[1].needCount
    
        --货币类型
        local currencyId = currencyList[1].item_id
        local currencyConfig = UIUtils.GetItemConfigById(currencyId)
        --icon
        --货币图片
        local iconResPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%d_png.Icon_%d_png', currencyConfig.id, currencyConfig.id)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            self.Image_5:SetBrushFromAtlasInterface(iconRes)
        end
    
        local textColor = UE.FSlateColor()
        textColor.SpecifiedColor = hasGold >= needGold and UE.FLinearColor(1.0, 1.0, 1.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
        self.Text_HaveGold:SetColorAndOpacity(textColor)
        self.Text_HaveGold:SetText("/" .. hasGold)
        self.Text_NeedGold:SetText(needGold)

        --材料列表
        local ItemListDataSource = {}
        for index = 1, #self.MaterialList do
            local itemData = NewObject(ItemClass)
            itemData.Index = index
            itemData.Id = self.MaterialList[index].item_id
            table.insert(ItemListDataSource, itemData)
        end
        self.List_Mat:ClearListItems()
        self.List_Mat:BP_SetListItems(ItemListDataSource)
    else
        self.List_Mat:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.cost:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

----------------------------------------------------------------------\
---点击事件
-- function M:OnClicked_Btn_Close()
--     self:SetVisibility(UE.ESlateVisibility.Hidden)
-- end

-- function M:OnClicked_Btn_LevelUp()
--     self:SetVisibility(UE.ESlateVisibility.Hidden)
-- end

function M:OnClicked_Btn_SkillDes()
    self.WidgetSwitcher_SkillDes:SetActiveWidgetIndex(1)
    self.WidgetSwitcher_SKillAttr:SetActiveWidgetIndex(0)
    self.WidgetSwitcher_Introduction:SetActiveWidgetIndex(0)
end

function M:OnClicked_Btn_SkillAttr()
    self.WidgetSwitcher_SkillDes:SetActiveWidgetIndex(0)
    self.WidgetSwitcher_SKillAttr:SetActiveWidgetIndex(1)
    self.WidgetSwitcher_Introduction:SetActiveWidgetIndex(1)
end

function M:BP_OnEntryInitialized_Des(itemData, ui)
    local strArr = string.split(itemData.Value, '#')
    local titleStr = string.gsub(strArr[1], "\n", "")
    local desStr = strArr[2]
    if nil == desStr then
        desStr = titleStr
        titleStr = ''
    end
    ui.Text_Title:SetVisibility(titleStr == '' and UE.ESlateVisibility.Collapsed or UE.ESlateVisibility.SelfHitTestInvisible)
    ui.Text_Title:SetText(titleStr)
    ui.Text_Des:SetText(desStr)
end

function M:BP_OnEntryInitialized_Attr(itemData, ui)
    ui.Text_Title:SetText(itemData.Value)
    ui.Text_CurValue:SetText(itemData.ValueEx)
    ui.Img_Bg:SetVisibility(itemData.Index % 2 == 1 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:BP_OnEntryInitialized_Mat(item_data, ui)
    local itemData = self.MaterialList[item_data.Index]

    --稀有度背景图片
    if itemData.config.rarityPath and itemData.config.rarityPath ~= '' then
        local strArr = string.split(itemData.config.rarityPath, '/')
        local littePath = strArr[#strArr]
        local rarityPath = string.format('/Game/_Game/%s.%s', itemData.config.rarityPath, littePath)
        local itemRarityPic = LoadObject(rarityPath)
        if itemRarityPic then
            ui.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
        end
    end

    local hasMat = itemData.count > 0
    if hasMat then
        ui.lackState:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        end
    else
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.lackState:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        --icon
        if itemData.config.iconPath and itemData.config.iconPath ~= '' then
            local strArr = string.split(itemData.config.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                ui.lackIcon:SetBrushFromAtlasInterface(iconRes)
            end
        end
    end

    --选中个数
    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = itemData.count >= itemData.needCount and UE.FLinearColor(0.0, 0.0, 0.0, 1.0) or UE.FLinearColor(1.0, 0.0, 0.0, 1.0)
    ui.Text_Count:SetColorAndOpacity(textColor)
    ui.Text_Count:SetText(itemData.count .. "/" .. itemData.needCount)
end

function M:BP_OnItemClicked_Mat(item_data)
    local itemData = self.MaterialList[item_data.Index]
    UIUtils.ShowItemInfo(itemData.item_id, itemData.hasCount)
end

----------------------------------------------------------------------
---辅助函数

return M
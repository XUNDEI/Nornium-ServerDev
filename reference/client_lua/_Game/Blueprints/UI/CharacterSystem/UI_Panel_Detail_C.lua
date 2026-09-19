require "UnLua"
require "Common.TableUtil"
local Database = require "_Game.Utils.Database"
local UIUtils = require "_Game.Utils.UIUtils"
local d_character = require "ClientDatas.d_character"
local d_characteristic = require "ClientDatas.d_characteristic"

---@type UI_CharaterSystem_C
local M = Class()

--构造函数
function M:Construct()
    self:InitData()
    self:InitUI()
end

function M:Destruct()
   
end

function M:InitData()

end

function M:InitUI()
    --角色详情星级
    -- self.RoleStarIconList = {
    --     [1] = self.StarIcon,
    --     [2] = self.StarIcon_1,
    --     [3] = self.StarIcon_2,
    --     [4] = self.StarIcon_3,
    --     [5] = self.StarIcon_4,
    --     [6] = self.StarIcon_5,
    -- }

    --特性列表
    --生成器
    self.UI_Sub_Feature.FeatureList.BP_OnEntryInitialized:Clear()
    self.UI_Sub_Feature.FeatureList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
  
    --点击事件
    self.UI_Sub_Feature.FeatureList.BP_OnItemClicked:Clear()
    self.UI_Sub_Feature.FeatureList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)
end

function M:RefreshUI(roleData)
    self.CharacterInfo = roleData

    --print("===当前角色数据:" .. tostring(table.dump(roleData, false, 10)))
    --机甲名字
    self.MechaName:SetText(Database.L10n(roleData.config.mechName))

    --角色名字
    self.RoleName:SetText(Database.L10n(roleData.config.name))

    --元素icon
    local config = roleData.config
    local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/element_%s_s_png.element_%s_s_png", config.element, config.element)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.ElementIcon_res:SetBrushFromAtlasInterface(iconObj)
    end

    --武器icon
    local config = roleData.config
    local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/weapons_%s_png.weapons_%s_png", config.profession, config.profession)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        self.WeaponIcon:SetBrushFromAtlasInterface(iconObj)
    end

    --星级 测试默认3星
    -- roleData.Star = math.random(1, 6)
    -- for i, icon in pairs(self.RoleStarIconList) do 
    --     icon:SetVisibility(roleData.Star >= i and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)
    -- end
    
    --判断突破等级是否满，等级是否满级
    local maxBreakTimes = UIUtils.GetCharacterMaxBreakTimes(self.CharacterInfo.character_id)
    local maxLevel = UIUtils.GetCharacterMaxLevel(self.CharacterInfo.character_id, self.CharacterInfo.break_times)
    local lv, needExp, nextExp = UIUtils.GetCharacterLevel(self.CharacterInfo.character_id, self.CharacterInfo.break_times, self.CharacterInfo.exp)
    local isMaxBreakTimes = maxBreakTimes == self.CharacterInfo.break_times
    local isMaxLevel = maxLevel == lv

    --升级按钮
    self.UI_Sub_LevelEntrance.LevelUp:SetVisibility((isMaxLevel and isMaxBreakTimes) and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    --升级文字
    local isBreak = lv == maxLevel
    self.UI_Sub_LevelEntrance.Text_LvUp:SetVisibility(isBreak and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.UI_Sub_LevelEntrance.Text_LvBreak:SetVisibility(isBreak and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    
    --等级
    self.UI_Sub_LevelEntrance.CurrentLevel:SetText(lv)
    self.UI_Sub_LevelEntrance.MaxLevel:SetText(maxLevel)

    --经验条
    if isMaxBreakTimes and isMaxLevel then
        self.UI_Sub_LevelEntrance.LevelExp:SetPercent(1)
    else
        local rate = (nextExp - needExp) / nextExp
        self.UI_Sub_LevelEntrance.LevelExp:SetPercent(rate)
    end
    
    --默认特性
    local characteristicInfo = d_character[roleData.character_id].characteristicHave
    --获取天赋特性
    local talentCharacteristList = UIUtils.GetTalentEffectCharacteristicLv(roleData.character_id)
    for _, cId in ipairs(characteristicInfo) do
        talentCharacteristList[cId] = math.max(talentCharacteristList[cId] or 1, 1)
    end
    self.TalentCharacteristList = talentCharacteristList
    -- print("===天赋列表:" .. tostring(table.dump(self.TalentCharacteristList, nil, 10)))

    local itemDataSource = {}
    local ItemSourcePath = "'/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_ListRoleData.BP_ListRoleData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local index = 1
    for id, lv in pairs(self.TalentCharacteristList) do
        local ItemData = NewObject(ItemClass)
        ItemData.Index = index
        ItemData.RoleId = id
        table.insert(itemDataSource, ItemData)
        index = index + 1
    end

    self.UI_Sub_Feature.FeatureList:ClearListItems()
    self.UI_Sub_Feature.FeatureList:BP_SetListItems(itemDataSource)
end

----------------------------------------------------------------------
---ui event
function M:BP_OnEntryInitialized(item, widget)
    local ItemLv = nil
    for id, lv in pairs(self.TalentCharacteristList) do
        if id == item.RoleId then
            ItemLv = lv
        end
    end
    local config = d_characteristic[item.RoleId]

    local showBg = item.Index % 2 == 1
    widget.Img_Bg:SetVisibility(showBg and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    --特性icon
    if config.characteristicIcon and config.characteristicIcon ~= ''  then
        local iconObj = LoadObject(config.characteristicIcon)
        if iconObj then
            widget.Img_FeatureIcon:SetBrushFromAtlasInterface(iconObj)
        end
    end 
   
    --特性title
    widget.Text_Title:SetText(Database.L10n(config.characteristicName))
    --特性等级
    widget.Text_Lv:SetText("LV." .. (ItemLv or 1))
end

function M:BP_OnItemClicked(item)
    local ItemLv = nil
    for id, lv in pairs(self.TalentCharacteristList) do
        if id == item.RoleId then
            ItemLv = lv
        end
    end
    if not ItemLv then return end
    
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_DescText')

    local screenPos = UE.UWidgetLayoutLibrary.GetMousePositionOnViewport(self)
    ui.float.Slot:SetAlignment(UE.FVector2D(1, 0.5))
    ui.float.Slot:SetZOrder(1)
    ui.float.Slot:SetPosition(screenPos)
    local config = d_characteristic[item.RoleId]

    ui.name:SetText(Database.L10n(config.characteristicName))
    ui.desc:SetText(Database.L10n(config.characteristicDesc))
end

return M
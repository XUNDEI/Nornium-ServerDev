local UIUtils = {}

local Database = require("_Game.Utils.Database")
local BagItemConfig = require "ClientDatas.d_bag_item"
local BagWeaponConfig = require "ClientDatas.d_bag_item_weapon"
local BagEquipConfig = require "ClientDatas.d_bag_item_equip"
local BagSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"

--道具类型
UIUtils.ItemMainType = 
{
    Weapon = 10, --武器
    Equip = 11, --装备
    TempProp = 12, --非局类道具
    Prop = 13, --局类道具
    Consumables = 20, --消耗品
    Currency = 90, --货币
    Ship = 91, --舰船
    Skin = 92, --皮肤卡
    Build = 93, --建筑物
}

--武器类型
UIUtils.ItemWeaponType = 
{
    Glaive             = 1, --巨刃
    LongSword          = 2, --长剑
    Sabre              = 3, --佩刀
    Firearms           = 4, --枪械
    SacrificialVessels = 5, --礼器
    PoLun              = 6, --宝轮
    FuTa               = 7, --浮塔
}

--武器类型word
UIUtils.WordWeaponType = 
{
    82800001, --巨刃
    82800003, --长剑
    82800006, --佩刀
    82800002, --枪械
    82800004, --礼器
    82800005, --宝轮
    82800007, --浮塔
}

--装备类型
UIUtils.ItemEquipType = 
{
    Heart = 1, --心念引擎
    Lung = 2, --肺叶涡轮
    kidney = 3, --肾腺燃剂
    Liver = 4, --肝膜晶壳
    Stomach = 5, --胃壁视界
    Brain = 6, --脑核算机
}

--装备类型word
UIUtils.WordEquipType = 
{
    82701002, --心念引擎 = 1
    82701003, --肺叶涡轮 = 2
    82701004, --肾腺燃剂 = 3
    82701005, --肝膜晶壳 = 4
    82701006, --胃壁视界 = 5
    82701007, --脑核算机 = 6
}

UIUtils.EItemRarityColor = 
{
    [1] = "bbd6f3",
    [2] = "bbd6f3",
    [3] = "5dfcab",
    [4] = "fbc55d",
    [5] = "ff7639",
    [6] = "ff5266",
    [7] = "ff5266",
}

--货币子类型
UIUtils.ItemCurrencyType = 
{
    Gold = 1, --金币
    Diamond = 2, --钻石
}

--非局类道具子类型
UIUtils.ItemTempPropType = 
{
    Material = 2,  --材料
    CharacterExp = 3, --角色经验道具
    WeaponExp = 4, --武器经验道具
    EquipExp = 5, --装备经验道具
    CharCard = 6, --角色卡
    Consume = 7, --消耗品
    BluePrint = 8, --蓝图
    ForgeBP = 9,   --锻造蓝图
}

--道具稀有度
UIUtils.ItemRarityType = 
{
    Gray = 1, --灰
    White = 2, --白
    Green = 3, --绿
    Yellow = 4, --黄
    Orange = 5, --橙
    Red = 6, --红
    RedEx = 7, --特效红
}

--技能类型
UIUtils.ESkillTabType = 
{
    Active = 1, --主动
    Passive = 2, --被动
    --特质
}

--任务类型
UIUtils.ETaskType =
{
    None = 0,
    Daily = 1,    --日常
    Main = 2,     --主线 
    Sub = 3,      --支线
    Tutorial = 4, --教学
}

--任务状态
UIUtils.EMissionResult = 
{
    Accepted = 1, --已接受
    Got = 2, --已领取
}

--关卡类型
UIUtils.LevelType = 
{
    CharacterExp = 1, --角色经验
    Coin = 2, --金钱本
    CharacterSkillMaterial = 3, --角色技能材料
    CharacterBreakMaterial = 4, --角色突破材料
    EquipForgeMaterial = 5, --装备锻造材料
}

UIUtils.BuildSubType = 
{
    Char = 1, --角色
    Platform = 2, --地台
    Decorate = 3, --摆设
    Hang = 4, --悬浮
}

UIUtils.EFightState = {
    FIGHT_STATE_IDLE     = 0,
    FIGHT_STATE_FIGHTING = 1,
}

--元素类型
-- 粒子:1
-- 动能:2
-- 力场:3
-- 灾厄:4
-- 侵蚀:5
-- 虚无:6
UIUtils.EElementRelation = 
{
    [1] = 3,
    [2] = 1,
    [3] = 3,
    [4] = 6,
    [5] = 4,
    [6] = 5
}

--每个元素类型对应的文字
UIUtils.EElementWord =
{
    [1] = 255,
    [2] = 256,
    [3] = 257,
    [4] = 258,
    [5] = 259,
    [6] = 260,
}

--每个元素类型对应的颜色
UIUtils.EElementColor =
{
    [1] = "eec37bff",
    [2] = "f58d4fff",
    [3] = "74eae9ff",
    [4] = "f85f5fff",
    [5] = "a5f177ff",
    [6] = "b27af1ff",
}

UIUtils.EItemId =
{
    DailyCopySweep = 1201001,--扫荡卷
    DailyCopyTicket = 1201003,--门票
}

UIUtils.ECurrencyId =
{
    Gold = 9001, --金星贝（金币）
    Diamond = 9002, --诺伦炬（钻石）
    ChongYi = 9003, --败者翼膜
    Exp = 9004, --玩家经验
    Fossil = 9005, --时枝化石
    GachaCoinLow = 9005, --抽卡代币低级
    GachaCoinHigh = 9006, --抽卡代币高级
    NolenLens = 9007, --诺伦透镜
    PalacePoints = 9008, --王宫点数(家具币)
}

UIUtils.AttributeType = 
{
    AbsoluteValue = 1, --绝对值
    OverAHundred = 2, --超过100
    InAHundred = 3,--不超过100
}

UIUtils.ESkinSubType = 
{
    Char = 1, --角色
    Mecha = 2, --机甲
}

--排序方式
UIUtils.ESortType = 
{
    Type   = 1, --类型排序
    Level  = 2, --等级排序
    Star   = 3, --品阶排序
    Talent = 4, --星位排序
    DEF    = 5, --防御力排序
    Attack = 6, --攻击力排序
    
}

UIUtils.EFilterType = 
{
    --Equip
    EquipType     = 1, --装备类型
    MainProperty  = 2, --主属性
    Rune          = 3, --星芒
    Custom        = 4, --自定义
    --Character
    WeaponType    = 5, --武器类型
    ElementType   = 6, --命质类型 元素类型
    SynthesisType = 7; --炼金类型
    Rarity        = 8; --稀有度
}


UIUtils.ECopyType = 
{
    ECopyType_Challenge = 1, --挑战
    ECopyType_Train = 2, --角色试炼
    ECopyType_DPS = 3, --凹分关
    ECopyType_BaseTeach = 4, --基础教学
    ECopyType_Plot = 5, --剧情
}

--地铁抽奖奖池类型
UIUtils.EGachaPoolType = 
{
    Study = 0, --教学池
    CharPool = 1, --角色池
    WeaponPool = 2, --武器池
    Normal = 3, --常驻池
    NewPlayer = 4, --新手池
}
UIUtils.EGachaPoolTypeName = 
{
    [1] = 500001,
    [2] = 500002,
    [3] = 500003,
    [4] = 500004,
}

--抽奖券类型
UIUtils.EGachaTicket = 
{
    GachaTickLimit = 1200001, --限定抽卡券
    GachaTickNormal = 1200002, --常驻抽卡券
}

--抽奖券类型
UIUtils.SceneId = 
{
    City1Station = 1,   --地铁
    City1Hotel = 2,     --套房
    BusinessCenter = 3, --商业区
    OpeningScene = 4,   --OpeningScene
}

----------------------------------------------------------------------
---货币
---获取金币
function UIUtils.GetGold()
    return UIUtils.GetItemCount(UIUtils.ECurrencyId.Gold)
end

--获取钻石
function UIUtils.GetDimond()
    return UIUtils.GetItemCount(UIUtils.ECurrencyId.Diamond)
end

--获取闪色虫翼
function UIUtils.GetChongYi()
    return UIUtils.GetItemCount(UIUtils.ECurrencyId.ChongYi)
end

--获取指定货币类型道具
function UIUtils.GetCurrency(type)
    for item_id, bagInfo in pairs(BagSystem:GetInstance().BagInfo) do
        local bagConfig = UIUtils.GetItemConfigById(item_id)
        if bagConfig.itemType == UIUtils.ItemMainType.Currency and bagConfig.subType == type then
            return bagInfo
        end
    end
    return nil
end

function UIUtils.GetItemCount(itemId)
    local count = 0
    local uuid = 0
    local bagInfos = BagSystem:GetInstance().BagInfo[itemId]
    if bagInfos then
        for _, bagInfo in pairs(bagInfos) do
            count = count + bagInfo.count
            uuid = bagInfo.item_uuid
        end
    end
   
    return count, uuid
end

--获取指定类型的道具配置
function UIUtils.GetAllItemConfigByType(mainType, subType)
    local reuslt = {}
    for k, v in pairs(BagItemConfig) do
        if v.itemType == mainType and v.subType == subType then
            reuslt[k] = v
        end
    end
    return reuslt
end

--获取指定道具id的配置表(普通道具,武器,装备)
function UIUtils.GetItemConfigById(itemId)
    local config = BagItemConfig[itemId] 
    if not config then
        config = BagWeaponConfig[itemId]
    end
    if not config then
        config = BagEquipConfig[itemId]
    end
    if not config then
        LOG_ERROR("====>>UIUtils.GetItemConfigById can't find config itemId:" .. tostring(itemId))
    end
    return config 
end

-- 物品表的神秘路径都以TP_New开头
local PREFIX = '/Game/_Game/'

function UIUtils.GetItemRarityBorder(itemId)
    local itemConfig = UIUtils.GetItemConfigById(itemId)
    if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
        local strArr = string.split(itemConfig.rarityPath, '/')
        local filename = strArr[#strArr]
        local borderPath = string.format('%s%s.%s', PREFIX, itemConfig.rarityPath, filename)
        return LoadObject(borderPath)
    end
end

function UIUtils.GetItemIcon(itemId)
    local itemConfig = UIUtils.GetItemConfigById(itemId)
    if itemConfig.iconPath and itemConfig.iconPath ~= '' then
        local strArr = string.split(itemConfig.iconPath, '/')
        local filename = strArr[#strArr]
        local iconPath = string.format('%s%s.%s', PREFIX, itemConfig.iconPath, filename)
        return LoadObject(iconPath)
    end
end

-- 给宇宙显示资源用的，资源不是物品没有相关配置
local RESOURCE_NAME = {
    99200001,
    99200003,
    99200005,
}

local RESOURCE_ICON = {
    "",
    '/Game/_Game/TP_New/SRPG_Shop_res/Frames/Icon_gel_png.Icon_gel_png',
    "",
}
function UIUtils.CreateUniverseResourceItem(context, resourceId, count)
    ---@type UI_Get_Item_C
    local item = UE.UWidgetBlueprintLibrary.Create(context, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
    item.TextName:SetText(Database.L10n(RESOURCE_NAME[resourceId]))
    item.TextNum:SetText(count)

    local sprite = LoadObject(RESOURCE_ICON[resourceId])
    local icon = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite, 0, 0)
    item.icon_res:SetBrush(icon)
    item.ItemPanel:SetRenderOpacity(1)

    return item
end

function UIUtils.CreateItem(context, itemId, count, showName)
    local showNameText = showName
    if showName == nil then
        showNameText = true
    end
    local itemConfig = UIUtils.GetItemConfigById(itemId)
    ---@type UI_Get_Item_C
    local item = UE.UWidgetBlueprintLibrary.Create(context, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
    item.TextName:SetText(Database.L10n(itemConfig.itemName))
    item.TextName:SetVisibility(showNameText and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    item.TextNum:SetText(count)

    item.TextNum:SetVisibility(count and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)

    local itemRarityPic = UIUtils.GetItemRarityBorder(itemId)
    if itemRarityPic then
        item.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
    end

    local iconRes = UIUtils.GetItemIcon(itemId)
    if iconRes then
        item.icon_res:SetBrushFromAtlasInterface(iconRes)
    end

    item.ItemPanel:SetRenderOpacity(1)
    item.Img_bg.OnMouseButtonDownEvent:Unbind()
    item.Img_bg.OnMouseButtonDownEvent:Bind(item, function()
        UIUtils.ShowItemInfo(itemId, count, 0)
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    return item
end

function UIUtils.GetSortedCharacterConfigData()
    local d_character = require "ClientDatas.d_character"
    local result = {}
    for k, v in pairs(d_character) do 
        table.insert(result, v)
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end

--背包中用到的 UI/UI_BUI/UI_Backpack/UI_Item 
function UIUtils.RefreshUIItem(ui, itemData, bIsSelected)
    ui:SetVisibility(UE.ESlateVisibility.Visible)
    --print("====UIUtils.RefreshUIItem:" .. tostring(table.dump(itemData)))
    if not itemData.config then
        itemData.config = UIUtils.GetItemConfigById(itemData.item_id)
    end
    ui.selected:SetVisibility(bIsSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    if itemData.config.itemType == UIUtils.ItemMainType.Weapon then
        local lv, _ = UIUtils.GetWeaponLevel(itemData.item_id, itemData.weapon_info.break_times, itemData.weapon_info.exp)
        ui.Text_Lv:SetText(Database.L10n(5014001) .. lv)
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        ui.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
        if itemData.weapon_info.refine_level > 0 then
            ui.weapon_refined:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            ui.refined_num:SetText('+'..itemData.weapon_info.refine_level)
        else
            ui.weapon_refined:SetVisibility(UE.ESlateVisibility.Hidden)
        end

        if itemData.characterId then
            ui.avatar:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

            local idolPath = UIUtils.GetCharacterIdolIcon(itemData.characterId)
            local idolPic = LoadObject(idolPath)
            if idolPic then
                ui.avatar_res:SetBrushFromAtlasInterface(idolPic)
            end
        else
            ui.avatar:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        if itemData.config.rarity > 6 then
            ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    elseif itemData.config.itemType == UIUtils.ItemMainType.Equip then
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.weapon_refined:SetVisibility(UE.ESlateVisibility.Hidden)
        --是否装备
        if itemData.characterId then
            ui.avatar:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

            local idolPath = UIUtils.GetCharacterIdolIcon(itemData.characterId)
            local idolPic = LoadObject(idolPath)
            if idolPic then
                ui.avatar_res:SetBrushFromAtlasInterface(idolPic)
            end
        else
            ui.avatar:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    else
        ui.Text_Count:SetText(itemData and itemData.count or "1")
        ui.Text_Count:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        ui.Text_Lv:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.avatar:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.weapon_refined:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    
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
    
    --类型
    --icon
    if itemData.config.iconPath and itemData.config.iconPath ~= '' then
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local strArr = string.split(itemData.config.iconPath, '/')
        local littePath = strArr[#strArr]
        local iconResPath = string.format('/Game/_Game/%s.%s', itemData.config.iconPath, littePath)
        local iconRes = LoadObject(iconResPath)
        if iconRes then
            ui.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
        end
    else
        ui.wp_icon_res:SetVisibility(UE.ESlateVisibility.Collapsed)
    end

    if itemData.config.rarity <= 6 then
        ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        ui.wp_container_icon_out_tex:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
   
    --锁定
    --时间
    --装备的编码
end

--获取角色id的头像图片路径
function UIUtils.GetCharacterHeadIcon(roleId, headRes)
    if not headRes or headRes == "" then
        local characterConfig = require("ClientDatas.d_character")
        local config = characterConfig[roleId]
        if config and config.headRes and config.headRes ~= "" then
            headRes = config.headRes 
        end
    end
   
    return string.format("'/Game/_Game/TP_New/TeamList_Head_Res/Frames/%s_png.%s_png'", headRes, headRes)
end

function UIUtils.GetCharacterIdolIcon(roleId)
    local headRes = ""
    local characterConfig = require("ClientDatas.d_character")
    local config = characterConfig[roleId]
    if config and config.idolProfile and config.idolProfile ~= "" then
        headRes = config.idolProfile 
    end
    return string.format("'/Game/_Game/TP_New/IdolProfile_res/Frames/%s_png.%s_png'", headRes, headRes)
end

--获取角色id的名字
function UIUtils.GetCharacterName(roleId, name)
    if not name or name == "" then
        local characterConfig = require("ClientDatas.d_character")
        local config = characterConfig[roleId]
        if config and config.name and config.name ~= "" then
            name = config.name 
        end
    end
    return Database.L10n(name)
end


---------------------------------------------------------------------------
---玩家
--获取玩家经验
function UIUtils.GetPlayerLevel()
    local exp = UIUtils.GetItemCount(UIUtils.ECurrencyId.Exp)
    local d_player_level = require("ClientDatas.d_player_level")
    local level = 1
    local next_level_exp_need = 0
    local level_exp = 0
    --稀有度 
    for _, v in ipairs(d_player_level) do
        if exp < v['exp'] then
            next_level_exp_need = v['exp'] - exp
            level_exp = v['exp']
            break
        end
        exp = exp - v['exp']
        level = level + 1
    end
    local max_level = UIUtils.GetPlayerMaxLevel()
    if level > max_level then
        level = max_level
        next_level_exp_need = 0
    end
    return level, next_level_exp_need, level_exp, exp
end

function UIUtils.GetPlayerMaxLevel()
    local d_player_level = require("ClientDatas.d_player_level")
    local maxLv = 1
    for lv, _ in ipairs(d_player_level) do
        maxLv = lv > maxLv and lv or maxLv
    end
    return maxLv
end

---------------------------------------------------------------------------
---武器
--获取武器最大突破次数
function UIUtils.GetWeaponMaxBreakTimes(weaponId)
    local d_weapon_levelbreak = require("ClientDatas.d_weapon_levelbreak")
    local max_level = 1
    for _, v in ipairs(d_weapon_levelbreak) do
        if weaponId == v.weaponId then
            max_level = max_level > v.levelbreak and max_level or v.levelbreak
        end
    end
    return max_level
end

--获取武器最大等级
function UIUtils.GetWeaponMaxLevel(weaponId, breakTimes)
    local d_weapon_levelbreak = require("ClientDatas.d_weapon_levelbreak")
    local max_level = 1
    for _, v in ipairs(d_weapon_levelbreak) do
        if weaponId == v.weaponId and breakTimes == v.levelbreak then
            max_level = v.level
            break
        end
    end
    return max_level
end

--获取武器等级
function UIUtils.GetWeaponLevel(weaponId, breakTimes, exp)
    --print("===weaponId:" .. tostring(weaponId) .. ", breakTimes:" .. tostring(breakTimes) .. ",exp:" .. tostring(exp))
    local d_weapon_level = require("ClientDatas.d_weapon_level")
    local level = 1
    local next_level_exp_need = 0
    local level_exp = 0
    --稀有度 
    local config = UIUtils.GetItemConfigById(weaponId)
    local rarity = config and config.rarity or 1
    local expStr = "exp" .. rarity
    --print("===expStr:" .. expStr)
    for _, v in ipairs(d_weapon_level) do
        if exp < v[expStr] then
            next_level_exp_need = v[expStr] - exp
            level_exp = v[expStr]
            break
        end
        exp = exp - v[expStr]
        level = level + 1
    end
    local max_level = UIUtils.GetWeaponMaxLevel(weaponId, breakTimes)
    if level > max_level then
        level = max_level
        next_level_exp_need = 0
    end
    return level, next_level_exp_need, level_exp
end

--获取武器最大精炼等级
function UIUtils.GetWeaponMaxRefineLevel(weaponId)
    local weaponConfig = require("ClientDatas.d_weapon")[weaponId]
    local max_level = 1
    if weaponConfig then
        max_level = weaponConfig.maxRefine
    end
    return max_level
end

--获取升到指定等级需要所有经验
function UIUtils.GetWeaponAllExp(weaponId, tarLv)
    local needExp = 0
    local config = UIUtils.GetItemConfigById(weaponId)
    local rarity = config and config.rarity or 1
    local expStr = "exp" .. rarity
    local d_weapon_level = require("ClientDatas.d_weapon_level")
    for _, v in ipairs(d_weapon_level) do
        if v.id < tarLv then
            needExp = needExp + v[expStr]
        end
    end
    return needExp
end

--计算角色初始等级到目标等级的所有属性提升叠加
function UIUtils.GetWeaponLevelUpAttr(weaponId, initLv, tarLv)
    local allAddAttr = {}
    local baseAttrList1 = UIUtils.GetWeaponBaseAttr(weaponId, initLv)
    local baseAttrList2 = UIUtils.GetWeaponBaseAttr(weaponId, tarLv)
    for attrId, attrValue in pairs(baseAttrList2) do
        allAddAttr[attrId] = attrValue - (baseAttrList1[attrId] or 0)
    end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级的所有属性提升叠加
function UIUtils.GetWeaponLevelBreakAttr(weaponId, initBreakLv, tarBreakLv)
    --print("=====GetCharacterLevelBreakAttr:" .. tostring(initBreakLv) .. ", tarbreakLv:" .. tostring(tarBreakLv))
    local allAddAttr = {}
    local d_weapon_levelbreak = require("ClientDatas.d_weapon_levelbreak")
    for _, v in ipairs(d_weapon_levelbreak) do
        if weaponId == v.weaponId and v.levelbreak > initBreakLv and v.levelbreak <= tarBreakLv then
            for i = 1, #v.attributes, 2 do
                local attrId = v.attributes[i]
                local attrValue = UIUtils.GetAttributeValue(attrId, v.attributes[i + 1]) 
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级所需要的所有材料
function UIUtils.GetWeaponLevelBreakMat(weaponId, initBreakLv, tarBreakLv)
    local allAddAttr = {}
    local d_weapon_levelbreak = require("ClientDatas.d_weapon_levelbreak")
    for _, v in ipairs(d_weapon_levelbreak) do
        if weaponId == v.weaponId and v.levelbreak >= initBreakLv and v.levelbreak < tarBreakLv then
            print("===weaponId:" .. tostring(weaponId) .. ",levelbreak:" .. tostring(v.levelbreak) .. ",material:" .. tostring(v.materail))
            for i = 1, #v.material, 2 do
                local attrId = v.material[i]
                local attrValue = v.material[i + 1]
                if not attrValue then
                    LOG_ERROR('==d_weapon_levelbreak:weaponId' .. tostring(weaponId) .. ",levelbreak:" .. tostring(v.levelbreak) .. ",material:" .. tostring(v.materail))
                    attrValue = 1
                end
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--获取武器基础属性
function UIUtils.GetWeaponBaseAttr(weaponId, weaponLv)
    local attrTable = {}
    local weaponConfig = require("ClientDatas.d_weapon")[weaponId]
    if weaponConfig then
        local baseAttr = weaponConfig.weaponAttr
        local baseValue = weaponConfig.attrValue
        local attrUnlockLv = weaponConfig.attrUnlock
        local starValue = weaponConfig.starValue
        local attrM1 = weaponConfig.attrM1
        local lvAdd = weaponConfig.lvAdd
        local attrM2 = weaponConfig.attrM2
        local attrGrowth = weaponConfig.attrGrowth
        local attrM3 = weaponConfig.attrM3

        for i = 1, #baseAttr do
            if attrUnlockLv[i] <= weaponLv then
                local addValue = ((starValue[i] + attrM1[i]) + weaponLv *  UIUtils.GetAttributeValue(baseAttr[i], lvAdd[i]) + attrM2[i]) * (attrGrowth[i] / 10000 + attrM3[i])
                attrTable[baseAttr[i]] = UIUtils.GetAttributeValue(baseAttr[i],  baseValue[i]) + addValue
            end
        end
    end
  
    return attrTable
end

--获取武器当前属性(基础属性+突破属性)
function UIUtils.GetWeaponAttr(weaponId, weaponLv, weaponBreakTimes)
    --基础属性
    local baseAttr = UIUtils.GetWeaponBaseAttr(weaponId, weaponLv or 1)
    --print("====基础属性:" .. tostring(table.dump(baseAttr or {}, false, 10)))

    --突破属性
    local d_role_levelbreak = require("ClientDatas.d_weapon_levelbreak")
    for _, v in ipairs(d_role_levelbreak) do
        if weaponId == v.weaponId then
            if weaponBreakTimes >= v.levelbreak then
                for i = 1, #v.attributes, 2 do
                    local attrId = v.attributes[i]
                    local attrValue = UIUtils.GetAttributeValue(attrId, v.attributes[i + 1])
                    if not baseAttr[attrId] then baseAttr[attrId] = 0 end
                    baseAttr[attrId] = baseAttr[attrId] + attrValue
                end
            end
        end
    end
    --print("====突破属性:" .. tostring(table.dump(baseAttr or {}, false, 10)))
    return baseAttr
end

--获取武器精炼需要的材料
function UIUtils.GetWeaponRefineMat(weapon_id, init_lv, refine_lv)
    local weaponConfig = require("ClientDatas.d_weapon")[weapon_id]
    if weaponConfig then
        return weaponConfig.refinedCost
    end
end

--获取武器精炼技能
function UIUtils.GetWeaponRefineSkill(weapon_id, refine_lv)
    local weaponConfig = require("ClientDatas.d_weapon")[weapon_id]
    if weaponConfig then
        return weaponConfig.skillID
    end
end

function UIUtils.GetWeaponSkillDesc(item_id, refine_level)
    local weaponSkillId = UIUtils.GetWeaponRefineSkill(item_id, refine_level)
    if weaponSkillId and weaponSkillId > 0 then
        local skillInfo = Database.Query("d_skill", weaponSkillId)
        local skillDesc = Database.L10n(skillInfo.skillDesc) or ""
        local skillName = Database.L10n(skillInfo.skillName) or ""
        local skillFightLevelInfo = UIUtils.GetSkillFightLvConfig(weaponSkillId, refine_level + 1)
        local array = string.split(skillInfo.rateShow, ',')
        for index, value in ipairs(array) do
            if value == '#' then
                if skillFightLevelInfo.inbornSkill then
                    local param = string.split(skillFightLevelInfo.inbornSkill, ',')
                    skillDesc = string.gsub(skillDesc, value, param[index], 1)
                end
            elseif value == '#%' then
                if skillFightLevelInfo.inbornSkill then
                    local param = string.split(skillFightLevelInfo.inbornSkill, ',')
                    local skillParam = string.format("%.1f", tonumber(param[index]) / 100)
                    skillDesc = string.gsub(skillDesc, '#', skillParam, 1)
                end
            end
        end
        return skillDesc, skillName
    end
    return '', ''
end

function UIUtils.GetSkillDescBySkillI(skill_id, refine_level)
    local skillInfo = Database.Query("d_skill", skill_id)
    local skillDesc = Database.L10n(skillInfo.skillDesc) or ""
    local skillFightLevelInfo = UIUtils.GetSkillFightLvConfig(skill_id, refine_level + 1)
    local array = string.split(skillInfo.rateShow, ',')
    for index, value in ipairs(array) do
        if value == '#' then
            if skillFightLevelInfo.inbornSkill then
                local param = string.split(skillFightLevelInfo.inbornSkill, ',')
                if param[index] then
                    skillDesc = string.gsub(skillDesc, value, param[index], 1)
                end                
            end
        elseif value == '#%' then
            if skillFightLevelInfo.inbornSkill then
                local param = string.split(skillFightLevelInfo.inbornSkill, ',')
                local skillParam = string.format("%.1f", tonumber(param[index]) / 100)
                skillDesc = string.gsub(skillDesc, '#', skillParam, 1)
            end
        end
    end
    return skillDesc
end

function UIUtils.GetWeaponSkillParams(weaponSkillId, refine_lv) 
    local skillLvConfig = UIUtils.GetSkillFightLvConfig(weaponSkillId, refine_lv + 1)
    if skillLvConfig then
        return skillLvConfig.inbornSkill
    end

    return ''
end

---------------------------------------------------------------------------
---装备
--获取装备最大突破次数
function UIUtils.GetEquipMaxBreakTimes(equipId)
    local d_equip_levelbreak = require("ClientDatas.d_equip_levelbreak")
    local max_breakTime = 0
    for _, v in ipairs(d_equip_levelbreak) do
        if equipId == v.equipId then
            max_breakTime = max_breakTime > v.levelbreak and max_breakTime or v.levelbreak
        end
    end
    return max_breakTime
end

--获取装备最大等级
function UIUtils.GetEquipMaxLevel(equipId, breakTimes)
    local d_equip_levelbreak = require("ClientDatas.d_equip_levelbreak")
    local max_level = 1
    for _, v in ipairs(d_equip_levelbreak) do
        if equipId == v.equipId and breakTimes == v.levelbreak then
            max_level = v.level
            break
        end
    end
    return max_level
end

--获取装备等级
function UIUtils.GetEquipLevel(equipId, breakTimes, exp)
    local d_equip_level = require("ClientDatas.d_equip_level")
    local level = 1
    local next_level_exp_need = 0
    local level_exp = 0
    --稀有度 
    local config = UIUtils.GetItemConfigById(equipId)
    local rarity = config and config.rarity or 1
    local expStr = "exp" .. rarity
    for _, v in ipairs(d_equip_level) do
        if exp < v[expStr] then
            next_level_exp_need = v[expStr] - exp
            level_exp = v[expStr]
            break
        end
        exp = exp - v[expStr]
        level = level + 1
    end
    local max_level = UIUtils.GetEquipMaxLevel(equipId, breakTimes)
    if level > max_level then
        level = max_level
        next_level_exp_need = 0
    end
    return level, next_level_exp_need, level_exp
end

--获取升到指定等级需要所有经验
function UIUtils.GetEquipAllExp(equipId, tarLv)
    local needExp = 0
    local config = UIUtils.GetItemConfigById(equipId)
    local rarity = config and config.rarity or 1
    local d_equip_level = require("ClientDatas.d_equip_level")
    for _, v in ipairs(d_equip_level) do
        if v.id < tarLv then
            needExp = needExp + v["exp" .. rarity]
        end
    end
    print("====GetEquipAllExp:" .. tostring(needExp))
    return needExp
end

--计算角色初始等级到目标等级的所有属性提升叠加
function UIUtils.GetEquipLevelUpAttr(equipId, initLv, tarLv)
    local allAddAttr = {}
    local baseAttrList1 = UIUtils.GetEquipBaseAttr(self.InitArmInfo)
    local baseAttrList2 = UIUtils.GetEquipBaseAttr(self.InitArmInfo)
    for attrId, attrValue in pairs(baseAttrList2) do
        allAddAttr[attrId] = attrValue - (baseAttrList1[attrId] or 0)
    end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级的所有属性提升叠加
function UIUtils.GetEquipLevelBreakAttr(equipId, initBreakLv, tarBreakLv)
    print("=====GetCharacterLevelBreakAttr:" .. tostring(initBreakLv) .. ", tarbreakLv:" .. tostring(tarBreakLv))
    local allAddAttr = {}
    local d_equip_levelbreak = require("ClientDatas.d_equip_levelbreak")
    for _, v in ipairs(d_equip_levelbreak) do
        if equipId == v.equipId and v.levelbreak >= initBreakLv and v.levelbreak < tarBreakLv then
            for i = 1, #v.attributes, 2 do
                local attrId = v.attributes[i]
                local attrValue = UIUtils.GetAttributeValue(attrId, v.attributes[i + 1])
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级所需要的所有材料
function UIUtils.GetEquipLevelBreakMat(equipId, initBreakLv, tarBreakLv)
    local allAddAttr = {}
    local d_equip_levelbreak = require("ClientDatas.d_equip_levelbreak")
    for _, v in ipairs(d_equip_levelbreak) do
        if equipId == v.equipId and v.levelbreak >= initBreakLv and v.levelbreak < tarBreakLv then
            for i = 1, #v.material, 2 do
                local attrId = v.material[i]
                local attrValue = v.material[i + 1]
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--获取武器基础属性
function UIUtils.GetEquipBaseAttr(equipData)
    local equipId = equipData.item_id
    local arm_info = equipData.arm_info
    local attrTable = {}
    local equipConfig = require("ClientDatas.d_equip")[equipId]
    if equipConfig then
        local baseAttr = equipConfig.equipAttr
        local baseValue = equipConfig.attrValue
        
        local weight_index = arm_info.arm_random_attribute_infos[1].weight_index
        local float_count = arm_info.arm_random_attribute_infos[1].float_count
        local randomAttr1 = equipConfig.randomAtt[weight_index + 1]
        local randomAttrValue1 = equipConfig.randomAttrValue[weight_index + 1] + float_count * equipConfig.randomAttrValueAdd[weight_index + 1]

        weight_index = arm_info.arm_random_attribute_infos[2].weight_index
        float_count = arm_info.arm_random_attribute_infos[2].float_count
        local randomAttr2 = equipConfig.randomAtt[weight_index + 1]
        local randomAttrValue2 = equipConfig.randomAttrValue[weight_index + 1] + float_count * equipConfig.randomAttrValueAdd[weight_index + 1]

        attrTable[baseAttr] = UIUtils.GetAttributeValue(baseAttr, baseValue)
        attrTable[randomAttr1] = UIUtils.GetAttributeValue(randomAttr1, randomAttrValue1)
        attrTable[randomAttr2] = UIUtils.GetAttributeValue(randomAttr2, randomAttrValue2)
    end
  
    return attrTable
end

--获取装备当前属性(一条基础属性+两条随机属性)
function UIUtils.GetEquipAttr(equipData)
    --基础属性
    local baseAttr = UIUtils.GetEquipBaseAttr(equipData)
    return baseAttr
end

---------------------------------------------------------------------------
---符文系统
--获取符文属性
function UIUtils.GetRuneAttr(rune_id, data, index)
    local d_equip_rune = require("ClientDatas.d_equip_rune")
    local d_attributes = require("ClientDatas.d_attributes")
    local d_equip_rune_att_value = require("ClientDatas.d_equip_rune_att_value")
    local rune_info = d_equip_rune[rune_id]
    local baseAttr = {}
    local arm_info = data.arm_info
    if not data.config then
        data.config = UIUtils.GetItemConfigById(data.item_id)
    end
    local rarity = data.config.rarity
    if rune_info then
        --第一条固定属性
        local attr_id = rune_info.attrType
        local attr_info = d_equip_rune_att_value[attr_id]
        if attr_info then
            local float_count = arm_info.arm_rune_infos[index].base_attribute_float_count
            local attrValue1 = attr_info.starValue[rarity] + attr_info.starValueAdd[rarity] * float_count
            local attr1 = {
                attrId = attr_id,
                attrValue = UIUtils.GetAttributeValue(attr_id, attrValue1),
                attrUp = 0,
                config = d_attributes[attr_id]
            }
            table.insert(baseAttr, attr1)
        end

        attr_id = arm_info.arm_rune_infos[index].extra_attribute_id
        attr_info = d_equip_rune_att_value[attr_id]
        if attr_info then
            local float_count = arm_info.arm_rune_infos[index].extra_attribute_float_count
            local attrValue2 = attr_info.starValue[rarity] + attr_info.starValueAdd[rarity] * float_count
            local attr2 = {
                attrId = attr_id,
                attrValue = UIUtils.GetAttributeValue(attr_id, attrValue2),
                attrUp = 0,
                config = d_attributes[attr_id]
            }
            table.insert(baseAttr, attr2)
        end
    end
    return baseAttr
end

--获取角色装备激活的符文之语列表
function UIUtils.GetCharacterRuneSuit(roleId, charInfo)
    local character_info = charInfo or CharacterSystem:GetInstance():GetCharacterInfoById(roleId)
    if not character_info then
        return {}
    end
    local baseAttr = {}
    local skillList = {}
    if character_info.arm_infos then
        local runeIdList = {}
        for _, arm_info in ipairs(character_info.arm_infos) do
            for i, arm_rune_info in ipairs(arm_info.arm_info.arm_rune_infos) do
                local runeId = arm_rune_info.rune_id
                runeIdList[runeId] = (runeIdList[runeId] or 0) + 1
            end
        end
        local d_equip_Rune = require('ClientDatas.d_equip_Rune')
        local d_attributes = require("ClientDatas.d_attributes")
        for id, count in pairs(runeIdList) do 
            local config = d_equip_Rune[id]
            if count > 1 and config then
                for suit_index = 2, count do
                    local attrTypeStr = tostring(suit_index) .. 'runesAttrType'
                    local attrValueStr = tostring(suit_index) .. 'runesAttrValue'
                    if config[attrTypeStr] and config[attrValueStr] 
                        and #config[attrTypeStr] > 0 and #config[attrValueStr] 
                        and #config[attrTypeStr] == #config[attrValueStr] then
                        for idx, attrId in ipairs(config[attrTypeStr]) do
                            local attrVlaue = config[attrValueStr][idx]
                            local attrTab = {
                                attrId = attrId,
                                attrValue = UIUtils.GetAttributeValue(attrId, attrVlaue),

                                attrUp = 0,
                                config = d_attributes[attrId]
                            }
                            table.insert(baseAttr, attrTab)
                        end
                    end
                    local skillStr = tostring(suit_index) .. 'runesSkill'
                    if config[skillStr] and config[skillStr] > 0 then
                        table.insert(skillList, config[skillStr])
                    end
                end
            end
        end
    end
    return baseAttr, skillList
end

function UIUtils.GetCharacterEquipSkillList(roleId, character_info)
    local _, skillList = UIUtils.GetCharacterRuneSuit(roleId, character_info)
    return skillList
end

---------------------------------------------------------------------------
---角色系统
--获取角色最大突破次数
function UIUtils.GetCharacterMaxBreakTimes(roleId)
    -- local d_role_levelbreak = require("ClientDatas.d_role_levelbreak")
    local d_com_params = require('ClientDatas.d_com_params')

    local max_level = tonumber(d_com_params[12].value2)
    -- for _, v in ipairs(d_role_levelbreak) do
    --     if roleId == v.roleId then
    --         max_level = max_level > v.levelbreak and max_level or v.levelbreak
    --     end
    -- end
    return max_level
end

--当前突破等级下最大等级
function UIUtils.GetCharacterMaxLevel(roleId, breakTimes)
    local d_role_levelbreak = require("ClientDatas.d_role_levelbreak")
    local max_level = 1
    for _, v in ipairs(d_role_levelbreak) do
        if roleId == v.roleId and breakTimes == v.levelbreak then
            max_level = v.level
            break
        end
    end
    return max_level
end

--获取角色等级和下一级
function UIUtils.GetCharacterLevel(roleId, breakTimes, exp)
    local d_role_level = require("ClientDatas.d_role_level")
    local level = 1
    local next_level_exp_need = 0
    local level_exp = 0
    for _, v in ipairs(d_role_level) do
        if exp < v.exp then
            next_level_exp_need = v.exp - exp
            level_exp = v.exp
            break
        end
        exp = exp - v.exp
        level = level + 1
    end
    local max_level = UIUtils.GetCharacterMaxLevel(roleId, breakTimes)
    if level > max_level then
        level = max_level
        next_level_exp_need = 0
    end
    return level, next_level_exp_need, level_exp
end

--获取升到指定等级需要所有经验
function UIUtils.GetCharacterAllExp(tarLv)
    local needExp = 0
    local d_role_level = require("ClientDatas.d_role_level")
    for _, v in ipairs(d_role_level) do
        if v.id < tarLv then
            needExp = needExp + v.exp
        end
    end
    return needExp
end

--计算角色初始等级到目标等级的所有属性提升叠加
function UIUtils.GetCharacterLevelUpAttr(character_id, initLv, tarLv)
    local allAddAttr = {}
    local d_character = require("ClientDatas.d_character")
    local character_data = d_character[character_id]
    for i = 1, #character_data.lvAdd, 2 do
        local attrId, attrValue = table.unpack(character_data.lvAdd, i, i + 1)
        local growth_index = math.floor((i-1) / 2) + 1
        attrValue = attrValue * character_data.attrGrowth[growth_index] / 10000
        attrValue = attrValue * (tarLv - initLv)
        allAddAttr[attrId] = (allAddAttr[attrId] or 0) + UIUtils.GetAttributeValue(attrId, attrValue)
    end
    -- local d_role_level = require("ClientDatas.d_role_level")
    -- for lv, levelInfo in ipairs(d_role_level) do 
    --     if lv > initLv and lv <= tarLv then
    --         allAddAttr[1001] = (allAddAttr[1001] or 0) + UIUtils.GetAttributeValue(1001, levelInfo["hpMaxUp"])
    --         allAddAttr[1002] = (allAddAttr[1002] or 0) + UIUtils.GetAttributeValue(1002, levelInfo["attackUp"])
    --         allAddAttr[1024] = (allAddAttr[1024] or 0) + UIUtils.GetAttributeValue(1024, levelInfo["physicalDefenseUp"])
    --         allAddAttr[1025] = (allAddAttr[1025] or 0) + UIUtils.GetAttributeValue(1025, levelInfo["magicDefenseUp"])
    --     end
    -- end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级的所有属性提升叠加
function UIUtils.GetCharacterLevelBreakAttr(roleId, initBreakLv, tarBreakLv)
    local allAddAttr = {}
    local d_role_levelbreak = require("ClientDatas.d_role_levelbreak")
    for _, v in ipairs(d_role_levelbreak) do
        if roleId == v.roleId and v.levelbreak > initBreakLv and v.levelbreak <= tarBreakLv then
            for i = 1, #v.attributes, 2 do
                local attrId = v.attributes[i]
                local attrValue = UIUtils.GetAttributeValue(attrId, v.attributes[i + 1])
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--计算角色初始突破等级到目标突破等级所需要的所有材料
function UIUtils.GetCharacterLevelBreakMat(roleId, initBreakLv, tarBreakLv)
    local allAddAttr = {}
    local d_role_levelbreak = require("ClientDatas.d_role_levelbreak")
    for _, v in ipairs(d_role_levelbreak) do
        if roleId == v.roleId and v.levelbreak >= initBreakLv and v.levelbreak < tarBreakLv then
            for i = 1, #v.material, 2 do
                local attrId = v.material[i]
                local attrValue = v.material[i + 1]
                allAddAttr[attrId] = (allAddAttr[attrId] or 0) + attrValue
            end
        end
    end
    return allAddAttr
end

--获取角色基础属性
function UIUtils.GetCharacterBaseAttr(roleId)
    local attrTable = {}
    local baseAttr = require("ClientDatas.d_character")[roleId].attr
    for i = 1, #baseAttr, 2 do
        attrTable[baseAttr[i]] = UIUtils.GetAttributeValue(baseAttr[i], baseAttr[i + 1])
    end
    return attrTable
end

--获取角色当前属性(非武器+装备+天赋)
function UIUtils.GetCharacterAttr(roleId, roleLv, roleBreakTimes, char_info)
    --基础属性
    local baseAttr = UIUtils.GetCharacterBaseAttr(roleId)
    --print("====基础属性:" .. tostring(table.dump(baseAttr or {}, false, 10)))

    --等级属性
    local d_character = require("ClientDatas.d_character")
    local character_data = d_character[roleId]
    for i = 1, #character_data.lvAdd, 2 do
        local attrId, attrValue = table.unpack(character_data.lvAdd, i, i + 1)
        local growth_index = math.floor((i-1) / 2) + 1
        attrValue = attrValue * character_data.attrGrowth[growth_index] / 10000
        attrValue = attrValue * (roleLv - 1)
        baseAttr[attrId] = (baseAttr[attrId] or 0) + UIUtils.GetAttributeValue(attrId, attrValue)
    end
    -- local d_role_level = require("ClientDatas.d_role_level")
    -- for lv, leveInfo in ipairs(d_role_level) do 
    --     if roleLv >= lv then
    --         baseAttr[1001] = baseAttr[1001] + UIUtils.GetAttributeValue(1001, leveInfo["hpMaxUp"])
    --         baseAttr[1002] = baseAttr[1002] + UIUtils.GetAttributeValue(1002, leveInfo["attackUp"])
    --         baseAttr[1024] = baseAttr[1024] + UIUtils.GetAttributeValue(1024, leveInfo["physicalDefenseUp"])
    --         baseAttr[1025] = baseAttr[1025] + UIUtils.GetAttributeValue(1025, leveInfo["magicDefenseUp"])
    --     end
    -- end
    --print("====等级属性:" .. tostring(table.dump(baseAttr or {}, false, 10)))
    --突破属性
    local d_role_levelbreak = require("ClientDatas.d_role_levelbreak")
    for _, v in ipairs(d_role_levelbreak) do
        if roleId == v.roleId then
            if roleBreakTimes >= v.levelbreak then
                for i = 1, #v.attributes, 2 do
                    local attrId = v.attributes[i]
                    local attrValue = UIUtils.GetAttributeValue(attrId, v.attributes[i + 1])
                    if not baseAttr[attrId] then baseAttr[attrId] = 0 end
                    baseAttr[attrId] = baseAttr[attrId] + attrValue
                end
            end
        end
    end
    --print("====突破属性:" .. tostring(table.dump(baseAttr or {}, false, 10)))
    --天赋属性
    local talentAttr = UIUtils.GetTalentAddAttr(roleId, char_info)
    for attrId, attrValue in pairs(talentAttr) do 
        baseAttr[attrId] = (baseAttr[attrId] or 0) + attrValue
    end
    
    return baseAttr
end

--获取角色当前额外属性(武器+装备+天赋)
function UIUtils.GetCharacterAttrEx(character_id, char_info)
    local attrs = {}
    local character_info = char_info and char_info or CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return
    end

    --武器属性
    local weapon_info = character_info.weapon_info
    local weapon_id = weapon_info.item_id
    local weapon_level = UIUtils.GetWeaponLevel(weapon_id, weapon_info.weapon_info.break_times, weapon_info.weapon_info.exp)
    local weapon_attrs = UIUtils.GetWeaponAttr(weapon_id, weapon_level, weapon_info.weapon_info.break_times)
    for i, v in pairs(weapon_attrs) do
        attrs[i] = (attrs[i] or 0) + v
    end

    --武器精炼
    -- local weapon_refine_attrs = UIUtils.GetWeaponRefineAttr(weapon_id, weapon_info.weapon_info.refine_level)
    -- for i, v in pairs(weapon_refine_attrs) do
    --     attrs[i] = (attrs[i] or 0) + v
    -- end

    local arm_attrsExport = {}
    local rune_AttrsExport = {}
    --装备属性
    if character_info.arm_infos then
        for _, arm_info in ipairs(character_info.arm_infos) do
            local arm_attrs = UIUtils.GetEquipAttr(arm_info)
            for i, v in pairs(arm_attrs) do
                arm_attrsExport[i] = (arm_attrsExport[i] or 0) + v
                attrs[i] = (attrs[i] or 0) + v
            end
            --装备符文数据
            for i, arm_rune_info in ipairs(arm_info.arm_info.arm_rune_infos) do 
                local rune_id = arm_rune_info.rune_id
                local runeAttrs = UIUtils.GetRuneAttr(rune_id, arm_info, i)
                for _, runeAttr in pairs(runeAttrs) do
                    rune_AttrsExport[runeAttr.attrId] = (rune_AttrsExport[runeAttr.attrId] or 0) + runeAttr.attrValue
                    attrs[runeAttr.attrId] = (attrs[runeAttr.attrId] or 0) + runeAttr.attrValue
                end
            end
        end
    end
    --所有属性加成，武器属性，装备基础属性，装备符文属性
    return attrs, weapon_attrs, arm_attrsExport, rune_AttrsExport
end

function UIUtils.GetCharacterEquipAttr(character_id, fixAttr)
    fixAttr = fixAttr or false
    local allAttr = {}
    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return
    end
    -- character
    local character_level = UIUtils.GetCharacterLevel(character_id, character_info.break_times, character_info.exp)
    local attrs = UIUtils.GetCharacterAttr(character_id, character_level, character_info.break_times, character_info)
    for i, v in pairs(attrs) do
        allAttr[i] = (allAttr[i] or 0) + v
    end

    local arm_rune_attrsExport = {}
    --装备属性
    if character_info.arm_infos then
        for _, arm_info in ipairs(character_info.arm_infos) do
            local arm_attrs = UIUtils.GetEquipAttr(arm_info)
            for i, v in pairs(arm_attrs) do
                arm_rune_attrsExport[i] = (arm_rune_attrsExport[i] or 0) + v
            end
            --装备符文数据
            for i, arm_rune_info in ipairs(arm_info.arm_info.arm_rune_infos) do 
                local rune_id = arm_rune_info.rune_id
                local runeAttrs = UIUtils.GetRuneAttr(rune_id, arm_info, i)
                for _, runeAttr in pairs(runeAttrs) do
                    arm_rune_attrsExport[runeAttr.attrId] = (arm_rune_attrsExport[runeAttr.attrId] or 0) + runeAttr.attrValue
                end
            end
        end
    end

    --符文套装属性
    local rune_suit_attrs, skill_ids = UIUtils.GetCharacterRuneSuit(character_id)
    for i, v in pairs(rune_suit_attrs) do
        arm_rune_attrsExport[v.attrId] = (arm_rune_attrsExport[v.attrId] or 0) + v.attrValue
        allAttr[v.attrId] = (allAttr[v.attrId] or 0) + v.attrValue
    end
    
    local attrsEx, weaponAttrs = UIUtils.GetCharacterAttrEx(character_id)
    for i, v in pairs(attrsEx) do
        allAttr[i] = (allAttr[i] or 0) + v
    end

    --武器的攻击数值 统计到基础里面
    for i, v in pairs(weaponAttrs) do
        attrs[i] =  (attrs[i] or 0) + (v or 0)
    end

    ----------------------------------------------------------------------
    if fixAttr then
        --所有属性 = （基础属性 + 额外属性） * 修正的值
        arm_rune_attrsExport = UIUtils.FixAttribute(allAttr, arm_rune_attrsExport)

        --额外属性 = 所有属性 - 基础属性 = 加成
        attrsEx = {}
        for i, v in pairs(arm_rune_attrsExport) do
            attrsEx[i] = v - (attrs[i] or 0)
        end
        return attrsEx
    else
        return arm_rune_attrsExport
    end
end

function UIUtils.GetCharacterAllAttr(character_id, fixAttr)
    fixAttr = fixAttr or false
    local allAttr = {}
    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return allAttr
    end

    -- character
    local character_level = UIUtils.GetCharacterLevel(character_id, character_info.break_times, character_info.exp)
    local attrs = UIUtils.GetCharacterAttr(character_id, character_level, character_info.break_times, character_info)
    
    for i, v in pairs(attrs) do
        allAttr[i] = (allAttr[i] or 0) + v
    end
    
    local attrsEx, weaponAttrs = UIUtils.GetCharacterAttrEx(character_id)
    for i, v in pairs(attrsEx) do
        allAttr[i] = (allAttr[i] or 0) + v
    end

    --符文套装属性
    local rune_suit_attrs, skill_ids = UIUtils.GetCharacterRuneSuit(character_id)
    for i, v in pairs(rune_suit_attrs) do
        allAttr[v.attrId] = (allAttr[v.attrId] or 0) + v.attrValue
    end
    ----------------------------------------------------------------------
    if fixAttr then
        --武器的攻击数值 统计到基础里面
        attrs[1002] =  (attrs[1002] or 0) + (weaponAttrs[1002] or 0)
        
        --所有属性 = （基础属性 + 额外属性） * 修正的值
        allAttr = UIUtils.FixAttribute(allAttr, allAttr)

        --额外属性 = 所有属性 - 基础属性 = 加成
        attrsEx = {}
        for i, v in pairs(allAttr) do
            attrsEx[i] = v - (attrs[i] or 0)
        end
    end

    return allAttr, attrs, attrsEx
end

--面板属性值
function UIUtils.FixAttribute(attrs, allAttr)
    local newAttrs = {}
    for attrId, attrValue in pairs(attrs) do
        if attrId == 1001 then --生命上限 * (1 + HealthBonus) * (1 - HealthReduce)
            newAttrs[attrId] = attrValue * (1 + (allAttr[1049] or 0)) * (1 - (allAttr[1052] or 0))
        elseif attrId == 1002 then --攻击力 * (1 + AttackBonus) * (1 - AttackReduce)
            newAttrs[attrId] = attrValue * (1 + (allAttr[1003] or 0)) * (1 - (allAttr[1053] or 0))
        elseif attrId == 1024 then --物理防御 * (1 + physicalDefenseBonus) * (1 - physicalDefenseReduce)
            newAttrs[attrId] = attrValue * (1 + (allAttr[1026] or 0)) * (1 - (allAttr[1004] or 0))
        elseif attrId == 1025 then --魔法防御 * (1 + magicDefenseBonus) * (1 - magicDefenseReduce)
            newAttrs[attrId] = attrValue * (1 + (allAttr[1027] or 0)) * (1 - (allAttr[1005] or 0))
        else
            newAttrs[attrId] = attrValue
        end
    end
    return newAttrs
end

function UIUtils.GetTempCharacterAllAttr(character_info)
    if not character_info then return {}, {}, {} end
    local allAttr = {}
    local character_level = UIUtils.GetCharacterLevel(character_info.character_id, character_info.break_times, character_info.exp)
    local attrs = UIUtils.GetCharacterAttr(character_info.character_id, character_level, character_info.break_times, character_info)

    for i, v in pairs(attrs) do
        allAttr[i] = (allAttr[i] or 0) + v
    end
    
    local attrsEx, weaponAttrs = UIUtils.GetCharacterAttrEx(character_id, character_info)
    for i, v in pairs(attrsEx) do
        allAttr[i] = (allAttr[i] or 0) + v
    end

    --符文套装属性
    local rune_suit_attrs, skill_ids = UIUtils.GetCharacterRuneSuit(character_id, character_info)
    for i, v in pairs(rune_suit_attrs) do
        allAttr[v.attrId] = (allAttr[v.attrId] or 0) + v.attrValue
    end
    ----------------------------------------------------------------------
    if fixAttr then
        --武器的攻击数值 统计到基础里面
        attrs[1002] =  (attrs[1002] or 0) + (weaponAttrs[1002] or 0)
        
        --所有属性 = （基础属性 + 额外属性） * 修正的值
        allAttr = UIUtils.FixAttribute(allAttr, allAttr)

        --额外属性 = 所有属性 - 基础属性 = 加成
        attrsEx = {}
        for i, v in pairs(allAttr) do
            attrsEx[i] = v - (attrs[i] or 0)
        end
    end

    return allAttr, attrs, attrsEx
end

---------------------------------------------------------------------------
---技能
---获取技能 d_skill_fight_level 配置
function UIUtils.GetSkillFightLvConfig(skillId, skillLv)
    local lv = skillLv <= 0 and 1 or skillLv
    local d_skill_fight_level = require("ClientDatas.d_skill_fight_level")
    for _, config in pairs(d_skill_fight_level) do 
        if config.skillId == skillId and config.skillLevel == lv then
            return config
        end
    end
    return nil
end

function UIUtils.GetSkillMaxLv(skillId)
    local max_level = 1
    local d_skill_fight_level = require("ClientDatas.d_skill_fight_level")
    for _, config in pairs(d_skill_fight_level) do 
        if config.skillId == skillId and config.skillLevel > max_level then
            max_level = config.skillLevel
        end
    end
    --print("===max skill:" .. tostring(skillId) .. ",max;" .. tostring(max_level))
    return max_level
end

--获取指定技能id的名字
function UIUtils.GetSkillNameById(skill_id)
    local skillConfig = require('ClientDatas.d_skill')[skill_id]
    if skillConfig then
        return Database.L10n(skillConfig.skillName)
    end
    return ""
end

UIUtils.ESkillType = 
{
    Character = 1, --角色技能
    Weapon = 2, --武器技能 
    Equip = 3, --装备技能
    Item = 4, --道具技能
    Talent = 5, --天赋技能
}

UIUtils.ETalentSkillSubType = 
{
    TalentAdd = 1, --天赋等级累加
    TalentMax = 2, --天赋最大等级
}

function UIUtils.IsUnlockSkill(characterId, skillId, condition)
    local d_skill = require("ClientDatas.d_skill")
    local skillConfig = d_skill[skillId]
    if skillConfig then
        if skillConfig.skillType == UIUtils.ESkillType.Talent then --天赋技能
            --获取角色天赋列表 是否激活了该技能
            local talentSkill = UIUtils.GetTalentSkillInfo(characterId)
            if talentSkill and talentSkill[skillId] then
                return true, ''
            end
        end
    end
    return UIUtils.IsUnlock(characterId, condition)
end

UIUtils.EUnlockType = 
{
    Lv = 1, --等级解锁
};

--解锁类型判断
function UIUtils.IsUnlock(characterId, condition)
    local unlock = true --默认解锁
    local tips = ""
    if not characterId or 
        not condition or 
        condition == '' or 
        type(condition) ~= 'table' then 
        return unlock, tips 
    end
  
    for i = 1, #condition, 2 do 
        local unlockType = tonumber(condition[i])
        local unlockValue = tonumber(condition[i + 1])
        if unlockType == UIUtils.EUnlockType.Lv then
            local charLv = UIUtils.GetLevelByCharacterId(characterId)
            if charLv < unlockValue then
                tips = string.format(Database.L10n(504401), unlockValue)
                return false, tips
            end
        end
    end
   
    return unlock, tips
end

--获取所有解锁状态和条件描述
function UIUtils.GetUnlockCondition(characterId, condition)
    local unlock = true --默认是否全部解锁
    local unlockCondition = {}
    if not characterId or  not condition or  condition == '' or  type(condition) ~= 'table' then 
        return unlock, unlockCondition 
    end
    
    for i = 1, #condition, 2 do 
        local unlockType = tonumber(condition[i])
        local unlockValue = tonumber(condition[i + 1])
        if unlockType == UIUtils.EUnlockType.Lv then
            local charLv = UIUtils.GetLevelByCharacterId(characterId)
            local data = {
                isUnlock = charLv >= unlockValue, --当前条件是否解锁
                tips = string.format(Database.L10n(504401), unlockValue) --解锁条件描述
            }
            table.insert(unlockCondition, data)
            if charLv < unlockValue then
                unlock = false
            end
        end
    end
    return unlock, unlockCondition
end

--解析材料配置列表
function UIUtils.ParseMatrailConfig(materail)
    local currencyList = {} --货币类型
    local matList = {} --道具类型
    local bIsFull = true --材料是否满足
    if materail then
        for i = 1, #materail, 2 do 
            local itemId = materail[i]
            local needCount = materail[i + 1]
            local hasCount = BagSystem:GetInstance():GetItemCount(itemId)
            local config = UIUtils.GetItemConfigById(itemId)
            
            local item = {
                item_id = itemId,
                needCount = needCount,
                count = hasCount,
                config = config
            }
            if config.itemType == UIUtils.ItemMainType.Currency then
                table.insert(currencyList, item)
            else
                table.insert(matList, item)
            end
            if needCount > hasCount then
                bIsFull = false
            end
        end 
    end
 
    return currencyList, matList, bIsFull
end

function UIUtils.GetLevelByCharacterId(characterId)
    local chardata = CharacterSystem:GetInstance():GetCharacterInfoById(characterId)
    if not chardata then 
        return 0
    end
    --角色等级
    return UIUtils.GetCharacterLevel(chardata.character_id, chardata.break_times, chardata.exp)
end

function UIUtils.GetCharacterSkillLv(character_id, skill_id)
    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if charInfo and charInfo.skill_infos then
        for _, skillInfo in ipairs(charInfo.skill_infos) do
            if skillInfo.skill_id == skill_id then
                return skillInfo.skill_level
            end
        end
    end
    return 0
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
---角色天赋
function UIUtils.GetTalentAddAttr(character_id, char_info)
    local allAttr = {}
    local character_info = char_info or CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return allAttr
    end
    local d_attributes = require('ClientDatas.d_attributes')
    --天赋属性
    if character_info.talent_ids then
        for _, talent_id in ipairs(character_info.talent_ids) do
            local talentConfig = UIUtils.GetTalentConfig(talent_id, character_id)
            if talentConfig.inbornEffect == UIUtils.CharTalentEffectType.Atrribute then
                for i = 1, #talentConfig.inbornEffectPrice, 2 do 
                    local attrId = talentConfig.inbornEffectPrice[i]
                    local attrValue =  talentConfig.inbornEffectPrice[i + 1]
                    --属性判定 放置配置错误
                    if d_attributes[attrId] then
                        local attrValueEx = UIUtils.GetAttributeValue(attrId, attrValue)
                        allAttr[attrId] = (allAttr[attrId] or 0) + attrValueEx
                    else
                        LOG_ERROR('---talentId is error:' .. tostring(talent_id) .. ", attr:" .. tostring(attrId) .. ",value:" .. tostring(attrValue))
                    end
                end 
            end
        end
    end
    return allAttr
end

function UIUtils.GetTalentConfig(tablent_id, character_id)
    local d_character_inborn = require("ClientDatas.d_character_inborn")
    for _, config in pairs(d_character_inborn) do
        if config.id == tablent_id and config.roleID == character_id then
            return config
        end
    end
    print('-------->Error:GetTalentConfig->talent_id:' .. tostring(tablent_id) .. ',character_id:' .. tostring(character_id))
    return nil
end

function UIUtils.GetTalentConfigByHole(hole, character_id)
    local d_character_inborn = require("ClientDatas.d_character_inborn")
    for _, config in pairs(d_character_inborn) do
        if config.hole == hole and config.roleID == character_id then
            return config
        end
    end
    return nil
end

function UIUtils.GetTalentInfo(character_id)
    local talentInfo = {}
    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return talentInfo
    end

    if character_info.talent_ids then
        --print("===激活的天赋列表:" .. tostring(table.dump(character_info.talent_ids, nil, 10)))
    end

    local d_character_inborn = require("ClientDatas.d_character_inborn")
    for _, config in pairs(d_character_inborn) do
        if config.roleID == character_id then
            local talenId = config.id
            local tInfo = {
                isActived = UIUtils.TalentIsActive(talenId, character_id),
                isPreActived = UIUtils.PrevTalentIsActive(talenId, character_id),
            }
            talentInfo[talenId] = tInfo
        end
    end
    return talentInfo
end

function UIUtils.TalentIsActive(talent_id, character_id)
    local character_info = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if not character_info then
        return false
    end
    if character_info.talent_ids then
        for _, talentId in ipairs(character_info.talent_ids) do
            if talentId == talent_id then
                return true
            end
        end
    end
    return false
end

function UIUtils.PrevTalentIsActive(talent_id, character_id)
    local talentConfig = UIUtils.GetTalentConfig(talent_id, character_id)
    if talentConfig.frontHole == 0 then
        return true
    end
    local prevConfig = UIUtils.GetTalentConfigByHole(talentConfig.frontHole, character_id)
    if not prevConfig then
        return true
    end
    -- print("===talentId:" .. tostring(talent_id) .. ",prev:" .. tostring(prevConfig.id))
    return UIUtils.TalentIsActive(prevConfig.id, character_id)
end

UIUtils.CharTalentEffectType = 
{
    Item = 1, --奖励道具
    Skill = 2, --技能等级
    Characteristic = 3, --特质等级
    Atrribute = 4, --增加属性
};

function UIUtils.GetAttributeValue(attrId, value)
    value = value or 0
    local d_attributes = require("ClientDatas.d_attributes")
    local config = d_attributes[attrId]
    if config then
        if config.types == UIUtils.AttributeType.AbsoluteValue then
            return value
        elseif config.types == UIUtils.AttributeType.OverAHundred then
            return value / 10000
        elseif config.types == UIUtils.AttributeType.InAHundred then
            return math.min(1, value / 10000)
        end
    end
    return value
end

--天赋解锁效果
function UIUtils.GetTalentEffect(effectType, effectPrice)
    local itemInfo = {}
    if effectType == UIUtils.CharTalentEffectType.Item then
        for i = 1, #effectPrice, 3 do 
            local itemId = effectPrice[i]
            local count = effectPrice[i + 2]
            table.insert(itemInfo, {
                type = effectType,
                id = itemId, 
                value = count,
                config = UIUtils.GetItemConfigById(itemId)
            })
        end 
    elseif effectType == UIUtils.CharTalentEffectType.Skill then
        for i = 1, #effectPrice, 2 do 
            local skillId = effectPrice[i]
            local skillLv = effectPrice[i + 1]
            table.insert(itemInfo, {
                type = effectType,
                id = skillId, 
                value = skillLv
            })
        end 
    elseif effectType == UIUtils.CharTalentEffectType.Characteristic then
        for i = 1, #effectPrice, 2 do 
            local characteristicId = effectPrice[i]
            local characteristicLv = effectPrice[i + 1]
            table.insert(itemInfo, {
                type = effectType,
                id = characteristicId, 
                value = characteristicLv
            })
        end 
    elseif effectType == UIUtils.CharTalentEffectType.Atrribute then
        for i = 1, #effectPrice, 2 do 
            local attrId = effectPrice[i]
            local attrValue = UIUtils.GetAttributeValue(attrId, effectPrice[i + 1])
            table.insert(itemInfo, {
                type = effectType,
                id = attrId, 
                value = attrValue
            })
        end
    else

    end
    return itemInfo
end

--天赋激活条件
function UIUtils.GetTalentUnlock(character_id, openNeed, openNeedPrice, text)
    return UIUtils.ComOpenType(character_id, openNeed, openNeedPrice, text)
end

--计算天赋附加特性等级
function UIUtils.GetTalentEffectCharacteristicLv(character_id)
    local characteristicList = {}
    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if charInfo and charInfo.talent_ids then
        for _, talentId in ipairs(charInfo.talent_ids) do
            local talentConfig = UIUtils.GetTalentConfig(talentId, character_id)
            if talentConfig then
                if talentConfig.inbornEffect == UIUtils.CharTalentEffectType.Characteristic then
                    for i = 1, #talentConfig.inbornEffectPrice, 2 do 
                        local characteristicId = talentConfig.inbornEffectPrice[i]
                        local characteristicLv = talentConfig.inbornEffectPrice[i + 1]
                        characteristicList[characteristicId] = math.max(characteristicList[characteristicId] or 0, characteristicLv)
                    end 
                end
            end
        end
    end
    return characteristicList
end

function UIUtils.GetTalentSkillInfo(character_id, char_Info)
    local skillList = {}

    local charInfo = char_Info or CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if charInfo and charInfo.talent_ids then
        for _, talentId in ipairs(charInfo.talent_ids) do
            local talentConfig = UIUtils.GetTalentConfig(talentId, character_id)
            if talentConfig then
                if talentConfig.inbornEffect == UIUtils.CharTalentEffectType.Skill then
                    for i = 1, #talentConfig.inbornEffectPrice, 2 do 
                        local skillId = talentConfig.inbornEffectPrice[i]
                        local skillLv = talentConfig.inbornEffectPrice[i + 1]
                        --获取技能类型
                        local skillConfig = require('ClientDatas.d_skill')[skillId]
                        if not skillList[skillId] then
                            skillList[skillId] = {}
                        end 

                        if skillConfig and skillConfig.skillType == UIUtils.ESkillType.Talent and skillConfig.subType == UIUtils.ETalentSkillSubType.TalentAdd then
                            table.insert(skillList[skillId], skillLv)
                        else
                            skillList[skillId][1] = math.max(skillList[skillId][1] or 0, skillLv)
                        end
                    end 
                end
            end
        end
    end
    return skillList
end

function UIUtils.GetTalentSkillParams(skillId, skillLvs) 
    local skillConfig = require('ClientDatas.d_skill')[skillId]
    local splitList = string.split(skillConfig.rateShow, ',')

    local valueTab = {}
    for _, skillLv in ipairs(skillLvs) do 
        local skillLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
        if skillLvConfig then
            local paramsArr = string.split(skillLvConfig.inbornSkill, ',')
            for idx, pStr in ipairs(splitList) do 
                local value = tonumber(paramsArr[idx]) or 0
                if pStr == "$%" then
                    local intValue, _ = value / 100 --math.modf(value / 100)
                    valueTab[idx] = (valueTab[idx] or 0) + intValue
                elseif pStr == "#%" then
                    valueTab[idx] = (valueTab[idx] or 0) + value
                else
                    valueTab[idx] = (valueTab[idx] or 0) + value
                end
            end
        end
    end

    for idx, pStr in ipairs(splitList) do 
        if string.endswith(pStr, '%') and valueTab[idx] then
            valueTab[idx] = string.format("%.1f", valueTab[idx]) .. '%'
        end
    end

    return valueTab
end

--给蓝图的
function UIUtils.GetTalentSkillParamsEx(skillId, skillLvs) 
    local skillConfig = require('ClientDatas.d_skill')[skillId]
    local splitList = string.split(skillConfig.rateShow, ',')

    local valueTab = {}
    for _, skillLv in ipairs(skillLvs) do 
        local skillLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
        if skillLvConfig then
            local paramsArr = string.split(skillLvConfig.inbornSkill, ',')
            for idx, pStr in ipairs(splitList) do 
                local value = tonumber(paramsArr[idx]) or 0
                if pStr == "$%" then
                    local intValue = value / 10000
                    valueTab[idx] = (valueTab[idx] or 0) + intValue
                elseif pStr == "#%" then
                    local intValue = value / 10000
                    valueTab[idx] = (valueTab[idx] or 0) + intValue
                else
                    valueTab[idx] = (valueTab[idx] or 0) + value
                end
            end
        end
    end

    return valueTab
end

---------------------------------------------------------------------------
---装扮
--获取保存的机甲和角色装扮id
function UIUtils.GetIdolAndCharMeshByCharacterId(character_id)
    local defaultIdolId = 0
    local defautlCharId = 0
    local defaultCityCharId = 0
    local d_char_clothes = require("ClientDatas.d_char_clothes")
    for k, v in pairs(d_char_clothes) do
        if v.charBelong == character_id and v.dressInitial == 1 then
            if v.dressType == 3 then
                defaultCityCharId = v.id
            elseif v.dressType == 2 then
                defaultIdolId = v.id
            else
                defautlCharId = v.id
            end
        end
    end

    local saveIdolId = 0
    local saveCharId = 0
    local saveCityCharId = 0
    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(character_id)
    if charInfo then
        saveIdolId = charInfo.mecha_skin_id == 0 and defaultIdolId or charInfo.mecha_skin_id
        saveCharId = charInfo.character_skin_id == 0 and defautlCharId or charInfo.character_skin_id
        saveCityCharId = charInfo.city_skin_id == 0 and defaultCityCharId or charInfo.city_skin_id
    end

    return saveIdolId, saveCharId, saveCityCharId, defaultIdolId, defautlCharId, defaultCityCharId
end

---------------------------------------------------------------------------
---常用
--- 将slot锚点设置到中心
---@param slot UCanvasPanelSlot
function UIUtils.SetAnchorPositionToCenter(slot)
    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()

    anchors.Maximum = UE.FVector2D(0.5, 0.5)
    anchors.Minimum = UE.FVector2D(0.5, 0.5)

    slot:SetAnchors(anchors)
    slot:SetOffsets(offsets)
end

function UIUtils.SetAnchorPositionToFullScreen(slot)
    local anchors = UE.FAnchors()
    local offsets = UE.FMargin()

    anchors.Minimum = UE.FVector2D(0, 0)
    anchors.Maximum = UE.FVector2D(1, 1)

    slot:SetAnchors(anchors)
    slot:SetOffsets(offsets)
end

--通知弹框
function UIUtils.ShowComNotice(text, context, OkCallBack, CancleCallBack)
    UIManager:GetInstance():ShowConfirm({
        notice = text,
        confirm = function()
            if OkCallBack then
                OkCallBack()
            end
        end,
        cancel = function()
            CancleCallBack()
        end,
        showCancel = CancleCallBack ~= nil,
    })
end

function UIUtils.GetDayOfWeek()
    local today = UE.UKismetMathLibrary.Today()
    local year = UE.UKismetMathLibrary.GetYear(today)
    local month = UE.UKismetMathLibrary.GetMonth(today)
    local day = UE.UKismetMathLibrary.GetDay(today)
    local C = math.floor(year / 100)
    year = year % 100

    if month == 1 or month == 2 then
        month = month + 12
        if year == 0 then
            year = 99
            C = C - 1
        else
            year = year - 1
        end
    end
 
    local w = (math.floor(C / 4) - 2 * C + year + math.floor(year / 4) + math.floor(26 * (month + 1) / 10) + day - 1) % 7
    if w == 0 then
        w = 7
    end
    return w
end

function UIUtils.ShowGetRewardCommonUI(WorldContext, RewardList)
    local ui = UE.UGameplayStatics.GetGameInstance(WorldContext):AddUMG('UI_GetItem_Notice')

    if RewardList then
        for _, rewardInfo in pairs(RewardList) do
            local itemConfig = UIUtils.GetItemConfigById(rewardInfo.itemId)
            if itemConfig then
                local item_ui = UE.UWidgetBlueprintLibrary.Create(WorldContext, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
                item_ui.TextName:SetText(Database.L10n(itemConfig.itemName))
                item_ui.TextNum:SetText(rewardInfo.count)
                --稀有度背景图片
                if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                    local strArr = string.split(itemConfig.rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        item_ui.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
    
                --icon
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        item_ui.icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                item_ui.Img_bg.OnMouseButtonDownEvent:Unbind()
                item_ui.Img_bg.OnMouseButtonDownEvent:Bind(WorldContext, function()
                    UIUtils.ShowItemInfo(rewardInfo.itemId, rewardInfo.count, 20)
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)
                item_ui.ItemPanel:SetRenderOpacity(0)
                ui.ItemBox:AddChild(item_ui)
            end
        end
    end
    ui:PlayAnimationForward(ui.start, 1, false)
    ui:PlayItemAnim()

    return ui
end

--通用奖励物品弹框
function UIUtils.ShowItemInfo(itemid, count, extrInfo)
    local layers = UIManager:GetInstance().layers
    local gameInstance = layers:GetGameInstance()
    local ui = gameInstance:AddUMG('UI_ItemDetail')
    local itemConfig = UIUtils.GetItemConfigById(itemid)
    local item_data = {}
    item_data.item_id = itemid
    item_data.config = itemConfig
    item_data.count = UIUtils.GetItemCount(itemid)
    ui:RefreshUI(item_data, extrInfo)
end

--通用提示　
function UIUtils.ShowNotify(backUI, text)
    UIManager:GetInstance():Notify(text)
end

function UIUtils.ShowPlayerLevelUp(backUI, oldLevel, newLevel)
    print('----升级了:' .. tostring(oldLevel) .. ',newlevel:' .. tostring(newLevel))
    local gameInstance = UE.UGameplayStatics.GetGameInstance(backUI)
    gameInstance:RemoveUMG('UI_PlayerLevelUp')
    local ui = gameInstance:AddUMG('UI_PlayerLevelUp')
    ui.Text_Level:SetText(newLevel)
    local d_player_level = require('ClientDatas.d_player_level')
    local config = d_player_level[newLevel]
    if config and config.levelupHint > 0 then
        ui.Text_Unlock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        ui.Text_Unlock:SetText(Database.L10n(config.levelupHint))
    else
        ui.Text_Unlock:SetText('')
        ui.Text_Unlock:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    ui:BindToAnimationFinished(ui.In, function()
        gameInstance:RemoveUMG('UI_PlayerLevelUp')
    end)
    ui:PlayAnimationForward(ui.In)
    UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        {gameInstance, function()
            gameInstance:RemoveUMG('UI_PlayerLevelUp')
        end},
        2.5,
        false
    )
end 

function UIUtils.ShowSystemDes(id)
    local layers = UIManager:GetInstance().layers
    local gameInstance = layers:GetGameInstance()
    local ui = gameInstance:AddUMG('UI_SystemDescription')
    ui:RefreshUI(id)
end

----------------------------------------------------------------------
---任务
function UIUtils.GetTaskTypeName(taskType)
    print("===taskType:" .. tostring(taskType))
    if taskType == UIUtils.ETaskType.Daily then
        return "日常"
    elseif taskType == UIUtils.ETaskType.Main then
        return "主线"
    else
        return "支线"
    end
    return ""
end

function UIUtils.GetTaskConfigById()

end

----------------------------------------------------------------------
--- 通用解锁条件判断
UIUtils.EOpenNeedType = 
{
    DailyCopyCount = 10000, --打%s次任意日常本
    TotalWarFight = 10001, --总力战完成X次
    TowerCopyId = 10002, --对战塔到达X层
    CopyFinishCount = 10003, --副本关累计获得X次胜利
    FightCountInUniverse = 20000, --在宇宙进行%s次战斗
    BuildCountInUniverse = 20001, --在宇宙建造%s个建筑
    CostCountInUniverse = 20002, --在宇宙进行%s次探索
    BuyCountInUniverse = 20003, --在宇宙购买%s次建筑
    BuildTargetCountInUniverse = 20004, --在宇宙建造%s个带有「XX」词条的建筑
    BuildTraceCountInUniverse = 20005, --在宇宙建造%s个带有「XX」种族的建筑
    SRPGCount = 20006, --进行X局SRPG
    SRPGRecord = 20007, --单局积分到达X
    SRPGDifficulty = 20008, --完成某难度的SRPG
    SRPGCardDemolition = 20009, --在宇宙拆毁若干张卡牌
    SRPGCardUpgrade = 20010,--在宇宙晋升若干张卡牌
    SRPGChangeCharacter = 20011, --在宇宙替换%s次出场角色
    CharLevel = 30000, --XX角色等级升至X级
    CharSkillLv = 30001, --XX技能升至X级
    CharLevelCount = 30002, --X名角色等级升至X级
    CharSkillLvCount = 30003, --X名角色任意技能技能升至X
    CharTalentCount = 30004, --X名角色天赋点亮X个
    CharWeaponLvCount = 30005, --X件武器升至X级
    CharEquipLvCount = 30006, --X件装备升至X级
    Shopping = 30007, --买若干个特定道具
    UnlockTalent = 30008, --点亮一个星位
    DiamondCount = 30009, --当单局结算后RMB钻超过N个
    SpecifyShopping = 30010, --购买特定的商店的任意物品
    MainQuestChapter = 40000,--主线剧情完成X章X节
    CostGold = 50000,--消耗%s金币
    ForgeCount = 50001,--进行%s次装备锻造
    DecomposeCount = 50002,--进行%s次熔炉拆解
    Login = 50003,--登录游戏
    CostItem = 50004, --【消耗条件区别于检测条件】消耗%s道具（含金币）
    HaveChar = 50005, --拥有某角色
    RewardBook = 50006,--完成若干个任务
    SyntheticCount = 50007,
    CompletedDailyMission = 50008, --完成若干个日常任务
    Dialog = 60001,-- 60001
    PlayerLevel = 60002, --玩家等级大于等于某等级
    CompleteFight = 60003, --完成某场战斗
    CompleteUniverseTrip = 60004, --完成某段宇宙航行
    CompleteSpecialSRPG = 60005, --完成某个剧情星图
    SelectPanel = 60006, --在剧情选择界面完成剧情跳转
    STTButton = 60007, --点击特定按钮
    BuildActor = 60008,--完成家具交互
    OpenUI = 60009,--打开某个ui/系统连接
    SRPGGrowth = 60010, --肉鸽局外养成加点x次
    Gacha = 60011, --抽卡次数
    BuildCreate = 60012, --摆放指定id的家具
}

function UIUtils.ComOpenType(character_id, openNeed, openNeedPrice, text)
    local isFullUnlock = true
    local unlockInfo = {} --条件提示/道具类型
    local exInfo = {} --货币类型
    if openNeed == UIUtils.EOpenNeedType.CharLevel then --角色等级升到x级
        for i = 1, #openNeedPrice, 2 do 
            local charId = openNeedPrice[i]
            local charLv = openNeedPrice[i + 1]
            local hasCharLv = UIUtils.GetLevelByCharacterId(charId)
            table.insert(unlockInfo, {
                ['isUnlock'] = hasCharLv >= charLv,
                ['tip'] = string.format(Database.L10n(text), charLv)
            })
            if hasCharLv < charLv then
                isFullUnlock = false
            end
        end 
    elseif openNeed == UIUtils.EOpenNeedType.CharSkillLv then --某技能升至x级
        for i = 1, #openNeedPrice, 2 do 
            local skillId = openNeedPrice[i]
            local skillLv = openNeedPrice[i + 1]
            local hasSkillLv = UIUtils.GetCharacterSkillLv(character_id, skillId)
            table.insert(unlockInfo, {
                ['isUnlock'] = hasSkillLv >= skillLv,
                ['tip'] = string.format(Database.L10n(text), UIUtils.GetSkillNameById(skillId), skillLv)
            })
            if hasSkillLv < skillLv then
                isFullUnlock = false
            end
        end 
    elseif openNeed == UIUtils.EOpenNeedType.CostItem then --消耗xx道具
        for i = 1, #openNeedPrice, 2 do 
            local itemId = openNeedPrice[i]
            local itemCount = openNeedPrice[i + 1]
            local hasCount = BagSystem:GetInstance():GetItemCount(itemId)
            local config = UIUtils.GetItemConfigById(itemId)
            local itemInfo = {
                ['isUnlock'] = hasCount >= itemCount,
                ['tip'] = "",
                ['item_id'] = itemId,
                ['count'] = itemCount,
                ['hasCount'] = hasCount,
                ['config'] = config,
            }
            if config.itemType == UIUtils.ItemMainType.Currency then
                table.insert(exInfo, itemInfo)
            else
                table.insert(unlockInfo, itemInfo)
            end
            
            if hasCount < itemCount then
                isFullUnlock = false
            end
        end 
    elseif openNeed == UIUtils.EOpenNeedType.HaveChar then --拥有某角色
        for i = 1, #openNeedPrice, 1 do 
            local charId = openNeedPrice[i]
            local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
            local d_character = require "ClientDatas.d_character"
            table.insert(unlockInfo, {
                ['isUnlock'] = charInfo ~= nil,
                ['tip'] = string.format(Database.L10n(text), Database.L10n(d_character[charId].name))
            })
            if not charInfo then
                isFullUnlock = false
            end
        end
    elseif openNeed == UIUtils.EOpenNeedType.PlayerLevel then
        local needPlayerLevel = openNeedPrice[1]
        local PlayerSystem = require('Module.Player.PlayerSystem')
        local playerLevel = PlayerSystem:GetInstance().Level
        table.insert(unlockInfo, {
            ['isUnlock'] = needPlayerLevel >= playerLevel,
            ['tip'] = string.format(Database.L10n(text), needPlayerLevel)
        })
        if playerLevel < needPlayerLevel then
            isFullUnlock = false
        end  
    end
    return isFullUnlock, unlockInfo, exInfo
end 

function UIUtils.IsAndroidOrIOS()
    local platformName = UE.UGameplayStatics.GetPlatformName() 
    return platformName == "Android" or platformName == "IOS" 
end

function UIUtils.ReplacePlayerName(showText)
    local PlayerSystem = require "Module.Player.PlayerSystem"
    if string.find(showText, "{name}") then
        local player_sequence_name = PlayerSystem:GetInstance().PlayerInfo.player_sequence_name 
        if player_sequence_name and player_sequence_name ~= "" then
            showText = string.gsub(showText, "{name}", player_sequence_name)
        end
    end
    return showText
end

----------------------------------------------------------------------
---解析技能数值
function UIUtils.ParseSkillParams(skillId, skillLv)
    local function SplitByChar(str)
        local result = {}
        local tempList = string.split(str, "$%")
        local count = #tempList
        for idx, v in ipairs(tempList) do
            if v == "" then
                if idx ~= count then
                    table.insert(result, "$%")
                end
            else
                local strList = string.split(v, "#")
                local strCount = #strList
                for strIdx, str in ipairs(strList) do
                    if str == "" then
                        if strIdx ~= strCount then
                            table.insert(result, "#")
                        end
                    else
                        table.insert(result, str)
                        if strIdx ~= strCount then
                            table.insert(result, "#")
                        end
                    end
                end
                if idx ~= count then
                    table.insert(result, "$%")
                end
            end
        end
        return result
    end

    local skillConfig = require("ClientDatas.d_skill")[skillId]
    local skillFightLvConfig = UIUtils.GetSkillFightLvConfig(skillId, skillLv)
    --解析描述分段
    local descList = {}
    if skillConfig.paramsItem and skillConfig.paramsItem ~= '' then
        local tarString = Database.L10n(skillConfig.paramsItem)
        --去掉换行符号
        tarString = string.gsub(tarString, "\n", "")
        --去掉空格
        tarString = string.gsub(tarString, "%s", "")
        descList = string.split(tarString, '|')
        -- print('===paramsItem:' .. tostring(table.dump(descList, false, 10)))
    end
    --解析格式
    local splitList = {}
    if skillConfig.rateShow and skillConfig.rateShow ~= '' then
        local tarString = skillConfig.rateShow
        --去掉换行符号
        tarString = string.gsub(tarString, "\n", "")
        --去掉空格
        tarString = string.gsub(tarString, "%s", "")
        splitList = string.split(tarString, '|')
        -- print('===rateShow:' .. tostring(table.dump(splitList, false, 10)))
    end
    --等级数值
    local valueList = {}
    if skillFightLvConfig and skillFightLvConfig.clickDamage then
        valueList = skillFightLvConfig.clickDamage
        for _, v in ipairs(skillFightLvConfig.pressDamage) do 
            table.insert(valueList, v)
        end
        -- print('===values:' .. tostring(table.dump(valueList, false, 10)))
    end
    --解析格式->填充数值
    local resultList = {}
    local posIndx = 1
    for _, splitStr in ipairs(splitList) do 
        --print('==str:' .. tostring(splitStr))
        local tempList = SplitByChar(splitStr)
        --print('===tempList:' .. tostring(table.dump(tempList, false, 10)))
        local resultStr = ''
        for _, tempStr in ipairs(tempList) do 
            if tempStr == "$%" then --百分比
                local intValue, _ = (valueList[posIndx] or 0) / 100-- math.modf((valueList[posIndx] or 0) / 100)
                posIndx = posIndx + 1
                local tempValue = string.format("%.1f", intValue) .. '%'
                if resultStr == '' then
                    resultStr = tempValue
                else
                    resultStr = resultStr .. tempValue
                end
            elseif tempStr == "#%" then --百分比
                local intValue, _ = valueList[posIndx] or 0
                posIndx = posIndx + 1
                local tempValue = string.format("%.1f", intValue) .. '%'
                if resultStr == '' then
                    resultStr = tempValue
                else
                    resultStr = resultStr .. tempValue
                end
            elseif tempStr == "#" then --纯值
                local tempValue = valueList[posIndx] or 0
                posIndx = posIndx + 1
                if resultStr == '' then
                    resultStr = tempValue
                else
                    resultStr = resultStr  .. tempValue
                end
            else--格式默认值
                if resultStr == '' then
                    resultStr = tempStr
                else
                    resultStr = resultStr .. tempStr
                end
            end
        end
        table.insert(resultList, resultStr)
    end
    --print('===resultList:' .. tostring(table.dump(resultList, false, 10)))
    return descList, resultList
end

---服务器函数, 获取pick物品刷新时间
function UIUtils.get_days_refresh(pre_time, days)
    local PlayerSystem = require('Module.Player.PlayerSystem')
    local now = PlayerSystem:GetInstance():GetServerTime()
    local new_time = 0
    for _, day in ipairs(days) do
        local temp_date = os.date("*t", now)
        temp_date.day = day
        temp_date.hour = 4
        temp_date.min = 0
        temp_date.sec = 0
        local temp_time = os.time(temp_date)
        temp_date = os.date("*t", temp_time)
        -- valid date
        if temp_date.day == day then
            if temp_time > pre_time and now >= temp_time then
                new_time = math.max(new_time, temp_time)
            end
        end
    end
    if new_time == 0 then
        -- last month
        local last_date = os.date("*t", now)
        last_date.day = 1
        last_date.hour = 0
        last_date.min = 0
        last_date.sec = 0
        local last_time = os.time(last_date) - 1
        local max_time
        for _, day in ipairs(days) do
            local temp_date = os.date("*t", last_time)
            temp_date.day = day
            temp_date.hour = 4
            temp_date.min = 0
            temp_date.sec = 0
            local temp_time = os.time(temp_date)
            temp_date = os.date("*t", temp_time)
            -- valid date
            if temp_date.day == day then
                max_time = max_time and math.max(max_time, temp_time) or temp_time
            end
        end
        if max_time > pre_time then
            new_time = max_time
        end
    end
    return new_time
end

---获取刷新时间
function UIUtils.get_daily_refresh(pre_time)
    local PlayerSystem = require('Module.Player.PlayerSystem')
    local now = PlayerSystem:GetInstance():GetServerTime()
    local temp_date = os.date("*t", now)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time and now >= temp_time then
        return temp_time
    end
    -- last day
    local last_date = os.date("*t", now)
    last_date.hour = 0
    last_date.min = 0
    last_date.sec = 0
    local last_time = os.time(last_date) - 1
    local temp_date = os.date("*t", last_time)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time then
        return temp_time
    end
    return 0
end

-------------------------------------------------------
---解析富文本超链接
function UIUtils.ParaseRichTextLinkText(showText)
    local curStr = showText
    local result = {}
    local p1, p2 = 1, 1 
    local startPos = 1
    repeat
        p1, p2 = string.find(curStr, 'action=%b""', startPos)
        if p1 and p1 > 1 then
            local str = string.sub(curStr, p1, p2)
            local p3, p4 = string.find(str, '%b""')
            if p3 and p3 > 1 then
                str = string.sub(str, p3 + 1, p4 - 1)
                table.insert(result, str)
                startPos = p2
            end
        end
    until (not p1)

    return result
end

-------------------------------------------------------
---反解析角色信息

function UIUtils.GetSkillInfo(skillConfig)
    local result = {}
    for i = 1, #skillConfig, 2 do 
        local info = {
            skill_id = skillConfig[i],
            skill_level = skillConfig[i + 1]
        }
        table.insert(result, info) 
    end
    return result
end

function UIUtils.GetCharacterExpByLevel(charId, lv)
    local allExp = 0
    local d_role_level = require('ClientDatas.d_role_level')
    for id, v in ipairs(d_role_level) do
        if id < lv then
            allExp = allExp + v.exp
        end
    end
    return allExp
end

function UIUtils.GetCharacterBreakTimesByLevel(charId, lv)
    local breakTimes = 0
    local d_role_levelbreak = require('ClientDatas.d_role_levelbreak')
    for _, config in ipairs(d_role_levelbreak) do
        if config.roleId == charId then
            if config.level <= lv then
                breakTimes = config.levelbreak
            end
        end
    end
    return breakTimes
end

function UIUtils.GetWeaponExpByLevel(weaponId, lv) 
    local config = UIUtils.GetItemConfigById(weaponId)
    local rarity = config and config.rarity or 1
    local allExp = 0
    local d_weapon_level = require('ClientDatas.d_weapon_level')
    for id, v in ipairs(d_weapon_level) do
        if id < lv then
            allExp = allExp + (v['exp' .. tostring(rarity)] or 0)
        end
    end
    return allExp
end

function UIUtils.GetWeaponBreakTimesByLevel(weaponId, lv) 
    local breakTimes = 0
    local d_weapon_levelbreak = require('ClientDatas.d_weapon_levelbreak')
    for _, config in ipairs(d_weapon_levelbreak) do
        if weaponId == config.weaponId then
            if config.level <= lv then
                breakTimes = config.levelbreak
            end
        end
    end
    return breakTimes
end

----------------------------------------------------------
---临时角色数据
function UIUtils.BuildCharInfo(roleId, roleLv, firstWeapon, roleSkill, roleInborn)
    --生成临时角色数据
    local charInfo = {
        arm_infos = {} --[[table: 00000956AE557350]],
        break_times = UIUtils.GetCharacterBreakTimesByLevel(roleId, roleLv),
        character_id = roleId,
        character_skin_id = 0,
        city_skin_id = 0,
        exp = UIUtils.GetCharacterExpByLevel(roleId, roleLv),
        mecha_skin_id = 0,
        own_character_skin_ids = {},
        own_city_skin_ids = {},
        own_mecha_skin_ids = {},
        skill_infos = UIUtils.GetSkillInfo(roleSkill),
        talent_ids = roleInborn,
        weapon_info = {
            count = 1,
            item_extra = "weapon_info",
            item_id = firstWeapon[1],
            item_uuid = 0,
            weapon_info = {
                break_times = UIUtils.GetWeaponBreakTimesByLevel(firstWeapon[1], firstWeapon[2]),
                exp = UIUtils.GetWeaponExpByLevel(firstWeapon[1], firstWeapon[2]) ,
                locked = false,
                refine_level = firstWeapon[3]
            }
        }
    }
    print('---buildcharInfo:' .. tostring(table.dump(charInfo, nil, 10)))
    return charInfo
end

function UIUtils.BuildCharInfoByTrainId(trainCharId)
    local d_character_trial = require('ClientDatas.d_character_trial')
    local config = d_character_trial[trainCharId]
    if config and config.roleTrialId then
        --生成临时角色数据
        return UIUtils.BuildCharInfo(config.roleTrialId, config.roleLevel, config.firstWeapon, config.roleSkill, config.roleInborn)
    end
    return nil
end

--获取挑战副本的描述文字
function UIUtils.GetSwitchText(switchId)
    local reuslt = ''
    local d_com_tutorial = require('ClientDatas.d_com_tutorial')
    local config = d_com_tutorial[switchId]
    if config then
        while(config) do
            reuslt = reuslt .. Database.L10n(config.text) .. '\n'
            if config.next > 0 then
                config = d_com_tutorial[config.next]
            else
                config = nil
            end
        end
    end
    return reuslt
end

--判定角色皮肤解锁
function UIUtils.CharSkinIsUnlock(charId, type, skinId)
    --判断角色皮肤解锁
    local isUnlock = false
    local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(charId)
    if charInfo then
        if type == 0 then --战斗皮肤
            for _, did in pairs(charInfo.own_character_skin_ids) do
                if did == skinId then
                    isUnlock = true
                    break
                end
            end
        elseif type == 1 then --战斗机甲
            for _, did in pairs(charInfo.own_mecha_skin_ids) do
                if did == skinId then
                    isUnlock = true
                    break
                end
            end
        else --主城皮肤
            for _, did in pairs(charInfo.own_city_skin_ids) do
                if did == skinId then
                    isUnlock = true
                    break
                end
            end
        end
    else
        return false, false
    end
    return true, isUnlock
end

--解析时间配置 2024-2-23 10:00:00 
function UIUtils.ParseTimeStr(str)
    local year, month, day, hour, min, sec = string.match(str, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    return os.time({year=year, month=month, day=day, hour=hour, min=min, sec=sec})
end

function UIUtils.GetDailyRefresh(pre_time)
    local PlayerSystem = require('Module.Player.PlayerSystem')
    local now = PlayerSystem:GetInstance():GetServerTime()
    local temp_date = os.date("*t", now)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time and now >= temp_time then
        return temp_time
    end
    -- last day
    local last_date = os.date("*t", now)
    last_date.hour = 0
    last_date.min = 0
    last_date.sec = 0
    local last_time = os.time(last_date) - 1
    local temp_date = os.date("*t", last_time)
    temp_date.hour = 4
    temp_date.min = nil
    temp_date.sec = nil
    local temp_time = os.time(temp_date)
    if temp_time > pre_time then
        return temp_time
    end
    return 0
end

function UIUtils.TriggerWidget(widget)
    if UE.UGameplayStatics.ObjectIsA(widget, UE.UGHSButton) then
        widget.OnGHSClicked:Broadcast()
    elseif UE.UGameplayStatics.ObjectIsA(widget, UE.UButton) then
        widget.OnClicked:Broadcast()
    elseif UE.UGameplayStatics.ObjectIsA(widget, UE.UGHSCheckBox) then
        widget:SetIsCheckedAndFireEvent(not widget:IsChecked())
    end
end

return UIUtils

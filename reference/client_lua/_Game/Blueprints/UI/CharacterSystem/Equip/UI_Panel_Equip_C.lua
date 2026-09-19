--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local d_attributes = require("ClientDatas.d_attributes")
local d_equip_rune = require("ClientDatas.d_equip_rune")
local BackpackSystem = require "Module.Backpack.BackpackSystem"

---@type UI_Panel_Equip_C
local M = UnLua.Class()

local EquipUIName = 
{
    "UI_Core",
    "UI_Lung",
    "UI_Kidney",
    "UI_Liver",
    "UI_Stomach",
    "UI_Brain",
}

local EquipIcon = 
{
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_heart_png.icon_heart_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_lungs_png.icon_lungs_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_kidney_png.icon_kidney_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_liver_png.icon_liver_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_stomach_png.icon_stomach_png',
    '/Game/_Game/TP_New/Character_Detail/Frames/icon_head_png.icon_head_png',
}

local ColorType = 
{
    --White
    {
        UE.FLinearColor(0.75, 0.75, 0.75, 1),
        UE.FLinearColor(0.8, 0.8, 0.8, 1),
        UE.FLinearColor(1.0, 1.0, 1.0, 1),
        UE.FLinearColor(0.55, 0.55, 0.55, 1),
        UE.FLinearColor(0.35, 0.35, 0.35, 1),
        UE.FLinearColor(0.75, 0.75, 0.75, 1),
    },

    --Green
    {
        UE.FLinearColor(0.527344, 0.75, 0.604199, 1),
        UE.FLinearColor(0.095834, 0.8, 0.447917, 1),
        UE.FLinearColor(0.086191, 0.907129, 0.973446, 1),
        UE.FLinearColor(0.0, 0.55, 0.183333, 1),
        UE.FLinearColor(0.0, 0.35, 0.116667, 1),
        UE.FLinearColor(0.054687, 0.75, 0.294332, 1),
    },
    
    --Yellow
    {
        UE.FLinearColor(1.1, 1.072309, 0.767708, 1),
        UE.FLinearColor(1.1, 0.877994, 0.211979, 1),
        UE.FLinearColor(0.973446, 0.921478, 0.349832, 1),
        UE.FLinearColor(1.1, 0.627345, 0.154688, 1),
        UE.FLinearColor(0.973446, 0.760505, 0.121681, 1),
        UE.FLinearColor(1.1, 0.840277, 0.320834, 1),
    }, 

    --Orange
    {
        UE.FLinearColor(1.0, 0.663195, 0.494792, 1),
        UE.FLinearColor(1.0, 0.320312, 0.093750, 1),
        UE.FLinearColor(1.0, 0.627604, 0.255208, 1),
        UE.FLinearColor(1.0, 0.181164, 0.040915, 1),
        UE.FLinearColor(1.0, 0.402344, 0.203125, 1),
        UE.FLinearColor(1.0, 0.402344, 0.203125, 1),
    },

    --Red
    {
        UE.FLinearColor(1.0, 0.825, 0.825, 1),
        UE.FLinearColor(1.0, 0.0875, 0.0875, 1),
        UE.FLinearColor(1.0, 0.302083, 0.302083, 1),
        UE.FLinearColor(1.0, 0.03125, 0.03125, 1),
        UE.FLinearColor(1.0, 0.223958, 0.223958, 1),
        UE.FLinearColor(1.0, 0.307292, 0.307292, 1),
    },
}

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.parent = nil
    self.select_equip = 0
    self.characterInfos = {}
    self.SelectedCharacterData = {}
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Equip_Arm", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Equip_Arm", self)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitUI()
    self.UI_Core.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.Heart)
    end)
    self.UI_Kidney.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.kidney)
    end)
    self.UI_Liver.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.Liver)
    end)
    self.UI_Stomach.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.Stomach)
    end)
    self.UI_Brain.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.Brain)
    end)
    self.UI_Lung.EquipBtn.OnGHSClicked:Add(self, function() 
        self:OnClicked_EuipItem(UIUtils.ItemEquipType.Lung)
    end)

    self.UI_itemlist_siderbar.Btn_Close:SetVisibility(UE.ESlateVisibility.Visible)

    self.UI_itemlist_siderbar.Btn_Close.OnGHSClicked:Add(self, function()
        self.UI_itemlist_siderbar:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_sub_EquipTotalAttr:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self[EquipUIName[self.select_equip]].Equipped:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self[EquipUIName[self.select_equip]].Selected:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[self.select_equip]].UI_Panel_Equip_VfxChoose:StopVFXAnimation()
        self.select_equip = 0
    end)

    self.UI_itemlist_siderbar.UI_Com_BagDetail.Btn_Replace.OnGHSClicked:Add(self, function()
        self:OnClicked_Replace(self.select_equip)
    end)
    self.UI_itemlist_siderbar.UI_Com_BagDetail.Btn_Level.OnGHSClicked:Add(self, function()
        self:OnClicked_Strengthen(self.select_equip)
    end)

    self.UI_itemlist_siderbar.UI_Com_ItemBox.Rune_1.OnClicked:Add(self, function()
        local rune_id = self.UI_itemlist_siderbar.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[1].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.UI_itemlist_siderbar.UI_Com_ItemBox.Rune_2.OnClicked:Add(self, function()
        local rune_id = self.UI_itemlist_siderbar.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[2].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    --UI_sub_EquipTotalAttr
    self.UI_sub_EquipTotalAttr.ButtonAttr.OnClicked:Add(self, function()
        if self.UI_sub_EquipTotalAttr.attr_list_display:IsVisible() then
            self.UI_sub_EquipTotalAttr.attr_list_display:SetVisibility(UE.ESlateVisibility.Collapsed)
            self.UI_sub_EquipTotalAttr.Img_Arrow:SetRenderTransformAngle(-90)
        else
            self.UI_sub_EquipTotalAttr.attr_list_display:SetVisibility(UE.ESlateVisibility.Visible)
            self.UI_sub_EquipTotalAttr.Img_Arrow:SetRenderTransformAngle(0)
        end
    end)
    self.UI_sub_EquipTotalAttr.attr_list_display.BP_OnEntryInitialized:Clear()
    self.UI_sub_EquipTotalAttr.attr_list_display.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized_Attr(item, widget)
    end)

    self.UI_sub_EquipTotalAttr.Btn_OneClickEquip.OnClicked:Add(self, self.OnClickedEquipAll)
    self.UI_sub_EquipTotalAttr.Btn_OneClickDischarge.OnClicked:Add(self, self.OnClickedDischargeAll)

    for i = 1, 6 do
        self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].GHSButton.OnGHSClicked:Add(self, function() 
            self:OnClicked_EuipItem(i)
        end)
    end
end

function M:RefreshData()
    self.AttrData = {}
    self.AllEquipData = {}
    self.select_equip = 0
    for item_id, bagData in pairs(BackpackSystem:GetInstance().BagInfo) do
        local itemConfig = UIUtils.GetItemConfigById(item_id)
        if itemConfig then
            local mainType = itemConfig.itemType
            local subType = itemConfig.subType
            if mainType == UIUtils.ItemMainType.Equip then
                if not self.AllEquipData[subType] then self.AllEquipData[subType] = {} end
                for _, value in ipairs(bagData) do
                    value.config = itemConfig
                    table.insert(self.AllEquipData[subType], value)
                end
            end
        end
    end
    --排序
    for subType, EquipDatas in pairs(self.AllEquipData) do
        table.sort(EquipDatas, function(a, b)
            if a.config.rarity ~= b.config.rarity then
                return a.config.rarity > b.config.rarity
            else
                return a.item_uuid > b.item_uuid
            end
        end)
    end

    --灼痕
    self.rune_ids = {}
    for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
        for _, arm_rune_infos in ipairs(arm_info.arm_info.arm_rune_infos) do
            local rune_id = arm_rune_infos.rune_id
            if not self.rune_ids[rune_id] then
                self.rune_ids[rune_id] = 1
            else
                self.rune_ids[rune_id] = self.rune_ids[rune_id] + 1
            end
        end
    end
end

function M:RefreshTotalAttr()
    --属性列表刷新
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    local attrDataSource = {}
    for index, _ in pairs(self.AttrData) do
        local itemData = NewObject(ItemClass)
        itemData.ItemId = index
        table.insert(attrDataSource, itemData)
    end

    self.UI_sub_EquipTotalAttr.attr_list_display:ClearListItems()
    self.UI_sub_EquipTotalAttr.attr_list_display:BP_SetListItems(attrDataSource)
    self.UI_sub_EquipTotalAttr.RuneWordBox:ClearChildren()
    for rune_id, count in pairs(self.rune_ids) do
        if count > 1 then
            local ui = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Equip/UI_Equip_RuneWords.UI_Equip_RuneWords_C"))
            self.UI_sub_EquipTotalAttr.RuneWordBox:AddChild(ui)
            local rune_info = d_equip_rune[rune_id]
            if rune_info then
                local strArr = string.split(rune_info.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format('/Game/_Game/%s.%s', rune_info.runeIcon, littePath))
                if itemRarityPic then
                    ui.ImageRune:SetBrushFromAtlasInterface(itemRarityPic)
                end
                ui.TextName:SetText(Database.L10n(rune_info.runeSuitsName))
                for i = 2, 6 do
                    if i <= count then
                        ui["TextDesc_" .. i]:SetText(Database.L10n(rune_info[i .. "runesDesc"]))
                        ui["TextDesc_" .. i]:SetVisibility(UE.ESlateVisibility.Visible)
                    else
                        ui["TextDesc_" .. i]:SetVisibility(UE.ESlateVisibility.Collapsed)
                    end
                end
            end
            ui["TextDesc_" .. 6]:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
    end

    --符文总览
    local ICON_PATH = '/Game/_Game/%s.%s'
    for i = 1, 6 do
        self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].Text_Rune:SetText(Database.L10n(UIUtils.WordEquipType[i]))
        if i == 1 then
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].HeartIcon:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].OtherIcon:SetVisibility(UE.ESlateVisibility.Hidden)
        else
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].HeartIcon:SetVisibility(UE.ESlateVisibility.Hidden)
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].OtherIcon:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end
        self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].Image:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].Image_1:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. i].Image_2:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
        local itemConfig = UIUtils.GetItemConfigById(arm_info.item_id)
        if itemConfig.subType == 1 then
            local rune_info_1 = d_equip_rune[arm_info.arm_info.arm_rune_infos[1].rune_id]
            local rune_info_2 = d_equip_rune[arm_info.arm_info.arm_rune_infos[2].rune_id]
            if rune_info_1 then
                local strArr = string.split(rune_info_1.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format(ICON_PATH, rune_info_1.runeIcon, littePath))
                if itemRarityPic then
                    self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image_1:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            if rune_info_2 then
                local strArr = string.split(rune_info_2.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format(ICON_PATH, rune_info_2.runeIcon, littePath))
                if itemRarityPic then
                    self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image_2:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        else
            local rune_info_1 = d_equip_rune[arm_info.arm_info.arm_rune_infos[1].rune_id]
            if rune_info_1 then
                local strArr = string.split(rune_info_1.runeIcon, '/')
                local littePath = strArr[#strArr]
                local itemRarityPic = LoadObject(string.format(ICON_PATH, rune_info_1.runeIcon, littePath))
                if itemRarityPic then
                    self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end
            self.UI_sub_EquipTotalAttr["UI_Sub_Rune_" .. itemConfig.subType].Image:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end
    end
end

function M:RefreshUI(parent, SelectedCharacterData)
    self.parent = parent
    self.SelectedCharacterData = SelectedCharacterData
    self.UI_itemlist_siderbar:SetVisibility(UE.ESlateVisibility.Hidden)
    self.UI_sub_EquipTotalAttr:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self:RefreshData()
    for i = 1, 6 do
        self[EquipUIName[i]].Equipped:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].Unequip:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self[EquipUIName[i]].Selected:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].Organ_img:SetBrushFromAtlasInterface(UE.UObject.Load(EquipIcon[i]))
    end

    --effect
    local cineCameraActors = UE.UGameplayStatics.GetAllActorsOfClassWithTag(self, UE.ACineCameraActor, "equip")
    local tarCamera = nil
    if cineCameraActors:Length() > 0 then
        tarCamera = cineCameraActors:Get(1)
    end
    local niagaraComponents = tarCamera:K2_GetComponentsByClass(UE.UNiagaraComponent)

    --set ui vfx color 连线特效隐隐藏
    for i = 1, 6 do
        self[EquipUIName[i]].VFX_1:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].VFX_2:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].VFX_3:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].VFX_4:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].VFX_5:SetVisibility(UE.ESlateVisibility.Hidden)
        self[EquipUIName[i]].UI_Panel_Equip_VfxReady:SetVisibility(UE.ESlateVisibility.Hidden)
        local color = UE.FSlateColor()
        color.SpecifiedColor = UE.FLinearColor(1, 1, 1, 1)
        self[EquipUIName[i]].BaseImage:SetBrushTintColor(color)
        print("=========color_type1:" .. tostring(color))
        for _, niagaraComponent in pairs(niagaraComponents) do
            niagaraComponent:Deactivate()
            niagaraComponent:SetVariableInt('Color', 0)
        end
    end

    coroutine.resume(coroutine.create(function()
        UE.UKismetSystemLibrary.Delay(self, 0.2)
        for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
            local itemConfig = UIUtils.GetItemConfigById(arm_info.item_id)
            if arm_info then
                self[EquipUIName[itemConfig.subType]].Equipped:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].Unequip:SetVisibility(UE.ESlateVisibility.Hidden)
                self[EquipUIName[itemConfig.subType]].Selected:SetVisibility(UE.ESlateVisibility.Hidden)
    
                local color_type = 0 --未激活套装
                for _, arm_rune_info in ipairs(arm_info.arm_info.arm_rune_infos) do
                    if self.rune_ids[arm_rune_info.rune_id] > 1 then
                        --激活套装
                        color_type = 3
                    end
                end
                print("=========color_type:" .. tostring(color_type))
                --vfx
                local color = UE.FSlateColor()
                color.SpecifiedColor = ColorType[color_type + 1][1]
                self[EquipUIName[itemConfig.subType]].BaseImage:SetBrushTintColor(color)
                color.SpecifiedColor = ColorType[color_type + 1][2]
                self[EquipUIName[itemConfig.subType]].VFX_1:SetBrushTintColor(color)
                color.SpecifiedColor = ColorType[color_type + 1][3]
                self[EquipUIName[itemConfig.subType]].VFX_2:SetBrushTintColor(color)
                color.SpecifiedColor = ColorType[color_type + 1][4]
                self[EquipUIName[itemConfig.subType]].VFX_3:SetBrushTintColor(color)
                color.SpecifiedColor = ColorType[color_type + 1][5]
                self[EquipUIName[itemConfig.subType]].VFX_4:SetBrushTintColor(color)
                color.SpecifiedColor = ColorType[color_type + 1][6]
                self[EquipUIName[itemConfig.subType]].VFX_5:SetBrushTintColor(color)
                if self[EquipUIName[itemConfig.subType]]:IsAnimationPlaying(self[EquipUIName[itemConfig.subType]].ShowVFX) then
                    self[EquipUIName[itemConfig.subType]]:SetAnimationCurrentTime(self[EquipUIName[itemConfig.subType]].ShowVFX, 0)
                else
                    self[EquipUIName[itemConfig.subType]]:PlayAnimationForward(self[EquipUIName[itemConfig.subType]].ShowVFX, 1, false)
                end
    
                for _, niagaraComponent in pairs(niagaraComponents) do
                    local name = "Niagara" .. itemConfig.subType
                    if niagaraComponent:GetName() == name then
                        print("===设置粒子颜色:" .. tostring(color_type))
                        niagaraComponent:SetVisibility(true)
                        niagaraComponent:Activate(false)
                        niagaraComponent:SetVariableInt('Color', color_type)
                        break
                    end
                end
    
                --人物背后的光显示
                for _, niagaraComponent in pairs(niagaraComponents) do
                    local name = "Niagara"
                    if niagaraComponent:GetName() == name then
                        niagaraComponent:SetVisibility(true)
                        niagaraComponent:Activate(false)
                        break
                    end
                end
    
                self[EquipUIName[itemConfig.subType]].VFX_1:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].VFX_2:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].VFX_3:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].VFX_4:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].VFX_5:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    
                -- icon
                local iconResPath = string.format('/Game/_Game/TP_New/Bag_equip_res/Frames/circleicon%s_png.circleicon%s_png', arm_info.item_id, arm_info.item_id)
                local object = UE.UObject.Load(iconResPath)
                if object then
                    self[EquipUIName[itemConfig.subType]].Equip_res:SetBrushFromAtlasInterface(object)
                end
            else
                self[EquipUIName[itemConfig.subType]].Equipped:SetVisibility(UE.ESlateVisibility.Hidden)
                self[EquipUIName[itemConfig.subType]].Unequip:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].Selected:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
        for subType = 1, 6 do
            if not self[EquipUIName[subType]].Equipped:IsVisible() and self.AllEquipData[subType] then
                self[EquipUIName[subType]].UI_Panel_Equip_VfxReady:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            else
                self[EquipUIName[subType]].UI_Panel_Equip_VfxReady:SetVisibility(UE.ESlateVisibility.Hidden)
            end
        end
    end))

    local attrEx = UIUtils.GetCharacterEquipAttr(self.SelectedCharacterData.character_id, false)
    --修正要显示的属性(合并和显示的)
    for k, v in pairs(attrEx) do
        local attrConfig = d_attributes[k]
        print('---v:' .. tostring(v))
        if v ~= 0 then
            if v > 0.00000001 then
                local attrInfo = {
                    attrId = k,
                    attrValue = v,
                    attrUp = 0,
                    config = attrConfig
                }
                table.insert(self.AttrData, attrInfo)
            end
        end
    end
    if #self.AttrData > 2 then
        table.sort(self.AttrData, function(a, b)
            if a.config.showOrder ~= b.config.showOrder then
                if a.config.showOrder == 0 then
                    return false
                elseif b.config.showOrder == 0 then
                    return true
                else
                    return a.config.showOrder < b.config.showOrder
                end
            else
                return a.config.id < b.config.id
            end
        end)
    end

    --判断分辨率是否全屏
    local gameUserSettings = UE.UGameUserSettings:GetGameUserSettings()
    local fullScreenMode = gameUserSettings:GetFullscreenMode()
    if fullScreenMode == UE.EWindowMode.Fullscreen or fullScreenMode == UE.EWindowMode.WindowedFullscreen then
        local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
        if winWidth / winHeight > 1920 / 1080 then
            local x = (winWidth - winHeight / 1080 * 1920) * 0.5
            self.equipBox:SetRenderTranslation(UE.FVector2D(-x, 0))
        end
    end
    self:RefreshTotalAttr()
end

function M:OnMsg_Req_Character_Equip_Arm()
    self:RefreshUI(self.parent, self.SelectedCharacterData)
end

function M:OnClickedEquipAll()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    local equipped_type = {}
    for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
        equipped_type[arm_info.config.subType] = arm_info.config.subType
    end

    for subType = 1, 6 do
        if not equipped_type[subType] and self.AllEquipData[subType] and #self.AllEquipData[subType] > 0 then
            local equip_data = self.AllEquipData[subType][1]
            local msg = {
                character_id = self.SelectedCharacterData.character_id,
                item_uuid = equip_data.item_uuid
            }
            print("======req_character_equip_arm:" .. tostring(table.dump(msg, false, 10)))
            Client.send("req_character_equip_arm", msg)
        end
    end
end

function M:OnClickedDischargeAll()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    
    for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
        BackpackSystem:GetInstance():CacheReplaceWeaponOrEquip(self.SelectedCharacterData.character_id, arm_info)
        local msg = {
            character_id = self.SelectedCharacterData.character_id,
            item_uuid = arm_info.item_uuid
        }
        print("======req_character_unequip_arm:" .. tostring(table.dump(msg, false, 10)))
        Client.send("req_character_unequip_arm", msg)
    end
end

function M:OnClicked_EuipItem(equip_type)
    if equip_type == self.select_equip then
        return
    end

    local bEquipped = false
    local subType = 0
    for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
        local itemConfig = UIUtils.GetItemConfigById(arm_info.item_id)
        if itemConfig.subType == equip_type then
            bEquipped = true
            subType = itemConfig.subType
            break
        end
    end

    if bEquipped then
        for _, arm_info in pairs(self.SelectedCharacterData.arm_infos) do
            local itemConfig = UIUtils.GetItemConfigById(arm_info.item_id)
            if itemConfig.subType == equip_type then
                local item_data = arm_info
                item_data.config = itemConfig
                self.select_equip = equip_type
                self.UI_itemlist_siderbar:RefreshUI(item_data, false)
                self.UI_itemlist_siderbar:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self.UI_sub_EquipTotalAttr:SetVisibility(UE.ESlateVisibility.Hidden)
                --self[EquipUIName[itemConfig.subType]].Equipped:SetVisibility(UE.ESlateVisibility.Hidden)
                self[EquipUIName[itemConfig.subType]].Selected:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].UI_Panel_Equip_VfxChoose:PlayVFXAnimation()
            else
                self:UnbindAllFromAnimationFinished(self.startAnimation)
                --self[EquipUIName[itemConfig.subType]].Equipped:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
                self[EquipUIName[itemConfig.subType]].Selected:SetVisibility(UE.ESlateVisibility.Hidden)
                self[EquipUIName[itemConfig.subType]].UI_Panel_Equip_VfxChoose:StopVFXAnimation()
            end
        end
    else
        self:OnClicked_Replace(equip_type)
    end
end

function M:OnClicked_Rune(rune_id)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Rune_Overview')
    ui:InitUI(rune_id)
end

function M:OnClicked_Replace(equip_type)
    self.parent:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Equip_Change')
    ui:SetBackUI(self.parent, self.SelectedCharacterData)
    ui:RefreshTab(equip_type)
end

function M:OnClicked_Strengthen()
    self.parent:SetVisibility(UE.ESlateVisibility.Hidden)
    local item_data = self.UI_itemlist_siderbar.UI_Com_BagDetail.ItemData
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Levelup_Equip')
    ui:SetBackUI(self.parent, item_data, false)
end

function M:BP_OnEntryInitialized_Attr(item, ui)
    local attrInfo = self.AttrData[item.ItemId]
    if not attrInfo.config then
        attrInfo.config = d_attributes[attrInfo.attrID]
    end
    --背景图片
    ui.Img_Bg:SetVisibility((item.Index % 2 == 1) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Collapsed)

    --属性类型图片
    local iconPath = string.format("'/Game/_Game/TP_New/Attribute_res/Frames/%s_png.%s_png'", attrInfo.config.attrIcon, attrInfo.config.attrIcon)
    local iconObj = LoadObject(iconPath)
    if iconObj then
        ui.Img_Icon:SetBrushFromAtlasInterface(iconObj)
    end
    local bShowUp = (attrInfo.attrUp or 0) > 0
    ui.Text_Title:SetText(Database.L10n(attrInfo.config.attrName))

    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = bShowUp and UE.FLinearColor(0.545725, 0.603828, 0.760525, 1.0) or UE.FLinearColor(0.278431, 0.329412, 0.47451, 1.0)
    ui.Text_NextValue:SetColorAndOpacity(textColor)

    local isHundred = false
    if attrInfo.config.types == UIUtils.AttributeType.OverAHundred or 
        attrInfo.config.types == UIUtils.AttributeType.InAHundred then
        isHundred = true
    end
    local attrValue = isHundred and string.format("%.1f", attrInfo.attrValue * 100) or string.format("%d", math.modf(attrInfo.attrValue))
    ui.Text_NextValue:SetText((isHundred and (attrValue .. '%') or attrValue))
end

return M

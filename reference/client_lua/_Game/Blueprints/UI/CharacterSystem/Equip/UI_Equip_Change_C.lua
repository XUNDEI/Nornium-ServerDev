--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local d_character = require "ClientDatas.d_character"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local Protos = require("Helper.Protos")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local SideUI_State = {
    Compare = 1,
    Equipped = 2,
    Equipped_Now = 3,
    Close = 4,
    Hidden = 5,
}

---@type UI_Equip_Change_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.BackUI:RefreshEquipPanel()
        self.BackUI = nil
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)
InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.CurTabIndex = 0
    self.curCharacterInfo = {}
    self.characterList = {}
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Equip_Arm", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Swap_Arm", self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_EQUIP_ARM, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_UNEQUIP_ARM, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_SWAP_ARM, self)
    -- MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Equip_Success", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Equip_Arm", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Swap_Arm", self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_EQUIP_ARM, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_UNEQUIP_ARM, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_SWAP_ARM, self)
    -- MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Equip_Success", self)
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

M[Protos.RES_CHARACTER_EQUIP_ARM] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

M[Protos.RES_CHARACTER_UNEQUIP_ARM] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

M[Protos.RES_CHARACTER_SWAP_ARM] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

function M:InitUI()
    --退出按钮
    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Exit)

    --生成器
    self.List.BP_OnEntryInitialized:Clear()
    self.List.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.List.BP_OnItemClicked:Clear()
    self.List.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    
    self.UI_Tab_EquipType.MindEngine.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Heart, true)
        end
    end)
    self.UI_Tab_EquipType.LunglobeTurbine.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Lung, true)
        end
    end)
    
    self.UI_Tab_EquipType.RenalGlandBurners.OnCheckStateChanged:Add(self, function(self, isOn)  
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.kidney, true)
        end
    end)
    
    self.UI_Tab_EquipType.HepaticCrystal.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Liver, true)
        end
    end)

    self.UI_Tab_EquipType.GastricParietal.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Stomach, true)
        end
    end)
    self.UI_Tab_EquipType.BrainComputer.OnCheckStateChanged:Add(self, function(self, isOn) 
        if isOn then
            self:TabSelected(UIUtils.ItemEquipType.Brain, true)
        end
    end)

    self.UI_itemlist_siderbar.UI_Com_ItemBox.Rune_1.OnClicked:Add(self, function()
        local rune_id = self.UI_itemlist_siderbar.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[1].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.UI_itemlist_siderbar.UI_Com_ItemBox.Rune_2.OnClicked:Add(self, function()
        local rune_id = self.UI_itemlist_siderbar.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[2].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.new.UI_Com_ItemBox.Rune_1.OnClicked:Add(self, function()
        local rune_id = self.new.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[1].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.new.UI_Com_ItemBox.Rune_2.OnClicked:Add(self, function()
        local rune_id = self.new.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[2].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.old.UI_Com_ItemBox.Rune_1.OnClicked:Add(self, function()
        local rune_id = self.old.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[1].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.old.UI_Com_ItemBox.Rune_2.OnClicked:Add(self, function()
        local rune_id = self.old.UI_Com_BagDetail.ItemData.arm_info.arm_rune_infos[2].rune_id
        self:OnClicked_Rune(rune_id)
    end)

    self.UI_Com_SortFilter.OnFinishedSort:Add(self, function()
        self:TabSelected(self.CurTabIndex, true)
    end)
    
    self.UI_Com_SortFilter.OnFinishedFilter:Add(self, function()
        self:TabSelected(self.CurTabIndex, true)
    end)

    --装备替换
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Replace.OnClicked:Add(self, self.OnClicked_Replace)
    -- self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Level.OnClicked:Add(self, self.OnClicked_Strengthen)
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Discharge.OnClicked:Add(self, self.OnClicked_Discharge)

    --对比面板
    self.UI_Itemlist_siderbar.UI_Com_ItemBox.Compare.OnClicked:Add(self, function()
        local item_data = self.CurItemDataList[self.SelectedItemIndex]
        self:ShowCompare(item_data)
    end)

    self.new.UI_Com_ItemBox.Close.OnClicked:Add(self, self.CloseCompare)

    self.new.UI_Com_BagDetail.Btn_Replace.OnClicked:Add(self, self.OnClicked_Replace)

end

function M:InitData()
    self.AllEquipData = {}
    self.characterList = {}
    --背包装备数据
    for item_id, bagData in pairs(BackpackSystem:GetInstance().BagInfo) do
        local itemConfig = UIUtils.GetItemConfigById(item_id)
        if itemConfig then
            local mainType = itemConfig.itemType
            local subType = itemConfig.subType
            --get equipped equip info
            if mainType == UIUtils.ItemMainType.Equip then
                if not self.AllEquipData[subType] then self.AllEquipData[subType] = {} end
                --table.insert(self.AllWeaponData, role_equip_info)
                for _, value in ipairs(bagData) do
                    value.config = itemConfig
                    table.insert(self.AllEquipData[subType], value)
                end
            end
        end
    end

    --把character的arm_info用subtype做key重新存储方便查找
    for _, character_info in ipairs(CharacterSystem:GetInstance().CharacterInfo) do
        local new_character_info = {}
        local new_arm_infos = {}
        if character_info.arm_infos then
            for _, arm_data in pairs(character_info.arm_infos) do
                local itemConfig = UIUtils.GetItemConfigById(arm_data.item_id)
                local subType = itemConfig.subType
                arm_data.config = itemConfig
                if not self.AllEquipData[subType] then self.AllEquipData[subType] = {} end
                table.insert(self.AllEquipData[subType], arm_data)
                new_arm_infos[subType] = arm_data
            end
        end
        new_character_info.character_id = character_info.character_id
        new_character_info.arm_infos = new_arm_infos
        self.characterList[new_character_info.character_id] = new_character_info
    end

    --排序
    for _, value in ipairs(self.AllEquipData) do
        if #value > 1 then
            table.sort(value, function(a, b)
                if a.config.bagSort ~= b.config.bagSort then
                    return a.config.bagSort < b.config.bagSort
                else
                    return a.item_uuid < b.item_uuid
                end
            end)
        end
    end
    
    local sortData = {}
    local SortTypes = { UIUtils.ESortType.Star }
    local filterTypes = { UIUtils.EFilterType.MainProperty, UIUtils.EFilterType.Rune }
    sortData.sortTypes = SortTypes
    sortData.filterTypes = filterTypes
    sortData.canFilter = true
    self.UI_Com_SortFilter:RefreshData(sortData)
end

function M:RefreshTab(equip_type)
    if equip_type == UIUtils.ItemEquipType.Brain then
        self.UI_Tab_EquipType.BrainComputer:SetIsCheckedAndFireEvent(true)
    elseif equip_type == UIUtils.ItemEquipType.kidney then
        self.UI_Tab_EquipType.RenalGlandBurners:SetIsCheckedAndFireEvent(true)
    elseif equip_type == UIUtils.ItemEquipType.Lung then
        self.UI_Tab_EquipType.LunglobeTurbine:SetIsCheckedAndFireEvent(true)
    elseif equip_type == UIUtils.ItemEquipType.Liver then
        self.UI_Tab_EquipType.HepaticCrystal:SetIsCheckedAndFireEvent(true)
    elseif equip_type == UIUtils.ItemEquipType.Stomach then
        self.UI_Tab_EquipType.GastricParietal:SetIsCheckedAndFireEvent(true)
    elseif equip_type == UIUtils.ItemEquipType.Heart then
        self.UI_Tab_EquipType.MindEngine:SetIsCheckedAndFireEvent(true)
    end
end

function M:TabSelected(equip_type, bForceFirst)
    self.CurTabIndex = equip_type
    self.SelectedItemIndex = bForceFirst and 1 or self.SelectedItemIndex
    self.ItemDataSource = {}
    self:GetItemDataByTabIndex()
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
    local EquipCount = #self.CurItemDataList
    if EquipCount > 0 then
        for i = 1, EquipCount do
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local EquipItem = UE.UWidgetBlueprintLibrary.Create(self, ItemClass)
            local data = self.CurItemDataList[i]
            EquipItem.item_data = data
            EquipItem.index = i
            for _, arm_info in pairs(self.curCharacterInfo.arm_infos) do
                if arm_info.item_uuid == data.item_uuid and bForceFirst then
                    self.SelectedItemIndex = i
                    break
                end
            end
            table.insert(self.ItemDataSource, EquipItem)
        end
        self.List:ClearListItems()
        self.List:BP_SetListItems(self.ItemDataSource)
        local equip_data = self.CurItemDataList[self.SelectedItemIndex]
        equip_data.config = self.CurItemDataList[self.SelectedItemIndex].config
        self.UI_Itemlist_siderbar:RefreshUI(equip_data, false)
        self.UI_Itemlist_siderbar:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)

        local equiped = false
        local equip_character = {}
        for _, character_info in pairs(self.characterList) do
            if character_info.arm_infos[equip_type] then
                local character_arm = character_info.arm_infos[equip_type]
                if character_arm.item_uuid == equip_data.item_uuid then
                    equiped = true
                    equip_character = character_info
                    break
                end
            end
        end

        if equiped then
            if equip_character.character_id == self.curCharacterInfo.character_id then
                self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
                self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(true)
            else
                self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
                self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
            end
            local idolProfile = d_character[equip_character.character_id].idolProfile
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshRoleIcon(idolProfile)
        else
            if self.characterList[self.curCharacterInfo.character_id] and
                self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
                self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
            else
                self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)
            end
            self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
        end

        if self.characterList[self.curCharacterInfo.character_id] and
            self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
            self.UI_Itemlist_siderbar.UI_Com_BagDetail.Text_Replace:SetText(Database.L10n(322))
        else
            self.UI_Itemlist_siderbar.UI_Com_BagDetail.Text_Replace:SetText(Database.L10n(323))
        end
    else
        self.List:ClearListItems()
        self.UI_Itemlist_siderbar:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:BP_OnEntryInitialized(item, widget)
    local bIsSelected = self.SelectedItemIndex == item.index
    local bCurEquiped = false
    local equip_character = {}
    widget.index = item.index
    widget.item_data = item.item_data
    widget.UI_Com_ItemBox:RefreshUI(item.item_data, false)
    widget.UI_Com_ItemBox:RefreshSelectState(bIsSelected)
    widget.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)
    widget.UI_Com_ItemBox.Text_ItemCount:SetVisibility(UE.ESlateVisibility.Hidden)

    for _, character_info in pairs(self.characterList) do
        if character_info.arm_infos[widget.item_data.config.subType] then
            local character_arm = character_info.arm_infos[widget.item_data.config.subType]
            if character_arm.item_uuid == widget.item_data.item_uuid then
                equip_character = character_info
                bCurEquiped = true
                break
            end
        end
    end
    
    if bCurEquiped then
        local idolProfile = d_character[equip_character.character_id].idolProfile
        widget.UI_Com_ItemBox:RefreshRoleIcon(idolProfile)
        widget.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
    end
end

function M:BP_OnItemClicked(item)
    print("====itemClicked:" .. tostring(self.SelectedItemIndex) .. ",index:" .. tostring(item.index) .. ",id:" .. tostring(item.ItemId))
    if self.SelectedItemIndex == item.index then return end
    self.SelectedItemIndex = item.index
    local widgets = self.List:GetDisplayedEntryWidgets()
    for _, widget in pairs(widgets) do
        local bIsSelected = widget.index == item.index
        widget.UI_Com_ItemBox:RefreshSelectState(bIsSelected)
    end
    local equip_data = self.CurItemDataList[self.SelectedItemIndex]
    local equip_type = equip_data.config.subType
    equip_data.config = self.CurItemDataList[self.SelectedItemIndex].config
    self.UI_Itemlist_siderbar:RefreshUI(equip_data, false)

    local equiped = false
    local equip_character = {}
    for _, character_info in pairs(self.characterList) do
        if character_info.arm_infos[equip_type] then
            local character_arm = character_info.arm_infos[equip_type]
            if character_arm.item_uuid == equip_data.item_uuid then
                equiped = true
                equip_character = character_info
                break
            end
        end
    end

    if equiped then
        if equip_character.character_id == self.curCharacterInfo.character_id then
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
            self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(true)
        else
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
            self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
        end
        local idolProfile = d_character[equip_character.character_id].idolProfile
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshRoleIcon(idolProfile)
    else
        if self.characterList[self.curCharacterInfo.character_id] and
            self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
        else
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)
        end
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
    end

    if self.characterList[self.curCharacterInfo.character_id] and
        self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
        self.UI_Itemlist_siderbar.UI_Com_BagDetail.Text_Replace:SetText('替换')
    else
        self.UI_Itemlist_siderbar.UI_Com_BagDetail.Text_Replace:SetText('装备')
    end
end

function M:OnClicked_Rune(rune_id)
    local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Rune_Overview')
    ui:InitUI(rune_id)
end

function M:GetItemDataByTabIndex()
    if not self.AllEquipData[self.CurTabIndex] then self.AllEquipData[self.CurTabIndex] = {} end
    self.CurItemDataList = self.AllEquipData[self.CurTabIndex] or {}

    local sortData = self.UI_Com_SortFilter:GetSortData()
    --filter
    local filterItemData = {}
    local filterData = self.UI_Com_SortFilter.FilterData
    for filterType, tags in pairs(filterData) do
        if filterType == UIUtils.EFilterType.MainProperty then
            local tag_count = 0
            for i, v in pairs(tags) do
                tag_count = tag_count + 1
            end
            if tag_count > 0 then
                for index, itemData in ipairs(self.CurItemDataList) do
                    for _, arm_random_attribute_info in ipairs(itemData.arm_info.arm_random_attribute_infos) do
                        local equipConfig = require("ClientDatas.d_equip")[itemData.item_id]
                        local weight_index = arm_random_attribute_info.weight_index
                        local attr_id = equipConfig.randomAtt[weight_index + 1]
                        local attrConfig = require("ClientDatas.d_attributes")[attr_id]
                        if tags[attrConfig.showTag] then
                            table.insert(filterItemData, itemData)
                        end
                    end
                end
                self.CurItemDataList = filterItemData
                filterItemData = {}
            end
        end
        if filterType == UIUtils.EFilterType.Rune then
            local tag_count = 0
            for i, v in pairs(tags) do
                tag_count = tag_count + 1
            end
            if tag_count > 0 then
                for index, itemData in ipairs(self.CurItemDataList) do
                    for _, arm_rune_info in ipairs(itemData.arm_info.arm_rune_infos) do
                        if tags[arm_rune_info.rune_id] then
                            table.insert(filterItemData, itemData)
                        end
                    end
                end
                self.CurItemDataList = filterItemData
                filterItemData = {}
            end
        end
    end
    --sort
    if sortData.selectedSortType == UIUtils.ESortType.Star then
        table.sort(self.CurItemDataList, function(a, b)
            if a.config.rarity ~= b.config.rarity then
                if sortData.sortOrderUp then
                    return a.config.rarity > b.config.rarity
                else
                    return a.config.rarity < b.config.rarity
                end
            else
                return a.item_uuid < b.item_uuid
            end
        end)
    end
end

function M:OnClicked_Replace()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end

    local item_data = self.CurItemDataList[self.SelectedItemIndex]
    local is_equip = false
    local swap_character_info = {}
    for _, character_info in pairs(self.characterList) do
        if character_info.arm_infos[self.CurTabIndex] then
            if character_info.arm_infos[self.CurTabIndex].item_uuid == item_data.item_uuid then
                is_equip = true
                swap_character_info = character_info
                break
            end
        end
    end

    if not is_equip then
        BackpackSystem:GetInstance():CacheReplaceWeaponOrEquip(self.curCharacterInfo.character_id, item_data)
        local msg = {
            character_id = self.curCharacterInfo.character_id,
            item_uuid = item_data.item_uuid
        }
        if not self.waiting then
            self.waiting = true
            print("======req_character_equip_arm:" .. tostring(table.dump(msg, false, 10)))
            Client.send("req_character_equip_arm", msg)
        end
    else
        local str = Database.L10n(5014006)
        local weapon_name = Database.L10n(item_data.config.itemName)
        local character_name = Database.L10n(d_character[swap_character_info.character_id].name)
        str = string.format(str, weapon_name, character_name)
        UIManager:GetInstance():ShowConfirm({
            notice = str,
            confirm = function()
                CharacterSystem:GetInstance():CacheSwapArm(self.curCharacterInfo.character_id, swap_character_info.character_id, item_data.config.subType)
                local msg = {
                    character_id = self.curCharacterInfo.character_id,
                    item_slot = item_data.config.subType,
                    other_character_id = swap_character_info.character_id
                }
                if not self.waiting then
                    self.waiting = true
                    print("======req_character_swap_arm:" .. tostring(table.dump(msg, false, 10)))
                    Client.send("req_character_swap_arm", msg)
                    self:CloseCompare()
                end
            end,
            showCancel = true,
        })
    end
    self:CloseCompare()
end

-- function M:OnClicked_Strengthen()
--     self:SetVisibility(UE.ESlateVisibility.Hidden)
--     local ui = UE.UGameplayStatics.GetGameInstance(self):AddUMG('UI_Levelup_Equip')
--     local item_data = self.CurItemDataList[self.SelectedItemIndex]

--     local equiped = false
--     local equip_type = item_data.config.subType
--     for _, character_info in pairs(self.characterList) do
--         if character_info.arm_infos[equip_type] then
--             local character_arm = character_info.arm_infos[equip_type]
--             if character_arm.item_uuid == item_data.item_uuid and
--                 character_info.character_id == self.curCharacterInfo.character_id then
--                 equiped = true
--                 break
--             end
--         end
--     end
    
--     ui:SetBackUI(self, item_data, false)
-- end

function M:OnClicked_Discharge()
    local item_data = self.CurItemDataList[self.SelectedItemIndex]
    BackpackSystem:GetInstance():CacheReplaceWeaponOrEquip(self.curCharacterInfo.character_id, item_data)
    local msg = {
        character_id = self.curCharacterInfo.character_id,
        item_uuid = item_data.item_uuid
    }
    if not self.waiting then
        self.waiting = true
        print("======req_character_unequip_arm:" .. tostring(table.dump(msg, false, 10)))
        Client.send("req_character_unequip_arm", msg)
    end
end

function M:OnMsg_Req_Character_Equip_Arm()
    self.curCharacterInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.curCharacterInfo.character_id)
    self:InitData()
    self:TabSelected(self.CurTabIndex, false)
    local equiped = false
    local equip_data = self.CurItemDataList[self.SelectedItemIndex]
    local equip_type = equip_data.config.subType
    for _, character_info in pairs(self.characterList) do
        if character_info.arm_infos[equip_type] then
            local character_arm = character_info.arm_infos[equip_type]
            if character_arm.item_uuid == equip_data.item_uuid and
                character_info.character_id == self.curCharacterInfo.character_id then
                equiped = true
                break
            end
        end
    end

    if equiped then
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(true)
    else
        if self.characterList[self.curCharacterInfo.character_id] and
            self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
        else
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)
        end
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
    end
end

function M:OnMsg_Req_Character_Swap_Arm()
    self.curCharacterInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.curCharacterInfo.character_id)
    self:InitData()
    self:TabSelected(self.CurTabIndex, false)
    local equiped = false
    local equip_data = self.CurItemDataList[self.SelectedItemIndex]
    local equip_type = equip_data.config.subType
    for _, character_info in pairs(self.characterList) do
        if character_info.arm_infos[equip_type] then
            local character_arm = character_info.arm_infos[equip_type]
            if character_arm.item_uuid == equip_data.item_uuid and
                character_info.character_id == self.curCharacterInfo.character_id then
                equiped = true
                break
            end
        end
    end

    if equiped then
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(true)
    else
        if self.characterList[self.curCharacterInfo.character_id] and
            self.characterList[self.curCharacterInfo.character_id].arm_infos[equip_type] then
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
        else
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)
        end
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshDischargePanel(false)
    end
end

-- function M:OnMsg_Req_Strengthen_Equip_Success()
--     self:TabSelected(self.CurTabIndex, false)
-- end

function M:ShowCompare(new_equip_data)
    local equip_type = new_equip_data.config.subType
    local old_weapon_data = nil
    for _, arm_info in ipairs(self.curCharacterInfo.arm_infos) do
        if arm_info.config.subType == equip_type then
            old_weapon_data = arm_info
        end
    end
    
    if old_weapon_data then
        self.new:RefreshUI(new_equip_data, false)
        self.new:RefreshCompareState(false)
        self.old:RefreshUI(old_weapon_data, false)
        self.old:RefreshCompareState(true)
        self.compare:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end
end

function M:CloseCompare()
    self.compare:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:SetRoleVisibility(visible)
    self.BackUI:SetRoleVisibility(visible)
end

function M:SetEquipEffectVisibility(visible)
    self.BackUI:SetEquipEffectVisibility(visible)
end

function M:RefreshEquipPanel()
    self.BackUI:RefreshEquipPanel()
end

function M:SetBackUI(beforeUI, roleData)
    self.BackUI = beforeUI
    self.curCharacterInfo = roleData
    self:InitData()
    self:InitUI()
end

return M

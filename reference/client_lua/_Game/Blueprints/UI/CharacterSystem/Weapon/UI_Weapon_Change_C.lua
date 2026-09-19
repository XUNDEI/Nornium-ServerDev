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

---@type UI_Weapon_Change_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
    if self.BackUI then
        self.BackUI:RefreshRoleWeapon(self.BackUI.SelectedCharacterData.weapon_info.item_id)
        self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        self.BackUI = nil
    end
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Exit)
InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self.BackUI = nil
    self.curCharacterInfo = {}
    self.characterInfos = {}
    self.role_weapon_uuid = 0
    self.SelectedItemIndex = 1
    MessageManager:GetInstance():AddListener("OnMsg_Req_Character_Swap_Weapon", self)
    MessageManager:GetInstance():AddListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_EQUIP_WEAPON, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_CHARACTER_SWAP_WEAPON, self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Character_Swap_Weapon", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_Req_Strengthen_Weapon_Success", self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_EQUIP_WEAPON, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_CHARACTER_SWAP_WEAPON, self)
end

M[Protos.RES_CHARACTER_EQUIP_WEAPON] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

M[Protos.RES_CHARACTER_SWAP_WEAPON] = function(self, result, msgId, parsed_msg)
    self.waiting = false
end

function M:InitData()
    self:InitWeaponInfo()
end

function M:InitWeaponInfo()
    self.AllWeaponData = {}
    local CurRoleWeaponType = 0
    local role_weapon_info = self.curCharacterInfo.weapon_info
    local role_weapon_data = UIUtils.GetItemConfigById(role_weapon_info.item_id)
    CurRoleWeaponType = role_weapon_data.subType
    self.role_weapon_uuid = role_weapon_info.item_uuid
    local character_configList = CharacterSystem:GetInstance().CharacterInfo
    --get equipped weapon info
    for _, character_info in ipairs(character_configList) do
        local weapon_config = UIUtils.GetItemConfigById(character_info.weapon_info.item_id)
        if weapon_config.subType == CurRoleWeaponType then
            local weapon_info = {}
            weapon_info = character_info.weapon_info
            weapon_info.config = weapon_config
            table.insert(self.characterInfos, character_info)
            table.insert(self.AllWeaponData, weapon_info)
        end
    end
    local bag_infos = BackpackSystem:GetInstance():GetAllItemByType(UIUtils.ItemMainType.Weapon, CurRoleWeaponType)
    for _, weaponData in pairs(bag_infos) do
        table.insert(self.AllWeaponData, weaponData)
    end

    local sortData = {}
    local sortTypes = { UIUtils.ESortType.Level, UIUtils.ESortType.Star }
    sortData.sortTypes = sortTypes
    sortData.canFilter = false
    self.UI_Com_SortFilter:RefreshData(sortData)
    self.UI_Com_SortFilter:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
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

    --武器替换
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Replace.OnClicked:Add(self, self.OnClicked_Replace)
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Level.OnClicked:Add(self, self.OnClicked_LevelUp)
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Refine.OnClicked:Add(self, self.OnClicked_Refine)
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Refine_short.OnClicked:Add(self, self.OnClicked_Refine)
    self.UI_Itemlist_siderbar.UI_Com_BagDetail.Btn_Level_short.OnClicked:Add(self, self.OnClicked_LevelUp)

    --对比面板
    self.UI_Itemlist_siderbar.UI_Com_ItemBox.Compare.OnClicked:Add(self, function()
        local item_data = self.AllWeaponData[self.SelectedItemIndex]
        self:ShowCompare(item_data)
    end)

    --对比面板按钮
    self.new.UI_Com_ItemBox.Close.OnClicked:Add(self, self.CloseCompare)
    self.new.UI_Com_BagDetail.Btn_Replace.OnClicked:Add(self, self.OnClicked_Replace)
    self.new.UI_Com_BagDetail.Btn_Level.OnClicked:Add(self, self.OnClicked_LevelUp)
    self.new.UI_Com_BagDetail.Btn_Refine.OnClicked:Add(self, self.OnClicked_Refine)
    self.new.UI_Com_BagDetail.Btn_Refine_short.OnClicked:Add(self, self.OnClicked_Refine)
    self.new.UI_Com_BagDetail.Btn_Level_short.OnClicked:Add(self, self.OnClicked_LevelUp)

    self.UI_Com_SortFilter.OnFinishedSort:Add(self, function()
        self:RefreshTab(true)
    end)
    self.UI_Com_SortFilter.OnFinishedFilter:Add(self, function()
        self:RefreshTab(true)
    end)

    self.InitHideItemUI = true  
    self.MaxItemNumInDisplay = 15
    self:RefreshTab(true)

  
    self.minValue = math.min(self.MaxItemNumInDisplay, #self.ItemDataSource)

    self.Time1 = 0.05 --每行时间间隔
    self.Time2 = 0.15 --一行的所有item的间隔 /列数
    self.ColumNum = 3
    self.InitAnimationIndex = 0
    self.DoAnimationIndexList = {}
    self.PastTime = 0
    self.StartPlayAnim = self.minValue > 0 
end

function M:RefreshTab(bForceFirst)
    if bForceFirst then
        self.SelectedItemIndex = 1
    end

    local sortData = self.UI_Com_SortFilter:GetSortData()
    if sortData.selectedSortType == UIUtils.ESortType.Level then
        table.sort(self.AllWeaponData, function(a, b)
            if a.weapon_info.exp ~= b.weapon_info.exp then
                if sortData.sortOrderUp then
                    return a.weapon_info.exp > b.weapon_info.exp
                else
                    return a.weapon_info.exp < b.weapon_info.exp
                end
            else
                if a.config.id ~= b.config.id then
                    return a.config.id < b.config.id
                else
                    return a.item_uuid < b.item_uuid
                end
            end
        end)
    elseif sortData.selectedSortType == UIUtils.ESortType.Type then
        table.sort(self.AllWeaponData, function(a, b)
            if a.config.subType ~= b.config.subType then
                if sortData.sortOrderUp then
                    return a.config.subType > b.config.subType
                else
                    return a.config.subType < b.config.subType
                end
            else
                if a.config.id ~= b.config.id then
                    return a.config.id < b.config.id
                else
                    return a.item_uuid < b.item_uuid
                end
            end
        end)
    elseif sortData.selectedSortType == UIUtils.ESortType.Star then
        table.sort(self.AllWeaponData, function(a, b)
            if a.config.rarity ~= b.config.rarity then
                if sortData.sortOrderUp then
                    return a.config.rarity > b.config.rarity
                else
                    return a.config.rarity < b.config.rarity
                end
            else
                if a.config.id ~= b.config.id then
                    return a.config.id < b.config.id
                else
                    return a.item_uuid < b.item_uuid
                end
            end
        end)
    end

    self.ItemDataSource = {}
    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Weapon/UI_Weapon_ListItem.UI_Weapon_ListItem_C'
    local WeaponCount = #self.AllWeaponData
    if WeaponCount > 0 then
        for i = 1, WeaponCount do
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            local WeaponItem = UE.UWidgetBlueprintLibrary.Create(self, ItemClass)
            local data = self.AllWeaponData[i]
            WeaponItem.item_data = data
            WeaponItem.index = i
            table.insert(self.ItemDataSource, WeaponItem)
            if data.item_uuid == self.role_weapon_uuid then
                self.SelectedItemIndex = i
            end
        end
        self.List:ClearListItems()
        self.List:BP_SetListItems(self.ItemDataSource)
        
        local item_data = self.AllWeaponData[self.SelectedItemIndex]
        self.UI_Itemlist_siderbar:RefreshUI(item_data, false)
        self.UI_Itemlist_siderbar:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        local bEquiped = item_data.item_uuid == self.role_weapon_uuid
        if bEquiped then
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshRoleIcon(self.curCharacterInfo.config.idolProfile)
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
            self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshReplacePanel(bEquiped)
        else
            self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
            self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshReplacePanel(bEquiped)
        end
    else
        self.UI_Itemlist_siderbar:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnMsg_Req_Character_Swap_Weapon()
    self.curCharacterInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.curCharacterInfo.character_id)
    self:InitData()
    self:RefreshTab(false)
end

function M:OnMsg_Req_Strengthen_Weapon_Success()
    self:InitData()
    self:RefreshTab(false)
end


function M:Tick(MyGeometry, InDeltaTime)
    if self.StartPlayAnim then
        local uiNum = self.List:GetDisplayedEntryWidgets():Length()
        local itemNum = self.minValue
        if uiNum >= itemNum then
            self.PastTime = self.PastTime + InDeltaTime
            for i = 1, self.minValue do 
                local curTime = self.Time1 + math.ceil((i - 1) / self.ColumNum) * self.Time1 + (i - 1) % self.ColumNum * (self.Time2 / self.ColumNum)
               
                local find = false
                for _, index in ipairs(self.DoAnimationIndexList) do 
                    if index == i then 
                        find = true
                        break
                    end
                end
                if not find then
                    if self.PastTime >= curTime then
                        --优化节点
                        if self.InitHideItemUI then
                            self.InitHideItemUI = false
                        end
                        self:InitPlayAnimation(i)
                    end
                end
            end
        end
    end
end

function M:InitPlayAnimation(index)
    local widgets = self.List:GetDisplayedEntryWidgets()
    -- print('----index:' .. tostring(index) .. ',array:' .. tostring(#self.DoAnimationIndexList) .. ', count:' .. tostring(widgets:Length()))
    if index <= widgets:Length() then
        local widget = widgets:Get(index)
        if widget then 
            print('---->initPlayAnimation:' .. tostring(index))
            --widget:StopAllAnimations()
            widget:PlayAnimationForward(widget.danru, 1, false)
        else
            LOG_ERROR('----not find ui:' .. tostring(index))
        end
    else
        print('--------error index:' .. tostring(index))
    end
    table.insert(self.DoAnimationIndexList, index)
    if #self.DoAnimationIndexList >= self.minValue then
        self.StartPlayAnim = false
        self.InitHideItemUI = false
    end
end


function M:BP_OnEntryInitialized(item, widget)
    local bIsSelected = self.SelectedItemIndex == item.index
    local bCurEquiped = widget.item_data.item_uuid == self.role_weapon_uuid
    widget.index = item.index
    widget.item_data = item.item_data
    widget.UI_Com_ItemBox:RefreshUI(item.item_data, false)
    widget.UI_Com_ItemBox:RefreshSelectState(bIsSelected)
    widget.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Hidden)

    for _, character_info in ipairs(self.characterInfos) do
        if character_info.weapon_info.item_uuid == widget.item_data.item_uuid then
            if not bCurEquiped then
                widget.UI_Com_ItemBox:RefreshRoleIcon(character_info.config.idolProfile)
                widget.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
            else
                widget.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped_Now)
            end
        end
    end
    if self.StartPlayAnim and self.InitHideItemUI then
        if item.index > self.MaxItemNumInDisplay then
            widget.Panel_Root:SetRenderOpacity(1)
        else
            widget.Panel_Root:SetRenderOpacity(0)
        end
    else
        widget.Panel_Root:SetRenderOpacity(1)
    end
end

function M:BP_OnItemClicked(item)
    print("====itemClicked:" .. tostring(self.SelectedItemIndex) .. ",index:" .. tostring(item.index) .. ",id:" .. tostring(item.ItemId))
    if self.SelectedItemIndex == item.index then return end

    self:PlayAnimationForward(self.switch, 1, false)

    self.SelectedItemIndex = item.index
    local widgets = self.List:GetDisplayedEntryWidgets()
    for _, widget in pairs(widgets) do
        local bIsSelected = widget.index == item.index
        widget.UI_Com_ItemBox:RefreshSelectState(bIsSelected)
    end

    local item_data = self.AllWeaponData[self.SelectedItemIndex]
    self.UI_Itemlist_siderbar:RefreshUI(item_data, false)
    local bEquiped = item_data.item_uuid == self.role_weapon_uuid
    if bEquiped then
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshRoleIcon(self.curCharacterInfo.config.idolProfile)
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Equipped)
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshReplacePanel(bEquiped)
    else
        self.UI_Itemlist_siderbar.UI_Com_ItemBox:RefreshSideUI(SideUI_State.Compare)
        self.UI_Itemlist_siderbar.UI_Com_BagDetail:RefreshReplacePanel(bEquiped)
    end
end

function M:SetBackUI(beforeUI, roleData)
    self.BackUI = beforeUI
    self.curCharacterInfo = roleData
    self:InitData()
    self:InitUI()
end

function M:OnClicked_Replace()
    local item_data = self.AllWeaponData[self.SelectedItemIndex]
    local is_equip = false
    local swap_character_info = {}
    for _, character_info in ipairs(self.characterInfos) do
        if character_info.weapon_info.item_uuid == item_data.item_uuid then
            is_equip = true
            swap_character_info = character_info
            break
        end
    end

    if not is_equip then
        if not self.waiting then
            self.waiting = true
            BackpackSystem:GetInstance():CacheReplaceWeaponOrEquip(self.curCharacterInfo.character_id, item_data)
            local msg = {
                character_id = self.curCharacterInfo.character_id,
                item_uuid = item_data.item_uuid
            }
            print("======req_character_equip_weapon:" .. tostring(table.dump(msg, false, 10)))
            Client.send("req_character_equip_weapon", msg)
        end
        self:CloseCompare()
    else
        local str = Database.L10n(5014006)
        local weapon_name = Database.L10n(item_data.config.itemName)
        local character_name = Database.L10n(swap_character_info.config.name)
        str = string.format(str, weapon_name, character_name)
        UIManager:GetInstance():ShowConfirm({
            notice = str,
            confirm = function()
                if not self.waiting then
                    self.waiting = true
                    CharacterSystem:GetInstance():CacheSwapWeapon(self.curCharacterInfo.character_id, swap_character_info.character_id)
                    local msg = {
                        character_id = self.curCharacterInfo.character_id,
                        other_character_id = swap_character_info.character_id
                    }
                    print("======req_character_swap_Weapon:" .. tostring(table.dump(msg, false, 10)))
                    Client.send("req_character_swap_weapon", msg)
                    self:CloseCompare()
                end
            end,
            showCancel = true,
        })
    end
end

function M:OnClicked_LevelUp()
    local item_data = self.AllWeaponData[self.SelectedItemIndex]
    local is_equip = false
    for _, character_info in ipairs(self.characterInfos) do
        if character_info.weapon_info.item_uuid == item_data.item_uuid then
            is_equip = true
            break
        end
    end
   
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance:OpenLink(9017, "") then
        self:SetVisibility(UE.ESlateVisibility.Hidden)
        local ui = gameInstance:GetUMG('UI_Levelup_weapon')
        ui:SetBackUI(self, item_data, true)
    end
end

function M:OnClicked_Refine()
    local item_data = self.AllWeaponData[self.SelectedItemIndex]
    self:SetVisibility(UE.ESlateVisibility.Hidden)
    local ui = UE4.UGameplayStatics.GetGameInstance(self):AddUMG('UI_weapon_refined')
    ui:SetBackUI(self, item_data, false)
end

function M:ShowCompare(new_weapon_data)
    self:PlayAnimationForward(self.inCompare, 1, false)
    local old_weapon_data = self.curCharacterInfo.weapon_info
    self.new:RefreshUI(new_weapon_data, false)
    self.new:RefreshCompareState(false)
    self.old:RefreshUI(old_weapon_data, false)
    self.old:RefreshCompareState(true)
    self.compare:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
end

function M:CloseCompare()
    self.compare:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:SetRoleVisibility(visible)
    self.BackUI:SetRoleVisibility(visible)
end

return M

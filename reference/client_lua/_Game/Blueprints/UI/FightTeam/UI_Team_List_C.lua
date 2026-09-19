--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"
local UIUtils = require "_Game.Utils.UIUtils"
local Database = require "_Game.Utils.Database"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"
local BossRushController = require("Module.BossRush.BossRushController")
local datamanager = require("DataCenter.DataManager")

---@type UI_Team_List_C
local UI_Team_List_C = Class()

UI_Team_List_C.HideCursor = false
UI_Team_List_C.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(UI_Team_List_C)

local ESelectedMode = {
    Single = 0,

    Multi = 1,
};

--构造函数
function UI_Team_List_C:Construct()
    self:InitData()
    self:InitUI()
    self.Overridden.Construct(self)
end

function UI_Team_List_C:Destruct()
        
end

function UI_Team_List_C:SetBackUI(ui, selectedMode, tag, selectedIndex)
    --print("===setBackUI:" .. tostring(tag) .. ',index:' .. tostring(selectedIndex))
    self.UITag = tag
    self.BackUI = ui
    self.SelectedMode = selectedMode
    self.SelectedTeamIndex = selectedIndex or 1 --ui_fight_start点击的模型索引
    --self.LastSelectedTeamIndex = self.SelectedTeamIndex
    self:RefreshUI(selectedIndex)

    if self.UITag == "CharacterSystem" then
        self.UI_Com_TeamBtn:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    --播放动画
    self:PlayAnimationForward(self.InitAnima)
end

function UI_Team_List_C:InitData()
    self.DefaultItemData = nil --默认当前位置的对象
    self.SelectedItemData = nil --单选时当前选中的对象
    self.AllSelectedItemData = {}
end

function UI_Team_List_C:InitUI()
    self.Img_Mask.OnMouseButtonDownEvent:Unbind()
    self.Img_Mask.OnMouseButtonDownEvent:Bind(self, self.OnClicked_Imag_Mask)

    self.BackButton.OnGHSClicked:Clear()
    self.BackButton.OnGHSClicked:Add(self, self.OnClicked_BackButton)

    self.UI_Com_TeamBtn.TeamFinish.OnGHSClicked:Clear()
    self.UI_Com_TeamBtn.TeamFinish.OnGHSClicked:Add(self, self.OnClicked_TeamFinish)

    self.UI_Com_TeamBtn.AddTeam.OnGHSClicked:Clear()
    self.UI_Com_TeamBtn.AddTeam.OnGHSClicked:Add(self, self.OnClicked_AddTeam)

    self.UI_Com_TeamBtn.LeaveTeam.OnGHSClicked:Clear()
    self.UI_Com_TeamBtn.LeaveTeam.OnGHSClicked:Add(self, self.OnClicked_LeaveTeam)

    self.UI_Com_TeamBtn.Position.OnGHSClicked:Clear()
    self.UI_Com_TeamBtn.Position.OnGHSClicked:Add(self, self.OnClick_Position)

    self.UI_Com_TeamBtn.Infomation.OnGHSClicked:Clear()
    self.UI_Com_TeamBtn.Infomation.OnGHSClicked:Add(self, self.OnClick_Infomation)

    --生成器
    self.UI_Com_TeamList.PersonList.BP_OnEntryInitialized:Clear()
    self.UI_Com_TeamList.PersonList.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.UI_Com_TeamList.PersonList.BP_OnItemClicked:Clear()
    self.UI_Com_TeamList.PersonList.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    --获取控制器组件
    if controller and controller.BP_PlayerController_City_UniverseBridge then
        controller.BP_PlayerController_City_UniverseBridge.OnDoDelayTimeStart:Add(self, self.OnDoDelayTimeStart)
        controller.BP_PlayerController_City_UniverseBridge.OnDoDelayTimeEnd:Add(self, self.OnDoDelayTimeEnd)
    end

    self.UI_Com_SortFilter.OnFinishedSort:Add(self, function()
        self:RefreshUI()
    end)

    self.UI_Com_SortFilter.OnFinishedFilter:Add(self, function()
        self:RefreshUI()
    end)

    local sortData = {}
    local SortTypes = { UIUtils.ESortType.Level, UIUtils.ESortType.Talent, UIUtils.ESortType.DEF, UIUtils.ESortType.Attack }
    local filterTypes = { UIUtils.EFilterType.WeaponType, UIUtils.EFilterType.ElementType }
    sortData.sortTypes = SortTypes
    sortData.filterTypes = filterTypes
    sortData.canFilter = true
    self.UI_Com_SortFilter:RefreshData(sortData)
end

function UI_Team_List_C:InitSaveGameTeamIdList()
    self.SaveGameTeamIdList = {}
    if self.BackUI then
        if self.UITag == 'FightStart' then
            local teamInfo = self.BackUI:GetCurTeamData()
            for i = 1, teamInfo.RoleList:Length() do
                self.SaveGameTeamIdList[i] = teamInfo.RoleList:Get(i)
            end
        end
    end
end

function UI_Team_List_C:InitRoleList()
    local CharacterSystem = require("Module.CharacterSystem.CharacterSystem")
    local characterInfo = {}
    for _, value in ipairs(CharacterSystem:GetInstance().CharacterInfo) do
        if self.BackUI and self.BackUI.LockedFlags then
            local isLocked = false
            for _, rId in ipairs(self.BackUI.LockedFlags) do 
                if value.character_id == rId then
                    isLocked = true
                    break
                end
            end
            if not isLocked then
                table.insert(characterInfo, value)
            end
        else
            table.insert(characterInfo, value)
        end
    end
    local RoleArray = {}
    local NormalArray = {}
    if self.UITag == 'FightStart' then
        for _, charInfo in pairs(characterInfo) do
            local isInTeam, index = self:IsInTeamByRoleId(charInfo.character_id, true)
            if isInTeam then
                RoleArray[index] = charInfo.character_id
            else
                table.insert(NormalArray, charInfo.character_id)
            end
        end
        table.sort(NormalArray, function(a, b)
            return a < b
        end)
    
        local result = {}
        for index = 1, 3 do 
            if RoleArray[index] then
                result[#result + 1] = RoleArray[index]
            end
        end
       
        for _, v in pairs(NormalArray) do
            table.insert(result, v)
        end
        self.SortRoleListData = result
    else
        local sortData = self.UI_Com_SortFilter:GetSortData()
        --filter
        local filterData = self.UI_Com_SortFilter.FilterData
        local filterCharacterData = {}
        for filterType, tags in pairs(filterData) do
            local tag_count = 0
            for key, value in pairs(tags) do
                tag_count = tag_count + 1
            end
            if filterType == UIUtils.EFilterType.WeaponType and tag_count > 0 then
                for _, charInfo in pairs(characterInfo) do
                    if tags[charInfo.config.profession] then
                        table.insert(filterCharacterData, charInfo)
                    end
                end
                characterInfo = filterCharacterData
                filterCharacterData = {}
            end
            if filterType == UIUtils.EFilterType.ElementType and tag_count > 0 then
                for _, charInfo in pairs(characterInfo) do
                    if tags[charInfo.config.element] then
                        table.insert(filterCharacterData, charInfo)
                    end
                end
                characterInfo = filterCharacterData
                filterCharacterData = {}
            end
        end

        --sort
        if sortData.selectedSortType == UIUtils.ESortType.Star then
            -- if #characterInfo > 1 then
            --     table.sort(characterInfo, function(a, b)
            --         if sortData.sortOrderUp then
            --             return a.character_id > b.character_id
            --         else
            --             return a.character_id < b.character_id
            --         end
            --     end)
            -- end
        elseif sortData.selectedSortType == UIUtils.ESortType.Level then
            if #characterInfo > 1 then
                table.sort(characterInfo, function(a, b)
                    if sortData.sortOrderUp then
                        if a.exp ~= b.exp then
                            return a.exp > b.exp
                        else
                            return a.character_id > b.character_id
                        end
                    else
                        if a.exp ~= b.exp then
                            return a.exp < b.exp
                        else
                            return a.character_id < b.character_id
                        end
                    end
                end)
            end
        elseif sortData.selectedSortType == UIUtils.ESortType.Talent then
            table.sort(characterInfo, function(a, b)
                if sortData.sortOrderUp then
                    if #a.talent_ids ~= #b.talent_ids then
                        return #a.talent_ids > #b.talent_ids
                    else
                        return a.character_id > b.character_id
                    end
                else
                    if #a.talent_ids ~= #b.talent_ids then
                        return #a.talent_ids < #b.talent_ids
                    else
                        return a.character_id < b.character_id
                    end
                end
            end)
        elseif sortData.selectedSortType == UIUtils.ESortType.DEF then
            table.sort(characterInfo, function(a, b)
                local a_Attrs = UIUtils.GetCharacterAllAttr(a.character_id, true)
                local b_Attrs = UIUtils.GetCharacterAllAttr(b.character_id, true)
                if sortData.sortOrderUp then
                    if a_Attrs[1024] ~= b_Attrs[1024] then
                        return a_Attrs[1024] > b_Attrs[1024]
                    else
                        return a.character_id > b.character_id
                    end
                else
                    if a_Attrs[1024] ~= b_Attrs[1024] then
                        return a_Attrs[1024] < b_Attrs[1024]
                    else
                        return a.character_id < b.character_id
                    end
                end
            end)
        elseif sortData.selectedSortType == UIUtils.ESortType.Attack then
            table.sort(characterInfo, function(a, b)
                local a_Attrs = UIUtils.GetCharacterAllAttr(a.character_id, true)
                local b_Attrs = UIUtils.GetCharacterAllAttr(b.character_id, true)
                if sortData.sortOrderUp then
                    if a_Attrs[1002] ~= b_Attrs[1002] then
                        return a_Attrs[1002] > b_Attrs[1002]
                    else
                        return a.character_id > b.character_id
                    end
                else
                    if a_Attrs[1002] ~= b_Attrs[1002] then
                        return a_Attrs[1002] < b_Attrs[1002]
                    else
                        return a.character_id < b.character_id
                    end
                end
            end)
        end 

        for _, charInfo in pairs(characterInfo) do
            table.insert(NormalArray, charInfo.character_id)
        end
        self.SortRoleListData = NormalArray
    end
end

function UI_Team_List_C:RefreshUI()
    self:InitSaveGameTeamIdList()
    self:InitRoleList()
    self.SelectedItemData = nil
    local ItemSourcePath = "'/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_ListRoleData.BP_ListRoleData_C'"
    local ItemClass = UE.UClass.Load(ItemSourcePath)
    --队列中排序(简单)
    self.ItemDataSource = {}
    
    for i = 1, #self.SortRoleListData do
        local ItemData = NewObject(ItemClass)   
        ItemData.Index = i
        ItemData.RoleId = self.SortRoleListData[i]
        table.insert(self.ItemDataSource, ItemData)
    end

    if self.SelectedMode == ESelectedMode.Single then
        local selectedRoleId = self:GetRoleIdByIndex(self.SelectedTeamIndex)
        self.DefaultItemData = nil
        if selectedRoleId > 0 then
            for k, itemdata in pairs(self.ItemDataSource) do 
                if itemdata.RoleId == selectedRoleId then
                    self.DefaultItemData = itemdata
                    break  
                end
            end
        end
        self.SelectedItemData = self.DefaultItemData
        --self:ChangeModel(self.SelectedTeamIndex, self.SelectedItemData and self.SelectedItemData.RoleId or 0)
    else
        self.AllSelectedItemData = {}
        local teamList = self.SaveGameTeamIdList
        for _, itemdata in pairs(self.ItemDataSource) do 
            for idx, rId in ipairs(teamList) do
                if itemdata.RoleId == rId then
                    self.AllSelectedItemData[idx] = itemdata
                end
            end
        end
    end
   
    self.UI_Com_TeamList.PersonList:ClearListItems()
    self.UI_Com_TeamList.PersonList:BP_SetListItems(self.ItemDataSource)

    self:RefreshOptionButton()
end

function UI_Team_List_C:RefreshRoleItem(item, widget)
    widget.Index = item.Index
    widget.RoleId = item.RoleId

    --选中状态
    local bSelected = false
    local bInTeam = false
    local teamIndex = -1
    if self.SelectedMode == ESelectedMode.Single then
        bSelected = self.SelectedItemData and (widget.Index == self.SelectedItemData.Index) or false
        --是否在队列,是否显示队伍序号
        bInTeam, teamIndex = self:IsInTeamByRoleId(item.RoleId)
    else
        bInTeam, teamIndex = self:IsInAllSelectedItemData(item.RoleId)
        bSelected = bInTeam
    end

    for i = 1, 3 do
        local bShow = (bInTeam and i == teamIndex) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden
        widget["Num" .. i]:SetVisibility(bShow)
    end

    widget.Num2_seleted:SetVisibility(UE.ESlateVisibility.Hidden)
    widget.Num3_seleted:SetVisibility(UE.ESlateVisibility.Hidden)
    if bSelected and bInTeam and teamIndex >= 0 then
        if teamIndex == 2 then
            widget.Num2_seleted:SetVisibility(UE.ESlateVisibility.Visible)
        elseif teamIndex == 3 then
            widget.Num3_seleted:SetVisibility(UE.ESlateVisibility.Visible)
        end
    end

    --选中状态
    local bVisible = bSelected and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden

    widget.choose:SetVisibility(bVisible)
    widget.Selected:SetVisibility(bInTeam and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    widget.Selected:SetVisibility((bInTeam and not bSelected) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    widget.NoSelect:SetVisibility((not bInTeam and not bSelected) and 
        UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    widget.choose2:SetVisibility(bVisible)
 
    local charConfig = require "ClientDatas.d_character"
    local roleConfig = charConfig[tonumber(item.RoleId)]
    if roleConfig then
        --头像
        local HeadPath = UIUtils.GetCharacterHeadIcon(roleConfig.id, roleConfig.headRes)
        local iconTexture = LoadObject(HeadPath)
        if iconTexture then
            widget.Head:SetBrushFromAtlasInterface(iconTexture)
        end
        --名字
        widget.Text_Name:SetText(UIUtils.GetCharacterName(roleConfig.id, roleConfig.name))

        local lv = 1
        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(roleConfig.id)
        if charInfo then
            lv, _, _ = UIUtils.GetCharacterLevel(charInfo.character_id, charInfo.break_times, charInfo.exp)
        end
        
        widget.Text_RoleId:SetText(lv)

        local iconPath = string.format("/Game/_Game/TP_New/Element_res/Frames/element_%s_s_png.element_%s_s_png", roleConfig.element, roleConfig.element)
        local iconObj = LoadObject(iconPath)
        if iconObj then
            widget.element:SetBrushFromAtlasInterface(iconObj)  
        end
    end

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.TeamContext then
        if gameInstance.TeamContext.type == 1 then
            local usedCharacters = BossRushController:GetInstance():GetOtherBossUsedCharacters(gameInstance.TeamContext.bossId)

            if table.indexof(usedCharacters, widget.RoleId) then
                widget.NativeButton:SetIsEnabled(false)
                widget.CannotSeleted:SetVisibility(UE.ESlateVisibility.Visible)
                widget:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
            end
        end
    end
end

--按钮显示
function UI_Team_List_C:RefreshOptionButton()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if self.SelectedMode == ESelectedMode.Multi then
        self.UI_Com_TeamBtn.Panel_Team:SetVisibility(UE.ESlateVisibility.Visible)

        self.UI_Com_TeamBtn.TeamFinish:SetVisibility(UE.ESlateVisibility.Visible)
        self.UI_Com_TeamBtn.LeaveTeam:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.AddTeam:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.Position:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.Infomation:SetVisibility((gameInstance.fightCanBack and self.SelectedItemData) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
    else
        self.UI_Com_TeamBtn.TeamFinish:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.Panel_Team:SetVisibility(self.SelectedItemData and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

        self.UI_Com_TeamBtn.LeaveTeam:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.Position:SetVisibility(UE.ESlateVisibility.Hidden)
        self.UI_Com_TeamBtn.AddTeam:SetVisibility(UE.ESlateVisibility.Hidden)

        self.UI_Com_TeamBtn.Infomation:SetVisibility((gameInstance.fightCanBack and self.SelectedItemData) and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

        if self.SelectedItemData then
            if self.DefaultItemData then
                if self.SelectedItemData == self.DefaultItemData then
                    self.UI_Com_TeamBtn.LeaveTeam:SetVisibility(UE.ESlateVisibility.Visible)
                else
                    local isInTeam, _ = self:IsInTeamByRoleId(self.SelectedItemData.RoleId)
                    if isInTeam then
                        self.UI_Com_TeamBtn.Position:SetVisibility(UE.ESlateVisibility.Visible)
                    else
                        self.UI_Com_TeamBtn.AddTeam:SetVisibility(UE.ESlateVisibility.Visible)
                    end
                end
            else
                local isInTeam, _ = self:IsInTeamByRoleId(self.SelectedItemData.RoleId)
                if isInTeam then
                    self.UI_Com_TeamBtn.Position:SetVisibility(UE.ESlateVisibility.Visible)
                else
                    self.UI_Com_TeamBtn.AddTeam:SetVisibility(UE.ESlateVisibility.Visible)
                end
            end
        end
    end
end

function UI_Team_List_C:SetEnableAllButton(bEnable)
    self.Img_Mask:SetIsEnabled(bEnable)
    self.BackButton:SetIsEnabled(bEnable)
    -- self.TeamFinish:SetIsEnabled(bEnable)
    -- self.AddTeam:SetIsEnabled(bEnable)
    -- self.LeaveTeam:SetIsEnabled(bEnable)
    -- self.Position:SetIsEnabled(bEnable)
    self.UI_Com_TeamBtn.Panel_Team:SetIsEnabled(bEnable)
    self.UI_Com_TeamBtn.Infomation:SetIsEnabled(bEnable)

    if bEnable then
        self:RefreshOptionButton()
    end
end

function UI_Team_List_C:ChangeModel(index, roleList)
    if self.SelectedMode == ESelectedMode.Single then
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        --获取控制器组件
        if controller and controller.BP_PlayerController_City_UniverseBridge then
            controller.BP_PlayerController_City_UniverseBridge:ChangeModel(index, roleList)
        end
    end
end

function UI_Team_List_C:SwapModel(roleList)
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    --获取控制器组件
    if controller and controller.BP_PlayerController_City_UniverseBridge then
        controller.BP_PlayerController_City_UniverseBridge:SwapTeamModel(self.SelectedTeamIndex, roleList, true)
        --controller.BP_PlayerController_City_UniverseBridge:ChangeRoleCamera(self.SelectedTeamIndex, false, self.SelectedItemData and self.SelectedItemData.RoleId or 0)
    end
end

--判断是否在队伍中
function UI_Team_List_C:IsInTeamByRoleId(RoleId, forceTeamData)
    if RoleId == 0 then return false, 0 end
    -- if self.SelectedMode == ESelectedMode.Single then
        if self.UITag == "FightStart" then
            for idx, rid in ipairs(self.SaveGameTeamIdList) do
                if rid == RoleId then
                    return true, idx
                end
            end
        else
            return false, 0
        end
    -- else
    --     for k, data in pairs(self.AllSelectedItemData) do
    --         if data and data.RoleId == RoleId then
    --             return true, k
    --         end
    --     end
    -- end
    return false, 0
end

function UI_Team_List_C:GetRoleIdByIndex(index)
    if self.BackUI then
        if self.UITag == "FightStart" then
            return self.SaveGameTeamIdList[index]
        else
            local char_id = CharacterSystem:GetInstance().CharacterInfo[index].character_id
            return char_id
        end
    end
    return 0
end

function UI_Team_List_C:GetIndexByRoleId(index)
    --还原筛选排序前的index
    if self.BackUI then
        if self.UITag ~= "FightStart" then
            local char_id = self.SortRoleListData[index]
            for index, charInfo in ipairs(CharacterSystem:GetInstance().CharacterInfo) do
                if char_id == charInfo.character_id then
                    return index
                end
            end
        end
    end
    return 0
end

--------------------------------------------------------------------------------
---定时器
function UI_Team_List_C:OnDoDelayTimeStart()
    self:SetEnableAllButton(false)
end

function UI_Team_List_C:OnDoDelayTimeEnd()
    self:SetEnableAllButton(true)
end

----------------------------------------------------------------------
---ui事件
function UI_Team_List_C:BP_OnEntryInitialized(item, widget)
    if widget.InitAnima then
        widget:PlayAnimationForward(widget.InitAnima, 1, false)
    end
    self:RefreshRoleItem(item, widget)
end

function UI_Team_List_C:BP_OnItemClicked(item)
    local widgets = self.UI_Com_TeamList.PersonList:GetDisplayedEntryWidgets()
    if self.SelectedMode == ESelectedMode.Single then
        if self.SelectedItemData and self.SelectedItemData == item then 
            return 
        end

        local lastSelectedItemData = self.SelectedItemData

        if self.UITag == "FightStart" then
            local delayTime = 0.5
            local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
            --获取控制器组件
            if controller and controller.BP_PlayerController_City_UniverseBridge then
                delayTime = controller.BP_PlayerController_City_UniverseBridge.ChangePlayerWaitTime or delayTime
            end
            delayTime = delayTime + 0.1

            --时间判断
            self.LastSingleClick = self.LastSingleClick or 0
            local clickTime = UE.UKismetSystemLibrary.GetGameTimeInSeconds(self)
            if clickTime - self.LastSingleClick < delayTime then
                return
            end
            self.LastSingleClick = clickTime 
            self.SelectedItemData = item

            for i = 1, widgets:Length() do
                local widget = widgets:Get(i)
                --old selected item
                if lastSelectedItemData and widget.Index == lastSelectedItemData.index then
                    self:RefreshRoleItem(lastSelectedItemData, widget)
                end
                --new selected item
                if widget.Index == item.Index then
                    self:RefreshRoleItem(item, widget)
                end
            end
            self:RefreshOptionButton()

            --获取当前选中的index
            local inTeam, index = self:IsInTeamByRoleId(self.SelectedItemData.RoleId)

            --缓存一份原来固有角色列表

            local newRoleList = {}
            for idx, rid in ipairs(self.SaveGameTeamIdList) do
                newRoleList[idx] = rid
            end


            if inTeam then
                local tempRoleId = newRoleList[self.SelectedTeamIndex]
                newRoleList[self.SelectedTeamIndex] = newRoleList[index]
                newRoleList[index] = tempRoleId

                self:SwapModel(newRoleList)
            else
                local selectedRoleId = self.SelectedItemData and self.SelectedItemData.RoleId or 0
                newRoleList[self.SelectedTeamIndex] = selectedRoleId
                self:ChangeModel(self.SelectedTeamIndex, newRoleList)
            end
        elseif self.UITag == "CharacterSystem" then
            if self.BackUI then
                local index = self:GetIndexByRoleId(item.Index)
                self.BackUI:SelectedRole(index)
                UIManager:GetInstance():RemoveUI(self)
            end
        end
    else
        local inTeam, inTeamIdx = self:IsInAllSelectedItemData(item.RoleId)
        if inTeam and inTeamIdx > 0 then
            self.AllSelectedItemData[inTeamIdx] = nil
        else
            local count = 0
            for k, v in pairs(self.AllSelectedItemData) do 
                count = count + 1
            end
            ---判断当前是否满
            if count < 3 then
                for index = 1, 3 do 
                    --判断是否锁住
                    if self.BackUI and self.BackUI.LockedFlags then
                        local isLocked = false
                        for idx, roleId in ipairs(self.BackUI.LockedFlags) do 
                            if idx == index and roleId > 0 then
                                isLocked = true
                                break
                            end
                        end
                        if not isLocked then
                            if not self.AllSelectedItemData[index] then
                                self.AllSelectedItemData[index] = item
                                break
                            end
                        else
                            local DataBase = require('_Game.Utils.Database')
                            UIUtils.ShowNotify(self, DataBase.L10n(315))
                        end
                    end
                end 
                --table.insert(self.AllSelectedItemData, item)
            else
                --选中的已经>=3
                return
            end
        end
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            --new selected item
            if widget.Index == item.Index then
                self:RefreshRoleItem(item, widget)
            end
        end
        --选中的其他
        for _, selectedItem in pairs(self.AllSelectedItemData) do 
            for i = 1, widgets:Length() do
                local widget = widgets:Get(i)
                --new selected item
                if widget.Index == selectedItem.Index then
                    self:RefreshRoleItem(selectedItem, widget)
                end
            end
        end
    end
end

function UI_Team_List_C:IsInAllSelectedItemData(roleId)
    for idx, tItem in pairs(self.AllSelectedItemData) do
        if tItem.RoleId == roleId then
            return true, idx
        end
    end
    return false, 0
end

function UI_Team_List_C:OnClicked_BackButton()
    if self.BackUI then
        if self.UITag == "FightStart" then
            self.BackUI:RefreshModel()
            self.BackUI:SetAllChairListCollision(true)
            if self.SelectedMode == ESelectedMode.Multi then
                self.BackUI:SetVisibility(UE.ESlateVisibility.Visible)
            end
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end

    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(UI_Team_List_C, InputAssets.IA_Back, UE.ETriggerEvent.Completed, UI_Team_List_C.OnClicked_BackButton)

function UI_Team_List_C:OnClicked_TeamFinish()
   
    if self.BackUI then
        if self.UITag == "FightStart" then
            local roleList = {}
            for index, data in pairs(self.AllSelectedItemData) do
                roleList[index] = data and data.RoleId or 0
            end
            if self.BackUI and self.BackUI.LockedFlags then
                for idx, roleId in ipairs(self.BackUI.LockedFlags) do 
                    if roleId > 1 then
                        roleList[idx] = roleId
                        break
                    end
                end
            end

            self.BackUI:QuickEditTeam(roleList)
            self.BackUI:SetVisibility(UE.ESlateVisibility.Visible)
            self.BackUI:SetAllChairListCollision(true)
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end
    UIManager:GetInstance():RemoveUI(self)
end

function UI_Team_List_C:OnClicked_AddTeam()
    if self.BackUI then
        if self.UITag == "FightStart" then
            if self.DefaultItemData then
                self.BackUI:ChangeRole(self.SelectedTeamIndex, self.SelectedItemData.RoleId)
            else
                self.BackUI:AddRole(self.SelectedItemData.RoleId)
            end
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end
    UIManager:GetInstance():RemoveUI(self)
end

function UI_Team_List_C:OnClicked_LeaveTeam()
    if self.BackUI then
        if self.UITag == "FightStart" then
            local _, Index = self:IsInTeamByRoleId(self.SelectedItemData.RoleId)
            self.BackUI:RemoveRole(Index)
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end
    UIManager:GetInstance():RemoveUI(self)
end

function UI_Team_List_C:OnClicked_Imag_Mask()
    if self.BackUI then
        if self.UITag == "FightStart" then
            self.BackUI:RefreshModel()
            if self.SelectedMode == ESelectedMode.Multi then
                self.BackUI:SetVisibility(UE.ESlateVisibility.Visible)
                self.BackUI:SetAllChairListCollision(true)
            end
           
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end
    UIManager:GetInstance():RemoveUI(self)
    return UE.UWidgetBlueprintLibrary.Handled()
end

function UI_Team_List_C:OnClick_Position()
    if self.BackUI then
        if self.UITag == "FightStart" then
            --self.BackUI:RefreshModel()
            local bInTeam, Index = self:IsInTeamByRoleId(self.SelectedItemData.RoleId)
            if bInTeam then
                self.BackUI:SwapRole(Index, self.SelectedTeamIndex)
                self.BackUI:ChangeRoleCamera(0, false)
                if self.SelectedMode == ESelectedMode.Single then
                    self.BackUI:SetVisibility(UE.ESlateVisibility.Visible)
                    self.BackUI:SetAllChairListCollision(true)
                end
            end
        elseif self.UITag == "CharacterSystem" then
            self.BackUI:OnBack()
        end
    end
    UIManager:GetInstance():RemoveUI(self)
end

function UI_Team_List_C:OnClick_Infomation()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local isOpen, _ = gameInstance:OpenLinkEx(9009, false)
    if isOpen then
        local charInfo = CharacterSystem:GetInstance():GetCharacterInfoById(self.SelectedItemData.RoleId)
        if not charInfo then
            local tip = ''
            local charConfig = require('ClientDatas.d_character')[self.SelectedItemData.RoleId]
            if charConfig and charConfig.name then
                tip = Database.L10n(charConfig.name) .. '<' .. Database.L10n(charConfig.mechName) .. '>'
            end
            UIUtils.ShowNotify(self, Database.L10n(451) .. tip)
            return
        end
        local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
        --获取控制器组件
        if controller and controller.BP_PlayerController_City_UniverseBridge then
            controller.BP_PlayerController_City_UniverseBridge:LoadCharacterSystem(self.SelectedItemData.RoleId)
        end
        UIManager:GetInstance():RemoveUI(self)
    end
end

----------------------------------------------------------------------
---

return UI_Team_List_C
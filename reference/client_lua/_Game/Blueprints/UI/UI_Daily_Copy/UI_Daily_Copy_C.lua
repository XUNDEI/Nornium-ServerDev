--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"
local d_levels = require "ClientDatas.d_levels"
local UIUtils = require "_Game.Utils.UIUtils"
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Daily_Copy_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)


function M:Construct()
    self:InitData()
end

function M:InitData()
    self.InitItemID = 0
end

function M:InitUIEx(args)
    self:InitUI(args)
end

--npcType 1:一三五小姐，负责经验本、钱本 2:二四六小姐，负责技能材料本、突破材料本、锻造素材本
function M:InitUI(npcType)
    npcType = npcType and tonumber(npcType) or 1
    self.npcType = npcType

    self.Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Close.OnGHSClicked:Add(self, self.OnClicked_Btn_Close)
    self.Btn_Start.OnGHSClicked:Add(self, self.OnClicked_Btn_Start)

    self.ExplainBtn.OnGHSClicked:Add(self, self.OnClicked_ExplainBtn)

    --生成器
    self.List_Mat.BP_OnEntryInitialized:Clear()
    self.List_Mat.BP_OnEntryInitialized:Add(self, function(wbp, item, widget) 
        self:BP_OnEntryInitialized(item, widget)
    end)
    --点击事件
    self.List_Mat.BP_OnItemClicked:Clear()
    self.List_Mat.BP_OnItemClicked:Add(self, function(wbp, item)
        self:BP_OnItemClicked(item)
    end)

    --树。列表
    self.TreeView.BP_OnEntryInitialized:Add(self, function(wbp, data, ui)
        self:BP_OnEntryInitialized_TreeView(data, ui)
    end)

    self.TreeView.BP_OnItemExpansionChanged:Add(self, function(wbp, data, expand)
        self:BP_OnItemExpansionChanged_TreeView(data, expand)
    end)

    self.TreeView.BP_OnItemClicked:Add(self, function(wbp, data)
        self:BP_OnItemClicked_TreeView(data)
    end)

    self.OnVisibilityChanged:Add(self, function(ui, bIsVisible)
        -- print('----visible:' .. tostring(bIsVisible))
        -- if bIsVisible then
        --     local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        --     pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        -- end
    end)

    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if not pc.BP_PlayerController_City_UniverseBridge.BlockInputAction then
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
        self.InitIsBlock = true
    end
   
    self.SelectedIndex = 1
   
    --票据
    local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
    if ticket_count <= 0 then
        ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
        local iconPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201001_png.Icon_mini_1201001_png'
        local iconRes = LoadObject(iconPath)
        if iconRes then
            self.Image_2:SetBrushFromAtlasInterface(iconRes)
        end
    else
        local iconPath = '/Game/_Game/TP_New/Common/Frames/Icon_mini_1201003_png.Icon_mini_1201003_png'
        local iconRes = LoadObject(iconPath)
        if iconRes then
            self.Image_2:SetBrushFromAtlasInterface(iconRes)
        end
    end
    self.Text_NeedGold:SetText('1')
    self.Text_HaveGold:SetText("/" .. tostring(ticket_count))

    self.costbase.OnMouseButtonDownEvent:Bind(self, function()
        local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
        if ticket_count <= 0 then
            UIUtils.ShowItemInfo(UIUtils.EItemId.DailyCopySweep)
        else
            UIUtils.ShowItemInfo(UIUtils.EItemId.DailyCopyTicket)
        end
        
        return UE.UWidgetBlueprintLibrary.Handled()
    end)

    self:RefreshTreeView()
    self:InitTreeViewData()
end

function M:InitTreeViewData()
    self.MaxItemNumInDisplay = 7
    local uiNum = table.count(self.MainItemDataSource)
    if self.LastSelectedItemData then
        if self.AllChildItemDataSource[self.LastMainItemData.Index] then
            uiNum = uiNum + #self.AllChildItemDataSource[self.LastMainItemData.Index]
        end
    end
    self.minValue = math.min(self.MaxItemNumInDisplay, uiNum)
    self.Time1 = 0.04 --每个item时间间隔
    self.DoAnimationIndexList = {}
    self.PastTime = 0
    self.InitHideItemUI = true
    self.StartPlayAnim = self.minValue > 0 
end


function M:Tick(MyGeometry, InDeltaTime)
    if self.StartPlayAnim then
        local uiNum = self.TreeView:GetDisplayedEntryWidgets():Length()
        local itemNum = self.minValue
        if uiNum >= itemNum then
            self.PastTime = self.PastTime + InDeltaTime
            for i = 1, self.minValue do 
                local curTime = self.Time1 * (i - 1)
               
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
    local widgets = self.TreeView:GetDisplayedEntryWidgets()
    print('----index:' .. tostring(index) .. ',array:' .. tostring(#self.DoAnimationIndexList) .. ', count:' .. tostring(widgets:Length()))
    if index <= widgets:Length() then
        local widget = widgets:Get(index)
        if widget then 
            -- widget:StopAllAnimations()
            widget:PlayAnimationForward(widget.InitAnimation, 1, false)
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

function M:GetLevelConfig(levelId)
    for _, levelInfo in pairs(d_levels) do 
        if levelInfo.id == levelId then
            return levelInfo
        end
    end
    return nil
end

function M:UnlockLevel(type)
    local maxPassedLv = 0
    for _, passed_id in ipairs(BackpackSystem:GetInstance().PlayerInfo.daily_level_id_passed) do
        local config = self:GetLevelConfig(passed_id)
        if config and config.levelType == type then
            maxPassedLv = maxPassedLv > passed_id and maxPassedLv or passed_id
        end
    end
    -- print('---type:' .. tostring(type) .. ",maxLevel:" .. tostring(maxPassedLv))
    return maxPassedLv
end

function M:BP_OnEntryInitialized(item, widget)
    local itemConfig = UIUtils.GetItemConfigById(item.ItemId)
    local data = {}
    data.config = itemConfig
    widget.index = item.index
    widget.item_data = itemConfig
    if itemConfig then
        --widget.Text_Count:SetText(itemData and itemData.count or "1")
        --widget.Text_Count:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.Text_Count:SetText(Database.L10n(itemConfig.itemName))
        --稀有度背景图片
        if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
            local strArr = string.split(itemConfig.rarityPath, '/')
            local littePath = strArr[#strArr]
            local rarityPath = string.format('/Game/_Game/%s.%s', itemConfig.rarityPath, littePath)
            local itemRarityPic = LoadObject(rarityPath)
            if itemRarityPic then
                widget.wp_container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
            end
        end
        
        --类型
        --icon
        if itemConfig.iconPath and itemConfig.iconPath ~= '' then
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            local strArr = string.split(itemConfig.iconPath, '/')
            local littePath = strArr[#strArr]
            local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
            local iconRes = LoadObject(iconResPath)
            if iconRes then
                widget.wp_icon_res:SetBrushFromAtlasInterface(iconRes)
            end
        else
            widget.wp_icon_res:SetVisibility(UE.ESlateVisibility.Collapsed)
        end
    end
end

--刷新ui
function M:RefreshUI(tabIdx, levelIdx)
    print("===daily copy: " .. tostring(tabIdx) .. ",level:" .. tostring(levelIdx))
    self:RefreshSelectedItem(tabIdx)
    self:TabSelected(tabIdx)
end

function M:RefreshSelectedItem(level_index)
    -- local oldItem = self.UI_Tab_Daily_Copy.ScrollBox:GetChildAt(self.SelectedIndex - 1)
    -- if oldItem then
    --     oldItem.selected:SetVisibility(UE.ESlateVisibility.Collapsed)
    -- end
    -- local nowItem = self.UI_Tab_Daily_Copy.ScrollBox:GetChildAt(level_index - 1)
    -- nowItem.selected:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    -- self.SelectedIndex = level_index
end

function M:RefreshTreeView()
    self.level_infos = {}

    local tempLvs = {}
    local dayOfWeek = UIUtils.GetDayOfWeek()
    for _, level_info in ipairs(d_levels) do
        for _, openDay in ipairs(level_info.openTime) do
            local isTypeOne = self.npcType == 1 and (level_info.levelType == 3 or level_info.levelType == 4) 
            local isTypeTwo = self.npcType == 2 and (level_info.levelType == 1 or level_info.levelType == 5)
            if dayOfWeek == openDay and (isTypeOne or isTypeTwo) then
                if not tempLvs[level_info.levelType] then
                    tempLvs[level_info.levelType] = {}
                end
                table.insert(tempLvs[level_info.levelType], level_info)
            end
        end
    end
    print("=========日常副本通关:") 
    print("==>>daily_level_id_passed:" .. table.dump(BackpackSystem:GetInstance().PlayerInfo.daily_level_id_passed, false, 10))
    for lvType, lvs in pairs(tempLvs) do
        if not self.level_infos[lvType] then
            self.level_infos[lvType] = {}
        end
        for index, level_info in ipairs(lvs) do
            
            if index ~= 1 then
                level_info.bPassed = level_info.id <= (self:UnlockLevel(level_info.levelType) + 1)
            else
                level_info.bPassed = true
            end
            table.insert(self.level_infos[lvType], level_info)
        end
    end

    self.TreeView:ClearListItems()
    self.MainItemDataSource = {}
    self.SubItemDataSource = {}
    self.AllChildItemDataSource = {}

    self.LastSelectedItemData = nil
    self.LastMainItemData = nil

    local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Quest/UI_Data/BP_QuestData.BP_QuestData_C'
    local ItemClass = UE.UClass.Load(ItemSourcePath)

    local defaultSelectedItemData = nil
    local initSelectedItemData = nil
    local mainIdx = 1
    for type, datas in pairs(self.level_infos) do
        local mainItemData = NewObject(ItemClass)
        mainItemData.Index = type
        mainItemData.ID = type
        mainItemData.Layer = 1
        for idx, entry in ipairs(datas) do 
            local subItemData = NewObject(ItemClass)
            subItemData.Index = type
            subItemData.ID = entry.id
            subItemData.Layer = 2
            mainItemData.Children:Add(subItemData)
            self.SubItemDataSource[entry.id] = subItemData

            if not self.AllChildItemDataSource[type] then 
                self.AllChildItemDataSource[type] = {}
            end
            table.insert(self.AllChildItemDataSource[type], subItemData)
            
            if mainIdx == 1 and idx == 1 then
                defaultSelectedItemData = subItemData
            end

            if not initSelectedItemData then
                if self.InitItemID > 0 then
                    if entry.id == self.InitItemID then
                        initSelectedItemData = subItemData
                    end
                end
            end
        end
        self.TreeView:AddItem(mainItemData)
        self.MainItemDataSource[type] = mainItemData

        mainIdx = mainIdx + 1
    end

    if not initSelectedItemData then initSelectedItemData = defaultSelectedItemData end
    if initSelectedItemData then
        self:ScrollItem(initSelectedItemData)
    end

    self:RefreshDetailPanel()
end

function M:RefreshDetailPanel()
    if self.LastSelectedItemData then
        self:PlayAnimationForward(self.switch, 1, false)
        self.LevelId = self.LastSelectedItemData.ID

        --缓存下，不用每次都换图片
        if not self.CachedMainIndex or self.CachedMainIndex ~= self.LastSelectedItemData.Index then
            --背景图片
            local path = '/Game/_Game/TP_New/DailyCopy/Res/L_' .. self.LastSelectedItemData.Index .. '.L_' .. self.LastSelectedItemData.Index
            print("---path:" .. tostring(path))
            local bgObj = LoadObject(path)
            if bgObj then
                self.Img_Info_Bg:SetBrushFromTexture(bgObj)
            end
            self.CachedMainIndex = self.LastSelectedItemData.Index
        end
       

        local level_info = nil
        if self.level_infos[self.LastSelectedItemData.Index] then
            for idx, levelInfo in pairs(self.level_infos[self.LastSelectedItemData.Index]) do
                if levelInfo.id == self.LevelId then
                    level_info = levelInfo
                    break
                end
            end
        end
       
        -- print('===选中:' .. tostring(level_index) .. ",id:" .. tostring(level_info.id))
        if level_info then
            local level_name = Database.L10n(level_info.levelName)
            local level_desc = Database.L10n(level_info.levelDesc)
            self.Text_Copy_Name:SetText(level_name)
            self.Text_Copy_Desc:SetText(level_desc)

            self.Text_NeedLv:SetText(level_info.proposeLevel)

            local dropItems = level_info.dropID
            local rewardIds = {}
            for _, id in ipairs(dropItems) do
                rewardIds[id] = 1
            end
            local result = {}
            for id, _ in pairs(rewardIds) do
                table.insert(result, id)
            end

            table.sort(result, function(aId, bId) 
                return aId < bId
            end)

            local ItemSourcePath = '/Game/_Game/Blueprints/UI/UI_Backpack/UI_Data/BP_BackpackItemData.BP_BackpackItemData_C'
            local ItemClass = UE.UClass.Load(ItemSourcePath)
            self.ItemDataSource = {}
            for i = 1, #result do
                local ItemData = NewObject(ItemClass)
                ItemData.Index = i
                ItemData.ItemId = result[i]
                table.insert(self.ItemDataSource, ItemData)
            end

            if level_info.bPassed then
                local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 1.0)
                self.Btn_Start:SetColorAndOpacity(opacity)
                self.Btn_Start:SetVisibility(UE.ESlateVisibility.Visible)

                local ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopyTicket)
                if ticket_count < 1 then
                    ticket_count = BackpackSystem:GetInstance():GetItemCount(UIUtils.EItemId.DailyCopySweep)
                end
                
                if ticket_count < 1 then
                    local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
                    self.Btn_Start:SetColorAndOpacity(opacity)
                    self.Btn_Start:SetVisibility(UE.ESlateVisibility.HitTestInvisible)

                    self.Panel_Tips:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                    self.Text_Tips:SetText(Database.L10n(272))
                else
                    self.Panel_Tips:SetVisibility(UE.ESlateVisibility.Hidden)
                end
            else
                local opacity = UE.FLinearColor(1.0, 1.0, 1.0, 0.5)
                self.Btn_Start:SetColorAndOpacity(opacity)
                self.Btn_Start:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                self.Panel_Tips:SetVisibility(UE.ESlateVisibility.HitTestInvisible)
                self.Text_Tips:SetText(Database.L10n(271))
            end

            self.List_Mat:ClearListItems()
            self.List_Mat:BP_SetListItems(self.ItemDataSource)
        end
    end
end

function M:GetItem(itemData)
    local widgets = self.TreeView:GetDisplayedEntryWidgets()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.Index == itemData.Index and widget.Layer == itemData.Layer and widget.ID == itemData.ID then
            return widget
        end
    end
    return nil
end

function M:ScrollItem(subItem)
    for _, mainItemData in pairs(self.MainItemDataSource) do
        local ui = self:GetItem(mainItemData)
        if ui then
            self:RefreshMainItem(ui, false)
        end
    end
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, false)
        end
    end
    self.LastSelectedItemData = subItem

    self.TreeView:CollapseAll()
    if subItem then
        local expandItemData = self.MainItemDataSource[subItem.Index]
        if expandItemData then
            self.LastMainItemData = expandItemData
            self.TreeView:SetItemExpansion(expandItemData, true)
            self.TreeView:BP_ScrollItemIntoView(expandItemData)
            self.TreeView:BP_ScrollItemIntoView(subItem)
        end
    end

    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, true)
        end
    end

    self:RefreshDetailPanel()
end

function M:RefreshMainItem(ui, isExpand)
    ui.Panel_Main_Normal:SetRenderOpacity(not isExpand and 1 or 0)
    ui.Panel_Main_Selected:SetRenderOpacity(isExpand and 1 or 0)

    -- if isExpand then
    --     ui:PlayAnimationForward(ui.selected, 1, false)
    -- else
    --     ui:PlayAnimationReverse(ui.selected, 1, false)
    -- end
end

function M:RefreshSubItem(ui, selected, isClicked)
    if not isClicked then
        ui.Img_Sub_Selected:SetRenderOpacity(selected and 1 or 0)
        ui.Text_Sub_Normal_Name:SetRenderOpacity(not selected and 1 or 0)
        ui.Text_Sub_Selected_Name:SetRenderOpacity(selected and 1 or 0)
    else
        if selected then
            ui:PlayAnimationForward(ui.selected, 1, false)
        else
            ui:PlayAnimationReverse(ui.selected, 1, false)
        end
    end
end

--树。列表
function M:BP_OnEntryInitialized_TreeView(data, ui)
    ui.Index = data.Index
    ui.Layer = data.Layer
    ui.ID = data.ID

    ui.Panel_Main:SetVisibility(data.Layer == 1 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    ui.Panel_Sub:SetVisibility(data.Layer == 2 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
    
    if data.Layer == 1 then
        --副本大类类型
        ui.Text_Type:SetText(Database.L10n(816000100 + ui.ID))
        --副本大类名字
        local MainName = Database.L10n(816000200 + ui.ID)
        ui.Text_Main_Normal_Name:SetText(MainName)
        ui.Text_Main_Selected_Name:SetText(MainName)

        local path = '/Game/_Game/TP_New/DailyCopy/Res/S_' .. ui.ID .. '.S_' .. ui.ID
        local bgObj = LoadObject(path)
        if bgObj then
            ui.Img_Main_Normal_Bg:SetBrushFromTexture(bgObj)
            ui.Img_Main_Selected_Bg:SetBrushFromTexture(bgObj)
        end
        
        local isExpand = data.Index == self.LastSelectedItemData.Index
        self:RefreshMainItem(ui, isExpand)
    else
        local config = d_levels[ui.ID]
        if config then
            ui.TextLevel:SetText(string.format(Database.L10n(816000301), config.proposeLevel))
            --难度
            -- ui.Img_Difficulty:SetColorAndOpacity(EDailyCopyDifficultyColor[config.levelDifficulty])

            ui.Text_Sub_Normal_Name:SetText(Database.L10n(config.levelName))
            ui.Text_Sub_Selected_Name:SetText(Database.L10n(config.levelName))
            
            local itemLevelInfo = nil
            if self.level_infos[ui.Index] then
                for idx, levelInfo in pairs(self.level_infos[ui.Index]) do
                    if levelInfo.id == ui.ID then
                        itemLevelInfo = levelInfo
                        break
                    end
                end
            end
           
            if itemLevelInfo then
                ui.Img_Lock:SetRenderOpacity(not itemLevelInfo.bPassed and 1 or 0)
            end
        end
        
        self:RefreshSubItem(ui, data == self.LastSelectedItemData)
    end

    if self.StartPlayAnim and self.InitHideItemUI then
        if data.index > self.MaxItemNumInDisplay then
            ui.Panel_Root:SetRenderOpacity(1)
        else
            ui.Panel_Root:SetRenderOpacity(0)
        end
    else
        ui.Panel_Root:SetRenderOpacity(1)
    end
end

function M:BP_OnItemExpansionChanged_TreeView(data, expand)
    if data.Layer == 1 then
        local ui = self:GetItem(data)
        if ui then
            self:RefreshMainItem(ui, expand)
        end
    end
end

function M:BP_OnItemClicked_TreeView(data)
    if data.Layer == 1 then
        if self.LastMainItemData == data then
            return
        end
        --if self.LastMainItemData
        -- for _, mainItemData in pairs(self.MainItemDataSource) do
        --     self.TreeView:SetItemExpansion(mainItemData, mainItemData == data)
        -- end

        if self.LastMainItemData then
            self.TreeView:SetItemExpansion(self.LastMainItemData, false)
            local ui = self:GetItem(self.LastMainItemData)
            if ui then
                self:RefreshMainItem(ui, false, true)
            end
        end

        self.LastMainItemData = data

        if self.LastMainItemData then
            self.TreeView:SetItemExpansion(self.LastMainItemData, true)
            local ui = self:GetItem(self.LastMainItemData)
            if ui then
                self:RefreshMainItem(ui, true, true)
            end
        end

        --选中子item 最高可解锁的
        local targetId = -1
        for _, v in ipairs(self.level_infos[data.ID]) do
            if v.bPassed then
                targetId = math.max(targetId, v.id)
            end
        end
        if targetId > 0 then
            self.LastSelectedItemData = self.SubItemDataSource[targetId]
        end

        if self.LastSelectedItemData then
            local ui = self:GetItem(self.LastSelectedItemData)
            if ui then
                self:RefreshSubItem(ui, true, true)
            end
        end
        self:RefreshDetailPanel()
        return
    end

    if data.Layer ~= 2 or self.LastSelectedItemData == data then return end
    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, false, true)
        end
    end
    self.LastSelectedItemData = data

    if self.LastSelectedItemData then
        local ui = self:GetItem(self.LastSelectedItemData)
        if ui then
            self:RefreshSubItem(ui, true, true)
        end
    end
    self:RefreshDetailPanel()
end

---点击事件
---------------------------------------------------------

function M:BP_OnItemClicked(item)
    UIUtils.ShowItemInfo(item.ItemId)
end

function M:OnClicked_Btn_Close()
    if self.InitIsBlock then
        local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
        pc.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
        self.InitIsBlock = false
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveTopUI(true)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Close)

function M:OnClicked_Btn_Start()
    
    --判断是否在角色界面
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local curLevelName = gameInstance:TopSubLevelName()
    print("--------curlevelName:" .. tostring(curLevelName))
    if curLevelName == 'CharecterScene' then
        
        gameInstance.OnBackStreamLevelEnd:Add(self, self.OnBackLevel)
        gameInstance:BackStreamLevel(true)
        return
    end
  
    self:OnBackLevel()
end

function M:OnClicked_ExplainBtn()
    UIUtils.ShowSystemDes(1004)
end

function M:OnBackLevel()
   
    print("------------------>>UI_Daily_Copy_C")
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:HideAllUI()

    local level_path = '/Game/_Game/Blueprints/Levels/ARPG/Level_Dungeon/%s/%s.%s_C'
    local level_id = d_levels[self.LevelId].path
    level_path = string.format(level_path, level_id, level_id, level_id)
    local fightLevelClass = UE.LoadClass(level_path)
    gameInstance.LevelClass = fightLevelClass
    gameInstance.fightMsg = { fight_level_id = self.LevelId }
    gameInstance.fightType = gameInstance.FIGHT_STATE.DailyCopy
    gameInstance.FightLevel = d_levels[self.LevelId].proposeLevel
    gameInstance.fightCanBack = true

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance.CachedSubLevel = 'City1BusinessCenter'
    gameInstance:CachePlayInCity()

    gameInstance.UIName = 'UI_Daily_Copy'
    gameInstance.UIArgs = self.npcType .. '|' .. self.SelectedIndex .. '|' .. self.LevelId


    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
    controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
    controller:LoadFightBeforeInCity()

end

function M:TabSelected(level_index)
   
end

return M

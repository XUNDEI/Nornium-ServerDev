local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local CharacterConfig = require "ClientDatas.d_character"
local CharacterSystem = require "Module.CharacterSystem.CharacterSystem"
local Client = require('Network.Client')
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Panel_Equip_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_SystemEntry,
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    self:InitData()
    self:InitUI()
    MessageManager:GetInstance():AddListener("OnResBuildHome", self)
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    InputUtils.RemoveMappingContext(playerController, InputAssets.IMC_BuildActor)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnResBuildHome", self)
    if self.CityCharActor then
        self.CityCharActor:K2_DestroyActor()
        self.CityCharActor = nil
    end
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    InputUtils.AddMappingContext(playerController, InputAssets.IMC_BuildActor)
end

function M:IA_ChangeSkin()
    print('---家装 换肤')
    local skinId = self.ColorList[self.ColorSelectedIndex]
    if skinId ~= self.BuildActor.SkinId then
        self.BuildActor:OnCloseDress()
    end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG('UI_Idol_Dress_Hotel')
    gameInstance:ShowTopUI(true)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Character, UE.ETriggerEvent.Completed, M.IA_ChangeSkin)

function M:OnResBuildHome()
    --local config = self.DressItemListData[self.SelectedListIndex]
    --刷新当前选中的皮肤
    -- self:RefreshTab()
    --刷新当前选中的皮肤
    local selectedRoleIdColorSkinID = self.ColorList[self.ColorSelectedIndex]
    self:RefreshColorInfo(selectedRoleIdColorSkinID)
    local colorSkinConfig = Database.Query("d_char_clothes", selectedRoleIdColorSkinID)

    local parentSkinConfig = self.DressItemListData[self.SelectedListIndex]
    --刷新当前item
    local widgets = self.UI_DressLoopList.Panel:GetAllChildren()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.ItemId == parentSkinConfig.id then
            self:RefreshDressItem(widget, colorSkinConfig)
            break
        end
        -- self:RefreshDressItem(widget, self.DressItemListData[i])
    end
end

function M:InitData()
    self.LastLevelIndex = 0
    self.LastScrollOffset = 0
    self.IsRefreshPending = false
    self.bHandleOffset = true
    self.ScrollCount = 0
    self.LastRoleId = 0
end

function M:InitUI()
    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)
    -- self.UI_Com_ChangeRole.ChangeRole.OnGHSClicked:Add(self, self.OnClicked_Btn_ChangeRole)
    self.Btn_Dress.OnGHSClicked:Add(self, self.OnClicked_Btn_Dress)
    self.GetSource.OnGHSClicked:Add(self, self.OnClicked_Btn_GetSource)

    -- self.UI_DressTab.CityDressTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_CityDress) 
    -- self.UI_DressTab.IdolDressTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_IdolDress)
    -- self.UI_DressTab.MeshDressTab.OnCheckStateChanged:Add(self, self.OnCheckStateChanged_MeshDressTab)

    self.UI_DressLoopList.OnItemInitialized:Add(self, function(wbp, ui, index) 
        self:OnItemInitialized(ui, index)
    end)
     
    self.UI_DressLoopList.OnItemSelected:Add(self, function(wbp, newIndex, lastIndex) 
        self:OnScrollViewSelected(newIndex)
    end)

    for i = 1, 5 do
        local colorItemUI = self['UI_DressColorItem' .. i]
        colorItemUI.Button.OnGHSClicked:Add(self, function()
            self:OnClicked_ColorItem(i)
        end)
    end
end

function M:OnClicked_ColorItem(index)
    print('--->colorItem:' .. index)
    local colorListCount = #self.ColorList
    if index <= colorListCount and self.ColorSelectedIndex ~= index then
        local colorSkinId = self.ColorList[index]
        
        --item old
        local oldColorItemUI = self['UI_DressColorItem' .. self.ColorSelectedIndex]
        if oldColorItemUI then
            oldColorItemUI.WidgetSwitcher:SetActiveWidgetIndex(2)
        end
        --item new
        local newColorItemUI = self['UI_DressColorItem' .. index]
        if newColorItemUI then
            newColorItemUI.WidgetSwitcher:SetActiveWidgetIndex(1)
        end

       

        self.ColorSelectedIndex = index
        print("----------->colorSkinId:" .. tostring(colorSkinId))
        self:RefreshColorInfo(colorSkinId)

        if self:IsNewSkin(colorSkinId) then
            self:MarkIsOldSkin(colorSkinId)
        end
        local colorSkinConfig = Database.Query("d_char_clothes", colorSkinId)
        if self.BuildActor then
            self.BuildActor:ChangeActorMesh(colorSkinConfig)
        end

        --刷新当前item
        local parentSkinConfig = self.DressItemListData[self.SelectedListIndex]
        local widgets = self.UI_DressLoopList.Panel:GetAllChildren()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.ItemId == parentSkinConfig.id then
                self:RefreshDressItem(widget, colorSkinConfig)
                break
            end
        end
    end
end

function M:GetDressList(roledId, dressType)
    local dressList = {}
    local d_char_clothes = require("ClientDatas.d_char_clothes")
    for k, v in pairs(d_char_clothes) do
        if v.charBelong == roledId and v.dressType == dressType and v.painting == 0 then
            table.insert(dressList, v)
        end
    end
    if #dressList > 1 then
        table.sort(dressList, function(a, b)
            return a.id < b.id
        end)
    end
    return dressList
end

function M:RefreshUI(buildActor)
    self.BuildActor = buildActor
    self.BuildActorID = buildActor.ID --家具id
    self.TrialClothID = Database.Query('d_bag_item_furniture', buildActor.ID).trialClothes
   
    if self.BuildActorID and self.BuildActorID > 0 then
        local itemConfig = UIUtils.GetItemConfigById(self.BuildActorID)
        if itemConfig and itemConfig.subParam and itemConfig.subParam[1] and itemConfig.subParam[1] > 0 then
            local charId = itemConfig.subParam[1]
            if charId and charId > 0 then
                self.SelectedRoleId = charId --角色id
                self.SelectedTabIndex = 3
                self:RefreshTab()
            end
        end
    end
end

function M:OnScrollViewSelected(index)
    self.SelectedListIndex = index + 1
    local config = self.DressItemListData[self.SelectedListIndex]
    if not config then return end
    self.CurDressCityCharId = config.id

    if self.BuildActor then
        self.BuildActor:ChangeActorMesh(config)
    end
    --刷新当前选中的皮肤
    self:RefreshDressInfo(config)

    --判断是否关闭'新'标记
    --print('----------->OnScrollViewSelected' .. tostring(config.id))
    if self:IsNewSkin(config.id) then
        self:MarkIsOldSkin(config.id)
        --刷新当前item

        local widgets = self.UI_DressLoopList.Panel:GetAllChildren()
        for i = 1, widgets:Length() do
            local widget = widgets:Get(i)
            if widget.ItemId == config.id then
                widget.NewIcon:SetVisibility(UE.ESlateVisibility.Hidden)
                break
            end
        end
    end
end

function M:RefreshTab(bIsSameTabIndex)
    if not bIsSameTabIndex then
        -- self:HideActorNiagara()
    end
    self.DressItemListData = self:GetDressList(self.SelectedRoleId, self.SelectedTabIndex + 1)
    self.MaxIndex = #self.DressItemListData - 1
    --print("===========配置个数:" .. tostring(#self.DressItemListData) .. ",MaxIndex:" .. tostring(self.MaxIndex)) 
    --获取self.SelectedRoleId的皮肤
    local idolId, charId, cityCharId, defaultIdolId, defaultCharId, defaultCityCharId = UIUtils.GetIdolAndCharMeshByCharacterId(self.SelectedRoleId)
    if idolId <= 0 then idolId = defaultIdolId end
    if charId <= 0 then charId = defaultCharId end
    if cityCharId <= 0 then cityCharId = defaultCityCharId end
    self.CurDressCharId = charId
    self.CurDressIdolId = idolId
    self.CurDressCityCharId = cityCharId

    self.SavedDressIdolId = idolId
    self.SavedDressCharId = charId
    self.SavedDressCityCharId = cityCharId


    self.SelectedListIndex = 1

    local dressId = self.BuildActor.SkinId
    local unlockCount = 0
    for i = 1, #self.DressItemListData do
        if self.DressItemListData[i].id == dressId then
            self.SelectedListIndex = i
        end
        local isUnlock = self:IsUnlockSkinId(self.SelectedRoleId, self.SelectedTabIndex, self.DressItemListData[i].id)
        if isUnlock then
            unlockCount = unlockCount + 1
        end
    end
    self.UI_DressLoopList:BP_SetListItems(#self.DressItemListData)
    self.UI_DressLoopList:SetScrollToIndex(self.SelectedListIndex - 1)
    --个数统计(todo)
    self.Text_Count:SetText(unlockCount .. "/" .. #self.DressItemListData)
    --刷新当前选中的皮肤
    self:RefreshDressInfo(self.DressItemListData[self.SelectedListIndex])
end

function M:CreateCityCharActor()
    self.LastRoleId = self.SelectedRoleId
    --创建一个角色
    local modelPath = Database.Query("d_character", self.SelectedRoleId).cityModelPath
    local strArr = string.split(modelPath, '/')
    local path = string.format("'/Game/_Game/Blueprints/Players/%s.%s_C'", modelPath, strArr[2]) 
    local playerClass = LoadClass(path)

    if self.BackUI and self.BackUI.GetSelectedActor then
        local fightActor = self.BackUI:GetSelectedActor()
        if fightActor then
            self.CityCharActor = self:GetWorld():SpawnActor(playerClass,
                fightActor:GetTransform(), UE.ESpawnActorCollisionHandlingMethod.AlwaysSpawn, self, self)
        end
    end
end

function M:HideActorNiagara()
    if self.BackUI and self.BackUI.GetSelectedActor then
        local fightActor = self.BackUI:GetSelectedActor()
        if fightActor then
            local niagaraComponents = fightActor:K2_GetComponentsByClass(UE.UNiagaraComponent)
            for _, niagaraComponent in pairs(niagaraComponents) do
                niagaraComponent:SetVisibility(false)
            end
        end
    end
end

function M:RefreshDressInfo(config)
    print("===RefreshDressInfo:" .. tostring(config.id))
    local dressId = self.BuildActor.SkinId

    --炫彩
    self.ColorList = self:GetColorList(config.id)
    print('---炫彩列表：' .. tostring(table.dump(self.ColorList, nil, 10)))
    self.ColorSelectedIndex = 1
    for i, colorId in pairs(self.ColorList) do
        if dressId == colorId then
            self.ColorSelectedIndex = i
        end
    end

    local colorCount = #self.ColorList
    self.Panel_Color:SetVisibility(colorCount > 0 and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    for i = 1, 5 do
        local colorItemUI = self['UI_DressColorItem' .. i]
        if i <= colorCount then
            local colorSkinId = self.ColorList[i]
            --判定是否解锁
            local bIsColorUnlock = self:IsUnlockSkinId(self.SelectedRoleId, self.SelectedTabIndex, colorSkinId)
            colorItemUI.Img_Lock:SetVisibility(bIsColorUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)

            if bIsColorUnlock then
                colorItemUI.Img_Lock:SetVisibility(UE.ESlateVisibility.Hidden)
            else
                colorItemUI.WidgetSwitcher:SetActiveWidgetIndex(2)
                colorItemUI.Img_Lock:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            end

            --默认已装扮
            if self.ColorSelectedIndex == i then
                colorItemUI.WidgetSwitcher:SetActiveWidgetIndex(1)
            else
                colorItemUI.WidgetSwitcher:SetActiveWidgetIndex(2)
            end
        else
            colorItemUI.WidgetSwitcher:SetActiveWidgetIndex(0)
            colorItemUI.Img_Lock:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end


    local selectedRoleIdColorSkinID = self.ColorList[self.ColorSelectedIndex]
    self:RefreshColorInfo(selectedRoleIdColorSkinID)
    local colorSkinConfig = Database.Query("d_char_clothes", selectedRoleIdColorSkinID)
    --刷新当前item
    local parentSkinConfig = self.DressItemListData[self.SelectedListIndex]
    local widgets = self.UI_DressLoopList.Panel:GetAllChildren()
    for i = 1, widgets:Length() do
        local widget = widgets:Get(i)
        if widget.ItemId == parentSkinConfig.id then
            self:RefreshDressItem(widget, colorSkinConfig)
            break
        end
    end
end

--获取炫彩皮肤列表
function M:GetColorList(skinId)
    local result = { skinId }
    local d_char_clothes = require('ClientDatas.d_char_clothes')
    for _, v in pairs(d_char_clothes) do
        if v.painting > 0 and v.painting == skinId then
            table.insert(result, v.id)
        end
    end
    return result
end

function M:RefreshColorInfo(skinId)
    local dressId = self.BuildActor.SkinId

    self.GetSource:SetVisibility(UE.ESlateVisibility.Hidden)
    --判断角色皮肤解锁
    local isUnlock = self:IsUnlockSkinId(self.SelectedRoleId, self.SelectedTabIndex, skinId)
    if isUnlock then
        self.Btn_Dress:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        -- self.GetSource:SetVisibility(UE.ESlateVisibility.Hidden)
        self.cannotClick:SetVisibility(UE.ESlateVisibility.Hidden)

        local isDressed = skinId == dressId
        self.Btn_Dress:SetIsEnabled(not isDressed)
        self.Btn_Dress_Normal:SetVisibility(isDressed and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInvisible)
        self.Btn_Dress_Dressed:SetVisibility(isDressed and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    else
        self.Btn_Dress:SetVisibility(UE.ESlateVisibility.Hidden)
        --检测皮肤获取的道具的来源
        local itemConfig = self:GetSkinFromItemInfo(skinId)
        --有来源
        if itemConfig then --显示来源按钮
            -- self.GetSource:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            self.cannotClick:SetVisibility(UE.ESlateVisibility.Hidden)
        else --显示仅供预览
            -- self.GetSource:SetVisibility(UE.ESlateVisibility.Hidden)
            self.cannotClick:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        end
    end
    --self.Btn_Dress_Normal:SetIsEnabled(isUnlock)
end

function M:OnBack()
    --self.WidgetSwitcher:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    -- self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Collapsed)
    -- self.UI_Team_List:SetVisibility(UE.ESlateVisibility.Collapsed)
    --self:ChangeActorAndCamera(self.SelectedTabIndex)
end

--切换角色
function M:SelectedRole(Index)
    self.BackUI:SelectedRole(Index, 5)

    self.SelectedCharacterIndex = Index
    self.SelectedCharacterData = self.CharacterConfigList[self.SelectedCharacterIndex]
    self.SelectedRoleId = self.SelectedCharacterData.character_id

    -- self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.Collapsed)
    -- self.UI_Team_List:SetVisibility(UE.ESlateVisibility.Collapsed)

    self:RefreshTab()
end

function M:ReqChangeDressInfo()
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end

    if self.BuildActor then
        self.BuildActor.SkinId = self.ColorList[self.ColorSelectedIndex]
    end
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc.SaveBuildActorInfo then
        pc:SaveBuildActorInfo() 
    end

end

--主城页签时,当前的装扮id 获取对应的 战斗服装中的 模型路径
function M:GetCharModeFByCityCharId(cityCharId)
    local charDressList = self:GetDressList(self.SelectedRoleId, 1)
    local index = 1
    local cityCharDressList = self:GetDressList(self.SelectedRoleId, 3)
    for idx, config in ipairs(cityCharDressList) do 
        if config.id == cityCharId then
            index = idx
            break
        end
    end
    local charDressConfig = charDressList[index]
    return charDressConfig.modelF, charDressConfig.id
end

----------------------------------------------------------------------
---点击事件
function M:OnClicked_Btn_Exit()
    self:IA_ChangeSkin()
    -- if self.BackUI then
    --     --重新切换到默认皮肤
    --     if self.CurDressIdolId ~= self.SavedDressIdolId then
    --         local idolConfig = Database.Query("d_char_clothes", self.SavedDressIdolId)
    --         if idolConfig then
    --             self.BackUI:ChangeActorMesh(idolConfig.modelF, nil)
    --             self.BackUI:ChangeIdol(self.SavedDressIdolId)
    --         end
    --     end
    --     local charConfig = Database.Query("d_char_clothes", self.SavedDressCharId)
    --     if charConfig then
    --         self.BackUI:ChangeActorMesh(nil, charConfig.modelF)
    --     end
    -- end
    -- UIManager:GetInstance():RemoveUI(self)

    -- if self.BackUI and self.BackUI.ShowActorWeapon then
    --     self.BackUI:ShowActorWeapon(true)
    -- end

    -- if self.BackUI then
    --     if self.BackUI.BackFromLevelUp then
    --         self.BackUI:BackFromLevelUp()
    --     end

    --     self.BackUI:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    -- end
end

-- InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Exit)

function M:OnClicked_Btn_ChangeRole()
    -- self.ChangeRoleList:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    -- self.UI_Team_List:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    -- self.UI_Team_List:SetBackUI(self, 0, "CharacterSystem", self.SelectedCharacterIndex)
end

--主城服装
function M:OnCheckStateChanged_CityDress()
    self:OnTabCheckStateChanged(2)
end

--战斗服装
function M:OnCheckStateChanged_IdolDress()
    self:OnTabCheckStateChanged(0)
end

--机甲涂装
function M:OnCheckStateChanged_MeshDressTab()
    self:OnTabCheckStateChanged(1)
end

function M:OnClicked_Btn_Dress()
    local colorSkinId = self.ColorList[self.ColorSelectedIndex]
    if self.SelectedTabIndex == 0 then
        self.CurDressCharId = colorSkinId
        self.SavedDressCharId = colorSkinId
    elseif self.SelectedTabIndex == 1 then
        self.CurDressIdolId = colorSkinId
        self.SavedDressIdolId = colorSkinId
    else
        self.CurDressCityCharId = colorSkinId
        self.SavedDressCityCharId = colorSkinId
    end
    self:ReqChangeDressInfo()
end

function M:OnClicked_Btn_GetSource()
    local skinId = self.ColorList[self.ColorSelectedIndex]
    local itemConfig = self:GetSkinFromItemInfo(skinId)
    UIUtils.ShowItemInfo(itemConfig.id)
end 

function M:OnTabCheckStateChanged(index)
    local lastIndex = self.SelectedTabIndex == 1 and 0 or 3
    local curIndex = index == 1 and 0 or 3

    if self.SelectedTabIndex ~= index then
        local bIsSameTabIndex = (self.SelectedTabIndex == 0 or self.SelectedTabIndex == 2) and (index == 0 or index == 2)
        self.SelectedTabIndex = index
        self:RefreshTab(bIsSameTabIndex)
        if not bIsSameTabIndex and self.BackUI and self.BackUI.ChangeRoleAnimation and lastIndex ~= curIndex then
            self.BackUI:ChangeRoleAnimation(self.SelectedTabIndex == 1 and 0 or 3)
        end
        -- if self.BackUI and self.BackUI.ChangeActorAndCamera then
            -- local cameraIndex = self.SelectedTabIndex == 1 and 0 or 5
            -- self.BackUI:ChangeActorAndCamera(cameraIndex, self.SelectedTabIndex == 1 and 9 or 8)
        -- end
    end
end

-- function M:BP_OnEntryInitialized(itemData, ui)
--     ui.Index = itemData.Index - 1
--     local item = self.DressItemListData[itemData.Index]
--     if item then
--         ui:SetRenderOpacity(1)
--         ui.Text_Name:SetText(Database.L10n(item.dressName))
--     else
--         ui:SetRenderOpacity(0)
--     end
-- end

function M:OnItemInitialized(ui, index)
    local config = self.DressItemListData[index + 1]
    if config then
        ui.Index = index
        ui.ItemId = config.id

        self:RefreshDressItem(ui, config)
    else
        ui:SetRenderOpacity(0)
    end
end

function M:RefreshDressItem(ui, config)
    --ui:SetRenderOpacity(1)
    ui.Text_Name:SetText(Database.L10n(config.dressName))
    if config.picturePath and config.picturePath ~= '' then
        local itemPic = LoadObject(config.picturePath)
        if itemPic then
            ui.uniform_res:SetBrushFromAtlasInterface(itemPic)
        end
    end
    --解锁
    local isUnlock = self:IsUnlockSkinId(self.SelectedRoleId, self.SelectedTabIndex, config.id)
    ui.lockList:SetVisibility(not isUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    ui.unlockList:SetVisibility(isUnlock and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

    --锁标记
    -- ui.lockicon:SetVisibility(isUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
    ui.lockicon:SetVisibility(UE.ESlateVisibility.Hidden)
    if isUnlock then
        --是否穿戴
        local dressId = self.BuildActor.SkinId
        local isDressed = dressId == config.id
        ui.Dressed:SetVisibility(isDressed and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.default:SetVisibility(not isDressed and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
       
        --试用标记
        ui.TrailIcon:SetVisibility(self.TrialClothID == config.id and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        if self.TrialClothID ~= config.id then
            --是否是新标记
            local isNewSkin = self:IsNewSkin(config.id)
            ui.NewIcon:SetVisibility(isNewSkin and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        end
       
    else
        if self.TrialClothID ~= config.id then
            ui.NewIcon:SetVisibility(UE.ESlateVisibility.Hidden)
            --锁标记
            ui.lockicon:SetVisibility(isUnlock and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.SelfHitTestInVisible)
        end
        --试用标记
        ui.TrailIcon:SetVisibility(self.TrialClothID == config.id and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end


----------------------------------------------------------------------
---辅助函数
function M:IsUnlockSkinId(roleId, type, skinId)
    --如果是默认皮肤
    -- local config = require('ClientDatas.d_char_clothes')[skinId]
    -- if config then
    --     if config.dressInitial == 1 then
    --         return true
    --     end
    -- end
    --判断角色皮肤解锁
    local _, isUnlock = UIUtils.CharSkinIsUnlock(roleId, type, skinId - 1000000)
    return isUnlock
end

function M:IsNewSkin(skinId)
    --是原始皮肤
    -- local config = require('ClientDatas.d_char_clothes')[skinId]
    -- if config then
    --     if config.dressInitial == 1 then
    --         return false
    --     end
    -- end
    --未获得
    local isUnlock = self:IsUnlockSkinId(self.SelectedRoleId, self.SelectedTabIndex, skinId)
    if not isUnlock then
        return false
    end
    --本地是否保存过
    local isNew = true
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local saveGameChar = gameInstance:LoadSaveGameChar()
    if saveGameChar and saveGameChar.OldSkinList then
        for i = 1, saveGameChar.OldSkinList:Length() do
            if skinId == saveGameChar.OldSkinList:Get(i) then
                isNew = false
                break
            end
        end
    end
    return isNew
end

function M:MarkIsOldSkin(skinId)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local saveGameChar = gameInstance:LoadSaveGameChar()
    if saveGameChar and saveGameChar.OldSkinList then
        saveGameChar.OldSkinList:AddUnique(skinId)
        gameInstance:SaveSaveGameChar()
    end
end

function M:GetSkinFromItemInfo(dressId)
    --print('---GetSkinFromItemInfo:' .. tostring(dressId))
    local itemConfig = require('ClientDatas.d_bag_item')
    for _, config in pairs(itemConfig) do 
        if config.itemType == UIUtils.ItemMainType.Skin then
            if config.subParam and #config.subParam > 0 then
                for _, id in pairs(config.subParam) do
                    --print('---id:' .. tostring(id))
                    if id == dressId then
                        return config
                    end
                end
            end
        end
    end
    return nil
end

function M:GetSelectedSkinId()
    return self.DressItemListData[self.SelectedListIndex].id
end

return M
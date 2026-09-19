local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local BackpackSystem = require "Module.Backpack.BackpackSystem"
local QuestSystem = require "Module.Quest.QuestSystem"
local Client = require "Network.Client"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

local UI_CityMenu_C = require "_Game.Blueprints.UI.UI_CityMenu.UI_CItyMenu_C"
local bp_playercontroller_fight_c = require("_Game.Blueprints.Character.BP_PlayerController_Fight.BP_PlayerController_Fight_C")

---@type UI_City_C
local M = UnLua.Class()

M.HideCursor = true
M.EnableMove = true
M.ShowInteractOptions = true
M.InputMappingContexts = {
    InputAssets.IMC_UI_SystemEntry,
}

-- TODO 很邪门的写法 好孩子千万别学，记得改
InputUtils.RegisterUIAction(M, InputAssets.IA_Character, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Character)
InputUtils.RegisterUIAction(M, InputAssets.IA_Item, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Backpack)
InputUtils.RegisterUIAction(M, InputAssets.IA_Mission, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Task)
InputUtils.RegisterUIAction(M, InputAssets.IA_Team, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Team)
InputUtils.RegisterUIAction(M, InputAssets.IA_Event, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Active)
InputUtils.RegisterUIAction(M, InputAssets.IA_Story, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Plot)
InputUtils.RegisterUIAction(M, InputAssets.IA_Gacha, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Card)
InputUtils.RegisterUIAction(M, InputAssets.IA_Store, UE.ETriggerEvent.Completed, UI_CityMenu_C.OnClicked_Shop)


function M:IA_Switch()
    local controller = UE.UGameplayStatics.GetPlayerController(self, 0)

    if controller.BPIIsCity and not controller:BPIIsCity() then
        self:Back()
    end
end
InputUtils.RegisterUIAction(M, InputAssets.IA_Switch, UE.ETriggerEvent.Completed, M.IA_Switch)

function M:Construct()
    self:InitData()
    self:InitUI()
    self.Overridden.Construct(self)
    MessageManager:GetInstance():AddListener('OnChangePlayerController', self)
    MessageManager:GetInstance():AddListener('OnMsg_BuildCoin', self)
    MessageManager:GetInstance():AddListener('OnMsg_Refresh_Plot_Mission', self)
    
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener('OnChangePlayerController', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_BuildCoin', self)
    MessageManager:GetInstance():RemoveListener('OnMsg_Refresh_Plot_Mission', self)
end

function M:InitData()
    self.LastCheckTime = 0
    self.LastTrackQuestId = 0
    -- self.TrackPosMap = QuestSystem:GetInstance():InitTrackPosMap()
end

function M:InitUI()
    self.UI_MenuButton.OnClicked:Add(self, self.OnClicked_MenuButton)
    self.BuildButton.OnGHSClicked:Add(self, self.OnClicked_BuildButton)

    local isApp = not UE.UGHSFunctionLibrary.WithEditor() and UIUtils.IsAndroidOrIOS()
    self.TouchJoystickLeft:SetVisibility(isApp and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)

    self:OnChangePlayerController()

     --判定是否有教学任务100030108
     local QuestSystem = require("Module.Quest.QuestSystem")
     local QuestInfo = QuestSystem:GetInstance():GetQuestInfo(100030108)
     if (QuestInfo and (not QuestInfo.completed or not QuestInfo.finished)) then
         self:ShowUIKey_BuildPlace(false)
     else
        self:ShowUIKey_BuildPlace(true)
     end
end

-- function M:OnUIVisibilityChanged(inVisibility)
--     self.Overridden.OnUIVisibilityChanged(self, inVisibility)
--     local controller = UE.UGameplayStatics.GetPlayerController(self, 0)
--     if inVisibility == UE.ESlateVisibility.Hidden or inVisibility == UE.ESlateVisibility.CollapsepU_cd then
--         controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = true
--     else
--         controller.BP_PlayerController_City_UniverseBridge.BlockInputAction = false
--         self.ShowInteractOptions = true
--         self.HideCursor = true
--     end
-- end

function M:OnChangePlayerController()
    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.UI_Jump:SetVisibility(UE.ESlateVisibility.Collapsed)
    self.UI_Key_R:SetVisibility(UE.ESlateVisibility.Collapsed)

    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    self.Panel_SkillInCity:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

    local isApp = not UE.UGHSFunctionLibrary.WithEditor() and UIUtils.IsAndroidOrIOS()
    if gameInstance and gameInstance.GetPlayerCharacterIdInCity then
        gameInstance:LoadSaveGameChar()
        local charId = gameInstance:GetPlayerCharacterIdInCity()
        if charId and charId > 0 then 
            if isApp then
                if charId == 10701 then
                    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Collapsed)
                elseif charId == 10601 then
                    -- self.UI_Jump:SetVisibility(UE.ESlateVisibility.Collapsed)
                    self.UI_Key_R:SetVisibility(UE.ESlateVisibility.Collapsed)
                    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Visible)
                -- elseif charId == 11202 then
                --     self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Hidden)
                elseif charId == 24001 then
                    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Collapsed)
                    -- self.UI_Jump:SetVisibility(UE.ESlateVisibility.Collapsed)
                    self.UI_Key_R:SetVisibility(UE.ESlateVisibility.Collapsed)
                end
            else
                if charId == 10401 then
                    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Visible)
                elseif charId == 10601 then
                    -- self.UI_Jump:SetVisibility(UE.ESlateVisibility.Collapsed)
                    self.UI_Key_R:SetVisibility(UE.ESlateVisibility.Collapsed)
                    self.UI_City_Sprint:SetVisibility(UE.ESlateVisibility.Visible)
                end
            end
            
        end
    end
end

function M:RefreshQuestPanel()

end

function M:OnClicked_MenuMission()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:OpenLink(9008, "")
    return UE.UWidgetBlueprintLibrary.Handled()
end

function M:OnClicked_MenuButton()
    if self:IsVisible() and self.UI_MenuButton:IsVisible() and not self:IsPlayingAnimation() then
        if not self.bIsPossedBuild then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            gameInstance:ShowTopUI(false)
            gameInstance:AddUMG('UI_CityMenu')
        end
    end
end

-- TODO 因为这玩意是立即执行，没有闭包，必须在定义后绑定
InputUtils.RegisterUIAction(M, InputAssets.IA_Menu, UE.ETriggerEvent.Completed, M.OnClicked_MenuButton)

function M:OnClicked_BuildButton()
    local pc = UE.UGameplayStatics.GetPlayerController(self, 0)
    if pc and pc.IsInBuildLevel and not pc.BuildActorIsControlled then
        local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
        if gameInstance:OpenLink(9023, "") then
            gameInstance:HideAllUI('UI_Build')
            gameInstance:ShowTopUI(true)
        end 
    end
end
InputUtils.RegisterUIAction(M, InputAssets.IA_BuildPlace, UE.ETriggerEvent.Completed, M.OnClicked_BuildButton)

function M:OnBackButtonEnd()
    UIManager:GetInstance():ClearInteractOption()
end

---@param Text string
function M:AddOptionItem(Text)
    local index = UIManager:GetInstance().layers.Options:GetChildrenCount()
    local ui = UIManager:GetInstance():AddInteractOption(self, Text, function()
        local widget = UIManager:GetInstance().layers.Options:GetChildAt(index)
        self.OnOptionItemClicked:Broadcast(widget, index)
    end)

    return ui
end

-------------------------------------------------------
-------------------------------------------------------
---扩展交互按钮逻辑
function M:AddInteractOption(opId, callback)
    if not self.OptionItemMap then
        self.OptionItemMap = {}
    end
    if #self.OptionItemMap == 0 then
        self.OnOptionItemClicked:Add(self, self.OnInteractOptionClicked)
    end 
    local ui = self:AddOptionItem(Database.L10n(opId))
    if ui then
        table.insert(self.OptionItemMap, { option = ui, callback = callback })
    end
    return ui
end

function M:RemoveInteractOption(opItem)
    for index, optionInfo in pairs(self.OptionItemMap) do
        if optionInfo.option == opItem then
            table.remove(self.OptionItemMap, index)
            break
        end 
    end
    if #self.OptionItemMap == 0 then
        self.OnOptionItemClicked:Remove(self, self.OnInteractOptionClicked)
    end
    if opItem then
        self:RemoveOptionItem(opItem)
    end
end

function M:RemoveOptionItem(widget)
    UIManager:GetInstance():RemoveInteractOption(widget)
end

function M:ClearOptionListItems()
    UIManager:GetInstance():ClearInteractOption()
end

function M:OnInteractOptionClicked(option, index)
    -- print('---------OnOptionItemClicked:' .. table.dump(self.OptionItemMap, false, nil))
    for _, optionInfo in pairs(self.OptionItemMap) do
        if optionInfo.option == option then
            if optionInfo.callback then
                local obj = optionInfo.callback[1]
                local func = optionInfo.callback[2]
                func(obj, option, index)
                --callback[1]:callback[2](option, index)
            end
        end
    end
end

-------------------------------------------------------
---进入家具地图，ui显示逻辑
function M:EnterBuildRegion()
    self:RefreshBuildCoinInfo()
    self.Overridden.EnterBuildRegion(self)
end

function M:ExitBuildRegion()
    self.Overridden.ExitBuildRegion(self)
end

-------------------------------------------------------
---家具币信息
function M:RefreshBuildCoinInfo()
    local BuildSystem = require('Module.BuildSystem.BuildSystem')
    local curCount = BuildSystem:GetInstance():GetBuildCoinCount()
    local d_com_params = require('ClientDatas.d_com_params')
    local allCount = tonumber(d_com_params[25].value2)
    --获取
    self.UI_City_Build_DailyReward.RewardProgressBar:SetPercent(curCount / allCount)
    self.UI_City_Build_DailyReward.RewardLeft:SetText(math.max(0, allCount - curCount))
end

function M:OnMsg_BuildCoin(getCount)
    self:RefreshBuildCoinInfo()
    self.UI_City_Build_DailyReward.RewardGet:SetText(getCount)
    self.UI_City_Build_DailyReward:PlayAnimationForward(self.UI_City_Build_DailyReward.Animation)
end

--显影家具摆放按钮上的提示键p
function M:ShowUIKey_BuildPlace(Visible)
    self.UI_Key_BuildPlace:SetVisibility(Visible and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Collapsed)
end

function M:OnMsg_Refresh_Plot_Mission(mission_id)
    if mission_id == 100030108 then
        local QuestSystem = require("Module.Quest.QuestSystem")
        local QuestInfo = QuestSystem:GetInstance():GetQuestInfo(100030108)
        if (QuestInfo and (not QuestInfo.completed or not QuestInfo.finished)) then
            self:ShowUIKey_BuildPlace(false)
        else
            self:ShowUIKey_BuildPlace(true)
        end
    end
end

return M
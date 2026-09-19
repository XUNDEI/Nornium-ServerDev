local UIUtils = require "_Game.Utils.UIUtils"
local Database = require("_Game.Utils.Database")
local Client = require "Network.Client"
local MessageManager = require "Framework.Updater.MessageManager"
local NetworkMessageManager = require('Framework.Updater.NetworkMessageManager')
local QuestSystem = require "Module.Quest.QuestSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_RewardBook_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

local ItemBgPath = '/Game/_Game/TP_New/Task/TaskBookBG/%s.%s'

function M:Construct()
    self:InitUI()
    self:InitData()
    MessageManager:GetInstance():AddListener("OnNetCmd_Res_Mission_RewardBook_Reward", self)
    MessageManager:GetInstance():AddListener("OnMsg_MissionRecord", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("OnNetCmd_Res_Mission_RewardBook_Reward", self)
    MessageManager:GetInstance():RemoveListener("OnMsg_MissionRecord", self)
end

function M:InitUI()
    self.Btn_Exit.OnGHSClicked:Add(self, self.OnClicked_Btn_Exit)
    self.Btn_Left.OnGHSClicked:Add(self, self.OnClicked_Btn_Left)
    self.Btn_Right.OnGHSClicked:Add(self, self.OnClicked_Btn_Right)
    self.Btn_Chapter.OnGHSClicked:Add(self, self.OnClicked_Btn_Chapter)
end

function M:InitData()
    self:InitChapterData(true)
    self:RefreshTab()
end

function M:InitChapterData(bResetTabIndex)
    local firstTabIndex, maxTab = QuestSystem:GetInstance():CheckAllBookMission()
    if bResetTabIndex then
        self.SelectedTabIndex = firstTabIndex
    end
    self.TabMax = maxTab
end

function M:OnNetCmd_Res_Mission_RewardBook_Reward(questId)
    local rewardList = {}
    local config = Database.Query('d_task_book', questId)
    for i = 1, #config.reward, 3 do 
        local itemId = config.reward[i]
        local count = config.reward[i + 2]
        table.insert(rewardList, {
            itemId = itemId,
            count = count,
        })
    end
  
 
    --刷新指定ui
    local targetUI = nil
    for i = 1, 5 do 
        local ui = self['UI_RewardBookItem' .. i]
        if ui and ui.QuestId == questId then
            targetUI = ui
            break
        end
    end
    --章节奖励
    if not targetUI then
        UIUtils.ShowGetRewardCommonUI(self, rewardList)
        local questList, chapterQuestInfo = self:GetRewardBookDataList(self.SelectedTabIndex)
        self:RefreshChapterUI(chapterQuestInfo)
        return
    end

    --隐藏领取按钮
    targetUI.Btn_Receive:SetVisibility(UE.ESlateVisibility.Hidden)
    targetUI:vfx_AtoB()
    -- targetUI.image2:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
    -- targetUI.Panel_Forward:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)

    -- local missionData = nil 
    -- for idx, v in ipairs(self.QuestDataList) do
    --     if questId == v.mission_id then
    --         missionData = v 
    --         break
    --     end
    -- end
    -- if targetUI and missionData then
    --     missionData.finished = true
    --     missionData.completed = true
        -- targetUI:SetRewardFlag(true)
        -- self:RefreshItemEx(targetUI, missionData)
        -- -- targetUI:SetRewardFlag(true)

        -- local questList, chapterQuestInfo = self:GetRewardBookDataList(self.SelectedTabIndex)
        -- self.QuestDataList = questList
        -- self.ChapterQuestInfo = chapterQuestInfo
        -- self:RefreshChapterUI(chapterQuestInfo)
        -- -- targetUI.image2:SetVisibility(UE.ESlateVisibility.Hidden)
        -- -- targetUI.Image:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        -- -- if not targetUI:IsAnimationPlaying(targetUI.Anim_Flip) then
        -- --     targetUI:PlayFlipEffect()
        -- -- end
        -- UIUtils.ShowGetRewardCommonUI(self, rewardList)
    -- end
    -- do return end
    
    -- targetUI:BindToAnimationFinished(targetUI.full, function()
        local questList, chapterQuestInfo = self:GetRewardBookDataList(self.SelectedTabIndex)
        self.QuestDataList = questList
        self.ChapterQuestInfo = chapterQuestInfo
    
        local missionData = nil 
        for idx, v in ipairs(self.QuestDataList) do
            if questId == v.mission_id then
                missionData = v 
                break
            end
        end
        if targetUI and missionData then
            missionData.finished = true
            missionData.completed = true
            targetUI:SetRewardFlag(true)
            self:RefreshItemEx(targetUI, missionData)
            targetUI:SetRewardFlag(true)
            self:RefreshChapterUI(chapterQuestInfo)
            -- targetUI.image2:SetVisibility(UE.ESlateVisibility.Hidden)
            -- targetUI.Image:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
            -- if not targetUI:IsAnimationPlaying(targetUI.Anim_Flip) then
            --     targetUI:PlayFlipEffect()
            -- end
            UIUtils.ShowGetRewardCommonUI(self, rewardList)
        end
    -- end)

    -- targetUI:PlayAnimationForward(targetUI.full, 1.0, false)

end

function M:OnMsg_MissionRecord()
    self:RefreshTab()
end

function M:GetRewardBookDataList(index)
    local result = {}
    local chapterQuestInfo = nil
    local taskList = QuestSystem:GetInstance().QuestBookInfo
    for k, v in pairs(taskList) do 
        local config = Database.Query('d_task_book', v.mission_id)
        if config.page == index then
            if config.taskContent == UIUtils.EOpenNeedType.RewardBook then
                chapterQuestInfo = v
            else
                table.insert(result, v)
            end
        end
    end
   
    if #result > 1 then
        table.sort(result, function(a, b)
            return a.mission_id < b.mission_id
        end)
    end
    return result, chapterQuestInfo
end

function M:RefreshTab()
    local questList, chapterQuestInfo = self:GetRewardBookDataList(self.SelectedTabIndex)
    self.QuestDataList = questList
    self.ChapterQuestInfo = chapterQuestInfo

    for idx, v in ipairs(self.QuestDataList) do
        local ui = self['UI_RewardBookItem' .. idx]
        ui.Index = idx
        ui.QuestId = v.mission_id
        self:RefreshItem(ui, v)

        -- ui:StopAllAnimations()
        -- ui:PlayAnimationForward(ui.InitAnimation, 1, false)
    end

    self:RefreshChapterUI(chapterQuestInfo)

end

function M:RefreshChapterUI(chapterQuestInfo)
    --章节数据
    local questConfig = Database.Query('d_task_book', chapterQuestInfo.mission_id)

    local hasGot = chapterQuestInfo.completed
    local hasFinished = chapterQuestInfo.finished

    self.Img_RedPoint:SetVisibility((not hasGot and hasFinished) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Panel_Getted:SetVisibility(hasGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    self.Text_Chapter:SetText(chapterQuestInfo.DoneCount)
    local itemId = questConfig.reward[1]
    local rewardCount = questConfig.reward[3]
    --章节奖励
    local iconPath = string.format('/Game/_Game/TP_New/Common/Frames/Icon_%s_png.Icon_%s_png', itemId, itemId)
    local iconRes = LoadObject(iconPath)
    if iconRes then
        self.icon_res:SetBrushFromAtlasInterface(iconRes)
    end

    self.Text_Res:SetText('x' .. rewardCount)

    --左右切换按钮
    self.Btn_Left:SetVisibility(self.SelectedTabIndex == 1 and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)
    self.Btn_Right:SetVisibility(self.SelectedTabIndex == self.TabMax and UE.ESlateVisibility.Hidden or UE.ESlateVisibility.Visible)

    self.Btn_Chapter:SetVisibility(hasGot and UE.ESlateVisibility.HitTestInvisible or UE.ESlateVisibility.Visible)
end

function M:GetDetailStr(config, questData)
    local detailStr = string.format(Database.L10n(config.taskDetails), table.unpack(config.taskNumber))
    local allNum = questData.AllCount
    if config.taskContent == UIUtils.EOpenNeedType.CharLevel or --30000, --XX角色等级升至X级
        config.taskContent == UIUtils.EOpenNeedType.CharSkillLv then --30001, --XX技能升至X级
        detailStr = string.format(Database.L10n(config.taskDetails), allNum)
    end
  
    return detailStr, allNum
end

function M:RefreshItem(ui, questData)
    local config = Database.Query('d_task_book', questData.mission_id)
    if ui and config then
        local hasGot = questData.completed
        local hasFinished = questData.finished
        print('==mission_id:' .. tostring(questData.mission_id) .. ',hasgot:' .. tostring(hasGot) .. ',hasFinished:' .. tostring(hasFinished))
     
        local linkId = tonumber(config.useLink)
        ui.Btn_Goto.OnGHSClicked:Clear()
        ui.Btn_Goto.OnGHSClicked:Add(self, function()
            -- UE.UGameplayStatics.GetGameInstance(self):ShowTopUI(false)
            -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            -- gameInstance:OpenLink(linkId, '')
            UIUtils.ShowNotify(self, Database.L10n(50500))
        end)
        

        local iconPath = string.format(ItemBgPath, config.taskBookBG, config.taskBookBG)
        -- print("-----iconPath:" .. tostring(iconPath))
        local bgObj = LoadObject(iconPath)
        if bgObj then
            -- ui.Img_ItemBg:SetBrushFromTexture(bgObj)
            ui.Img_ItemBg_1:SetBrushFromTexture(bgObj)
        end
        local bgObj2 = LoadObject(iconPath)
        if bgObj2 then
            ui:SetBGTexture(bgObj2)
        end
    
        ui.Btn_Receive.OnGHSClicked:Clear()
        ui.Btn_Receive.OnGHSClicked:Add(self, function()
            self:GetReward(questData.mission_id)
        end)

        --奖励是否领取
        --ui:SetRewardFlag(hasGot)
        --ui.Panel_Forward:SetVisibility(UE.ESlateVisibility.Hidden)
        if hasGot then
            ui:vfx_B()
        else
            ui:vfx_A()
        end

        --任务描述
        local detailStr, allNum = self:GetDetailStr(config, questData)
        ui.Text_Detail:SetText(detailStr)
        ui.Text_Progress:SetText(questData.DoneCount .. '/' .. questData.AllCount)
        ui.LevelExp:SetPercent(questData.DoneCount / questData.AllCount)

        --点击事件
        ui.OnClickedEvent:Clear()
        ui.OnClickedEvent:Add(self, self.OnClicked_RewardBookItem)
       
        --奖励道具
        ui.HBox_Reward:ClearChildren()
        -- print("---config.reward:" .. tostring(table.dump(config.reward, false, 10)))
        local class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C")
        for i = 1, #config.reward, 3 do
            local itemId = config.reward[i]
            local itemCount = config.reward[i + 2]
            local itemConfig = UIUtils.GetItemConfigById(itemId)

            local itemUI = UE.UWidgetBlueprintLibrary.Create(self, class)
            itemUI.TextName:SetText(Database.L10n(itemConfig.itemName))
            itemUI.TextNum:SetText(itemCount)
            --稀有度背景图片
            if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                local strArr = string.split(itemConfig.rarityPath, '/')
                local littePath = strArr[#strArr]
                local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                local itemRarityPic = LoadObject(rarityPath)
                if itemRarityPic then
                    itemUI.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                end
            end

            --icon
            if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                local strArr = string.split(itemConfig.iconPath, '/')
                local littePath = strArr[#strArr]
                local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                local iconRes = LoadObject(iconResPath)
                if iconRes then
                    itemUI.icon_res:SetBrushFromAtlasInterface(iconRes)
                end
            end

            itemUI.ItemPanel:SetRenderOpacity(1)
            itemUI.Img_bg.OnMouseButtonDownEvent:Unbind()
            itemUI.Img_bg.OnMouseButtonDownEvent:Bind(self, function()
                UIUtils.ShowItemInfo(itemId, itemCount)
                return UE.UWidgetBlueprintLibrary.Handled()
            end)

            ui.HBox_Reward:AddChild(itemUI)
        end
    end

    self:RefreshItemEx(ui, questData)
end

function M:RefreshItemEx(ui, questData)
    if ui then
        local hasGot = questData.completed
        local hasFinished = questData.finished
        -- print('==index:' .. tostring(idx) .. ',hasgot:' .. tostring(hasGot))
        
        -- ui.image2:SetVisibility(hasGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Panel_Getted:SetVisibility(hasGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Img_Getted:SetVisibility(hasGot and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

        -- ui.Btn_Goto:SetVisibility((not hasGot and not hasFinished) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
        ui.Btn_Goto:SetVisibility(UE.ESlateVisibility.Hidden)
        ui.Btn_Receive:SetVisibility((not hasGot and hasFinished) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)

        -- if hasGot then
        --     ui.Img_ItemBg:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        -- elseif not hasGot and hasFinished then
        --     ui.Img_ItemBg:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        -- else
        --     ui.Img_ItemBg:SetVisibility(UE.ESlateVisibility.Hidden)
        -- end
        --红点提醒
        ui.Img_RedPoint:SetVisibility((not hasGot and hasFinished) and UE.ESlateVisibility.SelfHitTestInVisible or UE.ESlateVisibility.Hidden)
    end
end

function M:IsAnimPlaying()
    local isPlayAnim = false
    for idx = 1, 5 do
        local ui = self['UI_RewardBookItem' .. idx]
        if ui:IsAnimationPlaying(ui.Anim_Flip) then
            isPlayAnim = true
            break
        end
    end
    return isPlayAnim
end

----------------------------------------------------------------------
--- ui event
function M:OnClicked_Btn_Exit()
    if self:IsAnimationPlaying(self.InitAnimation) then return end
    self:BindToAnimationFinished(self.InitAnimation, function()
        UE.UGameplayStatics.GetGameInstance(self):RemoveTopUI(true)
    end)
    self:PlayAnimationReverse(self.InitAnimation, 2, false)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.OnClicked_Btn_Exit)

function M:OnClicked_RewardBookItem(index)
  
    local ui = self['UI_RewardBookItem' .. index]
    local questInfo = self.QuestDataList[index]
    local config = Database.Query('d_task_book', questInfo.mission_id)
    if questInfo and config then
        local hasGot = questInfo.completed
        local hasFinished = questInfo.finished
        if hasGot then
            -- if not ui:IsAnimationPlaying(ui.Anim_Flip) then
            --     ui:PlayFlipEffect()
            -- end
        elseif hasFinished then
            self:GetReward(questInfo.mission_id)
        end
    end
end

function M:OnClicked_Btn_Left()
    if self:IsAnimPlaying() then return end
    self.SelectedTabIndex = math.max(1, self.SelectedTabIndex - 1)
    self:PlayAnimationForward(self.switch, 1, false)
    self:RefreshTab()
end

function M:OnClicked_Btn_Right()
    if self:IsAnimPlaying() then return end
    self.SelectedTabIndex = math.min(self.TabMax, self.SelectedTabIndex + 1)
    self:PlayAnimationForward(self.switch, 1, false)
    self:RefreshTab()
end

function M:OnClicked_Btn_Chapter()
    --local questConfig = Database.Query('d_task_book', self.ChapterQuestInfo.mission_id)
    self.Text_Chapter:SetText(self.ChapterQuestInfo.DoneCount)
    if not self.ChapterQuestInfo.completed and self.ChapterQuestInfo.finished then
        self:GetReward(self.ChapterQuestInfo.mission_id)
    else
        UIUtils.ShowNotify(self, Database.L10n(264))
    end
end

----------------------------------------------------------------------
--- assist function
function M:GetReward(questId)
    local SrpgController = require('Module.Srpg.SrpgController')
    if SrpgController:GetInstance():HasPendingFight() then
        UIUtils.ShowNotify(self, Database.L10n(285))
        return
    end
    QuestSystem:GetInstance():ReqCompletePlayerBookMission(questId)
end

return M
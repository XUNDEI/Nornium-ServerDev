
require "UnLua"
local Database = require("_Game.Utils.Database")

---@class BP_NPC_Dialog_C : BP_NPC_Dialog
local M = UnLua.Class()

local EDialogType = {
    NonInterrupt = 1, --不可打断
    Interrupt = 2, --可打断->显示对话选项
}

function M:ReceiveBeginPlay()
    -- self:InitDialogConfig()
    -- self.IsPlayDialog = false --是否正在播放对话
    -- self.Widget_Dialog:SetVisibility(false)
    -- if self.Widget_Dialog:GetUserWidgetObject() then
    --     self.Widget_Dialog:GetUserWidgetObject().Border:SetRenderOpacity(0)
    -- end
   
    -- if self.IsInitAutoPlay then
    --     self:StartDialog(self.InitDialogId, 0) --从头开始播放
    -- end
    -- self.Overridden.ReceiveBeginPlay(self)
    self.InOtherDialogConfigList = {}
end

function M:ReceiveEndPlay()

end

function M:OnInteractiveDialogBeginOverLap()
    if self.InitDialogId <= 0 then
        self:InitDialogConfig()
    end
    if self.InitDialogId > 0 then
        if self.IsPlayDialog then
            if self.DialogType == EDialogType.Interrupt then
                local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
                if not gameInstance.UI_Dialog_Story or self.bHidden then
                    self:StopAllDialog()
                    self:ShowOption()
                end
            end
        else
            if self.DialogType == EDialogType.Interrupt then
                self:ShowOption()
            end
        end
    end
end

function M:OnInteractiveDialogEndOverLap()
    if self.InitDialogId > 0 then
        if self.DialogType == EDialogType.Interrupt then
            self:StopAllDialog()
            self:HideOption()
        end
    end
end

----------------------------------------------------------------------
---
function M:StartDialog(dialogId, parentNpcId)
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    if gameInstance.UI_Dialog_Story or self.bHidden then
        return
    end
    -- print('------------------------------>bHide:' .. tostring(self.bHidden))
    if dialogId <= 0 then return end
    local name = UE.UKismetSystemLibrary.GetDisplayName(self)
    -- print("===StartDialog:NpcId:" .. tostring(self.NpcId) .. ',dialogId:' .. tostring(dialogId) .. ',name:' .. tostring(name))

    -- print("====StartDialog:" .. tostring(dialogId) .. ",curId:" .. tostring(self.CurDialogId))
    -- print("====>>MainNpcId:" .. tostring(self.MainNpcId) .. ",parentNpcId:" .. tostring(parentNpcId))
    if self.InitDialogId == dialogId then
        self.MainNpcId = self.NpcId
    else
        --判断npcid在那个对话中
        if #self.InOtherDialogConfigList > 0 then
            for npcId, _ in pairs(self.InOtherDialogConfigList) do
                local npcActor = self:GetNpcCharByNpcId(npcId)
                if npcActor then
                    npcActor:StopAllDialog()
                end
            end
        end
    end
   
    self.CurDialogId = dialogId
    self:PlayDialog()
end

function M:PlayDialog()
    -- print("==PlayDialog mainId:" .. tostring(self.MainNpcId) .. ",npcId:" .. tostring(self.NpcId))
    -- print("===list:" .. tostring(table.dump(self.DialogConfigList, nil, 10)))
    self.IsPlayDialog = true
    self.Widget_Dialog:SetVisibility(true)
    self.Widget_Dialog:SetHiddenInGame(false, false)
    local ui = self.Widget_Dialog:GetUserWidgetObject() 
    if ui and self.CurDialogId > 0 then
        ui.EventOnPlayEnd:Clear()
        ui.EventOnPlayEnd:Add(self, self.EventOnPlayEnd)
        ui:InitUI(self.CurDialogId)
       
    end
end

function M:StopDialog()
    self.MainNpcId = 0
    self.CurDialogId = 0
    self.IsPlayDialog = false
    self.Widget_Dialog:SetVisibility(false)
    self.Widget_Dialog:SetHiddenInGame(true, false)
    local ui = self.Widget_Dialog:GetUserWidgetObject() 
    if ui then
        ui.EventOnPlayEnd:Remove(self, self.EventOnPlayEnd)
        ui:StopUI()
    end
end

function M:StopAllDialog()
    self:StopDialog()
    if self.MainNpcId ~= self.NpcId then --转到主npc去播放下一个
        local npcActor = self:GetNpcCharByNpcId(self.MainNpcId)
        if npcActor then
            npcActor:StopAllDialog()
        end
    end
end

function M:PlayNextDialog(curDialogId)
    -- print("====PlayNextDialog:" .. tostring(curDialogId))
    local config = Database.Query('d_story_bubble', curDialogId)
    if config then 
        local nextId = tonumber(config.next)
        if nextId > 0 then
            local nextConfig = Database.Query('d_story_bubble', nextId)
            if nextConfig then
                local nextNpcId = tonumber(nextConfig.npcID)
                if nextId > 0 and nextNpcId > 0 then
                    if nextNpcId == self.NpcId then
                        self:StartDialog(nextId, self.MainNpcId)
                    else
                        local npcActor = self:GetNpcCharByNpcId(nextNpcId)
                        if npcActor then
                            npcActor:StartDialog(nextId, self.MainNpcId)
                        end
                    end
                elseif nextId == 0 then
                    if self.IsLoop then
                        self:StartDialog(self.InitDialogId, self.MainNpcId) --从头开始播放
                    else
                        -- self:StopDialog()
                        self:StartDialog(self.InitDialogId, self.MainNpcId) --从头开始播放
                    end
                else
                    print("====playNextDialog nextId:" .. tostring(nextId))
                end
            end
        end
        
    else
        print("====playNextDialog error:" .. tostring(curDialogId))
    end
end

function M:InitDialogConfig()
    print("--------InitDialogConfig:" .. tostring(self.NpcId))
    if self.NpcId == 0 then
        return
    end
    -- print("===初始化npcId:" .. tostring(self.NpcId))
    self.DialogConfigList = {}
    

    local npcBubbleConfig = Database.Query('d_story_bubble_npc', self.NpcId)
    if npcBubbleConfig then
        self.DialogType = npcBubbleConfig.dialogueTypes
        self.InitDialogId = npcBubbleConfig.dialogueID
        -- print("===初始化InitDialogId:" .. tostring(self.InitDialogId))
    else
        -- LOG_ERROR('--->d_story_bubble_npc非法配置对话npcId:' .. tostring(self.NpcId))
        return
    end
   
    local dialogId = self.InitDialogId
    while dialogId > 0 do
        local dialogConfig = Database.Query('d_story_bubble', dialogId)
        if dialogConfig then
            table.insert(self.DialogConfigList, dialogConfig)
            dialogId = dialogConfig.next
        else
            dialogId = 0
        end
    end
    --不是主npc
    if #self.DialogConfigList == 0 then
        local configAll = {}
        local d_story_bubble_npc = require('ClientDatas.d_story_bubble_npc')
        for id, v in pairs(d_story_bubble_npc) do
            local list = {}
            local dialogId = v.dialogueID
            while dialogId > 0 do
                local dialogConfig = Database.Query('d_story_bubble', dialogId)
                if dialogConfig then
                    local npcId = tonumber(dialogConfig.npcID)
                    local bFind = false
                    for _, nId in ipairs(list) do
                        if nId == npcId then
                            bFind = true
                            break
                        end
                    end
                    if not bFind then
                        table.insert(list, npcId)
                    end
                    dialogId = dialogConfig.next
                else
                    dialogId = 0
                end
            end
            if #list > 0 then
                if not configAll[id] then
                    configAll[id] = {}
                end
                configAll[id][v.dialogueID] = list
            end
        end
        for npcId, v in pairs(configAll) do
            for dId, npcs in pairs(v) do 
                local bFind = false
                for _, npcId in ipairs(npcs) do 
                    if npcId == self.NpcId then
                        bFind = true 
                        break
                    end
                end
                if bFind then
                    if not  self.InOtherDialogConfigList then
                        self.InOtherDialogConfigList = {}
                    end
                    self.InOtherDialogConfigList[npcId] = npcs
                end
            end
        end
    end
end

function M:ShowOption()
    if self.NpcDialogOptionItem then
        UIManager:GetInstance():RemoveInteractOption(self.NpcDialogOptionItem)
        self.NpcDialogOptionItem = nil
    end 
    self.NpcDialogOptionItem = UIManager:GetInstance():AddInteractOption(self, Database.L10n(self.NpcOptionNameId), function()
        self:OnClicked_OptionItem(self.NpcDialogOptionItem, 0)
    end)
end

function M:HideOption()
    if self.NpcDialogOptionItem then
        UIManager:GetInstance():RemoveInteractOption(self.NpcDialogOptionItem)
        self.NpcDialogOptionItem = nil
    end
end

----------------------------------------------------------------------
---ui Event
-- function M:OnClicked_OptionItem(item, index)
--     if item == self.NpcDialogOptionItem then
--         self:HideOption()
--         self:StartDialog(self.InitDialogId, self.MainNpcId) --从头开始播放
--     end
-- end

function M:EventOnPlayEnd()
    if self.Widget_Dialog:GetUserWidgetObject() then
        self.Widget_Dialog:GetUserWidgetObject().EventOnPlayEnd:Remove(self, self.EventOnPlayEnd)
        self.Widget_Dialog:SetVisibility(false)
        self.Widget_Dialog:SetHiddenInGame(true, false)
    end
    if self.MainNpcId > 0 and self.MainNpcId ~= self.NpcId then --转到主npc去播放下一个
        local npcActor = self:GetNpcCharByNpcId(self.MainNpcId)
        if npcActor then
            npcActor:EventOnPlayEnd()
        end
    else
        --self.MainNpcId = 0
        self.IsPlayDialog = false
        -- print('====EventOnPlayEnd:')
        self:PlayNextDialog(self.CurDialogId)
    end 
end

function M:GetNpcCharByNpcId(npcId)
    local bp_npc_dialog_class = UE.LoadClass('/Game/_Game/Blueprints/NPCs/BP_NPC_Dialog.BP_NPC_Dialog_C')
    local npc_actors = UE.UGameplayStatics.GetAllActorsOfClass(self, bp_npc_dialog_class)
    if npc_actors:Length() > 0 then
        for i = 1, npc_actors:Length() do
            local npcActor = npc_actors:Get(i)
            if npcActor.NpcId == npcId then
                return npcActor
            end
        end
    end 
    return nil
end

return M
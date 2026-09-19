--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type SO_NPCBase_C
local M = UnLua.Class()

-- function M:ReceiveBeginPlay()
--     self.Overridden.ReceiveBeginPlay(self)
--     print("------------------------self.BP_Interactive.ChildActor1")
--     if self.BP_Interactive.ChildActor then
--         print("------------------------self.BP_Interactive.ChildActor2")
--         self.BP_Interactive.ChildActor.SpherePerceive:SetSphereRadius(self.PerceiveRadius, false)
--         self.BP_Interactive.ChildActor.SphereInteractive:SetSphereRadius(self.InteractiveRadius, false)
--         self.BP_Interactive.ChildActor.Lua_OnOverlap:Add(self, self.OnOverlap_Interactive)
--         self.BP_Interactive.ChildActor.LUa_EndOverLap:Add(self, self.EndOverlap_Interactive)
--         --获取 ui_com_npc
--     end
--     local class = UE.LoadClass('/Game/_Game/Blueprints/UI/UI_Com_NPC.UI_Com_NPC_C')
--     local widgetComps = self:K2_GetComponentsByClass(UE.UWidgetComponent):ToTable()
--     for _, widgetComp in ipairs(widgetComps) do
--         local ui = widgetComp:GetUserWidgetObject()
--         if ui:Cast(class) then
--             self.UI_Com_NPC = ui
--             break
--         end
--     end
--     if self.UI_Com_NPC then
--         self.UI_Com_NPC:UpdateText(self.Name)
--         self.UI_Com_NPC:UpdateTitleText(self.Title, UE.ESlateVisibility.Visible)
--     end

--     if self.Activated then
--         self:NPC_Activate()
--     else
--         self:NPC_Deactivate()
--     end
-- end

function M:OnEvent_OverlapStart()
    print('---------basenpc.onverlap:' .. tostring('aaaaa'))
    UIManager:GetInstance():ClearInteractOption()
    UIManager:GetInstance():AddInteractOption(self, self.OptionId == 0 and 247 or self.OptionId, function()
        print('---------basenpc.onverlap.clicked:' .. tostring(1111111))
        local index = UIManager:GetInstance().layers.Options:GetChildrenCount() - 1
        local widget = UIManager:GetInstance().layers.Options:GetChildAt(index)
        self.BP_Interactive.ChildActor.Option = widget
        self:OnClickItem(widget, index)
    end)
end

function M:OnEvent_OverlapEnd()
    print('---------basenpc.onverlap.EndOverlap:' .. tostring(2222222))
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
end

function M:OnClickItem(widget, index)
    print('---------basenpc.onverlap.clicked:' .. tostring(33333333))
    UIManager:GetInstance():RemoveInteractOptionByObject(self)
    self.Overridden.OnClickItem(self, widget, index)
end

return M
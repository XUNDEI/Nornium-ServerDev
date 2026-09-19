--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type STT_Button_C
local M = UnLua.Class()

function M:ReceiveLatentEnterState(Transition)
    if self.UI then
        local UIClass = UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.UI)
        if not UE.UKismetSystemLibrary.IsValidClass(UIClass) then
            UE.UKismetSystemLibrary.LoadClassAsset_Blocking(self.UI)
            UIClass = UE.UKismetSystemLibrary.Conv_SoftClassReferenceToClass(self.UI)
        end
        self.WatchUI = UIClass
    end
    if self.WatchUI then
        local top_ui = UIManager:GetInstance():GetTopUI()
        if UE.UGameplayStatics.ObjectIsA(top_ui, self.WatchUI) then
            self:ShowButton()
        end
    else
        self:ShowButton()
    end
end

function M:ReceiveStateCompleted(Transition)
    if self.Panel then
        UIManager:GetInstance():RemoveUI(self.Panel)
    end
end

function M:ReceiveLatentTick(DeltaTime)
    if self.Panel then return end
    if self.WatchUI then
        local top_ui = UIManager:GetInstance():GetTopUI()
        if UE.UGameplayStatics.ObjectIsA(top_ui, self.WatchUI) then
            self:ShowButton()
        end
    end
end

function M:ShowButton()
    self.Panel = UE.UGameplayStatics.GetGameInstance(self):GetUISttButton()
    local button_ui = UE.UWidgetBlueprintLibrary.Create(self, self.WidgetClass)
    self.Panel.CanvasPanel:AddChild(button_ui)
    self.Panel:InitButton(button_ui)
    local anchors = UE.FAnchors()
    anchors.Maximum = self.WidgetAnchors
    anchors.Minimum = self.WidgetAnchors
    button_ui.Slot:SetAnchors(anchors)
    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(button_ui):SetPosition(self.WidgetPosition)
    button_ui.TaskId = self.Id
end

return M
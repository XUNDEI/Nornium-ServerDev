local datetime = require("_Game.Utils.datetime")
local PlayerSystem = require("Module.Player.PlayerSystem")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Bulletin_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Construct()
    if not M.UI_BulletinItem then
        M.UI_BulletinItem = LoadClass('/Game/_Game/Blueprints/UI/UI_Bulletin/UI_BulletinItem.UI_BulletinItem_C')
        M.UI_BulletinItemRef = UnLua.Ref(M.UI_BulletinItem)
    end
end

function M:Setup()
    self.Btn_Close.OnClicked:Add(self, self.Close)
    self.BulletinTab.OnCheckStateChanged:Add(self, function(_, isOn)
        self:ShowNotice(isOn and "1" or "2")
    end)

    self.BulletinTab:SetIsCheckedAndFireEvent(false)

    self:Load()
end

function M:Load()
    if not self.save then
        if UE.UGameplayStatics.DoesSaveGameExist("SG_SaveGame_Notice", 0) then
            ---@type SG_SaveGame_Notice_C
            self.save = UE.UGameplayStatics.LoadGameFromSlot('SG_SaveGame_Notice', 0)
            self.saveRef = UnLua.Ref(self.save)
        else
            self.save = UE.UGameplayStatics.CreateSaveGameObject(UE.UClass.Load('/Game/_Game/Blueprints/Game/SG_SaveGame_Notice.SG_SaveGame_Notice_C'))
            self.saveRef = UnLua.Ref(self.save)
        end
    end
end

function M:Save()
    UE.UGameplayStatics.SaveGameToSlot(self.save, "SG_SaveGame_Notice", 0)
end

function M:ShowNotice(type)
    self.type = type
    ---@type BP_GameInstance_C
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)

    if not self.waiting then
        self.waiting = true
        gameInstance:GMHttpPost("/client/notice/list", {}, function(res, status, responseString, msg)
            self:OnServerStatus(res, status, responseString, msg)
        end)
    end
end

function M:OnServerStatus(res, status, responseString, msg)
    if not res then
        UIManager:GetInstance():Notify("找不到公告")
        self:Close()
    elseif msg.code ~= 0 then
        UIManager:GetInstance():Notify("公告错误 " .. msg.code)
        self:Close()
    end

    self.notices = msg.data

    self.NoticeGroup:ResetToggleState()
    self.NoticeList:ClearChildren()
    self.NoticeGroup:ResetToggleState()
    for _, noticeInfo in ipairs(msg.data) do
        local show = noticeInfo.isUse == "yes"
        local createTime = datetime.str_to_time(noticeInfo.openTime)
        local closeTime = datetime.str_to_time(noticeInfo.closeTime)
        local type = noticeInfo.type

        if self.type == type and show and PlayerSystem:GetInstance():GetServerTime() < closeTime then
            ---@type UI_BulletinItem_C
            local entry = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BulletinItem)

            self.NoticeList:AddChild(entry)

            local date = os.date("*t", createTime)
            entry.Title1:SetText(noticeInfo.noticeTitle)
            entry.M1:SetText(date.month)
            entry.D1:SetText(date.day)
            entry.Title2:SetText(noticeInfo.noticeTitle)
            entry.M2:SetText(date.month)
            entry.D2:SetText(date.day)

            entry.Img_RedPoint:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
            for _, id in pairs(self.save.ReadNotices) do
                if id == noticeInfo.id then
                    entry.Img_RedPoint:SetVisibility(UE.ESlateVisibility.Hidden)
                    break
                end
            end

            entry.CheckBox.OnCheckStateChanged:Add(entry, function(_, isOn)
                if isOn then
                    self.Content:SetText(noticeInfo.text)

                    self.save.ReadNotices:AddUnique(noticeInfo.id)
                    self:Save()
                    entry.Img_RedPoint:SetVisibility(UE.ESlateVisibility.Hidden)

                    self:UpdateUnread()
                end
            end)

            entry.CheckBox.CheckBoxGroup = self.NoticeGroup
        end
    end

    local entries = self.NoticeList:GetAllChildren()

    if entries:Num() > 0 then
        entries:Get(1).CheckBox:SetIsCheckedAndFireEvent(true)
    end

    self.waiting = false
end

function M:UpdateUnread()
    local anyEntryUnread = {
        ["2"] = false,
        ["1"] = false,
    }
    for _, noticeInfo in ipairs(self.notices) do
        local entryRead = false
        local show = noticeInfo.isUse == "yes"
        local closeTime = datetime.str_to_time(noticeInfo.closeTime)

        if show and PlayerSystem:GetInstance():GetServerTime() < closeTime then
            for _, id in pairs(self.save.ReadNotices) do
                if id == noticeInfo.id then
                    entryRead = true
                    break
                end
            end
        else
            entryRead = true
        end

        if not entryRead then
            anyEntryUnread[noticeInfo.type] = true
        end
    end

    self.Game_RedPoint:SetVisibility(anyEntryUnread["2"] and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    self.Activity_RedPoint:SetVisibility(anyEntryUnread["1"] and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

return M

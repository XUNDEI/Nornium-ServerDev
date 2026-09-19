local MailModel = require("Module.Mail.MailModel")

---@type UI_EmailItem_C
local M = UnLua.Class()

---@param mailInfo MailInfo
function M:Setup(mailInfo)
    self.title:SetText(mailInfo.title)
    self.title0:SetText(mailInfo.title)
    self.title1:SetText(mailInfo.title)

    self.sender:SetText(mailInfo.type)
    self.sender0:SetText(mailInfo.type)
    self.sender1:SetText(mailInfo.type)

    local dayElapsed = math.ceil((os.time() - mailInfo.send_seconds) / 86400)

    self.DaysLeft:SetText(30 - dayElapsed)

    self.choose:SetVisibility(UE.ESlateVisibility.Hidden)

    self:UpdateState(mailInfo)
end

function M:Unselect()
    LOG_INFO("unselect", UE.UKismetSystemLibrary.GetDisplayName(self))
    --self.choose:SetVisibility(UE.ESlateVisibility.Hidden)
    self:PlayAnimationReverse(self.switch)
end

function M:Select()
    LOG_INFO("select", UE.UKismetSystemLibrary.GetDisplayName(self))
    -- self.choose:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    self:PlayAnimationForward(self.switch)
end

---@param mailInfo MailInfo
function M:UpdateState(mailInfo)
    self.unread:SetVisibility(UE.ESlateVisibility.Hidden)
    self.read:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Item:SetVisibility(UE.ESlateVisibility.Hidden)
    self.taken:SetVisibility(UE.ESlateVisibility.Hidden)

    if mailInfo.mail_state == MailModel.MailState.Unread then
        self.unread:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    else
        self.read:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
    end

    if #mailInfo.item_infos > 0 then
        if mailInfo.mail_state ~= MailModel.MailState.Received then
            self.Item:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        else
            self.taken:SetVisibility(UE.ESlateVisibility.SelfHitTestInvisible)
        end
    end
end

return M

local UIUtils = require "_Game.Utils.UIUtils"
local Client = require "Network.Client"
local Protos = require("Helper.Protos")
local Database = require("_Game.Utils.Database")

local MailModel = require("Module.Mail.MailModel")
local MailController = require("Module.Mail.MailController")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_Email_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_Cursor,
}

InputUtils.RegisterMouseEvent(M)

function M:Initialize()
    if not M.UI_EmailItem then
        M.UI_EmailItem = LoadClass('/Game/_Game/Blueprints/UI/UI_Email/UI_EmailItem.UI_EmailItem_C')
        M.UI_EmailItemRef = UnLua.Ref(M.UI_EmailItem)
    end
end

---@param self UI_Email_C
---@param parsed_msg ResMailReadMessage
M[Protos.RES_MAIL_READ] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        MailController:GetInstance():ReadMail(parsed_msg.req_data.mail_uuid)

        self.mailWidgets[parsed_msg.req_data.mail_uuid]:UpdateState(MailController:GetInstance():GetMailByUUID(parsed_msg.req_data.mail_uuid))

        self:SelectMail(parsed_msg.req_data.mail_uuid)
    end
end

---@param self UI_Email_C
---@param parsed_msg ResMailReadMessage
M[Protos.RES_MAIL_RECEIVE] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        MailController:GetInstance():ReceiveMail(parsed_msg.req_data.mail_uuid)

        self.mailWidgets[parsed_msg.req_data.mail_uuid]:UpdateState(MailController:GetInstance():GetMailByUUID(parsed_msg.req_data.mail_uuid))

        self:SelectMail(parsed_msg.req_data.mail_uuid)

        local mailInfo = MailController:GetInstance():GetMailByUUID(parsed_msg.req_data.mail_uuid)

        local rewardList = {}
        for _, item in ipairs(mailInfo.item_infos) do
            table.insert(rewardList, {
                itemId = item.item_id,
                count = item.count,
            })
        end
        UIUtils.ShowGetRewardCommonUI(self, rewardList)
    end
end

M[MailController.MailUpdated] = function(self)
    self:Refresh()
end

function M:Close()
    UIManager:GetInstance():RemoveUI(self)
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.Close)

function M:Construct()
    self.Exit.OnClicked:Add(self, self.Close)

    self.Receive.OnClicked:Add(self.Receive, function()
        if self.selectedMailUUID then
            Client.send(Protos.REQ_MAIL_RECEIVE, { mail_uuid = self.selectedMailUUID })
        end
    end)

    NetworkMessageManager:GetInstance():AddListener(Protos.RES_MAIL_READ, self)
    NetworkMessageManager:GetInstance():AddListener(Protos.RES_MAIL_RECEIVE, self)
    -- NetworkMessageManager:GetInstance():AddListener(Protos.NTF_ITEM_INFO, self)

    MessageManager:GetInstance():AddListener(MailController.MailUpdated, self)
end

function M:Refresh()
    local mails = MailController:GetInstance():GetMails()

    ---@type UI_EmailItem_C[]
    self.mailWidgets = {}
    self.Mails:ClearChildren()
    for _, mailInfo in ipairs(mails) do
        ---@type UI_EmailItem_C
        local mail = UE.UWidgetBlueprintLibrary.Create(self, M.UI_EmailItem)

        self.Mails:AddChild(mail)

        mail:Setup(mailInfo)

        mail.Modal.OnClicked:Add(mail.Modal, function()
            self:SelectMail(mailInfo.mail_uuid)
        end)

        self.mailWidgets[mailInfo.mail_uuid] = mail
    end

    self.Capacity:SetText(tostring(#mails))

    self:SelectMail()
end

function M:ShowMail(UUID)
    self.MailContent:SetVisibility(UUID and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    if UUID then
        local mailInfo = MailController:GetInstance():GetMailByUUID(UUID)

        local received = mailInfo.mail_state == 2

        self.Title:SetText(mailInfo.title)
        self.Sender:SetText(mailInfo.type)

        local date = os.date("%Y.%m.%d", mailInfo.send_seconds)
        self.Date:SetText(date)

        self.Content:SetText(mailInfo.content)

        self.Items:ClearChildren()
        for _, itemInfo in pairs(mailInfo.item_infos) do
            local itemConfig = UIUtils.GetItemConfigById(itemInfo.item_id)
            if itemConfig then
                if not itemInfo.config then
                    itemInfo.config = Database.Query("d_bag_item", itemInfo.item_id)
                end
                if not itemInfo.config then
                    itemInfo.config = Database.Query("d_bag_item_weapon", itemInfo.item_id)
                end
                if not itemInfo.config then
                    itemInfo.config = Database.Query("d_bag_item_equip", itemInfo.item_id)
                end

                ---@type UI_Get_Item_C
                local item = UE.UWidgetBlueprintLibrary.Create(self, UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_Shop/UI_Get_Item.UI_Get_Item_C"))
                item.TextName:SetText(Database.L10n(itemConfig.itemName))
                item.TextNum:SetText(itemInfo.count)
                --稀有度背景图片
                if itemConfig.rarityPath and itemConfig.rarityPath ~= '' then
                    local strArr = string.split(itemConfig.rarityPath, '/')
                    local littePath = strArr[#strArr]
                    local rarityPath = string.format('/Game/_Game/TP_New/Common/Frames/%s.%s', littePath, littePath)
                    local itemRarityPic = LoadObject(rarityPath)
                    if itemRarityPic then
                        item.container_icon_res:SetBrushFromAtlasInterface(itemRarityPic)
                    end
                end
    
                --icon
                if itemConfig.iconPath and itemConfig.iconPath ~= '' then
                    local strArr = string.split(itemConfig.iconPath, '/')
                    local littePath = strArr[#strArr]
                    local iconResPath = string.format('/Game/_Game/%s.%s', itemConfig.iconPath, littePath)
                    local iconRes = LoadObject(iconResPath)
                    if iconRes then
                        item.icon_res:SetBrushFromAtlasInterface(iconRes)
                    end
                end

                item.ItemPanel:SetRenderOpacity(1)
                item:SetIsEnabled(not received)
                item.Img_bg.OnMouseButtonDownEvent:Unbind()
                item.Img_bg.OnMouseButtonDownEvent:Bind(item, function()
                    UIUtils.ShowItemInfo(itemInfo.item_id, itemInfo.count, 0)
                    return UE.UWidgetBlueprintLibrary.Handled()
                end)

                self.Items:AddChild(item)
            end
        end

        self.Receive:SetIsEnabled(#mailInfo.item_infos > 0 and not received)
        self.Receive:SetVisibility(#mailInfo.item_infos > 0 and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
    end
end

function M:SelectMail(UUID)
    if self.selectedMailUUID then
        self.mailWidgets[self.selectedMailUUID]:Unselect()
    end

    self.selectedMailUUID = UUID

    if self.selectedMailUUID then
        local mailInfo = MailController:GetInstance():GetMailByUUID(UUID)

        if mailInfo.mail_state ~= MailModel.MailState.Unread then
            self.mailWidgets[self.selectedMailUUID]:Select()
            self:ShowMail(UUID)
        else
            Client.send(Protos.REQ_MAIL_READ, { mail_uuid = UUID })
        end
    end
    self.MailContent:SetVisibility(self.selectedMailUUID and UE.ESlateVisibility.SelfHitTestInvisible or UE.ESlateVisibility.Hidden)
end

function M:Destruct()
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_MAIL_READ, self)
    NetworkMessageManager:GetInstance():RemoveListener(Protos.RES_MAIL_RECEIVE, self)
    -- NetworkMessageManager:GetInstance():RemoveListener(Protos.NTF_ITEM_INFO, self)

    MessageManager:GetInstance():RemoveListener(MailController.MailUpdated, self)
end

return M

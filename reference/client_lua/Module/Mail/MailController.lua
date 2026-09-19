local Protos = require("Helper.Protos")
local NetworkMessageListener = require("Module.NetworkMessageListener")
local MessageManager = require("Framework.Updater.MessageManager"):GetInstance()

local MailModel = require("Module.Mail.MailModel")

---@class MailController : NetworkMessageListener
---@field model MailModel
---@field GetInstance fun():MailController
local MailController = BaseClass("MailController", NetworkMessageListener)

MailController.MailUpdated = "MailController.MailUpdated"

---{{{protos
MailController.__listened_network_messages = {
    Protos.RES_MAIL_LIST,
    Protos.NTF_MAIL_LIST,
}

---@param self MailController
---@param parsed_msg ResMailListMessage
MailController[Protos.RES_MAIL_LIST] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.model:Init(parsed_msg.res_mail_list.mail_list_info.mail_infos)
    end

    MessageManager:Broadcast(MailController.MailUpdated)
    MessageManager:Broadcast('OnMsg_MailInit')
end

---@param self MailController
---@param parsed_msg NtfMailListMessage
MailController[Protos.NTF_MAIL_LIST] = function(self, result, msgId, parsed_msg)
    if result == 0 then
        self.model:UpdateMail(parsed_msg.ntf_mail_list)
    end

    MessageManager:Broadcast(MailController.MailUpdated)
end
---}}}

function MailController:GetMails()
    return self.model.mails
end

function MailController:GetMailByUUID(UUID)
    for _, mail in ipairs(self.model.mails) do
        if mail.mail_uuid == UUID then
            return mail
        end
    end
end

function MailController:ReadMail(UUID)
    self.model:ReadMail(UUID)

    MessageManager:Broadcast(MailController.MailUpdated)
end

function MailController:ReceiveMail(UUID)
    self.model:ReceiveItems(UUID)

    MessageManager:Broadcast(MailController.MailUpdated)
end

function MailController:HasUnreadMail()
    return self.model:HasUnreadMail()
end

function MailController:__init()
    self.model = MailModel.New()
end

return MailController

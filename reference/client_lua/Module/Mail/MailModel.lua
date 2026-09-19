local MailModel = BaseClass("MailModel")

MailModel.MailState = {
    Unread = 0,
    Read = 1,
    Received = 2,
}

function MailModel:__init()
    self.mails = {}
end

local QUOTE_CHARS = {
    ["@"] = "@",
    ["s"] = " ",
    ["n"] = "\n",
}

local function format(str)
    local res = ""
    local escaped = false

    for i = 1, string.len(str) do
        local char = string.sub(str, i, i)
        if escaped then
            if QUOTE_CHARS[char] then
                res = res .. QUOTE_CHARS[char]
                escaped = false
            else
                res = res .. "@" .. char
                escaped = false
            end
        else
            if char == "@" then
                escaped = true
            else
                res = res .. char
            end
        end
    end

    if escaped then
        res = res .. "@"
    end

    return res
end

---@param mailList MailInfo[]
function MailModel:Init(mailList)
    for _, mail in ipairs(mailList) do
        mail.content = format(mail.content)
        mail.title = format(mail.title)
        mail.type = format(mail.type)
    end

    self.mails = mailList
    
    table.sort(self.mails, function(a, b)
        return a.send_seconds > b.send_seconds
    end)
end

function MailModel:HasUnreadMail()
    return table.any(self.mails, function(mail)
        return mail.mail_state == MailModel.MailState.Unread
    end)
end

function MailModel:ReadMail(uuid)
    for _, mail in pairs(self.mails) do
        if mail.mail_uuid == uuid then
            mail.mail_state = MailModel.MailState.Read
            break
        end
    end
end

function MailModel:ReceiveItems(uuid)
    for _, mail in pairs(self.mails) do
        if mail.mail_uuid == uuid then
            mail.mail_state = MailModel.MailState.Received
            break
        end
    end
end

---@param msg NtfMailList
function MailModel:UpdateMail(msg)
    for i = #self.mails, 1, -1 do
        if table.indexof(msg.removed_mail_uuids, self.mails[i].mail_uuid) then
            table.remove(self.mails, i)
        end
    end

    for _, mail in pairs(msg.added_mail_infos) do
        mail.content = format(mail.content)
        mail.title = format(mail.title)
        mail.type = format(mail.type)
        table.insert(self.mails, mail)
    end

    table.sort(self.mails, function(a, b)
        return a.send_seconds > b.send_seconds
    end)
end

return MailModel

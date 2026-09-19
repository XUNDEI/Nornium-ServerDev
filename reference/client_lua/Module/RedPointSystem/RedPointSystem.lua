local NetCmdController = require "Framework.Common.NetCmdController"
local M = BaseClass("RedPointSystem", NetCmdController)
local Client = require "Network.Client"

M.RedRecord = {}
----------------------------------------------------------------------
---
function M:AddRecord(type, id)
    if not self.RedRecord[type] then
        self.RedRecord[type] = {}
    end
    local have = false
    for _, rid in ipairs(self.RedRecord[type]) do
        if rid == id then
            have = true
            break
        end
    end
    if not have then
        table.insert(self.RedRecord[type], id)
        MessageManager:GetInstance():Broadcast('OnMsg_RedPointSystem', type)
    end
end

function M:RemoveRecord(type, id)
    if self.RedRecord[type] then
        table.removebyvalue(self.RedRecord[type], id, false)
        MessageManager:GetInstance():Broadcast('OnMsg_RedPointSystem', type)
    end
end

function M:GetRecordCount(tag)
    local count = 0
    for key, value in pairs(self.RedRecord) do
        if string.contains(key, tag) then
            count = count + #value
        end
    end
    return count
end

function M:GetRecord(tag)
    return self.RedRecord[tag] or {}
end

return M

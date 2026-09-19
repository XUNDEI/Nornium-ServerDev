-- 绑定网络事件用的Messenger，注册事件时也会去关联相应的协议

local MessageManager = require "Framework.Updater.MessageManager"

local NetworkMessageManager = BaseClass("NetworkMessageManager", MessageManager)
local Client = require "Network.Client"
local pbmsg = require "Helper.pbmsg"

-- 外面应该用不上，应该都靠网络那边触发广播
local function Broadcast(self, Result, MsgId, ParsedMsg)
    -- TODO 如果未来Client.lua那边统一用协议号的话，这里就不需要转换了
    local MessageName = pbmsg.get_msg_name_by_msg_id(MsgId)
    if Result ~= 0 then
        self.messenger:Broadcast('ServerError', MessageName, Result, ParsedMsg)
    end
    return self.messenger:Broadcast(MessageName, Result, MsgId, ParsedMsg)
end

-- TODO 注册的参数后面转换成编号，减少开销？
-- 这个版本本质上只是多加了一步绑定到对应协议
---@param CallbackOrThis function | table @如果传过来一个function，就直接用作callback，如果传进来的是一个table/userdata，则默认其实现了名为MessageName的方法并自动生成一个绑定了self的callback
function NetworkMessageManager:AddListener(MessageName, CallbackOrThis)
    NetworkMessageManager.super.AddListener(self, MessageName, CallbackOrThis)

    Client.register_msg(MessageName, Broadcast, self)
end

return NetworkMessageManager

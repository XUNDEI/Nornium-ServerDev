local NetCmdController = BaseClass("NetCmdController", Singleton)

function NetCmdController:__init()
    self.__binded_network_events = {}
    self.__binded_msg_events = {}
    local mt = getmetatable(self)
    for k, v in pairs(mt.__index) do
        if (type(v) == 'function') then
            if (string.sub(k, 1, 9) == "OnNetCmd_") then
                local msgName = string.lower(string.sub(k, 10, -1))
                self.__binded_network_events[msgName] = BindCallback(self, v)
                NetworkMessageManager:GetInstance():AddListener(msgName, self.__binded_network_events[msgName])
            elseif (string.sub(k, 1, 6) == 'OnMsg_') then
                local msgName = k
                self.__binded_msg_events[msgName] = BindCallback(self, v)
                MessageManager:GetInstance():AddListener(msgName, self.__binded_msg_events[msgName])
            end
        end
    end
end

function NetCmdController:__delete()
    for msgName, bindedFunction in pairs(self.__binded_network_events) do
        NetworkMessageManager:GetInstance():RemoveListener(msgName, bindedFunction)
    end
    for msgName, bindedFunction in pairs(self.__binded_msg_events) do
        MessageManager:GetInstance():RemoveListener(msgName, bindedFunction)
    end
end

function NetCmdController:ReqMsgIsInSendCache(msgName, msg)
    local isInSend = false
    local Client = require "Network.Client"
    local caches = Client.get_send_caches()
    for _, v in pairs(caches) do
        if v.msg_name == msgName then --协议名字相同
            local msgIsSame = true
            --遍历消息体参数
            for idx, value in pairs(v.msg) do
                --只比较下简单的数字和字符串
                if (type(value) == 'number' or type(value) == 'string') and value ~= msg[idx] then
                    msgIsSame = false
                    break
                end
            end
            if msgIsSame then
                isInSend = true
                break
            end
        end
    end
    return isInSend
end

return NetCmdController
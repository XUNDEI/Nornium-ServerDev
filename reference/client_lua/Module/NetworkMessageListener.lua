local MessageListener = require("Module.MessageListener")

---@class NetworkMessageListener : MessageListener 基础的Model，自动绑定__listened_network_messages中的协议
---@field __listened_network_messages string[] 监听的协议，需要实现对应名字的方法
---@field private __binded_network_events table<string, fun()> 自动生成的回调函数绑定
local NetworkMessageListener = BaseClass("NetworkMessageListener", MessageListener)

function NetworkMessageListener:__init()
    self.__binded_network_events = {}
    if self.__listened_network_messages then
        for _, messageName in pairs(self.__listened_network_messages) do
            self.__binded_network_events[messageName] = BindCallback(self, self[messageName])

            NetworkMessageManager:GetInstance():AddListener(messageName, self.__binded_network_events[messageName])
        end
    end
end

function NetworkMessageListener:__delete()
    for messageName, bindedFunction in pairs(self.__binded_network_events) do
        NetworkMessageManager:GetInstance():RemoveListener(messageName, bindedFunction)
    end
end

return NetworkMessageListener

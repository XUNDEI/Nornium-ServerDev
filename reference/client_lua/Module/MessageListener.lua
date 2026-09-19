---@class MessageListener : Singleton 一个自动在创建时监听事件，销毁时解绑的类
---@field __listened_messages string[] 监听的事件，需要实现对应名字的方法
---@field private __binded_events table<string, fun()> 自动生成的回调函数绑定
local MessageListener = BaseClass("BaseModel", Singleton)

function MessageListener:__init()
    self.__binded_events = {}
    if self.__listened_messages then
        for _, messageName in pairs(self.__listened_messages) do
            if not self[messageName] then
                LOG_ERROR(self.__cname, "doesn't have callback for", messageName)
            end
            self.__binded_events[messageName] = BindCallback(self, self[messageName])

            MessageManager:GetInstance():AddListener(messageName, self.__binded_events[messageName])
        end
    end
end

function MessageListener:__delete()
    for messageName, bindedFunction in pairs(self.__binded_events) do
        MessageManager:GetInstance():RemoveListener(messageName, bindedFunction)
    end
end

return MessageListener

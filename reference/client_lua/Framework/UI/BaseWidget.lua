-- 基础的lua侧管理的UWidget，子类一定要设置__widget_class

---@class BaseWidget
---@field widget UUserWidget
local BaseWidget = BaseClass("BaseWidget")

--- lua侧管理的UserWidget，只创建并挂到@parent下，slot未设置
--- 注意Widget实际要在SBorder::SetContent执行之后才能获取内容，所以创建一个widget之后一定要先关联到父节点、初始化slot
---@param WorldContextObject UObject
function BaseWidget:__init(WorldContextObject)
    if not self.__widget_class then
        LOG_ERROR(self.__cname, "did not set WidgetClass!")
        return
    end

    local world = nil
    if type(WorldContextObject) == "table" or type(WorldContextObject) == "userdata" then
        world = WorldContextObject and WorldContextObject.GetWorld and WorldContextObject:GetWorld()
    end

    if world then
        self.widget = UE.UWidgetBlueprintLibrary.Create(WorldContextObject, self.__widget_class, nil)
    else
        self.widget = NewObject(self.__widget_class)
    end
end

return BaseWidget

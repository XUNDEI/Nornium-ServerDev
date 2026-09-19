local Widget = {}

---@class Widget
---@field __widget_class UClass

---@return Widget
function Widget.Class()
    local class = UnLua.Class()

    class.New = function(self)
        if not self.__widget_class then
            LOG_ERROR("Did not set WidgetClass!")
            return
        end

        return NewObject(self.__widget_class)
    end

    return class
end

return Widget

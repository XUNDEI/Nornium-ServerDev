--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_Weapon_ListItem_C
local M = UnLua.Class()

function M:Initialize(Initializer)
    self.item_data = {}
    self.index = 0
end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
end

--function M:Tick(MyGeometry, InDeltaTime)
--end


return M

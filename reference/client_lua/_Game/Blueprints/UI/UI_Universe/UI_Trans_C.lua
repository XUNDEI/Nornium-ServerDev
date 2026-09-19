--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"

---@type UI_Trans_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

-- function M:Construct()
-- end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitTransUI(main_pos_id)
    local main_pos_date = Database.Query('d_srpg_main_pos_base', main_pos_id)
    local main_pos_name = Database.L10n(main_pos_date.nameId)
    self.Text1_2:SetText(main_pos_name)
    local icon_path = string.format("/Game/_Game/TP_New/SRPG_starpoint_res/Frames/%s_png.%s_png", 
        main_pos_date.posIcon, main_pos_date.posIcon)
    local icon = UE.UObject.Load(icon_path)
    if icon then
        local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(icon, 0, 0)
        self.Image_2:SetBrush(icon_sprite)
    end
    self:PlayAnimation(self.End)
end

return M

--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_MenuCardInfo_C
local M = UnLua.Class()

local Database = require "_Game.Utils.Database"

function M:Initialize()
    if not M.UI_DescTextRef then
        M.UI_DescText = LoadClass("/Game/_Game/Blueprints/UI/UI_SRPG_CardShow/UI_DescText.UI_DescText_C")
        M.UI_DescTextRef = UnLua.Ref(M.UI_DescText)
    end
end

function M:InitCardInfoUI(card_id)
    self.DescBox:ClearChildren()
    local card_info = Database.Query("d_srpg_card_base", card_id)
    for _, value in ipairs(card_info.keywords) do
        local affix_info = Database.Query("d_srpg_card_keyword", value)
        local card = UE.UWidgetBlueprintLibrary.Create(self, M.UI_DescText)
        card.Title_text:SetText(Database.L10n(affix_info.nameId))
        card.Text_content:SetText(Database.L10n(affix_info.descrId))
        self.DescBox:AddChild(card)
    end
    local card_info = {}
    card_info.card_id = card_id
    card_info.upgrade_times = 0
    card_info.index = 0
    self.UI_MenuCardBtn:InitCardUI(card_info)
end

return M

--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_Panel_ChooseTarget_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

--function M:Construct()
--end

function M:OnClickCard(card)
    if card == self.SelectCard then
        self.SelectCard:SelectCard(false)
        self.SelectCard = nil
    else
        local select_card_num = self.CardArray:Length()
        for i = 1, select_card_num do
            self.CardArray[i]:SelectCard(card == self.CardArray[i])
        end
        self.SelectCard = card
    end
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

return M

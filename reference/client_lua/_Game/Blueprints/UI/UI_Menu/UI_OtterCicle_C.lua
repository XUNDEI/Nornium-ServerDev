--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Database = require "_Game.Utils.Database"

---@type UI_OutterCicle_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

-- function M:Construct()
-- end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:UpdateCardsUI(card_info)
    if card_info.card_count > 0 then
        for i = 1, 4 do
            local card_slot = string.format("card_%d", i)
            self[card_slot]:SetVisibility(UE.ESlateVisibility.Hidden)
        end
        for i = 1, card_info.card_count do
            local card_slot = string.format("card_%d", i)
            self[card_slot]:SetVisibility(UE.ESlateVisibility.Visible)
            -- show lock icon
            if i <= card_info.unlock_card_count then
                local unlock_img = string.format("unlock_%d", i)
                local icon_img = string.format("icon_%d", i)
                local name_text = string.format("name_text_%d", i)
                self[unlock_img]:SetVisibility(UE.ESlateVisibility.Hidden)
                self[icon_img]:SetVisibility(UE.ESlateVisibility.Hidden)
                self[name_text]:SetVisibility(UE.ESlateVisibility.Hidden)
                self[card_slot]:SetRenderOpacity(1)
                --show place card icon
                for _, card_in_place_info in pairs(card_info.card_in_place) do
                    if card_in_place_info.index + 1 == i then
                        local card_data = Database.Query('d_srpg_card_base', card_in_place_info.card_info.card_id)
                        local sprite_path = string.format('/Game/_Game/TP_New/Universe_CardShow/Frames/type_%d.type_%d',
                            card_data.type, card_data.type)
                        local sprite_object = UE.UObject.Load(sprite_path)
                        if sprite_object then
                            local icon_sprite = UE.UPaperSpriteBlueprintLibrary.MakeBrushFromSprite(sprite_object, 0, 0)
                            self[icon_img]:SetBrush(icon_sprite)
                        end 
                        local card_name = Database.L10n(card_data.nameId)
                        self[name_text]:SetText(card_name)
                        self[icon_img]:SetVisibility(UE.ESlateVisibility.Visible)
                        self[name_text]:SetVisibility(UE.ESlateVisibility.Visible)
                    end
                end
            else
                local unlock_img = string.format("unlock_%d", i)
                local icon_img = string.format("icon_%d", i)
                local name_text = string.format("name_text_%d", i)
                self[unlock_img]:SetVisibility(UE.ESlateVisibility.Visible)
                self[icon_img]:SetVisibility(UE.ESlateVisibility.Hidden)
                self[name_text]:SetVisibility(UE.ESlateVisibility.Hidden)
                self[card_slot]:SetRenderOpacity(0.5)
            end
        end
    else
        for i = 1, 4 do
            local card_slot = string.format("card_%d", i)
            self[card_slot]:SetVisibility(UE.ESlateVisibility.Hidden)
        end
    end
end

return M

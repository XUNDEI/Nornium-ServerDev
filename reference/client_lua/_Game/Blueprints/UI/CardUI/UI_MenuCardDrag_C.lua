--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type UI_MenuCardDrag_C
local M = UnLua.Class()

local Database = require "_Game.Utils.Database"

function M:Construct()
    if not M.FrameTextureRef then
        M.FrameTexture = {
            [1] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_1_png.card_rarity_1_png'),
            [2] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_1_png.card_rarity_1_png'),
            [3] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_2_png.card_rarity_2_png'),
            [4] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_2_png.card_rarity_2_png'),
            [5] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_3_png.card_rarity_3_png'),
            [6] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_3_png.card_rarity_3_png'),
            [7] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_4_png.card_rarity_4_png'),
        }
        M.FrameTextureRef = {
            UnLua.Ref(M.FrameTexture[1]),
            UnLua.Ref(M.FrameTexture[2]),
            UnLua.Ref(M.FrameTexture[3]),
            UnLua.Ref(M.FrameTexture[4]),
            UnLua.Ref(M.FrameTexture[5]),
            UnLua.Ref(M.FrameTexture[6]),
            UnLua.Ref(M.FrameTexture[7]),
        }
    end
    self.Overridden.Construct(self)
end

function M:InitCardUI(card_id)
    self.CardId = card_id
    local card_info = Database.Query("d_srpg_card_base", card_id)
    local name = Database.L10n(card_info.nameId)
    local describ = Database.L10n(card_info.effectsDescrId)
    local affix_id = {}
    local affix = ''
    for _, value in ipairs(card_info.keywords) do
        table.insert(affix_id, Database.Query("d_srpg_card_keyword", value).nameId)
    end
    if #affix_id > 0 then
        affix = '['
        for index, value in ipairs(affix_id) do
            affix = affix .. Database.L10n(value)
            if index < #affix_id then
                affix = affix .. '/'
            end
        end
        affix = affix .. ']'
    end
    for i = 1, #card_info.baseEffectvalue do
        describ = string.gsub(describ, "%%d", math.floor(card_info.baseEffectvalue[i]), 1)
    end
    self.Text_Name:SetText(name)
    self.Text_Describ:SetText(describ)
    self.Text_Affix:SetText(affix)

    self.Image_Bg_1:SetBrushFromAtlasInterface(M.FrameTexture[card_info.rarity])
    local content_path = "Texture2D'/Game/_Game/TP_New/SRPG_OverView/card_img/%s.%s'"
    content_path = string.format(content_path, card_info.img, card_info.img)
    local content_texture = UE.UObject.Load(content_path)
    if content_texture then
        self.Image_Content:SetBrushFromTexture(content_texture)
    end
end

function M:RefreshMapPlacePos()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:ShowPlaceCardPos(self.CardId)
end

function M:ClearCardPlaceEffect()
    local playerController = UE.UGameplayStatics.GetPlayerController(self, 0)
    playerController:ClearCardPosEffect()
end

return M

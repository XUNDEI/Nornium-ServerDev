local UIUtils = require "_Game.Utils.UIUtils"

---@type UI_MenuCardBtn_C
local M = UnLua.Class()

local Database = require "_Game.Utils.Database"

function M:Initialize()
    if not M.FrameTextureRef then
        M.FrameTexture = {
            [1] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_1_png.card_rarity_1_png'),
            [2] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_1_png.card_rarity_1_png'),
            [3] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_2_png.card_rarity_2_png'),
            [4] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_3_png.card_rarity_3_png'),
            [5] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_4_png.card_rarity_4_png'),
            [6] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_5_png.card_rarity_5_png'),
            [7] = UE.UObject.Load('/Game/_Game/TP_New/Universe_CardShow/Frames/card_rarity_5_png.card_rarity_5_png'),
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

        ---@type BP_GHSFunctionLibrary_C
        M.BP_GHSFunctionLibrary = LoadClass("/Game/_Game/Blueprints/Game/BP_GHSFunctionLibrary.BP_GHSFunctionLibrary_C")
        M.BP_GHSFunctionLibraryRef = UnLua.Ref(M.BP_GHSFunctionLibrary)
    end
end

function M:InitCardUI(card_info)
    self.CardId = card_info.card_id
    self.Index = card_info.index
    local upgrade_times = card_info.upgrade_times
    local cardConfig = Database.Query("d_srpg_card_base", self.CardId)
    if cardConfig then
        local name = Database.L10n(cardConfig.nameId)
        local desc = Database.L10n(cardConfig.effectsDescrId)
        local races = {}
        local raceString = ''
        for _, value in ipairs(cardConfig.race) do
            table.insert(races, Database.Query("d_srpg_card_race", value).nameId)
        end
        if #races > 0 then
            raceString = '['
            for index, value in ipairs(races) do
                raceString = raceString .. Database.L10n(value)
                if index < #races then
                    raceString = raceString .. '/'
                end
            end
            raceString = raceString .. ']'
        end
        self.Text_Name:SetText(name)
        local textColor = UE.FSlateColor()
        textColor.SpecifiedColor = M.BP_GHSFunctionLibrary.HexToColor(UIUtils.EItemRarityColor[cardConfig.rarity])
        self.Text_Name:SetColorAndOpacity(textColor)

        self.Text_Desc:SetText(desc)
        self.Text_Affix:SetText(raceString)

        self.Image_Bg:SetBrushFromAtlasInterface(M.FrameTexture[cardConfig.rarity])

        for i = 1, 6 do
            self["CardStar" .. i]:SetVisibility(i <= cardConfig.rarity and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
        end
    end
    local imagePath = "Texture2D'/Game/_Game/TP_New/SRPG_OverView/card_img/%s.%s'"
    imagePath = string.format(imagePath, cardConfig.img, cardConfig.img)
    local image = UE.UObject.Load(imagePath)
    if image then
        self.Image_Content:SetBrushFromTexture(image)
    end
end

function M:ShowUpgradeAnim()
    self.promotion:SetVisibility(UE.ESlateVisibility.Visible)
    self:PlayAnimation(self.CardLoop, 0.0, 10000, UE.EUMGSequencePlayMode.Forward, 1)
end

return M

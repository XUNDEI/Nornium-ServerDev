local UIUtils = require "_Game.Utils.UIUtils"

---@type UI_Curio_C
local M = UnLua.Class()

local Database = require "_Game.Utils.Database"

function M:InitCurioUI(curioId, index)
    self.CardId = curioId
    self.Index = index
    local cardConfig = Database.Query("d_srpg_curio_base", curioId)
    local name = Database.L10n(cardConfig.nameId)
    local desc = Database.L10n(cardConfig.effectsDescrId)
    local rarity = cardConfig.rarity
    self.name:SetText(name)

    local BP_GHSFunctionLibrary = LoadClass("/Game/_Game/Blueprints/Game/BP_GHSFunctionLibrary.BP_GHSFunctionLibrary_C")

    local textColor = UE.FSlateColor()
    textColor.SpecifiedColor = BP_GHSFunctionLibrary.HexToColor(UIUtils.EItemRarityColor[rarity])
    self.name:SetColorAndOpacity(textColor)

    self.desc:SetText(desc)
    local imagePath = "/Game/_Game/TP_New/SRPG_res/upgrade_icon/%s.%s"
    imagePath = string.format(imagePath, cardConfig.graph, cardConfig.graph)
    local image = UE.UObject.Load(imagePath)
    if image then
        self.image:SetBrushFromTexture(image)
    end
    local showedRarity = math.min(math.max(rarity - 1, 1), 5)
    local borderPath = "/Game/_Game/TP_New/Universe_CardShow/Frames/curio_rarity_%d_png.curio_rarity_%d_png"
    borderPath = string.format(borderPath, showedRarity, showedRarity)
    local border = UE.UObject.Load(borderPath)
    if border then
        self.border:SetBrushFromAtlasInterface(border)
    end
end

function M:SelectCard(selected)
    self.selected:SetVisibility(selected and UE.ESlateVisibility.Visible or UE.ESlateVisibility.Hidden)
end

return M

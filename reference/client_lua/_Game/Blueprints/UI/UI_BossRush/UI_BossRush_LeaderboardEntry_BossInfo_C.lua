local BossRushController = require("Module.BossRush.BossRushController")
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local UIUtils = require("_Game.Utils.UIUtils")
local Database = require("_Game.Utils.Database")

---@type UI_BossRush_LeaderboardEntry_BossInfo_C
local M = UnLua.Class()

function M:Construct()
    M.UI_BossRush_CharacterIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_CharacterIcon.UI_BossRush_CharacterIcon_C')
    M.UI_BossRush_CharacterIconRef = UnLua.Ref(M.UI_BossRush_CharacterIcon)
end

local BOSS_ICON_L_PATH = '/Game/_Game/TP_New/TotalWar_res/Frames/TotalWar_Level%d_L_png.TotalWar_Level%d_L_png'

---@param record TotalWarRankRecordInfo
function M:Setup(record)
    local bossId = record.boss_id
    local difficulty = BossRushUtils.GetScoreDifficulty(record.score)

    local bossConfig = BossRushUtils.GetBossConfig(bossId, difficulty)

    local iconPath = string.format(BOSS_ICON_L_PATH, difficulty, difficulty)
    local icon = LoadObject(iconPath)
    self.BossIcon:SetBrushFromAtlasInterface(icon)
    self.Name:SetText(Database.L10n(bossConfig.name))
    self.Score:SetText(BossRushUtils.FormatRichText(record.score))

    if record.character_infos then
        for _, characterInfo in ipairs(record.character_infos) do
            ---@type UI_BossRush_CharacterIcon_C
            local characterIcon = UE.UWidgetBlueprintLibrary.Create(self, M.UI_BossRush_CharacterIcon)

            self.Characters:AddChild(characterIcon)

            characterIcon.Icon:SetBrushFromAtlasInterface(LoadObject(UIUtils.GetCharacterIdolIcon(characterInfo.character_id)))

            local weaponId = characterInfo.weapon_info.item_id
            characterIcon.WeaponRarity:SetBrushFromAtlasInterface(UIUtils.GetItemRarityBorder(weaponId))
            characterIcon.WeaponIcon:SetBrushFromAtlasInterface(UIUtils.GetItemIcon(weaponId))
        end
    end
end

return M

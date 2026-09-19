local BossRushController = require("Module.BossRush.BossRushController")
local BossRushUtils = require "_Game.Blueprints.UI.UI_BossRush.BossRushUtils"
local UIUtils = require("_Game.Utils.UIUtils")
local Database = require("_Game.Utils.Database")

---@type UI_BossRush_LeaderboardEntry_SingleBoss_C
local M = UnLua.Class()

function M:Construct()
    M.UI_BossRush_CharacterIcon = LoadClass('/Game/_Game/Blueprints/UI/UI_BossRush/UI_BossRush_CharacterIcon.UI_BossRush_CharacterIcon_C')
    M.UI_BossRush_CharacterIconRef = UnLua.Ref(M.UI_BossRush_CharacterIcon)
end

---@param data LeaderboardEntryData_C
function M:OnListItemObjectSet(data)
    local entry = BossRushController:GetInstance():GetBossLeaderboard(data.BossId)[data.Rank]
    local recordId = entry.record_id
    local record = BossRushController:GetInstance():GetRecord(recordId)

    self.Name:SetText(record.player_name)
    self.UID:SetText(record.player_id)
    self.Score:SetText(BossRushUtils.FormatRichText(record.score))
    self.Rank:SetText(string.format(Database.L10n(450), data.Rank))

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

local Database = require("_Game.Utils.Database")
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SetSystem_Handle_Entry_C
local M = UnLua.Class()

function M:Construct()
    self.platform = InputUtils.Platform.Xbox

    local keyAsset = InputUtils.GetKeyAsset(self.Key, self.platform)

    self.L:SetBrushFromAtlasInterface(keyAsset)
    self.R:SetBrushFromAtlasInterface(keyAsset)

    if self.Left then
        self.L:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.SpacerR:SetVisibility(UE.ESlateVisibility.Collapsed)
    else
        self.R:SetVisibility(UE.ESlateVisibility.Collapsed)
        self.SpacerL:SetVisibility(UE.ESlateVisibility.Collapsed)
    end
end

function M:Update(title)
    local bound = false
    ---@param entry UInputMappingContext
    for _, entry in pairs(InputAssets) do
        if UE.UGameplayStatics.ObjectIsA(entry, UE.UInputMappingContext) then
            if InputUtils.MappingContextType[entry] == title then
                local Mappings = entry.Mappings
            
                ---@param Mapping FEnhancedActionKeyMapping
                for _, Mapping in pairs(Mappings) do
                    if Mapping.SettingBehavior ~= UE.EPlayerMappableKeySettingBehaviors.OverrideSettings then
                        break
                    end

                    local name = Mapping.PlayerMappableKeySettings.Name
                    local playerMapping = InputUtils.GetMapping(self, name)
                    
                    if playerMapping.CurrentKey == self.Key then
                        self.Name:SetText(Database.L10n(tonumber(playerMapping.DisplayName)))
                        bound = true
                    end
                end
            end
        end
    end

    if not bound then
        self.Name:SetText("-")
    end
end

return M

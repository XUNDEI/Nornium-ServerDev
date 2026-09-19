

local Database = require "_Game.Utils.Database"
local d_levels = require "ClientDatas.d_levels"
local UIUtils = require "_Game.Utils.UIUtils"
local BackpackSystem = require "Module.Backpack.BackpackSystem"

---@type UI_SystemEntry_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self:InitData()
    self:InitUI()
    self:RefreshUI()
    
end

function M:Destruct()
   
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitData()
end

function M:InitUI()
   
    -- local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    -- local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    -- local isOpenCharAndTeam = saveGameSpeak.StoryFinished or (saveGameSpeak.PlotIndex > 3 or (saveGameSpeak.PlotIndex == 3))
    --文字颜色
    -- local textColor = UE.FSlateColor()
    -- textColor.SpecifiedColor = isOpenCharAndTeam and UE.FLinearColor(0.921569, 0.941177, 1.0, 0.6) or UE.FLinearColor(0.552941, 0.560784, 0.603922, 0.301961)
    -- self.TextBlock_Team:SetColorAndOpacity(textColor)
    -- self.TextBlock_Char:SetColorAndOpacity(textColor)
    --锁的图片
    self.Image_Team_Lock:SetVisibility(UE.ESlateVisibility.Hidden)
    self.Image_Char_Lock:SetVisibility(UE.ESlateVisibility.Hidden)
end

function M:RefreshUI()
   
end




return M
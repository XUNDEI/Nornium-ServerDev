--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"

---@type UI_Loading2_C
local UI_Loading2_C = Class()

local BGPath = {
    [1] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading1.Loading1'",
    [2] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading2.Loading2'",
    [3] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading3.Loading3'",
    [4] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading4.Loading4'",
    [5] = "Texture2D'/Game/_Game/TP_New/Loading/BG/Loading5.Loading5'",
}

--构造函数
function UI_Loading2_C:Construct()
    self.Overridden.Construct(self)
    print('-------UI_Loading2_C')
    self:InitUI()
end

-- function UI_Loading2_C:Destruct()
--     self:CancelDelayDestroy()
--     self.Overridden.Destruct(self)
-- end

function UI_Loading2_C:InitUI()
    -- local i = math.random(1, 5)
    -- if BGPath[i] and BGPath[i] ~= '' then
    --     local iconTexture = LoadObject(BGPath[i])
    --     LOG_DEBUG('iconTexture:', iconTexture)
    --     if iconTexture then
    --         self.Img_Bg:SetBrushFromTexture(iconTexture, true)
    --         self.Img_Bg:SetBrushTintColor(UE.FSlateColor())
    --         --self.Img_Bg:SetBrushFromAtlasInterface(iconTexture)
    --     end
    -- end
end

function UI_Loading2_C:RefreshUI(curCount, AllCount)
    print('----cur:' .. tostring(curCount) .. ",all:" .. tostring(AllCount))
    self.TextBlock_Rate:SetText(string.format("%0.2f%%", (math.min(curCount / AllCount, 1)) * 100))
end

function UI_Loading2_C:DelayDestroy(bWeak)
    LOG_DEBUG_TRACKBACK('------->DelayDestroy')
    -- 取消后不再接受新的Delay
    if self.cancel_delay_destroy and bWeak then 
        return 
    end
    if self.DelayDestroyHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.DelayDestroyHandle)
        self.DelayDestroyHandle = nil
    end
    self.DelayDestroyHandle = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
        { self, self.OnDelayDestroy },
        2,
        false
    )
end

function UI_Loading2_C:CancelDelayDestroy()
    LOG_DEBUG_TRACKBACK('------->CancelDelayDestroy')
    self.cancel_delay_destroy = true
    if self.DelayDestroyHandle then
        UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.DelayDestroyHandle)
        self.DelayDestroyHandle = nil
    end
end

function UI_Loading2_C:OnDelayDestroy()
    if not UE.UKismetSystemLibrary.IsValid(self) then return end
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    gameInstance:RemoveUMG("UI_Loading2")
end

return UI_Loading2_C

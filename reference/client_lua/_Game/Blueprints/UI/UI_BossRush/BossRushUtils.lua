local d_bossrush_points = require("ClientDatas.d_bossrush_points")
local d_bossrush_level = require("ClientDatas.d_bossrush_level")

local M = {}

local NUMBER = '<img id="TotalWar_%s"/>'
local COMMA = '<img id="TotalWar_Point"/>'

function M.FormatRichText(number)
    local s = tostring(number)
    local richText = ""

    -- 别问 问就是犯病不搓字体
    for i = 1, string.len(s) do
        richText = richText .. string.format(NUMBER, string.sub(s, i, i))

        if i > 1 and i < string.len(s) and (string.len(s) - i) % 3 == 0 then
            richText = richText .. COMMA
        end
    end

    return richText
end

function M.GetScoreDifficulty(score)
    if not score then
        return 0
    end
    for i, record in ipairs(d_bossrush_points) do
        if score <= record.ptBase + record.ptDamage + record.ptTime then
            return i, score > record.ptBase + record.ptDamage
        end
    end
end

function M.GetBossConfig(bossId, difficulty)
    for _, level in ipairs(d_bossrush_level) do
        if level.bossID == bossId and level.difficult == difficulty then
            return level
        end
    end
end

M.RANK_MAX = 1000
M.RANK_STEP = 100

function M.GetRealRank(index)
    if index <= M.RANK_MAX then
        return index
    else
        return M.RANK_MAX + (index - M.RANK_MAX) * M.RANK_STEP
    end
end

return M

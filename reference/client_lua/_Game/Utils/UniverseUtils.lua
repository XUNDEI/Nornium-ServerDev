local hex_grid = require "Helper.hex_grid"

local UniverseUtils = {}

---@param mainPosInfo MainPosInfo
function UniverseUtils.IsVisible(mainPosInfo)
    return mainPosInfo.state > 0
end

---@param mainPosInfo MainPosInfo
function UniverseUtils.IsReachable(mainPosInfo)
    return mainPosInfo.state > 1
end

---@param mainPosInfo MainPosInfo
function UniverseUtils.IsExplored(mainPosInfo)
    return mainPosInfo.state > 2
end

function UniverseUtils.LineEqual(lineA, lineB)
    return (hex_grid.equal(lineA[1], lineB[1]) and hex_grid.equal(lineA[2], lineB[2])) or (hex_grid.equal(lineA[1], lineB[2]) and hex_grid.equal(lineA[2], lineB[1]))
end

function UniverseUtils.LineSameDirection(lineA, lineB)
    return (hex_grid.equal(lineA[1], lineB[1]) and hex_grid.equal(lineA[2], lineB[2]))
end

return UniverseUtils

local M = {}

local function Hex(q, r)
    return {
        q = q,
        r = r
    }
end

local function Cube(x, y, z)
    return {
        x = x,
        y = y,
        z = z
    }
end

local function Point(x, y)
    return {
        x = x,
        y = y
    }
end

local function cube_to_hex(h)
    return Hex(h.x, h.z)
end

local function hex_to_cube(h)
    return Cube(h.q, -h.q-h.r, h.r)
end

-- y x
--  z
--  3 2
-- 4   1
--  5 6
local directions = {
    Cube(1, -1, 0), Cube(1, 0, -1), Cube(0, 1, -1),
    Cube(-1, 1, 0), Cube(-1, 0, 1), Cube(0, -1, 1)
}

local function cube_direction(direction)
    return directions[direction]
end

local function cube_add(a, b)
    return Cube(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function cube_sub(a, b)
    return Cube(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function cube_neighbor(cube, direction)
    if direction == 0 then
        return Cube(cube.x, cube.y, cube.z)
    end
    return cube_add(cube, cube_direction(direction))
end

--    2
-- 3 o o 1
--  o   o
-- 4 o o 6
--    5
local diagonals = {
   Cube(2, -1, -1), Cube(1, 1, -2), Cube(-1, 2, -1),
   Cube(-2, 1, 1), Cube(-1, -1, 2), Cube(1, -2, 1)
}

local function cube_diagonal_neighbor(cube, direction)
    if direction == 0 then
        return Cube(cube.x, cube.y, cube.z)
    end
    return cube_add(cube, diagonals[direction])
end

local abs = math.abs
local function cube_distance(a, b)
    return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2
end

local function hex_distance(a, b)
    return (abs(a.q - b.q) + abs((-a.q - a.r) - (-b.q - b.r)) + abs(a.r - b.r)) / 2
end

local function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(math.floor(num * mult + 0.5) / mult)
end

local function cube_round(cube)
    local rx = round(cube.x)
    local ry = round(cube.y)
    local rz = round(cube.z)

    local x_diff = abs(rx - cube.x)
    local y_diff = abs(ry - cube.y)
    local z_diff = abs(rz - cube.z)

    if x_diff > y_diff and x_diff > z_diff then
        rx = -ry-rz
    elseif y_diff > z_diff then
        ry = -rx-rz
    else
        rz = -rx-ry
    end

    return Cube(rx, ry, rz)
end

local function hex_round(h)
    return cube_to_hex(cube_round(hex_to_cube(h)))
end

local sqrt = math.sqrt
local sqrt3 = sqrt(3)
local function hex_to_pixel(hex, size)
    local x = size * sqrt3 * (hex.q + hex.r/2)
    local y = size * 3/2 * hex.r
    return Point(x, y)
end

local function pixel_to_hex(p, size)
    local q = (p.x * sqrt3/3 - p.y / 3) / size
    local r = p.y * 2/3 / size
    return hex_round(Hex(q, r))
end

local function cube_lerp(a, b, t)
    return Cube(a.x + (b.x - a.x) * t,
                a.y + (b.y - a.y) * t,
                a.z + (b.z - a.z) * t)
end

local function cube_linedraw(a, b)
    local N = cube_distance(a, b)
    local results = {}
    for i = 0, N do
        table.insert(results, cube_round(cube_lerp(a, b, 1.0/N * i)))
    end
    return results
end

--      2
--       +    1
-- 3  + o o +
--     o   o
--    + o o +
--       +
local diagonals2 = {
    Cube(3, -1, -2), Cube(1, 2, -3), Cube(-2, 3, -1),
    Cube(-3, 1, 2), Cube(-1, -2, 3), Cube(2, -3, 1)
}

local function cube_diagonal2_neighbor(cube, direction)
    if direction == 0 then
        return Cube(cube.x, cube.y, cube.z)
    end
    return cube_add(cube, diagonals2[direction])
end

---@param hex Hex
---@return string
local function to_string(hex)
    return string.format("%d,%d", hex.q, hex.r)
end

---@param str string
---@return Hex
local function from_string(str)
    local hex = string.split(str, ",")
    if #hex == 2 then
        return {
            q = tonumber(hex[1]),
            r = tonumber(hex[2]),
        }
    else
        return { q = 0, r = 0 }
    end
end

---@param hexA Hex
---@param hexB Hex
local function equal(hexA, hexB)
    return hexA.q == hexB.q and hexA.r == hexB.r
end

local function hex_add(hex, offset)
    return Hex(hex.q + offset.q, hex.r + offset.r)
end

M.Hex = Hex
M.Cube = Cube
M.Point = Point
M.cube_to_hex = cube_to_hex
M.hex_to_cube = hex_to_cube
M.hex_to_pixel = hex_to_pixel
M.pixel_to_hex = pixel_to_hex
M.cube_add = cube_add
M.cube_sub = cube_sub
M.cube_neighbor = cube_neighbor
M.cube_diagonal_neighbor = cube_diagonal_neighbor
M.cube_diagonal2_neighbor = cube_diagonal2_neighbor
M.cube_distance = cube_distance
M.hex_distance = hex_distance
M.to_string = to_string
M.from_string = from_string
M.equal = equal
M.hex_add = hex_add

return M

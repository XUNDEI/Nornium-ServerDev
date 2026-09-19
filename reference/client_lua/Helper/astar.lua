-- ======================================================================
-- Copyright (c) 2012 RapidFire Studio Limited
-- All Rights Reserved.
-- http://www.rapidfirestudio.com

-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:

-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ======================================================================

-- module ( "astar", package.seeall )
local M = {}

----------------------------------------------------------------
-- local variables
----------------------------------------------------------------

local INF = 1 / 0
local cachedPaths = nil

----------------------------------------------------------------
-- local functions
----------------------------------------------------------------

function M.dist(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
end

function M.dist_between(nodeA, nodeB)
    return M.dist(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
end

function M.heuristic_cost_estimate(nodeA, nodeB)
    return M.dist(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
end

function M.is_valid_node(node, neighbor)
    return true
end

function M.lowest_f_score(set, f_score)
    local lowest, bestNode = INF, nil
    for _, node in ipairs(set) do
        local score = f_score[node]
        if score < lowest then
            lowest, bestNode = score, node
        end
    end
    return bestNode
end

function M.neighbor_nodes(theNode, nodes)
    local neighbors = {}
    for _, node in ipairs(nodes) do
        if theNode ~= node and M.is_valid_node(theNode, node) then
            table.insert(neighbors, node)
        end
    end
    return neighbors
end

function M.not_in(set, theNode)
    for _, node in ipairs(set) do
        if node == theNode then return false end
    end
    return true
end

function M.remove_node(set, theNode)
    for i, node in ipairs(set) do
        if node == theNode then
            set[i] = set[#set]
            set[#set] = nil
            break
        end
    end
end

function M.unwind_path(flat_path, map, current_node)
    if map[current_node] then
        table.insert(flat_path, 1, map[current_node])
        return M.unwind_path(flat_path, map, map[current_node])
    else
        return flat_path
    end
end

----------------------------------------------------------------
-- pathfinding functions
----------------------------------------------------------------

function M.a_star(start, goal, nodes, valid_node_func, dist_between_func, heuristic_cost_estimate_func)
    local closedset = {}
    local openset = { start }
    local came_from = {}

    if valid_node_func then M.is_valid_node = valid_node_func end
    if dist_between_func then M.dist_between = dist_between_func end
    if heuristic_cost_estimate_func then M.heuristic_cost_estimate = heuristic_cost_estimate_func end

    local g_score, f_score = {}, {}
    g_score[start] = 0
    f_score[start] = g_score[start] + heuristic_cost_estimate_func(start, goal)

    while #openset > 0 do
        local current = M.lowest_f_score(openset, f_score)
        if current == goal then
            local path = M.unwind_path({}, came_from, goal)
            table.insert(path, goal)
            return path
        end

        M.remove_node(openset, current)
        table.insert(closedset, current)

        local neighbors = M.neighbor_nodes(current, nodes)
        for _, neighbor in ipairs(neighbors) do
            if M.not_in(closedset, neighbor) then
                local tentative_g_score = g_score[current] + M.dist_between(current, neighbor)

                if M.not_in(openset, neighbor) or tentative_g_score < g_score[neighbor] then
                    came_from[neighbor] = current
                    g_score[neighbor] = tentative_g_score
                    f_score[neighbor] = g_score[neighbor] + heuristic_cost_estimate_func(neighbor, goal)
                    if M.not_in(openset, neighbor) then
                        table.insert(openset, neighbor)
                    end
                end
            end
        end
    end
    return nil -- no valid path
end

----------------------------------------------------------------
-- exposed functions
----------------------------------------------------------------

function M.clear_cached_paths()
    cachedPaths = nil
end

function M.distance(x1, y1, x2, y2)
    return M.dist(x1, y1, x2, y2)
end

function M.path(start, goal, nodes, ignore_cache, valid_node_func, dist_between_func, heuristic_cost_estimate_func)
    if not cachedPaths then cachedPaths = {} end
    if not cachedPaths[start] then
        cachedPaths[start] = {}
    elseif cachedPaths[start][goal] and not ignore_cache then
        return cachedPaths[start][goal]
    end

    local resPath = M.a_star(start, goal, nodes, valid_node_func, dist_between_func, heuristic_cost_estimate_func)
    if not cachedPaths[start][goal] and not ignore_cache then
        cachedPaths[start][goal] = resPath
    end

    return resPath
end

return M

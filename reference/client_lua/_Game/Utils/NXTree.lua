local NXTree = {}

function NXTree:New(id, parent, depth, show)
    self = {}
    self.id = id
    self.x = 0
    self.y = depth
    self.mod = 0             --根据左兄弟定位的x与根据子节点中间定位的x之差
    self.extend = 0          --如果有非主线节点连接进行延申
    self.parent = parent
    self.show = show
    if not self.parent then
    end
    self.children = {}
    self.lmost_sibling = nil --最左侧的兄弟节点
    return self
end

function NXTree:GetLmostSibling(node)
    if not node.lmost_sibling and node.parent and node ~= node.parent.children[1] then
        node.lmost_sibling = node.parent.children[1]
    end
    return node.lmost_sibling
end

function NXTree:GetLeftBrother(node)
    local brother = nil
    if node.parent then
        for _, child in ipairs(node.parent.children) do
            if child == node then
                return brother
            else
                brother = child
            end
        end
    end
    return brother
end

function NXTree:FirstWalk(node, distance)
    if #node.children == 0 then
        if NXTree:GetLmostSibling(node) then
            --当前节点是叶子节点且存在左兄弟节点，则其x坐标等于其左兄弟的x坐标加上间距distance
            local brother = NXTree:GetLeftBrother(node)
            node.x = brother.x + distance
        else
            --当前节点是叶节点无左兄弟，那么x坐标为0
            node.x = 0
        end
    else
        --后序遍历，先递归子节点
        for _, child in ipairs(node.children) do
            self:FirstWalk(child, distance)
        end
        --子节点的中点
        local midPoint = (node.children[1].x + node.children[#node.children].x) / 2
        --左兄弟
        local w = NXTree:GetLeftBrother(node)
        if w then
            --有左兄弟节点，x坐标设为其左兄弟的x坐标加上间距distance
            node.x = w.x + distance
            --同时记录下偏移量（x坐标与子节点的中点之差）
            node.mod = node.x - midPoint
        else
            --没有左兄弟节点，x坐标直接是子节点的中点
            node.x = midPoint
        end
    end
    return node
end

function NXTree:SecondWalk(node, mod, depth)
    --初始x值加上所有祖宗节点的mod值（不包括自身的mod）
    node.x = node.x + mod
    node.y = depth
    mod = node.mod + mod
    for _, child in ipairs(node.children) do
        self:SecondWalk(child, mod, depth + 1)
    end
end

return NXTree

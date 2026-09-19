--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local NXTree = require("_Game.Utils.NXTree")
local Database = require "_Game.Utils.Database"
local d_story_node = require("ClientDatas.d_story_node")
local PlotSystem = require "Module.Plot.PlotSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_SelectNode_C
local M = UnLua.Class()

M.InputMappingContexts = {
    InputAssets.IMC_UI_Common,
    InputAssets.IMC_UI_StoryCursor,
    InputAssets.IMC_UI_MoveUp,
    InputAssets.IMC_UI_MoveDown,
    InputAssets.IMC_UI_MoveRight,
    InputAssets.IMC_UI_MoveLeft,
    InputAssets.IMC_UI_ZoomIn,
}

function M:IA_MoveUp()
    self.UI_StoryNodeTree:MoveUpClickNode()
end

function M:IA_MoveDown()
    self.UI_StoryNodeTree:MoveDownClickNode()
end

function M:IA_MoveRight()
    self.UI_StoryNodeTree:MoveRightClickNode()
end

function M:IA_MoveLeft()
    self.UI_StoryNodeTree:MoveLeftClickNode()
end

function M:IA_ZoomIn(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    local input = ActionValue:GetAxis2D()
    print('=====IA_ZoomIn X ' .. input.X .. ' Y ' .. input.Y)
    --self.UI_StoryNodeTree:MoveLeftClickNode()
    if input.X > 0 then
        self.UI_StoryNodeTree:OnZoomIn()
    else
        self.UI_StoryNodeTree:OnZoomOut()
    end
end

function M:IA_Back()
    self.UI_StoryNodeTree.ClickFromGamePad = false
    if self.UI_StoryNodeTree.SelectedIndex then
        self.UI_StoryNodeTree:OnClickedNode(self.UI_StoryNodeTree.SelectedIndex)
    else
        UIManager:GetInstance():RemoveUI(self)
    end
end

function M:IA_SimulateClick_Started(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    self.UI_StoryNodeTree.ClickFromGamePad = true
    UE.UGHSFunctionLibrary.SimulateLeftMouseButton(true)
end

function M:IA_SimulateClick_Completed(ActionValue, ElapsedSeconds, TriggeredSeconds, InputAction)
    self.UI_StoryNodeTree.ClickFromGamePad = true
    UE.UGHSFunctionLibrary.SimulateLeftMouseButton(false)
end

function M:IA_Click_Started()
    self.UI_StoryNodeTree.ClickFromGamePad = false
end

function M:IA_Click_Triggered()
    self.UI_StoryNodeTree.ClickFromGamePad = false
end

function M:IA_Click_Completed()
    self.UI_StoryNodeTree.ClickFromGamePad = false
end

InputUtils.RegisterUIAction(M, InputAssets.IA_Back, UE.ETriggerEvent.Completed, M.IA_Back)
InputUtils.RegisterUIAction(M, InputAssets.IA_MoveUp, UE.ETriggerEvent.Completed, M.IA_MoveUp)
InputUtils.RegisterUIAction(M, InputAssets.IA_MoveDown, UE.ETriggerEvent.Completed, M.IA_MoveDown)
InputUtils.RegisterUIAction(M, InputAssets.IA_MoveRight, UE.ETriggerEvent.Completed, M.IA_MoveRight)
InputUtils.RegisterUIAction(M, InputAssets.IA_MoveLeft, UE.ETriggerEvent.Completed, M.IA_MoveLeft)
InputUtils.RegisterUIAction(M, InputAssets.IA_ZoomIn, UE.ETriggerEvent.Triggered, M.IA_ZoomIn)
InputUtils.RegisterUIAction(M, InputAssets.IA_StorySimulateClick, UE.ETriggerEvent.Started, M.IA_SimulateClick_Started)
InputUtils.RegisterUIAction(M, InputAssets.IA_StorySimulateClick, UE.ETriggerEvent.Completed, M.IA_SimulateClick_Completed)
InputUtils.RegisterUIAction(M, InputAssets.IA_StoryClick, UE.ETriggerEvent.Started, M.IA_Click_Started)
InputUtils.RegisterUIAction(M, InputAssets.IA_StoryClick, UE.ETriggerEvent.Triggered, M.IA_Click_Triggered)
InputUtils.RegisterUIAction(M, InputAssets.IA_StoryClick, UE.ETriggerEvent.Completed, M.IA_Click_Completed)
InputUtils.RegisterMouseEvent(M)

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

-- function M:Construct()
-- end

function M:RefreshUI(tree_id)
    self:InitData(tree_id)
    self:InitUI()
end

--function M:Tick(MyGeometry, InDeltaTime)
--end

function M:InitData(storyTree_id)
    self.story_id = storyTree_id
    self.nodes_data = {}
    self.nodes_map = {}
    local cur_node_id = storyTree_id
    local last_node_id = nil
    local node_height = 1
    local node_width = 0
    --连线位置
    self.lines_data = {}
    --先生成主干node
    self.nodes_data = self:GetMainNodes(storyTree_id)

    last_node_id = nil
    node_height = 1
    node_width = 0
    local distance = 1
    local branch_nodes = {}  --记录主节点index对应的分支树信息
    local repeat_nodes = {}  --记录同名节点
    local main_node_count = #self.nodes_data
    --节点位置
    for cur_node_index = main_node_count, 1, -1 do
        --while cur_node_id and d_story_node[cur_node_id] do
        cur_node_id = self.nodes_data[cur_node_index].id
        local son_ids = d_story_node[cur_node_id].sonid
        local hasBranch = false
        if #son_ids > 1 then
            --找到分支树
            last_node_id = cur_node_id
            hasBranch = true
        end

        if hasBranch then
            local linked_node = {}
            local branchRoot = NXTree:New(cur_node_id, nil, 1, true)
            table.insert(linked_node, { id = cur_node_id, node = branchRoot })
            local length = #linked_node
            local depth = 0
            distance = distance * -1
            --生成多叉树
            while length > 0 do
                depth = depth + 1
                for i = 1, length do
                    local id = linked_node[i].id
                    local node = linked_node[i].node
                    local start_index = 1
                    local end_index = #d_story_node[id].sonid
                    if id == cur_node_id and d_story_node[id] then --主干node的第一个子节点不用生成 已经在生成主干node时生成
                        start_index = 2
                    elseif d_story_node[id] and #d_story_node[id].sonid > 0 then --分支的分支或子节点
                        start_index = 1
                    end
                    for i = start_index, end_index do
                        local son_id = d_story_node[id].sonid[i]
                        local root_index = self:GetExistedNodes(son_id)
                        if not self.lines_data[node.id] then
                            self.lines_data[node.id] = {}
                        end
                        if root_index then
                            --生成同名分支再合并 并且不继续查找子节点
                            local childTree = NXTree:New(son_id, node, depth, false)
                            table.insert(node.children, childTree)
                            if not repeat_nodes[son_id] then 
                                repeat_nodes[son_id] = {} 
                                repeat_nodes[son_id].repeat_index = root_index     --同名主节点的index
                                repeat_nodes[son_id].branch_root_id = cur_node_id  --当前分支的主节点root id
                            end
                            table.insert(repeat_nodes[son_id], childTree)
                            --连到重名分支节点的连线特殊处理
                            table.insert(self.lines_data[node.id], { id = son_id, branch_to_main = true })
                        else
                            if son_id ~= id then--防止死循环 相等就是配置有问题
                                local childTree = NXTree:New(son_id, node, depth, true)
                                table.insert(linked_node, { id = son_id, node = childTree })
                                table.insert(node.children, childTree)
                                table.insert(self.lines_data[node.id], { id = son_id, branch_to_main = false })
                            end
                        end
                    end
                end
                for i = length, 1, -1 do
                    table.remove(linked_node, i)
                end
                length = #linked_node
            end

            --获得绘制坐标
            NXTree:FirstWalk(branchRoot, distance)
            NXTree:SecondWalk(branchRoot, 0, 0)

            --遍历绘制坐标
            linked_node = {}
            table.insert(linked_node, branchRoot)
            length = #linked_node
            while length > 0 do
                for i = 1, length do
                    for _, child in ipairs(linked_node[i].children) do
                        if not repeat_nodes[child.id] then
                            table.insert(linked_node, child)
                            local child_height = child.y
                            local child_width = child.x + distance
                            if not branch_nodes[cur_node_index] then branch_nodes[cur_node_index] = {} end
                            table.insert(branch_nodes[cur_node_index], { id = child.id, height = child_height, width = child_width, main = false })
                        end
                    end
                end
                for i = length, 1, -1 do
                    table.remove(linked_node, i)
                end
                length = #linked_node
            end
        end
    end

    for index = #self.nodes_data, 1, -1 do
        if repeat_nodes[self.nodes_data[index].id] then
            --根据重复节点位置修正主节点里的同名节点位置
            local first_node = self.nodes_data[index]
            local mod = 0 --偏移量
            for _, repeat_node in ipairs(repeat_nodes[first_node.id]) do
                local branch_root_index = self:GetExistedNodes(repeat_nodes[first_node.id].branch_root_id)
                local y = self.nodes_data[branch_root_index].height + repeat_node.y
                if y - first_node.height > mod then
                    mod = y - first_node.height
                end
            end

            if mod > 0 then
                for i = index, #self.nodes_data do
                    self.nodes_data[i].height = self.nodes_data[i].height + mod
                end
            end
        end
    end

    for branch_root_index, nodes in pairs(branch_nodes) do
        for _, node in ipairs(nodes) do
            --加上主干节点的位置偏移
            node.height = self.nodes_data[branch_root_index].height + node.height
            node.width = self.nodes_data[branch_root_index].width + node.width
            table.insert(self.nodes_data, node)
        end
    end
end

function M:GetExistedNodes(node_id)
    for index, node_data in ipairs(self.nodes_data) do
        if node_id == node_data.id then
            return index
        end
    end
    return nil
end


function M:GetMainNodes(start_node_id)
    local node_data = {}
    local cur_node_id = start_node_id
    local last_node_id = nil
    local node_height = 1
    local node_width = 0
    --插入所有主干node
    while cur_node_id and d_story_node[cur_node_id] do
        local childNode_ids = d_story_node[cur_node_id].sonid
        local find_main_node = false
        if last_node_id then
            for _, value in ipairs(node_data) do
                if value.id == last_node_id then
                    node_height = value.height + 1
                    break
                end
            end
        end
        table.insert(node_data, { id = cur_node_id, height = node_height, width = node_width, parent_id = last_node_id, main = true })


        if #childNode_ids > 0 then
            --生成连线
            if not self.lines_data[cur_node_id] then
                self.lines_data[cur_node_id] = {}
            end
            table.insert(self.lines_data[cur_node_id], { id = childNode_ids[1], branch_to_main = false })
            --sonid里第一个为主干node
            find_main_node = true
            last_node_id = cur_node_id
            if cur_node_id == childNode_ids[1] then--防止死循环 相等就是配置有问题
                cur_node_id = nil
            else
                cur_node_id = childNode_ids[1]
            end
        end

        if not find_main_node then
            cur_node_id = nil
        end
    end
    return node_data
end

function M:InitUI()
    self.UI_StoryNodeTree.OnItemInitialized:Add(self, function(wbp, widget, index)
        self:OnItemInitialized(widget, index)
    end)

    self.Exit.OnClicked:Add(self, self.OnClicked_Exit)
    self.UI_StoryNodeTree:BP_SetListItems(self.nodes_data, self.lines_data)
    self.IsBadEnd = false
    local selectNodePanel = UE.UGameplayStatics.GetGameInstance(self):GetUMG('UI_SelectTree')
    self.IsBadEnd = selectNodePanel.IsBadEnd
    if self.IsBadEnd then
        self.BEText:SetVisibility(UE.ESlateVisibility.Visible)
    end
end

function M:OnItemInitialized(widget, index)
    local node_data = self.nodes_data[index]
    local config = d_story_node[node_data.id]
    widget.Text_NameLock:SetText(Database.L10n(config.name))
    widget.Text_NameUnLock:SetText(Database.L10n(config.name))
    widget.Text_NameComplete:SetText(Database.L10n(config.name))
    local plot_info = PlotSystem:GetInstance().PlotInfo
    if plot_info.plot_tree_id == self.story_id and plot_info.plot_node_id == node_data.id then
        widget.StoryNowPanel:SetVisibility(UE.ESlateVisibility.Visible)
    else
        widget.StoryNowPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    end

    if plot_info.story_node_infos[self.story_id][node_data.id].unlocked and plot_info.story_node_infos[self.story_id][node_data.id].completed then
        widget.Lock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.Complete:SetVisibility(UE.ESlateVisibility.Visible)
    elseif plot_info.story_node_infos[self.story_id][node_data.id].unlocked then
        widget.Lock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.UnLock:SetVisibility(UE.ESlateVisibility.Visible)
        widget.Complete:SetVisibility(UE.ESlateVisibility.Hidden)
    else
        widget.Lock:SetVisibility(UE.ESlateVisibility.Visible)
        widget.UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
        widget.Complete:SetVisibility(UE.ESlateVisibility.Hidden)
    end
end

function M:OnClicked_Exit()
    UIManager:GetInstance():RemoveUI(self)
end

return M

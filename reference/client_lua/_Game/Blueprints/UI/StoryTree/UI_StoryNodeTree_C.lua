--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

local Client = require "Network.Client"
local Database = require "_Game.Utils.Database"
local PlotSystem = require "Module.Plot.PlotSystem"
local InputAssets = require "_Game.Utils.Input.InputAssets"
local InputUtils = require "_Game.Utils.Input.InputUtils"

---@type UI_StoryNodeTree_C
local M = UnLua.Class()

--function M:Initialize(Initializer)
--end

--function M:PreConstruct(IsDesignTime)
--end

function M:Construct()
    self.IntervalTime = 0.15
    MessageManager:GetInstance():AddListener("Play_Plot", self)
end

function M:Destruct()
    MessageManager:GetInstance():RemoveListener("Play_Plot", self)
end

function M:Tick(MyGeometry, InDeltaTime)
    if self.bUserScroll then
        local translation = self.ContentPanel.RenderTransform.Translation
        local interpX = UE.UKismetMathLibrary.FInterpTo(translation.X, self.OffsetX, InDeltaTime, self.InterpSpeed)
        local interpY = UE.UKismetMathLibrary.FInterpTo(translation.Y, self.OffsetY, InDeltaTime, self.InterpSpeed)
        -- print("-----x:" .. tostring(interpX) .. ",y:" .. tostring(interpY))
        local temp_offsetX = UE.UKismetMathLibrary.Abs(interpX / (self.ItemWidth + self.ItemOffset) / self.ZoomFactor)
        local temp_offsetY = UE.UKismetMathLibrary.Abs(interpX / (self.ItemHeight + self.ItemOffset) / self.ZoomFactor)
        self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, self.OffsetY))
        -- if not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(translation.X, self.OffsetX, 0.001) or
        --     not UE.UKismetMathLibrary.NearlyEqual_FloatFloat(translation.Y, self.OffsetY, 0.001) then

        --     -- print("-----temp_offsetX:" .. tostring(UE.UKismetMathLibrary.Fraction(temp_offsetX)))
        --     if UE.UKismetMathLibrary.Fraction(temp_offsetX) < 0.5 then
        --         local floor = UE.UKismetMathLibrary.FFloor(temp_offsetX)
        --         self.NewIndex = UE.UKismetMathLibrary.Clamp(floor, 0, self.ItemDataSourceCount - 1)
        --         -- print("-----NewIndex:" .. tostring(self.NewIndex))
        --     else
        --         local ceil = UE.UKismetMathLibrary.FCeil(temp_offsetX)
        --         self.NewIndex = UE.UKismetMathLibrary.Clamp(ceil, 0, self.ItemDataSourceCount - 1)
        --         -- print("-----NewIndex2:" .. tostring(self.NewIndex))
        --     end

        --     if self.NewIndex ~= self.LastIndex then
        --         self:OnScrollSelected(self.NewIndex, self.LastIndex)
        --         self.LastIndex = self.NewIndex
        --     end
        -- else
        --     self.OffsetX = (self.ItemWidth + self.ItemOffset) * self.NewIndex * -1 * self.ZoomFactor
        --     if self.SelectedIndex then
        --         self.OffsetY = self.SelectedOffsetY
        --     else
        --         self.OffsetY = 0
        --     end
        -- end
    end
end

function M:BP_SetListItems(node_data, line_data)
    self.node_data = node_data
    self.ItemDataSourceCount = 0
    for _, value in ipairs(node_data) do
        if value.height > self.ItemDataSourceCount then
            self.ItemDataSourceCount = value.height
        end
    end
    self.ContentPanel:ClearChildren()
    UE.UBlueprintMapLibrary.Map_Clear(self.ItemUIArray)
    UE.UKismetArrayLibrary.Array_Clear(self.ItemIndexArray)

    self.OffsetX = 0
    self.OffsetY = 0
    self.ContentPanel:SetRenderTranslation(UE.FVector2D(0, 0))
    self.ContentPanel:SetRenderTranslation(UE.FVector2D(0, 0))

    self.DefaultItemCount = self.ItemDataSourceCount + 1
    self:CreateDefaultItems()
    self:CreateDefaultLines(line_data)
    local detail_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_StoryTree/UI_TreeDetail.UI_TreeDetail_C")
    self.DetailPanel = UE4.UWidgetBlueprintLibrary.Create(self, detail_class)
    self.ContentPanel:AddChild(self.DetailPanel)
    self.DetailPanel:SetVisibility(UE.ESlateVisibility.Hidden)
    self.DetailPanel.OKButton.OnClicked:Add(self, self.OnClickOpenPlot)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    --选中当前节点
    local cur_node_data = {}
    for index, node_data in ipairs(self.node_data) do
        if plot_info.plot_tree_id == self.node_data[1].id and plot_info.plot_node_id == node_data.id then
            cur_node_data = node_data
            break
        end
    end

    local selectTreePanel = UE.UGameplayStatics.GetGameInstance(self):GetUMG('UI_SelectTree')
    if selectTreePanel.IsBadEnd then
        --如果是BE选中上一个节点 根据连线找所有在当前节点之前的节点
        local pre_node_id = {}
        for head_id, tail_infos in pairs(line_data) do
            for _, tail_info in ipairs(tail_infos) do
                if tail_info.id == cur_node_data.id then
                    for index, node_data in ipairs(self.node_data) do
                        if node_data.id == head_id then
                            local node_info = {}
                            node_info.node_id = head_id
                            node_info.node_data = node_data
                            table.insert(pre_node_id, node_info)
                            table.insert(pre_node_id, node_info)
                        end
                    end
                end
            end
        end

        if #pre_node_id > 1 then
            table.sort(pre_node_id, function(a, b)
                local a_unlocked = plot_info.story_node_infos[self.node_data[1].id][a.node_id].unlocked
                local b_unlocked = plot_info.story_node_infos[self.node_data[1].id][b.node_id].unlocked
                if a_unlocked and not b_unlocked then
                    return true
                elseif not a_unlocked and b_unlocked then
                    return false
                else
                    return a.node_id < b.node_id
                end
            end)
        end
        cur_node_data = pre_node_id[1].node_data
    end

    local cur_select_index = 0
    for index, node_data in ipairs(self.node_data) do
        if cur_node_data.id == node_data.id then
            cur_select_index = index
            break
        end
    end
    local positionX = (self.ItemWidth + self.ItemOffset) * (cur_node_data.height - 1) + 29
    local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
    self.OffsetX = -positionX + winWidth / 2 - self.ItemWidth * 0.15
    self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, 0))
    self:OnClickedNode(cur_select_index - 1)
    local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
end

function M:CreateDefaultItems()
    for index = 0, #self.node_data - 1 do
        self.ItemIndexArray:Add(index)
        local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_StoryTree/UI_Node.UI_Node_C")
        local widget = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
        self.ItemUIArray:Add(index, widget)
        self.ContentPanel:AddChild(widget)
        local slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget)
        local anchors = UE.FAnchors()
        anchors.Minimum = UE.FVector2D(0, 0.5)
        anchors.Maximum = UE.FVector2D(0, 0.5)
        slot:SetAnchors(anchors)
        local positionX = (self.ItemWidth + self.ItemOffset) * (self.node_data[index + 1].height - 1) + 29
        local positionY = 168 * self.node_data[index + 1].width - 80
        slot:SetPosition(UE.FVector2D(positionX, positionY))
        slot:SetSize(UE.FVector2D(self.ItemWidth, self.ItemHeight))
        self:BP_OnEntryInitialized(widget, index + 1)
        widget.Button.OnClicked:Add(self, function()
            self:OnClickedNode(index)
        end)
    end
end

function M:CreateDefaultLines(lines_data)
    self.LineUIArray = {}
    local d_story_node = require("ClientDatas.d_story_node")
    for head_id, tail_infos in pairs(lines_data) do
        local head_data = {}
        local tails_data = {}
        for _, node_data in ipairs(self.node_data) do
            if head_id == node_data.id then
                head_data = node_data
            else
                for __, tail_info in ipairs(tail_infos) do
                    if tail_info.id == node_data.id then
                        node_data.branch_to_main = tail_info.branch_to_main
                        table.insert(tails_data, node_data)
                    end
                end
            end
        end
        if #tails_data > 1 then
            table.sort(tails_data, function(a, b)
                return a.width < b.width
            end)
        end

        for index, tail_data in ipairs(tails_data) do
            local line_height = 6
            local space = 20
            local handle_length = 40
            local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_StoryTree/UI_TreeLine.UI_TreeLine_C")
            local widget = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
            self.ContentPanel:AddChild(widget)
            local slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget)
            local anchors = UE.FAnchors()
            anchors.Minimum = UE.FVector2D(0, 0.5)
            anchors.Maximum = UE.FVector2D(0, 0.5)
            slot:SetAnchors(anchors)
            if head_data.width == tail_data.width then --线头和线尾在同一直线上
                local positionX = (self.ItemWidth + self.ItemOffset) * (head_data.height - 1) + 27 + self.ItemWidth
                local positionY = 168 * head_data.width - 80 + self.ItemHeight / 2 - line_height / 2
                slot:SetPosition(UE.FVector2D(positionX, positionY))
                local x = (self.ItemWidth + self.ItemOffset) * (tail_data.height - 1) - positionX
                local size = UE.FVector2D(x, 2)
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Handle):SetSize(UE.FVector2D(0, 0))
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetSize(UE.FVector2D(0, 0))
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(handle_length,
                    2))
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetSize(size)

                --如果线头和线尾中间相隔节点
                if math.abs(head_data.height - tail_data.height) > 1 then
                    --如果连线之间有node就需要绕开
                    local has_node = false
                    for index, node_data in ipairs(self.node_data) do
                        if node_data.width == head_data.width then
                            if head_data.height > tail_data.height then
                                if node_data.height > tail_data.height
                                    and node_data.height < head_data.height then
                                    has_node = true
                                end
                            else
                                if node_data.height < tail_data.height
                                    and node_data.height > head_data.height then
                                    has_node = true
                                end
                            end
                            
                        end
                    end
                    if has_node then
                        local pos_Horizontal = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):GetPosition()
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(pos_Horizontal.X, -170))
                        size = UE.FVector2D(170, 2)
                        local pos_Vertical = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):GetPosition()
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetSize(size)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetPosition(UE.FVector2D(pos_Vertical.X, -170))

                        widget.Image_Vertical_1:SetVisibility(UE.ESlateVisibility.Visible)
                        pos_Vertical = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical_1):GetPosition()
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical_1):SetSize(size)
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical_1):SetPosition(UE.FVector2D(pos_Vertical.X + x, -170))
                    end
                end
            elseif head_data.width < tail_data.width then --线头低于线尾
                local positionX = (self.ItemWidth + self.ItemOffset) * (head_data.height - 1) + 27 + self.ItemWidth
                local positionY = 168 * head_data.width - 80 + self.ItemHeight / 2 + index * 6 - line_height / 2
                slot:SetPosition(UE.FVector2D(positionX, positionY))

                --根据当前连线后面还有多少根连线计算Image_Handle长度
                local count = #tails_data - index
                local size = UE.FVector2D(count * 20, 2)
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Handle):SetSize(size)
                local x = (168 * tail_data.width - 80 + self.ItemHeight / 2) - positionY
                size = UE.FVector2D(x, 2)
                if tail_data.branch_to_main then
                    local horizontal_x = (self.ItemWidth + self.ItemOffset) * (tail_data.height - 1) - positionX - count * space
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetPosition(UE.FVector2D(count * space + handle_length + horizontal_x, 2))
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetSize(size)
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(count * space + handle_length, 2))
                    size = UE.FVector2D(horizontal_x, 2)
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetSize(size)
                else
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetPosition(UE.FVector2D(count * space + handle_length, 2))
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetSize(size)
                    
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(count * space + handle_length, x))
                    local x = (self.ItemWidth + self.ItemOffset) * (tail_data.height - 1) - positionX - count * space
                    size = UE.FVector2D(x, 2)
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetSize(size)
                end
            elseif head_data.width > tail_data.width then --线头高于线尾
                local positionX = (self.ItemWidth + self.ItemOffset) * (head_data.height - 1) + 27 + self.ItemWidth
                local positionY = 168 * head_data.width - 80 + self.ItemHeight / 2 - index * 10 - line_height / 2
                slot:SetPosition(UE.FVector2D(positionX, positionY))

                --根据当前连线后面还有多少根连线计算Image_Handle长度
                local count = index - 1
                local size = UE.FVector2D(count * 20, 2)
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Handle):SetSize(size)

                local x = positionY - (168 * tail_data.width - 80 + self.ItemHeight / 2)
                size = UE.FVector2D(x, 2)
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetPosition(UE.FVector2D(count * space + handle_length, -x + 3))
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetSize(size)

                if tail_data.width >= 0 and head_data.width > 0 then
                    --y设为2是为了让Horizontal居中于Image
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(count * space + handle_length, 2))
                    local x = (self.ItemWidth + self.ItemOffset) * (tail_data.height - 1) - positionX - count * space
                    size = UE.FVector2D(x, 2)
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetSize(size)

                    local pos_Vertical = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):GetPosition()
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Vertical):SetPosition(UE.FVector2D(pos_Vertical.X + x, pos_Vertical.Y))
                else
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetPosition(UE.FVector2D(count * space + handle_length, -x + 3))
                    local x = (self.ItemWidth + self.ItemOffset) * (tail_data.height - 1) - positionX - count * space
                    size = UE.FVector2D(x, 2)
                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget.Image_Horizontal):SetSize(size)
                end
            end
            local config = d_story_node[tail_data.id]
            if #config.key > 0 then
                local images = widget.LinePanel:GetAllChildren()
                for _, image in pairs(images) do
                    image:SetRenderOpacity(0.3)
                end
            end
            if not self.LineUIArray[head_data.id] then
                self.LineUIArray[head_data.id] = {}
            end
            table.insert(self.LineUIArray[head_data.id], { ui = widget, head = head_data, tail = tail_data })
        end
    end
end

function M:OnClickedNode(index)
    -- if self.OnClickedTimer then
    --     UE.UKismetSystemLibrary.K2_ClearAndInvalidateTimerHandle(self, self.OnClickedTimer)
    --     self.OnClickedTimer = nil
    --     self.bUserScroll = false
    -- end

    --取消上次选中
    if self.SelectedIndex then
        if self.SelectedIndex == index and self.ClickFromGamePad then
            self:OnClickOpenPlot()
            return
        end
        local select_widget = self.ItemUIArray:Find(self.SelectedIndex)
        select_widget.select:SetVisibility(UE.ESlateVisibility.Hidden)
        local select_slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(select_widget)
        select_slot:SetPosition(UE.FVector2D(select_slot:GetPosition().X,
            select_slot:GetPosition().Y + self.ItemHeight * 0.25))
        select_slot:SetSize(UE.FVector2D(self.ItemWidth, self.ItemHeight))
        if self.LineUIArray[self.node_data[self.SelectedIndex + 1].id] then
            for _, value in ipairs(self.LineUIArray[self.node_data[self.SelectedIndex + 1].id]) do
                local line_slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui)
                local positionX = line_slot:GetPosition().X - self.ItemWidth * 0.5
                local positionY = line_slot:GetPosition().Y
                line_slot:SetPosition(UE.FVector2D(positionX, positionY))
                local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetSize()
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetSize(UE.FVector2D(
                    size.X + self.ItemWidth * 0.5, size.Y))
                local position_Vertical_1 = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical_1):GetPosition()
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical_1):SetPosition(UE.FVector2D(position_Vertical_1.X + self.ItemWidth * 0.5, position_Vertical_1.Y))
                if value.head.width ~= 0 then
                    local pos_Vertical = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                    local pos_Horizontal = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                    if value.head.width ~= 0 then
                        if pos_Vertical.X > pos_Horizontal.X then--Vertica和Horizontal前后关系不一样时处理也不一样
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(pos_Vertical.X + self.ItemWidth * 0.5, pos_Vertical.Y))
                        end
                    end
                end
            end
        end

        --还原兄弟节点
        local detail_height = 695
        for i, node_data in ipairs(self.node_data) do
            if node_data.height == self.node_data[self.SelectedIndex + 1].height and node_data.id ~= self.node_data[self.SelectedIndex + 1].id
                and node_data.width > self.node_data[self.SelectedIndex + 1].width then
                local brother = self.ItemUIArray:Find(i - 1)
                local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(brother):GetPosition()
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(brother):SetPosition(UE.FVector2D(position.X,
                    position.Y - detail_height))

                for _, lines in pairs(self.LineUIArray) do
                    for __, value in ipairs(lines) do
                        if value.tail.id == node_data.id then
                            local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetSize()
                            if value.tail.width > value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X - detail_height), 2))
                            else
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X - detail_height), 2))
                            end
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                math.abs(size.X - detail_height), 2))
                            local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetPosition(UE.FVector2D(
                                position.X, position.Y - detail_height))
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                            size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetSize()
                            if value.tail.width < value.head.width then
                                if value.head.width == 0 then
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                        position.X, position.Y - size.X))
                                else
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                        position.X, position.Y + size.X))
                                end
                            end
                        elseif value.head.id == node_data.id then
                            local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetSize()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                math.abs(size.X - detail_height), 2))
                            local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                            if value.tail.width > value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X, position.Y + size.X - detail_height))
                            elseif value.tail.width < value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X, position.Y + detail_height - size.X))
                            elseif value.tail.width == value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X -
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetSize().x,
                                    position.Y))
                            end
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetPosition(UE.FVector2D(
                                position.X, position.Y - detail_height))
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image):SetPosition(UE.FVector2D(
                                position.X, position.Y - detail_height))
                        end
                    end
                end
            end
        end

        for _, lines in pairs(self.LineUIArray) do
            for __, value in ipairs(lines) do
                value.ui:SetVisibility(UE.ESlateVisibility.Visible)
            end
        end
    end

    --选中
    if index == self.SelectedIndex then
        self:SelectNodeScroll(index, true)
    else
        local widget = self.ItemUIArray:Find(index)
        widget.select:SetVisibility(UE.ESlateVisibility.SelfHitTestInVisible)
        local slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget)
        self.SelectedOffsetY = -250 + (-80 - slot:GetPosition().Y)
        slot:SetPosition(UE.FVector2D(slot:GetPosition().X, slot:GetPosition().Y - self.ItemHeight * 0.25))
        --和UI一样的缩放比例是1.5倍
        slot:SetSize(UE.FVector2D(self.ItemWidth * 1.5, self.ItemHeight * 1.5))
        local detail_height = 695
        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(self.DetailPanel):SetPosition(UE.FVector2D(slot:GetPosition().X,
            slot:GetPosition().Y + detail_height))

        local tail_ids = {}
        if self.LineUIArray[self.node_data[index + 1].id] then
            for _, value in ipairs(self.LineUIArray[self.node_data[index + 1].id]) do
                local line_slot = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui)
                local positionX = line_slot:GetPosition().X + self.ItemWidth * 0.5
                local positionY = line_slot:GetPosition().Y
                line_slot:SetPosition(UE.FVector2D(positionX, positionY))
                local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetSize()

                --相邻连线右移
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetSize(UE.FVector2D(
                    size.X - self.ItemWidth * 0.5, size.Y))

                local position_Vertical_1 = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical_1):GetPosition()
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical_1):SetPosition(UE.FVector2D(position_Vertical_1.X - self.ItemWidth * 0.5, position_Vertical_1.Y))

                local pos_Vertical = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                local pos_Horizontal = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                if value.head.width ~= 0 then
                    if pos_Vertical.X > pos_Horizontal.X then --Vertica和Horizontal前后关系不一样时处理也不一样
                        UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(pos_Vertical.X - self.ItemWidth * 0.5, pos_Vertical.Y))
                    end
                end

                table.insert(tail_ids, value.tail.id)
            end
        end

        --移动兄弟节点
        for i, node_data in ipairs(self.node_data) do
            if node_data.height == self.node_data[index + 1].height and node_data.id ~= self.node_data[index + 1].id
                and node_data.width > self.node_data[index + 1].width then
                local brother = self.ItemUIArray:Find(i - 1)
                local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(brother):GetPosition()
                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(brother):SetPosition(UE.FVector2D(position.X,
                    position.Y + detail_height))
                for _, lines in pairs(self.LineUIArray) do
                    for __, value in ipairs(lines) do
                        if value.tail.id == node_data.id then
                            --连线的尾是当前点击节点
                            local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetSize()
                            if value.tail.width > value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X + detail_height), 2))
                            else
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X - detail_height), 2))
                            end
                            local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetPosition(UE.FVector2D(
                                position.X, position.Y + detail_height))
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                            if value.tail.width <= value.head.width then
                                if value.head.width == 0 then
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                        position.X, position.Y + size.X))
                                else
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                        position.X, position.Y - size.X))
                                end
                            end
                        elseif value.head.id == node_data.id then
                            --连线的头是当前点击节点
                            local size = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetSize()
                            if value.tail.width > value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X - detail_height), 2))
                            else
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetSize(UE.FVector2D(
                                    math.abs(size.X + detail_height), 2))
                            end
                            local position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):GetPosition()
                            if value.tail.width > value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X, position.Y + size.X))
                            elseif value.tail.width < value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X, position.Y - size.X))
                            elseif value.tail.width == value.head.width then
                                UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Vertical):SetPosition(UE.FVector2D(
                                    position.X +
                                    UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetSize().x,
                                    position.Y))
                            end
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image_Horizontal):SetPosition(UE.FVector2D(
                                position.X, position.Y + detail_height))
                            position = UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image):GetPosition()
                            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(value.ui.Image):SetPosition(UE.FVector2D(
                                position.X, position.Y + detail_height))
                        end
                    end
                end
            end
        end

        --同列在下方没有节点但有连线的隐藏连线
        for i, tail_id in ipairs(tail_ids) do
            for _, lines in pairs(self.LineUIArray) do
                for __, value in ipairs(lines) do
                    if value.tail.id == tail_id then
                        local height = self.node_data[index + 1].height
                        local width = self.node_data[index + 1].width
                        if value.head.height < height and value.head.width > width then
                            value.ui:SetVisibility(UE.ESlateVisibility.Hidden)
                        end
                    end
                end
            end
        end

        self:RefreshDetailPanel(index)
        self:SelectNodeScroll(index, false)
    end
end

function M:RefreshDetailPanel(index)
    local plot_info = PlotSystem:GetInstance().PlotInfo
    local d_story_node = require("ClientDatas.d_story_node")
    local config = d_story_node[self.node_data[index + 1].id]
    if plot_info.story_node_infos[self.node_data[1].id][self.node_data[index + 1].id].unlocked then
        self.DetailPanel.UI_Desc.TextDesc:SetText(Database.L10n(config.desc))
        self.DetailPanel.OKButton:SetVisibility(UE.ESlateVisibility.Visible)
    else
        self.DetailPanel.UI_Desc.TextDesc:SetText(Database.L10n(94100000))
        self.DetailPanel.OKButton:SetVisibility(UE.ESlateVisibility.Hidden)
    end
    self.DetailPanel.UI_UnLock.NodePanel:ClearChildren()
    local index = 0
    for _, value in ipairs(config.key) do
        local key_config = d_story_node[math.floor(value / 10)]
        local is_parent = false
        for _, sonid in ipairs(key_config.sonid) do
            if sonid == config.id then
                is_parent = true
            end
        end

        if not is_parent then
            index = index + 1
            local widget_class = UE.UClass.Load("/Game/_Game/Blueprints/UI/UI_StoryTree/UI_Node.UI_Node_C")
            local widget = UE4.UWidgetBlueprintLibrary.Create(self, widget_class)
            self.DetailPanel.UI_UnLock.NodePanel:AddChild(widget)
            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget):SetSize(UE.FVector2D(400, 80))
            UE.UWidgetLayoutLibrary.SlotAsCanvasSlot(widget):SetPosition(UE.FVector2D(0, 80 * (index - 1)))

            if key_config then
                widget.Text_NameLock:SetText(Database.L10n(key_config.name))
                widget.Text_NameUnLock:SetText(Database.L10n(key_config.name))
                widget.Text_NameComplete:SetText(Database.L10n(key_config.name))

                if plot_info.story_node_infos[self.node_data[1].id][key_config.id].unlocked and plot_info.story_node_infos[self.node_data[1].id][key_config.id].completed then
                    widget.Lock:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget.UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget.Complete:SetVisibility(UE.ESlateVisibility.Visible)
                elseif plot_info.story_node_infos[self.node_data[1].id][key_config.id].unlocked then
                    widget.Lock:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget.UnLock:SetVisibility(UE.ESlateVisibility.Visible)
                    widget.Complete:SetVisibility(UE.ESlateVisibility.Hidden)
                else
                    widget.Lock:SetVisibility(UE.ESlateVisibility.Visible)
                    widget.UnLock:SetVisibility(UE.ESlateVisibility.Hidden)
                    widget.Complete:SetVisibility(UE.ESlateVisibility.Hidden)
                end
            end
        end
    end
end

function M:OnClickOpenPlot()
    UIManager:GetInstance():ShowConfirm({
        notice = Database.L10n(50601),
        confirm = function()
            self:Req_Plot()
        end,
        showCancel = true,
    })
end

function M:Req_Plot()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    local SaveGameSpeak = gameInstance:LoadSaveGameSpeak()
    SaveGameSpeak.PlotIndex = 0
    gameInstance:CachePlayInCity()
    local plot_info = PlotSystem:GetInstance().PlotInfo
    if not plot_info.story_node_infos[self.node_data[1].id][self.node_data[self.SelectedIndex + 1].id].unlocked then
        return
    end

    local msg = {}
    msg.plot_tree_id = self.node_data[1].id
    msg.plot_node_id = self.node_data[self.SelectedIndex + 1].id
    Client.send("req_play_plot_node", msg)
    --Client.send("req_receive_plot_tree_award", { plot_tree_id = 101010, award_id = 1 })
end

function M:Play_Plot()
    local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
    --gameInstance.OnUnloadPlotLevels:Add(gameInstance, PlotSystem.RestartStateTree)
    if UE.UGameplayStatics.GetCurrentLevelName(self, true) == "CityMap" then
        local level = UE.UGameplayStatics.GetStreamingLevel(self, "City1BusinessCenter")
        if level:IsLevelLoaded() then
            local gameInstance = UE.UGameplayStatics.GetGameInstance(self)
            if gameInstance:TopSubLevelName() == "City1BusinessCenter" then
                gameInstance:RemoveTopSubLevelName()
            end
            gameInstance.PlotLevelsName:AddUnique("City1BusinessCenter")
        end
    end
    local saveGameSpeak = gameInstance:LoadSaveGameSpeak()
    if saveGameSpeak.StoryFinished then
        saveGameSpeak.StoryFinished = false
        gameInstance:SaveSaveGameSpeak()
    end

    PlotSystem:GetInstance():RestartStateTree()
    if UE.UGameplayStatics.GetCurrentLevelName(gameInstance, true) ~= "CityMap" then
        gameInstance.JumpFromUINodeTree = true
    end
    gameInstance:GetOrAddUMG('UI_Loading2')
end

function M:SelectNodeScroll(index, bCancelSelected)
    if bCancelSelected then
        self.SelectedIndex = nil
        self.OffsetY = 0
        self.DetailPanel:SetVisibility(UE.ESlateVisibility.Hidden)
        self.bUserScroll = true
    else
        self.OffsetY = self.SelectedOffsetY
        self.SelectedIndex = index
        self.DetailPanel:SetVisibility(UE.ESlateVisibility.Visible)
    end
    self.bUserScroll = true
    -- self.OnClickedTimer = UE.UKismetSystemLibrary.K2_SetTimerDelegate(
    --     { self, self.OnClickedEvent },
    --     self.IntervalTime,
    --     false,
    --     0.0)
end

function M:MoveUpClickNode()
    if not self.SelectedIndex then
        return
    end

    local width = self.node_data[self.SelectedIndex + 1].width
    local height = self.node_data[self.SelectedIndex + 1].height
    local nearest_width
    local index
    for i, node_data in ipairs(self.node_data) do
        if node_data.height == height then
            if node_data.width < width then
                if not nearest_width then
                    nearest_width = node_data.width
                    index = i - 1
                elseif node_data.width > nearest_width then
                    nearest_width = node_data.width
                    index = i - 1
                end
            end
        end
    end

    if not index then
        local nearest_length
        --如果正上方找不到 就从上半区找
        for i, node_data in ipairs(self.node_data) do
            if node_data.width < width then --当前点的上半区
                local length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                if not nearest_length then
                    nearest_length = length
                    index = i - 1
                elseif length < nearest_length then
                    nearest_length = length
                    index = i - 1
                end
            end
        end
    end

    if index then
        self:OnClickedNode(index)
        local positionX = (self.ItemWidth + self.ItemOffset) * (self.node_data[index + 1].height - 1) + 29
        local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
        self.OffsetX = -positionX + winWidth / 2 - self.ItemWidth * 0.15
        self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, 0))
    end
end

function M:MoveDownClickNode()
    if not self.SelectedIndex then
        return
    end

    local width = self.node_data[self.SelectedIndex + 1].width
    local height = self.node_data[self.SelectedIndex + 1].height
    local nearest_width
    local index
    for i, node_data in ipairs(self.node_data) do
        if node_data.height == height then
            if node_data.width > width then
                if not nearest_width then
                    nearest_width = node_data.width
                    index = i - 1
                elseif node_data.width < nearest_width then
                    nearest_width = node_data.width
                    index = i - 1
                end
            end
        end
    end

    if not index then
        local nearest_length
        --如果正下方找不到 就从下半区找
        for i, node_data in ipairs(self.node_data) do
            if node_data.width > width then --当前点的下半区
                local length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                if not nearest_length then
                    nearest_length = length
                    index = i - 1
                elseif length < nearest_length then
                    nearest_length = length
                    index = i - 1
                end
            end
        end
    end

    if index then
        self:OnClickedNode(index)
        local positionX = (self.ItemWidth + self.ItemOffset) * (self.node_data[index + 1].height - 1) + 29
        local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
        self.OffsetX = -positionX + winWidth / 2 - self.ItemWidth * 0.15
        self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, 0))
    end
end

function M:MoveRightClickNode()
    if not self.SelectedIndex then
        return
    end

    local width = self.node_data[self.SelectedIndex + 1].width
    local height = self.node_data[self.SelectedIndex + 1].height
    local nearest_height
    local nearest_length
    local index
    for i, node_data in ipairs(self.node_data) do
        if node_data.width == width then
            if node_data.height > height then
                if not nearest_height then
                    nearest_height = node_data.height
                    index = i - 1
                    nearest_length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                elseif node_data.height < nearest_height then
                    nearest_height = node_data.height
                    index = i - 1
                    nearest_length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                end
            end
        end
    end

    --找到了正右方的节点也要和右半区的所有点对比距离
    for i, node_data in ipairs(self.node_data) do
        if node_data.height > height then     --当前点的右半区
            local length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
            if not nearest_length then
                nearest_length = length
                index = i - 1
            elseif length < nearest_length then
                nearest_length = length
                index = i - 1
            end
        end
    end

    if index then
        self:OnClickedNode(index)
        local positionX = (self.ItemWidth + self.ItemOffset) * (self.node_data[index + 1].height - 1) + 29
        local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
        self.OffsetX = -positionX + winWidth / 2 - self.ItemWidth * 0.15
        self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, 0))
    end
end

function M:MoveLeftClickNode()
    if not self.SelectedIndex then
        return
    end

    local width = self.node_data[self.SelectedIndex + 1].width
    local height = self.node_data[self.SelectedIndex + 1].height
    local nearest_height
    local nearest_length
    local index
    for i, node_data in ipairs(self.node_data) do
        if node_data.width == width then
            if node_data.height < height then
                if not nearest_height then
                    nearest_height = node_data.height
                    index = i - 1
                    nearest_length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                elseif node_data.height > nearest_height then
                    nearest_height = node_data.height
                    index = i - 1
                    nearest_length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
                end
            end
        end
    end

    --找到了正左方的节点也要和左半区的所有点对比距离
    for i, node_data in ipairs(self.node_data) do
        if node_data.height < height then     --当前点的左半区
            local length = (node_data.width - width) * (node_data.width - width) + (node_data.height - height) * (node_data.height - height)
            if not nearest_length then
                nearest_length = length
                index = i - 1
            elseif length < nearest_length then
                nearest_length = length
                index = i - 1
            end
        end
    end

    if index then
        self:OnClickedNode(index)
        local positionX = (self.ItemWidth + self.ItemOffset) * (self.node_data[index + 1].height - 1) + 29
        local winWidth, winHeight = UE.UGameplayStatics.GetPlayerController(self, 0):GetViewportSize()
        self.OffsetX = -positionX + winWidth / 2 - self.ItemWidth * 0.15
        self.ContentPanel:SetRenderTranslation(UE.FVector2D(self.OffsetX, 0))
    end
end

function M:OnClickedEvent()
    self.bUserScroll = true
end

return M

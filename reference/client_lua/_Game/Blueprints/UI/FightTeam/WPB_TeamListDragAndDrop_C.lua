--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

require "UnLua"
require "Common.TableUtil"
local utf8 = require "Common.Tools.utf8"

---@type WPB_TeamListDragAndDrop_C
local WPB_TeamListDragAndDrop_C = Class()

--构造函数
function WPB_TeamListDragAndDrop_C:Construct()
    self:InitData()
    self:InitUI()
end

function WPB_TeamListDragAndDrop_C:Destruct()
end

function WPB_TeamListDragAndDrop_C:InitUI()
    self.Image_Mask.OnMouseButtonDownEvent:Unbind()
    self.Image_Mask.OnMouseButtonDownEvent:Bind(self, self.OnMouseButtonDown_Image_Mask)
end

function WPB_TeamListDragAndDrop_C:InitData()

end

function WPB_TeamListDragAndDrop_C:OnDragCancelled()
    self.Image_Drag:SetVisibility(UE.ESlateVisibility.Hidden)
end

function WPB_TeamListDragAndDrop_C:OnMouseButtonDown(MyGemotry, MouseEvent)
    return UE.UWidgetBlueprintLibrary.DetectDragIfPressed(MouseEvent, self, UE.EKeys.LeftMouseButton)
end

function WPB_TeamListDragAndDrop_C:OnMouseButtonUp(MyGemotry, MouseEvent)
    if self.ParentUI then
        self.ParentUI:OnSelectedRole(self.TeamIndex)
    end
    return UE.UWidgetBlueprintLibrary.Handled()
end

function WPB_TeamListDragAndDrop_C:OnMouseButtonDown_Image_Mask(MyGemotry, MouseEvent)
    if self.ParentUI then
        self.ParentUI:OnSelectedRole(self.TeamIndex)
    end
    return UE.UWidgetBlueprintLibrary.Handled()
end

function WPB_TeamListDragAndDrop_C:OnDragDetected(MyGemotry, PointerEvent)
    self.Image_Drag:SetVisibility(UE.ESlateVisibility.Visible)
    self.Image_Drag:RemoveFromParent()
    local operationClass = UE.UClass.Load('/Game/_Game/Blueprints/UI/UI_TeamEdit/UI_Data/BP_TeamListDragAndDrop.BP_TeamListDragAndDrop_C')
    if not operationClass then
        return 
    end
    local operation = NewObject(operationClass)
    operation.Payload = self
    operation.DefaultDragVisual = self.Image_Drag
    operation.Pivot = UE.EDragPivot.CenterCenter
    operation.TeamIndex = self.TeamIndex
    return operation
end

function WPB_TeamListDragAndDrop_C:OnDrop(MyGemotry, PointerEvent, Operation)
    self.Image_Drag:SetVisibility(UE.ESlateVisibility.Hidden)
    if self.ParentUI then
        self.ParentUI:OnDragAndDropEnd(Operation.TeamIndex, self.TeamIndex)
    end
    return false
end

return WPB_TeamListDragAndDrop_C
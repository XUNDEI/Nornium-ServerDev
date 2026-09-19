local M = {}

---@type UInputAction
M.IA_MoveUp = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_MoveUp.IA_MoveUp")
---@type UInputAction
M.IA_Back = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_Back.IA_Back")
---@type UInputAction
M.IA_Confirm = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_Confirm.IA_Confirm")
---@type UInputAction
M.IA_Shift = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_Shift.IA_Shift")
---@type UInputAction
M.IA_RightMouseButton = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_RightMouseButton.IA_RightMouseButton")
---@type UInputAction
M.IA_LeftMouseButton = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_LeftMouseButton.IA_LeftMouseButton")
---@type UInputAction
M.IA_HideUI = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_HideUI.IA_HideUI")
---@type UInputAction
M.IA_Grab = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_Grab.IA_Grab")
---@type UInputAction
M.IA_ChangeSkin = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_ChangeSkin.IA_ChangeSkin")
---@type UInputAction
M.IA_Controlled = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_Controlled.IA_Controlled")
---@type UInputAction
M.IA_Ctrl = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_Ctrl.IA_Ctrl")
---@type UInputAction
M.IA_Finger = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IA_Finger.IA_Finger")
---@type UInputAction
M.IA_Move = LoadObject("/Game/_Game/Blueprints/Input/Common/IA_Move.IA_Move")
---@type UInputAction
M.IA_MoveCamera = LoadObject("/Game/_Game/Blueprints/Input/Common/IA_MoveCamera.IA_MoveCamera")
---@type UInputAction
M.IA_Scale = LoadObject("/Game/_Game/Blueprints/Input/Common/IA_Scale.IA_Scale")
---@type UInputAction
M.IA_DashSkill = LoadObject("/Game/_Game/Blueprints/Input/Character/IA_DashSkill.IA_DashSkill")
---@type UInputAction
M.IA_Jump = LoadObject("/Game/_Game/Blueprints/Input/Character/IA_Jump.IA_Jump")
---@type UInputAction
M.IA_ToggleSprint = LoadObject("/Game/_Game/Blueprints/Input/Character/IA_ToggleSprint.IA_ToggleSprint")
---@type UInputAction
M.IA_ShowCursor = LoadObject("/Game/_Game/Blueprints/Input/Common/IA_ShowCursor.IA_ShowCursor")
---@type UInputAction
M.IA_NextCharacter = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_NextCharacter.IA_NextCharacter")
---@type UInputAction
M.IA_NextTarget = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_NextTarget.IA_NextTarget")
---@type UInputAction
M.IA_NormalAttack = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_NormalAttack.IA_NormalAttack")
---@type UInputAction
M.IA_Pause = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_Pause.IA_Pause")
---@type UInputAction
M.IA_PrevCharacter = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_PrevCharacter.IA_PrevCharacter")
---@type UInputAction
M.IA_PrevTarget = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_PrevTarget.IA_PrevTarget")
---@type UInputAction
M.IA_ShipSkill = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_ShipSkill.IA_ShipSkill")
---@type UInputAction
M.IA_Skill = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_Skill.IA_Skill")
---@type UInputAction
M.IA_Step = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_Step.IA_Step")
---@type UInputAction
M.IA_Ultimate = LoadObject("/Game/_Game/Blueprints/Input/Fight/IA_Ultimate.IA_Ultimate")
---@type UInputAction
M.IA_Switch = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_Switch.IA_Switch")
---@type UInputAction
M.IA_BuildPlace = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_BuildPlace.IA_BuildPlace")
---@type UInputAction
M.IA_Character = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Character.IA_Character")
---@type UInputAction
M.IA_Event = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Event.IA_Event")
---@type UInputAction
M.IA_Gacha = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Gacha.IA_Gacha")
---@type UInputAction
M.IA_Item = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Item.IA_Item")
---@type UInputAction
M.IA_Menu = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Menu.IA_Menu")
---@type UInputAction
M.IA_Mission = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Mission.IA_Mission")
---@type UInputAction
M.IA_Store = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Store.IA_Store")
---@type UInputAction
M.IA_Story = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Story.IA_Story")
---@type UInputAction
M.IA_Team = LoadObject("/Game/_Game/Blueprints/Input/UI/SystemEntry/IA_Team.IA_Team")
---@type UInputAction
M.IA_Interact = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_Interact.IA_Interact")
---@type UInputAction
M.IA_SwitchOption = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_SwitchOption.IA_SwitchOption")
---@type UInputAction
M.IA_GachaOne = LoadObject("/Game/_Game/Blueprints/Input/UI/Gacha/IA_GachaOne.IA_GachaOne")
---@type UInputAction
M.IA_GachaTab = LoadObject("/Game/_Game/Blueprints/Input/UI/Gacha/IA_GachaTab.IA_GachaTab")
---@type UInputAction
M.IA_GachaTen = LoadObject("/Game/_Game/Blueprints/Input/UI/Gacha/IA_GachaTen.IA_GachaTen")
---@type UInputAction
M.IA_Click = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_Click.IA_Click")
---@type UInputAction
M.IA_MoveCursor = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_MoveCursor.IA_MoveCursor")
---@type UInputAction
M.IA_SimulateClick = LoadObject("/Game/_Game/Blueprints/Input/UI/IA_SimulateClick.IA_SimulateClick")
---@type UInputAction
M.IA_MoveDown = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_MoveDown.IA_MoveDown")
---@type UInputAction
M.IA_MoveRight = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_MoveRight.IA_MoveRight")
---@type UInputAction
M.IA_MoveLeft = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_MoveLeft.IA_MoveLeft")
---@type UInputAction
M.IA_ZoomIn = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_ZoomIn.IA_ZoomIn")
---@type UInputAction
M.IA_StorySimulateClick = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_StorySimulateClick.IA_StorySimulateClick")
---@type UInputAction
M.IA_StoryClick = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IA_StoryClick.IA_StoryClick")
---@type UInputMappingContext
M.IMC_UI_MoveUp = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_MoveUp.IMC_UI_MoveUp")
---@type UInputMappingContext
M.IMC_UI_Common = LoadObject("/Game/_Game/Blueprints/Input/UI/IMC_UI_Common.IMC_UI_Common")
---@type UInputMappingContext
M.IMC_BuildActor = LoadObject("/Game/_Game/Blueprints/Input/BuildActor/IMC_BuildActor.IMC_BuildActor")
---@type UInputMappingContext
M.IMC_Character = LoadObject("/Game/_Game/Blueprints/Input/Character/IMC_Character.IMC_Character")
---@type UInputMappingContext
M.IMC_Move = LoadObject("/Game/_Game/Blueprints/Input/Common/IMC_Move.IMC_Move")
---@type UInputMappingContext
M.IMC_Common = LoadObject("/Game/_Game/Blueprints/Input/Common/IMC_Common.IMC_Common")
---@type UInputMappingContext
M.IMC_Fight = LoadObject("/Game/_Game/Blueprints/Input/Fight/IMC_Fight.IMC_Fight")
---@type UInputMappingContext
M.IMC_UI_SystemEntry = LoadObject("/Game/_Game/Blueprints/Input/UI/IMC_UI_SystemEntry.IMC_UI_SystemEntry")
---@type UInputMappingContext
M.IMC_UI_Options = LoadObject("/Game/_Game/Blueprints/Input/UI/IMC_UI_Options.IMC_UI_Options")
---@type UInputMappingContext
M.IMC_UI_Gacha = LoadObject("/Game/_Game/Blueprints/Input/UI/IMC_UI_Gacha.IMC_UI_Gacha")
---@type UInputMappingContext
M.IMC_UI_Cursor = LoadObject("/Game/_Game/Blueprints/Input/UI/IMC_UI_Cursor.IMC_UI_Cursor")
---@type UInputMappingContext
M.IMC_UI_MoveDown = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_MoveDown.IMC_UI_MoveDown")
---@type UInputMappingContext
M.IMC_UI_MoveRight = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_MoveRight.IMC_UI_MoveRight")
---@type UInputMappingContext
M.IMC_UI_MoveLeft = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_MoveLeft.IMC_UI_MoveLeft")
---@type UInputMappingContext
M.IMC_UI_ZoomIn = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_ZoomIn.IMC_UI_ZoomIn")
---@type UInputMappingContext
M.IMC_UI_StoryCursor = LoadObject("/Game/_Game/Blueprints/Input/UI/StoryTree/IMC_UI_StoryCursor.IMC_UI_StoryCursor")

return M

// This is an Unreal Script
class RecoveryTurnSystem_TurnManagement extends X2EventListener;

static function array<X2DataTemplate> CreateTemplates()
{
  local array<X2DataTemplate> Templates;

  `log("RecoveryTurnSystem_TurnManagement :: Registering Tactical Event Listeners");

  Templates.AddItem(AddStartOfTacticalActionTurn());
  Templates.AddItem(AddTacticalUnitGroupTurnBegun());

  return Templates;
}


static function X2EventListenerTemplate AddStartOfTacticalActionTurn()
{
  local X2EventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'X2EventListenerTemplate', Template, 'RecoveryTurnSystem_StartOfTacticalActionTurn');

	Template.RegisterInTactical = true;
	Template.AddEvent('StartOfTacticalActionTurn', OnStartOfTacticalActionTurn);

	return Template;
}


static function X2EventListenerTemplate AddTacticalUnitGroupTurnBegun()
{
  local X2EventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'X2EventListenerTemplate', Template, 'RecoveryTurnSystem_UnitGroupTurnBegun');

	Template.RegisterInTactical = true;
	Template.AddEvent('UnitGroupTurnBegun', OnUnitGroupTurnBegun);

	return Template;
}


static protected function EventListenerReturn OnStartOfTacticalActionTurn(Object EventData, Object EventSource, XComGameState GivenGameState, name EventID, Object CallbackData)
{
	local XComGameState_RecoveryQueue RecoveryQueue;
	local XComGameState_Unit UnitState, NewUnitState, FollowerState;
	local StateObjectReference UnitRef, ControllingPlayer, FollowerRef, EffectRef;
	local XComGameState_AIGroup LeaverGroup, ActorGroupState, ReturnGroup, RecoveryGroup;
	local XComGameState_Player PlayerState;
	local int FollowerIx;
	local UnitValue ReturnGroupValue;
	local XComGameState NewGameState;
	local XComGameState_BattleData BattleData;
	local Array<StateObjectReference> FollowerRefs;
	local X2TacticalGameRuleset TacticalRules;
	`log("RecoveryTurnSystem :: StartOfTacticalActionTurn");

	TacticalRules = `TACTICALRULES;
	BattleData = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	RecoveryQueue = XComGameState_RecoveryQueue(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RecoveryQueue'));

	if (
		RecoveryQueue.ActiveGroupID != 0 &&
		BattleData.InterruptingGroupRef.ObjectID != 0 &&
		BattleData.InterruptingGroupRef.ObjectID == RecoveryQueue.ActiveGroupID
	)
	{
		`log("RecoveryTurnSystem :: Broke early");
		return ELR_NoInterrupt;
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("SetupUnitActionsForPlayerTurnBegin");
	RecoveryQueue = XComGameState_RecoveryQueue(NewGameState.CreateStateObject(class'XComGameState_RecoveryQueue', RecoveryQueue.ObjectID));

	// return current unit reference to the queue - this will probably be
	// moved as we are not likely to have ActionsAvailable here
	UnitRef = RecoveryQueue.GetCurrentUnitReference();
	// we should remove the actor group here somewhere

	if (UnitRef.ObjectID != 0)
	{
		UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
		RecoveryGroup = UnitState.GetGroupMembership();
		UnitState.GetUnitValue('RTSOriginalGroup', ReturnGroupValue);
		ReturnGroup = XComGameState_AIGroup(NewGameState.ModifyStateObject(class'XComGameState_AIGroup', ReturnGroupValue.fValue));
		ReturnGroup.AddUnitToGroup(UnitState.ObjectID, NewGameState);
		UnitState.ClearUnitValue('RTSOriginalGroup');
		RecoveryQueue.ReturnUnitToQueue(UnitState);
	}

	FollowerRefs = RecoveryQueue.GetCurrentFollowerReferences();
	foreach FollowerRefs(UnitRef)
	{	
		UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
		UnitState.GetUnitValue('RTSOriginalGroup', ReturnGroupValue);
		ReturnGroup = XComGameState_AIGroup(NewGameState.ModifyStateObject(class'XComGameState_AIGroup', ReturnGroupValue.fValue));
		ReturnGroup.AddUnitToGroup(UnitState.ObjectID, NewGameState);
		UnitState.ClearUnitValue('RTSOriginalGroup');
		RecoveryQueue.ReturnFollowerUnitToQueue(UnitState);
	}
	// end return functionality

	if (RecoveryGroup != none) {
		`log("Removed Recovery Group");
		NewGameState.RemoveStateObject(RecoveryGroup.ObjectID);
	}

	RecoveryQueue = ScanForNewUnits(NewGameState, RecoveryQueue);
	UnitRef = RecoveryQueue.PopNextUnitReference();
	UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));

	while (UnitState.IsDead()) // avoid visualising turn changes towards units that can't do anything
	{
		UnitRef = RecoveryQueue.PopNextUnitReference();
		UnitState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
	}

	UnitState.SetUnitFloatValue('RTSOriginalGroup', UnitState.GetGroupMembership().ObjectID, eCleanup_BeginTactical);
	LeaverGroup = UnitState.GetGroupMembership();
	ActorGroupState = XComGameState_AIGroup(NewGameState.CreateNewStateObject(class'XComGameState_AIGroup'));
	ActorGroupState.bSummoningSicknessCleared = true;

	if (LeaverGroup != none) {
		`log("Leaving Group");
		LeaverGroup.RemoveUnitFromGroup(UnitState.ObjectID, NewGameState);
	}

	`log("Unit Team:" @ UnitState.GetTeam());
	`log("Adding To Group");
	ActorGroupState.AddUnitToGroup(UnitState.ObjectID, NewGameState);

	if (UnitState.IsGroupLeader() && LeaverGroup != none && UnitState.GetTeam() != eTeam_XCom) {
		if ( XGUnit(UnitState.GetVisualizer()).GetAlertLevel(UnitState) != eAL_Red )
		{
			`log("Sweeping Unalerted Pod");
			foreach LeaverGroup.m_arrMembers(FollowerRef, FollowerIx)
			{
				if (FollowerIx == 0) continue; // this is the leader so ignore
				FollowerState = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', FollowerRef.ObjectID));
				RecoveryQueue.AddFollower(FollowerState);
				FollowerState.SetUnitFloatValue('RTSOriginalGroup', FollowerState.GetGroupMembership().ObjectID, eCleanup_BeginTactical);
				LeaverGroup.RemoveUnitFromGroup(FollowerState.ObjectID, NewGameState);
				`log("Leaving Group");
				ActorGroupState.AddUnitToGroup(FollowerState.ObjectID, NewGameState);
				`log("Adding To Group");
			}
		}
	}

	`log("Group Size: " @ ActorGroupState.m_arrMembers.Length);
	`log("Unit Reference Popped: " @ UnitState.ObjectID @ " " @ UnitState.GetMyTemplateName());
	RecoveryQueue.ActiveGroupID = ActorGroupState.ObjectID;
	NewGameState.AddStateObject(RecoveryQueue);
	TacticalRules.InterruptInitiativeTurn(NewGameState, ActorGroupState.GetReference());
	TacticalRules.SubmitGameState(NewGameState);

	`XEVENTMGR.TriggerEvent('RecoveryTurnSystemUpdate', RecoveryQueue);
	return ELR_NoInterrupt;
}


static protected function EventListenerReturn OnUnitGroupTurnBegun(Object EventData, Object EventSource, XComGameState NextGameState, name EventID, Object CallbackData)
{
	local XComGameState_RecoveryQueue RecoveryQueue;
	local XComGameState_AIGroup GroupState;
	local XComGameState_Unit UnitState, UnitHistoryState;
	local StateObjectReference UnitRef, FollowerRef;
	local int UnitIx;
	local bool bIsPartOfThisInterrupt;

	GroupState = XComGameState_AIGroup(EventData);
	RecoveryQueue = XComGameState_RecoveryQueue(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RecoveryQueue'));
	`log("Current Initiative Interrupting: " @ GroupState.ObjectID);
	foreach GroupState.m_arrMembers(UnitRef) 
	{
		`log("- GroupUnits UnitID: " @ UnitRef.ObjectID);
	}
	`log("Current Unit " @ RecoveryQueue.CurrentUnit.UnitRef.ObjectID);
	UnitHistoryState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(RecoveryQueue.CurrentUnit.UnitRef.ObjectID));
	UnitState = XComGameState_Unit(NextGameState.GetGameStateForObjectID(RecoveryQueue.CurrentUnit.UnitRef.ObjectID));
	`log("Current Unit ActionPoints:" @ UnitState.ActionPoints.Length);
	`log("Current Unit ActionPoints:" @ UnitHistoryState.ActionPoints.Length);
	// need to run some checks on why they're not able to act, do they have action points?

	return ELR_NoInterrupt;
}


static function XComGameState_RecoveryQueue ScanForNewUnits(XComGameState NewGameState, XComGameState_RecoveryQueue QueueState)
{
	local XComGameState_Unit UnitState;
	local bool PartOfTeam;
	
	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		PartOfTeam = (
			UnitState.GetTeam() == eTeam_XCom ||
			UnitState.GetTeam() == eTeam_TheLost ||
			UnitState.GetTeam() == eTeam_Resistance ||
			UnitState.GetTeam() == eTeam_Alien
		);

		if (!UnitState.GetMyTemplate().bIsCosmetic && PartOfTeam && !QueueState.CheckUnitInQueue(UnitState.GetReference()))
		{
			`log("Adding to queue: " @UnitState.ObjectID);
			QueueState.AddUnitToQueue(UnitState, true);
		}
	}
	return QueueState;
}

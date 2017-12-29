// This is an Unreal Script
class RecoveryTurnSystem_TurnManagement extends X2EventListener;

static function array<X2DataTemplate> CreateTemplates()
{
  local array<X2DataTemplate> Templates;

  `log("RecoveryTurnSystem_TurnManagement :: Registering Tactical Event Listeners");

  Templates.AddItem(AddTacticalNextInitiativeGroup());
  Templates.AddItem(AddTacticalUnitGroupTurnBegun());

  return Templates;
}


static function X2EventListenerTemplate AddTacticalNextInitiativeGroup()
{
  local X2EventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'X2EventListenerTemplate', Template, 'RecoveryTurnSystem_NextInitiativeGroup');

	Template.RegisterInTactical = true;
	Template.AddEvent('NextInitiativeGroup', OnNextInitiativeGroup);

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


static protected function EventListenerReturn OnNextInitiativeGroup(Object EventData, Object EventSource, XComGameState GivenGameState, name EventID, Object CallbackData)
{
	local XComGameState_RecoveryQueue RecoveryQueue;
	local XComGameState_Unit UnitState, NewUnitState, FollowerState;
	local StateObjectReference UnitRef, ControllingPlayer, FollowerRef, EffectRef;
	local int FollowerIx;
	local XComGameState NewGameState;
	local Array<StateObjectReference> FollowerRefs;
	local X2TacticalGameRuleset TacticalRules;
	`log("RecoveryTurnSystem :: NextInitiativeGroup");

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("SetupUnitActionsForPlayerTurnBegin");
	RecoveryQueue = XComGameState_RecoveryQueue(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RecoveryQueue'));
	RecoveryQueue = XComGameState_RecoveryQueue(NewGameState.CreateStateObject(class'XComGameState_RecoveryQueue', RecoveryQueue.ObjectID));

	// return current unit reference to the queue - this will probably be
	// moved as we are not likely to have ActionsAvailable here
	UnitRef = RecoveryQueue.GetCurrentUnitReference();

	if (UnitRef.ObjectID != 0)
	{
		UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
		RecoveryQueue.ReturnUnitToQueue(UnitState);
	}

	FollowerRefs = RecoveryQueue.GetCurrentFollowerReferences();
	foreach FollowerRefs(UnitRef)
	{	
		UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
		RecoveryQueue.ReturnFollowerUnitToQueue(UnitState);
	}
	// end return functionality


	RecoveryQueue = ScanForNewUnits(NewGameState, RecoveryQueue);
	UnitRef = RecoveryQueue.PopNextUnitReference();
	UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));

	while (UnitState.IsDead()) // avoid visualising turn changes towards units that can't do anything
	{
		UnitRef = RecoveryQueue.PopNextUnitReference();
		UnitState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	}


	if (UnitState.IsGroupLeader() && UnitState.GetGroupMembership() != none) {
		if ( XGUnit(UnitState.GetVisualizer()).GetAlertLevel(UnitState) != eAL_Red )
		{
			foreach UnitState.GetGroupMembership().m_arrMembers(FollowerRef, FollowerIx)
			{
				if (FollowerIx == 0) continue; // this is the leader so ignore
				FollowerState = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(FollowerRef.ObjectID));
				RecoveryQueue.AddFollower(FollowerState);
			}
		}
	}

	`log("Unit Reference Popped: " @ UnitState.ObjectID @ " " @ UnitState.GetMyTemplateName());
	TacticalRules = `TACTICALRULES;
	NewGameState.AddStateObject(RecoveryQueue);
	`log("Group Initiative Interrupting: " @ UnitState.GetGroupMembership().GetReference().ObjectID);
	TacticalRules.InterruptInitiativeTurn(NewGameState, UnitState.GetGroupMembership().GetReference());
	TacticalRules.SubmitGameState(NewGameState);

	`XEVENTMGR.TriggerEvent('RecoveryTurnSystemUpdate', RecoveryQueue);
	return ELR_NoInterrupt;
}


static protected function EventListenerReturn OnUnitGroupTurnBegun(Object EventData, Object EventSource, XComGameState NextGameState, name EventID, Object CallbackData)
{
	local XComGameState_RecoveryQueue RecoveryQueue;
	local XComGameState_AIGroup GroupState;
	local XComGameState_Unit NewUnitState;
	local StateObjectReference UnitRef, FollowerRef;
	local int UnitIx;
	local bool bIsPartOfThisInterrupt;

	GroupState = XComGameState_AIGroup(EventData);
	RecoveryQueue = XComGameState_RecoveryQueue(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_RecoveryQueue'));
	`log("Current Initiative Interrupting: " @ GroupState.ObjectID);
	`log("Current Unit " @ RecoveryQueue.CurrentUnit.UnitRef.ObjectID);

	foreach GroupState.m_arrMembers(UnitRef, UnitIx)
	{
		bIsPartOfThisInterrupt = false;

		`log("Checking Unit " @ UnitRef.ObjectID);
		if (UnitRef.ObjectID == RecoveryQueue.CurrentUnit.UnitRef.ObjectID) {
			bIsPartOfThisInterrupt = true;
		}

		foreach RecoveryQueue.CurrentFollowers(FollowerRef)
		{
			if (UnitRef.ObjectID == FollowerRef.ObjectID) {
				bIsPartOfThisInterrupt = true;
			}
		}

		if (!bIsPartOfThisInterrupt) {
			`log("Stripping action points for unit: " @ UnitRef.ObjectID);
			// strip this units action points
			NewUnitState = XComGameState_Unit(NextGameState.ModifyStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
			NewUnitState.ActionPoints.Length = 0;
			NewUnitState.ReserveActionPoints.Length = 0;
			NewUnitState.SkippedActionPoints.Length = 0;
		} else {
			`log("Retaining action points for unit: " @ UnitRef.ObjectID);
		}
	}

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

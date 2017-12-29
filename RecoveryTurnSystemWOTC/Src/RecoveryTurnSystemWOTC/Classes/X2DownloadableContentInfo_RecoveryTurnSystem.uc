class X2DownloadableContentInfo_RecoveryTurnSystem extends X2DownloadableContentInfo config(Game);

/// Called after the Templates have been created (but before they are validated) while this DLC / Mod is installed.
/// </summary>
static event OnPostTemplatesCreated()
{
	`log("RecoveryTurnSystem :: present and correct");
}


static function AddToTacticalStartState(XComGameState StartState)
{
	local XComGameState_Unit UnitState;
	local bool PartOfTeam;
	local XComGameState_RecoveryQueue QueueState;		
		
	`log("RecoveryTurnSystem :: TacticalStartState");
	QueueState = XComGameState_RecoveryQueue(StartState.CreateStateObject(class'XComGameState_RecoveryQueue'));
	StartState.AddStateObject(QueueState);
	QueueState.InitTurnTime();

	foreach StartState.IterateByClassType(class'XComGameState_Unit', UnitState)
	{
		PartOfTeam = (
			UnitState.GetTeam() == eTeam_XCom ||
			UnitState.GetTeam() == eTeam_TheLost ||
			UnitState.GetTeam() == eTeam_Resistance ||
			UnitState.GetTeam() == eTeam_Alien
		);

		if (!UnitState.GetMyTemplate().bIsCosmetic && PartOfTeam) {
			`log("Adding to queue: " @UnitState.ObjectID);
			QueueState.AddUnitToQueue(UnitState);
		}
	}
}

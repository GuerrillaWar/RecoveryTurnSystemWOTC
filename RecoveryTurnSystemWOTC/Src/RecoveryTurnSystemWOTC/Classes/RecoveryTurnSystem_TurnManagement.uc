// This is an Unreal Script
class RecoveryTurnSystem_TurnManagement extends X2EventListener;

static function array<X2DataTemplate> CreateTemplates()
{
  local array<X2DataTemplate> Templates;

  `log("RecoveryTurnSystem_TurnManagement :: Registering Tactical Event Listeners");

  Templates.AddItem(AddTacticalNextInitiativeOrder());

  return Templates;
}


static function X2EventListenerTemplate AddTacticalCleanupEvent()
{
  local X2EventListenerTemplate Template;

	`CREATE_X2TEMPLATE(class'X2EventListenerTemplate', Template, 'RecoveryTurnSystem_NextInitiativeGroup');

	Template.RegisterInTactical = true;
	Template.AddEvent('NextInitiativeGroup', OnNextInitiativeGroup);

	return Template;
}


static protected function EventListenerReturn OnNextInitiativeGroup(Object EventData, Object EventSource, XComGameState GivenGameState, name EventID, Object CallbackData)
{
	`log("RecoveryTurnSystem :: NextInitiativeGroup");
	return ELR_NoInterrupt;
}

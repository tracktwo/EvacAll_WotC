
/* X2Action_NoEvacTiles: An "action" for visualizing the blocked tiles in an evac zone. */

class X2Action_NoEvacTiles extends X2Action;

var XComGameState_NoEvacTiles NoEvacTilesState;

function Init()
{
	super.Init();

	NoEvacTilesState = XComGameState_NoEvacTiles(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_NoEvacTiles'));
}

simulated state Executing
{
Begin:
	NoEvacTilesState.FindOrCreateVisualizer();
	NoEvacTilesState.SyncVisualizer();
	CompleteAction();
}


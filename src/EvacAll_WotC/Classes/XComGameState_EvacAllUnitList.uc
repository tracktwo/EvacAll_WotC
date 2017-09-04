/*
 * XComGameState_EvacAllUnitList
 *
 * A game state to record all the units that have a deferred evac so they can be visualized in the
 * same frame as the initial evac (e.g. of a soldier carrying a VIP) despite their actual evac state
 * change occuring in a much later state after all the kismet actions associated with that original evac
 * have been processed.
 */
class XComGameState_EvacAllUnitList extends XComGameState_BaseObject;

// The list of unit references we'll visualize in this evac.
var array<StateObjectReference> UnitsToVisualize;

defaultproperties
{
	bTacticalTransient = true
}


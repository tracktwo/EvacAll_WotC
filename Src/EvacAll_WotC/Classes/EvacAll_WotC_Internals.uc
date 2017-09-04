
/*
 * EvacAll_WotC_Internals
 *
 * Contains config options not useful for players and not exposed through the Mod Config Menu.
 * Internal options that may be of use to other modders or for inter-mod compatibility.
 */
class EvacAll_WotC_Internals extends Object config(EvacAll_WotC_Internals);

// List of 'important' template names. Any soldiers carrying a unit of one of these types
// is evacuated before the rest of the squad in a separate state submission. This lets kismet
// process the evac while other units are still on the ground.
var config array<Name> ImportantCharacterTemplates;


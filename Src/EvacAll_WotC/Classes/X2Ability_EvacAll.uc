class X2Ability_EvacAll extends X2Ability;

`include(EvacAll_WotC/Src/ModConfigMenuAPI/MCM_API_CfgHelpers.uci)

`MCM_CH_VersionChecker(class'EvacAll_WotC_Defaults'.default.Version, class'UIScreenListener_EvacAll_MCM'.default.Version)

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	Templates.AddItem(EvacAllAbility());
	return Templates;
}

static function X2AbilityTemplate EvacAllAbility()
{
	local X2AbilityTemplate             Template;
	local X2AbilityCost_ActionPoints    ActionPointCost;
	local X2AbilityTrigger_PlayerInput  PlayerInput;
	local X2Condition_UnitValue         UnitValue;
	local X2Condition_UnitProperty      UnitProperty;
	local array<name>                   SkipExclusions;

	`CREATE_X2ABILITY_TEMPLATE(Template, 'EvacAll');

	Template.RemoveTemplateAvailablility(Template.BITFIELD_GAMEAREA_Multiplayer); // Do not allow "Evac All" in MP!

	Template.Hostility = eHostility_Neutral;

	Template.eAbilityIconBehaviorHUD = eAbilityIconBehavior_ShowIfAvailable;
	Template.ShotHUDPriority = class'UIUtilities_Tactical'.const.PLACE_EVAC_PRIORITY;
	Template.IconImage = "img:///UI_EvacAll.UIPerk_evac_all";
	Template.AbilitySourceName = 'eAbilitySource_Commander';
	Template.bAllowedByDefault = true;

	// Allow anyone to evac.
	SkipExclusions.AddItem(class'X2Ability_CarryUnit'.default.CarryUnitEffectName);
	SkipExclusions.AddItem(class'X2AbilityTemplateManager'.default.DisorientedName);
	SkipExclusions.AddItem(class'X2StatusEffects'.default.BurningName);
	Template.AddShooterEffectExclusions(SkipExclusions);

	UnitProperty = new class'X2Condition_UnitProperty';
	UnitProperty.ExcludeDead = true;
	UnitProperty.ExcludeFriendlyToSource = false;
	UnitProperty.ExcludeHostileToSource = true;
	Template.AbilityShooterConditions.AddItem(UnitProperty);

	Template.AbilityToHitCalc = default.DeadEye;

	Template.AbilityTargetStyle = default.SelfTarget;
	PlayerInput = new class'X2AbilityTrigger_PlayerInput';
	Template.AbilityTriggers.AddItem(PlayerInput);

	// Only allow when evac is allowed.
	UnitValue = new class'X2Condition_UnitValue';
	UnitValue.AddCheckValue(class'X2Ability_DefaultAbilitySet'.default.EvacThisTurnName, class'X2Ability_DefaultAbilitySet'.default.MAX_EVAC_PER_TURN, eCheck_LessThan);
	Template.AbilityShooterConditions.AddItem(UnitValue);
	Template.AbilityShooterConditions.AddItem(new class'X2Condition_UnitInEvacZone');

	ActionPointCost = new class'X2AbilityCost_ActionPoints';
	ActionPointCost.iNumPoints = 0;
	ActionPointCost.bFreeCost = true;
	Template.AbilityCosts.AddItem(ActionPointCost);

	Template.BuildNewGameStateFn = EvacAll_BuildGameState;
	Template.BuildVisualizationFn = EvacAll_BuildVisualization;
	Template.bDontDisplayInAbilitySummary = true;

	//Template.AddAbilityEventListener('EvacAllActivated', EvacAllActivated, ELD_OnStateSubmitted);

	return Template;
}

function bool CanEvac(XComGameState_Unit Unit)
{
	local XComGameState_Ability AbilityState;
	local StateObjectReference AbilityRef;

	AbilityRef = Unit.FindAbility('Evac');
	AbilityState = XComGameState_Ability(`XCOMHISTORY.GetGameStateForObjectID(AbilityRef.ObjectID));

	return AbilityState != none && AbilityState.CanActivateAbility(Unit) == 'AA_Success';
}

function int CarryingImportantUnitId(XComGameState_Unit Unit)
{
	local XComGameState_Effect CarryEffect;
	local XComGameState_Unit TestUnit;
	local XComGameStateHistory History;

	History = `XCOMHISTORY;

	foreach History.IterateByClassType(class'XComGameState_Unit', TestUnit)
	{
		CarryEffect = TestUnit.GetUnitAffectedByEffectState(class'X2AbilityTemplateManager'.default.BeingCarriedEffectName);
		if (CarryEffect != None && CarryEffect.ApplyEffectParameters.SourceStateObjectRef.ObjectID == Unit.ObjectID)
		{
			if (class'EvacAll_WotC_Internals'.default.ImportantCharacterTemplates.Find(TestUnit.GetMyTemplateName()) >= 0)
			{
				return CarryEffect.ApplyEffectParameters.TargetStateObjectRef.ObjectID;
			}
		}
	}

	return -1;
}

simulated function XComGameState EvacAll_BuildGameState(XComGameStateContext Context)
{
	local XComGameStateHistory History;
	local XComGameState_Unit Unit;
	local array<XComGameState_Unit> EligibleUnits;
	local XComGameState NewGameState;
	local XComGameState_EvacAllUnitList UnitList;
	local Object ThisObj;
	local bool TriggerEvent;
	local bool FoundCarryingUnit;
	local int VIPId;

	History = `XCOMHISTORY;

	TriggerEvent = true;
	ThisObj = self;

	NewGameState = History.CreateNewGameState(true, Context);

	// Pass 1: Iterate all units and figure out who is eligible to evac. Also check each unit
	// to see if they're carrying someone. If so, we need to split the state into two pieces to
	// work around the VIP bug.
	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (!Unit.bRemovedFromPlay && CanEvac(Unit))
		{
			EligibleUnits.AddItem(Unit);
			VIPId = CarryingImportantUnitId(Unit);
			if (VIPId >= 0)
			{
				FoundCarryingUnit = true;
				// Put the VIP unit first in the game state so that kismet will process this unit first.
				// Ideally this is all we'd need to do, and the mission scripts would see the VIP extracting first
				// in this state and mark the objective as complete. Unfortunately this isn't enough for neutralize
				// target: it sees the VIP first and marks the objective as complete, but then when it hits the other
				// units it thinks there is nobody left to evac it because it checks only the VIP unit's state and not
				// the kismet variable that was set by the VIP being extracted. Until the script does that, we need to
				// divide the evac into two distinct state submissions.
				NewGameState.ModifyStateObject(class'XComGameState_Unit', VIPId);
			}
		}
	}

	// Pass 2 over eligible units: If we have anyone carrying a unit, evac them.
	// Everyone else will wait for a second pass after this state is submitted so Kismet can process the
	// VIP being removed while other soldiers are still on the ground or the mission objectives may incorrectly
	// be reported as failed.
	foreach EligibleUnits(Unit)
	{
		if (!FoundCarryingUnit)
		{
			if (TryToEvacUnit(Unit, TriggerEvent, NewGameState))
			{
				TriggerEvent = false;
			}
		}
		else
		{
			if (CarryingImportantUnitId(Unit) >= 0)
			{
				if (TryToEvacUnit(Unit, TriggerEvent, NewGameState))
				{
					TriggerEvent = false;
				}
			}
			else
			{
				// This unit will evac, but not in this state frame. Record them so they can be visualized with this
				// frame, though.
				if (UnitList == none)
				{
					UnitList = XComGameState_EvacAllUnitList(NewGameState.CreateNewStateObject(class'XComGameState_EvacAllUnitList'));
				}

				UnitList.UnitsToVisualize.AddItem(Unit.GetReference());
			}
		}
	}

	if (FoundCarryingUnit)
	{
		// At least one unit was found carrying another. Only the carrying units have been evacuated, so
		// trigger an event to let us evac the rest of the squad after the fact.
		`XEVENTMGR.RegisterForEvent(ThisObj, 'EvacAllCarryingUnitEvaced', OnCarryingUnitEvaced, ELD_OnStateSubmitted);
		`XEVENTMGR.TriggerEvent('EvacAllCarryingUnitEvaced', Unit, Unit, NewGameState);
	}

	return NewGameState;
}


// Helper to finish up evacing other units after the ones carrying units have been processed.
function EventListenerReturn OnCarryingUnitEvaced(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local XComGameStateHistory History;
	local XComGameState_Unit GameStateUnit;
	local Object ThisObj;
	local bool TriggerEvent;

	TriggerEvent = true;

	History = `XCOMHISTORY;
	ThisObj = self;
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Evac All Cleanup");

	// Go over all remaining units and try to evac anyone left.
	foreach History.IterateByClassType(class'XComGameState_Unit', GameStateUnit)
	{
		if (GameStateUnit.bRemovedFromPlay)
		{
			continue;
		}

		// Fire off another evac event for this game state as well to ensure the 'evac activated'
		// kismet events are handled for this second group of evacuations.
		if (TryToEvacUnit(GameStateUnit, TriggerEvent, NewGameState))
		{
			TriggerEvent = false;
		}
	}

	if (NewGameState.GetNumGameStateObjects() > 0)
	{
		`TACTICALRULES.SubmitGameState(NewGameState);
	}
	else
	{
		History.CleanupPendingGameState(NewGameState);
	}

	`XEVENTMGR.UnRegisterFromEvent(ThisObj, 'EvacAllCarryingUnitEvaced');
	return ELR_NoInterrupt;
}

function bool TryToEvacUnit(XComGameState_Unit Unit, bool TriggerEvent, XComGameState NewGameState)
{
	local XComGameState_Ability AbilityState;
	local StateObjectReference AbilityRef;

	if (CanEvac(Unit))
	{
		AbilityRef = Unit.FindAbility('Evac');
		AbilityState = XComGameState_Ability(`XCOMHISTORY.GetGameStateForObjectID(AbilityRef.ObjectID));
		DoOneEvac(NewGameState, Unit, AbilityState, TriggerEvent);
		return true;
	}

	return false;
}

simulated function DoOneEvac(XComGameState NewGameState, XComGameState_Unit UnitState, XComGameState_Ability AbilityState, bool TriggerEvent)
{
	local XComGameState_Unit NewUnitState;

	NewUnitState = XComGameState_Unit(NewGameState.CreateStateObject(UnitState.Class, UnitState.ObjectID));
	if (TriggerEvent)
	{
		`XEVENTMGR.TriggerEvent('EvacActivated', AbilityState, NewUnitState, NewGameState);
	}

	NewUnitState.EvacuateUnit(NewGameState);
	NewGameState.AddStateObject(NewUnitState);
}

function bool UnitInList(StateObjectReference UnitRef, array<XComGameState_Unit> UnitList)
{
	local XComGameState_Unit Unit;

	foreach UnitList(Unit)
	{
		if (Unit.ObjectID == UnitRef.ObjectID)
		{
			return true;
		}
	}

	return false;
}

simulated function EvacAll_BuildVisualization(XComGameState VisualizeGameState)
{
	local XComGameStateHistory          History;
	local XComGameState_Unit            GameStateUnit;
	local VisualizationActionMetadata	ActionMetadata;
	local VisualizationActionMetadata	EmptyMetadata;
	local VisualizationActionMetadata	CarriedMetadata;
	local X2Action_PlaySoundAndFlyOver  SoundAndFlyover;
	local name                          nUnitTemplateName;
	local bool                          bIsVIP;
	local bool                          bNeedVIPVoiceover;
	local XComGameState_Unit            SoldierToPlayVoiceover;
	local array<XComGameState_Unit>     HumanPlayersUnits;
	local XComGameState_Effect          CarryEffect;
	local X2Action						LastAction;
	local X2Action_MarkerNamed			MarkerAction;
	local array<XComGameState_Unit>		UnitsToProcess;
	local XComGameState_EvacAllUnitList UnitList;
	local StateObjectReference          UnitRef;

	// Insta-vac if the user has requested no anims
	if (`MCM_CH_GetValue(class'EvacAll_WotC_Defaults'.default.DisableEvacAnimation, class'UIScreenListener_EvacAll_MCM'.default.DisableEvacAnimation))
	{
		EvacAll_BuildEmptyVisualization(VisualizeGameState);
		return;
	}

	History = `XCOMHISTORY;

	// Add all units that actually evacuated in this frame to our list
	foreach VisualizeGameState.IterateByClassType(class'XComGameState_Unit', GameStateUnit)
	{
		UnitsToProcess.AddItem(GameStateUnit);
	}

	// Look for additional units that should be visualized as evacuating, but which are not yet
	// done in this state.
	foreach VisualizeGameState.IterateByClassType(class'XComGameState_EvacAllUnitList', UnitList)
	{
		foreach UnitList.UnitsToVisualize(UnitRef)
		{
			if (!UnitInList(UnitRef, UnitsToProcess))
			{
				UnitsToProcess.AddItem(XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID)));
			}
		}
	}

	//Decide on which VO cue to play, and which unit says it
	foreach UnitsToProcess(GameStateUnit)
	{
		nUnitTemplateName = GameStateUnit.GetMyTemplateName();
		switch(nUnitTemplateName)
		{
		case 'Soldier_VIP':
		case 'Scientist_VIP':
		case 'Engineer_VIP':
		case 'FriendlyVIPCivilian':
		case 'HostileVIPCivilian':
		case 'CommanderVIP':
		case 'Engineer':
		case 'Scientist':
			bIsVIP = true;
			break;
		default:
			bIsVIP = false;
		}

		if (bIsVIP)
		{
			bNeedVIPVoiceover = true;
		}
		else
		{
			if (SoldierToPlayVoiceover == None)
				SoldierToPlayVoiceover = GameStateUnit;
		}
	}

	// Create a marker action to act as the parent of all evac visualizations so we can have them all processing
	// in parallel rather than in sequence.
	MarkerAction = X2Action_MarkerNamed(class'X2Action_MarkerNamed'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	MarkerAction.SetName("EvacAll");

	//Build tracks for each evacuating unit. Note that not all of these units may have actually evac'd yet, but we are
	// visualizing them evacing here. They'll be evac'd by the followup code that triggers after this state is completed.
	foreach UnitsToProcess(GameStateUnit)
	{
		LastAction = MarkerAction;

		//Start their track
		ActionMetadata = EmptyMetadata;
		ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(GameStateUnit.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
		ActionMetadata.StateObject_NewState = VisualizeGameState.GetGameStateForObjectID(GameStateUnit.ObjectID);
		ActionMetadata.VisualizeActor = History.GetVisualizer(GameStateUnit.ObjectID);

		//Add this potential flyover (does this still exist in the game?)
		class'XComGameState_Unit'.static.SetUpBuildTrackForSoldierRelationship(ActionMetadata, VisualizeGameState, GameStateUnit.ObjectID);

		//Play the VO if this is the soldier we picked for it
		if (SoldierToPlayVoiceover == GameStateUnit)
		{
			SoundAndFlyOver = X2Action_PlaySoundAndFlyover(class'X2Action_PlaySoundAndFlyover'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, LastAction));
			if (bNeedVIPVoiceover)
			{
				SoundAndFlyOver.SetSoundAndFlyOverParameters(None, "", 'VIPRescueComplete', eColor_Good);
				bNeedVIPVoiceover = false;
			}
			else
			{
				SoundAndFlyOver.SetSoundAndFlyOverParameters(None, "", 'EVAC', eColor_Good);
			}

			LastAction = SoundAndFlyOver;
		}

		//Note: AFFECTED BY effect state (being carried)
		CarryEffect = XComGameState_Unit(ActionMetadata.StateObject_OldState).GetUnitAffectedByEffectState(class'X2AbilityTemplateManager'.default.BeingCarriedEffectName);
		if (CarryEffect == None)
		{
			class'X2Action_DelayedEvac'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, LastAction); //Not being carried - rope out
			//Hide the pawn explicitly now - in case the vis block doesn't complete immediately to trigger an update
			class'X2Action_RemoveUnit'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded);

			// We're not being carried, but check if we're carrying someone else.
			CarryEffect = XComGameState_Unit(ActionMetadata.StateObject_OldState).GetUnitAffectedByEffectState(class'X2Ability_CarryUnit'.default.CarryUnitEffectName);
			if (CarryEffect != none)
			{
				// Hide the pawn being carried in this subtree.
				CarriedMetadata = EmptyMetadata;
				CarriedMetadata.StateObject_OldState = History.GetGameStateForObjectID(CarryEffect.ApplyEffectParameters.TargetStateObjectRef.ObjectID);
				CarriedMetadata.StateObject_NewState = VisualizeGameState.GetGameStateForObjectID(CarryEffect.ApplyEffectParameters.TargetStateObjectRef.ObjectID);
				CarriedMetadata.VisualizeActor = History.GetVisualizer(CarryEffect.ApplyEffectParameters.TargetStateObjectRef.ObjectID);
				class'X2Action_RemoveUnit'.static.AddToVisualizationTree(CarriedMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded);
			}
		}
	}

	//If a VIP evacuated alone, we may need to pick an (arbitrary) other soldier on the squad to say the VO line about it.
	if (bNeedVIPVoiceover)
	{
		XGBattle_SP(`BATTLE).GetHumanPlayer().GetUnits(HumanPlayersUnits);
		foreach HumanPlayersUnits(GameStateUnit)
		{
			if (GameStateUnit.IsSoldier() && !GameStateUnit.IsDead() && !GameStateUnit.bRemovedFromPlay)
			{
				ActionMetadata = EmptyMetadata;
				ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(GameStateUnit.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
				ActionMetadata.StateObject_NewState = ActionMetadata.StateObject_OldState;
				ActionMetadata.VisualizeActor = History.GetVisualizer(GameStateUnit.ObjectID);

				SoundAndFlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyover'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
				SoundAndFlyOver.SetSoundAndFlyOverParameters(None, "", 'VIPRescueComplete', eColor_Good);
				break;
			}
		}
	}
}


function EvacAll_BuildEmptyVisualization(XComGameState VisualizeGameState)
{
	local XComGameStateHistory History;
	local XComGameStateContext_Ability  Context;
	local StateObjectReference          InteractingUnitRef;
	local XComGameState_Ability         Ability;
	local VisualizationActionMetadata   ActionMetadata;
	local X2Action_PlaySoundAndFlyOver SoundAndFlyOver;

	History = `XCOMHISTORY;

	Context = XComGameStateContext_Ability(VisualizeGameState.GetContext());
	InteractingUnitRef = Context.InputContext.SourceObject;

	ActionMetadata.StateObject_OldState = History.GetGameStateForObjectID(InteractingUnitRef.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1);
	ActionMetadata.StateObject_NewState = VisualizeGameState.GetGameStateForObjectID(InteractingUnitRef.ObjectID);
	ActionMetadata.VisualizeActor = History.GetVisualizer(InteractingUnitRef.ObjectID);

	Ability = XComGameState_Ability(History.GetGameStateForObjectID(Context.InputContext.AbilityRef.ObjectID, eReturnType_Reference, VisualizeGameState.HistoryIndex - 1));
	SoundAndFlyOver = X2Action_PlaySoundAndFlyOver(class'X2Action_PlaySoundAndFlyOver'.static.AddToVisualizationTree(ActionMetadata, VisualizeGameState.GetContext(), false, ActionMetadata.LastActionAdded));
	SoundAndFlyOver.SetSoundAndFlyOverParameters(None, Ability.GetMyTemplate().LocFlyOverText, '', eColor_Good);
}


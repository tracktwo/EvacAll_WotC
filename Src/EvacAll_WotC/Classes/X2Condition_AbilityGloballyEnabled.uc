class X2Condition_AbilityGloballyEnabled extends X2Condition;

var Name AbilityName;

event name CallMeetsCondition(XComGameState_BaseObject kTarget)
{
	local XComGameStateHistory History;
	local XComGameState_BattleData BattleData;

	History = `XCOMHISTORY;
	BattleData = XComGameState_BattleData(History.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));

	if (BattleData.IsAbilityGloballyDisabled(AbilityName))
	{
		return 'AA_AbilityUnavailable';
	}
	else
	{
		return 'AA_Success';
	}
}


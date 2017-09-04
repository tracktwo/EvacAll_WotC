class UIScreenListener_EvacAll_MCM extends UIScreenListener config(EvacAll_WotC);

`include(EvacAll_WotC/Src/ModConfigMenuAPI/MCM_API_Includes.uci)
`include(EvacAll_WotC/Src/ModConfigMenuAPI/MCM_API_CfgHelpers.uci)

var config bool DisableEvacAnimation;
var config bool DisableNoEvacTiles;

var localized string PageTitle;
var localized string GeneralSettingsTitle;
var localized string DisableEvacAnimationTitle;
var localized string DisableEvacAnimationTooltip;
var localized string DisableNoEvacTilesTitle;
var localized string DisableNoEvacTilesTooltip;


var config int Version;

`MCM_CH_VersionChecker(class'EvacAll_WotC_Defaults'.default.Version, Version);

event OnInit(UIScreen Screen)
{
	if (MCM_API(Screen) != none)
	{
		`MCM_API_Register(Screen,EvacAllMCMCallback);
	}
}

simulated function LoadSavedSettings()
{
	DisableEvacAnimation = `MCM_CH_GetValue(class'EvacAll_WotC_Defaults'.default.DisableEvacAnimation, DisableEvacAnimation);
	DisableNoEvacTiles = `MCM_CH_GetValue(class'EvacAll_WotC_Defaults'.default.DisableNoEvacTiles, DisableNoEvacTiles);

}

simulated function EvacAllMCMCallback(MCM_API_Instance ConfigAPI, int GameMode)
{
	local MCM_API_SettingsPage Page;
	local MCM_API_SettingsGroup Group;

	LoadSavedSettings();

	Page = ConfigAPI.NewSettingsPage(PageTitle);
	Page.SetPageTitle(PageTitle);
	Page.SetSaveHandler(SaveButtonClicked);

	Group = Page.AddGroup('Group1', GeneralSettingsTitle);
	Group.AddCheckBox('checkbox', DisableEvacAnimationTitle, DisableEvacAnimationTooltip, DisableEvacAnimation, DisableEvacAnimationSaveHandler);
	Group.AddCheckBox('checkbox', DisableNoEvacTilesTitle, DisableNoEvacTilesTooltip, DisableNoEvacTiles, DisableNoEvacTilesSaveHandler);

	Page.ShowSettings();
}

simulated function SaveButtonClicked(MCM_API_SettingsPage Page)
{
	self.Version = `MCM_CH_GetCompositeVersion();
	self.SaveConfig();
}

`MCM_API_BasicCheckboxSaveHandler(DisableEvacAnimationSaveHandler, DisableEvacAnimation)
`MCM_API_BasicCheckboxSaveHandler(DisableNoEvacTilesSaveHandler, DisableNoEvacTiles)

defaultproperties
{
	ScreenClass=none
}

/* 
 * MicroTF2 2014 Edition
 * Copyright (C) 2010 - 2015 StSv.TF productions, in association with GEMINI Developments.
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>
#include <smlib>
#include <training>

#undef REQUIRE_PLUGIN
//#include <Framework>

#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS

#define NEW_HUD
//#define UMC_MAPCHOOSER

#include <sdkhooks>
#include <soundlib>
#include <steamtools>
#include <tf2items>


#if defined UMC_MAPCHOOSER
#include <umc-core>
#else
#include <mapchooser>
#endif

/**
 * Defines
 */
//#define DEBUG
#define PLUGIN_VERSION "2018.8A"
#define PLUGIN_PREFIX "\x0700FFFF[ \x07FFFF00MicroTF2 \x0700FFFF] {default}"

#include Header.inc
#include Forwards.inc
#include Weapons.inc
#include System.inc
#include MinigameSystem.inc
#include PrecacheSystem.inc
#include SecuritySystem.inc
#include Events.inc
#include SpecialRounds.inc
#include Internal.inc
#include Stocks.inc
#include Commands.inc
#include InternalWebAPI.inc

public Plugin:myinfo = 
{
	name = "MicroTF2",
	author = "GEMINI Developments",
	description = "Yet another WarioWare gamemode for Team Fortress 2",
	version = PLUGIN_VERSION,
	url = "http://www.gemini.software/"
}

public OnPluginStart()
{
	// Do our pre-requisite checks

#if defined FIXED_IP
	new hostIP = GetConVarInt(FindConVar("hostip"));
	if (hostIP != FIXED_IP)
	{
		SetFailState("This server has not been authorized to run MicroTF2.");
	}
#endif

	decl String:gameFolder[32];
	GetGameFolderName(gameFolder, sizeof(gameFolder));

	if (!StrEqual(gameFolder, "tf"))
	{
		SetFailState("MicroTF2 can only be run on Team Fortress 2.");
	}

	if (GetExtensionFileStatus("sdkhooks.ext") < 1) 
	{
		SetFailState("The SDKHooks Extension is not loaded.");
	}

	if (GetExtensionFileStatus("tf2items.ext") < 1)
	{
		SetFailState("The TF2Items Extension is not loaded.");
	}

	if (GetExtensionFileStatus("steamtools.ext") < 1)
	{
		SetFailState("The SteamTools Extension is not loaded.");
	}

	if (GetExtensionFileStatus("soundlib.ext") < 1)
	{
		SetFailState("The SoundLib Extension is not loaded.");
	}

	LoadTranslations("microtf2.phrases.txt");

	Offset_Collision = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");

	HookEvents();
	CreateWeaponTrie();
	InitializeSystem();
}

public OnMapStart()
{
	if (IsMicroTF2Map())
	{
		Steam_SetGameDescription("WarioWare (MicroTF2)");

		CreateTimer(120.0, GamemodeAdvertisement, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);

		PrepareConVars();

		new playerManagerEntity = FindEntityByClassname(MaxClients+1, "tf_player_manager");
		if (playerManagerEntity == -1)
		{
			SetFailState("Unable to find tf_player_manager entity");
		}
		else
		{
			SDKHook(playerManagerEntity, SDKHook_ThinkPost, Hook_Scoreboard);
		}

		AddNormalSoundHook(Hook_GameSound);

		if (GlobalForward_OnMapStart != INVALID_HANDLE)
		{
			Call_StartForward(GlobalForward_OnMapStart);
			Call_Finish();
		}
		else
		{
			SetFailState("MicroTF2 failed to initialise: ForwardSystem failed to start.");
		}
	}
	else
	{
		UnloadPlugin();
	}
}

public Action:Timer_GameLogic_EngineInitialisation(Handle:timer)
{
	GamemodeStatus = GameStatus_Playing;
	SetMinigameCaptionForAll("NOW LOADING...");

	CreateTimer(2.0, Timer_GameLogic_PrepareForMinigame);
}

public Action:Timer_GameLogic_PrepareForMinigame(Handle:timer)
{
	if (GamemodeStatus != GameStatus_Playing)
	{
		ResetGamemode();
		return Plugin_Stop;
	}

	GamemodeStatus = GameStatus_Playing;

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Timer_GameLogic_PrepareForMinigame");
	#endif

	if (!IsBonusRound)
	{
		SetSpeed_SpecialRound();
	}
	SetSpeed();

	ShowPlayerScores(true);
	SpecialRound_SetupEnv();

	new String:centerText[4096];

	if (SpecialRoundID == 16)
	{
		ScoreAmount = GetRandomInt(2, 14);
		Format(centerText, sizeof(centerText), "If you win this minigame, you will be awarded \"%d\" points!", ScoreAmount);
	}
	else if (SpecialRoundID == 17)
	{
		ScoreAmount = (MinigamesPlayed >= BossGameThreshold ? 5 : 1);

		new String:names[2048];
		new currentPlayers = 0;
		new maxPlayers = 0;

		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientValid(i))
			{
				maxPlayers++;

				if (IsPlayerParticipant[i])
				{
					if (currentPlayers < 7)
					{
						Format(names, sizeof(names), "%s%N\n", names, i);
					}
					else if (currentPlayers == 7)
					{
						Format(names, sizeof(names), "%s - Plus %d More - ", names, (maxPlayers - 7));
					}

					currentPlayers++;
				}
			}
		}

		Format(centerText, sizeof(centerText), "Current Players (%d of %d)\n%s", currentPlayers, maxPlayers, names);
	}
	else
	{
		ScoreAmount = (MinigamesPlayed >= BossGameThreshold ? 5 : 1);
		centerText = "";
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Preparing to choose minigame");
	#endif

	if (MinigamesPlayed >= BossGameThreshold)
	{
		new i = 0;
		do
		{
			BossgameID = GetRandomInt(1, BossgamesLoaded);

			if (BossgamesLoaded == 1)
			{
				PreviousBossgameID = 0;
			}

			decl String:funcName[64];
			Format(funcName, sizeof(funcName), "Bossgame%i_OnCheck", BossgameID);
			new Function:func = GetFunctionByName(INVALID_HANDLE, funcName);

			if (func != INVALID_FUNCTION)
			{
				new bool:isPlayable = false;

				Call_StartFunction(INVALID_HANDLE, func);
				Call_Finish(isPlayable);

				if (!isPlayable)
				{
					BossgameID = PreviousBossgameID;
				}

				if (i > 20)
				{
					// This fixes a crash.
					PreviousBossgameID = 0;
				}
			}

			i++;
		}
		while (BossgameID == PreviousBossgameID);
	}
	else
	{
		if (SpecialRoundID == 8)
		{
			PreviousMinigameID = 0;
			MinigameID = 8;
		}
		else
		{
			new i = 0;
			do
			{
				MinigameID = GetRandomInt(1, MinigamesLoaded);

				if (MinigamesLoaded == 1)
				{
					PreviousMinigameID = 0;
				}

				decl String:funcName[64];
				Format(funcName, sizeof(funcName), "Minigame%i_OnCheck", MinigameID);
				new Function:func = GetFunctionByName(INVALID_HANDLE, funcName);

				if (func != INVALID_FUNCTION)
				{
					new bool:isPlayable = false;

					Call_StartFunction(INVALID_HANDLE, func);
					Call_Finish(isPlayable);

					if (!isPlayable)
					{
						MinigameID = PreviousMinigameID;
					}

					if (i > 20)
					{
						// This fixes a crash.
						PreviousMinigameID = 1;
					}
				}

				i++;
			}
			while (MinigameID == PreviousMinigameID);
		}
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Minigame chosen. Preparing clients");
	#endif

	new Float:duration = SystemMusicLength[GamemodeID][SYSMUSIC_PREMINIGAME];

	if (GamemodeID == SPR_GAMEMODEID && SpecialRoundID == 20)
	{
		duration = 0.05;
	}

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (!IsPlayerAlive(i))
			{
				TF2_RespawnPlayer(i);
			}

			if (!IsPlayerParticipant[i] && SpecialRoundID != 17)
			{
				// If not a participant, and not Sudden Death, then they should now be a participant.
				IsPlayerParticipant[i] = true;
			}

			ResetWeapon(i, false);
			IsPlayerCollisionsEnabled(i, true);
			IsGodModeEnabled(i, true);
			ResetHealth(i);

			Client_RemoveAllDecals(i);

			SetEntityGravity(i, 1.0);
			SetEntProp(i, Prop_Send, "m_bGlowEnabled", 0);

			PlayerStatus[i] = PlayerStatus_NotWon;
			SetupSPR(i);

			PrintCenterText(i, centerText);

			if (duration >= 1.0)
			{
				DisplayOverlayToClient(i, OVERLAY_BLANK);
				PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_PREMINIGAME]);

				if (SpecialRoundID != 12)
				{
					decl String:score[32];
					Format(score, sizeof(score), "%d POINTS", PlayerScore[i]);
					ShowAnnotation(i, duration, score);
				}
			}
		}
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Clients ready. Creating timer for Timer_GameLogic_StartMinigame");
	#endif

	CreateTimer(duration, Timer_GameLogic_StartMinigame);
	
	return Plugin_Handled;
}

public Action:Timer_GameLogic_StartMinigame(Handle:timer)
{
	if (GamemodeStatus != GameStatus_Playing)
	{
		ResetGamemode();
		return Plugin_Stop;
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Timer_GameLogic_StartMinigame called - Starting Forward Calls for OnMinigameSelectedPre");
	#endif

	if (GlobalForward_OnMinigameSelectedPre != INVALID_HANDLE)
	{
		Call_StartForward(GlobalForward_OnMinigameSelectedPre);
		Call_Finish();
	}

	if (SpecialRoundID == 7 && BossgameID > 0)
	{
		SpeedLevel = 0.7;
	}

	UpdatePlayerIndexes();

	SetSpeed();
	ShowPlayerScores(true);
	SpecialRound_SetupEnv();

	IsMinigameActive = true;

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Preparing clients..");
	#endif

	new bool:isCaptionDynamic;
	new Function:func = INVALID_FUNCTION;

	if (MinigameCaptionIsDynamic[MinigameID] || BossgameCaptionIsDynamic[BossgameID])
	{
		isCaptionDynamic = true;
	}

	if (isCaptionDynamic)
	{
		decl String:funcName[64];

		if (MinigameID > 0)
		{
			funcName = MinigameDynamicCaptionFunctions[MinigameID];
		}
		else if (BossgameID > 0)
		{
			funcName = BossgameDynamicCaptionFunctions[MinigameID];
		}

		func = GetFunctionByName(INVALID_HANDLE, funcName);

		if (func == INVALID_FUNCTION)
		{
			LogError("Unable to find function \"%s\".", funcName);
		}
	}

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			SetupSPR(i);

			if (BossgameID > 0) 
			{
				if (!isCaptionDynamic)
				{
					decl String:objective[64];
					Format(objective, sizeof(objective), BossgameCaptions[BossgameID]);

					strcopy(MinigameCaption[i], MINIGAME_CAPTION_LENGTH, BossgameCaptions[BossgameID]);

					DisplayHudMessageToClient(i, objective, "", 5.0);
				}

				PlaySoundToPlayer(i, BossgameMusic[BossgameID]);
			}
			else if (MinigameID > 0)
			{
				strcopy(MinigameCaption[i], MINIGAME_CAPTION_LENGTH, MinigameCaptions[MinigameID]);

				if (!isCaptionDynamic)
				{
					decl String:objective[64];
					Format(objective, sizeof(objective), MinigameCaptions[MinigameID]);
					DisplayHudMessageToClient(i, objective, "", 3.0);
				}

				PlaySoundToPlayer(i, MinigameMusic[MinigameID]);
				PlaySoundToPlayer(i, SYSFX_CLOCK);
			}

			if (IsPlayerParticipant[i])
			{
				DisplayOverlayToClient(i, OVERLAY_BLANK);

				if (isCaptionDynamic)
				{
					Call_StartFunction(INVALID_HANDLE, func);
					Call_PushCell(i);
					Call_Finish();
				}

				if (GlobalForward_OnMinigameSelected != INVALID_HANDLE)
				{
					Call_StartForward(GlobalForward_OnMinigameSelected);
					Call_PushCell(i);
					Call_Finish();
				}
			}
			else
			{
				DisplayOverlayToClient(i, OVERLAY_BLANK);
			}
		}
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Clients prepared - calling post forward..");
	#endif

	if (GlobalForward_OnMinigameSelectedPost != INVALID_HANDLE)
	{
		Call_StartForward(GlobalForward_OnMinigameSelectedPost);
		Call_Finish();
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Forward called. Creating Timers for Timer_GameLogic_EndMinigame and OnPreFinish");
	#endif

	if (MinigameID > 0)
	{
		CreateTimer(MinigameMusicLength[MinigameID], Timer_GameLogic_EndMinigame);
		CreateTimer((MinigameMusicLength[MinigameID] - 0.5), Timer_GameLogic_OnPreFinish);
	}
	else if (BossgameID > 0)
	{
		Handle_ActiveGameTimer = CreateTimer(BossgameLength[BossgameID], Timer_GameLogic_EndMinigame);
		CreateTimer(10.0, Timer_RemoveBossOverlay);
		Handle_BossCheckTimer = CreateTimer(5.0, Timer_CheckBossEnd);
	}
	else
	{
		#if defined DEBUG
		PrintToChatAll("[DEBUG] MinigameID and BossgameID are 0, what the fuck do I do?");
		#endif
	}

	return Plugin_Handled;
}

public Action:Timer_GameLogic_EndMinigame(Handle:timer)
{
	IsMinigameEnding = true;

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Timer_GameLogic_EndMinigame called. Calling OnMinigameFinish forward.");
	#endif

	SetSpeed();
	ShowPlayerScores(true);

	if (GlobalForward_OnMinigameFinish != INVALID_HANDLE)
	{
		Call_StartForward(GlobalForward_OnMinigameFinish);
		Call_Finish();
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Saving data...");
	#endif

	new bool:playAnotherBossgame = false;
	new bool:returnedFromBoss = false;

	if (MinigameID > 0)
	{
		PreviousMinigameID = MinigameID;
	}
	else if (BossgameID > 0)
	{
		PreviousBossgameID = BossgameID;
		if (Handle_BossCheckTimer != INVALID_HANDLE)
		{
			// Closes the Boss Check Timer.
			KillTimer(Handle_BossCheckTimer);
			Handle_BossCheckTimer = INVALID_HANDLE;
		}

		returnedFromBoss = true;
		playAnotherBossgame = (SpecialRoundID == 10 && MinigamesPlayed == BossGameThreshold);
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Preparing env for next minigame");
	#endif

	IsMinigameActive = false;
	IsMinigameEnding = false;
	MinigamesPlayed++;
	MinigameID = 0;
	BossgameID = 0;

	IsBlockingDamage = true;
	IsBlockingDeaths = true;
	IsBlockingTaunts = true;
	IsOnlyBlockingDamageByPlayers = false;

	SpecialRound_SetupEnv();

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Preparing clients...");
	#endif

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (!IsPlayerAlive(i) || returnedFromBoss)
			{
				TF2_RespawnPlayer(i);
			}

			SetEntityGravity(i, 1.0);

			TF2_RemoveCondition(i, TFCond_Disguised);
			TF2_RemoveCondition(i, TFCond_Disguising);
			TF2_RemoveCondition(i, TFCond_Jarated);
			TF2_RemoveCondition(i, TFCond_OnFire);
			TF2_RemoveCondition(i, TFCond_Bonked);
			TF2_RemoveCondition(i, TFCond_Dazed);

			ClearSyncHud(i, HudSync_Caption);

			if (PlayerStatus[i] == PlayerStatus_Failed || PlayerStatus[i] == PlayerStatus_NotWon)
			{
				PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_FAILURE]); 
				PlaySoundToPlayer(i, SystemVocal[SYSFX_VOCAL_NEGATIVE][GetRandomInt(0, 4)]);
				DisplayOverlayToClient(i, ((SpecialRoundID == 17 && IsPlayerParticipant[i]) || SpecialRoundID != 17) ? OVERLAY_FAIL : OVERLAY_BLANK);

				if (IsPlayerParticipant[i])
				{
					SetEntProp(i, Prop_Send, "m_bGlowEnabled", 1);
					SetPlayerHealth(i, 1);
					PlayerMinigamesLost[i]++;

					if (SpecialRoundID != 12)
					{
						decl String:text[64];
						Format(text, sizeof(text), "%T", "General_Loser", i);

						ShowAnnotation(i, 2.0, text);
					}

					if (SpecialRoundID == 17)
					{
						IsPlayerParticipant[i] = false;
						PrintCenterText(i, "%T", "SuddenDeath_YouHaveBeenKnockedOut", i);
					}

					if (SpecialRoundID == 18)
					{
						PlayerScore[i] = 0;
					}
				}
			}
			else
			{
				PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_WINNER]);
				PlaySoundToPlayer(i, SystemVocal[SYSFX_VOCAL_POSITIVE][GetRandomInt(0, 6)]);
				DisplayOverlayToClient(i, OVERLAY_WON);

				ResetHealth(i);
				SetEntProp(i, Prop_Send, "m_bGlowEnabled", 1);

				PlayerScore[i] += ScoreAmount;
				PlayerMinigamesWon[i]++;

				if (SpecialRoundID != 12)
				{
					decl String:text[64];
					Format(text, sizeof(text), "%T", "General_Winner", i);
					ShowAnnotation(i, 2.0, text);
				}
			}

			PlayerStatus[i] = PlayerStatus_NotWon;

			ResetWeapon(i, false);
			IsPlayerCollisionsEnabled(i, true);
			IsGodModeEnabled(i , true);
			SetupSPR(i);
		}
	}

	if (SpecialRoundID == 17)
	{
		new participants = 0;
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientValid(i) && IsPlayerParticipant[i])
			{
				participants++;
			}
		}

		if (participants <= 1)
		{
			// End the round!
			CreateTimer(2.0, Timer_GameLogic_GameOverStart);
			return Plugin_Handled;
		}
		else
		{
			BossGameThreshold = 99999;
		}
	}
	else if (BossGameThreshold > 75)
	{
		// Maybe it will be funny if we let the plugin free for a bit,
		// but we *must* constrain it to a max of 75 if something goes wrong ;)

		BossGameThreshold = MinigamesPlayed;
	}

	if (MinigamesPlayed > 2 && Special_AreSpeedEventsEnabled() && SpeedLevel < 2.5 && MinigamesPlayed < BossGameThreshold)
	{
		if (GetRandomInt(0, 1) == 1)
		{
			#if defined DEBUG
			PrintToChatAll("[DEBUG] Decided to do a speed change!");
			#endif

			CreateTimer(2.0, Timer_GameLogic_SpeedChange);
			return Plugin_Handled;
		}
	}

	if (GamemodeID != SPR_GAMEMODEID && MinigamesPlayed < BossGameThreshold && GetRandomInt(0, 50) == 1)
	{
		GamemodeID = SPR_GAMEMODEID;

		SpecialRoundID = GetRandomInt(SPR_MIN, SPR_MAX);

		CreateTimer(2.0, Timer_GameLogic_SpecialRoundSelectionStart);
		return Plugin_Handled;
	}

	if ((SpecialRoundID != 10 && MinigamesPlayed == BossGameThreshold && !playAnotherBossgame) || (SpecialRoundID == 10 && (MinigamesPlayed == BossGameThreshold || playAnotherBossgame)))
	{
		CreateTimer(2.0, Timer_GameLogic_BossTime);
		return Plugin_Handled;
	}
	else if (MinigamesPlayed > BossGameThreshold && !playAnotherBossgame)
	{
		CreateTimer(2.0, Timer_GameLogic_GameOverStart);
		return Plugin_Handled;
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] Decided to continue gameplay as normal.");
	#endif

	CreateTimer(2.0, Timer_GameLogic_PrepareForMinigame);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_OnPreFinish(Handle:timer)
{
	if (GlobalForward_OnMinigameFinishPre != INVALID_HANDLE)
	{
		Call_StartForward(GlobalForward_OnMinigameFinishPre);
		Call_Finish();
	}

	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpeedChange(Handle:timer)
{
	new bool:flag = false;
	if (SpecialRoundID == 1)
	{
		flag = true;
		SpeedLevel -= 0.1;
	}
	else
	{
		SpeedLevel += 0.1;
	}

	SetSpeed();
	ShowPlayerScores(true);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SetEntProp(i, Prop_Send, "m_bGlowEnabled", 0);
			
			DisplayOverlayToClient(i, (flag ? OVERLAY_SPEEDDN : OVERLAY_SPEEDUP));
			PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_SPEEDUP]);
		}
	}

	CreateTimer(SystemMusicLength[GamemodeID][SYSMUSIC_SPEEDUP], Timer_GameLogic_PrepareForMinigame);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_BossTime(Handle:timer)
{
	SpeedLevel = 1.0;
	SetSpeed();

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SetEntProp(i, Prop_Send, "m_bGlowEnabled", 0);

			DisplayOverlayToClient(i, OVERLAY_BOSS);
			PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_BOSSTIME]);
		}
	}

	CreateTimer(SystemMusicLength[GamemodeID][SYSMUSIC_BOSSTIME], Timer_GameLogic_PrepareForMinigame);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_GameOverStart(Handle:timer)
{
	if (GamemodeStatus != GameStatus_Playing)
	{
		ResetGamemode();
		return Plugin_Stop;
	}

	#if defined DEBUG
	PrintToChatAll("[DEBUG] GameOverStart");
	#endif

	IsBlockingDamage = false;
	IsBlockingDeaths = false;
	IsBlockingTaunts = false;
	IsOnlyBlockingDamageByPlayers = false;
	IsBonusRound = true;
	SpeedLevel = 1.0;
	SetSpeed();

	SetConVarInt(ConVar_TFFastBuild, 1);

	new score = 0;
	new winnerCount = 0;
	new Handle:winners = CreateArray();
	new String:prefix[128];
	new String:names[1024];
	new bool:isWinner = false;

	score = SpecialRoundID == 9 ? GetLowestScore() : GetHighestScore();

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			if (GamemodeID == SPR_GAMEMODEID)
			{
				PrintCenterText(i, "%T", "GameOver_SpecialRoundHasFinished", i);
			}

			DisplayOverlayToClient(i, OVERLAY_GAMEOVER);
			PlaySoundToPlayer(i, SystemMusic[GamemodeID][SYSMUSIC_GAMEOVER]);

			SetEntityRenderColor(i, 255, 255, 255, 255);
			SetEntityRenderMode(i, RENDER_NORMAL);
	
			switch (SpecialRoundID)
			{
				case 17:
				{
					isWinner = IsPlayerParticipant[i];
				}

				case 9:
				{
					isWinner = (PlayerScore[i] == score);
				}

				default:
				{
					isWinner = (PlayerScore[i] >= score);
				}
			}

			IsPlayerWinner[i] = isWinner;
			IsGodModeEnabled(i, isWinner);
			IsViewModelVisible(i, isWinner);
			IsPlayerCollisionsEnabled(i, true);
			IsPlayerParticipant[i] = true;

			if (isWinner)
			{
				winnerCount++;

				if (false) //(Framework_PlayerHasConnectAccount(i)) // && IsSteamLoaded
				{
					// TODO: Remove StSv centric code from plugin
					// The reason I do this is so that the points are copied into a separate variable
					// and wont change suddenly.
					new points = PlayerScore[i] * 2;

					if (SpecialRoundID == 16)
					{
						points = points / 2;
					}
					else if (SpecialRoundID == 9)
					{
						points = PlayerMinigamesLost[i] * 2;
					}

					if (points > 0)
					{
						WebAPI_AddPointsForPlayer(i, points);
					}
				}

				ChooseRandomClass(i);
				TF2_RegeneratePlayer(i);

				CreateParticle(i, "Micro_Win_Sparkle", 10.0);
				CreateParticle(i, "Micro_Cheer_Winner", 10.0, true);
				CreateParticle(i, "unusual_aaa_aaa", 10.0, true);

				TF2_AddCondition(i, TFCond_Kritzkrieged, 10.0);

				PushArrayCell(winners, i);
			}
			else
			{
				if (false) //(Framework_PlayerHasConnectAccount(i)) // && IsSteamLoaded
				{
					// The reason I do this is so that the points are copied into a separate variable
					// and wont change suddenly.
					new points = PlayerScore[i];

					if (SpecialRoundID == 16)
					{
						points = points / 2;
					}
					else if (SpecialRoundID == 9)
					{
						points = PlayerMinigamesLost[i];
					}

					if (points > 0)
					{
						WebAPI_AddPointsForPlayer(i, points);
					}
				}

				SetCommandFlags("thirdperson", GetCommandFlags("thirdperson") & (~FCVAR_CHEAT));
				ClientCommand(i, "thirdperson");
				SetCommandFlags("thirdperson", GetCommandFlags("thirdperson") & (FCVAR_CHEAT));
						
				TF2_StunPlayer(i, 8.0, 0.0, TF_STUNFLAGS_LOSERSTATE, 0);
				SetPlayerHealth(i, 1);
			}
		}
	}

	if (winnerCount > 0)
	{
		#if defined NEW_HUD
		for (new i = 0; i < GetArraySize(winners); i++)
		{
			new client = GetArrayCell(winners, i);
			
			if (winnerCount > 1)
			{
				if (i >= (GetArraySize(winners)-1))
				{
					Format(names, sizeof(names), "%s and %N", names, client);
				}
				else
				{
					Format(names, sizeof(names), "%s, %N", names, client);
				}
			}
			else
			{
				Format(names, sizeof(names), "%N", client);
			}
		}

		if (winnerCount > 1)
		{
			ReplaceStringEx(names, sizeof(names), ", ", "");
		}

		if (winnerCount == 1)
		{
			Format(prefix, sizeof(prefix), "%T", "GameOver_WinnerPrefixSingle", 0);
		}
		else
		{
			Format(prefix, sizeof(prefix), "%T", "GameOver_WinnerPrefixMultiple", 0);
		}

		if (SpecialRoundID == 17)
		{
			DisplayHudMessage(prefix, names, 8.0);
		}
		else
		{
			DisplayHudMessage(prefix, names, 8.0);
		}

		#else

		for (new i = 0; i < GetArraySize(winners); i++)
		{
			new client = GetArrayCell(winners, i);

			if (winnerCount > 1)
			{
				if (i >= (GetArraySize(winners)-1))
				{
					Format(names, sizeof(names), "%s and {olive}%N{green}", names, client);
				}
				else
				{
					Format(names, sizeof(names), "%s, {olive}%N{green}", names, client);
				}
			}
			else
			{
				Format(names, sizeof(names), "{olive}%N{green}", client);
			}
		}

		if (winnerCount > 1)
		{
			ReplaceStringEx(names, sizeof(names), ", ", "");
		}

		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				if (winnerCount == 1)
				{
					Format(prefix, sizeof(prefix), "{green}%T", "GameOver_WinnerPrefixSingle", i);
				}
				else
				{
					Format(prefix, sizeof(prefix), "{green}%T", "GameOver_WinnerPrefixMultiple", i);
				}

				if (SpecialRoundID == 17)
				{
					CPrintToChat(i, "%s %s!", prefix, names);
				}
				else
				{
					CPrintToChat(i, "%s %s {green}with %i points!", prefix, names, score);
				}
			}
		}
		#endif
	}
	else
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				Format(prefix, sizeof(prefix), "{green}%T", "GameOver_WinnerPrefixNoOne", i);

				CPrintToChat(i, "%s", prefix);
			}
		}
	}

	ClearArray(winners);
	CloseHandle(winners);
	winners = INVALID_HANDLE;

	CreateTimer(8.0, Timer_GameLogic_GameOverEnd);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_GameOverEnd(Handle:timer)
{
	if (GamemodeStatus != GameStatus_Playing)
	{
		ResetGamemode();
		return Plugin_Stop;
	}

	for (new i = 1; i <= MaxClients; i++)
	{
		// Intentionally out side of IsClientValid - to cover any possible spectators with stale data.
		PlayerStatus[i] = PlayerStatus_NotWon;
		PlayerScore[i] = 0;
		PlayerMinigamesWon[i] = 0;
		PlayerMinigamesLost[i] = 0;

		if (IsClientValid(i))
		{
			IsPlayerParticipant[i] = true;
			
			if (IsPlayerWinner[i])
			{
				TF2_SetPlayerPowerPlay(i, false);
				ResetWeapon(i, false);
			
				IsPlayerWinner[i] = false;
			}

			IsGodModeEnabled(i, true);
		}
	}

	BossgameID = 0;
	MinigameID = 0;
	SpecialRoundID = 0;
	PreviousMinigameID = 0;
	PreviousBossgameID = 0;
	MinigamesPlayed = 0;
	
	IsMinigameActive = false;
	IsBonusRound = false;

	IsBlockingDamage = true;
	IsBlockingDeaths = true;
	IsBlockingTaunts = true;
	IsOnlyBlockingDamageByPlayers = false;

	BossGameThreshold = GetRandomInt(15, 26);

	SetSpeed();
	SetConVarInt(ConVar_TFFastBuild, 0);

	if (MaxRounds == 0 || RoundsPlayed < MaxRounds)
	{
		ShowPlayerScores(true);
		new bool:isWaitingForVoteToFinish = false;

		if (MaxRounds != 0 && RoundsPlayed == (MaxRounds / 2))
		{
			#if defined UMC_MAPCHOOSER
			// This should be using UMC_StartVote native, but that requires too many parameters... TODO: update this later on 
			ServerCommand("sm_umc_mapvote 2");
			#else
			InitiateMapChooserVote(MapChange_MapEnd);
			#endif
			
			isWaitingForVoteToFinish = true;
		}

		if (GetRandomInt(0, 2) == 1 || ForceNextSpecialRound)
		{
			// Special Round
			GamemodeID = SPR_GAMEMODEID;
		}
		else
		{
			// Back to normal - use themes.
			GamemodeID = GetRandomInt(0, MaxGamemodesSelectable - 1);
		}

		if (isWaitingForVoteToFinish)
		{
			SetMinigameCaptionForAll("INTERMISSION!\nVOTE FOR THE NEXT MAP!");

			for (new i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i) && !IsFakeClient(i))
				{
					EmitSoundToClient(i, SYSMUSIC_WAITINGFORPLAYERS);
				}
			}
		}

		CreateTimer(2.0, Timer_GameLogic_WaitForVoteToFinishIfAny);
	}
	else
	{
		// If any commands are put after this call, they will not be called;
		// The plugin will have already unloaded.
		EndGame();
	}

	RoundsPlayed++;
	return Plugin_Handled;
}

public Action:Timer_GameLogic_WaitForVoteToFinishIfAny(Handle:timer)
{
	#if defined UMC_MAPCHOOSER
	new bool:voteIsInProgress = UMC_IsVoteInProgress("core");
	#else
	new bool:voteIsInProgress = IsVoteInProgress();
	#endif

	if (voteIsInProgress)
	{
		CreateTimer(1.0, Timer_GameLogic_WaitForVoteToFinishIfAny);
		return Plugin_Handled;
	}

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			StopSound(i, SNDCHAN_AUTO, SYSMUSIC_WAITINGFORPLAYERS);
		}
	}

	ClearMinigameCaptionForAll();

	if (GamemodeID == SPR_GAMEMODEID)
	{
		CreateTimer(0.0, Timer_GameLogic_SpecialRoundSelectionStart);
	}
	else
	{
		CreateTimer(0.0, Timer_GameLogic_PrepareForMinigame);
	}

	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpecialRoundSelectionStart(Handle:timer)
{
	if (SpeedLevel == 1.0)
	{
		EmitSoundToAll(SYSMUSIC_SPECIALROUND);
	}
	else
	{
		PlaySoundToAll(SYSMUSIC_SPECIALROUND);
	}
	
	CreateTimer(0.2, Timer_GameLogic_SpecialRoundChoosing3);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpecialRoundChoosing3(Handle:timer)
{
	CreateTimer(0.3, Timer_GameLogic_SpecialRoundChoosing2);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpecialRoundChoosing2(Handle:timer)
{
	CreateTimer(0.3, Timer_GameLogic_SpecialRoundChoosing1);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpecialRoundChoosing1(Handle:timer)
{
	IsChoosingSpecialRound = true;

	DisplayOverlayToAll(OVERLAY_SPECIALROUND);

	CreateTimer(6.8, Timer_GameLogic_SpecialRoundChoosing0);
	return Plugin_Handled;
}

public Action:Timer_GameLogic_SpecialRoundChoosing0(Handle:timer)
{
	#if defined DEBUG
	PrintToChatAll("chose a special round, timer for PrepareForMinigame @ 5.0 from now");
	#endif

	SelectNewSpecialRound();
	PrintSelectedSpecialRound();

	CreateTimer(5.0, Timer_GameLogic_PrepareForMinigame);
	return Plugin_Handled;
}
/**
 * MicroTF2 - MinigameSystem.inc
 * 
 * Implements a System for Minigames.
 */

#define MAXIMUM_MINIGAMES 64
#define MINIGAME_CAPTION_LENGTH 64

new MinigamesLoaded = 0;
new BossgamesLoaded = 0;

new String:MinigameCaptions[MAXIMUM_MINIGAMES][MINIGAME_CAPTION_LENGTH];
new String:MinigameDynamicCaptionFunctions[MAXIMUM_MINIGAMES][64];
new bool:MinigameCaptionIsDynamic[MAXIMUM_MINIGAMES];

new String:BossgameCaptions[MAXIMUM_MINIGAMES][MINIGAME_CAPTION_LENGTH];
new String:BossgameDynamicCaptionFunctions[MAXIMUM_MINIGAMES][64];
new bool:BossgameCaptionIsDynamic[MAXIMUM_MINIGAMES];

new String:MinigameMusic[MAXIMUM_MINIGAMES][128];
new Float:MinigameMusicLength[MAXIMUM_MINIGAMES];

new String:BossgameMusic[MAXIMUM_MINIGAMES][128];
new Float:BossgameLength[MAXIMUM_MINIGAMES];

new String:MinigameCaption[MAXPLAYERS][MINIGAME_CAPTION_LENGTH];

#include MinigameStocks.inc

// Minigames
#include Minigames/Minigame1.inc
#include Minigames/Minigame2.inc
#include Minigames/Minigame3.inc
#include Minigames/Minigame4.inc
#include Minigames/Minigame5.inc
#include Minigames/Minigame6.inc
#include Minigames/Minigame7.inc
#include Minigames/Minigame8.inc
#include Minigames/Minigame9.inc
#include Minigames/Minigame10.inc
#include Minigames/Minigame11.inc
#include Minigames/Minigame12.inc
#include Minigames/Minigame13.inc
#include Minigames/Minigame14.inc 
#include Minigames/Minigame15.inc
#include Minigames/Minigame16.inc
#include Minigames/Minigame17.inc
#include Minigames/Minigame18.inc
#include Minigames/Minigame19.inc
#include Minigames/Minigame20.inc
#include Minigames/Minigame21.inc
#include Minigames/Minigame22.inc
#include Minigames/Minigame23.inc
#include Minigames/Minigame24.inc

// Bossgames
#include Bossgames/Bossgame1.inc
#include Bossgames/Bossgame2.inc
#include Bossgames/Bossgame3.inc
#include Bossgames/Bossgame4.inc
#include Bossgames/Bossgame5.inc

public InitializeMinigames()
{
	LogMessage("Initializing Minigame System...");
	decl String:funcName[64];
	decl String:manifestPath[128];

	// Our method of initializing minigames is:
	// Each minigame has a method called Minigame<NUMBER>_EntryPoint
	// This method is invoked and allows the minigame to add itself to the Minigame-cycle and add itself to forwards.

	// Determine count of Minigames that are available.
	BuildPath(Path_SM, manifestPath, sizeof(manifestPath), "data/microtf2/minigames.txt");

	new Handle:kv = CreateKeyValues("Minigames");
	FileToKeyValues(kv, manifestPath);
 
	if (KvGotoFirstSubKey(kv))
	{
		new i = 0;

		do
		{
			i++;

			if (KvGetNum(kv, "Enabled", 0) == 0)
			{
				// The Enabled/Disabled system needs reworking.
				// MinigamesLoaded might be lower and this means some minigames 
				// cant run...
				continue;
			}

			KvGetString(kv, "EntryPoint", funcName, sizeof(funcName));

			new Function:func = GetFunctionByName(INVALID_HANDLE, funcName);
			if (func != INVALID_FUNCTION)
			{
				MinigamesLoaded++;

				Call_StartFunction(INVALID_HANDLE, func);
				Call_Finish();
			}
			else
			{
				LogError("Unable to find EntryPoint for Minigame #%i with name: \"%s\"", i, funcName);
				continue;
			}

			KvGetString(kv, "BackgroundMusic", MinigameMusic[i], 128);
			KvGetString(kv, "Caption", MinigameCaptions[i], 64);

			MinigameCaptionIsDynamic[i] = (KvGetNum(kv, "CaptionIsDynamic", 0) == 1);

			if (MinigameCaptionIsDynamic[i])
			{
				KvGetString(kv, "DynamicCaptionMethod", MinigameDynamicCaptionFunctions[i], 64);
			}
		}
		while (KvGotoNextKey(kv));
	}
 
	CloseHandle(kv);

	BuildPath(Path_SM, manifestPath, sizeof(manifestPath), "data/microtf2/bossgames.txt");

	kv = CreateKeyValues("Bossgames");
	FileToKeyValues(kv, manifestPath);
 
	if (KvGotoFirstSubKey(kv))
	{
		new i = 0;

		do
		{
			i++;

			if (KvGetNum(kv, "Enabled", 0) == 0)
			{
				continue;
			}

			// Get EntryPoint first of all!
			KvGetString(kv, "EntryPoint", funcName, sizeof(funcName));

			new Function:func = GetFunctionByName(INVALID_HANDLE, funcName);
			if (func != INVALID_FUNCTION)
			{
				BossgamesLoaded++;

				Call_StartFunction(INVALID_HANDLE, func);
				Call_Finish();
			}
			else
			{
				LogError("Unable to find EntryPoint for Bossgame #%i with name: \"%s\"", i, funcName);
				continue;
			}

			KvGetString(kv, "BackgroundMusic", BossgameMusic[i], 128);
			KvGetString(kv, "Caption", BossgameCaptions[i], 64);

			BossgameLength[i] = KvGetFloat(kv, "Duration", 30.0);
			BossgameCaptionIsDynamic[i] = (KvGetNum(kv, "CaptionIsDynamic", 0) == 1);

			if (BossgameCaptionIsDynamic[i])
			{
				KvGetString(kv, "DynamicCaptionMethod", BossgameDynamicCaptionFunctions[i], 64);
			}
		}
		while (KvGotoNextKey(kv));
	}
 
	CloseHandle(kv);

	LogMessage("Minigame System initialized with %d Minigame(s) and %d Bossgame(s).", MinigamesLoaded, BossgamesLoaded);

	AddToForward(GlobalForward_OnMapStart, INVALID_HANDLE, MinigameSystem_OnMapStart);
}

public MinigameSystem_OnMapStart()
{
	new Handle:sndfile = INVALID_HANDLE;

	for (new i = 1; i <= MinigamesLoaded; i++)
	{
		if (strlen(MinigameMusic[i]) == 0)
		{
			continue;
		}

		PreloadSound(MinigameMusic[i]);
		sndfile = OpenSoundFile(MinigameMusic[i]);

		if (sndfile == INVALID_HANDLE)
		{
			LogError("Failed to get sound length for Minigame %d - %s", i, MinigameMusic[i]);
		}
		else
		{
			MinigameMusicLength[i] = GetSoundLengthFloat(sndfile);
			CloseHandle(sndfile);
		}
	}

	for (new i = 1; i <= BossgamesLoaded; i++)
	{
		if (strlen(BossgameMusic[i]) == 0)
		{
			continue;
		}


		PreloadSound(BossgameMusic[i]);
	}
}

#define DEBUG

#define PLUGIN_NAME           "landingfix"
#define PLUGIN_AUTHOR         ""
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            ""

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#pragma semicolon 1

Address g_CategorizeMovement;
Address g_CheckJumpButton;
ConVar g_cvMinLandHeight;
ConVar g_cvJumpHeight;

bool g_bLinux;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	GameData gamedata = new GameData("landfix.games");
	g_CategorizeMovement = gamedata.GetAddress("CategorizePosition");
	g_CheckJumpButton = gamedata.GetAddress("CheckJumpButton");	
	
	int os = gamedata.GetOffset("OS");
	
	if(os == 2)
	{
		g_bLinux = true;
	}
	
	g_cvMinLandHeight = CreateConVar("landfix_minlandheight", "0.5", "");
	g_cvJumpHeight = CreateConVar("landfix_jumpheight", "58.0", "57 is default. 58 = +1");
	AutoExecConfig();
	
	StoreDoubleToAddressFromFloat(g_CheckJumpButton + view_as<Address>(0x1CB760), (2 * 800 * g_cvJumpHeight.FloatValue));
	
	g_cvJumpHeight.AddChangeHook(OnJumpHeightChanged);
	
	LoadDHooks();
	
	delete gamedata;
}

public void OnJumpHeightChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(!g_bLinux)
	{
		StoreDoubleToAddressFromFloat(g_CheckJumpButton + view_as<Address>(0x1CB760), (2 * 800 * convar.FloatValue));
	}
	else
	{
		StoreDoubleToAddressFromFloat(g_CheckJumpButton + view_as<Address>(0x597230), SquareRoot(2 * 800 * convar.FloatValue));
	}
	
}

void LoadDHooks()
{
	GameData gamedata = new GameData("landfix.games");
	//Address addr = gamedata.GetAddress("CategorizePosition");

	if(gamedata == null)
	{
		SetFailState("Failed to load gamedata");
	}
	
	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CreateInterface"))
	{
		SetFailState("Failed to get CreateInterface");
	}
	
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if(CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];
	if(!GameConfGetKeyValue(gamedata, "IGameMovement", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IGameMovement interface name");
	}

	Address IGameMovement = SDKCall(CreateInterface, interfaceName, 0);
	if(!IGameMovement)
	{
		SetFailState("Failed to get IGameMovement pointer");
	}

	int offset = GameConfGetOffset(gamedata, "CategorizePosition");
	if(offset == -1)
	{
		SetFailState("Failed to get CategorizePosition offset");
	}

	Handle categorizePosition = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_CategorizePosition);
	DHookRaw(categorizePosition, false, IGameMovement);

	Handle processMovementPost = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_CategorizePositionPost);
	DHookRaw(processMovementPost, true, IGameMovement);

	delete CreateInterface;
	delete gamedata;
}

public MRESReturn DHook_CategorizePosition()
{
	int offset = g_bLinux?0x539D7C:0x23BB10;
	
	StoreToAddress(g_CategorizeMovement + view_as<Address>(offset), view_as<int>(g_cvMinLandHeight.FloatValue), NumberType_Int32);
	return MRES_Handled;
}

public MRESReturn DHook_CategorizePositionPost()
{
	int offset = g_bLinux?0x539D7C:0x23BB10;
	StoreToAddress(g_CategorizeMovement + view_as<Address>(offset), view_as<int>(2.0), NumberType_Int32);
	return MRES_Handled;
}

//stocks

stock float LoadDoubleFromAddressAsFloat(Address addr) {
	int dblVal[2];
	dblVal[0] = LoadFromAddress(addr, NumberType_Int32);
	dblVal[1] = LoadFromAddress(addr + view_as<Address>(0x04), NumberType_Int32);
	
	return DoubleToFloat(dblVal, false);
}

stock void StoreDoubleToAddressFromFloat(Address addr, float value) {
	int dblVal[2];
	FloatToDouble(value, dblVal);
	
	StoreToAddress(addr, dblVal[0], NumberType_Int32);
	StoreToAddress(addr + view_as<Address>(0x04), dblVal[1], NumberType_Int32);
}

stock float DoubleToFloat(const int dblVal[2], bool clamp = false) {
	int sign = (dblVal[1] >> 31) & 1;
	
	// extract truncated mantissa from both cells
	int mantissa = ((dblVal[1] << 3) & 0x007FFFFF) | (dblVal[0] >> 29);
	int expdbl_2 = (dblVal[1] >> 20) & 0x7FF;
	
	int expflt_2 = (expdbl_2 - 1023) + 127;
	if (expdbl_2 == 0x7FF) {
		// special case: infinity or subnormal
		expflt_2 = 0xFF;
		mantissa = (mantissa || dblVal[0]);
	} else if (expdbl_2 == 0) {
		// special case: no exponent
		expflt_2 = 0;
	} else if (expflt_2 > 0xFE) {
		// case: exponent is larger than can be represented
		// TODO test case for smaller exponent values
		if (!clamp) {
			ThrowError("Double value %08x%08x is outside of float value range", dblVal[1], dblVal[0]);
		}
		expflt_2 = 0xFE;
		mantissa = 0x007FFFFFF;
	}
	
	return view_as<float>((sign << 31) | (expflt_2 << 23) | (mantissa & 0x007FFFFF));
}

stock void FloatToDouble(float flValue, int dblVal[2]) {
	int bytesFloat = view_as<int>(flValue);
	
	int sign = (bytesFloat >> 31) & 1;
	int exp_2 = (bytesFloat >> 23) & 0xFF;
	int mantissa = bytesFloat & 0x007FFFFF;
	
	int expdbl_2 = (1023 + (exp_2 - 127)) & 0x7FF;
	if (exp_2 == 0xFF) {
		// special case: infinity or subnormal
		expdbl_2 = 0x7FF;
	} else if (exp_2 == 0) {
		// special case: no exponent
		expdbl_2 = 0;
	}
	
	// no bits in lower three bytes of double
	dblVal[0] = (mantissa << 29);
	dblVal[1] = (sign << 31) | (expdbl_2 << 20) | (mantissa >> 3);
}

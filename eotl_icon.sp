#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_AUTHOR  "ack"
#define PLUGIN_VERSION "0.08"

#define CONFIG_FILE    "configs/eotl_icon.cfg"

#define DB_CONFIG      "default"
#define DB_TABLE       "vip_users"
#define DB_COL_ICONID  "iconID"
#define DB_COL_STEAMID "steamID"

#define ICONID_MAX_LEN  32
#define CMD_MAX_LEN     128

//#define USE_SDKHOOK

enum struct PlayerState {
    bool isDonator;
    bool iconActive;
    int iconEntRef;
    char iconID[ICONID_MAX_LEN];
}

PlayerState g_playerStates[MAXPLAYERS + 1];
bool g_roundOver;
Handle g_dbh;
StringMap iconMap;
StringMap auxAddCmdMap;
StringMap auxRemoveCmdMap;
ConVar g_cvDebug;

public Plugin myinfo = {
	name = "eotl_icon",
	author = PLUGIN_AUTHOR,
	description = "Display icon over donators head at end of round",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart() {
    LogMessage("version %s starting (db config: %s, table: %s)", PLUGIN_VERSION, DB_CONFIG, DB_TABLE);
    g_cvDebug = CreateConVar("eotl_icon_debug", "0", "0/1 enable debug output", FCVAR_NONE, true, 0.0, true, 1.0);

#if defined USE_SDKHOOK
    LogMessage("SDKHOOK method is being used");
#else
    LogMessage("OnGameFrame method is being used");
#endif
}

public void OnMapStart() {

    LoadConfig();

    if(!ConnectDB()) {
        LogError("will re-attempt database connection when a client connects");
    }

    g_roundOver = false;

    for (int client = 1; client <= MaxClients; client++) {
        g_playerStates[client].iconEntRef = -1;
        g_playerStates[client].iconActive = false;
        g_playerStates[client].isDonator = false;
	}

    HookEvent("teamplay_round_start", EventRoundStart, EventHookMode_PostNoCopy);

    HookEvent("teamplay_round_stalemate", EventRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_win", EventRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("teamplay_game_over", EventRoundEnd, EventHookMode_PostNoCopy);

    HookEvent("player_death", EventPlayerDeath);
}

public void OnMapEnd() {
    if(g_dbh != INVALID_HANDLE) {
        CloseHandle(g_dbh);
        g_dbh = INVALID_HANDLE;
    }
    CloseHandle(iconMap);
    CloseHandle(auxAddCmdMap);
    CloseHandle(auxRemoveCmdMap);
}

public void OnClientAuthorized(int client, const char[] auth) {

    if(IsFakeClient(client)) {
        return;
    }

    if(InitClient(client, auth, true)) {
        LogMessage("client: %d, %N (%s) is a donator, iconID: %s", client, client, auth, g_playerStates[client].iconID);
    } else {
        LogMessage("client: %d, %N (%s) is not a donator", client, client, auth);
    }
}

public void OnClientDisconnect(int client) {

    LogDebug("client: %d disconnected", client);

    if(g_playerStates[client].iconActive) {
        RemoveIcon(client);
    }
    g_playerStates[client].isDonator = false;
}

public Action EventPlayerDeath(Handle event, const char[] name, bool dontBroadcast) {

    if(!g_roundOver) {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(g_playerStates[client].iconActive) {
        RemoveIcon(client);
    }
    return Plugin_Continue;
}

public Action EventRoundStart(Handle event, const char[] name, bool dontBroadcast) {
    g_roundOver = false;

    LogDebug("round start, cleaning up icons");
    for(int client = 1; client <= MaxClients; client++) {
        if(g_playerStates[client].iconActive) {
            RemoveIcon(client);

            char cmd[CMD_MAX_LEN];
            if(GetTrieString(auxRemoveCmdMap, g_playerStates[client].iconID, cmd, sizeof(cmd))) {
                runCommand(client, cmd);
            }
        }
    }
    return Plugin_Continue;
}

public Action EventRoundEnd(Handle event, const char[] name, bool dontBroadcast) {

    if(g_roundOver) {
        return Plugin_Continue;
    }
    g_roundOver = true;

    LogDebug("round ended, creating icons for donators");
    for(int client = 1; client <= MaxClients; client++) {

        if(!IsClientInGame(client)) {
            continue;

        }
        if(IsFakeClient(client)) {
            continue;
        }

        if(!IsPlayerAlive(client)) {
            continue;
        }

        if(!g_playerStates[client].isDonator) {
            continue;
        }

        if(g_playerStates[client].iconActive) {
            LogError("client: %d already has an active icon!? skipping", client);
            continue;
        }
        AddIcon(client);
    }
    RefreshIcons();
    return Plugin_Continue;
}

#if defined USE_SDKHOOK

public Action TransmitHook(int entity, int client) {

    if(!g_roundOver) {
        SDKUnhook(entity, SDKHook_SetTransmit, TransmitHook);
        return;
    }
    RefreshIcons();
}

#else

public void OnGameFrame() {

    if(!g_roundOver) {
        return;
    }
    RefreshIcons();
}

#endif

// refresh the location of icons
void RefreshIcons() {

    float playerPosition[3];

    for(int client = 1; client <= MaxClients; client++) {
        if(!g_playerStates[client].iconActive) {
            continue;
        }

        if(!IsClientInGame(client)) {
            continue;
        }

        int icon = EntRefToEntIndex(g_playerStates[client].iconEntRef);
        if(icon == INVALID_ENT_REFERENCE || !IsValidEntity(icon)) {
            g_playerStates[client].iconEntRef = -1;
            g_playerStates[client].iconActive = false;
            continue;
        }

        GetClientEyePosition(client, playerPosition);
        playerPosition[2] += 25;
        TeleportEntity(icon, playerPosition, NULL_VECTOR, NULL_VECTOR);
    }
}

void AddIcon(int client) {

    char targetName[32];
    char vmt[128];

    if(!GetTrieString(iconMap, g_playerStates[client].iconID, vmt, sizeof(vmt))) {
        LogError("client: %d has iconID %s but that doesn't exist in our iconMap trie!? skipping", client, g_playerStates[client].iconID);
        return;
    }

    int icon = CreateEntityByName("env_sprite");
    if(icon < 0) {
        LogMessage("client: %d failed to create icon entity", client);
        return;
    }

    DispatchKeyValue(icon, "model", vmt);
    DispatchKeyValue(icon, "spawnflags", "1");
    DispatchKeyValue(icon, "scale", "0.1");
    DispatchKeyValue(icon, "rendermode", "1");
    Format(targetName, sizeof(targetName), "client_%d_icon", client);
    DispatchKeyValue(icon, "targetname", targetName);

    DispatchSpawn(icon);

    g_playerStates[client].iconEntRef = EntIndexToEntRef(icon);
    g_playerStates[client].iconActive = true;

    LogDebug("client: %d icon added (iconID: %s, entity: %d, ref: %d) ", client, g_playerStates[client].iconID, icon, g_playerStates[client].iconEntRef);

    char cmd[CMD_MAX_LEN];
    if(GetTrieString(auxAddCmdMap, g_playerStates[client].iconID, cmd, sizeof(cmd))) {
        runCommand(client, cmd);
    }

#if defined USE_SDKHOOK
    SDKHook(client, SDKHook_SetTransmit, TransmitHook);
#endif
}

void RemoveIcon(int client) {

    int icon = EntRefToEntIndex(g_playerStates[client].iconEntRef);
    if(icon != INVALID_ENT_REFERENCE && IsValidEntity(icon)) {
        LogDebug("client: %d removing icon (entity: %d, ref: %d)", client, icon, g_playerStates[client].iconEntRef);
        AcceptEntityInput(icon, "kill");
#if defined USE_SDKHOOK
        SDKUnhook(client, SDKHook_SetTransmit, TransmitHook);
#endif

    }
    g_playerStates[client].iconActive = false;
    g_playerStates[client].iconEntRef = -1;
}

bool ConnectDB() {
    if(!SQL_CheckConfig(DB_CONFIG)) {
        SetFailState("Database config \"%s\" doesn't exist", DB_CONFIG);
    }

    char error[256];
    g_dbh = SQL_Connect(DB_CONFIG, false, error, sizeof(error));
    if(g_dbh == INVALID_HANDLE) {
        LogError("connection to database failed (DB config: %s): %s", DB_CONFIG, error);
        return false;
    }

    LogMessage("connected to database");
    return true;
}

bool InitClient(int client, const char[] steamid, bool retryDB) {

    g_playerStates[client].isDonator = false;
    g_playerStates[client].iconActive = false;
    g_playerStates[client].iconEntRef = -1;
    strcopy(g_playerStates[client].iconID, ICONID_MAX_LEN, "");

    if(g_dbh == INVALID_HANDLE) {
        LogError("InitClient() not connected to database, attempting reconnect");
        if(!ConnectDB()) {
            LogError("client: %d InitClient() still no connection to database, disabling icon for them", client);
            return false;
        }
        return InitClient(client, steamid, false);
    }

    char query[128];
    Format(query, sizeof(query), "SELECT %s from %s where %s = '%s'", DB_COL_ICONID, DB_TABLE, DB_COL_STEAMID, steamid);

    DBResultSet results;
    results = SQL_Query(g_dbh, query);

    // this seems to be an indication we aren't connected to the database anymore
    if(results == INVALID_HANDLE) {
        CloseHandle(g_dbh);
        g_dbh = INVALID_HANDLE;
        if(retryDB) {
            return InitClient(client, steamid, false);
        }
        LogError("client: %d InitClient() SQL_Query returned INVALID_HANDLE. Something maybe wrong with the connection to the database. disabling icon for them");
        return false;
    }

    if(results.RowCount > 0) {
        char iconID[32];
        char junk[1];
        if(results.FetchRow()) {
            if(results.FetchString(0, iconID, sizeof(iconID))) {
                if(GetTrieString(iconMap, iconID, junk, 0)) {
                    strcopy(g_playerStates[client].iconID, ICONID_MAX_LEN, iconID);
                    g_playerStates[client].isDonator = true;
                } else {
                    LogError("client: %d (streamid: %s) has iconID: %s in the database, but that iconID doesn't exist in the config, disabling icon for them", client, steamid, iconID);
                }
            }
        }
    }

    CloseHandle(results);
    return g_playerStates[client].isDonator;
}

void LoadConfig() {
    iconMap = CreateTrie();
    auxAddCmdMap = CreateTrie();
    auxRemoveCmdMap = CreateTrie();
    KeyValues cfg = CreateKeyValues("icons");

    char configFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configFile, sizeof(configFile), CONFIG_FILE);

    LogMessage("loading config file: %s", configFile);
    if(!FileToKeyValues(cfg, configFile)) {
        SetFailState("unable to load config file!");
        return;
    }

    char iconID[32];
    char vmt[64];
    char vtf[64];
    char auxAddCmd[CMD_MAX_LEN];
    char auxRemoveCmd[CMD_MAX_LEN];

    KvGotoFirstSubKey(cfg);
    do {
        cfg.GetSectionName(iconID, sizeof(iconID));
        cfg.GetString("vmt", vmt, sizeof(vmt));
        cfg.GetString("vtf", vtf, sizeof(vtf));
        cfg.GetString("aux_add_cmd", auxAddCmd, sizeof(auxAddCmd));
        cfg.GetString("aux_remove_cmd", auxRemoveCmd, sizeof(auxRemoveCmd));

        if(!SetTrieString(iconMap, iconID, vmt, false)) {
            LogError("WARN: dupe iconID's \"%s\" in config file, ignoring dupe", iconID);
            continue;
        }

        if(strlen(auxAddCmd) > 0) {
            SetTrieString(auxAddCmdMap, iconID, auxAddCmd, false);
        }

        if(strlen(auxRemoveCmd) > 0) {
            SetTrieString(auxRemoveCmdMap, iconID, auxRemoveCmd, false);
        }

        PrecacheGeneric(vmt, true);
        AddFileToDownloadsTable(vmt);
        PrecacheGeneric(vtf, true);
        AddFileToDownloadsTable(vtf);

        LogMessage("loaded iconID: %s, vmt: %s, vtf: %s, aux add cmd: \"%s\", aux remove cmd: \"%s\"", iconID, vmt, vtf, auxAddCmd, auxRemoveCmd);

    } while(KvGotoNextKey(cfg));

    CloseHandle(cfg);
}

void runCommand(int client, const char[] template) {
    char cmd[CMD_MAX_LEN];
    strcopy(cmd, sizeof(cmd), template);

    char userIdStr[16];
    int userId = GetClientUserId(client);
    if(userId > 0) {
        Format(userIdStr, sizeof(userIdStr), "%d", userId);
        ReplaceString(cmd, sizeof(cmd), "{userid}", userIdStr);
    }

    char name[32];
    if(GetClientName(client, name, sizeof(name))) {
        ReplaceString(cmd, sizeof(cmd), "{name}", name);
    }

    LogDebug("running command: %s", cmd);
    ServerCommand(cmd);
}

void LogDebug(char []fmt, any...) {

    if(!g_cvDebug.BoolValue) {
        return;
    }

    char message[128];
    VFormat(message, sizeof(message), fmt, 2);
    LogMessage(message);
}
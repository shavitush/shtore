/*
 * shtore
 * by: shavit
 *
 * This file is part of shtore.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <shtore>
#include <chat-processor>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

ConVar gCV_Refund_Tax = null;
ConVar gCV_Credits_Distribution = null;
ConVar gCV_Credits_NoSpectators = null;
ConVar gCV_Credits_Min = null;
ConVar gCV_Credits_Max = null;
ConVar gCV_Items_Per_Server = null;

char gS_LogPath[PLATFORM_MAX_PATH];
Database gH_Database = null;
store_settings_t gA_Settings;

ArrayList gA_Items = null;
ArrayList gA_ItemsMenu = null; // sorted

StoreItem gI_Category[MAXPLAYERS+1];
store_user_t gA_StoreUsers[MAXPLAYERS+1];
bool gB_CategoryEnabled[StoreItem_SIZE];

public Plugin myinfo =
{
	name = "shtore",
	author = "shavit",
	description = "Simple SourceMod store plugin.",
	version = SHTORE_VERSION,
	url = "https://github.com/shavitush/shtore"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shtore_GetUser", Native_GetUser);
	CreateNative("Shtore_LogMessage", Native_LogMessage);
	CreateNative("Shtore_PrintToChat", Native_PrintToChat);
	CreateNative("Shtore_SetCredits", Native_SetCredits);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shtore");

	return APLRes_Success;
}

public void OnPluginStart()
{
	// events
	HookEvent("player_spawn", EventPlayerSpawn, EventHookMode_Pre);

	// globals
	gA_Items = new ArrayList(sizeof(store_item_t));
	SQL_DBConnect();

	// admin commands
	RegAdminCmd("sm_reloadstoreitems", Command_ReloadStoreItems, ADMFLAG_RCON, "Fetches shtore items from database.");

	// player commands
	RegConsoleCmd("sm_shtore", Command_Store, "Opens the shtore menu.");
	RegConsoleCmd("sm_store", Command_Store, "Opens the shtore menu.");
	RegConsoleCmd("sm_shop", Command_Shop, "Opens the shop menu.");
	RegConsoleCmd("sm_inv", Command_Inventory, "Opens your inventory.");
	RegConsoleCmd("sm_inventory", Command_Inventory, "Opens your inventory.");
	RegConsoleCmd("sm_sell", Command_Sell, "Sell an item.");
	RegConsoleCmd("sm_credits", Command_Credits, "Show your or someone else's credits. Usage: sm_credits [target]");

	// settings
	CreateConVar("shtore_version", SHTORE_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));
	gCV_Refund_Tax = CreateConVar("shtore_refund_tax", "0.10", "Tax multiplier for item sales.", 0, true, 0.0, true, 1.0);
	gCV_Credits_Distribution = CreateConVar("shtore_credits_distribution", "300", "Distribute credits every N seconds.\nRestart map for changes to be applied.", 0, true, 1.0);
	gCV_Credits_NoSpectators = CreateConVar("shtore_credits_nospectators", "1", "Exclude spectators from credits distribution.", 0, true, 0.0, true, 1.0);
	gCV_Credits_Min = CreateConVar("shtore_credits_min", "10", "Minimum range of credits to randomly distribute.", 0, true, 0.0);
	gCV_Credits_Max = CreateConVar("shtore_credits_max", "15", "Maximum range of credits to randomly distribute.", 0, true, 0.0);
	gCV_Items_Per_Server = CreateConVar("shtore_items_per_server", "1", "Enable to separate item purchases per server.", 0, true, 0.0, true, 1.0);

	AutoExecConfig();

	if(!LoadStoreConfig(SHTORE_CONFIG_PATH))
	{
		SetFailState("Could not load config from path \"%s\".", SHTORE_CONFIG_PATH);
	}

	if(gA_Settings.iServerID == -1)
	{
		SetFailState("Server ID cannot be -1.");
	}

	// logs
	BuildPath(Path_SM, gS_LogPath, PLATFORM_MAX_PATH, "logs/shtore.log");

	// translations
	LoadTranslations("common.phrases");
}

public void OnMapStart()
{
	if(gH_Database != null)
	{
		FetchStoreCategories();
		FetchStoreItems();
	}

	if(gCV_Credits_Distribution.FloatValue > 0.0)
	{
		CreateTimer(gCV_Credits_Distribution.FloatValue, Timer_Credits, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	PrecacheModel("models/weapons/t_arms.mdl", true);
	PrecacheModel("models/weapons/ct_arms.mdl", true);

	DownloadFiles();
}


public void DownloadFiles()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shtore_downloads.ini");
	
	if (!FileExists(sPath))
	{
		LogError("can't find shtore_downloads.ini");
		return;
	}
	
	File file = OpenFile(sPath, "rt");
	while (!file.EndOfFile())
	{
		char cLine[255];
		if (!file.ReadLine(cLine, 255))
		{
			break;
		}
		
		if ((cLine[0] == '/' && cLine[1] == '/') || cLine[0] == ';' || cLine[0] == '\0' || cLine[0] == '#' || cLine[0] == '\n')
		{
			continue;
		}
		
		TrimString(cLine);
		
		if (!FileExists(cLine))
		{
			LogMessage("Error: can't find file '%s'", cLine);
		}
		
		if (StrContains(cLine, ".mdl", false) != -1)
		{
			PrecacheModel(cLine, true);
			if(!IsModelPrecached(cLine))
			{
				LogMessage("Can't PrecacheModel the model: '%s'", cLine);
			}
		}
		
		AddFileToDownloadsTable(cLine);
	}

	delete file;
}

bool LoadStoreConfig(const char[] path)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, path);

	KeyValues kv = new KeyValues("shtore");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	gA_Settings.iServerID = kv.GetNum("server_id", -1);

	delete kv;

	return true;
}

int RealRandomInt(int min, int max)
{
	int random = GetURandomInt();

	if(random == 0)
	{
		random++;
	}

	return (RoundToCeil(float(random) / (2147483647.0 / float(max - min + 1))) + min - 1);
}

public Action EventPlayerSpawn(Event event, const char[] name, bool db)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (!IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return;
	}
	
	store_item_t item;
	
	if (GetClientTeam(client) == CS_TEAM_CT && gA_StoreUsers[client].iEquippedItems[StoreItem_CTPlayerModel] != -1)
	{
		GetItemByID(gA_StoreUsers[client].iEquippedItems[StoreItem_CTPlayerModel], item);
		SetEntityModel(client, item.sValue);
		SetEntPropString(client, Prop_Send, "m_szArmsModel", "models/weapons/ct_arms.mdl");
	}
	
	else if (GetClientTeam(client) == CS_TEAM_T && gA_StoreUsers[client].iEquippedItems[StoreItem_TPlayerModel] != -1)
	{
		GetItemByID(gA_StoreUsers[client].iEquippedItems[StoreItem_TPlayerModel], item);
		SetEntityModel(client, item.sValue);
		SetEntPropString(client, Prop_Send, "m_szArmsModel", "models/weapons/t_arms.mdl");
	}
}

public Action CP_OnChatMessage(int & client, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool & processcolors, bool & removecolors)
{
	store_item_t item;
	
	if (gA_StoreUsers[client].iEquippedItems[StoreItem_ChatTitle] != -1)
	{
		GetItemByID(gA_StoreUsers[client].iEquippedItems[StoreItem_ChatTitle], item);
		Format(name, MAXLENGTH_NAME, "{red}%s {teamcolor}%s", item.sValue, name);
	}
	
	if (gA_StoreUsers[client].iEquippedItems[StoreItem_ChatColor] != -1)
	{
		GetItemByID(gA_StoreUsers[client].iEquippedItems[StoreItem_ChatColor], item);
		Format(message, MAXLENGTH_MESSAGE, "%s%s", item.sValue, message);
	}
	
	return Plugin_Changed;
}

public Action Timer_Credits(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i) || (gCV_Credits_NoSpectators.BoolValue && GetClientTeam(i) <= 1))
		{
			continue;
		}

		int credits = RealRandomInt(gCV_Credits_Min.IntValue, gCV_Credits_Max.IntValue);
		gA_StoreUsers[i].iCredits += credits;

		Shtore_PrintToChat(i, "You have earned \x04%d credits\x01.", credits);
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	delete gA_StoreUsers[client].aItems;
	gA_StoreUsers[client].iDatabaseID = -1;
	gA_StoreUsers[client].iCredits = 0;

	for(int i = 0; i < sizeof(store_user_t::iEquippedItems); i++)
	{
		gA_StoreUsers[client].iEquippedItems[i] = -1;
	}

	GetStoreUser(client);
}

void GetStoreUser(int client)
{
	char sAuth[32];

	if(IsFakeClient(client) || !GetClientAuthId(client, AuthId_Steam3, sAuth, 32))
	{
		return;
	}

	char sQuery[128];
	FormatEx(sQuery, 128, "SELECT id, credits FROM store_users WHERE auth = '%s';", sAuth);
	gH_Database.Query(SQL_GetStoreUser_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_GetStoreUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (get store user) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	char sName[MAX_NAME_LENGTH_SQL];
	GetClientName(client, sName, MAX_NAME_LENGTH_SQL);
	ReplaceString(sName, MAX_NAME_LENGTH_SQL, "#", "?");

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_Database.Escape(sName, sEscapedName, iLength);

	if(results.FetchRow())
	{
		gA_StoreUsers[client].iDatabaseID = results.FetchInt(0);
		gA_StoreUsers[client].iCredits = results.FetchInt(1);

		char sFetchItemsQuery[128];
		FormatEx(sFetchItemsQuery, 128, (gCV_Items_Per_Server.BoolValue)?
				"SELECT item_id FROM store_inventories WHERE owner_id = %d AND server_id = %d;":
				"SELECT item_id FROM store_inventories WHERE owner_id = %d;",
			gA_StoreUsers[client].iDatabaseID, gA_Settings.iServerID);
		gH_Database.Query(SQL_FetchUserInventory_Callback, sFetchItemsQuery, data, DBPrio_High);

		char sFetchEquippedItems[128];
		FormatEx(sFetchEquippedItems, 128, "SELECT item_id, slot FROM store_equipped_items WHERE owner_id = %d;", gA_StoreUsers[client].iDatabaseID);
		gH_Database.Query(SQL_FetchEquippedItems, sFetchEquippedItems, data, DBPrio_High);

		char sUpdateQuery[128];
		FormatEx(sUpdateQuery, 128, "UPDATE store_users SET name = '%s', lastlogin = %d WHERE id = %d;",
			sEscapedName, GetTime(), gA_StoreUsers[client].iDatabaseID);
		gH_Database.Query(SQL_UpdateStoreUser_Callback, sUpdateQuery, 0, DBPrio_High);
	}

	else
	{
		char sAuth[32];

		if(!GetClientAuthId(client, AuthId_Steam3, sAuth, 32))
		{
			KickClient(client, "Authentication failed.");

			return;
		}

		char sQuery[128];
		FormatEx(sQuery, 128, "INSERT INTO store_users (auth, lastlogin, name) VALUES ('%s', %d, '%s');",
			sAuth, GetTime(), sEscapedName);
		gH_Database.Query(SQL_InsertStoreUser_Callback, sQuery, data, DBPrio_High);
	}
}

public void SQL_UpdateStoreUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (update store user) SQL query failed. Reason: %s", error);

		return;
	}
}

public void SQL_InsertStoreUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (insert store user) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		GetStoreUser(client);
	}
}

bool UserHasItemEquipped(store_user_t user, store_item_t item)
{
	for(int i = 0; i < sizeof(store_user_t::iEquippedItems); i++)
	{
		if(item.iItemID == user.iEquippedItems[i])
		{
			return true;
		}
	}

	return false;
}

bool UserOwnsItem(store_user_t user, store_item_t item)
{
	int iLength = user.aItems.Length;

	for(int i = 0; i < iLength; i++)
	{
		int iItemID = user.aItems.Get(i);

		if(item.iItemID == iItemID)
		{
			return true;
		}
	}

	return false;
}

bool GetItemByID(int itemid, store_item_t item)
{
	int iLength = gA_Items.Length;

	for(int i = 0; i < iLength; i++)
	{
		store_item_t tempitem;
		gA_Items.GetArray(i, tempitem);

		if(tempitem.iItemID == itemid)
		{
			item = tempitem;

			return true;
		}
	}

	return false;
}

public void SQL_FetchEquippedItems(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (fetch equipped items) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	bool bInDatabase[sizeof(store_user_t::iEquippedItems)] = { false, ... };

	for(int i = 0; i < sizeof(store_user_t::iEquippedItems); i++)
	{
		gA_StoreUsers[client].iEquippedItems[i] = -1;
	}

	while(results.FetchRow())
	{
		int iItemID = results.FetchInt(0);
		int iSlot = results.FetchInt(1);

		bInDatabase[iSlot] = true;

		store_item_t item;
		GetItemByID(iItemID, item);

		if(gB_CategoryEnabled[item.siType])
		{
			gA_StoreUsers[client].iEquippedItems[iSlot] = iItemID;
		}
	}

	for(int i = 1; i < sizeof(bInDatabase); i++)
	{
		if(!bInDatabase[i])
		{
			char sInsertQuery[256];
			FormatEx(sInsertQuery, 256, "INSERT INTO store_equipped_items (owner_id, slot, item_id) VALUES (%d, %d, -1);", 
				gA_StoreUsers[client].iDatabaseID, i);
			gH_Database.Query(SQL_AddMissingEquip_Callback, sInsertQuery, 0, DBPrio_High);
		}
	}
}

public void SQL_AddMissingEquip_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (add missing equip) SQL query failed. Reason: %s", error);

		return;
	}
}

public void SQL_FetchUserInventory_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (fetch user inventory) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	delete gA_StoreUsers[client].aItems;
	gA_StoreUsers[client].aItems = new ArrayList();

	while(results.FetchRow())
	{
		store_item_t item;
		int iItemID = results.FetchInt(0);

		if(!GetItemByID(iItemID, item) || !item.bEnabled || !gB_CategoryEnabled[item.siType])
		{
			continue;
		}

		#if defined DEBUG
		PrintToChat(client, "%d %s", iItemID, item.sDisplay);
		#endif

		gA_StoreUsers[client].aItems.Push(iItemID);
	}
}

public void OnClientDisconnect(int client)
{
	SaveUserCredits(client);
	SaveEquippedItems(client);

	delete gA_StoreUsers[client].aItems;
}

public Action Command_ReloadStoreItems(int client, int args)
{
	if(gH_Database == null)
	{
		ReplyToCommand(client, "Database is null.");

		return Plugin_Handled;
	}

	FetchStoreCategories(client);
	FetchStoreItems(client);

	return Plugin_Handled;
}

public Action Command_Store(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	return OpenStoreMenu(client);
}

Action OpenStoreMenu(int client, int item = 0)
{
	Menu menu = new Menu(MenuHandler_Store);
	menu.SetTitle("shtore\nCredits: %d\n ", gA_StoreUsers[client].iCredits);

	menu.AddItem("0", "Shop");
	menu.AddItem("1", "Inventory");
	menu.AddItem("2", "Sell");

	menu.ExitButton = true;

	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_Store(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		switch(param2)
		{
			case 0: ShowShopMenu(param1);
			case 1: ShowInventoryMenu(param1);
			case 2: ShowSellMenu(param1);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Shop(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	return ShowShopMenu(client);
}

Action ShowShopMenu(int client, int item = 0)
{
	Menu menu = new Menu(MenuHandler_Shop);
	menu.SetTitle("Shop\nCredits: %d\n ", gA_StoreUsers[client].iCredits);

	for(int i = 1; i < view_as<int>(StoreItem_SIZE); i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		if(!gB_CategoryEnabled[i])
		{
			continue;
		}

		char sCategory[32];
		StoreItemEnumToString(view_as<StoreItem>(i), sCategory, 32);

		menu.AddItem(sInfo, sCategory);
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_Shop(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		gI_Category[param1] = view_as<StoreItem>(StringToInt(sInfo));

		ShowShopSubMenu(param1, gI_Category[param1]);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStoreMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowShopSubMenu(int client, StoreItem category)
{
	char sCategory[32];
	StoreItemEnumToString(view_as<StoreItem>(category), sCategory, 32);

	Menu menu = new Menu(MenuHandler_ShopSubmenu);
	menu.SetTitle("Shop (%s)\nCredits: %d\n ", sCategory, gA_StoreUsers[client].iCredits);

	int iLength = gA_ItemsMenu.Length;

	for(int i = 0; i < iLength; i++)
	{
		store_item_t item;
		gA_ItemsMenu.GetArray(i, item);

		if(item.siType != category || UserOwnsItem(gA_StoreUsers[client], item))
		{
			continue;
		}

		char sInfo[8];
		IntToString(item.iItemID, sInfo, 8);

		char sDisplay[sizeof(store_item_t::sDisplay) + sizeof(store_item_t::sDescription) + 10];

		if(strlen(item.sDescription) > 0)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%s (%d)\n%s\n ", item.sDisplay, item.iPrice, item.sDescription);
		}

		else
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%s (%d)\n ", item.sDisplay, item.iPrice);
		}

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No items found.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 60);
}

public int MenuHandler_ShopSubmenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int iInfo = StringToInt(sInfo);

		if(iInfo == -1)
		{
			ShowShopSubMenu(param1, gI_Category[param1]);

			return 0;
		}

		store_item_t item;
		GetItemByID(iInfo, item);

		if(gA_StoreUsers[param1].iCredits < item.iPrice)
		{
			Shtore_PrintToChat(param1, "The item \x05%s\x01 costs \x04%d credits\x01. You are missing \x04%d credits\x01.",
				item.sDisplay, item.iPrice, item.iPrice - gA_StoreUsers[param1].iCredits);
			ShowShopSubMenu(param1, gI_Category[param1]);

			return 0;
		}

		if(UserOwnsItem(gA_StoreUsers[param1], item))
		{
			Shtore_PrintToChat(param1, "You already own \x05%s\x01", item.sDisplay);
			ShowShopSubMenu(param1, gI_Category[param1]);

			return 0;
		}

		gA_StoreUsers[param1].iCredits -= item.iPrice;
		gA_StoreUsers[param1].aItems.Push(item.iItemID);

		Shtore_PrintToChat(param1, "Successfully purchased \x05%s\x01 for \x04%d credits\x01.", item.sDisplay, item.iPrice);

		SaveUserCredits(param1);
		AddItemToDatabase(param1, item.iItemID);

		ShowShopSubMenu(param1, gI_Category[param1]);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowShopMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}
public Action Command_Inventory(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	return ShowInventoryMenu(client);
}

Action ShowInventoryMenu(int client, int item = 0)
{
	Menu menu = new Menu(MenuHandler_Inventory);
	menu.SetTitle("Inventory\nCredits: %d\n ", gA_StoreUsers[client].iCredits);

	for(int i = 1; i < view_as<int>(StoreItem_SIZE); i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		if(!gB_CategoryEnabled[i])
		{
			continue;
		}

		char sCategory[32];
		StoreItemEnumToString(view_as<StoreItem>(i), sCategory, 32);

		menu.AddItem(sInfo, sCategory);
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_Inventory(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		gI_Category[param1] = view_as<StoreItem>(StringToInt(sInfo));
		
		ShowInventorySubMenu(param1, gI_Category[param1]);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStoreMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowInventorySubMenu(int client, StoreItem category)
{
	char sCategory[32];
	StoreItemEnumToString(view_as<StoreItem>(category), sCategory, 32);

	Menu menu = new Menu(MenuHandler_InventorySubMenu);
	menu.SetTitle("Inventory (%s)\nCredits: %d\n ", sCategory, gA_StoreUsers[client].iCredits);

	int iLength = gA_StoreUsers[client].aItems.Length;

	for(int i = 0; i < iLength; i++)
	{
		int iItemID = gA_StoreUsers[client].aItems.Get(i);
	
		store_item_t item;
		GetItemByID(iItemID, item);

		if(item.siType != category)
		{
			continue;
		}

		char sDisplay[sizeof(store_item_t::sDisplay) + sizeof(store_item_t::sDescription) + 10];

		if(strlen(item.sDescription) > 0)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%s (%d)\n%s\n ", item.sDisplay, item.iPrice, item.sDescription);
		}

		else
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%s (%d)\n ", item.sDisplay, item.iPrice);
		}
		
		if(UserHasItemEquipped(gA_StoreUsers[client], item))
		{
			Format(sDisplay, sizeof(sDisplay), "(EQUIPPED) %s", sDisplay);
		}

		char sInfo[8];
		IntToString(item.iItemID, sInfo, 8);

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No items found.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 60);
}

public int MenuHandler_InventorySubMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int iInfo = StringToInt(sInfo);

		if(iInfo == -1)
		{
			ShowInventorySubMenu(param1, gI_Category[param1]);

			return 0;
		}
		
		store_item_t item;
		GetItemByID(iInfo, item);

		if(gA_StoreUsers[param1].iEquippedItems[item.siType] == item.iItemID)
		{
			gA_StoreUsers[param1].iEquippedItems[item.siType] = -1;
		}

		else
		{
			gA_StoreUsers[param1].iEquippedItems[item.siType] = item.iItemID;
		}

		ShowInventorySubMenu(param1, gI_Category[param1]);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowInventoryMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Sell(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	return ShowSellMenu(client);
}

Action ShowSellMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Sell);

	if(gCV_Refund_Tax.FloatValue > 0.0)
	{
		menu.SetTitle("Sell\nYou cannot sell equipped items.\nYou will be taxed %d%% of the listed price.\nCredits: %d\n ", RoundToZero(gCV_Refund_Tax.FloatValue * 100), gA_StoreUsers[client].iCredits);
	}

	else
	{
		menu.SetTitle("Sell\nYou cannot sell equipped items.\nYou will receive a full refund.\nCredits: %d\n ", gA_StoreUsers[client].iCredits);
	}

	int iLength = gA_StoreUsers[client].aItems.Length;

	for(int i = 0; i < iLength; i++)
	{
		int iItemID = gA_StoreUsers[client].aItems.Get(i);

		store_item_t item;
		GetItemByID(iItemID, item);

		// no equipped items
		if(gA_StoreUsers[client].iEquippedItems[item.siType] == iItemID)
		{
			continue;
		}

		char sDisplay[sizeof(store_item_t::sDisplay) + 10];
		FormatEx(sDisplay, sizeof(sDisplay), "%s (%d)", item.sDisplay, item.iPrice);

		char sInfo[8];
		IntToString(iItemID, sInfo, 8);

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No items found.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_Sell(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int iInfo = StringToInt(sInfo);

		if(iInfo == -1)
		{
			ShowSellMenu(param1);

			return 0;
		}

		store_item_t item;
		GetItemByID(iInfo, item);

		if(!UserOwnsItem(gA_StoreUsers[param1], item))
		{
			Shtore_PrintToChat(param1, "You do not own \x05%s\x01.", item.sDisplay);
			ShowSellMenu(param1);

			return 0;
		}

		int iRefund = RoundToFloor(item.iPrice - (item.iPrice * gCV_Refund_Tax.FloatValue));
		gA_StoreUsers[param1].iCredits += iRefund;
		SaveUserCredits(param1);

		int index = gA_StoreUsers[param1].aItems.FindValue(item.iItemID);
		gA_StoreUsers[param1].aItems.Erase(index);
		RemoveItemFromDatabase(param1, item.iItemID);

		Shtore_PrintToChat(param1, "You have returned \x05%s\x01 to the store and received a refund of \x04%d credits\x01.", item.sDisplay, iRefund);

		ShowSellMenu(param1);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStoreMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Credits(int client, int args)
{
	int iStoreUser = client;
	int target = -1;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, false, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}

		iStoreUser = target;
	}

	if(gA_StoreUsers[iStoreUser].iDatabaseID != -1)
	{
		Shtore_PrintToChat(client, "\x03%N\x01 has \x04%d credits\x01.", iStoreUser, gA_StoreUsers[iStoreUser].iCredits);
	}

	else
	{
		Shtore_PrintToChat(client, "\x03%N\x01 is not present in the shtore database.", iStoreUser);
	}

	return Plugin_Handled;
}

void SQL_DBConnect()
{
	delete gH_Database;

	if(!SQL_CheckConfig("shtore"))
	{
		SetFailState("no shtore config, cya bro");
	}

	char sError[255];
	gH_Database = SQL_Connect("shtore", true, sError, 255);

	if(gH_Database == null)
	{
		SetFailState("shtore startup failed. Reason: %s", sError);
	}

	// support unicode names
	if(!gH_Database.SetCharset("utf8mb4"))
	{
		gH_Database.SetCharset("utf8");
	}
}

void SaveUserCredits(int client)
{
	if(gA_StoreUsers[client].iDatabaseID != -1)
	{
		char sName[MAX_NAME_LENGTH_SQL];
		GetClientName(client, sName, MAX_NAME_LENGTH_SQL);
		ReplaceString(sName, MAX_NAME_LENGTH_SQL, "#", "?");

		char sUpdateQuery[128];
		FormatEx(sUpdateQuery, 128, "UPDATE store_users SET name = '%s', lastlogin = %d, credits = %d WHERE id = %d;",
			sName, GetTime(), gA_StoreUsers[client].iCredits, gA_StoreUsers[client].iDatabaseID);
		gH_Database.Query(SQL_UpdateStoreUser_Callback, sUpdateQuery, 0, DBPrio_High);
	}
}

void SaveEquippedItems(int client)
{
	for(int i = 1; i < sizeof(store_user_t::iEquippedItems); i++)
	{
		char sUpdateQuery[128];
		FormatEx(sUpdateQuery, 128, "UPDATE store_equipped_items SET item_id = %d WHERE owner_id = %d AND slot = %d;",
			gA_StoreUsers[client].iEquippedItems[i], gA_StoreUsers[client].iDatabaseID, i);
		gH_Database.Query(SQL_SaveEquippedItems_Callback, sUpdateQuery, 0, DBPrio_High);
	}
}

public void SQL_SaveEquippedItems_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (save equipped items) SQL query failed. Reason: %s", error);

		return;
	}
}

void AddItemToDatabase(int client, int itemid)
{
	char sInsertQuery[128];
	FormatEx(sInsertQuery, 128, "INSERT INTO store_inventories (item_id, owner_id, server_id) VALUES (%d, %d, %d);",
		itemid, gA_StoreUsers[client].iDatabaseID, gA_Settings.iServerID);
	gH_Database.Query(SQL_AddUserItem_Callback, sInsertQuery, 0, DBPrio_High);
}

public void SQL_AddUserItem_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (add user item) SQL query failed. Reason: %s", error);

		return;
	}
}

void RemoveItemFromDatabase(int client, int itemid)
{
	char sDeleteQuery[128];
	FormatEx(sDeleteQuery, 128, (gCV_Items_Per_Server.BoolValue)?
			"DELETE FROM store_inventories WHERE item_id = %d AND owner_id = %d AND server_id = %d;":
			"DELETE FROM store_inventories WHERE item_id = %d AND owner_id = %d;",
		itemid, gA_StoreUsers[client].iDatabaseID, gA_Settings.iServerID);
	gH_Database.Query(SQL_DeleteUserItem_Callback, sDeleteQuery, 0, DBPrio_High);
}

public void SQL_DeleteUserItem_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (delete user item) SQL query failed. Reason: %s", error);

		return;
	}
}

void FetchStoreCategories(int client = 0)
{
	int serial = -1;

	if(client != 0)
	{
		serial = GetClientSerial(client);
	}

	for(int i = 0; i <= SHOTRE_CATEGORIES; i++)
	{
		gB_CategoryEnabled[i] = false;
	}

	char sQuery[128];
	FormatEx(sQuery, 128, "SELECT categories FROM store_categories WHERE server_id = %d;", gA_Settings.iServerID);
	gH_Database.Query(SQL_FetchCategories_Callback, sQuery, serial, DBPrio_High);
}

public void SQL_FetchCategories_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (item categories) SQL query failed. Reason: %s", error);

		return;
	}

	if(!results.FetchRow())
	{
		SetFailState("Could not find categories for server_id %d!", gA_Settings.iServerID);

		return;
	}

	char sCategories[128];
	results.FetchString(0, sCategories, 128);

	if(strlen(sCategories) == 0)
	{
		SetFailState("Could not find categories for server_id %d!", gA_Settings.iServerID);

		return;
	}

	char sCategoriesExploded[SHOTRE_CATEGORIES][32];
	int iExplodedStrings = ExplodeString(sCategories, ",", sCategoriesExploded, SHOTRE_CATEGORIES, 32, false);

	for(int i = 0; i < iExplodedStrings; i++)
	{
		StoreItem iCategory = StoreItemToEnum(sCategoriesExploded[i]);
		gB_CategoryEnabled[iCategory] = true;
	}

	PrintToSerialNumber(data, "Successfully fetched shtore categories.");
}

void FetchStoreItems(int client = 0)
{
	int serial = -1;

	if(client != 0)
	{
		serial = GetClientSerial(client);
	}

	gH_Database.Query(SQL_FetchItems_Callback, "SELECT id, enabled, type, price, display, description, value FROM store_items;", serial, DBPrio_High);
}

public int StoreItems_SortAscending(int index1, int index2, any array, any hndl)
{
	store_item_t item;
	view_as<ArrayList>(array).GetArray(index1, item);
	int price1 = item.iPrice;

	view_as<ArrayList>(array).GetArray(index2, item);
	int price2 = item.iPrice;

	if(price1 < price2)
	{
		return -1;
	}

	else if(price1 == price2)
	{
		return 0;
	}

	else
	{
		return 1;
	}
}

public void SQL_FetchItems_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (item fetch) SQL query failed. Reason: %s", error);

		return;
	}

	gA_Items.Clear();
	delete gA_ItemsMenu;

	while(results.FetchRow())
	{
		char sType[32];
		store_item_t item;
		item.iItemID = results.FetchInt(0);
		item.bEnabled = view_as<bool>(results.FetchInt(1));
		results.FetchString(2, sType, 32);
		item.siType = StoreItemToEnum(sType);
		item.iPrice = results.FetchInt(3);
		results.FetchString(4, item.sDisplay, 32);
		results.FetchString(5, item.sDescription, 64);
		results.FetchString(6, item.sValue, PLATFORM_MAX_PATH);

		if(!gB_CategoryEnabled[item.siType])
		{
			continue;
		}

		gA_Items.PushArray(item);
	}

	gA_ItemsMenu = gA_Items.Clone();
	SortADTArrayCustom(gA_ItemsMenu, StoreItems_SortAscending);

	#if defined DEBUG
	PrintToServer("---");
	int iLength = gA_Items.Length;

	for(int i = 0; i < iLength; i++)
	{
		store_item_t item;
		gA_Items.GetArray(i, item);

		PrintToServer("[%d] Item ID: %d | %s | Type: %d | Price: %d | Display: \"%s\" | Description: \"%s\" | Value: \"%s\"",
			i, item.iItemID, (item.bEnabled)? "Enabled":"Disabled", item.siType, item.iPrice, item.sDisplay, item.sDescription, item.sValue);
	}

	PrintToServer("---");
	#endif

	PrintToSerialNumber(data, "Successfully fetched shtore items.");

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public int Native_GetUser(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	SetNativeArray(2, gA_StoreUsers[client], sizeof(store_user_t));
}

public int Native_LogMessage(Handle plugin, int numParams)
{
	char sPlugin[32];

	if(!GetPluginInfo(plugin, PlInfo_Name, sPlugin, 32))
	{
		GetPluginFilename(plugin, sPlugin, 32);
	}

	static int iWritten = 0;

	char sBuffer[300];
	FormatNativeString(0, 1, 2, 300, iWritten, sBuffer);
	
	LogToFileEx(gS_LogPath, "[%s] %s", sPlugin, sBuffer);
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!IsClientInGame(client))
	{
		return;
	}

	static int iWritten = 0; // useless?

	char sBuffer[300];
	FormatNativeString(0, 2, 3, 300, iWritten, sBuffer);
	Format(sBuffer, 300, SHTORE_PREFIX ... " %s", sBuffer);

	if(GetEngineVersion() != Engine_CSGO)
	{
		Handle hSayText2 = StartMessageOne("SayText2", client);

		if(hSayText2 != null)
		{
			BfWriteByte(hSayText2, 0);
			BfWriteByte(hSayText2, true);
			BfWriteString(hSayText2, sBuffer);
		}

		EndMessage();
	}

	else
	{
		PrintToChat(client, " %s", sBuffer);
	}
}

public int Native_SetCredits(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int credits = GetNativeCell(2);

	gA_StoreUsers[client].iCredits = credits;
}
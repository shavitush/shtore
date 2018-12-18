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
#include <shtore>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

// float gF_Refund_Rate = 0.75;

Database gH_Database = null;
ArrayList gA_Items = null;

int gI_Credits[MAXPLAYERS+1];
StoreItem gI_Category[MAXPLAYERS+1];
store_user_t gA_StoreUsers[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "shtore",
	author = "shavit",
	description = "Simple SourceMod store plugin.",
	version = SHTORE_VERSION,
	url = "https://github.com/shavitush/shtore"
}

public void OnPluginStart()
{
	// globals
	gA_Items = new ArrayList(sizeof(store_item_t));
	SQL_DBConnect();

	// admin commands
	RegAdminCmd("sm_reloadstoreitems", Command_ReloadStoreItems, ADMFLAG_RCON, "Fetches shtore items from database.");

	// player commands
	RegConsoleCmd("sm_store", Command_Store, "Opens the shtore menu.");
	RegConsoleCmd("sm_shop", Command_Shop, "Opens the shop menu.");
	RegConsoleCmd("sm_inv", Command_Inventory, "Opens your inventory.");
	RegConsoleCmd("sm_inventory", Command_Inventory, "Opens your inventory.");
	RegConsoleCmd("sm_sell", Command_Sell, "Sell an item.");
	RegConsoleCmd("sm_credits", Command_Credits, "Show your or someone else's credits. Usage: sm_credits [target]");

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnMapStart()
{
	if(gH_Database != null)
	{
		FetchStoreItems();
	}
}

public void OnClientPutInServer(int client)
{
	delete gA_StoreUsers[client].aItems;
	gA_StoreUsers[client].iDatabaseID = -1;
	gA_StoreUsers[client].iCredits = 0;

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

	if(results.FetchRow())
	{
		gA_StoreUsers[client].iDatabaseID = results.FetchInt(0);
		gA_StoreUsers[client].iCredits = results.FetchInt(1);

		// TODO: fetch inventory and equipped items

		char sUpdateQuery[128];
		FormatEx(sUpdateQuery, 128, "UPDATE store_users SET name = '%s', lastlogin = %d WHERE id = %d;",
			sName, GetTime(), gA_StoreUsers[client].iDatabaseID);

		gH_Database.Query(SQL_InsertStoreUser_Callback, sUpdateQuery, data, DBPrio_High);
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
			sAuth, GetTime(), sName);

		gH_Database.Query(SQL_InsertStoreUser_Callback, sQuery, data, DBPrio_High);
	}
}

public void SQL_InsertStoreUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("shtore (insert store user) SQL query failed. Reason: %s", error);

		return;
	}
}

public void OnClientDisconnect(int client)
{
	// TODO: update db
	// TODO: move to update
	delete gA_StoreUsers[client].aItems;
}

public Action Command_ReloadStoreItems(int client, int args)
{
	if(gH_Database == null)
	{
		ReplyToCommand(client, "Database is null.");

		return Plugin_Handled;
	}

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
	menu.SetTitle("shtore\nCredits: %d\n ", gI_Credits[client]);

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
			case 0: OpenShopMenu(param1, true);
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

	return OpenShopMenu(client, false);
}

Action OpenShopMenu(int client, bool submenu, int item = 0)
{
	Menu menu = new Menu(MenuHandler_Shop);
	menu.SetTitle("Shop\nCredits: %d\n ", gI_Credits[client]);

	for(int i = 1; i < view_as<int>(StoreItem_SIZE); i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sCategory[32];
		StoreItemEnumToString(view_as<StoreItem>(i), sCategory, 32);

		menu.AddItem(sInfo, sCategory);
	}

	menu.ExitButton = true;
	menu.ExitBackButton = submenu;

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
	menu.SetTitle("Shop (%s)\nCredits: %d\n ", sCategory, gI_Credits[client]);

	int iLength = gA_Items.Length;

	for(int i = 0; i < iLength; i++)
	{
		store_item_t item;
		gA_Items.GetArray(i, item);

		if(item.siType != category)
		{
			continue;
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

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

		// TODO: don't show items that you already own
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No available items.");
	}

	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, 60);
}

public int MenuHandler_ShopSubmenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		ShowShopSubMenu(param1, gI_Category[param1]);

		// TODO: buy item, add to inventory
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenShopMenu(param1, true);
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

	// TODO: open menu

	return Plugin_Handled;
}

public Action Command_Sell(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	// TODO: open menu

	return Plugin_Handled;
}

public Action Command_Credits(int client, int args)
{
	// TODO: implement

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

void FetchStoreItems(int client = 0)
{
	int serial = -1;

	if(client != 0)
	{
		serial = GetClientSerial(client);
	}

	gH_Database.Query(SQL_FetchItems_Callback, "SELECT type, price, display, description, value FROM store_items;", serial, DBPrio_High);
}

public int StoreItems_SortAscending(int index1, int index2, Handle array, Handle hndl)
{
	store_item_t item;
	GetArrayArray(array, index1, item);
	int price1 = item.iPrice;

	GetArrayArray(array, index2, item);
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

	while(results.FetchRow())
	{
		store_item_t item;

		char sType[32];
		results.FetchString(0, sType, 32);
		item.siType = StoreItemToEnum(sType);
		item.iPrice = results.FetchInt(1);
		results.FetchString(2, item.sDisplay, 32);
		results.FetchString(3, item.sDescription, 64);
		results.FetchString(4, item.sValue, PLATFORM_MAX_PATH);

		gA_Items.PushArray(item);
	}

	SortADTArrayCustom(gA_Items, StoreItems_SortAscending);

	#if defined DEBUG
	PrintToServer("---");
	int iLength = gA_Items.Length;

	for(int i = 0; i < iLength; i++)
	{
		store_item_t item;
		gA_Items.GetArray(i, item);

		PrintToServer("[%d] Type: %d | Price: %d | Display: \"%s\" | Description: \"%s\" | Value: \"%s\"",
			i, item.siType, item.iPrice, item.sDisplay, item.sDescription, item.sValue);
	}

	PrintToServer("---");
	#endif

	PrintToSerialNumber(data, "Successfully fetched shtore items.");
}

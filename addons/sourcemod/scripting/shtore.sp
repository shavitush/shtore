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

Database gH_Database = null;
ArrayList gA_Items = null;

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
	gA_Items = new ArrayList(sizeof(store_item_t));

	SQL_DBConnect();
}

public void OnMapStart()
{
	if(gH_Database != null)
	{
		FetchStoreItems();
	}
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

void FetchStoreItems()
{
	if(gH_Database == null)
	{
		return;
	}

	gH_Database.Query(SQL_FetchItems_Callback, "SELECT type, price, display, description, value FROM store_items;", 0, DBPrio_High);
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
}

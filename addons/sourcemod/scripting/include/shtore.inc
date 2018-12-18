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

#if defined _shtore_included
	#endinput
#endif
#define _shtore_included

#define PREFIX "\x04[shtore]\x01"
#define SHTORE_VERSION "1.0"
#define MAX_NAME_LENGTH_SQL 32

enum StoreItem
{
	StoreItem_Unknown,
	StoreItem_PlayerModel,
	StoreItem_ChatTitle,
	StoreItem_ChatColor
};

enum struct store_item_t
{
	char sDisplay[32];
	char sDescription[64];
	char sValue[PLATFORM_MAX_PATH];
	StoreItem siType;
	int iPrice;
};

stock StoreItem StoreItemToEnum(const char[] input)
{
	if(StrEqual(input, "playermodel"))
	{
		return StoreItem_PlayerModel;
	}

	else if(StrEqual(input, "chattitle"))
	{
		return StoreItem_ChatTitle;
	}

	else if(StrEqual(input, "chatcolor"))
	{
		return StoreItem_ChatColor;
	}

	return StoreItem_Unknown;
}

/**
 * Use this native when printing anything in chat if it's related to the timer.
 * This native will auto-assign colors and a chat prefix.
 *
 * @param client					Client index.
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @return							PrintToChat()
 */
native int Shtore_PrintToChat(int client, const char[] format, any ...);

/**
 * Logs an entry to shtore's log file.
 * (addons/sourcemod/logs/shtore.log)
 *
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @noreturn
 */
native void Shtore_LogMessage(const char[] format, any ...);

// same as Shtore_PrintToChat() but loops through the whole server
// code stolen from the base halflife.inc file
stock void Shtore_PrintToChatAll(const char[] format, any ...)
{
	char[] buffer = new char[300];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, 300, format, 2);
			Shtore_PrintToChat(i, "%s", buffer);
		}
	}
}

public SharedPlugin __pl_shtore =
{
	name = "shtore",
	file = "shtore.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shtore_SetNTVOptional()
{
	
}
#endif

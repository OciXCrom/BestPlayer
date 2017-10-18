#include <amxmodx>
#include <hamsandwich>
#include <nvault>

#define PLUGIN_VERSION "1.0"
#define MOTD_BEST "addons/amxmodx/configs/BestPlayer.txt"
#define MOTD_STATS "addons/amxmodx/configs/BestPlayerStats.txt"
#define MAX_MOTD_LENGTH 1536
#define MAX_HEADER_LENGTH 32
#define MAX_FORMULA_CYCLES 10

#define ARG_MAP "$map$"
#define ARG_NAME "$name$"
#define ARG_WINS "$wins$"
#define ARG_KILLS "$kills$"
#define ARG_KILLS_SB "$kills_sb$"
#define ARG_DEATHS "$deaths$"
#define ARG_DEATHS_SB "$deaths_sb$"
#define ARG_HEADSHOTS "$headshots$"
#define ARG_HITS "$hits$"
#define ARG_DAMAGE "$damage$"
#define ARG_KDRATIO "$kdratio$"
#define ARG_KDRATIO_SB "$kdratio_sb$"
#define ARG_HSRATIO "$hsratio$"

enum _:Cvars
{
	bpm_formula,
	bpm_min_players,
	bpm_motd_header,
	bpm_stats_header,
	bpm_save_type
}

enum _:PlayerData
{
	PDATA_INFO[35],
	PDATA_WINS,
	PDATA_KILLS,
	PDATA_KILLS_SB,
	PDATA_DEATHS,
	PDATA_DEATHS_SB,
	PDATA_HEADSHOTS,
	PDATA_HITS,
	Float:PDATA_DAMAGE,
	Float:PDATA_KDRATIO,
	Float:PDATA_KDRATIO_SB,
	Float:PDATA_HSRATIO
}

new g_eCvars[Cvars], g_iSaveType, g_iVault
new g_ePlayerData[33][PlayerData], g_szStats[MAX_MOTD_LENGTH], g_szMap[32]

public plugin_init()
{
	register_plugin("Best Player MOTD", PLUGIN_VERSION, "OciXCrom")
	register_cvar("CRXBestPlayer", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED)
	
	RegisterHam(Ham_TakeDamage, "player", "OnTakeDamage", 1)
	register_event("DeathMsg", "OnPlayerKilled", "a")
	register_message(SVC_INTERMISSION, "OnIntermission")
	register_logevent("OnRestartRound", 2, "0=World triggered", "1&Restart_Round_")
	register_clcmd("say /mystats", "Cmd_MyStats")
	register_clcmd("say_team /mystats", "Cmd_MyStats")
	
	g_eCvars[bpm_formula] = register_cvar("bpm_formula", "157")
	g_eCvars[bpm_min_players] = register_cvar("bpm_min_players", "6")
	g_eCvars[bpm_motd_header] = register_cvar("bpm_motd_header", "Best Player: $name$")
	g_eCvars[bpm_stats_header] = register_cvar("bpm_stats_header", "Player Stats: $name$")
	g_eCvars[bpm_save_type] = register_cvar("bpm_save_type", "0")
	get_mapname(g_szMap, charsmax(g_szMap))
	g_iVault = nvault_open("BestPlayer")
}

public plugin_cfg()
	g_iSaveType = get_pcvar_num(g_eCvars[bpm_save_type])
	
public plugin_end()
	nvault_close(g_iVault)

public client_putinserver(id)
{
	reset_player_stats(id)	
	get_user_saveinfo(id, g_ePlayerData[id][PDATA_INFO], charsmax(g_ePlayerData[][PDATA_INFO]))
	use_vault(id, 1, g_ePlayerData[id][PDATA_INFO])
}

public client_disconnect(id)
	use_vault(id, 0, g_ePlayerData[id][PDATA_INFO])

public client_infochanged(id)
{
	if(g_iSaveType > 0)
		return
		
	static szNewName[32], szOldName[32]
	get_user_info(id, "name", szNewName, charsmax(szNewName))
	get_user_name(id, szOldName, charsmax(szOldName))
	
	if(!equali(szNewName, szOldName))
	{
		strtolower(szNewName); strtolower(szOldName)
		copy(g_ePlayerData[id][PDATA_INFO], charsmax(g_ePlayerData[][PDATA_INFO]), szNewName)
		
		use_vault(id, 0, szOldName)
		use_vault(id, 1, szNewName)
	}
}

public Cmd_MyStats(id)
{
	if(!g_szStats[0])
		LoadFileForMe(MOTD_STATS, g_szStats, charsmax(g_szStats))
		
	static szMotd[MAX_MOTD_LENGTH]
	new szHeader[MAX_HEADER_LENGTH]
	copy(szMotd, charsmax(szMotd), g_szStats)
	get_pcvar_string(g_eCvars[bpm_stats_header], szHeader, charsmax(szHeader))
	calculate_stats(id)
	apply_replacements(id, szMotd, charsmax(szMotd))
	apply_replacements(id, szHeader, charsmax(szHeader))
	show_motd(id, szMotd, szHeader)
	return PLUGIN_HANDLED
}

public OnRestartRound()
{
	new iPlayers[32], iPnum
	get_players(iPlayers, iPnum)
	
	for(new i; i < iPnum; i++)
		reset_player_stats(iPlayers[i])
}

public OnTakeDamage(iVictim, iInflictor, iAttacker, Float:fDamage, iDamageBits)
{
	if(is_user_alive(iAttacker) && iAttacker != iVictim)
	{
		g_ePlayerData[iAttacker][PDATA_HITS]++
		g_ePlayerData[iAttacker][PDATA_DAMAGE] += fDamage
	}
}

public OnPlayerKilled()
{
	new iAttacker = read_data(1),
		iVictim = read_data(2)
		
	g_ePlayerData[iVictim][PDATA_DEATHS]++
		
	if(is_user_connected(iAttacker) && iAttacker != iVictim)
	{
		g_ePlayerData[iAttacker][PDATA_KILLS]++
		
		if(read_data(3))
			g_ePlayerData[iAttacker][PDATA_HEADSHOTS]++
	}
}

public OnIntermission()
{
	new iPlayers[32], iPnum
	get_players(iPlayers, iPnum)
	
	if(!iPnum || iPnum < get_pcvar_num(g_eCvars[bpm_min_players]))
		return PLUGIN_CONTINUE
		
	new szFormula[MAX_FORMULA_CYCLES], iBest = iPlayers[0]
	get_pcvar_string(g_eCvars[bpm_formula], szFormula, charsmax(szFormula))
	
	new iLen = strlen(szFormula)
	
	for(new i, j, iPlayer, iScore, any:iBestScore; i < iPnum; i++)
	{
		iPlayer = iPlayers[i]
		calculate_stats(iPlayer)
		
		for(j = 0; j < iLen; j++)
		{
			iScore = get_score_by_formula(iPlayer, j, szFormula)
			iBestScore = get_score_by_formula(iBest, j, szFormula)
			
			if(iScore > iBestScore)
			{
				iBest = iPlayer
				break
			}
			else if(iScore == iBestScore)
			{
				if(j + 1 == iLen)
					break
					
				if(get_score_by_formula(iPlayer, j + 1, szFormula) > get_score_by_formula(iBest, j + 1, szFormula))
				{
					iPlayer = iBest
					break
				}
			}
		}
	}

	new bool:bNonZero
	
	for(new i; i < iLen; i++)
	{
		if(get_score_by_formula(iBest, i, szFormula) != 0)
		{
			bNonZero = true
			break
		}
	}
	
	if(!bNonZero)
		return PLUGIN_CONTINUE
	
	g_ePlayerData[iBest][PDATA_WINS]++
	
	new szMotd[MAX_MOTD_LENGTH], szHeader[MAX_HEADER_LENGTH]
	LoadFileForMe(MOTD_BEST, szMotd, charsmax(szMotd))
	get_pcvar_string(g_eCvars[bpm_motd_header], szHeader, charsmax(szHeader))
	apply_replacements(iBest, szMotd, charsmax(szMotd))
	apply_replacements(iBest, szHeader, charsmax(szHeader))
	show_motd(0, szMotd, szHeader)
	send_intermission()
	return PLUGIN_HANDLED
}

bool:has_argument(const szMessage[], const szArgument[])
	return contain(szMessage, szArgument) != -1

any:get_score_by_formula(const id, const iNum, const szFormula[])
{
	switch(szFormula[iNum])
	{
		case '0': return g_ePlayerData[id][PDATA_WINS]
		case '1': return g_ePlayerData[id][PDATA_KILLS]
		case '2': return g_ePlayerData[id][PDATA_KILLS_SB]
		case '3': return g_ePlayerData[id][PDATA_DEATHS] * -1
		case '4': return g_ePlayerData[id][PDATA_DEATHS_SB] * -1
		case '5': return g_ePlayerData[id][PDATA_HEADSHOTS]
		case '6': return g_ePlayerData[id][PDATA_HITS]
		case '7': return g_ePlayerData[id][PDATA_DAMAGE]
		case '8': return g_ePlayerData[id][PDATA_KDRATIO]
		case '9': return g_ePlayerData[id][PDATA_KDRATIO_SB]
		case 'a': return g_ePlayerData[id][PDATA_HSRATIO]
	}
	
	return 0
}

apply_replacements(const id, szMessage[], const iLen)
{	
	if(has_argument(szMessage, ARG_MAP))
		replace_all(szMessage, iLen, ARG_MAP, g_szMap)
		
	if(has_argument(szMessage, ARG_NAME))
	{
		static szBuffer[32]
		get_user_name(id, szBuffer, charsmax(szBuffer))
		replace_all(szMessage, iLen, ARG_NAME, szBuffer)
	}
	
	if(has_argument(szMessage, ARG_WINS))
		replace_num(szMessage, iLen, ARG_WINS, g_ePlayerData[id][PDATA_WINS])
		
	if(has_argument(szMessage, ARG_KILLS))
		replace_num(szMessage, iLen, ARG_KILLS, g_ePlayerData[id][PDATA_KILLS])
		
	if(has_argument(szMessage, ARG_KILLS_SB))
		replace_num(szMessage, iLen, ARG_KILLS_SB, g_ePlayerData[id][PDATA_KILLS_SB])
		
	if(has_argument(szMessage, ARG_DEATHS))
		replace_num(szMessage, iLen, ARG_DEATHS, g_ePlayerData[id][PDATA_DEATHS])
		
	if(has_argument(szMessage, ARG_DEATHS_SB))
		replace_num(szMessage, iLen, ARG_DEATHS_SB, g_ePlayerData[id][PDATA_DEATHS_SB])
		
	if(has_argument(szMessage, ARG_HEADSHOTS))
		replace_num(szMessage, iLen, ARG_HEADSHOTS, g_ePlayerData[id][PDATA_HEADSHOTS])
		
	if(has_argument(szMessage, ARG_HITS))
		replace_num(szMessage, iLen, ARG_HITS, g_ePlayerData[id][PDATA_HITS])
		
	if(has_argument(szMessage, ARG_DAMAGE))
		replace_num_f(szMessage, iLen, ARG_DAMAGE, g_ePlayerData[id][PDATA_DAMAGE])
		
	if(has_argument(szMessage, ARG_KDRATIO))
		replace_num_f(szMessage, iLen, ARG_KDRATIO, g_ePlayerData[id][PDATA_KDRATIO])
		
	if(has_argument(szMessage, ARG_KDRATIO_SB))
		replace_num_f(szMessage, iLen, ARG_KDRATIO_SB, g_ePlayerData[id][PDATA_KDRATIO_SB])
		
	if(has_argument(szMessage, ARG_HSRATIO))
		replace_num_f(szMessage, iLen, ARG_HSRATIO, g_ePlayerData[id][PDATA_HSRATIO])
}

reset_player_stats(const id)
{
	g_ePlayerData[id][PDATA_WINS] = 0
	g_ePlayerData[id][PDATA_KILLS] = 0
	g_ePlayerData[id][PDATA_KILLS_SB] = 0
	g_ePlayerData[id][PDATA_DEATHS] = 0
	g_ePlayerData[id][PDATA_DEATHS_SB] = 0
	g_ePlayerData[id][PDATA_HEADSHOTS] = 0
	g_ePlayerData[id][PDATA_HITS] = 0
	g_ePlayerData[id][PDATA_DAMAGE] = _:0.0
	g_ePlayerData[id][PDATA_KDRATIO] = _:0.0
	g_ePlayerData[id][PDATA_KDRATIO_SB] = _:0.0
	g_ePlayerData[id][PDATA_HSRATIO] = _:0.0
}

use_vault(const id, const iType, const szInfo[])
{
	if(!szInfo[0])
		return
	
	switch(iType)
	{
		case 0:
		{
			new szWins[10]
			num_to_str(g_ePlayerData[id][PDATA_WINS], szWins, charsmax(szWins))
			nvault_set(g_iVault, szInfo, szWins)
		}
		case 1:	g_ePlayerData[id][PDATA_WINS] = nvault_get(g_iVault, szInfo)
	}
}

get_user_saveinfo(const id, szInfo[], const iLen)
{
	switch(g_iSaveType)
	{
		case 0: { get_user_name(id, szInfo, iLen); strtolower(szInfo); }
		case 1: get_user_ip(id, szInfo, iLen, 1)
		case 2: get_user_authid(id, szInfo, iLen)
	}
}

calculate_stats(const id)
{
	g_ePlayerData[id][PDATA_KILLS_SB] = get_user_frags(id)
	g_ePlayerData[id][PDATA_DEATHS_SB] = get_user_deaths(id)
	g_ePlayerData[id][PDATA_KDRATIO] = g_ePlayerData[id][PDATA_DEATHS] ? (float(g_ePlayerData[id][PDATA_KILLS]) / float(g_ePlayerData[id][PDATA_DEATHS])) : float(g_ePlayerData[id][PDATA_KILLS])
	g_ePlayerData[id][PDATA_KDRATIO_SB] = g_ePlayerData[id][PDATA_DEATHS_SB] ? (float(g_ePlayerData[id][PDATA_KILLS_SB]) / float(g_ePlayerData[id][PDATA_DEATHS_SB])) : float(g_ePlayerData[id][PDATA_KILLS_SB])
	g_ePlayerData[id][PDATA_HSRATIO] = g_ePlayerData[id][PDATA_HEADSHOTS] ? (float(g_ePlayerData[id][PDATA_HEADSHOTS]) / float(g_ePlayerData[id][PDATA_KILLS])) : float(g_ePlayerData[id][PDATA_HEADSHOTS])
}

replace_num(szMessage[], const iLen, const szPlaceholder[], const iNum)
{
	static szBuffer[32]
	num_to_str(iNum, szBuffer, charsmax(szBuffer))
	replace_all(szMessage, iLen, szPlaceholder, szBuffer)
}

replace_num_f(szMessage[], const iLen, const szPlaceholder[], const Float:fNum)
{
	static szBuffer[32]
	formatex(szBuffer, charsmax(szBuffer), "%.2f", fNum)
	replace_all(szMessage, iLen, szPlaceholder, szBuffer)
}

send_intermission()
{
	message_begin(MSG_ALL, SVC_FINALE)
	write_string("")
	message_end()
}

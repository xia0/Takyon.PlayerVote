global function VoteMapInit
global function FillProposedMaps
global function CommandVote
global function OnPlayerSpawnedMap
global function OnPlayerDisconnectedMap
global function PlayingMap
global function PostmatchMap

array<string> playerMapVoteNames = [] // list of players who have voted, is used to see how many have voted
bool voteMapEnabled = true
float mapTimeFrac = 0.5 // when the vote is displayed. 0.5 would be halftime
int howManyMapsToPropose = 5

struct MapVotesData{
    string mapName
    string modeName
    int votes
}

global bool mapsHaveBeenProposed = false // dont fuck with this
array<string> maps = []
array<string> modes = [] // Array corresponds with maps array except it is a space separated list of gamemodes for the corresponding map
bool showModes = false // only show gamemodes in the vote menu if they are added to cvars
array<MapVotesData> voteData = []
array<string> proposedMaps = []
array<string> proposedModes = []
string nextMap = ""
string nextMode = ""
array<string> spawnedPlayers= []
global float mapsProposalTimeLeft = 0

// do not remove maps from here, just add the ones you need!
table<string, string> mapNameTable = {
    mp_angel_city = "Angel City",
    mp_black_water_canal = "Black Water Canal",
    mp_coliseum = "Coliseum",
    mp_coliseum_column = "Pillars",
    mp_colony02 = "Colony",
    mp_complex3 = "Complex",
    mp_crashsite3 = "Crashsite",
    mp_drydock = "Drydock",
    mp_eden = "Eden",
    mp_forwardbase_kodai = "Forwardbase Kodai",
    mp_glitch = "Glitch",
    mp_grave = "Boomtown",
    mp_homestead = "Homestead",
    mp_lf_deck = "Deck",
    mp_lf_meadow = "Meadow",
    mp_lf_stacks = "Stacks",
    mp_lf_township = "Township",
    mp_lf_traffic = "Traffic",
    mp_lf_uma = "UMA",
    mp_relic02 = "Relic",
    mp_rise = "Rise",
    mp_thaw = "Exoplanet",
    mp_wargames = "Wargames"
}

table<string, string> modeNameTable = {
    aitdm = "Attrition",
    at = "Bounty Hunt",
    coliseum = "Coliseum",
    cp = "Amped Hardpoint",
    ctf = "Capture the Flag",
    fd_easy = "Frontier Defense (Easy)",
    fd_hard = "Frontier Defense (Hard)",
    fd_insane = "Frontier Defense (Insane)",
    fd_master = "Frontier Defense (Master)",
    fd_normal = "Frontier Defense (Regular)",
    lf = "Live Fire",
    lts = "Last Titan Standing",
    mfd = "Marked For Death",
    ps = "Pilots vs. Pilots",
    solo = "Campaign",
    tdm = "Skirmish",
    ttdm = "Titan Brawl",
    alts = "Aegis Last Titan Standing",
    attdm = "Aegis Titan Brawl",
    ffa = "Free For All",
    fra = "Free Agents",
    holopilot_lf = "The Great Bamboozle",
    rocket_lf = "Rocket Arena",
    turbo_lts = "Turbo Last Titan Standing",
    turbo_ttdm = "Turbo Titan Brawl",
    chamber = "One in the Chamber",
    ctf_comp = "Competitive CTF",
    fastball = "Fastball",
    gg = "Gun Game",
    hs = "Hide and Seek",
    inf = "Infection",
    kr = "Amped Killrace",
    sbox = "Sandbox",
    sns = "Sticks and Stones",
    tffa = "Titan FFA",
    tt = "Titan Tag"
}

void function VoteMapInit(){

    /* We might be in lobby because we are changing gamemodes */
    if (IsLobby()) {
      thread ChangeMapFromLobby_Threaded();
    }

    // add commands here. i added some varieants for accidents, however not for brain damage. do whatever :P
    AddClientCommandCallback("!vote", CommandVote) //!vote force 3 will force the map if your name is in adminNames
    AddClientCommandCallback("!VOTE", CommandVote)
    AddClientCommandCallback("!Vote", CommandVote)

    // ConVar
    voteMapEnabled = GetConVarBool( "pv_vote_map_enabled" )
    string cvar = GetConVarString( "pv_maps" )
    mapTimeFrac = GetConVarFloat( "pv_map_time_frac" )
    howManyMapsToPropose = GetConVarInt( "pv_map_map_propose_amount" )

    // If defined, add additional maps cvar
    // These convars must be defined in mod.json therefore we specify the limits
    for(int i = 2; i <= 9; i++) {
      if (GetConVarString("pv_maps" + i).len() > 0) {
        cvar += "," + GetConVarString("pv_maps" + i);
      }
    }

    array<string> dirtyMaps = split( cvar, "," ) // Get list of unsanitised values from convar pv_maps
    foreach ( string map in dirtyMaps ) {
        array<string> mode = split(strip(map), " ");  // split game modes from map name, strip any leading or trailing spaces

        /* Do not add map if it is current map
            - Unless there is only one map specified
        */
        if (mode[0] != GetMapName() || dirtyMaps.len() == 1) {
          maps.append(mode[0]); // first string in array is map name, add it to list of maps
          mode.remove(0);
          printl(maps.top() + " added to list of maps");

          string modeList = ""; // compile a string of gamemodes
          foreach (string modeString in mode) {
            if (modeString in modeNameTable) {  // check if this is a valid gamemode
              // set to true since we've found at least one map with defined modes
              // If this remains false, we won't show game mode on the vote menu since it'll all be the same mode anyway
              showModes = true;
              modeList += " " + modeString;
            }
            else { // Debug message to check if an attempt to add the gametype was made
              printl("Mode " + modeString + " not found in valid modes");
            }
          }

          if (modeList.len() > 0) printl("- " + modeList);
          else printl("- no gamemodes specified");
          modes.append(strip(modeList));
      }
      else {
        printl(mode[0] + " ignored - is current map");
      }
    }

}

/*
 *  COMMAND LOGIC
 */

void function PlayingMap(){

    wait 2
    if(!IsLobby()){
        while(voteMapEnabled && !mapsHaveBeenProposed){
            wait 10

            /*
            printl(float(GameRules_GetTeamScore(GameScore_GetWinningTeam())))
            printl(float(GetRoundScoreLimit_FromPlaylist()))
            printl(float(GetScoreLimit_FromPlaylist()))
            printl(float(GameRules_GetTeamScore(GameScore_GetWinningTeam())) / float(GetRoundScoreLimit_FromPlaylist()));
            */

            // check if halftime or whatever
            float endTime = expect float(GetServerVar("gameEndTime"))
            if (
                (
                  // Check for time or score if it's not round based
                  (!IsRoundBased() &&
                    (
                      Time() / endTime >= mapTimeFrac
                      || float(GameRules_GetTeamScore(GameScore_GetWinningTeam())) / float(GetScoreLimit_FromPlaylist()) >= mapTimeFrac
                    )
                  )
                  // Check for team score on round based modes
                  || (IsRoundBased() && float(GameRules_GetTeamScore2(GameScore_GetWinningTeam())) / float(GetRoundScoreLimit_FromPlaylist()) >= mapTimeFrac)
                )
                && Time() > 5.0
                && !mapsHaveBeenProposed) {
                FillProposedMaps()
            }
        }
    }
}

bool function CommandVote(entity player, array<string> args){
    if(!IsLobby()){
        printl("USER TRIED VOTING")

        // check if voting is enabled
        if(!voteMapEnabled){
            Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + COMMAND_DISABLED, false)
            return false
        }

        // check if the maps have been proposed
        if(!mapsHaveBeenProposed){
            Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MAPS_NOT_PROPOSED, false)
            return false
        }

        // only !vote -> show maps again
        if(args.len() == 0){
            ShowProposedMaps(player)
            return true
        }

        // map num not a num
        if(args.len() < 1 || !IsInt(args[0])){
            Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MAP_VOTE_USAGE, false)
            return false
        }

        // check if num is valid
        if(!IsMapNumValid(args[0])){
            Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MAP_NUMBER_NOT_FOUND, false)
            return false
        }

        if(args.len() == 2 && args[1] == "force"){
            // Check if user is admin
            if(!IsPlayerAdmin(player)){
                Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MISSING_PRIVILEGES, false)
                return false
            }

            for(int i = 0; i < GetPlayerArray().len(); i++){
                SendHudMessageBuilder(GetPlayerArray()[i], ADMIN_VOTED_MAP, 255, 200, 200)
            }
            SetNextMap(args[0].tointeger(), true)
            return true
        }

        // check if player has already voted
        if(!PlayerHasVoted(player, playerMapVoteNames)){
            // add player to list of players who have voted
            playerMapVoteNames.append(player.GetPlayerName())
        }
        else {
            // Doesnt let the player vote twice, name is saved so even on reconnect they cannot vote twice
            Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + ALREADY_VOTED, false)
            return false
        }
    }

    SendHudMessageBuilder(player, MAP_YOU_VOTED + TryGetNormalizedMapName(proposedMaps[args[0].tointeger()-1]), 200, 200, 200)
    SetNextMap(args[0].tointeger())
    return true
}

void function OnPlayerSpawnedMap(entity player){ // show the player that just joined the map vote
    if(spawnedPlayers.find(player.GetPlayerName()) == -1 && mapsHaveBeenProposed){
        ShowProposedMaps(player)
        spawnedPlayers.append(player.GetPlayerName())
    }
}

void function OnPlayerDisconnectedMap(entity player){
    // remove player from list so on reconnect they get the message again
    while(spawnedPlayers.find(player.GetPlayerName()) != -1){
        try{
            spawnedPlayers.remove(spawnedPlayers.find(player.GetPlayerName()))
        } catch(exception){} // idc abt error handling
    }
}

/*
 *  POST MATCH LOGIC
 */

void function PostmatchMap(){ // change map before the server changes it lololol
    if(!mapsHaveBeenProposed)
        FillProposedMaps()
    thread ChangeMapBeforeServer()
}

void function ChangeMapBeforeServer(){

    if(nextMap == "") { // if nextMap has not been determined, pick a random one
        int randomMapIndex = rndint(maps.len());
        nextMap = maps[randomMapIndex];

        // Check if we're allowing possible change to FFA gamemode if the server is empty
        nextMode = getRandomModeForMap(randomMapIndex);
    }

    // Change immediately if next mode is different team size to current mode to prevent client kick
    if (GetPlayerArray().len() > 0 &&
        (
          GetMaxTeamsForPlaylistName(GameRules_GetGameMode()) != GetMaxTeamsForPlaylistName(nextMode) ||
          GetMaxTeamsForPlaylistName(nextMode) > 2  // Return to lobby required for all FFA modes otherwise players will be assigned teams 2 and 3
        )
      ) {
      // If team size is different, a quick map change to lobby will facilitate clients not being kicked
      ServerCommand("ns_private_match_last_map " + nextMap);
      ServerCommand("ns_private_match_last_mode " + nextMode);
      ServerCommand("ns_private_match_only_host_can_change_settings 1");
      ServerCommand("ns_private_match_countdown_length 0");
      SetConVarInt("pv_last_match_player_count", GetPlayerArray().len());
      SetCurrentPlaylist( "private_match" );
      GameRules_ChangeMap( "mp_lobby", GameRules_GetGameMode() );
    }
    else { // change 1 sec before server does
      if (GetPlayerArray().len()) wait GAME_POSTMATCH_LENGTH - 1;
      SetCurrentPlaylist(nextMode); // Update gamemode for server browser
      GameRules_ChangeMap(nextMap, nextMode);
    }
}

/*
 *  HELPER FUNCTIONS
 */

string function TryGetNormalizedMapName(string mapName){
    try{
        return mapNameTable[mapName]
    }
    catch(e){
        // name not normalized, should be added to list lol (make a pr with the mapname if i missed sumn :P)
        printl(e)
        return mapName
    }
}

string function TryGetNormalizedModeName(string modeName) {
    if (modeName in modeNameTable) return modeNameTable[modeName];
    return modeName;
}

bool function IsMapNumValid(string x){
    int num = x.tointeger()
    if(num <= 0 || num > proposedMaps.len()){
        return false
    }
    return true
}

void function ShowProposedMaps(entity player){
  // create message
  string message = "";
  // Only show instructions if vote has not been cast yet
  if (!PlayerHasVoted(player, playerMapVoteNames)) message += MAP_VOTE_USAGE + "\n";

  for (int i = 1; i <= proposedMaps.len(); i++) {
      string map = TryGetNormalizedMapName(proposedMaps[i-1])
      message += i + ": " + map
      if (showModes) { // Only show game mode if games modes are defined in config
        // Maybe one day we can use GetGameModeDisplayName
        message += " (" + TryGetNormalizedModeName(proposedModes[i-1]) + ")";
      }

      // Show how many votes this map currently has
      int voteDataIndex = FindMvdInVoteData(proposedMaps[i-1]);
      if (voteDataIndex >= 0) {
        if (voteData[voteDataIndex].votes > 0) {
          message += " - " + voteData[voteDataIndex].votes + " vote";
          if (voteData[voteDataIndex].votes > 1) message += "s";  // make plural if more than 1 vote
        }
      }

      message += "\n";
  }

    // message player
    SendHudMessage( player, message, -0.925, 0.4, 255, 255, 255, 255, 0.15, 30, 1 )
}

void function FillProposedMaps(){
    if (mapsHaveBeenProposed) return; // Do not run again if maps have already been proposed
    printl("Proposing maps")
    if(howManyMapsToPropose >= maps.len()){
        printl("\n\n[PLAYERVOTE][ERROR] pv_map_map_propose_amount is not lower than pv_maps! Set it to a lower number than the amount of maps in your map pool!\n\n")
        howManyMapsToPropose = maps.len()-1
    }

    for(int i = 0; i < howManyMapsToPropose; i++){
        while(true){
            // get a random map from maps
            int mapIndex = rndint(maps.len());
            if(proposedMaps.find(maps[mapIndex]) == -1 && maps[mapIndex] != GetMapName()){
                proposedMaps.append(maps[mapIndex])
                proposedModes.append(getRandomModeForMap(mapIndex));  // Get possible game modes for this map
                break
            }
        }
    }

    // message all players
    foreach(entity player in GetPlayerArray()){
        ShowProposedMaps(player)
    }

    Chat_ServerBroadcast("\x1b[38;2;220;220;0m[PlayerVote] \x1b[0mTo vote type !vote number in chat. \x1b[38;2;0;220;220m(Ex. !vote 2)")
    mapsProposalTimeLeft = Time()
    mapsHaveBeenProposed = true
}

/*  Returns a random gamemode as short string for provided map index.
    If user has not configured gamemodes for individual maps, set it to the server's gamemode.
    If that hasn't been set either, default to tdm.
*/
string function getRandomModeForMap(int mapIndex) {
  // Get modes available for this map
  string randomMode = strip(GetConVarString("mp_gamemode")); // By default, set gamemode to what's configured in startup args
  printl(maps[mapIndex]);

  // Populate list of assigned gamemodes
  array<string> modeStrings = split( strip(modes[mapIndex]), " " );
  array<string> randomModes;

  foreach (modeString in modeStrings) {
    randomModes.append(modeString);
    printl("- " + modeString + " available");

    // set to true since we've found at least one map with defined modes
    // If this remains false, we won't show game mode on the vote menu since it'll all be the same mode anyway
    showModes = true;
  }

  if (randomModes.len() > 0) { // If modes have been assigned
    randomMode = randomModes[rndint(randomModes.len())];  // Select one random mode from available modes
  }
  else {
    printl("- no valid gamemodes specified");
  }

  printl("- " + randomMode + " selected");
  return(randomMode);
}

void function SetNextMap(int num, bool force = false){
    int index = FindMvdInVoteData(proposedMaps[num-1])
    MapVotesData temp

    // is already in array
    if(index != -1){
        // increase votes
        temp = voteData[index]
        temp.votes++
    }
    else{ // add to array
        temp.votes = 1
        temp.mapName = proposedMaps[num-1]
        temp.modeName = proposedModes[num-1]
        voteData.append(temp)
    }

    if(force){
        // set to unbeatable value // TODO bad fix but uhhh idc
        temp.votes = 1000
        return
    }

    voteData.sort(MapVotesSort)
    nextMap = voteData[0].mapName
    nextMode = voteData[0].modeName
}

int function FindMvdInVoteData(string mapName){ // returns -1 if not found
    int index = -1
    foreach(MapVotesData mvd in voteData){
        index++
        if(mvd.mapName == mapName) return index
    }
    return -1
}

int function MapVotesSort(MapVotesData data1, MapVotesData data2)
{
  if ( data1.votes == data2.votes )
    return 0
  return data1.votes < data2.votes ? 1 : -1
}

bool function IsInt(string num){
    try {
        num.tointeger()
        return true
    } catch (exception){
        return false
    }
}

/* A gamemode with incompatible switching with previous mode is selected
    We have already returned to lobby so now we are changing to the intended map.
*/
void function ChangeMapFromLobby_Threaded() {

  while (IsLobby()) {
    //printl(Time() + " attempt start lobby");  // DEBUG

    array<entity> players = GetPlayerArray();

    if (players.len() >= GetConVarInt("pv_last_match_player_count") - 2) {  // We do -2 because some players might drop and if not, we don't care if they are on team 2 and 3
      foreach (entity p in players) {
        ClientCommand( p, "PrivateMatchLaunch" );
      }
    }

    WaitFrame();

    // If for some reason we are in lobby and no players are present after some time, change to random map
    if (Time() > 10) ChangeMapBeforeServer();
  }
}

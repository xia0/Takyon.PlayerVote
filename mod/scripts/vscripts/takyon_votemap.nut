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
table<entity, int> playersVote;

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
    speedball = "Live Fire",
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
    hidden = "The Hidden"
}

table<string, string> shortModeNameTable = {
    aitdm = "Attr",
    at = "BH",
    coliseum = "Col",
    cp = "AH",
    speedball = "LF",
    ps = "PVP",
    holopilot_lf = "HOLO",
    rocket_lf = "RA",
    chamber = "1ITC",
    fastball = "FB",
    hs = "H&S",
    inf = "Inf"
}

void function VoteMapInit(){

    /* We might be in lobby because we are changing gamemodes */
    if (IsLobby()) {
      // Fix for special modes
      switch( GetConVarString("ns_private_match_last_mode") ) {
        case "holopilot_lf":
          SetConVarString("ns_private_match_last_mode", "speedball");
          SetPlaylistVarOverride("featured_mode_all_holopilot", "1");
        break;

        case "rocket_lf":
          SetConVarString("ns_private_match_last_mode", "speedball");
          SetPlaylistVarOverride("featured_mode_rocket_arena", "1");
        break;

        default:
        break;
      }

      thread ChangeMapFromLobby_Threaded();
    }

    AddCallback_OnClientDisconnected(OnPlayerDisconnected); // Add a callback to remove client's vote on disconnect

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
            //Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + COMMAND_DISABLED, false)
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
            //Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MAP_VOTE_USAGE, false)
            ShowProposedMaps(player, MAP_VOTE_USAGE);
            return false
        }

        // check if num is valid
        if(!IsMapNumValid(args[0])){
            //Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MAP_NUMBER_NOT_FOUND, false)
            ShowProposedMaps(player, MAP_NUMBER_NOT_FOUND);
            return false
        }

        if(args.len() == 2 && args[1] == "force"){
            // Check if user is admin
            if(!IsPlayerAdmin(player)){
                Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + MISSING_PRIVILEGES, false)
                return false
            }

            /*
            for(int i = 0; i < GetPlayerArray().len(); i++){
                SendHudMessageBuilder(GetPlayerArray()[i], ADMIN_VOTED_MAP, 255, 200, 200)
            }
            */
            SetNextMap(args[0].tointeger(), true)
            return true
        }

        // check if player has already voted
        //if(!PlayerHasVoted(player, playerMapVoteNames)){
        if (!(player in playersVote)) {
            // add player to list of players who have voted
            //playerMapVoteNames.append(player.GetPlayerName())
            playersVote[player] <- args[0].tointeger();
        }
        else {
            // Doesnt let the player vote twice, name is saved so even on reconnect they cannot vote twice
            //Chat_ServerPrivateMessage(player, "\x1b[38;2;220;0;0m" + ALREADY_VOTED, false)
            //ShowProposedMaps(player, ALREADY_VOTED);

            if (playersVote[player] == args[0].tointeger()) return false; // Stop client from voting the same map again

            // Remove player's last vote
            voteData[FindMvdInVoteData(proposedMaps[playersVote[player]-1])].votes--;
            // Update the player's vote
            playersVote[player] = args[0].tointeger();
        }
    }

    //SendHudMessageBuilder(player, MAP_YOU_VOTED + TryGetNormalizedMapName(proposedMaps[args[0].tointeger()-1]), 200, 200, 200)


    SetNextMap(args[0].tointeger())

    // message all players
    foreach(entity player in GetPlayerArray()){
		  EmitSoundOnEntityOnlyToPlayer( player, player, "UI_InGame_FD_ArmoryPurchase" );
      ShowProposedMaps(player)
    }

    return true
}

void function OnPlayerDisconnected(entity player) {
  if (!mapsHaveBeenProposed) return;
  if (player in playersVote) {
    int index = FindMvdInVoteData(proposedMaps[playersVote[player]-1]);
    if (index >= 0) voteData[index].votes--;
  }
  foreach(entity p in GetPlayerArray()){
    //EmitSoundOnEntityOnlyToPlayer( player, player, "UI_InGame_FD_ArmoryPurchase" );
    ShowProposedMaps(p)
  }
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
        int randomMapIndex = RandomInt(maps.len());
        nextMap = maps[randomMapIndex];

        // Check if we're allowing possible change to FFA gamemode if the server is empty
        nextMode = getRandomModeForMap(randomMapIndex);
    }

    /*
    if (["alts", "attdm", "tffa", "ttdm", "lts", "speedball", "lf", "holopilot_lf", "rocket_lf", "fastball"].find(nextMode) >= 0) {
      ServerCommand("setplaylistvaroverrides classic_mp 1");
    }
    */
    ServerCommand("setplaylistvaroverrides featured_mode_all_holopilot 0");
    ServerCommand("setplaylistvaroverrides featured_mode_rocket_arena 0");

    // Change immediately if next mode is different team size to current mode to prevent client kick
    if (
        GetMaxTeamsForPlaylistName(GameRules_GetGameMode()) != GetMaxTeamsForPlaylistName(nextMode)
        || GetMaxTeamsForPlaylistName(nextMode) > 2  // Return to lobby required for all FFA modes otherwise players will be assigned teams 2 and 3
        || nextMode == "holopilot_lf"
        || nextMode == "rocket_lf"
      ) {
      // If team size is different, a quick map change to lobby will facilitate clients not being kicked
      //ServerCommand("ns_private_match_last_map " + nextMap);
      //ServerCommand("ns_private_match_last_mode " + nextMode);
      //ServerCommand("ns_private_match_only_host_can_change_settings 1");
      //ServerCommand("ns_private_match_countdown_length 0");
      SetConVarString("ns_private_match_last_map", nextMap);
      SetConVarString("ns_private_match_last_mode", nextMode);
      SetConVarBool("ns_private_match_only_host_can_change_settings", true);
      SetConVarBool("ns_private_match_only_host_can_start", false);
      SetConVarFloat("ns_private_match_countdown_length", 0);
      SetConVarInt("pv_last_match_player_count", GetPlayerArray().len());
      SetCurrentPlaylist( "private_match" );
      GameRules_ChangeMap( "mp_lobby", GameRules_GetGameMode() );
    }
    else { // change 1 sec before server does
      if (GetPlayerArray().len() > 0) wait GAME_POSTMATCH_LENGTH - 1;

      if (nextMode == "speedball") SetCurrentPlaylist("lf");  // Make exception for lf
      else SetCurrentPlaylist(nextMode); // Update gamemode for server browser

      GameRules_ChangeMap(nextMap, nextMode);
    }
}

/* A gamemode with incompatible switching with previous mode is selected
    We have already returned to lobby so now we are changing to the intended map.
*/
void function ChangeMapFromLobby_Threaded() {
  while (IsLobby()) {
    // Wait until most players have loaded into the lobby
    // We do this to let the lobby organise players into FFA teams
    array<entity> players = GetPlayerArray();
    if (players.len() > 0 && players.len() >= GetConVarInt("pv_last_match_player_count")) { // -2?
      /*
      players.reverse();
      foreach (entity p in players) {
        ClientCommand( p, "PrivateMatchLaunch" );
      }
      */
      wait 1;
      //SetConVarBool( "ns_private_match_only_host_can_start", false )
      ClientCommand( GetPlayerArray().top(), "PrivateMatchLaunch" );
      //SetConVarBool( "ns_private_match_only_host_can_start", true )
      //wait (GetConVarFloat("ns_private_match_countdown_length") + 0.5);
    }

    // Start the next map if nobody is around to push start
    if (Time() > 10) {
      if (GetConVarString("ns_private_match_last_map") != "" && GetConVarString("ns_private_match_last_mode") != "") {
        if (GetConVarString("ns_private_match_last_mode") == "speedball") SetCurrentPlaylist("lf");
        else SetCurrentPlaylist(GetConVarString("ns_private_match_last_mode"));
        GameRules_ChangeMap(GetConVarString("ns_private_match_last_map"), GetConVarString("ns_private_match_last_mode"));
      }
      else ChangeMapBeforeServer();
    }

    WaitFrame();
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

string function TryGetNormalizedModeName(string modeName, bool short = false) {
  if (short) {
    if (modeName in shortModeNameTable) return shortModeNameTable[modeName];
    else return modeName.toupper();
  }

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

void function ShowProposedMaps(entity player, string errorMsg = ""){
  /*
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
    SendHudMessage( player, message, -0.925, 0.4, 240, 182, 27, 255, 0.15, 30, 1 )
  */


  if (!mapsHaveBeenProposed) return;
  string message;

  for (int i = 1; i <= proposedMaps.len(); i++) {

    if (message.len() > 0) {
      if ((i - 1) % 2 == 0) message += " \n"; // Put maps on a new line if map before exceeded this number
      else message += "  ·  "; // Otherwise, draw a divider between the maps
    }

    message += "⁽" + sup(i) + "⁾ " + TryGetNormalizedModeName(proposedModes[i-1], true) + " " + TryGetNormalizedMapName(proposedMaps[i-1])

    // Show how many votes this map currently has
    int voteDataIndex = FindMvdInVoteData(proposedMaps[i-1]);
    if (voteDataIndex >= 0) message += " " + sup(voteData[voteDataIndex].votes, true);
    else message += " " + sup(0, true);


  }

  // Show prompt if user has not yet voted
  if (errorMsg.len() > 0) message = errorMsg + " \n" + message;
  if (!(player in playersVote)) message = "Vote in chat \n" + message;
  SendHudMessage( player, message + " ", 1, 1, 240, 182, 27, 255, 0, 180, 120);
}

void function FillProposedMaps(){
    if (mapsHaveBeenProposed) return; // Do not run again if maps have already been proposed
    printl("Proposing maps")
    if(howManyMapsToPropose > maps.len()){
        printl("\n\n[playersVote][ERROR] pv_map_map_propose_amount is not lower than pv_maps! Set it to a lower number than the amount of maps in your map pool!\n\n")
        howManyMapsToPropose = maps.len()-1
    }

    for(int i = 0; i < howManyMapsToPropose; i++){
        while(true){
            // get a random map from maps
            int mapIndex = RandomInt(maps.len());
            if(proposedMaps.find(maps[mapIndex]) == -1 && maps[mapIndex] != GetMapName()){
                proposedMaps.append(maps[mapIndex])
                proposedModes.append(getRandomModeForMap(mapIndex));  // Get possible game modes for this map
                break
            }
        }
    }

    //Chat_ServerBroadcast("\x1b[38;2;220;220;0m[playersVote] \x1b[0mTo vote type !vote number in chat. \x1b[38;2;0;220;220m(Ex. !vote 2)")
    mapsProposalTimeLeft = Time()
    mapsHaveBeenProposed = true

    // message all players
    foreach(entity player in GetPlayerArray()){
        ShowProposedMaps(player)
        EmitSoundOnEntityOnlyToPlayer( player, player, "DataKnife_Hack_Spectre_Pt3" );
    }
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
    //randomMode = randomModes[RandomIntRange(0, randomModes.len())];  // Select one random mode from available modes
    randomMode = randomModes.getrandom();
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



/* Converts a string to superscript or subscript unicode
    Supports numbers 0-9 and parentheses
*/
string function sup(int input, bool sub = false) {
  // ⁰¹²³⁴⁵⁶⁷⁸⁹⁽⁾₀₁₂₃₄₅₆₇₈₉₍₎
  array<string> charSet;
  if (sub) charSet = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"];
  else charSet = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"];

  string output;
  array<string> inputArray = SplitStringToChars(input.tostring());
  foreach (string c in inputArray) output += charSet[c.tointeger()];
  return output;
}

/* Take a string and return an array of characters
		Returns an array of strings containing 1 character each
*/
array<string> function SplitStringToChars(string input) {
	array<string> characters = [];
	for (int i = 0; i < input.len(); i++) {
		characters.append(input.slice(i, i+1));
	}
	return characters;
}

/* Returns a string with dots (colon, full stop) according to provided int
*/
string function IntToDots(int num, bool leftToRight = true) {
  string output;
  for (int i = 0; i < num; i += 2) {
    output += ":";
  }
  if (num % 2 != 0) {
    if (leftToRight) output += ".";
    else output = "." + output;
  }
  return output;
}

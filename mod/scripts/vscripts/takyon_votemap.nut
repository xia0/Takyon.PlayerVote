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

/*  An array of strings for modes defined as ffa
    We will use these to ensure we don't change gamemode from an FFA mode to a non-FFA mode and vice-versa
*/
array<string> FFAModes = [
  "coliseum",
  "ffa",
  "fra",
  "gg",
  "tffa",
  "sns"
];

void function VoteMapInit(){
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
    for(int i = 2; i <= 3; i++) {
      if (GetConVarString("pv_maps" + i).len() > 0) {
        cvar += "," + GetConVarString("pv_maps" + i);
      }
    }

    array<string> dirtyMaps = split( cvar, "," ) // Get list of unsanitised values from convar pv_maps
    foreach ( string map in dirtyMaps ) {
        array<string> mode = split(strip(map), " ");  // split game modes from map name, strip any leading or trailing spaces
        maps.append(mode[0]); // first string in array is map name, add it to list of maps
        mode.remove(0);
        printl(maps.top() + " added to list of maps");

        string modeList = ""; // compile a string of gamemodes
        foreach (string modeString in mode) {
          if (modeString in modeNameTable) {  // check if this is a valid gamemode

            // Do not allow switching to FFA from non-FFA and vice-versa
            if ((IsFFAGame() && FFAModes.find(modeString) >= 0) ||
              (!IsFFAGame() && FFAModes.find(modeString) < 0)) {
              modeList += " " + modeString;
              printl("- " + modeString + " gamemode added");

              // set to true since we've found at least one map with defined modes
              // If this remains false, we won't show game mode on the vote menu since it'll all be the same mode anyway
              showModes = true;
            }
            else { // Debug message if the map was not added due to incorrect FFA type
              printl("- " + modeString + " ignored due to wrong FFA type");
            }

          }
          else { // Debug message to check if an attempt to add the gametype was made
            printl("Mode " + modeString + " not found in valid modes");
          }
        }
        modes.append(strip(modeList));
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
            // check if halftime or whatever
            float endTime = expect float(GetServerVar("gameEndTime"))
            if(Time() / endTime >= mapTimeFrac && Time() > 5.0 && !mapsHaveBeenProposed){
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
            SendHudMessageBuilder(player, COMMAND_DISABLED, 255, 200, 200)
            return false
        }

        // check if the maps have been proposed
        if(!mapsHaveBeenProposed){
            SendHudMessageBuilder(player, MAPS_NOT_PROPOSED, 255, 200, 200)
            return false
        }

        // only !vote -> show maps again
        if(args.len() == 0){
            ShowProposedMaps(player)
            return true
        }

        // map num not a num
        if(args.len() < 1 || !IsInt(args[0])){
            SendHudMessageBuilder(player, MAP_VOTE_USAGE, 255, 200, 200)
            return false
        }

        // check if num is valid
        if(!IsMapNumValid(args[0])){
            SendHudMessageBuilder(player, MAP_NUMBER_NOT_FOUND, 255, 200, 200)
            return false
        }

        if(args.len() == 2 && args[1] == "force"){
            // Check if user is admin
            if(!IsPlayerAdmin(player)){
                SendHudMessageBuilder(player, MISSING_PRIVILEGES, 255, 200, 200)
                return false
            }

            for(int i = 0; i < GetPlayerArray().len(); i++){
                SendHudMessageBuilder(GetPlayerArray()[i], ADMIN_VOTED_MAP, 255, 200, 200)
            }
            SetNextMap(args[1].tointeger(), true)
            return true
        }

        // check if player has already voted
        if(!PlayerHasVoted(player, playerMapVoteNames)){
            // add player to list of players who have voted
            playerMapVoteNames.append(player.GetPlayerName())
        }
        else {
            // Doesnt let the player vote twice, name is saved so even on reconnect they cannot vote twice
            //SendHudMessageBuilder(player, ALREADY_VOTED, 255, 200, 200)
            ShowProposedMaps(player);
            return false
        }
    }

    //SendHudMessageBuilder(player, MAP_YOU_VOTED + TryGetNormalizedMapName(proposedMaps[args[0].tointeger()-1]), 200, 200, 200)
    SetNextMap(args[0].tointeger())
    // Show current tally to each player
    foreach(entity tally_player in GetPlayerArray()){
        ShowProposedMaps(tally_player)
    }
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
    wait GAME_POSTMATCH_LENGTH - 1 // change 1 sec before server does

    if(nextMap == "") { // if nextMap has not been determined, pick a random one
        int randomMapIndex = rndint(maps.len());
        nextMap = maps[randomMapIndex];
        nextMode = getRandomModeForMap(randomMapIndex);
    }

    ServerCommand("setplaylist " + nextMode); // Update gamemode for server browser
    GameRules_ChangeMap(nextMap, nextMode);
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
    else message += VOTED + "\n";

    for (int i = 1; i <= proposedMaps.len(); i++) {
        string map = TryGetNormalizedMapName(proposedMaps[i-1])
        message += i + ": " + map
        if (showModes) { // Only show game mode if games modes are defined in config
          message += " (" + TryGetNormalizedModeName(proposedModes[i-1]) + ")";
        }

        // Get how many votes this map currently has
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
    SendHudMessage( player, message, -0.925, 0.4, 255, 255, 255, 255, 0, 30, 1 )
}

void function FillProposedMaps(){
    printl("Proposing maps")
    if(howManyMapsToPropose >= maps.len()){
        printl("\n\n[PLAYERVOTE][ERROR] pv_map_map_propose_amount is not lower than pv_maps! Set it to a lower number than the amount of maps in your map pool!\n\n")
        howManyMapsToPropose = maps.len()-1
    }

    string currMap = GetMapName()
    for(int i = 0; i < howManyMapsToPropose; i++){
        while(true){
            // get a random map from maps
            int mapIndex = rndint(maps.len());
            string temp = maps[mapIndex]
            if(proposedMaps.find(temp) == -1 && temp != currMap){
                proposedMaps.append(temp)
                proposedModes.append(getRandomModeForMap(mapIndex));  // Get possible game modes for this map
                break
            }
        }
    }

    // message all players
    foreach(entity player in GetPlayerArray()){
        ShowProposedMaps(player)
    }

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

  // Populate list of assigned gamemodes
  array<string> randomModes = split( strip(modes[mapIndex]), " " );

  if (randomModes.len() > 0) { // If modes have been assigned
    printl(maps[mapIndex] + " available modes are " + modes[mapIndex]);
    randomMode = randomModes[rndint(randomModes.len())];  // Select one random mode from available modes
  }
  else {
    printl(maps[mapIndex] + " no gamemodes specified");
  }

  // Set to safe option if still undefined
  if (randomMode.len() == 0) {
    if (IsFFAGame()) randomMode = "ffa";
    else randomMode = "tdm";
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

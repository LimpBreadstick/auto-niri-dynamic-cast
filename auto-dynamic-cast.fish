#!/usr/bin/env fish

# This script will not work if it is run anywhere it does not have a $SteamAppId variable set by Steam to read from. It relies on that variable to know which game it should be looking for.
# If it does not have access to that variable when it is run, it will break (or more accurately immediately close itself to avoid inevitable breakage)

if test -n "$SteamAppId" -a "$SteamAppId" -ge 0
    echo "Auto Dynamic Cast: SteamAppId detected successfully as '$SteamAppId'"
else
    echo "Auto Dynamic Cast: SteamAppId variable could not be found, exiting..." >&2
    exit 1
end

if test -n "$STEAM_COMPAT_INSTALL_PATH"
    echo "Auto Dynamic Cast: Install path detected successfully as '$STEAM_COMPAT_INSTALL_PATH'"
else
    echo "Auto Dynamic Cast: Install path could not be found, exiting..." >&2
    exit 1
end

if test -r "$STEAM_COMPAT_INSTALL_PATH/../../appmanifest_$SteamAppId.acf"
    set -g Steam_Game_Title $(awk -F '"' '$2=="name" {print $4; exit}' $STEAM_COMPAT_INSTALL_PATH/../../appmanifest_$SteamAppId.acf) # Grabs the game's title from Steam's app manifest
    echo "Auto Dynamic Cast: Game title detected successfully as \"$Steam_Game_Title\""
else
    set -g Steam_Game_Title ""
    echo "Auto Dynamic Cast: No manifest found at '$HOME/.local/share/Steam/steamapps/appmanifest_$SteamAppId.acf', game title left empty" >&2
end

notify-send -u low -a "Auto Dynamic Cast" "Attempting Cast Start" "Looking for the $Steam_Game_Title window"

set -l Json_Overrides_Path "$(status dirname)/overrides.json" 
if test -e "$Json_Overrides_Path"
    if test -r "$Json_Overrides_Path"
	set -g Json_Overrides "$(cat $Json_Overrides_Path)"
	echo "Auto Dynamic Cast: JSON Overrides located successfully at '$Json_Overrides_Path'"
    else
	set -g Json_Overrides "{}"
	echo "Auto Dynamic Cast: File at '$Json_Overrides_Path' exists but is not readable, switching to empty fallback" >&2
    end
else
    echo "Auto Dynamic Cast: JSON Overrides file not found, attempting creation of default file" >&2
    mkdir -p $(dirname $Json_Overrides_Path) 
    printf "{\n    \"ID_<SteamAppId>\": \"<Niri app_id>\",\n    \"TITLE_<SteamAppId>\": \"<Niri title>\"\n}" > $Json_Overrides_Path
    # Default file is currently a hardcoded template, will be changed to reference a default file from github at a later date
    if test -r "$Json_Overrides_Path"
	set -g Json_Overrides "$(cat $Json_Overrides_Path)"
	echo "Auto Dynamic Cast: Successfully created default file at '$Json_Overrides_Path'"
    else
	set -g Json_Overrides "{}"
	echo "Auto Dynamic Cast: Failed to create default file at '$Json_Overrides_Path', switching to empty fallback" >&2
    end
end

if jq -e -n --argjson json "$Json_Overrides" '$json | ((type == "object") and (all(.[]; type == "string")))' > /dev/null 2>&1
    echo "Auto Dynamic Cast: JSON Overrides successfully validated"
else
    set -g Json_Overrides "{}"
    echo "Auto Dynamic Cast: JSON Overrides validation failed, switching to empty fallback" >&2
end

set -g Iteration 1
set -g Checks_Left 20 # Number of attempts that will be made before giving up. Change this if a game takes longer to open.
set -g Interval 1 # Time in seconds between attempts. Change this if more/less frequent polling is needed. Changes to this number will likely require changes to everywhere "Checks_Left" gets set
while true
    set Target_Info $(niri msg -j windows | jq -r --arg desired_title "$Steam_Game_Title" --arg game_app_id "steamapp$SteamAppId" --arg steamappid "$SteamAppId" --argjson override "$Json_Overrides" '. 
    | ($desired_title | ascii_downcase | gsub("_"; " ") | gsub("[^a-z0-9 ]"; "") | trim | gsub(" +"; " ")) as $cleaned_desired_title
    | ($override["ID_" + $steamappid] // "") as $override_id
    | ($override["TITLE_" + $steamappid] // "") as $override_title
    | .[]
    | ((.app_id // "") | (ascii_downcase | gsub("[^a-z0-9]"; ""))) as $cleaned_app_id 
    | ((.title // "") | (ascii_downcase | gsub("_"; " ") | gsub("[^a-z0-9 ]"; "") | trim | gsub(" +"; " "))) as $cleaned_title
    | select((($cleaned_app_id == $game_app_id) and ($cleaned_title == "" | not)) or 
    (($cleaned_title == $cleaned_desired_title) and ($cleaned_title | split(" ") | map(select(length >= 4)) as $words | any($words[]; . as $word | $cleaned_app_id | contains($word)))) or 
    (select(((.app_id == $override_id) and (.title == $override_title)) and ((.app_id == "") and (.title == "") | not))))
    | [.id, .title, .app_id] | @tsv' | head -n 1 | string split \t) # Horrible fucked up json parsing expression. Prepare to lose your sanity if you have to change this for any reason.

    set Target_Id $Target_Info[1]
    set Target_Title $Target_Info[2]
    set Target_App_Id $Target_Info[3]

    # In an attempt to document what it's actually doing: It takes a JSON list of window info from Niri, the game's internal steam ID, and its listed title from Steam's app manifest as inputs
    # It then cleans up all of that input, making each thing lowercase and free of special characters. Each Niri app id is stripped of spaces or underscores into one continuous string
    # The game's steam ID gets used to check if the Niri app id matches the form of steam_app_<ID>, with the actual correct ID for the current game
    # If the steam_app_<ID> check matches, with a nonempty title (to avoid an edge case), that window is considered a valid target.
    # This catches pretty much all Steam games run through Proton
    #
    # Each manifest title gets split into individual words, discarding ones too short to avoid false positives (e.g. "the")
    # Words here being delineated by spaces. Underscores are replaced by spaces, and counted as such. Repeat spaces are deleted
    # Each Niri title is checked against each manifest title. If they match, they are passed on to another check to avoid yet another edge case
    # This edge case being applications that change their Niri title based on the activity in said application, such as most browsers or file managers
    # So then each word (of at least 4 characters) from the Niri title is checked against the Niri app id. So long as at least one word is contained in the app id, that window is considered a valid target.
    # This is the most unreliable of the checks, but it helps catch many native Linux games that don't rely on Proton.
    #
    # Last but not least is the manual override. This looks up Niri app id and title pairs in a manually curated JSON file based on the game's steam id, exact matches are considered a valid target
    # This should work for any Steam game, however there could possibly be an edge case where it might fail if another app matches both the app_id and title of the game within Niri  
    #
    # Then finally the Niri window id, title, and app id of any matching window are read from Niri's window list and saved to the $Target_Info variable

    if test -n "$Target_Id"
	if test -n "$Old_Target"
	    if test "$Target_Id" != "$Old_Target" # Only updates if the game window changes its id, to minimize overriding user input
		niri msg action set-dynamic-cast-window --id $Target_Id
		set Checks_Left 10 # Number of checks to perform after a game window changes its id. Increase this number if consecutive changes are not getting caught
		echo "Auto Dynamic Cast: Target updated from window id $Old_Target to window id $Target_Id on iteration $Iteration. Checking $Checks_Left more times for further target changes"
	    else
		if test "$Checks_Left" -gt 0
		    set Checks_Left (math $Checks_Left -1)
		    echo "Auto Dynamic Cast: Target same as previous, no changes applied on iteration $Iteration. Checking $Checks_Left more times for target changes"
		else
		    notify-send -a "Auto Dynamic Cast" "Cast Success" "Now casting: $Target_Title"
		    echo "Auto Dynamic Cast: Target stable with title '$Target_Title', app id '$Target_App_Id', and window id '$Target_Id'"
		    exit 0
		end
	    end
	else
	    niri msg action set-dynamic-cast-window --id $Target_Id # Initialize the screencast the first time a valid id appears
	    set Checks_Left 10 # Number of checks to perform after first valid window is found
	    notify-send -u low -a "Auto Dynamic Cast" "Cast Started" "Started casting $Target_Title, waiting to see if target changes"
	    echo "Auto Dynamic Cast: Target initialized to $Target_Title with window id $Target_Id on iteration $Iteration. Checking $Checks_Left more times for target changes"
	end
    else
	if test -n "$Old_Target"
	    set Checks_Left 10 # Number of checks to perform after a valid target disappears
	    echo "Auto Dynamic Cast: Target with window id $Old_Target disappeared, checking $Checks_Left more times in case it reappears"
	else
	    set Checks_Left (math $Checks_Left -1)
	    echo "Auto Dynamic Cast: No valid target found on iteration $Iteration. Attempting to find target $Checks_Left more times"
	end
    end
    if test "$Checks_Left" -le 0 -a -z "$Target_Id"
	notify-send -u critical -a "Auto Dynamic Cast" "Cast Failure" "Unable to find $Steam_Game_Title window"
	echo "Auto Dynamic Cast: Target not found after $Iteration iterations, exiting..." >&2
	exit 1
    end
    if test (math $Iteration x $Interval) -ge 60
	notify-send -u critical -a "Auto Dynamic Cast" "Cast Failure" "$Steam_Game_Title window not found after $(math $Iteration x $Interval) seconds"
	echo "Auto Dynamic Cast: Maximum time limit of $(math $Iteration x $Interval) seconds elapsed, exiting..." >&2
	exit 1
    end
    set Iteration (math $Iteration +1)
    set -g Old_Target $Target_Id
    sleep $Interval
end



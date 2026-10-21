#!/usr/bin/env fish

# This script will not work if it is run anywhere it does not have a $SteamAppId variable set by Steam to read from. It relies on that variable to know which game it should be looking for.
# If it does not have access to that variable when it is run, it will break (or more accurately immediately close itself to avoid inevitable breakage)

if not test -n "$SteamAppId"
    echo "Auto Dynamic Cast: \$SteamAppId variable could not be found, exiting..."
    break
end

set Steam_Game_Title $(awk -F '"' '$2=="name" {print $4}' $HOME/.local/share/Steam/steamapps/appmanifest_$SteamAppId.acf) # Grabs the game's title from Steam's app manifest
echo "Auto Dynamic Cast: Game title detected as \"$Steam_Game_Title\""
set -l Json_Overrides_Path "$HOME/Projects/dynamic-cast-overrides.json" # Change file path as needed
if test -e "$Json_Overrides_Path"
    echo "Auto Dynamic Cast: JSON Overrides located successfully at $Json_Overrides_Path, proceeding"
else
    mkdir -p $(dirname $Json_Overrides_Path); printf "{\n    \"ID_<SteamAppId>\": \"<cleaned Niri app_id, no spaces>\"\n    \"TITLE_<SteamAppId>\": \"<cleaned Niri title, with spaces>\"\n}" > $Json_Overrides_Path
    echo "Auto Dynamic Cast: JSON Overrides file not found, created new file at $Json_Overrides_Path"
set -l Repeats 0
while true
    set Cast_Target $(niri msg -j windows | jq --arg desired_title "$Steam_Game_Title" --arg game_app_id "steamapp$SteamAppId" --arg steamappid "$SteamAppId" --argjson override "$(cat $Json_Overrides_Path)" '. 
    | ($desired_title | ascii_downcase | gsub("_"; " ") | gsub("[^a-z0-9 ]"; "") | trim | gsub(" +"; " ")) as $cleaned_title 
    | (.[] |= (.app_id |= (ascii_downcase | gsub("[^a-z0-9]"; "")) 
    | .title |= (ascii_downcase | gsub("_"; " ") | gsub("[^a-z0-9 ]"; "") | trim | gsub(" +"; " "))
    | select(((.app_id == $game_app_id) and (.title == "" | not)) or ((.title == $cleaned_title) and 
    (.app_id as $app_id | .title | split(" ") | map(select(length >= 4)) as $words | any($words[]; . as $word | $app_id | contains($word)))) or 
    (select((.app_id == $override["ID_" + $steamappid]) and (.title == $override["TITLE_" + $steamappid]))))))
    | .[] | .id') # Horrible fucked up json parsing expression. Prepare to lose your sanity if you have to change this for any reason.

    # In an attempt to document what it's actually doing: It takes a JSON list of window info from Niri, the game's internal steam ID, and its listed title from Steam's app manifest as inputs
    # It then cleans up all of that input, making each thing lowercase and free of special characters. Each Niri app id is stripped of spaces or underscores into one continuous string
    # The game's steam ID gets used to check if the Niri app id matches the form of steam_app_<ID>, with the actual correct ID for the current game
    # If the steam_app_<ID> check matches, with a nonempty title (to avoid an edge case), that window is considered a valid target.
    #
    # Each manifest title gets split into individual words, discarding ones too short to avoid false positives (e.g. "the")
    # Words here being delineated by spaces. Underscores are replaced by spaces, and counted as such. Repeat spaces are deleted
    # Each Niri title is checked against each manifest title. If they match, they are passed on to another check to avoid yet another edge case
    # This edge case being applications that change their Niri title based on theecho "" > /path/to/directory/filename.txt activity in said application, such as most browsers or file managers
    # So then each word (of at least 4 characters) from the Niri title is checked against the Niri app id. So long as at least one word is contained in the app id, that window is considered a valid target.
    # This is the most unreliable of the checks, but it helps catch many native Linux games that don't rely on Proton.
    #
    # Last but not least is the manual override. This looks up Niri app id and title pairs in a manually curated JSON file based on the game's steam id, exact matches are considered a valid target
    # Currently the unprocessed JSON data is compared against the already-sanitized app id and title data, so any entries there will need to be sanitized by hand to match properly
    # In the future this should probably be changed so the parser also sanitizes the manual overrides the same way, so that the raw data from Niri can simply be pasted in and expected to work
    # But that will require making the already complicated jq expression even longer and more complex, so that won't be happening for the moment
    #
    # Then finally the Niri window id (not to be confused with app_id) of any matching window is read from Niri's window list and saved as the $Cast_Target variable

    if test -n "$Cast_Target"
	if test -n "$Old_Target"
	    if test "$Cast_Target" != "$Old_Target" # Only updates if the game window changes its id, to minimize overriding user input
		niri msg action set-dynamic-cast-window --id $Cast_Target
		echo "Auto Dynamic Cast: Target updated from window id $Old_Target to window id $Cast_Target on iteration $Repeats"
	    else
		echo "Auto Dynamic Cast: Target same as previous, no changes applied on iteration $Repeats"
	    end
	else
	    niri msg action set-dynamic-cast-window --id $Cast_Target # Initialize the screencast the first time a valid id appears
	    echo "Auto Dynamic Cast: Target initialized to window id $Cast_Target on iteration $Repeats"
	end
    else
	echo "Auto Dynamic Cast: No valid target found on iteration $Repeats"
    end
    if test "$Repeats" -ge 20 # Timeout after a reasonable period. If a game takes longer to open, increase this number 
	echo "Auto Dynamic Cast: Exiting — limit of $Repeats iterations reached." >&2
	break
    end
    set Repeats (math $Repeats +1)
    set Old_Target $Cast_Target
    sleep 1
end



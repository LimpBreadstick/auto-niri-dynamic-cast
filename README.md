This project has some very specific goals, so it may not be what you need/want (especially in its early state).
In approximate order of importance, here is what this is attempting to accomplish (decided entirely by my whims atm): 

1. Only run for a short time when the game starts. No constant background checks eating up performance, even if it's small.
2. Work as often/reliably as possible, and be clear when it's not working and why. Nobody likes finding out after the fact that their recording was actually a black screen the whole time cause it didn't target the right source
3. Require as little per-game tweaking as physically possible. Running as a launch option is a significant compromise on that front for the sake of 1 and 2
4. Be easy to tweak when it is actually necessary. This still needs lots of work, but I will try to get around to improving this
5. Remain something within the realm of comprehension for a beginner like me who's taken like... one coding class ever.

Realistically those goals probably won't ever all be fully accomplished to my satisfaction, but who cares I'm gonna try anyway

As for how to actually use it, just plop `/path/to/auto-dynamic-screencast.sh & %command%` in your steam launch options for each game, and it *should* just work. If it doesn't, feel free to yell at me until I fix it. Any other launch options you have should go in between the `&` and the `%command%` and they'll work as normal
